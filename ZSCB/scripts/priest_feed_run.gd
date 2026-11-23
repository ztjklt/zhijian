extends RefCounted
## One cut portion remains in this priest's hands until an animal actually eats it.
var carried := 0
var job: Dictionary = {}
var route: Dictionary = {}
var endpoint := Vector2.INF

static func valid(data:Variant, works:Dictionary, active:bool) -> bool:
	if not data is Dictionary:return false
	var portions=data.get("carried",0)
	if not (portions is int or portions is float) or (portions!=0 and portions!=1):return false
	var j=data.get("job",{})
	if not j is Dictionary or active==j.is_empty():return false
	if not active:return true
	if not works.has(j.get("work_id")) or not j.get("chat") is bool:return false
	for key in ["call_id","pasture_id"]:
		if not j.get(key) is String or j[key].length()>128:return false
	if j.call_id.is_empty() or (data.get("carried",0)==0 and j.pasture_id.is_empty()):return false
	return preload("res://scripts/priest_species.gd").pair(j.get("field"),1e6)

func restore(data:Dictionary) -> void:
	carried=int(data.get("carried",0))
	job=data.get("job",{}).duplicate(true)
	route={}
	endpoint=Vector2.INF

func begin(p,c:Dictionary,chat:bool) -> void:
	var a=p.work_by_id(c.work_id)
	if not job.is_empty() or p.activity not in ["idle","wait"] or not a or a.phase in ["drawing","dead"] or not a.has_action("graze_grass") or a.satiety>=65:
		p.chat_notice="这只个体或牧师的工序已改变，本轮未开始饲喂。"
		p.progress=p.chat_notice
		return
	var field:=Vector2.ZERO
	if carried==0:
		var patches:Array=p.world.survival.pasture_near(Vector2(p.priest_x,p.priest_y),32)
		var index:=patches.find_custom(func(f):return f.id==c.pasture_id and f.portions>0)
		if index<0:
			p.progress="这处牧草已无法割取。"
			p.chat_notice=p.progress
			return
		field=Vector2(patches[index].x,patches[index].y)
	job={"work_id":c.work_id,"pasture_id":c.pasture_id,"field":[field.x,field.y],"call_id":c.call_id,"chat":chat}
	p.activity="feed"
	p.progress="准备把手里的牧草送给"+str(a.design.name) if carried else "动身去割一份牧草"
	p.goal=c.goal
	p.model_reason=c.reason
	p.last_eco_call=c.call_id
	if chat:p._chat_line("god",c.reply,c,a.work_id)
	p.chat_notice=p.progress
	p._keep_notes(c)

func _finish(p,reason:String) -> void:
	if carried:reason+=" 手中保留已割的一份。"
	p.progress=reason
	p.chat_notice=reason
	p.record_outcome("饲喂",p.model_reason,reason,job.work_id,job.call_id)
	if job.chat:p._chat_line("status",reason)
	p.activity="idle"
	job={}
	route={}
	endpoint=Vector2.INF

func step(p,dt:float) -> void:
	var at:=Vector2(p.priest_x,p.priest_y)
	var a=p.work_by_id(job.work_id)
	if not a or a.phase in ["dead","drawing"] or a.satiety>=65:
		_finish(p,"原个体已无法接草，结束这次饲喂。")
		return
	var goal:=Vector2(job.field[0],job.field[1])
	if carried:
		var accepted:Dictionary=p.feed_livestock(job.work_id,at,"priest")
		if accepted.ok:
			carried=0
			_finish(p,"已当面喂给%s一份牧草，饱食 %.1f → %.1f。" % [a.design.name,accepted.before,accepted.after])
			return
		goal=Vector2(a.beast_x,a.beast_y)
	if route.is_empty() or goal.distance_to(endpoint)>.55:
		endpoint=goal
		route=p.world.paper_nav_route(at,goal)
	if not route.get("ok",false):
		_finish(p,"通往%s的路不可达。" % (a.design.name if carried else job.pasture_id))
		return
	var advance:Dictionary=p.world.paper_nav_step(route,at,dt,2.0)
	if not advance.get("ok",false):
		_finish(p,"脚面已变，当前这条路走不通。")
		return
	var foot:Vector2=advance.at
	p.priest_x=foot.x
	p.priest_y=foot.y
	p.progress=("携草前往「%s」" % a.design.name if carried else "去草地 "+str(job.pasture_id))+" · 脚点（%.1f，%.1f）" % [foot.x,foot.y]
	if not advance.get("arrived",false):return
	if carried:
		var handed:Dictionary=p.feed_livestock(job.work_id,foot,"priest")
		if handed.ok:
			carried=0
			_finish(p,"已当面喂给%s一份牧草，饱食 %.1f → %.1f。" % [a.design.name,handed.before,handed.after])
		else:_finish(p,handed.error)
		return
	if not p.world.survival.graze_pasture(job.pasture_id,foot):
		_finish(p,"抵达后草量或脚面已变，未割到牧草。")
		return
	carried=1
	route={}
	endpoint=Vector2.INF
	var left:=int(p.world.survival.pastures[job.pasture_id].portions)
	p.ecology_log.record(p,a,"cut_grass",job.pasture_id,left+1,left,"牧师到草地割下一份，准备喂给%s，牧草余 %d 份。" % [a.design.name,left],foot)
