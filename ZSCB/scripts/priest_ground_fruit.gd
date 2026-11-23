extends RefCounted
## A ground fruit is a single world object. Only the survival ledger can take it.
const Ground:=preload("res://scripts/priest_ground.gd")
const Obstacles:=preload("res://scripts/priest_obstacles.gd")
const FULL:=65.0
const MOUTH_REACH:=.16
const BITE_DURATION:=1.48

static func same_floor(a, fruit:Vector2) -> bool:
	var floor_row:=Ground.trace(a.world,Vector2(a.beast_x,a.beast_y),fruit.x)
	return not floor_row.is_empty() and absf(float(floor_row.y)+.085-fruit.y)<=.11

static func sense(a) -> void:
	var previous:String=a.fruit_target.get("id","")
	a.fruit_target={}
	if a.satiety>=FULL or not a.world.survival or not a.world.survival.has_method("ground_fruit_near"):return
	var feet:=Vector2(a.beast_x,a.beast_y)
	var best:float=a.design.sight
	for item in a.world.survival.ground_fruit_near(feet,best):
		var at:=Vector2(item.x,item.y)
		var distance:=feet.distance_to(at)
		if distance>best or not same_floor(a,at):continue
		if not (previous==item.id and a.blocked_by.is_empty()) and not reachable(a,feet,at):continue
		best=distance
		a.fruit_target=item

# Trial movement uses the body's original slope contact and silhouette before
# choosing a fruit. A nearer blocked fruit must not pin the animal in place.
static func reachable(a,feet:Vector2,fruit:Vector2) -> bool:
	var slope:float=a._slope()
	var facing:int=a.face
	var trial_face:int=a.face
	var mouth:Vector2=a.form.fruit_mouth(feet,slope,facing,.5)
	if absf(fruit.x-feet.x)>.15 and (fruit.x-feet.x)*(mouth.x-feet.x)<0:facing=-facing
	for i in ceili(float(a.design.sight)/.16)+10:
		mouth=a.form.fruit_mouth(feet,slope,facing,.5)
		var dx:=fruit.x-mouth.x
		if absf(dx)<=.05:
			return mouth.distance_to(fruit)<=MOUTH_REACH and Obstacles.contact(a.world,mouth,fruit) and (trial_face==facing or Obstacles.movement_blocker(a,feet,feet,slope,facing,trial_face).is_empty())
		if not a.has_action("ground_walk"):return false
		var x:=feet.x+clampf(dx,-.16,.16)
		var floor_row:=Ground.trace(a.world,feet,x)
		if floor_row.is_empty():return false
		var next:=Vector2(x,floor_row.y)
		slope=atan2((next.y-feet.y)*signf(x-feet.x),absf(x-feet.x))
		var pose:=Obstacles.walking_pose(a,feet,next,slope,trial_face,1 if next.x>=feet.x else -1)
		if not pose.blocker.is_empty():return false
		trial_face=pose.face
		feet=next
	return false

static func approach(a,dt:float) -> bool:
	if a.satiety>=FULL or a.fruit_target.is_empty():return false
	var fruit:=Vector2(a.fruit_target.x,a.fruit_target.y)
	var feet:=Vector2(a.beast_x,a.beast_y)
	var slope:float=a._slope()
	var facing:int=a.face
	var mouth:Vector2=a.form.fruit_mouth(feet,slope,facing,.5)
	if absf(fruit.x-feet.x)>.15 and (fruit.x-feet.x)*(mouth.x-feet.x)<0:
		facing=-facing
		mouth=a.form.fruit_mouth(feet,slope,facing,.5)
	var dx:=fruit.x-mouth.x
	if absf(dx)>.05:
		if not a.has_action("ground_walk"):return false
		a.phase="walk"
		a._walk(dt,feet.x+dx)
		if a.blocked_by!="":a.fruit_target={}
		elif absf(a.beast_x-feet.x)>.0001:leave_track(a)
		return true
	if mouth.distance_to(fruit)>MOUTH_REACH or not same_floor(a,fruit):return false
	if facing!=a.face and not Obstacles.permits(a,feet,feet,slope,facing):return false
	a.face=facing
	a.phase="pickup"
	a.bite_phase=0
	a.fruit_bite_id=a.fruit_target.id
	return true

static func bite(a,dt:float) -> bool:
	var previous:float=a.bite_phase
	a.bite_phase=minf(1,previous+dt/BITE_DURATION)
	if previous<.5 and a.bite_phase>=.5:
		var feet:=Vector2(a.beast_x,a.beast_y)
		var mouth:Vector2=a.form.fruit_mouth(feet,a._slope(),a.face,a.bite_phase)
		for item in a.world.survival.ground_fruit_near(mouth,MOUTH_REACH):
			if item.id!=a.fruit_bite_id or a.satiety>=FULL:continue
			var fruit:=Vector2(item.x,item.y)
			if not same_floor(a,fruit) or not Obstacles.contact(a.world,mouth,fruit):continue
			var receipt:Dictionary=a.world.survival.take_ground_fruit(item.id,mouth,a.work_id)
			if receipt.get("ok",false):
				var before:float=a.satiety
				a.satiety=minf(100,before+30)
				a.fruit_meals+=1
				a.last_target=item.id
				a.keeper.ecology_log.record(a.keeper,a,"ground_fruit",item.id,receipt.before,receipt.after,"%s 拾食一枚地面朱果，饱食 %.1f → %.1f。"%[a.design.name,before,a.satiety],mouth)
			break
	if a.bite_phase>=1:
		a.phase="search" if a.has_action("ground_walk") else "rest"
		a.fruit_target={}
		a.fruit_bite_id=""
		a.sense_left=0
	return true

static func leave_track(a) -> void:
	var foot:=Vector2(a.beast_x,a.beast_y)
	if not a.fruit_tracks.is_empty() and absf(float(a.fruit_tracks.back().step_x)-foot.x)<.24:return
	var shapes:Array=a.form.world_parts(foot,a._slope(),a.face,a.stride,"walk",0)
	var nearest:=.10
	var contact:=Vector2.INF
	for i in shapes.size():
		if a.design.parts[i].motion not in ["stride","sway"]:continue
		for point:Vector2 in shapes[i]:
			var floor_row:=Ground.nearby(a.world,point.x,point.y,.10)
			if floor_row.is_empty():continue
			var gap:=absf(point.y-float(floor_row.y))
			if gap<nearest:
				nearest=gap
				contact=Vector2(point.x,floor_row.y)
	if contact.is_finite():
		a.fruit_tracks.append({"at":contact,"step_x":foot.x,"face":a.face,"life":4.0})
		if a.fruit_tracks.size()>16:a.fruit_tracks.pop_front()
