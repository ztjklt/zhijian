extends RefCounted
## A completed brush design and its own local movement, appetite and tree wounds.
const Form := preload("res://scripts/ink_life_form.gd")
const Obstacles:=preload("res://scripts/priest_obstacles.gd")
const Flight:=preload("res://scripts/priest_flight.gd")
const FoodWeb := preload("res://scripts/priest_food_web.gd")
const Ground := preload("res://scripts/priest_ground.gd")
const BIRTH_X := -1.48
const SIGHT := 13.0
const MEALS_PER_TREE := 3
const INK_SPEED := 2.25
const STARVATION_GRACE_SECONDS:=60.0
const STARVATION_DAMAGE_INTERVAL:=15.0
const STARVATION_DAMAGE:=2.0
const ANIMAL_ACTIONS := {"eat":"啃食","walk":"寻树","search":"嗅探","rest":"伏地休息","flee":"逃离捕食兽","hunt":"扑咬","chase":"追逐","dead":"遗骸","takeoff":"离地","fly":"飞行","land":"降落"}
var world
var game
var protected_tree := ""
var work_id := ""
var team_id := ""
var world_id := ""
var habitat_id := ""
var served_model := ""
var keeper
var blueprint_id := ""
var health := 36.0
var portions := 0
var stamina := 1.0
var hostile_left:=0.0
var hostile_reason:=""
var flight_energy:=1.0
var perch_y:=0.0
var takeoffs:=0
var landings:=0
var hunger_seconds := 0.0
var last_metabolism_rate := -1.0
var delivered_meals := 0
var blocked_by := ""
var fruit_tracks:Array[Dictionary]=[]
var avoided_person:=""
var fruit_meals:=0
var fruit_target:Dictionary={}
var fruit_bite_id:=""
var grass_meals:=0
var grass_target:Dictionary={}
var grazing:=preload("res://scripts/priest_grazing_memory.gd").new()
var hits := 0
var kills := 0
var last_target := ""
var other_id := ""
var check_restored_footing:=false
var sense_left := 0.0
var contact_timer := 0.0

func has_action(action:String) -> bool:
	return action in design.get("actions",[])
var revision := {}

var design := {}
var form: RefCounted
var phase := "idle"
var cursor := 0.0
var beast_x := BIRTH_X
var beast_y := 0.0
var face := 1
var satiety := 20.0
var stride := 0.0
var scan_in := 0.0
var bite_phase := 0.0
var bite_flash := 0.0
var last_tree := ""
var bark_point := Vector2.ZERO
var target_id := ""
var eaten := {}
var call_id := ""

func depends_on_food() -> bool:
	return has_action("eat_ground_fruit") or has_action("graze_grass") or has_action("graze_bark") or has_action("hunt_livestock")

func _init(habitat_world) -> void:
	world = habitat_world
	game = world.game

func _edible(tree) -> bool:
	return is_instance_valid(tree) and tree.is_inside_tree() and not tree.is_queued_for_deletion() and tree.entity_id != protected_tree and tree.alive and tree.health > 0 and Form.FOOD.has(tree.kind) and int(eaten.get(tree.entity_id,0)) < MEALS_PER_TREE

func _find_tree() -> String:
	var best := INF
	var id := ""
	var where := Vector2(beast_x,beast_y)
	for tree in world.entities:
		if not _edible(tree): continue
		var distance: float = where.distance_to(tree.position)
		if distance > SIGHT: continue
		var support:=Ground.trace(world,where,tree.position.x)
		if support.is_empty() or absf(tree.position.y-support.y)>.55: continue
		var score := distance - (1.5 if tree.kind == design.get("favorite","oak") else 0.0)
		if score < best:
			best = score
			id = tree.entity_id
	return id

func _slope() -> float:
	var at:=Vector2(beast_x,beast_y)
	var left:=Ground.trace(world,at,beast_x-.35)
	var right:=Ground.trace(world,at,beast_x+.35)
	return atan2(float(right.get("y",beast_y))-float(left.get("y",beast_y)),.70)

