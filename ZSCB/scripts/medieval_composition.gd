class_name MedievalComposition
extends RefCounted
## Authored scene groups, not a random scatter. IDs are independent of list order
## and begin at 100 so an old world's damaged/dead originals are never replaced.
const CONTENT_VERSION := 3
const FOLIAGE := ["grass_meadow","grass_tall","reeds","wildflowers","bush","wheat"]
const GROUND_PATROLS := {
	"villager-0":[21.0,27.0],"villager-1":[27.0,34.0],"villager-2":[34.0,40.0],
	"villager-3":[49.0,57.0],"villager-4":[62.0,67.0],"horse-0":[52.0,67.0],
	"general-0":[65.0,72.0],"knight-0":[76.0,85.0],
	"villager-100":[4.0,15.0],"villager-101":[40.0,49.0],
	"villager-102":[107.0,115.0],"villager-103":[116.0,125.0],
	"villager-104":[126.0,136.0],"villager-105":[138.0,144.0],
	"villager-106":[149.0,159.0],"knight-100":[164.0,177.0],
	"general-100":[168.0,178.0],"horse-100":[111.0,126.0]}

static func records() -> Array:
	return version2_records().filter(func(record):return not retired_id(record.id))

static func retired_id(id:String)->bool:
	if id in ["oak-1","oak-3","pine-1","orchard_tree-101","orchard_tree-102","orchard_tree-104"]:return true
	var kind:=id.get_slice("-",0)
	var suffix:=id.get_slice("-",1)
	return kind in FOLIAGE and suffix.is_valid_int() and int(suffix)%2==1

static func version2_records() -> Array:
	var result:Array=[]
	var counters:Dictionary={}
	# Village commons have a well and benches between the existing houses.
	# Market goods, river landings, castle gardens, orchards and abbey cloister
	# each have distinct silhouettes and open walking space.
	var groups:Dictionary={
		"orchard_tree":[11.3,19.0,101.5,145.4,160.9],
		"well":[25.5,175.4],
		"forge":[110.3,169.8],
		"tavern":[121.0],
		"windmill":[114.4],
		"watermill":[125.4],
		"tent":[165.8,174.1,178.0],
		"ruin_arch":[148.8,152.0,155.2,158.4],
		"fountain":[74.7,83.0],
		"bench":[23.0,26.8,49.4,73.0,110.0,149.0,156.8,172.1],
		"cart_goods":[40.4,52.7,119.5,141.4,166.2],
		"haystack":[18.3,65.6,88.8,110.1,116.7,121.0,142.6,176.5],
		"fence":[1.0,18.4,36.8,86.5,105.7,108.7,117.6,120.0,123.7,162.3,179.0],
		"signpost":[2.2,20.4,54.0,67.0,103.7,124.4,143.0,162.7,179.2],
		"lantern":[24.3,36.0,46.0,53.7,69.0,86.0,112.0,127.4,139.8,151.0,164.0,173.0],
		"barrel":[9.2,26.5,39.2,50.1,66.8,87.8,115.3,125.4,140.6,148.8,167.8],
		"crate":[6.7,27.0,40.0,52.0,67.5,88.2,111.1,118.7,127.2,139.3,157.3,171.8]}
	for kind in groups:
		for x in groups[kind]:_append(result,counters,kind,float(x))
	# The stone landing crosses a shallow side inlet beside the road crossing.
	# Its base is embedded in the river bank, with its arches visible over water.
	_append(result,counters,"bridge_stone",134.0,-1.04)
	# Each upper crate inherits its lower crate's actual transformed top face.
	for stack in [[67.5,"crate-104"],[88.2,"crate-105"],[111.1,"crate-106"],[127.2,"crate-108"]]:
		var record:=_append(result,counters,"crate",stack[0])
		record["stack_on"]=stack[1]
	# Irregular six-plant patches: under canopy, against garden walls, at field
	# margins and along the actual wet banks. Clear gaps distinguish districts.
	var patches:Array=[
		[0.2,"meadow"],[3.1,"wood"],[6.1,"wood"],[9.7,"wood"],[13.0,"wood"],[16.0,"wood"],
		[21.0,"garden"],[33.5,"garden"],[36.0,"garden"],
		[41.2,"meadow"],[48.0,"garden"],[53.6,"bank"],[62.0,"bank"],
		[69.4,"garden"],[85.2,"garden"],
		[90.0,"wood"],[94.2,"wood"],[103.5,"meadow"],
		[109.2,"field"],[114.7,"field"],[118.0,"field"],[121.6,"field"],
		[128.3,"bank"],[137.8,"bank"],
		[146.1,"garden"],[157.1,"wood"],
		[163.1,"meadow"],[168.2,"meadow"],[176.9,"meadow"]]
	var palettes:Dictionary={"wood":["grass_meadow","bush","grass_tall","wildflowers","grass_meadow","grass_tall"],"meadow":["grass_meadow","wildflowers","grass_tall","grass_meadow","wildflowers","grass_meadow"],"garden":["wildflowers","grass_meadow","wildflowers","bush","grass_meadow","wildflowers"],"bank":["reeds","grass_tall","reeds","grass_meadow","reeds","grass_tall"],"field":["wheat","wheat","grass_meadow","wheat","wildflowers","wheat"]}
	for index in patches.size():
		var patch:Array=patches[index]
		var offsets:Array=[0.0,0.31,0.74,1.23,1.70,2.19] if index%2==0 else [0.0,0.46,0.82,1.11,1.77,2.33]
		for n in offsets.size():
			var x:float=patch[0]+offsets[n]
			var record:=_append(result,counters,palettes[patch[1]][n],x)
			record["natural_ground"]=patch[1]=="bank"
	return result

