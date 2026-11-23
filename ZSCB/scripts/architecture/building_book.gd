extends RefCounted

const DATA := "res://assets/medieval/ink/buildings.json"
const GROVE := "res://assets/medieval/ink/grove_and_guild.json"
const CROWN_TIPS := "res://assets/medieval/ink/crown_tips.json"
const CURRENT_TREE_PAGES := {"pine":"pine_tips","orchard_tree":"orchard_tree_tips"}
const BAKED := "res://assets/medieval/ink/baked/"
static var sheets := {}

static func catalog() -> Dictionary:
	if sheets.is_empty():
		sheets = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		sheets.merge(JSON.parse_string(FileAccess.get_file_as_string(GROVE)))
		# Keep the original menu pages and their stroke data intact. New pages
		# carry the same tree geometry and add only the approved crown tips.
		var additions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CROWN_TIPS))
		for kind in CURRENT_TREE_PAGES:
			var revised: Dictionary = sheets[kind].duplicate(true)
			revised.name += " · 枝梢增笔"
			revised.kind = kind
			revised.strokes.append_array(additions[kind])
			for stroke in revised.strokes: stroke.section = revised.name
			sheets[CURRENT_TREE_PAGES[kind]] = revised
		sheets.merge(JSON.parse_string(FileAccess.get_file_as_string("res://assets/medieval/ink/guild_noticeboard.json")))
		sheets.merge(JSON.parse_string(FileAccess.get_file_as_string("res://assets/medieval/ink/east_field_studies.json")))
		sheets.merge(JSON.parse_string(FileAccess.get_file_as_string("res://assets/medieval/ink/traced_market_parts.json")))
		sheets.merge(JSON.parse_string(FileAccess.get_file_as_string("res://assets/medieval/ink/mill_studies.json")))
		sheets.merge(JSON.parse_string(FileAccess.get_file_as_string("res://assets/medieval/ink/counter_goods_studies.json")))
		sheets.merge(JSON.parse_string(FileAccess.get_file_as_string("res://assets/medieval/ink/grove_part_studies.json")))
	return sheets

static func key_for(kind: String) -> String:
	var key: String = "castle" if kind == "castle_piece" else CURRENT_TREE_PAGES.get(kind,kind)
	return key if catalog().has(key) else ""

static func pages() -> Array:
	var result := []
	for key in catalog():
		var page := {}
		for stroke in sheets[key].strokes:
			if page.get("section") != stroke.section or page.strokes.size() >= 128:
				page = {"key":key, "section":stroke.section, "strokes":[]}
				if sheets[key].has("reference_id"):
					for field in ["reference_id","author_id","layout"]:
						if sheets[key].has(field): page[field] = sheets[key][field]
				result.append(page)
			page.strokes.append(stroke)
	return result

## Match each visible footing to the ground beneath it. Raised artwork can
## still be placed freely. The bridge samples its banks below the raised road.
static func ground_fit(key: String, origin: Vector2, terrain):
	if catalog()[key].has("reference_id") or key in ["castle","west_crossing","mill_crossing"]: return null
	var kind: String = catalog()[key].get("kind",key)
	var natural := kind in ["bridge_stone","oak","pine","orchard_tree","bush"]
	var at: float = terrain.surface_height(origin.x) if natural else terrain.travel_height(origin.x)
	if absf(origin.y-at) > (1.0 if natural else .55): return null
	var size: Array = catalog()[key].size
	var texture: Texture2D = load(BAKED + key + ".png")
	var sheet := {"size":Vector2(size[0],size[1]), "source_rect":Rect2(Vector2.ZERO,texture.get_size()),
		"texture":texture, "position":origin}
	return preload("res://scripts/medieval_tree_roots.gd").new(sheet,terrain,not natural)

static func placed_draft(page: Dictionary, origin: Vector2, terrain) -> Array:
	var sheet:Dictionary=catalog()[page.key]
	if sheet.has("reference_id"):
		return study_draft(page,origin,terrain,1.0,_study_on_floor(origin,terrain))
	var fit = ground_fit(page.key, origin, terrain)
	var draft := draft_at(page, origin)
	if fit == null: return draft
	for path in draft: path.points = _fit_stroke(path.points,origin,fit)
	return draft


## Place a field study with the same local strokes at another size or on another bank.
## Addresses and terrain queries stay in world metres, including layered paper.
static func study_draft(page: Dictionary, origin: Vector2, terrain, scale_factor := 1.0, fit_to_surface := true) -> Array:
	var sheet: Dictionary = catalog()[page.key]
	if not sheet.has("reference_id") or not is_finite(scale_factor) or scale_factor<=0: return []
	var draft:=draft_at(page,Vector2.ZERO)
	for path in draft:
		for i in path.points.size():
			var local: Vector2=path.points[i]*scale_factor
			path.points[i]=origin+local+Vector2(0,_study_offset(sheet,origin,local,terrain) if fit_to_surface else 0.0)
	return draft

static func _study_on_floor(origin:Vector2,terrain) -> bool:
	if terrain==null:return false
	if terrain.paper_space==null:return absf(origin.y-terrain.travel_height(origin.x))<=.22
	for surface in terrain.paper_space.surfaces(origin.x,origin.y-.22,origin.y+.22):
		if surface.face=="floor":return true
	return false

