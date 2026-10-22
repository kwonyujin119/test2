# -*- coding: utf-8 -*-
r"""
지휘역량강화센터 일정·업무 보드 로컬 서버 (Python 3.8+ 표준 라이브러리만 사용)

프로그램 폴더 (압축 푼 위치, 어디든 상관없음):
  ictc_server.py   이 파일
  start.bat        더블클릭 실행용 (DB 위치를 D:\일정표,주요업무\ 로 지정)
  site\            웹앱 화면 (index.html, config.js, data\, checklist\, assets\)

데이터 폴더 (start.bat 이 자동 생성):  D:\일정표,주요업무\
  ictc.db          SQLite 데이터베이스 - 전체 데이터 (이 파일만 백업하면 됨)
  backups\         기동할 때마다 날짜별 사본 자동 생성 (최근 7개 보관)
  pin.txt          편집 PIN (처음 실행 시 1234 로 생성, 메모장으로 수정)
  view_pin.txt     조회 PIN (처음 실행 시 0000 으로 생성). 내용을 비우면 누구나 조회 가능

실행:  python ictc_server.py  [--port 8080] [--db 경로] [--pin-file 경로] [--static 경로]
접속:  본인  http://localhost:8080
       팀원  http://<이 PC의 IP>:8080
"""
import argparse, glob, hashlib, hmac, json, os, secrets, socket, sqlite3, sys, threading, time
from collections import deque
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
KINDS = ('schedule', 'tasks')
VERSION = '2.1'
BACKUP_KEEP = 7            # 기동 시 날짜별 백업 보관 개수
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
        con.commit(); con.close()

    def _con(self):
        return sqlite3.connect(self.path, check_same_thread=False)

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
        self._run(lambda c: c.execute('''insert into items(id, kind, board, data, updated_at) values(?,?,?,?,?)
            on conflict(id) do update set data=excluded.data, kind=excluded.kind, board=excluded.board, updated_at=excluded.updated_at''',
                                      (item['id'], kind, board, json.dumps(item, ensure_ascii=False), self.now())))

    def delete(self, kind, board, id_):
        self._run(lambda c: c.execute('delete from items where id=? and kind=? and board=?', (id_, kind, board)))

    def replace(self, kind, board, items):
        now = self.now()
        def fn(c):
            c.execute('delete from items where kind=? and board=?', (kind, board))
            for x in items:
                x.setdefault('id', f'{int(time.time()*1000):x}{os.urandom(3).hex()}')
                c.execute('insert into items(id, kind, board, data, updated_at) values(?,?,?,?,?)', (x['id'], kind, board, json.dumps(x, ensure_ascii=False), now))
        self._run(fn)

    # ----- 대시보드 -----
    def boards(self):
        rows = self._run(lambda c: c.execute("select id, name from boards order by (id <> 'main'), created_at").fetchall())
        return [{'id': i, 'name': n} for i, n in rows]

    def board_add(self, id_, name):
        if not name.strip(): raise ApiError('NAME_REQUIRED')
        def fn(c):
            if c.execute('select 1 from boards where id=?', (id_,)).fetchone(): raise ApiError('BOARD_EXISTS')
            c.execute('insert into boards(id, name, created_at) values(?,?,?)', (id_, name.strip(), self.now()))
        self._run(fn)

    def board_rename(self, id_, name):
        if not name.strip(): raise ApiError('NAME_REQUIRED')
        self._run(lambda c: c.execute('update boards set name=? where id=?', (name.strip(), id_)))

    def board_delete(self, id_):
        if id_ == 'main': raise ApiError('BOARD_PROTECTED')
        def fn(c):
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
            c.execute("delete from items where kind='personal' and board=?", (id_,))
            if c.execute('delete from users where id=?', (id_,)).rowcount == 0: raise ApiError('USER_NOT_FOUND', 404)
        self._run(fn)

    def user_check(self, id_, pin):
        row = self._run(lambda c: c.execute('select pin_hash, name from users where id=?', (id_,)).fetchone())
        if not row: raise ApiError('USER_NOT_FOUND', 403)
        if not check_hash(pin or '', row[0]): raise ApiError('USER_PIN_INVALID', 403)
        return row[1]

    def user_register(self, id_, name, pin):
        if len(id_ or '') < 4: raise ApiError('USER_ID_INVALID')
        if not (name or '').strip(): raise ApiError('NAME_REQUIRED')
        if len((pin or '').strip()) < 2: raise ApiError('PIN_TOO_SHORT')
        def fn(c):
            if c.execute('select 1 from users where id=?', (id_,)).fetchone(): raise ApiError('USER_EXISTS')
            c.execute('insert into users(id, name, pin_hash, created_at) values(?,?,?,?)', (id_, name.strip(), hash_pin(pin), self.now()))
        self._run(fn); return name.strip()

    def user_set_pin(self, id_, new):
        if len((new or '').strip()) < 2: raise ApiError('PIN_TOO_SHORT')
        self._run(lambda c: c.execute('update users set pin_hash=?, name=? where id=?', (hash_pin(new), new.strip(), id_)))

    def personal_list(self, id_):
        return self.list('personal', id_)

    def personal_save(self, id_, item):
        self.save('personal', id_, item)

    def personal_delete(self, id_, item_id):
        self.delete('personal', id_, item_id)


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
            if not self.path.startswith('/api/'):
                self.send_header('Cache-Control', 'no-cache')
            super().end_headers()

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
                raise ApiError('NOT_FOUND', 404)
            except ApiError as e:
                return self._json(e.status, {'message': e.code})

        def do_POST(self):
            u = urlparse(self.path)
            try:
                if not u.path.startswith('/api/'): raise ApiError('NOT_FOUND', 404)
                try:
                    n = int(self.headers.get('Content-Length') or 0)
                    b = json.loads(self.rfile.read(n) or b'{}')
                except Exception:
                    raise ApiError('JSON_INVALID')
                fn = u.path[5:]
                kind = b.get('kind'); board = (b.get('board') or 'main')
                if fn in ('save', 'delete', 'replace'):
                    self.require_edit(b.get('pin'))
                    if kind not in KINDS: raise ApiError('KIND_INVALID')
                    if fn == 'save':
                        item = b.get('item') or {}
                        if not item.get('id'): raise ApiError('ID_REQUIRED')
                        db.save(kind, board, item)
                    elif fn == 'delete':
                        db.delete(kind, board, str(b.get('id', '')))
                    else:
                        items = b.get('items')
                        if not isinstance(items, list): raise ApiError('ITEMS_REQUIRED')
                        db.replace(kind, board, items)
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
                if fn == 'users_list':
                    self.require_edit(b.get('pin')); return self._json(200, db.users_list())
                if fn == 'user_delete':
                    self.require_edit(b.get('pin')); db.user_delete(str(b.get('id', ''))); return self._json(204)
                if fn in ('personal_list', 'personal_save', 'personal_delete'):
                    uid = str(b.get('id', '')); self.user_check(uid, str(b.get('user_pin', '')))
                    if fn == 'personal_list': return self._json(200, db.personal_list(uid))
                    if fn == 'personal_save':
                        item = b.get('item') or {}
                        if not item.get('id'): raise ApiError('ID_REQUIRED')
                        db.personal_save(uid, item)
                    else:
                        db.personal_delete(uid, str(b.get('item_id', '')))
                    return self._json(204)
                raise ApiError('NOT_FOUND', 404)
            except ApiError as e:
                return self._json(e.status, {'message': e.code})
            except Exception as e:
                return self._json(500, {'message': str(e)})

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
    ap = argparse.ArgumentParser(description='일정·업무 보드 로컬 서버')
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
    print('=' * 56)
    print(f' 지휘역량강화센터 일정·업무 보드 서버 v{VERSION} 실행 중')
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
