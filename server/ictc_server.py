# -*- coding: utf-8 -*-
r"""
SAIL:41 (지휘역량강화센터 일정·업무 보드) 로컬 서버 (Python 3.8+ 표준 라이브러리만 사용)

프로그램 폴더 (압축 푼 위치, 어디든 상관없음):
  ictc_server.py   이 파일
  start.bat        더블클릭 실행용 (DB 위치를 D:\일정표,주요업무\ 로 지정)
  site\            웹앱 화면 (index.html, config.js, data\, checklist\, assets\)

데이터 폴더 (start.bat 이 자동 생성):  D:\일정표,주요업무\
  ictc.db          SQLite 데이터베이스 - 글·일정·업무·사용자 전체 (백업 대상 1)
                   삭제한 항목은 DB 안의 items_deleted 표에 30일 보관 (화면 ⋮ → 휴지통, 또는 /api/deleted_list, /api/restore, 편집 PIN)
  files\           41망 첨부파일 원본 (백업 대상 2. DB 만 복원하면 첨부 링크가 깨진다)
  backups\         기동할 때마다 날짜별 DB 사본 자동 생성 (최근 7개 보관)
  pin.txt          편집 PIN (처음 실행 시 1234 로 생성, 메모장으로 수정)
  view_pin.txt     조회 PIN (처음 실행 시 0000 으로 생성). 내용을 비우면 누구나 조회 가능

실행:  python ictc_server.py  [--port 8080] [--db 경로] [--pin-file 경로] [--static 경로]
접속:  본인  http://localhost:8080
       팀원  http://<이 PC의 IP>:8080
"""
import argparse, glob, hashlib, hmac, json, mimetypes, os, re, secrets, socket, sqlite3, sys, threading, time, traceback
from collections import deque
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse, parse_qs, quote

HERE = os.path.dirname(os.path.abspath(__file__))
KINDS = ('schedule', 'tasks')   # 41망 톡방(chat)은 입장코드 검증이 있는 /api/chat_* 로만 다룬다
CHAT_ROOMS_DEFAULT = (('ictc', '지휘역량강화센터', '5948', 1), ('edu-support', '교육지원과', '5914', 2), ('edu-plan', '교육기획과', '5926', 3), ('training', '훈련운영과', '5527', 4))
VERSION = '5.7'
FILE_MAX = 100 * 1024 * 1024   # 41망 첨부파일 최대 100MB (DB 폴더 옆 files/ 에 저장)
ITEM_MAX = 64 * 1024           # 항목(일정·업무·톡방 글) 한 건 최대 크기 (supabase.sql ictc_check_item 과 동일)
BODY_MAX = 32 * 1024 * 1024    # /api/* JSON 본문 상한 (JSON 가져오기 포함)
# 업로드 허용 형식 (supabase.sql 의 sail41 버킷 allowed_mime_types 와 동일). 그 밖의 형식은 FILE_TYPE
FILE_TYPES = {'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif', 'application/pdf', 'text/plain', 'text/csv',
              'application/zip', 'application/x-hwp', 'application/haansofthwp', 'application/vnd.hancom.hwp', 'application/vnd.hancom.hwpx', 'application/x-hwpx',
              'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation', 'application/octet-stream'}
# 브라우저 안에서 바로 열어도 안전한 형식. 나머지(html·svg·js 등 스크립트 실행 가능 형식 포함)는 octet-stream + 내려받기로만 준다
INLINE_TYPES = {'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp', 'image/heic', 'image/heif', 'application/pdf', 'text/plain', 'text/csv'}
BACKUP_KEEP = 7            # 기동 시 날짜별 백업 보관 개수
TRASH_DAYS = 30            # 삭제 항목 보관 일수 (supabase.sql 의 ictc_trash 와 동일)
THROTTLE_MAX, THROTTLE_WINDOW = 10, 600   # IP당 10분 내 PIN 실패 10회 → 잠시 거부


class Throttle:
    """IP 별 PIN 실패 횟수 제한 (메모리, 재시작하면 초기화)"""
    def __init__(self):
        self.fails = {}; self.lock = threading.Lock()

    def check(self, ip):
        with self.lock:
            q = self.fails.get(ip)
            if q:
                now = time.time()
                while q and q[0] < now - THROTTLE_WINDOW: q.popleft()
                if len(q) >= THROTTLE_MAX: raise ApiError('TOO_MANY_ATTEMPTS', 429)

    def fail(self, ip):
        with self.lock:
            self.fails.setdefault(ip, deque()).append(time.time())


class ApiError(Exception):
    def __init__(self, code, status=400):
        super().__init__(code); self.code = code; self.status = status


def find_static():
    parent = os.path.dirname(HERE)
    for c in (os.path.join(HERE, 'site'), os.path.join(HERE, 'ictc'), parent):
        if os.path.isfile(os.path.join(c, 'index.html')) and os.path.isdir(os.path.join(c, 'data')):
            return c
    return None


def read_pin(path, default='1234', label='편집'):
    if not os.path.exists(path):
        with open(path, 'w', encoding='utf-8') as f:
            f.write(default + '\n')
        print(f'[안내] {label} PIN 파일을 만들었습니다: {path}  (기본 PIN {default}, 메모장으로 바꾸세요)')
    with open(path, encoding='utf-8-sig') as f:
        return f.read().strip()


def view_pin_path(pin_path):
    return os.path.join(os.path.dirname(pin_path), 'view_pin.txt')


def hash_pin(pin, salt=None):
    salt = salt or secrets.token_hex(8)
    h = hashlib.pbkdf2_hmac('sha256', pin.encode('utf-8'), salt.encode('utf-8'), 50000).hex()
    return f'{salt}${h}'


