import gzip
import email.message
import importlib.util
import json
from pathlib import Path
import threading
import unittest
from unittest.mock import patch, MagicMock
import urllib.request

spec = importlib.util.spec_from_file_location("web", Path(__file__).parents[1] / "hosts/llm1/web-tools.py")
web = importlib.util.module_from_spec(spec)
spec.loader.exec_module(web)


class WebTests(unittest.TestCase):
    def test_private_destinations_blocked(self):
        for url in ("http://127.0.0.1/", "http://10.1.11.9/", "http://169.254.169.254/", "http://[::1]/", "file:///etc/passwd", "http://user:pass@example.com/", "http://example.com:22/"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                web.retrieve(url)

    def test_mixed_dns_blocked_before_connect(self):
        answers = [(2, 1, 6, "", (ip, 80)) for ip in ("1.1.1.1", "127.0.0.1")]
        with patch.object(web.socket, "getaddrinfo", return_value=answers), patch.object(web.socket, "create_connection") as connect:
            with self.assertRaises(ValueError):
                web.retrieve("http://example.com")
            connect.assert_not_called()

    def test_redirect_cannot_reach_private_host(self):
        response = MagicMock(status=302)
        response.getheader.return_value = "http://127.0.0.1/secret"
        connection = MagicMock()
        connection.getresponse.return_value = response
        with patch.object(web.socket, "create_connection"), patch.object(web.http.client, "HTTPConnection", return_value=connection):
            with self.assertRaises(ValueError):
                web.retrieve(web.SEARCH, search=True)
            self.assertEqual(connection.request.call_count, 1)

    def test_gzip_and_decompression_limit(self):
        for body in (b"<h1>Readable</h1>", b"x" * (web.LIMIT + 1)):
            response = MagicMock(status=200)
            response.getheader.side_effect = lambda key, default=None: {"Content-Type": "text/html", "Content-Encoding": "gzip"}.get(key, default)
            response.headers = email.message.Message()
            response.read.return_value = gzip.compress(body)
            connection = MagicMock()
            connection.getresponse.return_value = response
            with patch.object(web.socket, "create_connection"), patch.object(web.http.client, "HTTPConnection", return_value=connection):
                if len(body) > web.LIMIT:
                    with self.assertRaises(ValueError):
                        web.retrieve(web.SEARCH, search=True)
                else:
                    self.assertEqual(web.retrieve(web.SEARCH, search=True)[1], body.decode())

    def test_page_and_find(self):
        source = '<h1>Title</h1><script>secret script</script><p>Evidence here</p><a href="/source">Source</a>'
        with patch.object(web, "retrieve", return_value=("https://example.com/page", source, "text/html")):
            page = web.call("read_page", {"url": "https://example.com/page"})
            self.assertNotIn("secret script", page["text"])
            self.assertIn("https://example.com/source", page["links"])
            self.assertIsNone(page["next_offset"])
            found = web.call("find_in_page", {"url": "https://example.com/page", "text": "evidence"})
            self.assertEqual(found["matches"], 1)
            self.assertIn("Evidence", found["text"])

    def test_search_errors_and_recency(self):
        body = json.dumps({"results": [{"title": "Source", "url": "https://example.com"}], "unresponsive_engines": [["engine", "timeout"]]})
        with patch.object(web, "retrieve", return_value=("", body, "application/json")) as fetch:
            result = web.call("search", {"query": "test", "time_range": "week"})
            self.assertIn("time_range=week", fetch.call_args.args[0])
            self.assertEqual(result["results"][0]["title"], "Source")
            self.assertTrue(result["unresponsive_engines"])

    def test_mcp_wire(self):
        server = web.ThreadingHTTPServer(("127.0.0.1", 0), web.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for method in ("initialize", "tools/list", "tools/call"):
                request = urllib.request.Request(f"http://127.0.0.1:{server.server_port}/mcp",
                    data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method,
                                     "params": {"name": "read_page", "arguments": {"url": "http://127.0.0.1/"}}}).encode(),
                    headers={"Content-Type": "application/json"})
                with urllib.request.urlopen(request) as response:
                    result = json.load(response)["result"]
                if method == "tools/list":
                    self.assertEqual(len(result["tools"]), 3)
                if method == "tools/call":
                    self.assertTrue(result["isError"])
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()
