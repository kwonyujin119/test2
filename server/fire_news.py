# -*- coding: utf-8 -*-
"""소방 관련 뉴스 5개 고르기 (Google 뉴스 RSS, 표준 라이브러리만).
기준: 한국 시간 전날 18:00 ~ 당일 07:00 사이에 나온 기사 중 '가장 많이 다뤄진 사건' 순(주요 언론사 수 ×3 + 그 밖 언론사 수 ×1 + 기사 수 ×0.3 + 사고·인명 기사 +3, 해외 사건 −6, 행사·홍보성 기사 −4, 인천 관련 +100 = 무조건 최우선).
  - '소방' '소방관' '화재' 세 검색어의 RSS 를 합치고 창(window) 안의 기사만 남긴다
  - 제목 단어가 2개 이상(또는 1/4 이상) 겹치는 기사를 같은 사건으로 묶고, 보도한 언론사 수가 많은 묶음을 위로
  - 묶음마다 대표 기사 1개(주요 언론사 우선, 없으면 가장 최근)만 넣어 5개
사용: python3 server/fire_news.py [--date YYYY-MM-DD] [--json]   (날짜는 한국 시간 '당일', 기본 오늘)
로컬 서버도 같은 함수를 쓴다(fetch_fire_news). 인터넷이 안 되면 빈 목록."""
import argparse, datetime, html, json, re, sys, time, urllib.parse, urllib.request, xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime

KST = datetime.timezone(datetime.timedelta(hours=9))
QUERIES = ['소방', '소방관', '화재', '소방서 구조', '인천 소방']
INCHEON = ['인천', '부평', '계양', '미추홀', '연수구', '남동구', '송도', '영종', '청라', '검단', '강화군', '강화도', '옹진', '인천공항', '인천항']   # 인천 관련은 최우선
MAJOR = ['연합뉴스', 'KBS', 'MBC', 'SBS', 'YTN', 'JTBC', '조선일보', '중앙일보', '동아일보', '한겨레', '경향신문', '뉴시스', '뉴스1', '한국일보', '서울신문', '국민일보', '세계일보', '문화일보', '매일경제', '한국경제', '연합뉴스TV', 'MBN', 'TV조선', '채널A']
FOREIGN = ['홍콩', '중국', '일본', '미국', '대만', '영국', '프랑스', '독일', '러시아', '우크라이나', '인도', '호주', '캐나다', '유럽', '해외', '베트남', '태국', '필리핀', '인도네시아', '이스라엘', '이란', '터키', '튀르키예', '브라질', '멕시코', '뉴욕', '도쿄', 'LA', '파리', '런던']
PR = ['개최', '성황리', '훈련', '캠페인', '협약', 'MOU', '홍보', '간담회', '위촉', '수여', '표창', '방문', '시상', '발대식', '점검 실시', '교육 실시', '행사', '기념', '업무협약', '워크숍', '세미나', '봉사']   # 보도자료성 기사는 뒤로
INCIDENT = ['화재', '불', '사망', '숨져', '순직', '부상', '구조', '대피', '폭발', '붕괴', '사고', '진화', '전소', '화상', '참사', '이송', '인명']
STOP = set('소방 소방관 소방서 소방청 소방본부 화재 불 발생 관련 오늘 내일 어제 속보 단독 영상 사진 종합 기자 뉴스 등 및 의 는 을 를 이 가 에 서 로 도 한 명 중 명이 명을 명의 인명피해 없어 없음 만에 추정 원인 조사 당국 경찰 긴급 현장 오전 오후 새벽 밤 시간'.split())
SYN = [('다쳤', '부상'), ('다쳐', '부상'), ('숨졌', '사망'), ('숨져', '사망'), ('숨진', '사망'), ('불길', '진화'), ('진압', '진화')]   # 같은 뜻 다른 표현

def window(day):
    """(시작, 끝) = 전날 18:00 KST ~ 당일 07:00 KST"""
    d = datetime.datetime(day.year, day.month, day.day, tzinfo=KST)
    return d - datetime.timedelta(hours=6), d + datetime.timedelta(hours=7)

