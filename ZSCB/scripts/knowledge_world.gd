extends Node2D

# Positive Y is up. Editorial groups define all placement; no noise terrain,
# substring sampling, texture tiling, card backgrounds or automatic displacement.
const LEFT := -6.0
const RIGHT := 162.0
const STEP := 26.0
const CHUNK := 16.0
const REGIONS := ["数与形", "字里山河", "时间长廊", "光与力", "元素之间", "函数远方"]
const SUBJECTS := ["数学", "语文", "历史", "物理", "化学", "数学"]
const COLORS := [Color("587b6b"),Color("986e63"),Color("9a8056"),Color("60818c"),Color("7c8b59"),Color("807b96")]
const INK := Color("35423d")
const CELL_X := .36
const CELL_Y := .32
const MIN_ROW := -18
const MAX_ROW := 68
const Editorial = preload("res://scripts/semantic_layout.gd")
var game = null
var cells: Dictionary = {}
var materials: Dictionary = {}
var textures: Dictionary = {}
var placements: Array = []
var labels: Array = []
var paths: Array = []
var structures: Array = []
var stamps: Array = []
var chunks: Dictionary = {}
var semantic_blocks: Array = []
var text_rows: Array = []
var terrain_rects: Array = []
var raised_tiers: Array = []
var sky_tiers: Array = []
var density := 2
var overview := false
var collision_view := false
var region := 0
var collected: Dictionary = {}
var toast := ""
var toast_time := 0.0
var checkpoint := Vector2(9.0,-2.26)
var normal_ppu := 60.0
var collision_geometry: Array = []
var controls: Control
var serif := SystemFont.new()
var sans := SystemFont.new()

func _ready() -> void:
	serif.font_names=PackedStringArray(["Songti SC","STSong","PingFang SC"])
	sans.font_names=PackedStringArray(["PingFang SC","Heiti SC"])
	var file:=FileAccess.open("res://assets/image/ink-materials/manifest.json",FileAccess.READ)
	materials=JSON.parse_string(file.get_as_text())
	game.PIXELS_PER_UNIT=60.0
	_build_layout()
	_build_terrain()
	_cache_collision_geometry()
	checkpoint=Vector2(9,surface_height(9)+.9)
	game.camera_x=9
	_update_chunks()
	respawn()
	game.onboarding.visible=false
	game.onboarding.persist=false
	game.flip_timer=0.0
	if game.network_headless: return
	game.get_window().title="纸间 · " + map_title()
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	controls = preload("res://scripts/knowledge_map_controls.gd").new()
	controls.game = game
	controls.world = self
	layer.add_child(controls)

func map_title() -> String:
	return "课本文字地图"

func navigation_names() -> Array:
	return ["数学", "语文", "历史", "物理", "化学", "函数"]

func region_title(index: int) -> String:
	return REGIONS[clampi(index, 0, 5)]

func extent_summary() -> String:
	return "有限样段 156m · 高台至 27m · Home 回到地面"

func _text(group: Dictionary,text: String,x: float,top: float,size: int=28,role: String="body",physical: bool=false,fit_width: float=0) -> void:
	var h: float=serif.get_height(size)/78.0
	var width: float=serif.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x/78.0
	if fit_width>0:width=fit_width
	var row: Dictionary={"group_id":group.id,"text":text,"p":Vector2(x,top-h),"w":width,"h":h,"size":size,"role":role,"color":COLORS[group.chapter] if role=="title" else INK,"fit":fit_width>0}
	text_rows.append(row)
	if physical:paths.append({"points":[Vector2(x,top),Vector2(x+width,top)],"one_way":true,"source":group.id,"group_id":group.id})

func _group(id: String,title: String,chapter: int,bounds: Rect2,lines: Array=[],author: String="") -> Dictionary:
	var group: Dictionary={"id":id,"title":title,"author":author,"lines":lines,"chapter":chapter,"bounds":bounds,"assets":[],"formulas":[]}
	semantic_blocks.append(group)
	return group