def check_hash(pin, stored):
    try:
        salt, _ = stored.split('$', 1)
    except ValueError:
        return False
    return hmac.compare_digest(hash_pin(pin, salt), stored)


def check_item(item):
    """항목 한 건 검사 (supabase.sql ictc_check_item 과 동일): id 필수·100자 이하, 전체 64KB 이하"""
    if not isinstance(item, dict) or not item.get('id'): raise ApiError('ID_REQUIRED')
    if len(str(item['id'])) > 100 or len(json.dumps(item, ensure_ascii=False).encode('utf-8')) > ITEM_MAX: raise ApiError('ITEM_TOO_LARGE', 413)
    return item


def backup_db(path):
    """기동 시 데이터 폴더의 backups/ 에 날짜별 사본을 남기고 오래된 것은 지운다."""
    if not os.path.exists(path): return
    bdir = os.path.join(os.path.dirname(os.path.abspath(path)), 'backups')
    os.makedirs(bdir, exist_ok=True)
    dst = os.path.join(bdir, 'ictc-%s.db' % datetime.now().strftime('%Y%m%d'))
    try:
        src = sqlite3.connect(path); out = sqlite3.connect(dst)
        with out: src.backup(out)
        src.close(); out.close()
        old = sorted(glob.glob(os.path.join(bdir, 'ictc-*.db')))[:-BACKUP_KEEP]
        for f in old: os.remove(f)
        print(f'[안내] 백업: {dst}  (최근 {BACKUP_KEEP}개 보관)')
    except Exception as e:
        print(f'[경고] 백업 실패: {e}')



# ----- 아침 브리핑 문장 (supabase.sql ictc_briefing_text · index.html briefingText 와 같은 형식) -----
import datetime as _dt
def _d(s):
    try: return _dt.date.fromisoformat((s or '')[:10]) if s else None
    except ValueError: return None
def briefing_text(sched, tasks, room_name, date):
    dow = '일월화수목금토'
    out = [f'📋 {date.month}월 {date.day}일({dow[(date.weekday() + 1) % 7]}) 아침 브리핑 · {room_name}']
    for label, d in (('오늘', date), ('내일', date + _dt.timedelta(days=1))):
        rows = []
        for it in sched:
            sd = _d(it.get('date')); ed = _d(it.get('endDate')) or sd
            if sd and sd <= d <= ed:
                tags = it.get('tags') if isinstance(it.get('tags'), list) else [it.get('tag')]
                rows.append((0 if '주요업무' in tags else 1, it.get('start') or '', it.get('title') or '', it, sd, ed))
        rows.sort(key=lambda r: (r[0], r[1], r[2]))
        out.append(f'{label} 일정 {len(rows)}건')
        for k, (major, start, title, it, sd, ed) in enumerate(rows):
            if k >= 8: out.append(f' … 외 {len(rows) - 8}건'); break
            line = f" {start or '종일'} {'★ ' if major == 0 else ''}{title}"
            if it.get('place'): line += ' · ' + it['place']
            if it.get('owner'): line += ' · ' + it['owner']
            if ed > sd: line += f' ({(d - sd).days + 1}/{(ed - sd).days + 1}일차)'
            out.append(line)
    live = [t for t in tasks if (t.get('status') or '') not in ('완료', '보류')]
    late = [t for t in live if _d(t.get('due')) and _d(t['due']) < date]
    today = [t for t in live if _d(t.get('due')) == date]
    prog = [t for t in live if t.get('status') == '진행중']
    out.append(f'업무: 기한 지남 {len(late)}건 · 오늘 기한 {len(today)}건 · 진행중 {len(prog)}건')
    due = sorted(today, key=lambda t: t.get('title') or '')   # 목록에는 오늘 기한만 (기한 지난 업무는 건수만)
    for k, t in enumerate(due):
        if k >= 6: out.append(f' … 외 {len(due) - 6}건'); break
        line = ' ! ' + (t.get('title') or '')
        if t.get('owner'): line += ' · ' + t['owner']
        out.append(line + ' · 오늘')
    return '\n'.join(out)

