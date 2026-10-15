"""Fail closed if a Strata upgrade changes our integration points."""
from pathlib import Path


def replace(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f'Expected one integration point in {path}: {old!r}')
    path.write_text(text.replace(old, new))


server = Path('serve/server.py')
replace(server, '        def do_GET(self):\n            path = self.path.split("?")[0].rstrip("/")',
'''        def do_GET(self):
            path = self.path.split("?")[0].rstrip("/")
            if path.startswith("/workspace/"):
                if self._authorized():
                    from serve.workspace_proxy import handle
                    handle(self, path)
                return''')
replace(server, '            if path == "/settings":\n                self._settings()',
'''            if path.startswith("/workspace/"):
                if self._own_page("documents can be processed"):
                    from serve.workspace_proxy import handle
                    handle(self, path, self._body())
                return
            if path == "/settings":
                self._settings()''')
index = Path('serve/web/index.html')
replace(index, '<link rel="stylesheet" href="web/app.css">', '<link rel="stylesheet" href="web/app.css">\n<link rel="stylesheet" href="web/workspace.css">')
app = Path('serve/web/app.js')
replace(app, '`${health.model} runs on this PC. Nothing leaves it.`', '`${health.model} runs on llm1. Web tools send queries and page requests to external services.`')
# Keep the new module in the same classic-script scope as upstream's chat state.
app.write_text(app.read_text() + '\n' + Path('serve/web/workspace.js').read_text())