static func _study_offset(sheet: Dictionary,origin: Vector2,local: Vector2,terrain) -> float:
	if terrain==null or not sheet.has("contact_band"):return 0.0
	var band:float=sheet.contact_band
	var weight:=1.0 if band==0.0 else clampf(1.0-local.y/band,0.0,1.0)
	if weight<=0.0:return 0.0
	var height:=origin.y
	var distance:=INF
	if terrain.paper_space!=null:
		for surface in terrain.paper_space.surfaces(origin.x+local.x,origin.y-2.5,origin.y+2.5):
			var gap:=absf(surface.y-origin.y)
			if surface.face=="floor" and gap<distance:
				height=surface.y
				distance=gap
	else:
		height=terrain.travel_height(origin.x+local.x)
	return (height-origin.y)*weight

static func _fit_stroke(points: Array, origin: Vector2, fit) -> Array:
	var result := []
	var first: Vector2 = points[0]-origin
	result.append(origin+fit.fit(first))
	for i in range(1,points.size()):
		var end: Vector2 = points[i]-origin
		# Fit the contact band without adding samples to the untouched roof.
		var steps := maxi(1,ceili(first.distance_to(end)/.11)) if minf(first.y,end.y)<fit.band else 1
		for j in range(1,steps+1): result.append(origin+fit.fit(first.lerp(end,float(j)/steps)))
		first = end
	return result

static func draft_at(page: Dictionary, origin: Vector2) -> Array:
	var draft := []
	for stroke in page.strokes:
		var points := []
		for p in stroke.points: points.append(origin + Vector2(p[0], p[1]))
		var path := {"points":points, "brush":stroke.brush}
		if stroke.has("pigment"): path.pigment = stroke.pigment
		draft.append(path)
	return draft


## The optional terrain-pen sheet traces just the playable edges. Its solids
## are ordinary terrain pen objects, independent of the scenery silhouette.
static func support_at(page: Dictionary, origin: Vector2, terrain = null) -> Array:
	var walks := preload("res://scripts/medieval_walk_surfaces.gd")
	var castle := preload("res://scripts/medieval_castle_layout.gd")
	var edges := []
	var sheet:Dictionary=catalog()[page.key]
	if sheet.has("bearing_edges"):
		var draft:=[]
		for edge in sheet.bearing_edges:
			var points:=[]
			for xy in edge: points.append(origin+Vector2(xy[0],xy[1]))
			draft.append({"points":points})
		return draft
	if page.key in ["west_crossing","mill_crossing"]:
		return [{"points":draft_at({"strokes":[page.strokes[0]]},origin)[0].points}]
	if page.key == "castle":
		for route in walks.castle_routes():
			var a := Vector2(route[0],route[1])
			var b := Vector2(route[2],route[3])
			if _castle_walk_section((a+b)*.5) == page.section:
				edges.append([castle.project_pixel(a)-castle.entry_position(),castle.project_pixel(b)-castle.entry_position()])
	else:
		var size: Array = catalog()[page.key].size
		edges = walks.authored({"kind":catalog()[page.key].get("kind",page.key),"size":Vector2(size[0],size[1])})
	var fit = ground_fit(page.key,origin,terrain) if terrain != null else null
	var draft := []
	for edge in edges:
		if edge[0].distance_to(edge[1]) >= 0.25:
			var points := [origin+edge[0],origin+edge[1]]
			draft.append({"points":_fit_stroke(points,origin,fit) if fit != null else points})
	return draft

static func _castle_walk_section(pixel: Vector2) -> String:
	if pixel.x < 315: return "西侧旗塔"
	if pixel.x > 1200: return "东侧旗塔"
	if pixel.x < 530: return "西侧回廊"
	if pixel.x > 1000: return "东侧回廊"
	if pixel.y >= 500: return "拱门与垛台"
	if pixel.x < 670 and pixel.y < 417: return "西尖塔"
	if pixel.x > 865 and pixel.y < 417: return "东尖塔"
	return "中央望楼"


## The public house and stall sheets use their outermost drawn feet. The open
## front of each original is reserved as a usable standing place on the lane.
static func building_layout(page: Dictionary, origin: Vector2, terrain) -> Dictionary:
	var sheet: Dictionary = catalog()[page.key]
	if sheet.has("layout"):
		var layout: Dictionary = sheet.layout.duplicate(true)
		if _study_on_floor(origin,terrain):
			for field in ["supports","access"]:
				for xy in layout[field]:
					xy[1]+=_study_offset(sheet,origin,Vector2(xy[0],xy[1]),terrain)
		layout.layers = page.strokes.map(func(p): return p.get("layer",p.brush))
		return layout
	if page.key not in ["house","market","forge","tavern","windmill","watermill","tent","well"]: return {}
	var floor_y := INF
	var extent := Vector2(INF,-INF)
	var layers := []
	for stroke in page.strokes:
		for p in stroke.points:
			floor_y=minf(floor_y,p[1])
			extent.x=minf(extent.x,p[0]); extent.y=maxf(extent.y,p[0])
		layers.append(stroke.get("layer",{"wash":"铺色","wash_pool":"铺色","bold":"轮廓","fine":"细部"}.get(stroke.brush,"笔迹")))
	var left := Vector2(INF,0)
	var right := Vector2(-INF,0)
	for stroke in page.strokes:
		for p in stroke.points:
			if p[1]>floor_y+.12: continue
			if p[0]<left.x: left=Vector2(p[0],p[1])
			if p[0]>right.x: right=Vector2(p[0],p[1])
	var fit=ground_fit(page.key,origin,terrain) if terrain!=null else null
	var door := Vector2(0.0,0.0)
	if fit!=null:
		left=fit.fit(left)
		right=fit.fit(right)
		door.y=terrain.travel_height(origin.x)-origin.y
	return {"footprint":[extent.x,extent.y],"supports":[[left.x,left.y],[right.x,right.y]],"access":[[door.x,door.y]],"layers":layers}
