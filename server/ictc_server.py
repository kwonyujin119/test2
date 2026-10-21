# -*- coding: utf-8 -*-
r"""
ICTC 일정·업무 보드 로컬 서버 (Python 3.8+ 표준 라이브러리만 사용)

폴더 구성 예 (D:\ICTC일정표,주요업무\):
  ictc_server.py   이 파일
  start.bat        더블클릭 실행용
  pin.txt          편집 PIN (처음 실행 시 1234 로 생성, 메모장으로 수정)
  ictc.db          SQLite 데이터베이스 (자동 생성)
  ictc\            웹앱 화면 (저장소의 ictc 폴더를 그대로 복사)

실행:  python ictc_server.py  [--port 8080] [--db 경로] [--static 경로]
접속:  본인  http://localhost:8080
       팀원  http://<이 PC의 IP>:8080
r"""
import argparse, json, os, socket, sqlite3, sys, threading, time
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))


def find_static():
    for c in (os.path.join(HERE, 'ictc'), os.path.join(os.path.dirname(HERE), 'ictc')):
        if os.path.isfile(os.path.join(c, 'index.html')):
            return c
    return None


def read_pin(path):
    if not os.path.exists(path):
        with open(path, 'w', encoding='utf-8') as f:
            f.write('1234\n')
        print(f'[안내] 편집 PIN 파일을 만들었습니다: {path}  (기본 PIN 1234, 메모장으로 바꾸세요)')
    with open(path, encoding='utf-8-sig') as f:
        return f.read().strip()


class DB:
    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()
        con = self._con()
        con.execute('pragma journal_mode=wal')
        con.execute('''create table if not exists items (
            id text primary key, kind text not null, data text not null, updated_at text not null)''')
        con.commit(); con.close()

    def _con(self):
        return sqlite3.connect(self.path, check_same_thread=False)

    @staticmethod
    def now():
        return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')

    def list(self, kind):
        with self.lock:
            con = self._con()
            rows = con.execute('select data, updated_at from items where kind=? order by updated_at desc', (kind,)).fetchall()
            con.close()
        return [{'data': json.loads(d), 'updated_at': u} for d, u in rows]

    def save(self, kind, item):
        with self.lock:
            con = self._con()
            con.execute('''insert into items(id, kind, data, updated_at) values(?,?,?,?)
                on conflict(id) do update set data=excluded.data, kind=excluded.kind, updated_at=excluded.updated_at''',
                        (item['id'], kind, json.dumps(item, ensure_ascii=False), self.now()))
            con.commit(); con.close()

    def delete(self, kind, id_):
        with self.lock:
            con = self._con()
            con.execute('delete from items where id=? and kind=?', (id_, kind))
            con.commit(); con.close()

    def replace(self, kind, items):
        now = self.now()
        with self.lock:
            con = self._con()
            con.execute('delete from items where kind=?', (kind,))
            for x in items:
                x.setdefault('id', f'{int(time.time()*1000):x}{os.urandom(3).hex()}')
                con.execute('insert into items(id, kind, data, updated_at) values(?,?,?,?)',
                            (x['id'], kind, json.dumps(x, ensure_ascii=False), now))
            con.commit(); con.close()


def make_handler(db, static_dir, pin_path, poll):
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
            self.end_headers()
            self.wfile.write(body)

        def end_headers(self):
            if not self.path.startswith('/api/'):
                self.send_header('Cache-Control', 'no-cache')
            super().end_headers()

        def do_GET(self):
            u = urlparse(self.path)
            if u.path == '/config.js':
                body = ('window.ICTC_CONFIG = { apiUrl: "", pollSeconds: %d };\n' % poll).encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/javascript; charset=utf-8')
                self.send_header('Cache-Control', 'no-store')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers(); self.wfile.write(body); return
            if u.path == '/api/items':
                kind = parse_qs(u.query).get('kind', [''])[0]
                if kind not in ('schedule', 'tasks'):
                    return self._json(400, {'message': 'kind 오류'})
                return self._json(200, db.list(kind))
            if u.path == '/api/health':
                return self._json(200, {'ok': True, 'time': db.now()})
            if u.path.startswith('/api/'):
                return self._json(404, {'message': 'not found'})
            return super().do_GET()

        def do_POST(self):
            u = urlparse(self.path)
            if not u.path.startswith('/api/'):
                return self._json(404, {'message': 'not found'})
            try:
                n = int(self.headers.get('Content-Length') or 0)
                body = json.loads(self.rfile.read(n) or b'{}')
            except Exception:
                return self._json(400, {'message': 'JSON 오류'})
            if str(body.get('pin', '')).strip() != read_pin(pin_path):
                return self._json(403, {'message': 'PIN_INVALID'})
            kind = body.get('kind')
            if kind not in ('schedule', 'tasks'):
                return self._json(400, {'message': 'kind 오류'})
            try:
                if u.path == '/api/save':
                    item = body.get('item') or {}
                    if not item.get('id'):
                        return self._json(400, {'message': 'ID_REQUIRED'})
                    db.save(kind, item)
                elif u.path == '/api/delete':
                    db.delete(kind, str(body.get('id', '')))
                elif u.path == '/api/replace':
                    items = body.get('items')
                    if not isinstance(items, list):
                        return self._json(400, {'message': 'items 배열 필요'})
                    db.replace(kind, items)
                else:
                    return self._json(404, {'message': 'not found'})
            except Exception as e:
                return self._json(500, {'message': str(e)})
            return self._json(204)

    return Handler


def lan_ips():
    ips = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith('127.'):
                ips.add(ip)
    except Exception:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(('10.255.255.255', 1))
        ips.add(s.getsockname()[0]); s.close()
    except Exception:
        pass
    return sorted(ips)


def main():
    ap = argparse.ArgumentParser(description='ICTC 보드 로컬 서버')
    ap.add_argument('--port', type=int, default=8080)
    ap.add_argument('--db', default=os.path.join(HERE, 'ictc.db'))
    ap.add_argument('--pin-file', default=os.path.join(HERE, 'pin.txt'))
    ap.add_argument('--static', default=None, help='ictc 폴더 경로 (기본: 자동 탐색)')
    ap.add_argument('--poll', type=int, default=15, help='팀원 화면 자동 새로고침 주기(초)')
    ap.add_argument('--host', default='0.0.0.0', help='127.0.0.1 로 바꾸면 이 PC에서만 접속 가능')
    a = ap.parse_args()

    static = a.static or find_static()
    if not static:
        print('[오류] ictc 폴더(index.html)를 찾을 수 없습니다. 이 파일 옆에 ictc 폴더를 복사하세요.')
        sys.exit(1)
    db = DB(a.db)
    read_pin(a.pin_file)
    srv = ThreadingHTTPServer((a.host, a.port), make_handler(db, static, a.pin_file, a.poll))
    srv.daemon_threads = True
    print('=' * 56)
    print(' ICTC 일정·업무 보드 서버 실행 중')
    print(f'   화면 폴더 : {static}')
    print(f'   DB 파일   : {a.db}')
    print(f'   PIN 파일  : {a.pin_file}')
    print(f'   본인 접속 : http://localhost:{a.port}')
    for ip in lan_ips():
        print(f'   팀원 접속 : http://{ip}:{a.port}')
    print(' 종료하려면 이 창을 닫거나 Ctrl+C')
    print('=' * 56)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
