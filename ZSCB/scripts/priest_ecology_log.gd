extends RefCounted
## A bounded, world-local journal of completed effects. Sequence survives truncation.
const LIMIT := 256
const TITLES := {"dig_root":"牧师分根","plant_root":"牧师移栽","ground_fruit":"拾食地面朱果","hunger":"缺食损血","feed":"饲喂","cut_grass":"割取牧草","birth":"出生","revision":"改绘收笔","grass":"采食牧草","bark":"啃食树皮","hunt":"捕食牲畜","meat":"居民取肉","injury":"居民受伤","tend":"巡护活树"}
const FEEDERS := {"priest":"牧师","adventurer-lizhou":"砾舟","player":"玩家"}
var rows: Array = []

static func feed_display_text(detail: String) -> String:
	# The original feed receipt used a stable actor ID before the animal name.
	var feeder := detail.get_slice(" 向 ",0)
	if not FEEDERS.has(feeder) or not detail.begins_with(feeder+" 向 "):return detail
	var body := detail.trim_prefix(feeder+" 向 ")
	var ending := body.rfind(" 递交一份牧草，")
	if ending >= 0:body=body.left(ending)+body.substr(ending+1)
	return str(FEEDERS[feeder])+"向"+body

func record(priest, animal, kind: String, target: String, before: float, after: float, detail: String, event_at:=Vector2.INF) -> void:
	if kind=="feed":detail=feed_display_text(detail)
	var scope: Dictionary = priest._scope()
	var sequence := 1 if rows.is_empty() else int(rows.back().seq)+1
	var point := Vector2(animal.beast_x,animal.beast_y) if animal else Vector2(priest.priest_x,priest.priest_y)
	if event_at.is_finite():point=event_at
	var id: String = animal.work_id if animal else ""
	var book: String = animal.blueprint_id if animal else ""
	var row := {"seq":sequence,"kind":kind,"source_team_id":scope.team_id,"source_world_id":scope.world_id,
		"work_id":id,"blueprint_id":book,"at":[point.x,point.y],"target_id":target,
		"before":before,"after":after,"text":detail}
	rows.append(row)
	if rows.size()>LIMIT: rows.pop_front()
	var world = priest.world
	if "chronicle" in world and world.chronicle:
		var key := "priest:birth:"+id if kind=="birth" else "priest:%s:%d" % [scope.world_id,sequence]
		var name: String = animal.design.name if animal else "牧师"
		world.chronicle.record(key,kind,"priest",name+" · "+str(TITLES[kind]),detail,point,id)

func publish_review(priest, note: Dictionary, historical:=false) -> void:
	var world=priest.world
	var call_id:=str(note.get("review_call_id",""))
	var animal=priest.work_by_id(str(note.get("work_id","")))
	if not animal or call_id.is_empty() or not "chronicle" in world or not world.chronicle:return
	var status: String = "结案" if note.status=="resolved" else "继续复查"
	var detail: String = ("旧手记记有一次已完成的复查；读档所见：" if historical else "牧师复查时：")
	detail += "%s，生命 %d，已食牧草 %d 份，余肉 %d 份。" % ["已死亡" if animal.phase=="dead" else "活体",animal.health,animal.grass_meals,animal.portions]
	var at:=Vector2(animal.beast_x,animal.beast_y)
	if world.survival and world.survival.has_method("pasture_near"):
		var patches:Array=world.survival.pasture_near(at,8)
		patches.sort_custom(func(a,b):return at.distance_squared_to(Vector2(a.x,a.y))<at.distance_squared_to(Vector2(b.x,b.y)))
		if not patches.is_empty():detail+=" 附近 %s 牧草 %d/%d。" % [patches[0].id,patches[0].portions,patches[0].capacity]
	var key:="priest:review:"+str(note.note_id)+":"+call_id
	world.chronicle.record(key,"ecology_review","priest",str(animal.design.name)+" · 生态复查"+status,detail,at,animal.work_id)

func since(sequence: int, limit: int) -> Array:
	var result := []
	if limit<=0: return result
	for row in rows:
		if row.seq<=sequence:continue
		result.append(row.duplicate(true))
		if result.size()>=limit:break
	return result

static func valid(data: Variant, works: Dictionary, plans: Dictionary) -> bool:
	if not data is Array or data.size()>LIMIT:return false
	var last := 0
	for r in data:
		if not r is Dictionary or r.get("kind") not in TITLES or not finite_number(r.get("seq")):return false
		if r.seq<=last or floorf(r.seq)!=r.seq or r.seq>9007199254740991:return false
		last=int(r.seq)
		for key in ["source_team_id","source_world_id","work_id","blueprint_id","target_id","text"]:
			if not r.get(key) is String or r[key].length()>256:return false
		if r.source_team_id.is_empty() or r.source_world_id.is_empty() or r.text.is_empty():return false
		if r.kind!="tend" and not works.has(r.work_id):return false
		if not r.blueprint_id.is_empty() and not plans.has(r.blueprint_id):return false
		if not r.get("at") is Array or r.at.size()!=2:return false
		for n in [r.at[0],r.at[1],r.get("before"),r.get("after")]:
			if not finite_number(n):return false
	return true

static func finite_number(n: Variant) -> bool:
	return (n is int or n is float) and is_finite(float(n))
