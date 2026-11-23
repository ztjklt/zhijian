extends RefCounted

const Book := preload("res://scripts/architecture/building_book.gd")
const Brush := preload("res://scripts/architecture/scenery_brush.gd")
const Pens := preload("res://scripts/functional_pens.gd")
const EDGE := Color("423a39")
const PAPER := Color("f2e7cd")
const ROCK := Color("838582")
const LODE := Color("bb8461")

static func vein_point(world, x: float, offset: Vector2) -> Vector2:
	var world_x := x + offset.x
	return Vector2(world_x, world.terrain.surface_height(world_x) + offset.y - 0.035)

static func _vein_path(g, world, x: float, shape: Array) -> PackedVector2Array:
	var path := PackedVector2Array()
	for p: Vector2 in shape:
		path.append(g.world_to_screen(vein_point(world, x, p)))
	return path

static func landscape(c: Node2D, s, g) -> void:
	var unit: float = g.PIXELS_PER_UNIT
	var font: Font = g.toolbar.get_theme_font("font")
	if absf(g.view_camera().x-s.Guild.COUNTER_X) < 14:
		# The 31 m station belongs to this world's fixed village street. Cache its
		# fitted public strokes on the service so a new world measures its own feet.
		if not s.has_meta("guild_porch"):
			var origin := Vector2(s.Guild.COUNTER_X,s.world.travel_height(s.Guild.COUNTER_X))
			var page := {"key":"guild_noticeboard","strokes":Book.catalog().guild_noticeboard.strokes}
			var paths := Book.placed_draft(page,origin,s.world.terrain)
			s.set_meta("guild_porch",Brush.mesh_for(paths,Pens.STYLES.ink))
			s.set_meta("guild_porch_ink",paths)
		c.draw_set_transform(g.world_to_screen(Vector2.ZERO),0,Vector2(unit,-unit))
		c.draw_mesh(s.get_meta("guild_porch"),null)
		c.draw_set_transform(Vector2.ZERO)
	if absf(g.view_camera().x-s.Guild.VEIN_X) < 14:
		var x: float = s.Guild.VEIN_X
		var at: Vector2 = g.world_to_screen(vein_point(s.world, x, Vector2.ZERO))
		var crest := _vein_path(g,s.world,x,[Vector2(-.67,0),Vector2(-.56,.22),Vector2(-.36,.37),Vector2(-.25,.51),Vector2(-.05,.56),Vector2(.12,.49),Vector2(.26,.46),Vector2(.49,.26),Vector2(.61,0)])
		var rock := crest.duplicate()
		for dx in [.40,.16,0.0,-.23,-.45]:
			rock.append(g.world_to_screen(vein_point(s.world,x,Vector2(dx,0))))
		c.draw_colored_polygon(rock,ROCK)
		var facet := _vein_path(g,s.world,x,[Vector2(-.56,.16),Vector2(-.36,.37),Vector2(-.25,.50),Vector2(-.07,.54),Vector2(-.21,.31)])
		c.draw_colored_polygon(facet,Color("a7a69b"))
		c.draw_polyline(crest,EDGE,1.8,true)
		c.draw_polyline(facet.slice(3),EDGE,1.0,true)
		for i in s.ore_left:
			var dx: float = -.37+.13*(i%6)
			var dy := .15+float(i/6)*.12+float(i%3)*.023
			var stripe := _vein_path(g,s.world,x,[Vector2(dx,dy),Vector2(dx+.042,dy+.048),Vector2(dx+.088,dy+.060)])
			c.draw_polyline(stripe,LODE,2.7,true)
		if s.mine_flash > 0:
			for i in 4:
				var t: float = 1.0-s.mine_flash/.6
				var offset := Vector2((i-1.5)*.32*t,-.6-t*.5+t*t*.6)*unit
				c.draw_circle(at+offset,2.6,LODE,true,-1,true)
		var words := "矿脉 · %d" % s.ore_left if s.ore_left > 0 else "空矿脉"
		var width := font.get_string_size(words,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		var base: Vector2 = g.world_to_screen(vein_point(s.world,x,Vector2(-.25,.65)))+Vector2(-width*.5,0)
		c.draw_rect(Rect2(base-Vector2(3,14),Vector2(width+6,18)),PAPER)
		c.draw_string(font,base,words,HORIZONTAL_ALIGNMENT_LEFT,-1,14,EDGE)