func _heading(group: Dictionary,top: float) -> void:
	_text(group,group.title,group.bounds.position.x,top,38,"title")

func _figure(group: Dictionary,id: String,at: Vector2,width: float) -> void:
	group.assets.append(id)
	var info: Dictionary=materials[id]
	var height: float=width*float(info.height)/float(info.width)
	if not textures.has(id):textures[id]=load(info.path) as Texture2D
	placements.append({"id":id,"group_id":group.id,"p":at,"w":width,"h":height,"priority":0,"alpha":1.0,"terrain":true})
	for route in info.routes:
		var points: Array=[]
		for point in route.points:points.append(at+Vector2(float(point[0])/float(info.width)*width,height-float(point[1])/float(info.height)*height))
		paths.append({"points":points,"one_way":route.one_way,"source":id,"group_id":group.id})

func _formula(group: Dictionary,id: String,x: float,y: float,size: float=42) -> void:
	group.formulas.append(id)
	var info: Dictionary=materials[id]
	_figure(group,id,Vector2(x,y),float(info.width)/float(info.font_size)*size/78.0)

func _paragraph(group: Dictionary,lines: Array,top: float,size: int=25,gap: float=.58) -> void:
	for i in range(lines.size()):
		group.lines.append(lines[i])
		_text(group,lines[i],group.bounds.position.x,top-i*gap,size)

func _build_layout() -> void:
	var chapters: Array=Editorial.chapters()
	for i in range(6):
		var x: float=i*STEP
		var ground: float=surface_height(x+1)
		var chapter: Dictionary=chapters[i]
		var floor_group:=_group("chapter-%d"%i,chapter.title,i,Rect2(Vector2(x,ground-2.3),Vector2(STEP,2.3)),chapter.foundation)
		for row in range(chapter.foundation.size()):_text(floor_group,chapter.foundation[row],x,ground-row*.62,29,"body",false,STEP if row==0 else 0)
		labels.append({"value":"0%d  /  %s"%[i+1,REGIONS[i]],"p":Vector2(x+1,7.7),"size":22,"color":COLORS[i],"priority":0})
		stamps.append({"p":Vector2(x+23,ground+1.0),"id":i,"label":SUBJECTS[i]})
		# The upper ledge is a complete, useful paragraph, with exactly matching
		# rectangular collision; it is never a slice cut from a source texture.
		var summary:=_group("summary-%d"%i,"本章提要",i,Rect2(Vector2(x+8,8.35),Vector2(10,3.4)),chapter.summary)
		_heading(summary,11.5)
		for row in range(3):_text(summary,chapter.summary[row],x+8,10.65-row*.62,27,"body")
		var ledge_width: float=serif.get_string_size(chapter.summary[0],HORIZONTAL_ALIGNMENT_LEFT,-1,27).x/78.0
		raised_tiers.append(Rect2(Vector2(x+8,8.8),Vector2(ledge_width,1.85)))
	_math_region()
	_literature_region()
	_history_region()
	_physics_region()
	_elements_region()
	_functions_region()
	_build_sky_route()

func _build_sky_route() -> void:
	# A narrow margin spine gives the existing wall-climb controller a route
	# from the foundation. All original text, figures and fixtures stay put.
	var spine := Rect2(Vector2(.3, -2.8), Vector2(.45, 16.8))
	raised_tiers.append(spine)
	sky_tiers.append(spine)
	labels.append({"value":"页边攀登 ↑ 按住 D / 向墙移动", "p":Vector2(.95, 12.1), "size":17, "color":COLORS[0]})
	for i in range(18):
		var x: float = .75 + i * 8.5
		var top: float = 14.0 + minf(i, 14) * .9
		var tier := Rect2(Vector2(x, top - .24), Vector2(7.3, .24))
		raised_tiers.append(tier)
		sky_tiers.append(tier)
		var chapter := clampi(int(x / STEP), 0, 5)
		labels.append({"value":"%s · 天空 %dm" % [REGIONS[chapter], roundi(top)], "p":Vector2(x + .25, top - .62), "size":19, "color":COLORS[chapter]})
		if i % 3 == 1:
			labels.append({"value":"二连跳跨页 · 双 S 下穿 · 可画建筑搭桥", "p":Vector2(x + .15, top + .5), "size":15, "color":COLORS[chapter]})

