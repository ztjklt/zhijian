extends RefCounted
## Each entry is a place this animal really took a portion. Current stock is only sensed on site.
const LIMIT:=4
var places:Array=[]
var aim:Dictionary={}

func remember(id:String,foot:Vector2) -> void:
	for i in places.size():
		if places[i].id==id:
			places.remove_at(i)
			break
	places.push_front({"id":id,"at":[foot.x,foot.y]})
	if places.size()>LIMIT:places.pop_back()

func restore(a,eco:Dictionary) -> void:
	places=eco.get("grazed_places",[]).duplicate(true)
	aim={}
	if eco.has("grazed_places") or a.phase=="dead" or not a.keeper or a.grass_meals==0:return
	# Past editions kept the actual bite foot and plot ID in this world's ecology ledger.
	for row in a.keeper.ecology_log.rows:
		if row.kind=="grass" and row.work_id==a.work_id:
			remember(row.target_id,Vector2(row.at[0],row.at[1]))

func choose(a,visible:Array,sight:float) -> void:
	aim={}
	var foot:=Vector2(a.beast_x,a.beast_y)
	var remote:={}
	for place in places.duplicate():
		var last_foot:=Vector2(place.at[0],place.at[1])
		var current:Dictionary={}
		for plot in visible:
			if plot.id==place.id:
				current=plot
				break
		if not current.is_empty():
			if a.FoodWeb.pasture_barrier(a,current).is_empty():
				aim={"id":place.id,"at":[current.x,current.y],"in_sight":true}
				return
		elif foot.distance_to(last_foot)+1.15<sight:
			# The entire original bite reach is visible and this plot is gone.
			places.erase(place)
		elif remote.is_empty():
			remote={"id":place.id,"at":place.at,"in_sight":false}
	aim=remote

func approach(a,delta:float) -> bool:
	if aim.is_empty() or not a.has_action("ground_walk"):return false
	var at:=Vector2(a.beast_x,a.beast_y)
	var goal:=Vector2(aim.at[0],aim.at[1])
	if aim.in_sight and a.FoodWeb.can_reach_portion(a,at,goal):
		if a.phase!="eat" or a.contact_timer<=0:a.phase="rest"
	else:
		a.phase="walk"
		a._walk(delta,goal.x)
	return true

static func valid(value:Variant) -> bool:
	if not value is Array or value.size()>LIMIT:return false
	var seen:={}
	for row in value:
		if not row is Dictionary or not row.get("id") is String or row.id.is_empty() or row.id.length()>128 or seen.has(row.id):return false
		if not row.get("at") is Array or row.at.size()!=2:return false
		for n in row.at:
			if not (n is float or n is int) or not is_finite(float(n)) or absf(n)>1e6:return false
		seen[row.id]=true
	return true
