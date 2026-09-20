#!/usr/bin/env python3
"""Credential isolation, authentication, routing and output safety regression tests."""
import base64
import http.server
import shutil
import ssl
import subprocess
import threading
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import sys
sys.dont_write_bytecode = True
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request

root = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('infra_access', str(root / 'tools/infra-access/infra-access'))
spec = importlib.util.spec_from_loader(loader.name, loader)
app = importlib.util.module_from_spec(spec)
loader.exec_module(app)


class AccessTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.directory = Path(self.work.name)
        self.secret_patch = patch.object(app, 'SECRET_DIR', self.directory)
        self.secret_patch.start()
        self.addCleanup(self.secret_patch.stop)
        self.device = {'api': {'base_url': 'https://router.example', 'credential': 'router'}}

    def credential(self, data):
        app.private_write(self.directory / 'router.json', json.dumps(data))

    def test_private_file_and_no_overwrite(self):
        path = self.directory / 'secret'
        app.private_write(path, 'private')
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(app.private_read(path), 'private')
        with self.assertRaises(FileExistsError):
            app.private_write(path, 'overwrite')
        path.chmod(0o644)
        with self.assertRaises(ValueError):
            app.private_read(path)

    def test_symlink_and_fifo_refused(self):
        path = self.directory / 'target'
        app.private_write(path, 'secret')
        link = self.directory / 'link'
        link.symlink_to(path)
        with self.assertRaises(OSError):
            app.private_read(link)
        fifo = self.directory / 'fifo'
        os.mkfifo(fifo, 0o600)
        with self.assertRaises(ValueError):
            app.private_read(fifo)

    def test_repository_secret_and_traversal_refused(self):
        with patch.object(app, 'SECRET_DIR', root / 'modules/secrets'):
            with self.assertRaises(ValueError):
                app.credential_path('router')
        for name in ('../secret', '/tmp/secret', 'a/b'):
            with self.assertRaises(ValueError):
                app.credential_path(name)

    def test_no_url_credentials_or_cross_origin_paths(self):
        for base in ('http://router', 'https://user:password@router', 'https://router?token=x'):
            with self.assertRaises(ValueError):
                app.request_url(base, '/api')
        for path in ('//evil.example/api', 'https://evil.example/api', 'api', '/api#fragment'):
            with self.assertRaises(ValueError):
                app.request_url('https://router', path)
        self.assertEqual(app.request_url('https://router', '/api?q=x'), 'https://router/api?q=x')

    def test_redirect_refused(self):
        handler = app.NoRedirect()
        request = urllib.request.Request('https://router', headers={'Authorization': 'secret'})
        self.assertIsNone(handler.redirect_request(request, None, 302, '', {}, 'https://other'))

    def test_redaction(self):
        value = {'nested': [{'api_key': 'x', 'Password': 'x'}], 'message': 'echo literal-secret', 'ok': 1}
        redacted = app.scrub(value, ['literal-secret'])
        self.assertEqual(redacted['message'], 'echo [REDACTED]')
        self.assertEqual(redacted['nested'][0]['api_key'], '[REDACTED]')
        self.assertEqual(redacted['ok'], 1)

    def test_basic_write_preserves_json_and_credentials(self):
        self.credential({'type': 'basic', 'username': 'key', 'password': 'literal-secret'})
        with patch.object(app.urllib.request, 'build_opener') as factory:
            response = factory.return_value.open.return_value.__enter__.return_value
            response.status = 200
            response.read.return_value = b'{"success":true}'
            status, value, secrets = app.api_request(self.device, 'POST', '/api/write', b'{"enabled":true}')
            req = factory.return_value.open.call_args.args[0]
            self.assertEqual(req.method, 'POST')
            self.assertEqual(req.data, b'{"enabled":true}')
            self.assertEqual(req.headers['Authorization'], 'Basic ' + base64.b64encode(b'key:literal-secret').decode())
            self.assertNotIn('literal-secret', req.full_url)
            self.assertEqual(status, 200)
            self.assertTrue(value['success'])
            self.assertIn('literal-secret', secrets)
            self.assertTrue(any(isinstance(h, app.NoRedirect) for h in factory.call_args.args))
            proxy = next(h for h in factory.call_args.args if isinstance(h, urllib.request.ProxyHandler))
            self.assertEqual(proxy.proxies, {})

    def test_api_key_and_proxmox_headers(self):
        cases = [({'type': 'header', 'header': 'X-API-Key', 'value': 'key'}, 'X-api-key', 'key'),
                 ({'type': 'proxmox', 'token_id': 'agent@pve!infra', 'secret': 'secret'}, 'Authorization', 'PVEAPIToken=agent@pve!infra=secret'),
                 ({'type': 'proxmox-backup', 'token_id': 'agent@pbs!infra', 'secret': 'secret'}, 'Authorization', 'PBSAPIToken=agent@pbs!infra:secret')]
        for credential, name, expected in cases:
            with patch.object(app, 'private_read', return_value=json.dumps(credential)), patch.object(app.urllib.request, 'build_opener') as factory:
                response = factory.return_value.open.return_value.__enter__.return_value
                response.status = 200
                response.read.return_value = b'{}'
                app.api_request(self.device, 'DELETE', '/api/item')
                req = factory.return_value.open.call_args.args[0]
                self.assertEqual(req.headers[name], expected)
                self.assertEqual(req.method, 'DELETE')

    def test_tls_and_auth_errors_propagate_without_retry(self):
        self.credential({'type': 'basic', 'username': 'key', 'password': 'secret'})
        for error in (urllib.error.URLError('certificate failure'), urllib.error.HTTPError('https://router', 401, 'unauthorized', {}, None)):
            with patch.object(app.urllib.request, 'build_opener') as factory:
                factory.return_value.open.side_effect = error
                with self.assertRaises(urllib.error.URLError):
                    app.api_request(self.device, 'GET', '/api/status')
                self.assertEqual(factory.return_value.open.call_count, 1)
                if isinstance(error, urllib.error.HTTPError):
                    error.close()

    def test_real_https_trust_write_and_redirect(self):
        openssl = os.environ.get('OPENSSL') or shutil.which('openssl')
        if not openssl:
            self.skipTest('OpenSSL required for local HTTPS fixture; set OPENSSL')
        cert, key = self.directory / 'cert.pem', self.directory / 'key.pem'
        subprocess.run([openssl, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(key), '-out', str(cert), '-days', '1',
                        '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        seen = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                seen.append((self.path, self.headers.get('Authorization'),
                             self.rfile.read(int(self.headers.get('Content-Length', 0)))))
                if self.path == '/redirect':
                    self.send_response(302)
                    self.send_header('Location', '/leak')
                    self.end_headers()
                elif self.path == '/empty':
                    self.send_response(204)
                    self.end_headers()
                else:
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b'{"ok":true}')

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            self.credential({'type': 'basic', 'username': 'key', 'password': 'secret'})
            self.device['api']['base_url'] = 'https://localhost:' + str(server.server_port)
            with self.assertRaises(urllib.error.URLError):
                app.api_request(self.device, 'POST', '/write', b'{}')
            self.assertEqual(seen, [])
            self.device['api']['verify_tls'] = False
            self.assertEqual(app.api_request(self.device, 'POST', '/write', b'{}')[0], 200)
            self.device['api']['verify_tls'] = True
            self.device['api']['ca_file'] = str(cert)
            status, value, _ = app.api_request(self.device, 'POST', '/write', b'{"x":1}')
            self.assertEqual((status, value), (200, {'ok': True}))
            self.assertEqual(seen[-1], ('/write', 'Basic a2V5OnNlY3JldA==', b'{"x":1}'))
            with self.assertRaises(urllib.error.HTTPError) as rejected:
                app.api_request(self.device, 'POST', '/redirect', b'{}')
            self.assertEqual(rejected.exception.code, 302)
            rejected.exception.close()
            self.assertNotIn('/leak', [entry[0] for entry in seen])
            self.assertEqual(app.api_request(self.device, 'POST', '/empty', b'{}')[:2], (204, None))
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_strict_ssh(self):
        args = app.ssh_args({'ssh': {'host': '10.1.11.2', 'user': 'admin', 'identity_file': '~/.ssh/admin'}}, 'sudo -n true')
        self.assertIn('StrictHostKeyChecking=yes', args)
        self.assertIn('ForwardAgent=no', args)
        self.assertIn('BatchMode=yes', args)
        self.assertEqual(args[-1], 'sudo -n true')

    def test_password_ssh_preserves_trust_and_no_credential_argv(self):
        device = {'ssh': {'host': '10.1.10.11', 'user': 'admin',
                          'identity_file': '~/.ssh/admin', 'credential': 'switch'}}
        args = app.ssh_args(device, 'id')
        self.assertIn('StrictHostKeyChecking=yes', args)
        self.assertIn('BatchMode=no', args)
        self.assertIn('PreferredAuthentications=password', args)
        self.assertIn('NumberOfPasswordPrompts=1', args)
        self.assertNotIn('switch', args)

    def test_askpass_reads_private_profile_and_refuses_public_file(self):
        path = self.directory / 'ssh.json'
        app.private_write(path, json.dumps({'type': 'ssh-password', 'password': 'test-password'}))
        env = {**os.environ, 'INFRA_ACCESS_SSH_CREDENTIAL_FILE': str(path)}
        helper = root / 'tools/infra-access/ssh-askpass'
        result = subprocess.run([sys.executable, str(helper)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, 'test-password\n')
        path.chmod(0o644)
        result = subprocess.run([sys.executable, str(helper)], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertEqual(result.stderr, '')

    def test_ssh_accept_new_is_explicit_and_jump_uses_own_identity(self):
        jump = {'host': '10.1.10.1', 'user': 'root', 'identity_file': '~/.ssh/root'}
        device = {'ssh': {'host': '10.2.0.2', 'user': 'admin', 'identity_file': '~/.ssh/admin',
                          'host_key_policy': 'accept-new', 'proxy_jump': jump}}
        args = app.ssh_args(device, 'id')
        self.assertIn('StrictHostKeyChecking=accept-new', args)
        command = next(a for a in args if a.startswith('ProxyCommand='))
        self.assertIn('root@10.1.10.1', command)
        self.assertIn('StrictHostKeyChecking=yes', command)
        self.assertIn('-W %h:%p', command)
        device['ssh']['host_key_policy'] = 'no'
        with self.assertRaises(ValueError):
            app.ssh_args(device, 'id')

    def test_guest_arguments_preserve_shell_metacharacters(self):
        hypervisor = {'ssh': {'host': '10.1.10.21', 'user': 'root', 'identity_file': '~/.ssh/root'}}
        device = {'guest': {'vmid': 301, 'hypervisor': 'hv1'}}
        program = ['powershell.exe', '-Command', '$p="literal"; Write-Output $p']
        args = app.guest_args({'hv1': hypervisor}, device, program)
        self.assertEqual(app.shlex.split(args[-1]), ['qm', 'guest', 'exec', '301', '--'] + program)
        with self.assertRaises(ValueError):
            app.guest_args({'hv1': hypervisor}, device, [])

    def test_onvif_digest_contains_no_plaintext_password(self):
        self.credential({'type': 'basic', 'username': 'camera-admin', 'password': 'private-camera-password'})
        device = {'onvif': {'endpoint': 'http://camera:2020/onvif/device_service', 'credential': 'router'}}
        operation = b'<GetUsers xmlns="http://www.onvif.org/ver10/device/wsdl"/>'
        with patch.object(app.urllib.request, 'build_opener') as factory:
            response = factory.return_value.open.return_value.__enter__.return_value
            response.status = 200
            response.read.return_value = b'<Envelope><Body><UserLevel>Administrator</UserLevel></Body></Envelope>'
            status, value, _ = app.onvif_request(device, operation)
            req = factory.return_value.open.call_args.args[0]
            self.assertNotIn(b'private-camera-password', req.data)
            self.assertIn(b'PasswordDigest', req.data)
            xml = app.ET.fromstring(req.data)
            fields = {e.tag.split('}')[-1]: e.text for e in xml.iter()}
            expected = base64.b64encode(app.hashlib.sha1(base64.b64decode(fields['Nonce']) + fields['Created'].encode() + b'private-camera-password').digest()).decode()
            self.assertEqual(fields['Password'], expected)
            self.assertEqual(status, 200)
            self.assertIn('Administrator', json.dumps(app.xml_value(value)))

    def test_onvif_fault_does_not_count_as_success(self):
        self.credential({'type': 'basic', 'username': 'camera-admin', 'password': 'private-camera-password'})
        device = {'onvif': {'endpoint': 'http://camera:2020/onvif/device_service', 'credential': 'router'}}
        with patch.object(app.urllib.request, 'build_opener') as factory:
            response = factory.return_value.open.return_value.__enter__.return_value
            response.status = 200
            response.read.return_value = b'<Envelope xmlns="http://www.w3.org/2003/05/soap-envelope"><Body><Fault/></Body></Envelope>'
            with self.assertRaises(ValueError):
                app.onvif_request(device, b'<GetUsers xmlns="http://www.onvif.org/ver10/device/wsdl"/>')

    def test_remote_discovery_distinguishes_failed_probe_path(self):
        device = {'probe_via': 'router', 'probes': [{'host': '10.2.0.2', 'port': 22}]}
        router = {'ssh': {'host': '10.1.10.1', 'user': 'root', 'identity_file': '~/.ssh/root'}}
        with patch.object(app.subprocess, 'run') as execute:
            execute.return_value.returncode = 0
            execute.return_value.stdout = '{"10.2.0.2:22":"reachable"}'
            result = app.discover(('peer', device), {'router': router})
            self.assertEqual(result['ports']['10.2.0.2:22'], 'reachable')
            self.assertEqual(result['via'], 'router')
            execute.return_value.returncode = 255
            result = app.discover(('peer', device), {'router': router})
            self.assertEqual(result['ports']['10.2.0.2:22'], 'probe-path-failed')

    def test_excluded_targets_never_open_connections_or_credentials(self):
        for device in ({'excluded': True}, {'ssh': {'host': '100.90.0.2'}},
                       {'probes': [{'host': 'fd7a:115c:a1e0::1', 'port': 22}]},
                       {'api': {'base_url': 'https://peer.example.ts.net'}}):
            with patch.object(app.socket, 'create_connection') as connect, patch.object(app, 'private_read') as read:
                self.assertTrue(app.discover(('excluded', device))['excluded'])
                for operation in (lambda: app.ssh_args(device, 'id'),
                                  lambda: app.api_request(device, 'GET', '/'),
                                  lambda: app.onvif_request(device, b''),
                                  lambda: app.guest_args({}, device, ['id'])):
                    with self.assertRaises(ValueError):
                        operation()
                connect.assert_not_called()
                read.assert_not_called()

    def test_guest_sudo_and_excluded_hypervisor(self):
        host = {'guest_sudo': True, 'ssh': {'host': '10.1.10.21', 'user': 'infraaccess', 'identity_file': '~/.ssh/test'}}
        guest = {'guest': {'hypervisor': 'hv1', 'vmid': 208}}
        self.assertEqual(app.shlex.split(app.guest_args({'hv1': host}, guest, ['id'])[-1]),
                         ['sudo', '-n', 'qm', 'guest', 'exec', '208', '--', 'id'])
        host['excluded'] = True
        with self.assertRaises(ValueError):
            app.guest_args({'hv1': host}, guest, ['id'])

    def test_unifi_session_login_csrf_and_failure(self):
        self.credential({'type': 'unifi-session', 'username': 'admin', 'password': 'secret'})
        with patch.object(app.urllib.request, 'build_opener') as factory:
            response = factory.return_value.open.return_value.__enter__.return_value
            response.status = 200
            response.headers = {'X-CSRF-Token': 'csrf-test'}
            response.read.side_effect = [b'{"meta":{"rc":"ok"}}', b'{"done":true}']
            status, value, secrets = app.api_request(self.device, 'POST', '/api/write', b'{}')
            login, operation = [c.args[0] for c in factory.return_value.open.call_args_list]
            self.assertEqual(login.full_url, 'https://router.example/api/login')
            self.assertEqual(json.loads(login.data)['password'], 'secret')
            self.assertEqual(operation.headers['X-csrf-token'], 'csrf-test')
            self.assertIn('csrf-test', secrets)
            self.assertTrue(value['done'])
            self.assertTrue(any(isinstance(h, urllib.request.HTTPCookieProcessor) for h in factory.call_args.args))
            factory.return_value.open.reset_mock()
            response.read.side_effect = [b'{"meta":{"rc":"error"}}']
            with self.assertRaises(ValueError):
                app.api_request(self.device, 'POST', '/api/write', b'{}')
            self.assertEqual(factory.return_value.open.call_count, 1)

    def test_audit_excludes_payloads(self):
        with patch.dict(os.environ, {'INFRA_ACCESS_STATE': str(self.directory)}):
            app.audit('router', 'api:POST', 'http:200')
        row = json.loads((self.directory / 'audit.jsonl').read_text())
        self.assertEqual(set(row), {'time', 'device', 'operation', 'outcome'})


if __name__ == '__main__':
    unittest.main()