func _math_region() -> void:
	var a:=_group("pythagoras","勾股定理",0,Rect2(Vector2(1,-1.8),Vector2(10.5,8.7)))
	_heading(a,6.7)
	_paragraph(a,["作 CD ⟂ AB，研究直角三角形 ACD。","取 a = AD，b = CD，c = AC。"],5.8,24)
	_figure(a,"shape-triangle",Vector2(1,.65),7.0)
	_text(a,"D",4.35,.85,24,"annotation")
	_formula(a,"math-pythagoras",1,-.55,53)
	_formula(a,"math-root",7.6,-1.55,40)
	var b:=_group("equations","等式与一元二次方程",0,Rect2(Vector2(14,-1.8),Vector2(11,8.7)))
	_heading(b,6.7)
	_paragraph(b,["等式两边进行相同运算，等量关系不变。","二次方程先化为 ax² + bx + c = 0（a ≠ 0）。"],5.8,24)
	_formula(b,"math-equation",14,3.9,55)
	_formula(b,"math-delta",14,2.7,42)
	_paragraph(b,["判别式 Δ 决定实数根的个数。","Δ > 0：两个；Δ = 0：一个；Δ < 0：无。"],2.1,23)
	_formula(b,"math-sum",14,-1.55,42)

func _literature_region() -> void:
	var poems: Array=Editorial.poems()
	for i in range(2):
		var poem: Dictionary=poems[i]
		var x: float=STEP+1+i*12.8
		var block:=_group(poem.id,poem.title,1,Rect2(Vector2(x,-.8),Vector2(11,7.7)),poem.lines,poem.author)
		_heading(block,6.7)
		_text(block,poem.author,x,5.85,24,"author")
		for line in range(poem.lines.size()):_text(block,poem.lines[line],x,4.8-line*.86,36,"body",true)
		_text(block,"元曲 · 小令" if i==0 else "唐诗 · 五言律诗",x,-.1,22,"annotation")

func _history_region() -> void:
	var x: float=STEP*2+1
	var a:=_group("scripts","文字与史料",2,Rect2(Vector2(x,-1.8),Vector2(11,8.7)))
	_heading(a,6.7)
	_paragraph(a,["甲骨文、金文保存了早期历史信息。","观察载体、年代与记载内容。"],5.8,25)
	_formula(a,"history-script",x,3.3,40)
	_paragraph(a,["甲骨：龟甲与兽骨。","金文：青铜器上的文字。","考古发现与传世文献需要相互参照。"],2.4,25)
	_formula(a,"history-book",x,-1.55,34)
	var b:=_group("timeline","朝代顺序与交流",2,Rect2(Vector2(x+12.8,-1.8),Vector2(11,8.7)))
	_heading(b,6.7)
	_paragraph(b,["以下为朝代节选，只示顺序，不等距。"],5.8,25)
	_figure(b,"shape-timeline",Vector2(x+12.8,3.6),10.5)
	_paragraph(b,["秦汉：统一国家的建立和发展。","丝绸之路：物品、技术与文化的交流。","隋唐：城市、商业与文化的发展。"],2.6,25)
	_formula(b,"history-step-1",x+12.8,-1.55,34)
	_formula(b,"history-step-2",x+16.7,-.85,34)
	_formula(b,"history-step-3",x+20.6,-.15,34)

