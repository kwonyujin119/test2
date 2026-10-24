# Supabase REST(RPC) 모의 서버. server/supabase.sql 의 함수 시그니처를 읽어 파라미터 이름을 엄격 검증한다.
# 사용: python3 -I scripts/mock_supabase.py server/supabase.sql [포트]   (기본 포트 8766, anon key "test-anon")
import json, re, sys, datetime, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'server')); from ictc_server import briefing_text   # 브리핑 문장은 로컬 서버와 같은 코드
from http.server import BaseHTTPRequestHandler, HTTPServer
sql=open(sys.argv[1],encoding='utf-8').read()
SIGS={}
for m in re.finditer(r'create or replace function public\.(ictc_\w+)\((.*?)\)\s*returns', sql, re.S):
    params=[p.strip().split()[0] for p in m.group(2).split(',') if p.strip()]
    SIGS[m.group(1)]=params
EDIT='1234'; VIEW='0000'; ITEMS={}; BOARDS=[{'id':'main','name':'지휘역량강화센터'}]; USERS={}; TRASH=[]
FILES={}
# Storage 버킷 sail41 흉내: supabase.sql 의 allowed_mime_types · 업로드 정책 경로 형식(chat/<톡방>/… 또는 items/<종류>/…)과 같게
MIMES={'image/jpeg','image/png','image/gif','image/webp','image/heic','image/heif','application/pdf','text/plain','text/csv','application/zip','application/x-hwp','application/haansofthwp','application/vnd.hancom.hwp','application/vnd.hancom.hwpx','application/x-hwpx','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation','application/octet-stream'}
KEY_RE=re.compile(r'^(chat/[A-Za-z0-9_.%-]{1,64}|items/(schedule|tasks|personal))/[A-Za-z0-9_.-]{1,80}$')
def check_item(it):   # supabase.sql ictc_check_item 과 동일
    if not isinstance(it,dict) or not it.get('id'): raise ValueError('ID_REQUIRED')
    if len(str(it['id']))>100 or len(json.dumps(it,ensure_ascii=False).encode())>65536: raise ValueError('ITEM_TOO_LARGE')
    return it
def trash(k, reason='delete'):
    if k in ITEMS: TRASH.append({'seq':len(TRASH)+1,'reason':reason,'deleted_at':now(),**ITEMS.pop(k)})
def board_ok(b):
    if not any(x['id']==b for x in BOARDS): raise ValueError('BOARD_NOT_FOUND')
