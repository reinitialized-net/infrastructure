"""Run with the worker's ANALYSIS_* environment to exercise the real sandbox."""
import base64
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('analysis', Path(__file__).parents[1] / 'hosts/llm1/harness/analysis-tools.py')
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)


class AnalysisTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        a.ARTIFACTS = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def test_calculate_chart_and_download(self):
        result = a.execute({'code': "import pandas as pd\nimport matplotlib.pyplot as plt\nd=pd.read_csv('sales.csv')\nprint(d.amount.sum())\nd.plot.bar(x='name',y='amount');plt.savefig('chart.png')", 'files':{'sales.csv':'name,amount\na,12\nb,30\n'}})
        self.assertEqual(result['exit_code'], 0, result)
        self.assertIn('42',result['stdout'])
        artifact = next(x for x in result['artifacts'] if x['name']=='chart.png')
        self.assertTrue((a.ARTIFACTS / artifact['url'].split('/')[-1]).read_bytes().startswith(b'\x89PNG'))

    def test_network_and_host_files_inaccessible(self):
        result = a.execute({'code': "import os,socket\nassert not os.path.exists('/var/lib/service-secrets')\nassert not os.path.exists('/home/develop')\nassert not os.path.exists('/var/lib/strata-analysis')\ns=socket.socket();s.settimeout(1)\ntry: s.connect(('127.0.0.1',8080))\nexcept OSError: print('isolated')\nelse: raise RuntimeError('network escaped')"})
        self.assertEqual(result['exit_code'],0,result)
        self.assertIn('isolated',result['stdout'])

    def test_error_and_symlink_output(self):
        result = a.execute({'code':"import os\nos.symlink('/etc/passwd','leak.txt')\nraise ValueError('expected')"})
        self.assertNotEqual(result['exit_code'],0)
        self.assertEqual(result['artifacts'],[])

    def test_traversal_rejected(self):
        for name in ('../escape','/tmp/escape','..'):
            with self.assertRaises(ValueError):
                a.execute({'code':'print(1)','files':{name:'x'}})

    def test_documents(self):
        result = a.execute({'code':"from docx import Document\nfrom openpyxl import Workbook\nimport matplotlib.pyplot as plt\nd=Document();d.add_paragraph('document evidence');d.save('test.docx')\nw=Workbook();w.active.append(['sales',42]);w.save('test.xlsx')\nplt.text(.1,.5,'PDF evidence');plt.savefig('test.pdf')"})
        self.assertEqual(result['exit_code'],0,result)
        for artifact in result['artifacts']:
            raw=(a.ARTIFACTS / artifact['url'].split('/')[-1]).read_bytes()
            parsed=a.extract({'name':artifact['name'],'data':base64.b64encode(raw).decode()})
            expected = {'test.docx':'document evidence','test.xlsx':'sales\t42','test.pdf':'PDF evidence'}[artifact['name']]
            self.assertIn(expected,parsed['text'])


if __name__ == '__main__':
    unittest.main()