func _walk(delta: float, to: float) -> void:
	var previous := beast_x
	if satiety<=0 and depends_on_food():delta*=.65
	var next_x:=move_toward(beast_x,to,delta*float(design.pace)*cos(_slope()))
	var surface:=Ground.trace(world,Vector2(beast_x,beast_y),next_x)
	if surface.is_empty():
		target_id=""
		face*=-1
		return
	var facing:=1 if next_x>=beast_x else -1
	if not form.occupancy.is_empty():
		var from:=Vector2(beast_x,beast_y)
		var to_foot:=Vector2(next_x,surface.y)
		var slope:=_slope()
		var pose:=Obstacles.walking_pose(self,from,to_foot,slope,face,facing)
		if not pose.blocker.is_empty():
			blocked_by=pose.blocker
			target_id=""
			return
		facing=pose.face
	blocked_by=""
	beast_x=next_x
	beast_y=surface.y
	if absf(beast_x-previous) > .00001: face = facing
	stride = fmod(stride+absf(beast_x-previous)*(8.2 if str(design.get("gait","amble")) == "trot" else 6.5),TAU)

func spend_satiety(delta:float,rate:float) -> void:
	last_metabolism_rate+=rate
	satiety=maxf(0.0,satiety-delta*rate)

func _forage(delta: float) -> void:
	spend_satiety(delta,.35)
	if phase == "rest":
		stride = fmod(stride+delta*2.0,TAU)
		if satiety > 42.0: return
		phase = "search"
	var tree = world.entity_by_id(target_id) if target_id != "" else null
	if not _edible(tree):
		if target_id != "":
			target_id = ""
			scan_in = 0.0
			bite_phase = 0.0
		phase = "search"
		scan_in -= delta
		if scan_in <= 0:
			scan_in = .35
			target_id = _find_tree()
			tree = world.entity_by_id(target_id) if target_id != "" else null
		if tree == null:
			var limits:=Ground.bounds(world)
			var edge: float = limits.y-.9 if face > 0 else limits.x+.9
			if absf(beast_x-edge) < .02: face *= -1
			else: _walk(delta,edge)
			return
	var slope := _slope()
	var side := 1 if tree.position.x >= beast_x else -1
	# Align the animated muzzle with the near face of the actual trunk on this slope.
	var stand: float = tree.position.x - side*(.13+.84*cos(slope)) + .48*sin(slope)
	if absf(stand-beast_x) > .045:
		phase = "walk"
		_walk(delta,stand)
		return
	phase = "eat"
	face = side
	bite_phase += delta / (1.00 if design.get("feeding","gnaw") == "gnaw" else 1.48)
	if bite_phase < 1.0: return
	bite_phase = 0.0
	var mouth := Vector2(beast_x,beast_y)+Vector2(face*.85,.48).rotated(slope)
	if absf(mouth.x-tree.position.x) > .32 or absf(mouth.y-tree.position.y) > 1.4: return
	var before: float = tree.health
	var damage := 10.0 if design.get("feeding","gnaw") == "gnaw" else 14.0
	# Nibbling shares the tree's durable health and clipped geometry.
	# Grazing leaves bark flecks instead of broadcasting a combat impact.
	var bite_y := (float(eaten.get(tree.entity_id,0))-1.0)*.105
	bark_point = mouth+Vector2(0,bite_y)
	tree.damage(damage,bark_point,Vector2.ZERO)
	tree.hurt_timer = 0.0
	if tree.alive: tree.state = "idle"
	var consumed: float = before-tree.health
	if consumed <= 0: return
	if keeper:
		keeper.ecology_log.record(keeper,self,"bark",tree.entity_id,before,tree.health,"%s 啃食 %s，树木生命 %d → %d。" % [design.name,tree.entity_id,before,tree.health])
	eaten[tree.entity_id] = int(eaten.get(tree.entity_id,0))+1
	satiety = minf(100,satiety+25.0*consumed/damage)
	last_tree = tree.entity_id
	bite_flash = 1.0
	if satiety >= 80.0:
		phase = "rest"
		target_id = ""
	elif not _edible(tree):
		target_id = ""
		phase = "search"
		scan_in = 0.0