ROOMS={'ictc':{'name':'지휘역량강화센터','code':'5948','sort':1},'edu-support':{'name':'교육지원과','code':'5914','sort':2},'edu-plan':{'name':'교육기획과','code':'5926','sort':3},'training':{'name':'훈련운영과','code':'5527','sort':4}}
def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
class H(BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def _send(self,code,body=b''):
        self.send_response(code); self.send_header('Content-Type','application/json')
        for k,v in (('Access-Control-Allow-Origin','*'),('Access-Control-Allow-Headers','*'),('Access-Control-Allow-Methods','*')): self.send_header(k,v)
        self.end_headers(); self.wfile.write(body)
    def err(self,code): self._send(400, json.dumps({'message':code}).encode())
    def do_OPTIONS(self): self._send(204)
    def do_GET(self):
        if self.path.startswith('/storage/v1/object/public/sail41/'):
            f=FILES.get(self.path.split('/storage/v1/object/public/sail41/',1)[1])
            if not f: return self._send(404, b'{"message":"not found"}')
            self.send_response(200); self.send_header('Content-Type', f['type']); self.send_header('Access-Control-Allow-Origin','*'); self.send_header('Content-Length', str(len(f['data']))); self.end_headers(); self.wfile.write(f['data']); return
        self._send(403, b'{"message":"direct table access denied"}')
    def do_POST(self):
        if self.headers.get('apikey')!='test-anon': return self._send(401,b'{"message":"no key"}')
        if self.path.startswith('/storage/v1/object/sail41/'):   # Storage 업로드 흉내: chat/ 경로만, 10MB 제한
            key=self.path.split('/storage/v1/object/sail41/',1)[1]; n=int(self.headers.get('Content-Length',0)); ctype=self.headers.get('Content-Type','application/octet-stream').split(';')[0].strip()
            if not KEY_RE.match(key): return self._send(400, b'{"message":"new row violates row-level security policy"}')
            if n>104857600: return self._send(413, b'{"message":"Payload too large"}')
            if ctype not in MIMES: return self._send(415, json.dumps({'statusCode':'415','error':'invalid_mime_type','message':f'mime type {ctype} is not supported'}).encode())
            FILES[key]={'type':ctype,'data':self.rfile.read(n)}
            return self._send(200, json.dumps({'Key':'sail41/'+key}).encode())
        n=int(self.headers.get('Content-Length',0)); b=json.loads(self.rfile.read(n) or b'{}'); fn=self.path.rsplit('/',1)[-1]
        if fn not in SIGS: return self._send(404, json.dumps({'message':f'function {fn} not found'}).encode())
        bad=[k for k in b if k not in SIGS[fn]]
        if bad: return self._send(404, json.dumps({'message':f'{fn}: unknown params {bad}; expected {SIGS[fn]}'}).encode())
        g=b.get
        def view(p):
            if VIEW and p not in (VIEW,EDIT): raise ValueError('VIEW_PIN_INVALID' if p else 'VIEW_PIN_REQUIRED')
        def edit(p):
            if p!=EDIT: raise ValueError('PIN_INVALID')
        def user(i,p):
            u=USERS.get(i)
            if not u: raise ValueError('USER_NOT_FOUND')
            if u['pin']!=p: raise ValueError('USER_PIN_INVALID')
        try:
            if fn=='ictc_list':
                view(g('p_pin') or ''); board=g('p_board') or 'main'
                if g('p_kind') not in ('schedule','tasks'): raise ValueError('KIND_INVALID')
                rows=[{'data':v['data'],'updated_at':v['u']} for v in ITEMS.values() if v['kind']==g('p_kind') and v['board']==board]
                return self._send(200,json.dumps(sorted(rows,key=lambda r:r['updated_at'],reverse=True)).encode())
            if fn=='ictc_boards': view(g('p_pin') or ''); return self._send(200,json.dumps(BOARDS).encode())
            if fn=='ictc_chat_briefing_post':   # 평일 8시 이후, 톡방마다 하루 한 번
                view(g('p_pin') or ''); t=datetime.datetime.now(); cnt=0
                if t.weekday()>=5 or t.hour<8: return self._send(200,b'0')
                for rid,room in ROOMS.items():
                    mid=f"brief-{rid}-{t.strftime('%Y%m%d')}"
                    if mid in ITEMS: continue
                    board=next((b['id'] for b in BOARDS if b['name']==room['name']),'main')
                    txt=briefing_text([v['data'] for v in ITEMS.values() if v['kind']=='schedule' and v['board']==board],[v['data'] for v in ITEMS.values() if v['kind']=='tasks' and v['board']==board],room['name'],t.date())
                    ITEMS[mid]={'kind':'chat','board':rid,'data':{'id':mid,'text':txt,'name':'브리핑','dev':'bot','bot':True,'created':now()},'u':now()}; cnt+=1
                return self._send(200,str(cnt).encode())
            if fn=='ictc_chat_rooms': view(g('p_pin') or ''); return self._send(200,json.dumps([{'id':k,'name':v['name'],'sort':v['sort']} for k,v in sorted(ROOMS.items(),key=lambda kv:kv[1]['sort'])]).encode())
            if fn in ('ictc_chat_join','ictc_chat_list','ictc_chat_save','ictc_chat_delete'):
                view(g('p_pin') or ''); room=g('p_room')
                if room not in ROOMS: raise ValueError('CHAT_ROOM_NOT_FOUND')
                if (g('p_code') or '')!=ROOMS[room]['code']: raise ValueError('CHAT_CODE_INVALID')
                if fn=='ictc_chat_join': return self._send(200,json.dumps(ROOMS[room]['name']).encode())
                if fn=='ictc_chat_list':
                    rows=[{'data':v['data'],'updated_at':v['u']} for v in ITEMS.values() if v['kind']=='chat' and v['board']==room]
                    return self._send(200,json.dumps(sorted(rows,key=lambda r:r['updated_at'],reverse=True)).encode())
                if fn=='ictc_chat_save':
                    it=check_item(g('p_item')); old=ITEMS.get(it['id'])
                    if it.get('deleted') is True and old and old['kind']=='chat' and old['data'].get('deleted') is not True: TRASH.append({'seq':len(TRASH)+1,'reason':'delete','deleted_at':now(),**old})   # 삭제 자리표시 → 원문 휴지통
                    if old and (old['kind']!='chat' or old['board']!=room): return self._send(204)
                    ITEMS[it['id']]={'kind':'chat','board':room,'data':it,'u':now()}; return self._send(204)
                if not g('p_id'): raise ValueError('ID_REQUIRED')
                trash(g('p_id'))
                return self._send(204)
            if fn=='ictc_chat_set_code':
                edit(g('p_edit_pin'))
                if g('p_room') not in ROOMS: raise ValueError('CHAT_ROOM_NOT_FOUND')
                if len((g('p_new') or '').strip())<4: raise ValueError('CHAT_CODE_TOO_SHORT')
                ROOMS[g('p_room')]['code']=g('p_new').strip(); return self._send(204)
            if fn=='ictc_chat_room_rename':
                edit(g('p_edit_pin'))
                if g('p_room') not in ROOMS: raise ValueError('CHAT_ROOM_NOT_FOUND')
                ROOMS[g('p_room')]['name']=(g('p_name') or '').strip(); return self._send(204)
            if fn=='ictc_chat_room_add':
                edit(g('p_edit_pin'))
                if g('p_id') in ROOMS: raise ValueError('CHAT_ROOM_EXISTS')
                if len((g('p_code') or '').strip())<4: raise ValueError('CHAT_CODE_TOO_SHORT')
                ROOMS[g('p_id')]={'name':g('p_name'),'code':g('p_code').strip(),'sort':len(ROOMS)+1}; return self._send(204)
            if fn=='ictc_chat_room_delete':
                edit(g('p_edit_pin'))
                if g('p_room') not in ROOMS: raise ValueError('CHAT_ROOM_NOT_FOUND')
                for k in [k for k,v in ITEMS.items() if v['kind']=='chat' and v['board']==g('p_room')]: ITEMS.pop(k)
                ROOMS.pop(g('p_room')); return self._send(204)
            if fn=='ictc_save':
                view(g('p_pin') or ''); it=check_item(g('p_item')); board=g('p_board') or 'main'
                if g('p_kind') not in ('schedule','tasks'): raise ValueError('KIND_INVALID')
                board_ok(board)
                if it['id'] in ITEMS and ITEMS[it['id']]['kind'] not in ('schedule','tasks'): return self._send(204)
                ITEMS[it['id']]={'kind':g('p_kind'),'board':board,'data':it,'u':now()}; return self._send(204)
            if fn=='ictc_delete':
                view(g('p_pin') or '')
                if g('p_kind') not in ('schedule','tasks'): raise ValueError('KIND_INVALID')
                if not g('p_id'): raise ValueError('ID_REQUIRED')
                trash(g('p_id'))
                if g('p_kind')=='schedule': trash('sch-'+g('p_id'))   # 연동 주요업무 카드도 함께
                return self._send(204)
            if fn=='ictc_replace':
                edit(g('p_pin')); board=g('p_board') or 'main'; items=g('p_items')
                if g('p_kind') not in ('schedule','tasks'): raise ValueError('KIND_INVALID')
                if not isinstance(items,list): raise ValueError('ITEMS_REQUIRED')
                if len(items)>10000: raise ValueError('ITEM_TOO_LARGE')
                board_ok(board)
                for k in [k for k,v in ITEMS.items() if v['kind']==g('p_kind') and v['board']==board]: trash(k,'replace')
                for x in items:
                    x.setdefault('id', now()); check_item(x)
                    if x['id'] not in ITEMS: ITEMS[x['id']]={'kind':g('p_kind'),'board':board,'data':x,'u':now()}
                return self._send(204)
            if fn=='ictc_board_add':
                edit(g('p_pin'))
                if any(x['id']==g('p_id') for x in BOARDS): raise ValueError('BOARD_EXISTS')
                BOARDS.append({'id':g('p_id'),'name':g('p_name')}); return self._send(204)
            if fn=='ictc_board_rename':
                edit(g('p_pin')); board_ok(g('p_id')); [x.update(name=g('p_name')) for x in BOARDS if x['id']==g('p_id')]; return self._send(204)
            if fn=='ictc_board_delete':
                edit(g('p_pin'))
                if g('p_id')=='main': raise ValueError('BOARD_PROTECTED')
                for k in [k for k,v in ITEMS.items() if v['kind'] in ('schedule','tasks') and v['board']==g('p_id')]: trash(k,'board_delete')
                BOARDS[:]=[x for x in BOARDS if x['id']!=g('p_id')]; return self._send(204)
            if fn=='ictc_user_register':
                view(g('p_view_pin') or '')
                if g('p_id') in USERS: raise ValueError('USER_EXISTS')
                if len((g('p_pin') or '').strip())<4: raise ValueError('PIN_TOO_SHORT')   # supabase.sql v4 와 동일 (비밀번호 4자리)
                USERS[g('p_id')]={'name':g('p_name'),'pin':g('p_pin')}; return self._send(200,json.dumps(g('p_name')).encode())
            if fn=='ictc_user_login': user(g('p_id'),g('p_pin')); return self._send(200,json.dumps(USERS[g('p_id')]['name']).encode())
            if fn=='ictc_user_set_pin':
                user(g('p_id'),g('p_old'))
                if len((g('p_new') or '').strip())<4: raise ValueError('PIN_TOO_SHORT')
                USERS[g('p_id')]['pin']=g('p_new').strip(); return self._send(204)
            if fn=='ictc_user_reset_pin':
                edit(g('p_edit_pin'))
                if g('p_id') not in USERS: raise ValueError('USER_NOT_FOUND')
                if len((g('p_new') or '').strip())<4: raise ValueError('PIN_TOO_SHORT')
                USERS[g('p_id')]['pin']=g('p_new').strip(); return self._send(204)
            if fn=='ictc_user_set_name':
                user(g('p_id'),g('p_pin'))
                if len((g('p_name') or '').strip())<2: raise ValueError('NAME_REQUIRED')
                USERS[g('p_id')]['name']=g('p_name').strip()[:20]; return self._send(204)
            if fn=='ictc_user_rename':
                edit(g('p_edit_pin'))
                if g('p_id') not in USERS: raise ValueError('USER_NOT_FOUND')
                if len((g('p_name') or '').strip())<2: raise ValueError('NAME_REQUIRED')
                USERS[g('p_id')]['name']=g('p_name').strip(); return self._send(204)
            if fn=='ictc_personal_list':
                user(g('p_id'),g('p_pin')); rows=[{'data':v['data'],'updated_at':v['u']} for v in ITEMS.values() if v['kind']=='personal' and v['board']==g('p_id')]
                return self._send(200,json.dumps(rows).encode())
            if fn=='ictc_personal_save':
                user(g('p_id'),g('p_pin')); it=check_item(g('p_item'))
                if it['id'] in ITEMS and (ITEMS[it['id']]['kind']!='personal' or ITEMS[it['id']]['board']!=g('p_id')): return self._send(204)
                ITEMS[it['id']]={'kind':'personal','board':g('p_id'),'data':it,'u':now()}; return self._send(204)
            if fn=='ictc_personal_delete':
                user(g('p_id'),g('p_pin'))
                if not g('p_item_id'): raise ValueError('ID_REQUIRED')
                trash(g('p_item_id'),'personal_delete'); return self._send(204)
            if fn=='ictc_users_list':
                edit(g('p_edit_pin')); rows=[{'id':i,'name':u['name'],'created_at':now(),'item_count':sum(1 for v in ITEMS.values() if v['kind']=='personal' and v['board']==i)} for i,u in USERS.items()]
                return self._send(200,json.dumps(rows).encode())
            if fn=='ictc_deleted_list':
                edit(g('p_edit_pin')); rows=[{'seq':t['seq'],'id':t['data']['id'],'kind':t['kind'],'board':t['board'],'data':t['data'],'updated_at':t['u'],'deleted_at':t['deleted_at'],'reason':t['reason']} for t in reversed(TRASH) if (not g('p_kind') or t['kind']==g('p_kind')) and (not g('p_board') or t['board']==g('p_board'))]
                return self._send(200,json.dumps(rows).encode())
            if fn=='ictc_restore':
                edit(g('p_edit_pin')); t=next((t for t in TRASH if t['seq']==g('p_seq')),None)
                if not t: raise ValueError('DELETED_NOT_FOUND')
                if t['kind']=='personal' and t['board'] not in USERS: raise ValueError('USER_NOT_FOUND')
                if t['kind'] in ('schedule','tasks'): board_ok(t['board'])
                if t['kind']=='chat' and t['board'] not in ROOMS: raise ValueError('CHAT_ROOM_NOT_FOUND')
                TRASH.remove(t); ITEMS[t['data']['id']]={'kind':t['kind'],'board':t['board'],'data':t['data'],'u':now()}
                pid=('sch-'+t['data']['id']) if t['kind']=='schedule' else (t['data']['id'][4:] if t['kind']=='tasks' and t['data']['id'].startswith('sch-') else None)   # 연동 짝 함께 복구
                p=next((x for x in reversed(TRASH) if x['data']['id']==pid and x['board']==t['board']),None) if pid else None
                if p and pid not in ITEMS: TRASH.remove(p); ITEMS[pid]={'kind':p['kind'],'board':p['board'],'data':p['data'],'u':now()}
                return self._send(204)
            if fn=='ictc_user_delete':
                edit(g('p_edit_pin'))
                if g('p_id') not in USERS: raise ValueError('USER_NOT_FOUND')
                USERS.pop(g('p_id')); [ITEMS.pop(k) for k,v in list(ITEMS.items()) if v['kind']=='personal' and v['board']==g('p_id')]; return self._send(204)
            return self._send(404,b'{"message":"unhandled"}')
        except ValueError as e: return self.err(str(e))
        except Exception as e: return self._send(400, json.dumps({'message':f'MOCK_ERROR {type(e).__name__}: {e}'}).encode())   # 모의 서버 자체 오류도 연결 끊김 대신 응답으로
print('mock sigs:', len(SIGS)); sys.stdout.flush()
HTTPServer(('localhost', int(sys.argv[2]) if len(sys.argv) > 2 else 8766), H).serve_forever()
