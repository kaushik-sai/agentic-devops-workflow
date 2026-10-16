import http.server, ssl, json, sys
issues = json.load(open(sys.argv[1]))
log = open(sys.argv[2], 'a')
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        key = self.path.split('/issue/')[1].split('?')[0]
        log.write(f"GET {self.path} auth={'Authorization' in self.headers}\n"); log.flush()
        if key in issues:
            b = json.dumps(issues[key]).encode(); self.send_response(200)
        else:
            b = b'{"errorMessages":["Issue does not exist"]}'; self.send_response(404)
        self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        n = int(self.headers['Content-Length']); body = self.rfile.read(n).decode()
        log.write(f"POST {self.path} {body}\n"); log.flush()
        self.send_response(201); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(b'{"id":"1"}')
    def log_message(self,*a): pass
s = http.server.HTTPServer(('127.0.0.1', 8443), H)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain('cert.pem','key.pem')
s.socket = ctx.wrap_socket(s.socket, server_side=True); s.serve_forever()