func _clear_restored_footing(delta:float) -> bool:
	var at:=Vector2(beast_x,beast_y)
	var slope:=_slope()
	var previous:=Obstacles.clearance(self,at,slope,face)
	if previous<.00008:
		check_restored_footing=false
		return false
	var step:=minf(.045,delta*float(design.pace))
	var best:=previous
	var next:=at
	for direction in [-1.0,1.0]:
		var x:float=at.x+direction*step
		var floor_row:=Ground.trace(world,at,x)
		if floor_row.is_empty():continue
		var candidate:=Vector2(x,floor_row.y)
		var severity:=Obstacles.clearance(self,candidate,slope,face)
		if severity<best-.000001:
			best=severity
			next=candidate
	if next!=at:
		beast_x=next.x
		beast_y=next.y
		stride=fmod(stride+at.distance_to(next)*6.5,TAU)
		return true
	check_restored_footing=false
	return false

## Forecast at the ordinary ground metabolism, conditional on receiving no more food.
## Flight, pursuit, another injury or a meal can change the actual outcome.
func starvation_facts() -> Dictionary:
	var zero_seconds:=hunger_seconds if satiety<=0 else 0.0
	var next_tick:=maxf(STARVATION_GRACE_SECONDS,(floorf(zero_seconds/STARVATION_DAMAGE_INTERVAL)+1.0)*STARVATION_DAMAGE_INTERVAL)
	var seconds_to_empty:=satiety/FoodWeb.SATIETY_LOSS
	var next_damage:=seconds_to_empty+next_tick-zero_seconds
	return {"seconds_at_zero":snappedf(zero_seconds,.01),"currently_at_zero":satiety<=0,
		"damage_per_tick":STARVATION_DAMAGE,"grace_s":STARVATION_GRACE_SECONDS,"damage_interval_s":STARVATION_DAMAGE_INTERVAL,
		"if_no_food_at_base_ground_rate":{"empty_in_s":snappedf(seconds_to_empty,.01),"next_damage_in_s":snappedf(next_damage,.01),
		"death_from_hunger_in_s":snappedf(next_damage+maxf(0,ceilf(health/STARVATION_DAMAGE)-1)*STARVATION_DAMAGE_INTERVAL,.01)}}

func advance(delta: float, at_easel: bool, spared_tree: String) -> void:
	protected_tree = spared_tree
	if not fruit_tracks.is_empty():
		for track in fruit_tracks:track.life-=delta
		while not fruit_tracks.is_empty() and fruit_tracks[0].life<=0:fruit_tracks.pop_front()
	bite_flash = maxf(0,bite_flash-delta)
	if phase == "drawing":
		if at_easel:
			cursor = minf(form.length,cursor+delta*INK_SPEED)
			if cursor >= form.length: phase = "search"
	elif design.has("parts") and keeper!=null:
		hostile_left=maxf(0,hostile_left-delta)
		if phase!="dead" and check_restored_footing and _clear_restored_footing(delta):return
		last_metabolism_rate=0.0
		if not Flight.step(self,delta): FoodWeb.step(self,delta)
		if phase!="dead" and depends_on_food():
			if satiety>0:hunger_seconds=0
			else:
				var previous_interval:=floori(hunger_seconds/STARVATION_DAMAGE_INTERVAL)
				hunger_seconds+=delta
				if hunger_seconds>=STARVATION_GRACE_SECONDS and floori(hunger_seconds/STARVATION_DAMAGE_INTERVAL)>previous_interval:
					var before:=health
					health=maxf(0,health-STARVATION_DAMAGE)
					if health<=0:phase="dead"
					keeper.ecology_log.record(keeper,self,"hunger","",before,health,"%s 持续缺食，生命 %d → %d。" % [design.name,before,health])
	else:
		last_metabolism_rate=0.0
		_forage(delta)

