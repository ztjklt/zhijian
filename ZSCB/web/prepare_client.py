"""Apply Web flow to matched native sources and prediction to legacy releases."""
from pathlib import Path
import shutil
from prepare_authority import prepare_authority
import re

HERE=Path(__file__).resolve().parent

def replace_once(text, old, new):
    if text.count(old)!=1:
        raise ValueError('Fixed client anchor changed: '+old[:90])
    return text.replace(old,new,1)

def readable_menu(text):
    # Apply presentation changes to the fixed client without importing gameplay code.
    text=text.replace('PaperTheme.create()', 'PaperTheme.create_menu()')
    text=text.replace('"font_size", font_size)', '"font_size", PaperTheme.menu_font_size(font_size))')
    text=re.sub(r'("font_size",\s*)(\d+)(\))',r'\1PaperTheme.menu_font_size(\2)\3',text)
    text=text.replace('"font_size", 13 if viewport.y < 500 else 15)', '"font_size", PaperTheme.menu_font_size(13 if viewport.y < 500 else 15))')
    return text.replace('PaperTheme.MUTED','PaperTheme.MENU_MUTED').replace('Color("776c5e")','Color("5f574d")')

def prepare_legacy_movement(text):
    # Preserve authority rules while responding locally to locomotion.
    text=replace_once(text,'var received_position := false','var received_position := false\nvar prediction = preload("res://scripts/net/local_prediction.gd").new()\nvar last_controls: Dictionary = {}')
    text=replace_once(text,'func _connect() -> Error:\n', 'func _connect() -> Error:\n\tprediction.clear(); last_controls.clear(); heartbeat_clock=5\n')
    text=replace_once(text,'\t\t\tepoch=str(message.epoch); last_tick=-1; revision=-1','\t\t\tepoch=str(message.epoch); last_tick=-1; revision=-1\n\t\t\tprediction.clear()')
    text=replace_once(text,'for body in game.object_nodes: body.freeze=true; body.collision_layer=0; body.collision_mask=0','for body in game.object_nodes: body.freeze=true; body.collision_layer=8 if body.data.get("kind","") in ["gate","ladder"] else 1; body.collision_mask=0')
    text=replace_once(text,'''\t\tif not received_position or game.player.position.distance_to(local_target)>5:
\t\t\tgame.player.position=local_target
\t\t\treceived_position=true
\t\tgame.player.linear_velocity=state.get("velocity",Vector2.ZERO)
\t\tgame.facing=int(state.get("facing",1)); game.pose=state.get("pose","idle")
\t\tgame.crouching=state.get("crouching",false)''', '''\t\tprediction.receive(game,state,Time.get_ticks_msec(),round_trip_ms)
\t\treceived_position=true''')
    text=replace_once(text,'\tgame.player.freeze=true\n\tif received_position: game.player.position=game.player.position.lerp(local_target,minf(1,delta*24))','')
    text=replace_once(text,'\tgame.camera_x=lerpf(game.camera_x,game.player.position.x,minf(1,delta*7))\n\tif game.knowledge_world!=null or game.medieval_world!=null: game.camera_y=lerpf(game.camera_y,game.camera_target_y(),minf(1,delta*5))', '''\tif game.active_stroke==null and game.drag==null and not game.selecting_weapon_grip:
\t\tgame.camera_x=lerpf(game.camera_x,game.player.position.x,1-exp(-delta*7))
\t\tif game.knowledge_world!=null or game.medieval_world!=null: game.camera_y=lerpf(game.camera_y,game.camera_target_y(),1-exp(-delta*5))''')
    text=replace_once(text,'\tif not ready_to_play or leaving or local_dead_time>0: return','\tif not ready_to_play or leaving or ended or local_dead_time>0:\n\t\tprediction.step(game,delta,{},false,Time.get_ticks_msec())\n\t\treturn')
    text=replace_once(text,'''\tif send_clock>=.05 or blocked != last_blocked or combat_blocked != last_combat_blocked:
\t\tlast_blocked = blocked
\t\tlast_combat_blocked = combat_blocked
\t\tsend_clock=0
\t\tvar stick:Vector2=game.touch_controls.movement_vector() if game.touch_controls!=null else Vector2.ZERO
\t\tsend_op("input",{"blocked":blocked,"combat_blocked":combat_blocked,"left":not blocked and (Input.is_action_pressed("move_left") or stick.x<-.25),"right":not blocked and (Input.is_action_pressed("move_right") or stick.x>.25),"up":not blocked and (Input.is_action_pressed("move_up") or stick.y<-.5),"down":not blocked and (Input.is_action_pressed("move_down") or stick.y>.5),"jump":not blocked and (Input.is_action_pressed("jump") or jump_queued)})
\t\tjump_queued=false''', '''\tvar stick:Vector2=game.touch_controls.movement_vector() if game.touch_controls!=null else Vector2.ZERO
\tvar controls:={"blocked":blocked,"combat_blocked":combat_blocked,"left":not blocked and (Input.is_action_pressed("move_left") or stick.x<-.25),"right":not blocked and (Input.is_action_pressed("move_right") or stick.x>.25),"up":not blocked and (Input.is_action_pressed("move_up") or stick.y<-.5),"down":not blocked and (Input.is_action_pressed("move_down") or stick.y>.5),"jump":not blocked and (Input.is_action_pressed("jump") or jump_queued)}
\tprediction.step(game,delta,controls,true,Time.get_ticks_msec())
\tif send_clock>=.05 or controls!=last_controls:
\t\tlast_blocked=blocked;last_combat_blocked=combat_blocked
\t\tlast_controls=controls.duplicate();send_clock=0
\t\tvar input_number:=send_op("input",controls)
\t\tprediction.sent_input(input_number,controls)
\tjump_queued=false''')
    return text

