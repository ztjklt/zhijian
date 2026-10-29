from runtime_tools import resolve_godot, user_data_path
"""Run a real authority and two full Godot game clients in isolated projects."""
from pathlib import Path
import os, re, shutil, socket, subprocess, tempfile, time, uuid
import argparse
parser=argparse.ArgumentParser(); parser.add_argument("--map",default="paper"); parser.add_argument("--visual",action="store_true")
parser.add_argument("--latency-ms",type=int,default=0,help="Add round-trip delay through a test-only local stream proxy")
parser.add_argument("--bandwidth-kbps",type=int,default=0,help="Limit each direction in the local test proxy (KiB/s)")
parser.add_argument("--verbose",action="store_true",help="Keep detailed Godot resource diagnostics")
parser.add_argument("--duel",action="store_true",help="Exercise actual two-client combat, death, blocked bow and reconnect")
parser.add_argument("--save-request",action="store_true",help="Save clicked during real resync, deduplicated and confirmed after Ready")
parser.add_argument("--creation-receipt",action="store_true",help="Capacity races and new local workflows survive actual creation receipts")
parser.add_argument("--drawing-preview",action="store_true",help="128 actual strokes, all remote endpoints, clear/redraw/reconnect and full generation")
parser.add_argument("--weapon-lab",action="store_true",help="Place independent targets, measure gun/bow and copy through grip/type/equip")
parser.add_argument("--cooperation",action="store_true",help="Two authors lend, move, connect, revoke and reopen co-created structure")
parser.add_argument("--structure",action="store_true",help="Draw parts, connect fixed/hinge, unlink, check permissions and save")
parser.add_argument("--bridge-trial",action="store_true",help="Travel to the mill, share failure, draw a bridge and deliver actual cargo")
parser.add_argument("--feedback",action="store_true",help="Render both duel clients and verify real confirmed hit/hurt audio and captures")
parser.add_argument("--vitals",action="store_true",help="Also require authority ink consumption to reach both clients")
parser.add_argument("--address",help="Use an existing server, e.g. wss://host/ws; creates a disposable test world there")
parser.add_argument("--evidence-dir",type=Path,help="Keep client logs and optional rendered capture, without credentials")
parser.add_argument("--project-source",type=Path,help="Verify a frozen release instead of the active checkout")
parser.add_argument("--support-source",type=Path,help="Matched frozen tests/server when checking a Web-only project")
args=parser.parse_args()
if args.vitals: args.feedback=True
if args.feedback: args.duel=True
if args.address and (args.latency_ms or args.bandwidth_kbps): parser.error("delay/rate proxy is for the disposable local authority only")
source=args.project_source.resolve() if args.project_source else Path(__file__).resolve().parents[1]
support=args.support_source.resolve() if args.support_source else source
if not (support/'server').is_dir() or not (support/'tests').is_dir():
    import json
    manifest=source.parent/'WEB_RELEASE.json'
    if not manifest.is_file(): raise ValueError('Web project requires its release manifest or --support-source')
    support=Path(__file__).resolve().parents[2]/json.loads(manifest.read_text())['source']