def fetch_rss(q, timeout=12):
    url = 'https://news.google.com/rss/search?q=' + urllib.parse.quote(q) + '&hl=ko&gl=KR&ceid=KR:ko'
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36', 'Accept': 'application/rss+xml, application/xml;q=0.9, */*;q=0.8', 'Accept-Language': 'ko-KR,ko;q=0.9'})
    last = None
    for attempt in range(3):   # 일시 오류·속도 제한이면 잠깐 쉬고 다시
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                body = r.read()
            if b'<rss' not in body[:2000] and b'<feed' not in body[:2000]: raise ValueError('RSS 가 아닌 응답(%d bytes)' % len(body))
            return body
        except Exception as e:
            last = e; time.sleep(2 + attempt * 3)
    raise last

def parse_rss(xml_bytes):
    out = []
    root = ET.fromstring(xml_bytes)
    for it in root.iter('item'):
        title = (it.findtext('title') or '').strip(); link = (it.findtext('link') or '').strip(); pub = it.findtext('pubDate') or ''
        src = it.find('source'); press = (src.text or '').strip() if src is not None else ''
        if not press and ' - ' in title: press = title.rsplit(' - ', 1)[1].strip()
        if ' - ' in title: title = title.rsplit(' - ', 1)[0].strip()
        title = html.unescape(html.unescape(title)); title = re.sub(r'\s*>\s*뉴스\s*$', '', title)   # 이중 이스케이프(&amp;gt;)·꼬리말 정리
        try: ts = parsedate_to_datetime(pub)
        except Exception: continue
        if ts.tzinfo is None: ts = ts.replace(tzinfo=datetime.timezone.utc)
        if title and link: out.append({'title': title, 'url': link, 'press': press, 'ts': ts})
    return out

def tokens(title):
    for a, b in SYN: title = title.replace(a, b)
    words = re.findall(r'[가-힣A-Za-z0-9]{2,}', title)
    out = set()
    for w in words:
        if re.match(r'^\d+(명|시간|분|건|일|층|대|곳|여|차|호|%)?$', w): continue          # 숫자·단위(20명, 2시간)는 사건 식별에 약하다
        if w in STOP or any(w.startswith(st) for st in STOP if len(st) >= 2): continue   # 화재로·소방관이 같은 조사 붙은 꼴도 제외(두 글자 이상 불용어만 앞부분 비교)
        out.add(w[:2])                                                                # 활동하던→활동, 아파트→아파 처럼 앞 2자로 비교(조사·어미 차이 무시)
    return out

def pick_top(items, day, n=5):
    start, end = window(day)
    items = [i for i in items if start <= i['ts'].astimezone(KST) < end]
    # 같은 기사(제목·링크 중복) 제거
    seen = set(); uniq = []
    for i in sorted(items, key=lambda x: x['ts'], reverse=True):
        k = (i['title'], i['press'])
        if k in seen: continue
        seen.add(k); uniq.append(i)
    # 제목 단어가 40% 이상 겹치면 같은 사건으로 묶는다
    clusters = []
    for i in uniq:
        t = tokens(i['title'])
        for c in clusters:   # 묶음의 '첫 기사' 단어와 비교(단어를 합쳐 가며 비교하면 다른 사건이 눈덩이처럼 붙는다)
            inter = len(t & c['tok']); union = len(t | c['tok']) or 1
            if t and ((inter >= 2 and inter / union >= 0.2) or inter >= 3):
                c['items'].append(i); break
        else:
            clusters.append({'tok': set(t), 'items': [i]})
    def score(c):
        presses = {x['press'] for x in c['items']}
        major = sum(1 for p in presses if any(m in p for m in MAJOR))          # 주요 언론사 수
        titles = ' / '.join(x['title'] for x in c['items'])
        foreign = any(f in titles for f in FOREIGN)                            # 해외 사건은 뒤로
        pr = any(w in titles for w in PR)                                      # 행사·홍보성(훈련 개최 등)은 '구조' 같은 단어가 있어도 사고로 보지 않음
        incident = (not pr) and any(w in titles for w in INCIDENT)             # 사고·인명 기사는 앞으로
        incheon = any(w in titles for w in INCHEON)                            # 인천 소방 소식은 맨 위
        s = major * 3 + (len(presses) - major) * 1 + len(c['items']) * 0.3 + (3 if incident else 0) - (6 if foreign else 0) - (4 if pr else 0) + (100 if incheon else 0)
        return (s, max(x['ts'] for x in c['items']))
    clusters.sort(key=score, reverse=True)
    top = []
    for c in clusters[:n]:
        rank = lambda x: next((i for i, m in enumerate(MAJOR) if m in x['press']), len(MAJOR))   # 주요 언론사 순위(앞일수록 우선), 없으면 뒤
        rep = sorted(c['items'], key=lambda x: (rank(x), -x['ts'].timestamp()))[0]
        top.append({'title': rep['title'], 'press': rep['press'], 'url': rep['url'], 'time': rep['ts'].astimezone(KST).strftime('%H:%M'), 'outlets': len({x['press'] for x in c['items']})})
    return top

def fetch_fire_news(day=None, timeout=12):
    day = day or datetime.datetime.now(KST).date()
    items = []; log = []
    for i, q in enumerate(QUERIES):
        if i: time.sleep(1.5)   # 검색어 사이 간격(속도 제한 예방)
        try: got = parse_rss(fetch_rss(q, timeout)); items += got; log.append('%s: %d건' % (q, len(got)))
        except Exception as e: log.append('%s: 실패(%s)' % (q, e)); print('[뉴스] %s 실패: %s' % (q, e), file=sys.stderr)
    start, end = window(day); inwin = sum(1 for i in items if start <= i['ts'].astimezone(KST) < end)
    print('::notice title=뉴스 수집::' + ' · '.join(log) + ' · 창(%s~%s) 안 %d건' % (start.strftime('%m/%d %H:%M'), end.strftime('%m/%d %H:%M'), inwin), file=sys.stderr)
    return pick_top(items, day)

if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('--date'); ap.add_argument('--json', action='store_true'); ap.add_argument('--sample', help='RSS xml 파일로 테스트(인터넷 없이)')
    a = ap.parse_args()
    day = datetime.date.fromisoformat(a.date) if a.date else datetime.datetime.now(KST).date()
    if a.sample: top = pick_top(parse_rss(open(a.sample, 'rb').read()), day)
    else: top = fetch_fire_news(day)
    if a.json: print(json.dumps(top, ensure_ascii=False))
    else:
        for i, t in enumerate(top, 1): print('%d. %s (%s, %s) %s' % (i, t['title'], t['press'], t['time'], t['url']))
