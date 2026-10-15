"""Exercise authentication and origin checks on the added routes, without a GPU."""
import unittest
from unittest.mock import patch
from serve import test_security


class WorkspaceRoutes(unittest.TestCase):
    setUp = test_security.OverHttp.setUp
    tearDown = test_security.OverHttp.tearDown
    start = test_security.OverHttp.start
    req = test_security.OverHttp.req

    def test_authentication_precedes_worker(self):
        self.start(api_key='test-key')
        with patch('serve.workspace_proxy.handle') as worker:
            for method,path in [('POST','/workspace/extract'),('GET','/workspace/artifacts/'+'a'*32)]:
                status,_,_=self.req(method,path,{} if method=='POST' else None,{'Content-Type':'application/json'})
                self.assertEqual(status,401)
            worker.assert_not_called()

    def test_foreign_origin_and_form_refused(self):
        self.start(api_key='test-key')
        for origin,kind,status in [('https://evil.example','application/json',403),('http://localhost','text/plain',415)]:
            with patch('serve.workspace_proxy.handle') as worker:
                code,_,_=self.req('POST','/workspace/extract',{}, {'Authorization':'Bearer test-key','Origin':origin,'Content-Type':kind})
                self.assertEqual(code,status)
                worker.assert_not_called()

    def test_authorized_request_reaches_worker(self):
        self.start(api_key='test-key')
        def reply(handler,path,body=None):
            self.assertEqual(path,'/workspace/extract')
            self.assertEqual(body,b'{}')
            handler._json(200,{'text':'extracted'})
        with patch('serve.workspace_proxy.handle',side_effect=reply):
            code,data,_=self.req('POST','/workspace/extract',{}, {'Authorization':'Bearer test-key','Content-Type':'application/json'})
            self.assertEqual(code,200)
            self.assertEqual(data,{'text':'extracted'})