func snapshot() -> Dictionary:
	var record := {"version":1,"work_id":work_id,"author_id":"priest","team_id":team_id,"world_id":world_id,"served_model":served_model,"habitat_id":habitat_id,"design":design.duplicate(true),"call_id":call_id,"phase":phase,"cursor":cursor,
		"x":beast_x,"y":beast_y,"face":face,"satiety":satiety,"stride":stride,"target":target_id,
		"bite":bite_phase,"eaten":eaten.duplicate(),"last_tree":last_tree}
	if blueprint_id!="":
		record.blueprint_id=blueprint_id
		record.eco={"hunger_seconds":hunger_seconds,"delivered_meals":delivered_meals,"health":health,"hostile_left":hostile_left,"hostile_reason":hostile_reason,"flight_energy":flight_energy,"perch_y":perch_y,"takeoffs":takeoffs,"landings":landings,"fruit_meals":fruit_meals,"avoided_person":avoided_person,"fruit_bite_id":fruit_bite_id,"grass_meals":grass_meals,"portions":portions,"stamina":stamina,"hits":hits,"kills":kills,"last_target":last_target,"other_id":other_id,"cooldown":contact_timer}
		if not grazing.places.is_empty() or (grass_meals>0 and phase!="dead"):record.eco.grazed_places=grazing.places.duplicate(true)
	if not revision.is_empty(): record.revision=revision.duplicate(true)
	return record

func restore(data: Dictionary) -> void:
	last_metabolism_rate=-1.0
	blueprint_id=str(data.get("blueprint_id",""))
	var eco:Dictionary=data.get("eco",{})
	hostile_left=float(eco.get("hostile_left",0))
	hostile_reason=str(eco.get("hostile_reason",""))
	flight_energy=float(eco.get("flight_energy",1))
	perch_y=float(eco.get("perch_y",0))
	takeoffs=int(eco.get("takeoffs",0))
	landings=int(eco.get("landings",0))
	health=float(eco.get("health",36))
	portions=int(eco.get("portions",0))
	stamina=float(eco.get("stamina",1))
	hunger_seconds=float(eco.get("hunger_seconds",0))
	delivered_meals=int(eco.get("delivered_meals",0))
	fruit_meals=int(eco.get("fruit_meals",0))
	avoided_person=str(eco.get("avoided_person",""))
	fruit_bite_id=str(eco.get("fruit_bite_id",""))
	grass_meals=int(eco.get("grass_meals",0))
	hits=int(eco.get("hits",0))
	kills=int(eco.get("kills",0))
	last_target=str(eco.get("last_target",""))
	other_id=str(eco.get("other_id",""))
	contact_timer=float(eco.get("cooldown",0))
	work_id = data.work_id
	team_id = data.team_id
	world_id = data.world_id
	habitat_id = data.habitat_id
	served_model = data.get("served_model","")
	revision = data.get("revision",{}).duplicate(true)
	design = data.design.duplicate(true)
	form = Form.new(design)
	check_restored_footing=not form.occupancy.is_empty()
	phase = data.phase
	cursor = clampf(data.cursor,0,form.length)
	beast_x = data.x
	beast_y=data.get("y",world.travel_height(beast_x))
	face = int(data.face)
	satiety = data.satiety
	stride = data.stride
	target_id = data.target
	bite_phase = data.bite
	eaten = data.eaten.duplicate()
	last_tree = data.last_tree
	call_id = data.call_id
	grazing.restore(self,eco)

