extends RefCounted
## Observe a real personal drawing, use and save. Never fabricate a creation.
var game
var stage:=0
var visible:=false
var persist:=false
var target_key:=""
var map:=""
var drawing_mode:=1
var support_time:=0.0
var notice:=""
var baseline:Dictionary={}
func _init(owner_game)->void:
	game=owner_game;persist=game.onboarding.persist
	if persist and game.onboarding.visible and game.network_session==null:start()
func start()->bool:
	if game.network_session!=null:game.message("第一件作品在单人练习中进行；房间作品保持原样");return false
	visible=true;stage=0;target_key="";support_time=0;notice="";map=game.world_kind;baseline.clear()
	for object in game.objects:baseline[object.get("structure_id","")]=true
	game.onboarding.visible=false;game.onboarding.persist=false
	if game.draw_mode in [1,3,5] and not game.draft.is_empty():note_drawn(game.draw_mode)
	return true
func dismiss()->void:
	visible=false;game.onboarding.visible=false;_save_seen(stage==4)
func _save_seen(completed:bool)->void:
	if not persist:return
	var config:=ConfigFile.new();config.load(PaperOnboarding.PREFERENCES)
	config.set_value("guide","seen",true)
	if completed:config.set_value("first_work","completed",true)
	config.save(PaperOnboarding.PREFERENCES)
func note_drawn(mode:int)->void:
	if visible and stage in [0,1] and mode in [1,3,5]:stage=1;drawing_mode=mode;notice=""
func has_drawing()->bool:
	return not (game.draft if game.draw_mode==drawing_mode else game.mode_drafts.get(drawing_mode,[])).is_empty() or (game.draw_mode==drawing_mode and game.active_stroke!=null)
func target():
	for i in game.objects.size():
		if game.objects[i].get("structure_id","")==target_key and i<game.object_nodes.size():
			var body=game.object_nodes[i]
			if is_instance_valid(body) and not body.is_queued_for_deletion():return body
	return null
func note_created(object:Dictionary)->void:
	if not visible or stage!=1 or game.world_kind!=map or baseline.has(object.get("structure_id","")):return
	if object.get("role","")!="building" or object.get("structure_id","")=="":return
	target_key=object.structure_id
	if target()==null:target_key="";return
	stage=2;support_time=0;notice=""
func note_moved(object:Dictionary,from:Vector2,to:Vector2)->void:
	if visible and stage==2 and object.get("structure_id","")==target_key and from.distance_to(to)>=.25 and target()!=null:stage=3;notice="你已亲手搬动这件作品。"
func note_saved(ok:bool)->void:
	if not visible or stage!=3:return
	if target()==null or game.world_kind!=map:world_changed();return
	if not ok:notice="保存未成功，作品还在；请重试。";return
	stage=4;notice="作品和图纸都已保存，可以继续自由创作。";_save_seen(true)
func world_changed()->void:
	if not visible or stage==4:return
	start();stage=0;target_key="";notice="在这张纸上，重新画一件属于你的作品。"
func step(delta:float)->void:
	if not visible or game.network_session!=null:return
	if game.world_kind!=map:world_changed();return
	if stage==1 and not has_drawing():stage=0;notice="原画稿已清空；重新画一件即可。"
	if stage not in [2,3]:return
	var body=target()
	if body==null:world_changed();notice="目标部件已不在；原作品不清空，再画一件即可。";return
	if stage==2:
		var supported:bool=game.on_ground and game.player.support_bodies().has(body) and absf(game.player.linear_velocity.y-body.linear_velocity.y)<.4
		support_time=support_time+delta if supported else 0.0
		if support_time>=.3:stage=3;notice="它真的承住了你。接下来保存作品。"
func action_text()->String:
	if stage==1 and game.draw_mode!=drawing_mode:return "回到刚才笔迹"
	return ["1 画矮踏板","确认生成","4 亲手搬动","保存作品","继续自由创作"][stage]
func short_hint()->String:return ["画个矮踏板","按当前数字确认","跳上它或亲手搬动","最后保存作品","第一件作品完成！"][stage]
func title()->String:return "%d/4 · %s"%[mini(stage+1,4),["画下你的踏板","让笔迹成为实体","让它真的派上用场","留下第一件作品","第一件作品完成"][stage]]
func body_text()->String:
	var text:String=["按1，在脚边前方画一个矮而宽的闭合轮廓。可多笔补画；松手不会生成。","画好了，再按当前工具数字或下方确认按钮。只有成功生成后才继续。","A/D靠近，W或空格跳上这件作品并站稳；也可以按4，亲手拖动它一小段。","点击保存作品，或从作品菜单保存。失败可重试；图纸也会一起保留。","完成了：你画的东西进入了世界、被亲手使用，并已实际保存。继续搭建或叫上朋友。 "][stage]
	return notice+"\n"+text if notice!="" else text
func action()->void:
	if not visible:return
	match stage:
		0:game.set_draw_mode(1);game.generator="own";game.message("画一块矮踏板，完成后再按1；可以多笔补画。")
		1:
			if not has_drawing():stage=0;notice="原画稿已清空；重新画一件即可。"
			elif game.draw_mode!=drawing_mode:game.set_draw_mode(drawing_mode)
			else:game.generate()
		2:game.set_draw_mode(4);game.set_connection_tool("move");game.message("按住标记的作品拖动至少一小段；也可用跳跃站上它。")
		3:game.save_game()
		4:dismiss()
func draw_world(canvas:Node2D)->void:
	if not visible or stage not in [2,3] or game.bag_open or game.personal_overlay_open():return
	var body=target()
	if body==null:return
	var bounds:Rect2=game.object_bounds(body.data)
	var point:Vector2=game.world_to_screen(Vector2(bounds.get_center().x,bounds.end.y))+Vector2(0,-12)
	canvas.draw_line(point,point+Vector2(0,-14),PaperTheme.TEAL,1.5,true)
	canvas.draw_string(ThemeDB.fallback_font,point+Vector2(-42,-20),"我的第一件作品",HORIZONTAL_ALIGNMENT_LEFT,-1,13,PaperTheme.TEAL)
