"""Authenticated routes in Strata; untrusted work stays in the isolated worker."""
import http.client
import json
import re


def handle(handler, path, body=None):
    if body is None:
        if not re.fullmatch(r'/workspace/artifacts/[0-9a-f]{32}', path):
            handler._json(404, {'error': {'message': 'Not found'}})
            return
        method, target = 'GET', path.removeprefix('/workspace')
    else:
        if path != '/workspace/extract':
            handler._json(404, {'error': {'message': 'Not found'}})
            return
        method, target = 'POST', '/extract'
    conn = http.client.HTTPConnection('127.0.0.1', 8092, timeout=40)
    try:
        conn.request(method, target, body, {'Content-Type': 'application/json'})
        response = conn.getresponse()
        data = response.read(12_000_001)
        if len(data) > 12_000_000:
            raise ValueError('Worker response too large')
        handler.send_response(response.status)
        handler.send_header('Content-Type', 'application/octet-stream' if body is None else 'application/json')
        if body is None:
            handler.send_header('Content-Disposition', 'attachment; filename="artifact"')
        handler.send_header('X-Content-Type-Options', 'nosniff')
        handler.send_header('Cache-Control', 'no-store')
        handler.send_header('Content-Length', str(len(data)))
        handler.end_headers()
        handler.wfile.write(data)
    except (OSError, ValueError):
        handler._json(502, {'error': {'message': 'Analysis worker unavailable'}})
    finally:
        conn.close()