func _physics_region() -> void:
	var x: float=STEP*3+1
	var a:=_group("reflection","光的折射与色散",3,Rect2(Vector2(x,-1.8),Vector2(11,8.7)))
	_heading(a,6.7)
	_paragraph(a,["光从一种介质进入另一种介质时，","传播方向可能改变，这种现象叫折射。"],5.8,24)
	_figure(a,"shape-prism",Vector2(x,.65),8.5)
	_paragraph(a,["光线穿过棱镜，两次折射后改变方向。","不同色光的折射程度不同，可形成色散。"],.1,24)
	var b:=_group("force","力、功与能量",3,Rect2(Vector2(x+12.8,-1.8),Vector2(11,8.7)))
	_heading(b,6.7)
	_paragraph(b,["弹簧受力会改变形状；合力改变运动。"],5.8,24)
	_figure(b,"shape-spring",Vector2(x+12.8,3.2),9)
	_formula(b,"physics-force",x+12.8,2.3,45)
	_formula(b,"physics-work",x+17.2,2.3,45)
	_formula(b,"physics-power",x+20.1,2.3,40)
	_paragraph(b,["W = Fs 适用于力与位移方向相同的情形。","动能与速度有关，重力势能与高度有关。"],1.6,23)
	_formula(b,"physics-energy",x+12.8,-1.55,42)
	_formula(b,"physics-potential",x+18.1,-1.55,42)

func _elements_region() -> void:
	var x: float=STEP*4+1
	var a:=_group("molecules","化学式与结构式",4,Rect2(Vector2(x,-1.8),Vector2(11,8.7)))
	_heading(a,6.7)
	_paragraph(a,["化学式表示组成，结构式说明连接方式。"],5.8,24)
	_formula(a,"chem-bond",x,4.4,52)
	_formula(a,"chem-hydrogen",x+6.7,4.4,52)
	_figure(a,"shape-benzene",Vector2(x,.35),4.2)
	_paragraph(a,["苯环的结构示意。","水分子由氢、氧原子构成。"],-.2,24)
	_formula(a,"chem-methane",x+6.7,1.5,45)
	_formula(a,"chem-ion",x+6.7,.3,45)
	var b:=_group("reactions","化学反应与元素",4,Rect2(Vector2(x+12.8,-1.8),Vector2(11,8.7)))
	_heading(b,6.7)
	_paragraph(b,["化学变化中，原子重新组合。","检查每种原子的数目，先配平再计算。"],5.8,24)
	_formula(b,"chem-water",x+12.8,3.6,48)
	_formula(b,"chem-carbon",x+12.8,2.5,45)
	_figure(b,"shape-elements",Vector2(x+12.8,.5),9.5)
	_formula(b,"chem-small",x+12.8,-1.55,40)
	_formula(b,"chem-carbon-dioxide",x+21,-1.55,40)

func _functions_region() -> void:
	var x: float=STEP*5+1
	var a:=_group("quadratic","二次函数",5,Rect2(Vector2(x,-1.8),Vector2(11,8.7)))
	_heading(a,6.7)
	_paragraph(a,["图像是抛物线，对称轴经过顶点。","开口方向与二次项系数的正负有关。"],5.8,24)
	_figure(a,"graph-parabola",Vector2(x,.65),9.5)
	_formula(a,"graph-label",x,-1.55,45)
	_formula(a,"graph-origin",x+5.3,-1.55,40)
	var b:=_group("periodic","正弦函数与周期",5,Rect2(Vector2(x+12.8,-1.8),Vector2(11,8.7)))
	_heading(b,6.7)
	_paragraph(b,["正弦函数的图像按周期重复。","定义域是全体实数，值域为 [−1, 1]。"],5.8,24)
	_figure(b,"graph-sine",Vector2(x+12.8,.65),9.5)
	_formula(b,"graph-sin",x+12.8,-1.55,45)
	_formula(b,"graph-domain",x+18.1,-1.55,40)

# Only chapter edges change elevation; every span is horizontal.
func surface_height(x: float) -> float:
	var chapter:=clampi(int(floor(x/STEP)),0,5)
	return -2.8+[0.0,.64,0.0,1.28,.64,0.0][chapter]

