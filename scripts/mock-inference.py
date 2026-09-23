#!/usr/bin/env python3
"""Explicit local UI fixture. No model, tools, credentials, logging, or outbound requests."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        if self.path != '/v1/chat/completions':
            self.send_error(404)
            return
        length = int(self.headers.get('Content-Length', '0'))
        if not 0 < length <= 65536:
            self.send_error(413)
            return
        self.rfile.read(length)
        response = json.dumps({'choices': [{'message': {'role': 'assistant', 'content':
            'Fixture response: the app connected to the local test server successfully. No language model or workplace service was used.'}, 'finish_reason': 'stop'}]}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(response)))
        self.end_headers()
        self.wfile.write(response)

print('UI fixture listening on 127.0.0.1:9931. Stop with Ctrl-C.', flush=True)
HTTPServer(('127.0.0.1', 9931), Handler).serve_forever()
