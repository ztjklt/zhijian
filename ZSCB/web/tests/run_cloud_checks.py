"""Run cloud save/recovery with the frozen release's actual protocol and private fixture."""
from pathlib import Path
import argparse
import re
import runpy
import shutil
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser(add_help=False)
parser.add_argument('--matched-source',type=Path,default=ROOT/'dist/纸间联机最新版-20261025-r7')
args,forwarded=parser.parse_known_args()
protocol=int(re.search(r'const PROTOCOL := (\d+)',(args.matched_source/'scripts/net/codec.gd').read_text()).group(1))
with tempfile.TemporaryDirectory(prefix='paper-cloud-check-') as temp:
    target=Path(temp)
    for name in ['network_cloud_test.py','network_transport_test.py']:
        shutil.copy2(args.matched_source/'tests'/name,target/name)
    transport=target/'network_transport_test.py'
    source=transport.read_text()
    source,count=re.subn(r'value = dict\(value, protocol=\d+\)',f'value = dict(value, protocol={protocol})',source)
    if count!=1:raise RuntimeError('Review cloud fixture protocol before use')
    transport.write_text(source)
    sys.path.insert(0,str(target))
    sys.argv=[str(target/'network_cloud_test.py'),*forwarded]
    runpy.run_path(str(target/'network_cloud_test.py'),run_name='__main__')
