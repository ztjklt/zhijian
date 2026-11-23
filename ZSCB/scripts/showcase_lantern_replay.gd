extends Node2D
## The live nib draws the saved master onto the painter's hand-held sheet.
## Show those same completed marks at their final size until the real counter commits.
const Markets := preload("res://scripts/architecture/market_sites.gd")
const Brush := preload("res://scripts/architecture/scenery_brush.gd")
const PLAN := 4
const ORIGIN := Vector2(-2.34, 11.95)

var game
var painter
var stage := "opening"
var message := "展开阿靛的原图"
var meshes: Array[ArrayMesh] = []
var marks: Array[Dictionary] = []
var current_mark: ArrayMesh
var color := Color.BLACK
var door: Dictionary = {}
var visited: Array[String] = []

func start(world_game, artist) -> void:
	game = world_game
	painter = artist
	game.add_child(self)
	z_index = 1

func _process(_delta: float) -> void:
	if not is_instance_valid(painter) or not is_instance_valid(painter.actor):
		return
	match stage:
		"opening":
			if not painter.actor.on_ground: return
			# This uses the same site checks, actor ink and physical submission as reuse in play.
			painter.last_command = {"tool":"reuse_scene_plan","plan_id":PLAN}
			painter.start_at = painter.actor.player.position
			painter._build_scene_at(PLAN, ORIGIN)
			if painter.phase != "pen":
				_fail()
				return
			painter.caption = ""
			var cmd: Dictionary = painter.pen_command
			color = game.FunctionalPens.STYLES.get(cmd.style,Color.BLACK)
			for i in cmd.strokes.size():
				var points := PackedVector2Array()
				for p in cmd.strokes[i]: points.append(Vector2(p[0],p[1]) - ORIGIN)
				var mark := {"points":points,"brush":cmd.brushes[i],"pigment":cmd.pigments[i]}
				marks.append(mark)
				meshes.append(Brush.mesh_for([mark],color))
			stage = "drawing"
		"drawing":
			position = game.world_to_screen(ORIGIN)
			scale = Vector2(1,-1) * game.PIXELS_PER_UNIT
			queue_redraw()
			if painter.phase == "pen":
				_update_live_mark()
				message = "阿靛落笔　%d / %d" % [painter.pen_stroke + 1, meshes.size()]
			elif painter.last_result.get("ok",false):
				_walk_to("reed_leaf")
			else:
				_fail()
		"walking":
			if painter.phase == "walk": return
			var at: Vector2 = painter.actor.player.position
			if not painter.last_result.get("ok",false) or painter.actor.player.support_bodies().is_empty() or Markets.station_id(game,at) != door.station:
				_fail()
				return
			visited.append(door.station)
			if visited.size() == 1:
				_walk_to("paper_lantern")
			else:
				painter.caption = ""
				stage = "done"
				message = "两处柜口已走通 · 灯柜一盏两金"

# Project the native nib's current segment back from the hand-held sheet to the original site.
func _update_live_mark() -> void:
	var stroke: int = painter.pen_stroke
	var n: int = painter.pen_point
	var mark := marks[stroke]
	var original: PackedVector2Array = mark.points
	var sheet: PackedVector2Array = painter.pen_lines[stroke]
	var length := sheet[n-1].distance_to(sheet[n])
	var t := clampf(sheet[n-1].distance_to(painter.pen_from) / maxf(length,.000001),0,1)
	var points := original.slice(0,n)
	points.append(original[n-1].lerp(original[n],t))
	var brush: String = "fine" if mark.brush == "wash" else mark.brush
	current_mark = Brush.mesh_for([{"points":points,"pigment":mark.pigment,"brush":brush}],color)

func _walk_to(item: String) -> void:
	queue_redraw()
	for spot: Dictionary in Markets.known_stalls(game,painter.actor.player.position):
		if spot.offer.item != item: continue
		door = spot
		var goal := Vector2(spot.at[0],spot.at[1])
		stage = "walking"
		message = "阿靛试走 · " + str(spot.name)
		painter.last_command = {"tool":"walk_to_access","structure_id":spot.station}
		painter.start_at = painter.actor.player.position
		painter._go(goal.x,"region","",goal)
		return
	_fail()

func _fail() -> void:
	stage = "failed"
	message = str(painter.last_result.get("detail","原画现场未能恢复。"))
	if message.is_empty() or painter.last_result.get("ok",false):message = "脚下未能确认原柜的使用位。"

func _draw() -> void:
	if stage != "drawing" or painter.phase != "pen": return
	for i in mini(painter.pen_stroke,meshes.size()):
		if meshes[i].get_surface_count() > 0: draw_mesh(meshes[i],null)
	if current_mark != null and current_mark.get_surface_count() > 0: draw_mesh(current_mark,null)
