# Supabase REST(RPC) 모의 서버. server/supabase.sql 의 함수 시그니처를 읽어 파라미터 이름을 엄격 검증한다.
# 사용: python3 -I scripts/mock_supabase.py server/supabase.sql   (포트 8766, anon key "test-anon")
import json, re, sys, datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
sql=open(sys.argv[1],encoding='utf-8').read()
SIGS={}
for m in re.finditer(r'create or replace function public\.(ictc_\w+)\((.*?)\)\s*returns', sql, re.S):
    params=[p.strip().split()[0] for p in m.group(2).split(',') if p.strip()]
    SIGS[m.group(1)]=params
EDIT='1234'; VIEW='0000'; ITEMS={}; BOARDS=[{'id':'main','name':'지휘역량강화센터'}]; USERS={}; TRASH=[]
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
    def do_GET(self): self._send(403, b'{"message":"direct table access denied"}')
    def do_POST(self):
        if self.headers.get('apikey')!='test-anon': return self._send(401,b'{"message":"no key"}')
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
                    it=g('p_item')
                    if not it.get('id'): raise ValueError('ID_REQUIRED')
                    ITEMS[it['id']]={'kind':'chat','board':room,'data':it,'u':now()}; return self._send(204)
                if g('p_id') in ITEMS: TRASH.append({'seq':len(TRASH)+1,'reason':'delete','deleted_at':now(),**ITEMS.pop(g('p_id'))})
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
                view(g('p_pin') or ''); it=g('p_item')
                if g('p_kind') not in ('schedule','tasks'): raise ValueError('KIND_INVALID')
                if not it.get('id'): raise ValueError('ID_REQUIRED')
                ITEMS[it['id']]={'kind':g('p_kind'),'board':g('p_board') or 'main','data':it,'u':now()}; return self._send(204)
            if fn=='ictc_delete':
                view(g('p_pin') or '')
                if g('p_kind') not in ('schedule','tasks'): raise ValueError('KIND_INVALID')
                if g('p_id') in ITEMS: TRASH.append({'seq':len(TRASH)+1,'reason':'delete','deleted_at':now(),**ITEMS.pop(g('p_id'))})
                return self._send(204)
            if fn=='ictc_replace':
                edit(g('p_pin')); board=g('p_board') or 'main'
                for k in [k for k,v in ITEMS.items() if v['kind']==g('p_kind') and v['board']==board]: ITEMS.pop(k)
                for x in g('p_items'): ITEMS[x['id']]={'kind':g('p_kind'),'board':board,'data':x,'u':now()}
                return self._send(204)
            if fn=='ictc_board_add':
                edit(g('p_pin'))
                if any(x['id']==g('p_id') for x in BOARDS): raise ValueError('BOARD_EXISTS')
                BOARDS.append({'id':g('p_id'),'name':g('p_name')}); return self._send(204)
            if fn=='ictc_board_rename':
                edit(g('p_pin')); [x.update(name=g('p_name')) for x in BOARDS if x['id']==g('p_id')]; return self._send(204)
            if fn=='ictc_board_delete':
                edit(g('p_pin'))
                if g('p_id')=='main': raise ValueError('BOARD_PROTECTED')
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
            if fn=='ictc_user_rename':
                edit(g('p_edit_pin'))
                if g('p_id') not in USERS: raise ValueError('USER_NOT_FOUND')
                if len((g('p_name') or '').strip())<2: raise ValueError('NAME_REQUIRED')
                USERS[g('p_id')]['name']=g('p_name').strip(); return self._send(204)
            if fn=='ictc_personal_list':
                user(g('p_id'),g('p_pin')); rows=[{'data':v['data'],'updated_at':v['u']} for v in ITEMS.values() if v['kind']=='personal' and v['board']==g('p_id')]
                return self._send(200,json.dumps(rows).encode())
            if fn=='ictc_personal_save':
                user(g('p_id'),g('p_pin')); it=g('p_item'); ITEMS[it['id']]={'kind':'personal','board':g('p_id'),'data':it,'u':now()}; return self._send(204)
            if fn=='ictc_personal_delete': user(g('p_id'),g('p_pin')); ITEMS.pop(g('p_item_id'),None); return self._send(204)
            if fn=='ictc_users_list':
                edit(g('p_edit_pin')); rows=[{'id':i,'name':u['name'],'created_at':now(),'item_count':sum(1 for v in ITEMS.values() if v['kind']=='personal' and v['board']==i)} for i,u in USERS.items()]
                return self._send(200,json.dumps(rows).encode())
            if fn=='ictc_deleted_list':
                edit(g('p_edit_pin')); rows=[{'seq':t['seq'],'id':t['data']['id'],'kind':t['kind'],'board':t['board'],'data':t['data'],'updated_at':t['u'],'deleted_at':t['deleted_at'],'reason':t['reason']} for t in reversed(TRASH) if (not g('p_kind') or t['kind']==g('p_kind')) and (not g('p_board') or t['board']==g('p_board'))]
                return self._send(200,json.dumps(rows).encode())
            if fn=='ictc_restore':
                edit(g('p_edit_pin')); t=next((t for t in TRASH if t['seq']==g('p_seq')),None)
                if not t: raise ValueError('DELETED_NOT_FOUND')
                TRASH.remove(t); ITEMS[t['data']['id']]={'kind':t['kind'],'board':t['board'],'data':t['data'],'u':now()}; return self._send(204)
            if fn=='ictc_user_delete':
                edit(g('p_edit_pin'))
                if g('p_id') not in USERS: raise ValueError('USER_NOT_FOUND')
                USERS.pop(g('p_id')); [ITEMS.pop(k) for k,v in list(ITEMS.items()) if v['kind']=='personal' and v['board']==g('p_id')]; return self._send(204)
            return self._send(404,b'{"message":"unhandled"}')
        except ValueError as e: return self.err(str(e))
print('mock sigs:', len(SIGS)); sys.stdout.flush()
HTTPServer(('localhost',8766),H).serve_forever()