class DB:
    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()
        con = self._con()
        con.execute('pragma journal_mode=wal')
        con.execute('''create table if not exists items (
            id text primary key, kind text not null, data text not null, updated_at text not null)''')
        cols = [r[1] for r in con.execute('pragma table_info(items)')]
        if 'board' not in cols:
            con.execute("alter table items add column board text not null default 'main'")
        con.execute('create index if not exists items_kind_board_updated on items(kind, board, updated_at)')
        con.execute('create table if not exists boards (id text primary key, name text not null, created_at text not null)')
        con.execute("insert or ignore into boards(id, name, created_at) values('main', '지휘역량강화센터', ?)", (self.now(),))
        con.execute('create table if not exists users (id text primary key, name text not null, pin_hash text not null, created_at text not null)')
        con.execute('''create table if not exists items_deleted (seq integer primary key autoincrement, id text not null, kind text not null,
            board text not null, data text not null, updated_at text not null, deleted_at text not null, reason text not null default 'delete')''')
        con.execute('create index if not exists items_deleted_deleted_at on items_deleted(deleted_at)')
        # 41망 톡방: 입장코드는 해시로만. 기본 코드는 처음 만들 때만(insert or ignore)
        con.execute('create table if not exists chat_rooms (id text primary key, name text not null, code_hash text not null, sort integer not null default 0, created_at text not null)')
        for rid, name, code, sort in CHAT_ROOMS_DEFAULT:
            con.execute('insert or ignore into chat_rooms(id, name, code_hash, sort, created_at) values(?,?,?,?,?)', (rid, name, hash_pin(code), sort, self.now()))
        con.execute("update items set board='ictc' where kind='chat' and board='main'")   # v4 의 단일 톡방 글을 지휘역량강화센터 톡방으로
        con.commit(); con.close()

    def _con(self):
        return sqlite3.connect(self.path, timeout=10, check_same_thread=False)   # 백업 도구 등 외부 접근과 겹쳐도 10초 대기

    @staticmethod
    def now():
        return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')

    def _run(self, fn):
        with self.lock:
            con = self._con()
            try:
                r = fn(con); con.commit(); return r
            finally:
                con.close()

    # ----- 항목 -----
    def list(self, kind, board):
        rows = self._run(lambda c: c.execute('select data, updated_at from items where kind=? and board=? order by updated_at desc', (kind, board)).fetchall())
        return [{'data': json.loads(d), 'updated_at': u} for d, u in rows]

    def save(self, kind, board, item):
        check_item(item)
        def go(c):
            if kind in KINDS:
                if not c.execute('select 1 from boards where id=?', (board,)).fetchone(): raise ApiError('BOARD_NOT_FOUND', 404)
                # 같은 id 의 개인업무·톡방 행은 덮어쓰지 않음 (supabase.sql ictc_save 와 동일)
                guard = "items.kind in ('schedule','tasks')"
            else:
                # 개인업무·톡방 글은 같은 사용자·톡방의 행만 갱신 (ictc_personal_save / ictc_chat_save 와 동일)
                guard = 'items.kind=excluded.kind and items.board=excluded.board'
            if kind == 'chat' and item.get('deleted') is True:   # 화면의 '글 삭제'는 자리표시 덮어쓰기 → 원문을 휴지통에 남긴다
                c.execute('''insert into items_deleted(id, kind, board, data, updated_at, deleted_at, reason)
                    select id, kind, board, data, updated_at, ?, 'delete' from items where id=? and kind='chat' and board=? and json_extract(data, '$.deleted') is not 1''',
                          (self.now(), item['id'], board))
            c.execute('''insert into items(id, kind, board, data, updated_at) values(?,?,?,?,?)
                on conflict(id) do update set data=excluded.data, kind=excluded.kind, board=excluded.board, updated_at=excluded.updated_at
                where ''' + guard, (item['id'], kind, board, json.dumps(item, ensure_ascii=False), self.now()))
            if kind == 'chat':   # 톡방마다 최근 300개만 보관 (supabase.sql ictc_chat_save 와 동일)
                c.execute('''delete from items where kind='chat' and board=? and id not in
                             (select id from items where kind='chat' and board=? order by updated_at desc limit 300)''', (board, board))
        self._run(go)

    # ----- 아침 브리핑: 톡방마다 하루 한 번(id brief-<톡방>-<날짜>) -----
    def chat_briefing(self, date=None):
        date = date or _dt.date.today(); cnt = 0
        boards = {b['name']: b['id'] for b in self.boards()}
        for r in self.chat_rooms():
            mid = f"brief-{r['id']}-{date.strftime('%Y%m%d')}"
            if self._run(lambda c: c.execute('select 1 from items where id=?', (mid,)).fetchone()): continue
            board = boards.get(r['name'], 'main')
            txt = briefing_text([x['data'] for x in self.list('schedule', board)], [x['data'] for x in self.list('tasks', board)], r['name'], date)
            item = {'id': mid, 'text': txt, 'name': '브리핑', 'dev': 'bot', 'bot': True, 'created': _dt.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')}
            self.save('chat', r['id'], item); cnt += 1
        return cnt
    def chat_briefing_if_due(self):   # 평일 08:00 이후에만(화면의 보충 호출·스케줄러 공용)
        t = _dt.datetime.now()
        if t.weekday() >= 5 or t.hour < 8: return 0
        return self.chat_briefing(t.date())

    # ----- 41망 톡방 -----
    def chat_rooms(self):
        rows = self._run(lambda c: c.execute('select id, name, sort from chat_rooms order by sort, created_at').fetchall())
        return [{'id': i, 'name': n, 'sort': s} for i, n, s in rows]

    def chat_check(self, room, code):
        row = self._run(lambda c: c.execute('select code_hash from chat_rooms where id=?', (room,)).fetchone())
        if not row: raise ApiError('CHAT_ROOM_NOT_FOUND', 404)
        if not check_hash((code or '').strip(), row[0]): raise ApiError('CHAT_CODE_INVALID', 403)

    def chat_room_name(self, room):
        row = self._run(lambda c: c.execute('select name from chat_rooms where id=?', (room,)).fetchone())
        return row[0] if row else None

    def chat_set_code(self, room, new):
        if len((new or '').strip()) < 4: raise ApiError('CHAT_CODE_TOO_SHORT')
        def go(c):
            if c.execute('update chat_rooms set code_hash=? where id=?', (hash_pin(new.strip()), room)).rowcount == 0: raise ApiError('CHAT_ROOM_NOT_FOUND', 404)
        self._run(go)

    def chat_room_rename(self, room, name):
        if not (name or '').strip(): raise ApiError('NAME_REQUIRED')
        def go(c):
            if c.execute('update chat_rooms set name=? where id=?', (name.strip(), room)).rowcount == 0: raise ApiError('CHAT_ROOM_NOT_FOUND', 404)
        self._run(go)

    def chat_room_add(self, id_, name, code):
        if not (id_ or '').strip() or not (name or '').strip(): raise ApiError('NAME_REQUIRED')
        if len((code or '').strip()) < 4: raise ApiError('CHAT_CODE_TOO_SHORT')
        def go(c):
            if c.execute('select 1 from chat_rooms where id=?', (id_.strip(),)).fetchone(): raise ApiError('CHAT_ROOM_EXISTS')
            sort = (c.execute('select coalesce(max(sort),0) from chat_rooms').fetchone()[0] or 0) + 1
            c.execute('insert into chat_rooms(id, name, code_hash, sort, created_at) values(?,?,?,?,?)', (id_.strip(), name.strip(), hash_pin(code.strip()), sort, self.now()))
        self._run(go)

    def chat_room_delete(self, room):
        def go(c):
            self._trash(c, 'chat', room, None, 'room_delete')
            c.execute("delete from items where kind='chat' and board=?", (room,))
            if c.execute('delete from chat_rooms where id=?', (room,)).rowcount == 0: raise ApiError('CHAT_ROOM_NOT_FOUND', 404)
        self._run(go)

    def _trash(self, c, kind, board, id_, reason):
        """삭제 전 사본을 items_deleted 에 남기고 TRASH_DAYS 지난 보관 행을 정리 (supabase.sql ictc_trash 와 동일). id_ 가 None 이면 kind·board 전체"""
        now = self.now()
        c.execute('''insert into items_deleted(id, kind, board, data, updated_at, deleted_at, reason)
            select id, kind, board, data, updated_at, ?, ? from items where kind=? and board=? and (? is null or id=?)''', (now, reason, kind, board, id_, id_))
        cutoff = datetime.fromtimestamp(time.time() - TRASH_DAYS * 86400, timezone.utc).isoformat().replace('+00:00', 'Z')
        c.execute('delete from items_deleted where deleted_at < ?', (cutoff,))

    def delete(self, kind, board, id_, reason='delete'):
        if not id_: raise ApiError('ID_REQUIRED')   # id 없이 부르면 _trash 가 전체를 복사하므로 막는다
        def fn(c):
            self._trash(c, kind, board, id_, reason)
            c.execute('delete from items where id=? and kind=? and board=?', (id_, kind, board))
            if kind == 'schedule':   # 일정의 연동 주요업무 카드('sch-'+일정id)도 함께 (supabase.sql ictc_delete 와 동일)
                self._trash(c, 'tasks', board, 'sch-' + id_, reason)
                c.execute("delete from items where id=? and kind='tasks' and board=?", ('sch-' + id_, board))
        self._run(fn)

    def replace(self, kind, board, items):
        if not isinstance(items, list) or len(items) > 10000: raise ApiError('ITEMS_REQUIRED' if not isinstance(items, list) else 'ITEM_TOO_LARGE', 413)
        for x in items:
            if not isinstance(x, dict): raise ApiError('ITEMS_REQUIRED')
            x.setdefault('id', f'{int(time.time()*1000):x}{os.urandom(3).hex()}'); check_item(x)
        now = self.now()
        def fn(c):
            if not c.execute('select 1 from boards where id=?', (board,)).fetchone(): raise ApiError('BOARD_NOT_FOUND', 404)
            self._trash(c, kind, board, None, 'replace')
            c.execute('delete from items where kind=? and board=?', (kind, board))
            for x in items:   # 같은 id 가 여러 번이면 마지막 것. 다른 종류·대시보드에 있는 id 는 건너뜀 (ictc_replace 와 동일)
                c.execute('''insert into items(id, kind, board, data, updated_at) values(?,?,?,?,?)
                    on conflict(id) do update set data=excluded.data, updated_at=excluded.updated_at where items.kind=? and items.board=?''',
                          (x['id'], kind, board, json.dumps(x, ensure_ascii=False), now, kind, board))
        self._run(fn)

    # ----- 대시보드 -----
    def boards(self):
        rows = self._run(lambda c: c.execute("select id, name from boards order by (id <> 'main'), created_at").fetchall())
        return [{'id': i, 'name': n} for i, n in rows]

    def board_add(self, id_, name):
        if not id_.strip() or len(id_) > 64: raise ApiError('ID_REQUIRED')
        if not name.strip(): raise ApiError('NAME_REQUIRED')
        def fn(c):
            if c.execute('select 1 from boards where id=?', (id_,)).fetchone(): raise ApiError('BOARD_EXISTS')
            c.execute('insert into boards(id, name, created_at) values(?,?,?)', (id_, name.strip()[:60], self.now()))
        self._run(fn)

    def board_rename(self, id_, name):
        if not name.strip(): raise ApiError('NAME_REQUIRED')
        def fn(c):
            if c.execute('update boards set name=? where id=?', (name.strip()[:60], id_)).rowcount == 0: raise ApiError('BOARD_NOT_FOUND', 404)
        self._run(fn)

    def board_delete(self, id_):
        if id_ == 'main': raise ApiError('BOARD_PROTECTED')
        def fn(c):
            for k in KINDS: self._trash(c, k, id_, None, 'board_delete')
            c.execute("delete from items where board=? and kind in ('schedule','tasks')", (id_,))
            c.execute('delete from boards where id=?', (id_,))
        self._run(fn)

    def counts(self):
        rows = self._run(lambda c: c.execute('select kind, count(*) from items group by kind').fetchall())
        return {k: n for k, n in rows}

    # ----- 개인업무 -----
    def users_list(self):
        rows = self._run(lambda c: c.execute('''select u.id, u.name, u.created_at,
            (select count(*) from items i where i.kind='personal' and i.board=u.id) from users u order by u.created_at''').fetchall())
        return [{'id': i, 'name': n, 'created_at': c, 'item_count': k} for i, n, c, k in rows]

    def user_delete(self, id_):
        def fn(c):
            self._trash(c, 'personal', id_, None, 'user_delete')
            c.execute("delete from items where kind='personal' and board=?", (id_,))
            if c.execute('delete from users where id=?', (id_,)).rowcount == 0: raise ApiError('USER_NOT_FOUND', 404)
        self._run(fn)

    def user_check(self, id_, pin):
        row = self._run(lambda c: c.execute('select pin_hash, name from users where id=?', (id_,)).fetchone())
        if not row: raise ApiError('USER_NOT_FOUND', 403)
        if not check_hash(pin or '', row[0]): raise ApiError('USER_PIN_INVALID', 403)
        return row[1]

    def user_register(self, id_, name, pin):
        if not 4 <= len(id_ or '') <= 20: raise ApiError('USER_ID_INVALID')
        if not (name or '').strip(): raise ApiError('NAME_REQUIRED')
        if len((pin or '').strip()) < 4: raise ApiError('PIN_TOO_SHORT')
        name = name.strip()[:20]
        def fn(c):
            if c.execute('select 1 from users where id=?', (id_,)).fetchone(): raise ApiError('USER_EXISTS')
            c.execute('insert into users(id, name, pin_hash, created_at) values(?,?,?,?)', (id_, name, hash_pin(pin), self.now()))
        self._run(fn); return name

    def user_set_pin(self, id_, new):
        # v4: 비밀번호(4자리)와 이름은 별개
        if len((new or '').strip()) < 4: raise ApiError('PIN_TOO_SHORT')
        def go(c):
            if c.execute('update users set pin_hash=? where id=?', (hash_pin(new.strip()), id_)).rowcount == 0: raise ApiError('USER_NOT_FOUND', 404)
        self._run(go)

    def user_rename(self, id_, name):
        if len((name or '').strip()) < 2: raise ApiError('NAME_REQUIRED')
        def go(c):
            if c.execute('update users set name=? where id=?', (name.strip()[:20], id_)).rowcount == 0: raise ApiError('USER_NOT_FOUND', 404)
        self._run(go)

    def personal_list(self, id_):
        return self.list('personal', id_)

    def personal_save(self, id_, item):
        self.save('personal', id_, item)

    def personal_delete(self, id_, item_id):
        self.delete('personal', id_, item_id, 'personal_delete')

    # ----- 휴지통 (편집 PIN) -----
    def deleted_list(self, kind=None, board=None):
        def go(c):
            cutoff = datetime.fromtimestamp(time.time() - TRASH_DAYS * 86400, timezone.utc).isoformat().replace('+00:00', 'Z')
            c.execute('delete from items_deleted where deleted_at < ?', (cutoff,))   # 삭제가 한동안 없어도 목록을 열 때 정리
            return c.execute('''select seq, id, kind, board, data, updated_at, deleted_at, reason from items_deleted
                where (? is null or kind=?) and (? is null or board=?) order by deleted_at desc, seq desc limit 500''', (kind, kind, board, board)).fetchall()
        rows = self._run(go)
        return [{'seq': s, 'id': i, 'kind': k, 'board': b, 'data': json.loads(d), 'updated_at': u, 'deleted_at': dl, 'reason': r} for s, i, k, b, d, u, dl, r in rows]

    def restore(self, seq):
        """보관본 복구. 일정 ↔ 연동 카드('sch-'+일정id)는 보관본이 있으면 짝도 함께 (supabase.sql ictc_restore 와 동일)"""
        def fn(c):
            row = c.execute('select id, kind, board, data from items_deleted where seq=?', (seq,)).fetchone()
            if not row: raise ApiError('DELETED_NOT_FOUND', 404)
            id_, kind, board, data = row
            if kind == 'personal' and not c.execute('select 1 from users where id=?', (board,)).fetchone(): raise ApiError('USER_NOT_FOUND', 404)
            if kind in KINDS and not c.execute('select 1 from boards where id=?', (board,)).fetchone(): raise ApiError('BOARD_NOT_FOUND', 404)
            if kind == 'chat' and not c.execute('select 1 from chat_rooms where id=?', (board,)).fetchone(): raise ApiError('CHAT_ROOM_NOT_FOUND', 404)
            c.execute('''insert into items(id, kind, board, data, updated_at) values(?,?,?,?,?)
                on conflict(id) do update set data=excluded.data, board=excluded.board, updated_at=excluded.updated_at where items.kind=excluded.kind''', (id_, kind, board, data, self.now()))
            c.execute('delete from items_deleted where seq=?', (seq,))
            partner = None
            if kind == 'schedule': partner = ('tasks', 'sch-' + id_)
            elif kind == 'tasks' and id_.startswith('sch-'): partner = ('schedule', id_[4:])
            if partner:
                p = c.execute('select seq, id, kind, board, data from items_deleted where kind=? and board=? and id=? order by deleted_at desc, seq desc limit 1', (partner[0], board, partner[1])).fetchone()
                if p and not c.execute('select 1 from items where id=?', (p[1],)).fetchone():
                    c.execute('insert or ignore into items(id, kind, board, data, updated_at) values(?,?,?,?,?)', (p[1], p[2], p[3], p[4], self.now()))
                    c.execute('delete from items_deleted where seq=?', (p[0],))
        self._run(fn)


def make_handler(db, static_dir, pin_path, poll):
    throttle = Throttle()

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=static_dir, **kw)

        def log_message(self, fmt, *args):
            if self.path.startswith('/api/'):
                sys.stdout.write('%s  %s\n' % (time.strftime('%H:%M:%S'), fmt % args)); sys.stdout.flush()

        def _json(self, code, obj=None):
            body = b'' if obj is None else json.dumps(obj, ensure_ascii=False).encode('utf-8')
            self.send_response(code)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers(); self.wfile.write(body)

        def end_headers(self):
            if not self.path.startswith(('/api/', '/files/')):
                self.send_header('Cache-Control', 'no-cache')
            super().end_headers()

        def list_directory(self, path):   # 폴더 목록은 보여 주지 않음
            self.send_error(404); return None

        def _drain(self, n):
            """오류 응답 전에 작은 본문은 읽어 버린다 (안 읽으면 브라우저가 응답 대신 연결 끊김으로 보는 경우가 있음)"""
            if 0 < n <= 8 * 1024 * 1024:
                left = n
                while left > 0:
                    chunk = self.rfile.read(min(1 << 20, left))
                    if not chunk: break
                    left -= len(chunk)

        def _edit_pin(self): return read_pin(pin_path)
        def _view_pin(self): return read_pin(view_pin_path(pin_path), '0000', '조회')

        def _ip(self): return self.client_address[0]

        def require_view(self, given):
            vp = self._view_pin(); given = (given or '').strip()
            if vp and not given: raise ApiError('VIEW_PIN_REQUIRED', 403)
            throttle.check(self._ip())
            if vp and given not in (vp, self._edit_pin()):
                throttle.fail(self._ip()); raise ApiError('VIEW_PIN_INVALID', 403)

        def require_edit(self, given):
            throttle.check(self._ip())
            if (given or '').strip() != self._edit_pin():
                throttle.fail(self._ip()); raise ApiError('PIN_INVALID', 403)

        def user_check(self, uid, pin):
            throttle.check(self._ip())
            try:
                return db.user_check(uid, pin)
            except ApiError as e:
                if e.code == 'USER_PIN_INVALID': throttle.fail(self._ip())
                raise

        def do_GET(self):
            u = urlparse(self.path); q = parse_qs(u.query)
            if u.path == '/config.js':
                body = ('window.ICTC_CONFIG = { apiUrl: "", pollSeconds: %d };\n' % poll).encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/javascript; charset=utf-8')
                self.send_header('Cache-Control', 'no-store'); self.send_header('Content-Length', str(len(body)))
                self.end_headers(); self.wfile.write(body); return
            if u.path.startswith('/files/'):
                # 파일은 URL 의 난수 id 로만 찾는다 (이름 부분은 무시 → 경로 탐색 불가). 받다 만 .part 는 제외
                m = re.match(r'^/files/([0-9a-f]{24,40})/', u.path)
                fdir = os.path.join(os.path.dirname(db.path), 'files')
                path = m and [f for f in glob.glob(os.path.join(fdir, m.group(1) + '-*')) if not f.endswith('.part')]
                if not path: self.send_error(404); return
                name = os.path.basename(path[0]).split('-', 1)[1]; size = os.path.getsize(path[0])
                ctype = (mimetypes.guess_type(name)[0] or 'application/octet-stream').lower()
                self.send_response(200); self.send_header('Content-Length', str(size))
                if ctype in INLINE_TYPES:   # 사진·PDF·텍스트만 브라우저에서 바로 열기
                    self.send_header('Content-Type', ctype + ('; charset=utf-8' if ctype.startswith('text/') else ''))
                else:   # html·svg 등은 이 서버 origin 에서 스크립트가 실행될 수 있으므로 내려받기로만
                    self.send_header('Content-Type', 'application/octet-stream')
                    self.send_header('Content-Disposition', "attachment; filename*=UTF-8''" + quote(name))
                self.send_header('Cache-Control', 'public, max-age=31536000, immutable'); self.send_header('X-Content-Type-Options', 'nosniff')
                self.end_headers()
                with open(path[0], 'rb') as fh:   # 1MB 씩 스트리밍
                    while True:
                        chunk = fh.read(1 << 20)
                        if not chunk: break
                        self.wfile.write(chunk)
                return
            if not u.path.startswith('/api/'):
                return super().do_GET()
            try:
                if u.path == '/api/health':
                    return self._json(200, {'ok': True, 'version': VERSION, 'time': db.now(), 'counts': db.counts(), 'db': os.path.basename(db.path)})
                self.require_view(self.headers.get('X-Pin'))
                if u.path == '/api/items':
                    kind = q.get('kind', [''])[0]; board = q.get('board', ['main'])[0] or 'main'
                    if kind not in KINDS: raise ApiError('KIND_INVALID')
                    return self._json(200, db.list(kind, board))
                if u.path == '/api/boards':
                    return self._json(200, db.boards())
                if u.path == '/api/chat_rooms':
                    return self._json(200, db.chat_rooms())
                raise ApiError('NOT_FOUND', 404)
            except ApiError as e:
                return self._json(e.status, {'message': e.code})

        def do_POST(self):
            u = urlparse(self.path)
            try:
                if not u.path.startswith('/api/'): raise ApiError('NOT_FOUND', 404)
                if u.path == '/api/upload':   # 첨부: 조회 PIN 확인 뒤 files/ 에 저장. 41망(room+code)은 입장코드도 확인, 일정·업무 사진(kind=items)은 조회 PIN 만
                    q = parse_qs(u.query); room = (q.get('room') or [''])[0]; code = (q.get('code') or [''])[0]; kind = (q.get('kind') or [''])[0]
                    n = int(self.headers.get('Content-Length') or 0)
                    try:
                        self.require_view(self.headers.get('X-Pin')); throttle.check(self._ip())
                        if kind != 'items':
                            try: db.chat_check(room, code)
                            except ApiError as e:
                                if e.code == 'CHAT_CODE_INVALID': throttle.fail(self._ip())
                                raise
                        if n <= 0 or n > FILE_MAX: raise ApiError('FILE_TOO_LARGE', 413)   # 헤더로 1차 거부. 실제 받은 양은 아래에서 다시 확인
                        ctype = (self.headers.get('Content-Type') or mimetypes.guess_type((q.get('name') or ['file'])[0])[0] or 'application/octet-stream').split(';')[0].strip().lower()
                        if ctype not in FILE_TYPES: raise ApiError('FILE_TYPE', 415)
                    except ApiError:
                        self._drain(n); raise
                    name = re.sub(r'[^\w.\-가-힣 ()]+', '_', (q.get('name') or ['file'])[0]).strip(' .')[:80] or 'file'
                    fid = secrets.token_hex(12); fdir = os.path.join(os.path.dirname(db.path), 'files'); os.makedirs(fdir, exist_ok=True)
                    final = os.path.join(fdir, f'{fid}-{name}'); part = final + '.part'; got = 0
                    with open(part, 'wb') as f:   # 큰 파일은 1MB 씩 나눠 받아 메모리를 아낀다. 다 받기 전에는 .part 라 /files/ 로 안 보인다
                        while got < n:
                            chunk = self.rfile.read(min(1 << 20, n - got))
                            if not chunk: break
                            f.write(chunk); got += len(chunk)
                    if got != n:   # 중간에 끊긴 업로드는 버린다 (잘린 파일을 성공으로 돌려주지 않음)
                        try: os.remove(part)
                        except OSError: pass
                        raise ApiError('UPLOAD_FAILED', 400)
                    os.replace(part, final)
                    return self._json(200, {'url': f'/files/{fid}/{name}', 'name': name, 'size': n, 'type': ctype})
                n = int(self.headers.get('Content-Length') or 0)
                if n > BODY_MAX: self._drain(0); raise ApiError('ITEM_TOO_LARGE', 413)
                try:
                    b = json.loads(self.rfile.read(n) or b'{}')
                    if not isinstance(b, dict): raise ValueError
                except Exception:
                    raise ApiError('JSON_INVALID')
                fn = u.path[5:]
                kind = b.get('kind'); board = (b.get('board') or 'main')
                if fn in ('save', 'delete', 'replace'):
                    if fn == 'replace': self.require_edit(b.get('pin'))
                    else: self.require_view(b.get('pin'))      # 일정·주요업무 수정은 조회 PIN 으로 누구나
                    if kind not in KINDS: raise ApiError('KIND_INVALID')
                    if fn == 'save':
                        db.save(kind, board, check_item(b.get('item')))
                    elif fn == 'delete':
                        db.delete(kind, board, str(b.get('id') or ''))
                    else:
                        db.replace(kind, board, b.get('items'))
                    return self._json(204)
                if fn == 'board_add':
                    self.require_edit(b.get('pin')); db.board_add(str(b.get('id', '')), str(b.get('name', ''))); return self._json(204)
                if fn == 'board_rename':
                    self.require_edit(b.get('pin')); db.board_rename(str(b.get('id', '')), str(b.get('name', ''))); return self._json(204)
                if fn == 'board_delete':
                    self.require_edit(b.get('pin')); db.board_delete(str(b.get('id', ''))); return self._json(204)
                if fn == 'user_register':
                    self.require_view(b.get('view_pin'))
                    return self._json(200, {'name': db.user_register(str(b.get('id', '')), str(b.get('name', '')), str(b.get('user_pin', '')))})
                if fn == 'user_login':
                    return self._json(200, {'name': self.user_check(str(b.get('id', '')), str(b.get('user_pin', '')))})
                if fn == 'user_set_pin':
                    self.user_check(str(b.get('id', '')), str(b.get('user_pin', ''))); db.user_set_pin(str(b.get('id', '')), str(b.get('new_pin', ''))); return self._json(204)
                if fn == 'user_reset_pin':
                    self.require_edit(b.get('pin')); db.user_set_pin(str(b.get('id', '')), str(b.get('new_pin', ''))); return self._json(204)
                if fn == 'chat_briefing_now':   # 관리자: 요일·시각과 상관없이 오늘 브리핑을 지금 올린다(이미 있으면 0)
                    self.require_edit(b.get('pin')); return self._json(200, db.chat_briefing())
                if fn == 'chat_briefing':   # 보충 게시: 평일 8시 이후면 오늘 브리핑이 없는 톡방에 올린다
                    self.require_view(b.get('pin')); return self._json(200, db.chat_briefing_if_due())
                if fn in ('chat_join', 'chat_list', 'chat_save', 'chat_delete'):
                    self.require_view(b.get('pin')); room = str(b.get('room', ''))
                    throttle.check(self._ip())
                    try: db.chat_check(room, str(b.get('code', '')))
                    except ApiError as e:
                        if e.code == 'CHAT_CODE_INVALID': throttle.fail(self._ip())
                        raise
                    if fn == 'chat_join': return self._json(200, {'name': db.chat_room_name(room)})
                    if fn == 'chat_list': return self._json(200, db.list('chat', room))
                    if fn == 'chat_save':
                        db.save('chat', room, check_item(b.get('item'))); return self._json(204)
                    db.delete('chat', room, str(b.get('id') or '')); return self._json(204)
                if fn == 'chat_set_code':
                    self.require_edit(b.get('pin')); db.chat_set_code(str(b.get('room', '')), str(b.get('new_code', ''))); return self._json(204)
                if fn == 'chat_room_rename':
                    self.require_edit(b.get('pin')); db.chat_room_rename(str(b.get('room', '')), str(b.get('name', ''))); return self._json(204)
                if fn == 'chat_room_add':
                    self.require_edit(b.get('pin')); db.chat_room_add(str(b.get('id', '')), str(b.get('name', '')), str(b.get('code', ''))); return self._json(204)
                if fn == 'chat_room_delete':
                    self.require_edit(b.get('pin')); db.chat_room_delete(str(b.get('room', ''))); return self._json(204)
                if fn == 'user_set_name':
                    self.user_check(str(b.get('id', '')), str(b.get('user_pin', ''))); db.user_rename(str(b.get('id', '')), str(b.get('name', ''))[:20]); return self._json(204)
                if fn == 'user_rename':
                    self.require_edit(b.get('pin')); db.user_rename(str(b.get('id', '')), str(b.get('name', ''))); return self._json(204)
                if fn == 'users_list':
                    self.require_edit(b.get('pin')); return self._json(200, db.users_list())
                if fn == 'user_delete':
                    self.require_edit(b.get('pin')); db.user_delete(str(b.get('id', ''))); return self._json(204)
                if fn == 'deleted_list':
                    self.require_edit(b.get('pin')); return self._json(200, db.deleted_list(b.get('kind') or None, b.get('board') or None))
                if fn == 'restore':
                    self.require_edit(b.get('pin'))
                    try: seq = int(b.get('seq'))
                    except (TypeError, ValueError): raise ApiError('DELETED_NOT_FOUND', 404)
                    db.restore(seq); return self._json(204)
                if fn in ('personal_list', 'personal_save', 'personal_delete'):
                    uid = str(b.get('id', '')); self.user_check(uid, str(b.get('user_pin', '')))
                    if fn == 'personal_list': return self._json(200, db.personal_list(uid))
                    if fn == 'personal_save':
                        db.personal_save(uid, check_item(b.get('item')))
                    else:
                        db.personal_delete(uid, str(b.get('item_id') or ''))
                    return self._json(204)
                raise ApiError('NOT_FOUND', 404)
            except ApiError as e:
                return self._json(e.status, {'message': e.code})
            except Exception:
                # 예외 원문(경로·SQL 등)은 화면에 보내지 않고 콘솔에만 남긴다. 화면에는 코드 문자열만
                sys.stderr.write('[오류] %s %s\n%s' % (time.strftime('%H:%M:%S'), self.path, traceback.format_exc())); sys.stderr.flush()
                return self._json(500, {'message': 'SERVER_ERROR'})

    return Handler