func _build_terrain() -> void:
	for i in range(6):
		var x: float=i*STEP
		var left: float=x
		var right: float=x+STEP
		terrain_rects.append(Rect2(Vector2(left,surface_height(x+1)-2.3),Vector2(right-left,2.3)))
	for col in range(int(floor(LEFT/CELL_X)),int(ceil(RIGHT/CELL_X))):
		var x: float=(col+.5)*CELL_X
		for row in range(MIN_ROW,MAX_ROW):
			var p:=Vector2(x,(row+.5)*CELL_Y)
			for tier in terrain_rects:
				if tier.has_point(p):cells[Vector2i(col,row)]=true;break

func _cache_collision_geometry() -> void:
	for tier in terrain_rects + raised_tiers:
		var a: Vector2 = tier.position
		var b: Vector2 = tier.end
		collision_geometry.append(PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a]))
	for path in paths:
		collision_geometry.append(PackedVector2Array(path.points))

func _add_terrain_physics(parent: Node2D, chunk: int) -> void:
	for tier in terrain_rects + raised_tiers:
		var left: float = maxf(tier.position.x, chunk * CHUNK)
		var right: float = minf(tier.end.x, (chunk + 1) * CHUNK)
		if right <= left: continue
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 3
		body.set_meta("map_drop_allowed", raised_tiers.has(tier))
		parent.add_child(body)
		var fixture := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(right - left, tier.size.y)
		fixture.shape = box
		fixture.position = Vector2((left + right) * 0.5, tier.get_center().y)
		body.add_child(fixture)

func _update_chunks() -> void:
	if game == null: return
	var wanted := {}
	var centers: Array = game.physics_centers() + [game.player.position.x]
	# Active ink and roaming actors still need ground when they leave the camera.
	for node in game.object_nodes:
		if is_instance_valid(node) and absf(node.position.x - game.camera_x) < 70:
			centers.append(node.position.x)
	if game.combat != null:
		for native in game.combat.natives:
			if is_instance_valid(native): centers.append(native.position.x)
	for x in centers:
		var center := int(floor(float(x) / CHUNK))
		for chunk in range(center - 2, center + 3):
			if (chunk + 1) * CHUNK < LEFT or chunk * CHUNK > RIGHT: continue
			wanted[chunk] = true
	for chunk in wanted:
		if chunks.has(chunk): continue
		var parent := Node2D.new()
		parent.name = "InkChunk_%d" % chunk
		add_child(parent)
		_add_terrain_physics(parent, chunk)
		for path in paths:
			var points: Array = path.points
			for i in range(1, points.size()):
				var a: Vector2 = points[i - 1]
				var b: Vector2 = points[i]
				if int(floor((a.x + b.x) * 0.5 / CHUNK)) != chunk: continue
				var length := a.distance_to(b)
				if length < 0.02: continue
				var body := StaticBody2D.new()
				body.position = (a + b) * 0.5
				body.collision_layer = 1
				body.collision_mask = 3
				body.set_meta("map_drop_allowed", true)
				var fixture := CollisionShape2D.new()
				var box := RectangleShape2D.new()
				box.size = Vector2(length + 0.025, 0.07)
				fixture.shape = box
				fixture.rotation = (b - a).angle() + (PI if path.one_way else 0)
				fixture.one_way_collision = path.one_way
				fixture.one_way_collision_margin = 0.08
				body.add_child(fixture)
				parent.add_child(body)
		chunks[chunk] = parent
	for chunk in chunks.keys():
		if not wanted.has(chunk):
			chunks[chunk].queue_free()
			chunks.erase(chunk)

func _process(delta: float) -> void:
	if game==null:return
	toast_time=maxf(0,toast_time-delta)
	if overview:return
	region=clampi(int(floor(game.player.position.x/STEP)),0,5)
	_update_chunks()
	for stamp in stamps:
		if not collected.has(stamp.id) and game.player.position.distance_to(stamp.p)<.9:
			collected[stamp.id]=true
			toast="拾到「"+stamp.label+"」书签"
			toast_time=3
	if game.player.position.x>LEFT and game.player.position.x<RIGHT:
		var chapter := clampi(int(floor(game.player.position.x / STEP)), 0, 5)
		var x: float = chapter * STEP + 9
		checkpoint = Vector2(x, surface_height(x) + 0.9)