def prepare(project:Path):
    protocol=int(re.search(r'const PROTOCOL := (\d+)',(project/'scripts/net/codec.gd').read_text()).group(1))
    if protocol not in [2,6,7,8,9,10]:raise ValueError('Review Web adaptation for protocol '+str(protocol))
    prepare_authority(project)
    shutil.copytree(HERE/'client',project,dirs_exist_ok=True)
    prediction=project/'scripts/net/local_prediction.gd'
    if not prediction.is_file():
        shutil.copy2(HERE.parent/'scripts/net/local_prediction.gd',prediction)
    if protocol==2:
        shutil.copy2(HERE.parent/'scripts/paper_theme.gd',project/'scripts/paper_theme.gd')
        for name in ['map_select','settings_panel','backpack_panel','experience_panel']:
            script=project/'scripts'/f'{name}.gd'
            script.write_text(readable_menu(script.read_text()))
    session=project/'scripts/net/session.gd'
    text=session.read_text()
    text=replace_once(text,'var socket: WebSocketPeer','var flow_ui\nvar room_closed := false\nvar socket: WebSocketPeer')
    text=replace_once(text,'ended=false; leaving=false; leave_seq=-1; retries=0','ended=false; leaving=false; leave_seq=-1; retries=0\n\troom_closed=false; retry_clock=-1; heartbeat_clock=0; leave_confirmed=false\n\tupload_queue.clear(); chunks.clear(); chunk_bytes=0; chunk_count=0')
    text=replace_once(text,'\t\t"closed":\n\t\t\t_fail(', '\t\t"closed":\n\t\t\troom_closed=true\n\t\t\t_fail(')
    text=replace_once(text,'\t\t\tstatus=_error_text(str(message.get("error","联机操作失败")))','\t\t\tif message.get("error","")=="room_not_found": room_closed=true\n\t\t\tstatus=_error_text(str(message.get("error","联机操作失败")))')
    source_title='指尖' if protocol==2 else '纸间'
    text=replace_once(text,'\t\tget_window().title="'+source_title+' · 双人对战 "+Codec.RELEASE+" · "+code','\t\tget_window().title="纸间 · 双人房间 · "+code\n\t\tflow_ui=preload("res://scripts/net/online_panel.gd").new()\n\t\tflow_ui.session=self\n\t\tgame.add_child(flow_ui)')
    text=replace_once(text,'hud.visible=not game.bag_open and not (game.experience!=null and game.experience.visible)','hud.visible=false if flow_ui!=null else not game.bag_open and not (game.experience!=null and game.experience.visible)')
    text=replace_once(text,'if not focus_active: return','if not focus_active or get_meta("flow_modal",false): return')
    text=replace_once(text,'var blocked:bool=not focus_active or focus is LineEdit','var blocked:bool=not focus_active or bool(get_meta("flow_modal",false)) or focus is LineEdit')
    text=replace_once(text,'status="连接中断，正在尝试重连（保留30秒席位）…"','status="连接中断，正在自动重连 · 第%d/3次（草稿保留）…" % retries')
    text=replace_once(text,'func _disconnected() -> void:', '''func retry_now() -> Error:
\tif room_closed or token=="": return ERR_UNAVAILABLE
\tif not ended and retry_clock<0 and socket!=null and socket.get_ready_state() in [WebSocketPeer.STATE_CONNECTING,WebSocketPeer.STATE_OPEN]: return ERR_BUSY
\tended=false; leaving=false; leave_seq=-1; retries=0; retry_clock=-1; mode="join"
\tif socket!=null: socket.close()
\treturn _connect()

func _disconnected() -> void:''')
    # Unknown leave outcomes stop input and preserve the scene, with a clean retry state.
    text=replace_once(text,'\t\tended=true; ready_to_play=false\n\t\tif socket!=null: socket.close()', '\t\tended=true; ready_to_play=false\n\t\tif not leave_confirmed: leaving=false; leave_seq=-1\n\t\tif socket!=null: socket.close()')
    text=replace_once(text,'\t\tif not ended: status = "尚未收到退出保存确认，已保留当前画面与草稿；请检查连接"', '\t\tif not ended: status = "尚未收到退出保存确认，已保留当前画面与草稿；请尝试重连确认房间状态"\n\t\tleaving=false; leave_seq=-1; ready_to_play=false; ended=true\n\t\tif socket!=null: socket.close()')
    # Build one lookup for this received frame. Snapshot replacement cannot leave
    # stale object references because the index never outlives the frame.
    text=replace_once(text,'\tif game.medieval_world!=null:\n\t\tfor record in frame.get("entities",[]):\n\t\t\tvar entity=game.medieval_world.entity_by_id(str(record.id))', '\tif game.medieval_world!=null:\n\t\tvar frame_entities:={}\n\t\tfor item in game.medieval_world.entities: frame_entities[item.entity_id]=item\n\t\tfor record in frame.get("entities",[]):\n\t\t\tvar entity=frame_entities.get(str(record.id))')
    # Native sources carry matched prediction already; inject only for old releases.
    if 'var prediction = preload("res://scripts/net/local_prediction.gd").new()' not in text:
        text=prepare_legacy_movement(text)
    session.write_text(text)
    touch=project/'scripts/touch_controls.gd'
    text=touch.read_text()
    text=replace_once(text,'if game.experience != null and game.experience.visible:', 'if (game.experience != null and game.experience.visible) or (game.network_session!=null and game.network_session.get_meta("flow_modal",false)):')
    text=replace_once(text,'\t\tif not game.bag_open and event.position.distance_to(stick_center)', '\t\tvar flow=game.network_session.flow_ui if game.network_session!=null else null\n\t\tif flow!=null and flow.blocks_canvas(event.position):\n\t\t\tvar flow_button:=_button_at(flow.panel,event.position)\n\t\t\tif flow_button!=null:\n\t\t\t\towners[event.index]="ui"; pressed_button[event.index]=weakref(flow_button)\n\t\t\telse:\n\t\t\t\towners[event.index]="native"; native_mouse_active=true; return false\n\t\telif not game.bag_open and event.position.distance_to(stick_center)')
    text=replace_once(text,'if not game.toolbar.blocks_canvas(event.position): game.pointer_move(event.position)', 'if not game.toolbar.blocks_canvas(event.position) and not (game.network_session!=null and game.network_session.flow_ui!=null and game.network_session.flow_ui.blocks_canvas(event.position)): game.pointer_move(event.position)')
    touch.write_text(text)
    main=project/'scripts/main.gd' 
    text=main.read_text()
    text=replace_once(text,'\t\tnetwork_session.return_to_selector(destination)','\t\tif network_session.flow_ui!=null: network_session.flow_ui.request_exit(destination)\n\t\telse: network_session.return_to_selector(destination)')
    text=replace_once(text,'\t\tnetwork_session.save_and_return_to_selector("res://scenes/title_menu.tscn")','\t\tif network_session.flow_ui!=null: network_session.flow_ui.request_exit("res://scenes/title_menu.tscn")\n\t\telse: network_session.save_and_return_to_selector("res://scenes/title_menu.tscn")')
    text=replace_once(text,'\t\tnetwork_session.import_local()','\t\tif network_session.flow_ui!=null: network_session.flow_ui.request_import()\n\t\telse: network_session.import_local()')
    main.write_text(text)
    if protocol==2:
        toolbar=project/'scripts/toolbar.gd'
        text=replace_once(toolbar.read_text(),'game.bag_open, game.equipped_weapon, status_text, compact','game.bag_open, status_text, compact')
        toolbar.write_text(text)
    title=project/'scripts/title_menu.gd' 
    text=replace_once(title.read_text(),'func _ready() -> void:', '''func _ready() -> void:
\tif preload("res://scripts/net/online_flow.gd").entry_invite().get("present",false):
\t\tget_tree().call_deferred("change_scene_to_file","res://scenes/network_lobby.tscn")
\t\treturn''')
    title.write_text(text)
    # Display branding only: config/name and old save paths remain unchanged.
    if protocol==2:
        for script in (project/'scripts').rglob('*.gd'):
            script.write_text(script.read_text().replace('指尖','纸间').replace('纸上城堡','纸间').replace('纸间 · 纸间','纸间 · 在同一张纸上'))
