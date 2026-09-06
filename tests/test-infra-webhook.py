#!/usr/bin/env python3
"""Check webhook rejection and nonblocking dispatch without opening a socket."""
import io
import json
import os
from pathlib import Path
import re
import signal
import textwrap
import time
from unittest.mock import Mock, patch

source = (Path(__file__).resolve().parents[1] / "hosts/devenv/infraAutoUpdate.nix").read_text()
program = textwrap.dedent(re.search(
    r'dashboardWebhookPy = pkgs.writeText "[^"]+" \'\'\n(.*?)\n  \'\';', source, re.S
).group(1))
environment = {
    "RENOVATE_DASHBOARD_WEBHOOK_BIND": "127.0.0.1",
    "RENOVATE_DASHBOARD_WEBHOOK_PORT": "12345",
    "RENOVATE_DASHBOARD_WEBHOOK_SECRET_FILE": "/unused",
    "RENOVATE_DASHBOARD_WEBHOOK_REPOSITORY": "owner/repo",
    "RENOVATE_DASHBOARD_WEBHOOK_ISSUE_TITLE": "Dependency Dashboard",
    "RENOVATE_DASHBOARD_WEBHOOK_BOT_USERNAME": "Infratainer",
}
namespace = {"__name__": "test_webhook"}
with patch.dict(os.environ, environment):
    exec(compile(program, "infra-webhook", "exec"), namespace)

handler_type = namespace["Handler"]
payload = {"action": "edited", "sender": {"login": "maintainer"},
           "repository": {"full_name": "owner/repo"},
           "issue": {"title": "Dependency Dashboard",
                     "body": " - [x] <!-- rebase-all-open-prs -->"}}
for valid, content, expected in ((False, payload, 401), (True, [], 400),
                                  (True, payload, 202)):
    body = json.dumps(content).encode()
    handler = object.__new__(handler_type)
    handler.path = "/renovate-dashboard"
    handler.headers = {"Content-Length": str(len(body)), "X-Forgejo-Event": "issues"}
    handler.rfile = io.BytesIO(body)
    handler.respond = Mock()
    namespace["valid_signature"] = lambda _headers, _body: valid
    with patch.object(namespace["subprocess"], "run", return_value=Mock(returncode=0)) as run:
        handler.do_POST()
        assert handler.respond.call_args.args[0] == expected
        if expected == 202:
            assert run.call_args.args[0] == ["systemctl", "--no-block", "start", "infra-renovate.service"]
            assert run.call_args.kwargs["timeout"] == 10
        else:
            run.assert_not_called()

handler = object.__new__(handler_type)
handler.connection = Mock()
with patch("http.server.BaseHTTPRequestHandler.setup"):
    handler.setup()
handler.connection.settimeout.assert_called_once_with(10)
with patch("http.server.HTTPServer") as server, patch("signal.signal") as register:
    namespace["main"]()
    register.assert_called_once_with(signal.SIGALRM, namespace["request_deadline"])
    server.assert_called_once_with(("127.0.0.1", 12345), handler_type)
    server.return_value.serve_forever.assert_called_once()

# Exercise an absolute deadline while the simulated client keeps supplying
# bytes faster than an idle timeout. This must interrupt active, endless reads.
old_handler = signal.signal(signal.SIGALRM, namespace["request_deadline"])
def drip_request():
    while True:
        time.sleep(0.01)

try:
    with patch("signal.alarm", side_effect=lambda seconds: signal.setitimer(
        signal.ITIMER_REAL, 0.05 if seconds else 0
    )), patch("http.server.BaseHTTPRequestHandler.handle", side_effect=drip_request):
        started = time.monotonic()
        try:
            handler.handle()
            raise AssertionError("active slow request escaped its deadline")
        except TimeoutError:
            assert time.monotonic() - started < 1
    assert signal.getitimer(signal.ITIMER_REAL)[0] == 0
finally:
    signal.setitimer(signal.ITIMER_REAL, 0)
    signal.signal(signal.SIGALRM, old_handler)

print("Webhook checks passed (signature rejection, payload validation, bounded dispatch).")