static func _append(result:Array,counters:Dictionary,kind:String,x:float,y:float=-999.0)->Dictionary:
	var suffix:int=counters.get(kind,100)
	counters[kind]=suffix+1
	var record:Dictionary={"kind":kind,"x":x,"suffix":suffix,"id":kind+"-"+str(suffix),"y":y}
	result.append(record)
	return record

static func actor_records() -> Array:
	var result:Array= [
		{"kind":"villager","suffix":100,"x":9.5},{"kind":"villager","suffix":101,"x":44.5},
		{"kind":"villager","suffix":102,"x":111.0},{"kind":"villager","suffix":103,"x":120.5},
		{"kind":"villager","suffix":104,"x":131.0},{"kind":"villager","suffix":105,"x":141.0},
		{"kind":"villager","suffix":106,"x":154.0},{"kind":"knight","suffix":100,"x":170.5},
		{"kind":"general","suffix":100,"x":173.0}]
	var people:Array=[5.0,12.0,18.0,25.0,34.0,44.0,51.0,65.0,109.0,121.0,151.0,172.0]
	for i in people.size():result.append({"kind":"villager","suffix":107+i,"x":people[i],"radius":2.5})
	for kind in ["rabbit","deer","bat"]:
		var places:Array={"rabbit":[7.0,16.0,39.0,103.0,143.0,177.0],"deer":[10.0,95.0,145.0,162.0],"bat":[6.0,91.0,151.0,175.0]}[kind]
		for i in places.size():result.append({"kind":kind,"suffix":i,"x":places[i],"radius":3.0,"flight_height":4.0 if kind=="bat" else 0.0})
	for i in 2:result.append({"kind":"dragon","suffix":i+1,"x":[13.0,174.0][i],"flight_height":5.5})
	return result

static func configure_patrol(entity) -> void:
	if GROUND_PATROLS.has(entity.entity_id):
		var ends:Array=GROUND_PATROLS[entity.entity_id]
		entity.home_x=(ends[0]+ends[1])*0.5
		entity.patrol_half_width=(ends[1]-ends[0])*0.5
	else:
		for record in actor_records():
			if entity.entity_id==record.kind+"-"+str(record.suffix) and record.has("radius"):
				entity.home_x=record.x
				entity.patrol_half_width=record.radius
	if entity.kind in ["king","queen"]:
		for role in MedievalCastleLayout.role_positions():
			if entity.kind==role.kind:
				entity.patrol_half_width=minf(entity.home_x-role.patrol_left,role.patrol_right-entity.home_x)-0.25