func action_label() -> String:
	if phase=="walk" and not grazing.aim.is_empty() and grass_target.is_empty():return "返回取食过的草地"
	if phase=="rest" and grazing.aim.get("in_sight",false) and grass_target.is_empty():return "在草地旁等下一茬"
	if phase=="drawing":return "正在运笔"
	if phase=="dead":return "遗骸"
	if blocked_by!="" and phase in ["search","walk"]:return "寻食受阻 · "+("脚面中断" if blocked_by=="ground" else Ground.obstacle_name(blocked_by.get_slice("-",0)))
	if phase=="flee" and not avoided_person.is_empty():return "避开靠近的人"
	if phase=="pickup":return "低头拾果"
	if phase=="walk" and not fruit_target.is_empty():return "循地觅果"
	if design.has("parts") and phase=="walk":return "去草地" if not grass_target.is_empty() else "步行"
	if phase=="eat" and not grass_target.is_empty():return "食草"
	return ANIMAL_ACTIONS.get(phase,phase)

func field_warning() -> String:
	if phase in ["dead","drawing"]: return ""
	if hostile_left > 0: return "敌意"
	if phase == "flee": return "避人" if not avoided_person.is_empty() else "逃险"
	if phase in ["chase","hunt"]: return "追猎"
	if satiety <= 0 and (not design.has("parts") or depends_on_food()): return "缺食"
	return ""

func _paint_field_sign(canvas: Node2D, screen: Vector2, selected: bool) -> void:
	var warning := field_warning()
	if (not selected and warning.is_empty()) or not is_finite(form.highest_screen_y): return
	var tip := Vector2(screen.x, form.highest_screen_y - 4.0)
	if not warning.is_empty():
		var ink := Color("805820") if warning == "缺食" else Color("863e34")
		canvas._label(tip - Vector2(0, 6), warning, ink)
	if selected:
		var notch := PackedVector2Array([tip + Vector2(-4,-5), tip, tip + Vector2(4,-5)])
		canvas.draw_polyline(notch,Color("fff7e8"),4.0,true)
		canvas.draw_polyline(notch,Color("365e55"),2.0,true)

func paint(canvas: Node2D) -> Vector2:
	var ppu: float = game.PIXELS_PER_UNIT
	var base := Vector2(beast_x,beast_y)
	var screen: Vector2 = game.world_to_screen(base)
	var view: Rect2 = game.get_viewport_rect().grow(ppu*2.5)
	var panel = game.divine_panel
	var selected: bool = panel != null and panel.observed_animal(canvas) == self
	if form != null and view.has_point(screen):
		for track in fruit_tracks:
			var spot:Vector2=game.world_to_screen(track.at)+Vector2(0,2)
			var ink:=Color("81583a")
			ink.a=clampf(track.life/3.0,0,.8)
			canvas.draw_line(spot,spot+Vector2(track.face*4.0,-.8),ink,1.8,true)
		var tip: Vector2 = form.paint(canvas,game,base,_slope(),face,str(design.get("gait","amble")),stride,phase,bite_phase,cursor if phase == "drawing" else INF)
		if phase == "drawing": return game.world_to_screen(tip)
		_paint_field_sign(canvas,screen,selected)
	if last_tree == "": return Vector2.INF
	var tree = world.entity_by_id(last_tree)
	if tree == null: return Vector2.INF
	var settled: bool = phase == "rest" and absf(beast_x-tree.position.x) < 2.0
	if bite_flash <= 0 and not settled: return Vector2.INF
	var at: Vector2 = game.world_to_screen(tree.position+Vector2(.18,1.05))
	if not view.has_point(at): return Vector2.INF
	if selected:
		var words := "%s · 啃痕 %d　%d/%d" % [Form.FOOD[tree.kind],int(eaten[last_tree]),roundi(tree.health),roundi(tree.max_health)]
		canvas._label(at+Vector2(ppu*1.08,ppu*.24),words,Color("795139"))
	if bite_flash > .3:
		var age := 1.0-bite_flash
		for i in 5:
			var offset := Vector2(-face*(i+1)*.22*age,(1.3+.15*i)*age-4.4*age*age)
			var chip: Vector2 = game.world_to_screen(bark_point+offset)
			canvas.draw_line(chip,chip+Vector2((i%2*2-1)*3,1.5),Color("a47f51"),1.6,true)
	return Vector2.INF