func restore_state(state: Dictionary) -> void:
	var saved = state.get("checkpoint", Vector2(9, -1.9))
	checkpoint = saved if saved is Vector2 else Vector2(saved.x, saved.y)
	collected.clear()
	for id in state.get("bookmarks", []): collected[int(id)] = true

func respawn() -> void:
	if game.network_session != null:
		game.network_session.send_op("respawn")
		return
	game.retain_active_stroke()
	game.cancel_pointer()
	game.wall_climb.reset(game.player)
	game.player.reset_movement()
	game.jumps_used = 0
	game.climbing = false
	game.crouching = false
	game.down_tap_timer = 0
	game.down_was_down = false
	game.jump_was_down = false
	game.player.position = checkpoint
	PhysicsServer2D.body_set_state(game.player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0, checkpoint))
	game.player.linear_velocity = Vector2.ZERO
	game.player.gravity_scale = 1
	game.camera_x = checkpoint.x
	game.camera_y = game.camera_target_y()
	if game.combat != null: game.combat.cancel_draw()
	_update_chunks()

func visit(index: int) -> void:
	if game.network_session != null:
		game.message("联机地图浏览不传送角色，请与朋友一起探索")
		return
	if overview: toggle_overview()
	var x: float = clampi(index, 0, 5) * STEP + 9
	checkpoint = Vector2(x, surface_height(x) + 0.9)
	respawn()

func toggle_overview() -> void:
	game.retain_active_stroke()
	game.cancel_pointer()
	game.touch_controls.reset()
	game.combat.cancel_draw()
	overview = not overview
	if overview:
		normal_ppu = game.PIXELS_PER_UNIT
	else:
		game.PIXELS_PER_UNIT = normal_ppu
	resize_overview()
	game.canvas_node.queue_redraw()

func resize_overview() -> void:
	if overview: game.PIXELS_PER_UNIT = maxf(1.0, (get_viewport_rect().size.x - 40) / (RIGHT - LEFT))

func overview_point(pos: Vector2) -> Vector2:
	return Vector2(20 + (pos.x - LEFT) * game.PIXELS_PER_UNIT, get_viewport_rect().size.y * 0.62 - pos.y * game.PIXELS_PER_UNIT)

func overview_to_world(pos: Vector2) -> Vector2:
	return Vector2(LEFT + (pos.x - 20) / game.PIXELS_PER_UNIT, (get_viewport_rect().size.y * 0.62 - pos.y) / game.PIXELS_PER_UNIT)

func _visible(x: float,width: float=3) -> bool:
	if overview:return true
	var half: float=get_viewport_rect().size.x/game.PIXELS_PER_UNIT*.5
	return x+width>game.camera_x-half and x<game.camera_x+half

func draw_background(canvas: Node2D,size: Vector2) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO,size),Color("f8f5e9"))
	for j in range(160):
		var x:=fmod(j*137.731,size.x)
		var y:=fmod(j*87.337,size.y)
		canvas.draw_line(Vector2(x,y),Vector2(x+2+j%4,y+.3),Color(.55,.50,.38,.045),1,true)