godot=resolve_godot()
def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1',0)); return s.getsockname()[1]
with tempfile.TemporaryDirectory(prefix='paper-network-clients-') as temp:
    proxy=None
    base=Path(temp); coord=base/'coord'; coord.mkdir(); processes=[]; clients=[]; handles=[]; names=[]
    try:
        seed=base/'server'; shutil.copytree(source,seed,ignore=shutil.ignore_patterns('.godot','__pycache__'))
        for name in ('server','tests'):
            if not (seed/name).is_dir(): shutil.copytree(support/name,seed/name,ignore=shutil.ignore_patterns('__pycache__'))
        (seed/'tests').mkdir(exist_ok=True)
        bot = 'creation_receipt_bot.gd' if args.creation_receipt else 'save_request_bot.gd' if args.save_request else 'drawing_preview_bot.gd' if args.drawing_preview else 'cooperation_bot.gd' if args.cooperation else 'weapon_lab_bot.gd' if args.weapon_lab else 'structure_bot.gd' if args.structure else 'mill_bridge_bot.gd' if args.bridge_trial else ('network_vitals_bot.gd' if args.vitals else ('network_feedback_bot.gd' if args.feedback else ('network_duel_bot.gd' if args.duel else 'network_bot.gd')))
        shutil.copy2(Path(__file__).with_name(bot),seed/'tests/network_bot.gd')
        name='PaperNetwork_'+uuid.uuid4().hex; names.append(name)
        cfg=seed/'project.godot'; cfg.write_text(re.sub(r'^config/name=.*$',f'config/name="{name}"',cfg.read_text(),flags=re.M))
        imported=subprocess.run([str(godot),'--headless','--path',str(seed),'--editor','--import','--quit'],capture_output=True,text=True,timeout=45)
        if imported.returncode or 'ERROR:' in imported.stderr: raise RuntimeError(imported.stdout+imported.stderr)
        net_port=port(); public_port=port(); env=dict(os.environ,NET_PORT=str(net_port),PORT=str(public_port),GODOT_BIN=str(godot),NET_DATA_DIR=str(base/'worlds'))
        log=open(base/'server.log','w+'); handles.append(log)
        address=args.address or f'ws://127.0.0.1:{public_port}/ws'
        if not args.address:
            processes.append(subprocess.Popen([shutil.which('python3'),str(seed/'server/start_local.py')],stdout=log,stderr=subprocess.STDOUT,env=env))
            deadline=time.monotonic()+10
            while time.monotonic()<deadline:
                try:
                    with socket.create_connection(('127.0.0.1',net_port),.2): break
                except OSError: time.sleep(.05)
        if args.latency_ms or args.bandwidth_kbps:
            from network_delay_proxy import start_delay_proxy
            proxy=start_delay_proxy(('127.0.0.1',public_port),args.latency_ms,args.bandwidth_kbps)
            address=f'ws://127.0.0.1:{proxy.server_address[1]}/ws'
        for role in ('owner','guest'):
            project=base/role; shutil.copytree(seed,project)
            client_name=name+'_'+role; names.append(client_name)
            cfg=project/'project.godot'; cfg.write_text(re.sub(r'^config/name=.*$',f'config/name="{client_name}"',cfg.read_text(),flags=re.M))
            log=open(base/f'{role}.log','w+'); handles.append(log)
            client_env=dict(os.environ)
            if args.evidence_dir: client_env['PAPER_NET_CAPTURE_DIR']=str(args.evidence_dir.resolve())
            client=subprocess.Popen([str(godot),* (['--verbose'] if args.verbose else []),* ([] if args.feedback or (args.visual and role=='owner') else ['--headless']),'--path',str(project),'--script','res://tests/network_bot.gd','--',f'--role={role}',f'--coord={coord}',f'--address={address}',f'--map={args.map}'],stdout=log,stderr=subprocess.STDOUT,env=client_env)
            clients.append(client); processes.append(client)
        deadline=time.monotonic()+(120 if args.bridge_trial else 100 if args.duel else 60)
        while time.monotonic()<deadline and any(p.poll() is None for p in clients):
            if list(coord.glob('*.failed')) or any('SCRIPT ERROR' in path.read_text(errors='replace') for path in base.glob('*.log')): break
            time.sleep(.1)
        for p in clients:
            if p.poll() is None: p.terminate()
            p.wait(timeout=5)
        errors=[]
        for role in ('owner','guest'):
            if not (coord/f'{role}.checked').exists(): errors.append(f'{role}: no completion evidence')
        if any(p.returncode for p in clients): errors.append('Client exit failed')
        for path in base.glob('*.log'):
            output=path.read_text()
            if 'ERROR:' in output or 'SCRIPT ERROR' in output: errors.append(output)
        if errors:
            for path in base.glob('*.log'): print(path.name, path.read_text()[-12000:])
            raise RuntimeError('\n'.join(errors))
        world_id=(coord/'world_id').read_text()
        if not args.address: assert (base/'worlds'/f'{world_id}.json').exists(), 'World not persisted'
        if args.creation_receipt and not args.address:
            import json
            persisted=json.loads((base/'worlds'/f'{world_id}.json').read_text())
            assert len(persisted['data']['objects'])==1, 'Local blueprint retry duplicated authoritative object'
        prefix = 'NETWORK_CREATION_RECEIPT_CLIENTS ' if args.creation_receipt else 'NETWORK_SAVE_REQUEST_CLIENTS ' if args.save_request else 'NETWORK_DRAWING_PREVIEW_CLIENTS ' if args.drawing_preview else 'NETWORK_COOPERATION_CLIENTS ' if args.cooperation else 'NETWORK_WEAPON_LAB_CLIENTS ' if args.weapon_lab else 'NETWORK_STRUCTURE_CLIENTS ' if args.structure else 'NETWORK_MILL_CLIENTS ' if args.bridge_trial else ('NETWORK_FEEDBACK_CLIENTS ' if args.feedback else ('NETWORK_DUEL_CLIENTS ' if args.duel else 'NETWORK_REAL_CLIENTS '))
        details = 'actual single spawn/equip, full bag during both replies, local blueprint archive only, newer placement/wheel retained, private bags/permissions and confirmed save/close' if args.creation_receipt else 'actual drawing/equipment and permissions, duplicate save clicks during real resync, Ready then one confirmed save and owner close' if args.save_request else '128 actual strokes/8192 local points per client, all preview endpoints <=500 points, clear/redraw, credential reconnect, actual64-point generation and confirmed save' if args.drawing_preview else 'two authors actual drawings, per-piece panel lending, shared move/undo, cross-author fixed joint, revocation denial, saved reopen retaining structure/authors and clearing lending' if args.cooperation else 'independent authoritative targets, actual firearm28/bow24, retained comparison, complete copied drawing/grip/type/equip loop, saved close' if args.weapon_lab else 'actual drawings, fixed/unlink/hinge, author permissions, both replicas without local joints, retained creations, saved close' if args.structure else 'actual travel, shared missing-bridge failure, partner-drawn dynamic bridge, real cargo delivery, retained construction, confirmed save/close' if args.bridge_trial else ('bidirectional sword damage, both clients rendered hit/hurt and played matching audio, confirmed save/close' if args.feedback else ('bidirectional sword damage, lethal hits, 3s respawn, retained draft/equipment, bow hit, cancelled bow, credential reconnect, confirmed save/close' if args.duel else 'drawing, shared object, private blueprint bags, validated equipment, permissions, confirmed save, owner close'))
        print(prefix+args.map+': PASS — '+address+' + 2 actual game clients; '+details)
        if proxy: print(f'SIMULATED_NETWORK added_RTT_ms={args.latency_ms} per_direction_KiB_s={args.bandwidth_kbps or "unlimited"}')
        if args.address: print('Remote save acknowledged; persistent-volume restart recovery requires a separate check.')
    finally:
        if proxy: proxy.shutdown(); proxy.server_close()
        for p in reversed(processes):
            if p.poll() is None: p.terminate()
            try: p.wait(timeout=5)
            except subprocess.TimeoutExpired: p.kill(); p.wait()
        for h in handles: h.close()
        if args.evidence_dir:
            args.evidence_dir.mkdir(parents=True,exist_ok=True)
            for path in base.glob('*.log'): shutil.copy2(path,args.evidence_dir/f'{args.map}-{path.name}')
        for name in names:
            data=user_data_path(name)
            if data.exists(): shutil.rmtree(data)