def lan_ips():
    ips = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith('127.'): ips.add(ip)
    except Exception:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(('10.255.255.255', 1))
        ips.add(s.getsockname()[0]); s.close()
    except Exception:
        pass
    return sorted(ips)


def main():
    for stream in (sys.stdout, sys.stderr):   # Windows 에서 출력이 파일로 보내지면 cp949 가 되어 일부 글자가 예외를 내므로 대체 문자로
        try: stream.reconfigure(errors='replace')
        except Exception: pass
    ap = argparse.ArgumentParser(description='SAIL:41 일정·업무 보드 로컬 서버')
    ap.add_argument('--port', type=int, default=8080)
    ap.add_argument('--db', default=os.path.join(HERE, 'ictc.db'))
    ap.add_argument('--pin-file', default=os.path.join(HERE, 'pin.txt'))
    ap.add_argument('--static', default=None, help='웹앱 폴더 경로 (기본: 자동 탐색)')
    ap.add_argument('--poll', type=int, default=15, help='팀원 화면 자동 새로고침 주기(초)')
    ap.add_argument('--host', default='0.0.0.0', help='127.0.0.1 로 바꾸면 이 PC에서만 접속 가능')
    a = ap.parse_args()

    static = a.static or find_static()
    if not static:
        print('[오류] 웹앱 폴더(site)를 찾을 수 없습니다. 이 파일 옆에 site 폴더를 복사하세요.'); sys.exit(1)
    for path in (a.db, a.pin_file):
        d = os.path.dirname(os.path.abspath(path))
        if d and not os.path.isdir(d):
            os.makedirs(d, exist_ok=True); print(f'[안내] 데이터 폴더를 만들었습니다: {d}')
    backup_db(a.db)
    db = DB(a.db)
    read_pin(a.pin_file); read_pin(view_pin_path(a.pin_file), '0000', '조회')
    srv = ThreadingHTTPServer((a.host, a.port), make_handler(db, static, a.pin_file, a.poll))
    srv.daemon_threads = True
    def _brief_loop():   # 평일 08:00 아침 브리핑 (PC 시계 기준). 서버가 켜져 있는 동안 1분마다 확인하고, 꺼져 있었으면 화면이 처음 열릴 때 보충한다
        while True:
            try: db.chat_briefing_if_due()
            except Exception as e: print('[오류] 브리핑:', e)
            time.sleep(60)
    threading.Thread(target=_brief_loop, daemon=True).start()
    print('=' * 56)
    print(f' SAIL:41 (지휘역량강화센터 일정·업무 보드) 서버 v{VERSION} 실행 중')
    print(f'   화면 폴더 : {static}')
    print(f'   DB 파일   : {a.db}')
    print(f'   편집 PIN  : {a.pin_file}')
    print(f'   조회 PIN  : {view_pin_path(a.pin_file)}  (비우면 누구나 조회)')
    print(f'   본인 접속 : http://localhost:{a.port}')
    for ip in lan_ips(): print(f'   팀원 접속 : http://{ip}:{a.port}')
    print(' 종료하려면 이 창을 닫거나 Ctrl+C')
    print('=' * 56)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