func draw_landscape(canvas: Node2D,_size: Vector2) -> void:
	var ppu: float=game.PIXELS_PER_UNIT
	for tier in sky_tiers:
		if not _visible(tier.position.x, tier.size.x): continue
		var rect := Rect2(game.world_to_screen(Vector2(tier.position.x, tier.end.y)), tier.size * ppu)
		canvas.draw_rect(rect, Color("e3e5d6"))
		canvas.draw_rect(rect, Color("7c9380"), false, maxf(.8, ppu * .022))
	for row in text_rows:
		if not _visible(row.p.x,row.w):continue
		var at: Vector2=game.world_to_screen(row.p+Vector2(0,row.h))
		var scale_y: float=row.h*ppu/serif.get_height(row.size) if game.network_session!=null else ppu/78.0
		var native_width: float=serif.get_string_size(row.text,HORIZONTAL_ALIGNMENT_LEFT,-1,row.size).x
		var scale_x: float=row.w*ppu/native_width if row.fit else scale_y
		canvas.draw_set_transform(at,0,Vector2(scale_x,scale_y))
		canvas.draw_string(serif,Vector2(0,serif.get_ascent(row.size)),row.text,HORIZONTAL_ALIGNMENT_LEFT,-1,row.size,row.color)
		canvas.draw_set_transform(Vector2.ZERO)
	for entry in placements:
		if not _visible(entry.p.x,entry.w):continue
		canvas.draw_texture_rect(textures[entry.id],Rect2(game.world_to_screen(entry.p+Vector2(0,entry.h)),Vector2(entry.w,entry.h)*ppu),false)
	for label in labels:
		if not _visible(label.p.x,10):continue
		canvas.draw_string(serif,game.world_to_screen(label.p),label.value,HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(3,roundi(label.size*ppu/78)),label.color)
	if collision_view:
		for tier in terrain_rects+raised_tiers:
			canvas.draw_rect(Rect2(game.world_to_screen(Vector2(tier.position.x,tier.end.y)),tier.size*ppu),Color("c77948"),false,1.5)
		for path in paths:
			var points:=PackedVector2Array()
			for point in path.points:points.append(game.world_to_screen(point))
			canvas.draw_polyline(points,Color("54a680") if path.one_way else Color("c77948"),1.5,true)
	for stamp in stamps:
		if collected.has(stamp.id) or not _visible(stamp.p.x):continue
		var at: Vector2=game.world_to_screen(stamp.p)
		var r: float=9*ppu/78
		canvas.draw_polyline(PackedVector2Array([at+Vector2(0,-r),at+Vector2(r*.7,0),at+Vector2(0,r),at+Vector2(-r*.7,0),at+Vector2(0,-r)]),COLORS[stamp.id],maxf(.7,1.4*ppu/78),true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var focus:=get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit or game.bag_open or game.personal_overlay_open():return
		if event.keycode==KEY_M:toggle_overview()
		elif event.keycode==KEY_HOME:respawn()
		elif event.keycode==KEY_TAB:visit((region+1)%6)

# A round body can perch on a stair corner while the narrow foot Area2D misses
# both neighbouring cells. Probe the actual support to allow the slope assist.
func refresh_ground_support() -> void:
	if game.player.linear_velocity.y>.5:return
	var supported: bool=game.ground_contacts>0
	for dx in [-.20,0.0,.20]:
		var point: Vector2=game.player.position+Vector2(dx,0)
		var query:=PhysicsRayQueryParameters2D.create(point,point-Vector2(0,.54),1)
		query.exclude=[game.player.get_rid()]
		var hit: Dictionary=game.get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.normal.y>.5:supported=true
	game.on_ground=supported


func network_layout() -> Dictionary:
	var raised: Array=[]
	var sky: Array=[]
	for rect in raised_tiers: raised.append({"position":rect.position,"size":rect.size})
	for rect in sky_tiers: sky.append({"position":rect.position,"size":rect.size})
	return {"paths":paths,"rows":text_rows,"raised":raised,"sky":sky}

func apply_network_layout(layout: Dictionary) -> void:
	# Font metrics differ across operating systems. The authority supplies the
	# actual text widths and matching colliders; each client fits its glyphs to it.
	paths=layout.get("paths",paths)
	text_rows=layout.get("rows",text_rows)
	for row in text_rows: row.fit=true
	raised_tiers.clear(); sky_tiers.clear()
	for rect in layout.get("raised",[]): raised_tiers.append(Rect2(rect.position,rect.size))
	for rect in layout.get("sky",[]): sky_tiers.append(Rect2(rect.position,rect.size))
	collision_geometry.clear()
	_cache_collision_geometry()
	for chunk in chunks.values(): chunk.queue_free()
	chunks.clear()
	_update_chunks()
