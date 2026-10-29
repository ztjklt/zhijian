extends Node
static func frame_limit(focused:bool)->int:return 60 if focused else 20
func _ready()->void:
	if OS.has_feature("web"):Engine.max_fps=frame_limit(true)
func _notification(what:int)->void:
	if not OS.has_feature("web"):return
	if what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_WM_WINDOW_FOCUS_IN]:Engine.max_fps=frame_limit(true)
	elif what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_OUT]:Engine.max_fps=frame_limit(false)
var seconds:=0.0
var times:Array[float]=[]
func _process(delta:float)->void:
	if not OS.has_feature("web"):return
	times.append(delta*1000);seconds+=delta
	if seconds<1:return
	var sorted:=times.duplicate();sorted.sort()
	var report:={"fps":Engine.get_frames_per_second(),"frame_budget":Engine.max_fps,"frame_p50_ms":sorted[sorted.size()/2],"frame_p95_ms":sorted[mini(sorted.size()-1,int(sorted.size()*.95))],"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"viewport":str(get_viewport().get_visible_rect().size)}
	var scene:=get_tree().current_scene
	if scene!=null and scene.has_method("sync_objects"):
		report.map=scene.world_kind;report.objects=scene.objects.size()
		if scene.network_session!=null:
			report.rtt_ms=scene.network_session.round_trip_ms
			report.last_tick=scene.network_session.last_tick
			report.connected=scene.network_session.ready_to_play
			report.focused=scene.network_session.focus_active
			report.local_position=str(scene.player.position)
			report.authority_position=str(scene.network_session.local_target)
			report.predicting=scene.network_session.prediction.was_running
			report.reconciliation="input-ack" if scene.network_session.prediction.ack_enabled else "legacy"
			report.correction_m=scene.network_session.prediction.correction.length()
			report.max_correction_step_m=scene.network_session.prediction.max_correction_step
	JavaScriptBridge.eval("document.getElementById('canvas').dataset.paperPerformance = "+JSON.stringify(JSON.stringify(report)),true)
	times.clear();seconds=0
