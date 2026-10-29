"""Confirm optional motion ACKs on a disposable public WSS room; print no credentials."""
from pathlib import Path
import argparse
import json
import re
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--address', default='wss://paper-server-production-4b68.up.railway.app/ws')
parser.add_argument('--matched-source', type=Path, default=ROOT/'dist/纸间联机最新版-20261025-r7')
args = parser.parse_args()
protocol=int(re.search(r'const PROTOCOL := (\d+)',(args.matched_source/'scripts/net/codec.gd').read_text()).group(1))
sys.path.insert(0, str(args.matched_source/'tests'))
from network_cloud_test import CloudClient
client = CloudClient(args.address)
welcomed = False
try:
    client.send(dict(type='create', protocol=protocol, map_id='paper', name='移动确认验收'))
    identity = client.until('welcome')
    assert identity['protocol']==protocol
    welcomed = True
    client.ready()
    client.send(dict(type='command', seq=17, op='input', left=False, right=True,
                     up=False, down=False, jump=False, blocked=False, combat_blocked=False))
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        frame = client.until('frame')
        actor = next(a for a in frame['actors'] if a['id'] == identity['player_id'])
        if actor.get('input_ack') == 17:
            assert actor['input_age'] >= 0 and actor['movement_reset'] >= 0
            print(json.dumps(dict(status='PASS', protocol=protocol, input_ack=17,
                                  input_age=actor['input_age'], explicit_movement_reset=True,
                                  wss_certificate_verified=True)))
            break
    else:
        raise AssertionError('Current public authority did not acknowledge input17')
finally:
    if welcomed:
        client.send(dict(type='command', seq=18, op='leave'))
        client.until('closed')
    client.close()
