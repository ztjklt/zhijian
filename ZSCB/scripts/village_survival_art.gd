extends Node2D
## Ink on the map and objects at the animated hand share the world's coordinates.
var service
const OUTLINE := Color("302e35")
const INK := Color("2f3544")
const RED := Color("b4473e")
const LIGHT := Color("fcf4e4")

func _process(_delta: float) -> void:
	queue_redraw()

static func _berry(canvas: Node2D, at: Vector2, radius: float) -> void:
	canvas.draw_line(at+Vector2(0,-radius*.7),at+Vector2(radius*.48,-radius*1.55),OUTLINE,maxf(1,radius*.23),true)
	canvas.draw_circle(at,radius*1.05,OUTLINE,true,-1,true)
	canvas.draw_circle(at,radius*.80,RED,true,-1,true)
	canvas.draw_circle(at+Vector2(-.22,-.28)*radius,radius*.20,LIGHT,true,-1,true)

static func _ellipse(at: Vector2, radii: Vector2) -> PackedVector2Array:
	var line := PackedVector2Array()
	for i in 41:
		var angle := TAU*i/40.0
		line.append(at+Vector2(cos(angle),sin(angle))*radii)
	return line

static func _caption(canvas: Node2D, at: Vector2, words: String, color: Color, font: Font, font_size: int) -> void:
	var width := font.get_string_size(words,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var baseline := at+Vector2(-width*.5,0)
	canvas.draw_rect(Rect2(baseline-Vector2(4,font_size),Vector2(width+8,font_size+5)),Color(.99,.96,.87,.94))
	canvas.draw_string_outline(font,baseline,words,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,4,LIGHT)
	canvas.draw_string(font,baseline,words,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

static func landscape(canvas: Node2D, service, game) -> void:
	preload("res://scripts/village_guild_art.gd").landscape(canvas,service,game)
	service.Pasture.draw(canvas,service,game)
	var scale_unit: float = game.PIXELS_PER_UNIT
	var font: Font = game.toolbar.get_theme_font("font")
	if absf(game.view_camera().x-service.POOL_X) < 14:
		var at: Vector2 = game.world_to_screen(service.pool_position())
		var rim := _ellipse(at,Vector2(.84,.16)*scale_unit)
		var base := _ellipse(at+Vector2(0,.115)*scale_unit,Vector2(.76,.15)*scale_unit)
		canvas.draw_colored_polygon(base,LIGHT)
		canvas.draw_polyline(base,OUTLINE,2.3,true)
		canvas.draw_colored_polygon(rim,LIGHT)
		canvas.draw_polyline(rim,OUTLINE,2.2,true)
		canvas.draw_colored_polygon(_ellipse(at,Vector2(.73,.105)*scale_unit),INK)
		for offset in [-.52,-.19,.20,.55]:
			var foot := at + Vector2(offset,.14) * scale_unit
			canvas.draw_line(foot,foot+Vector2(.025,.07)*scale_unit,OUTLINE,1.4,true)
		for x in [-.32,.17]:
			canvas.draw_polyline(_ellipse(at+Vector2(x,0)*scale_unit,Vector2(.105,.019)*scale_unit),Color("bbc7c0"),1.1,true)
		_caption(canvas,at+Vector2(-.45,-.65)*scale_unit,"圣墨池",OUTLINE,font,16)
	for fruit in service.loose_fruit.state.items.values():
		if absf(game.view_camera().x-fruit.x)<14:
			_berry(canvas,game.world_to_screen(Vector2(fruit.x,fruit.y)),scale_unit*service.GroundFruit.RADIUS)
	for id in service.orchards.crops:
		if not service.orchards.alive(id) or absf(game.view_camera().x-service.orchards.at(id).x)>=14:continue
		var row:Dictionary=service.orchards.crops[id]
		var growing:int=service.orchards.next(service,id)
		for i in service.orchards.count_slots(id):
			var berry:Vector2=service.orchards.marker(service,id,i)
			var center:Vector2=game.world_to_screen(berry)
			if i==growing and i==row.bud and row.seconds>0:
				var progress:float=row.seconds/service.FRUIT_RIPEN_SECONDS
				var radius:=scale_unit*lerpf(.035,.073,progress)
				canvas.draw_line(center,center+Vector2(.5,-1.45)*radius,OUTLINE,maxf(1,radius*.23),true)
				canvas.draw_circle(center,radius,OUTLINE,true,-1,true)
				canvas.draw_circle(center,radius*.8,Color("819768").lerp(Color("d2aa65"),progress),true,-1,true)
			elif service.orchards.visible_fruit(service,id,i):_berry(canvas,center,scale_unit*.085)

func _draw() -> void:
	if service == null: return
	var game = service.world.game
	for id in service.actors:
		var state: Dictionary = service.actors[id]
		var resident_sword: bool = service.people.has(id) and state.get("economy",{}).get("sword_equipped",false)
		var eating_meat: bool = state.get("livelihood",{}).get("meat_meal",false)
		if state.held == service.EMPTY and not eating_meat and not resident_sword and not service.speech.has(id): continue
		var at: Vector2 = service._position(id)
		if not at.is_finite() or absf(game.view_camera().x-at.x) > 12: continue
		var visual = game.character_visual if id == service.PLAYER else null
		if service.people.has(id): visual = service.people[id].person_visual
		if id == service.COMPANION or id == service.ADVENTURER:
			var traveller = service.agent_rig(id)
			if traveller != null: visual = traveller.character_visual
		if not is_instance_valid(visual): continue
		var hand: Vector2 = visual.pencil.get_parent().global_position
		var unit: float = game.PIXELS_PER_UNIT
		if resident_sword and state.held == service.EMPTY:
			var tip := hand + Vector2(visual.actor_facing()*.5,-.28)*unit
			draw_line(hand,tip,OUTLINE,3.2,true)
			draw_line(hand,tip,LIGHT,1.1,true)
		if eating_meat:
			if state.meal < .65:
				var face := visual.get_node("Skeleton/Hips/Torso/Head") as Node2D
				hand = hand.lerp(face.global_position,1.0-state.meal/.65)
			var piece := PackedVector2Array([hand+Vector2(-.11,.01)*unit,hand+Vector2(-.05,-.07)*unit,hand+Vector2(.11,-.03)*unit,hand+Vector2(.05,.065)*unit])
			draw_colored_polygon(piece,Color("984e39"))
			draw_line(piece[0],piece[1],LIGHT,1.7,true)
		elif state.held==service.Goods.LAMP_SLOT:
			var center:=hand+Vector2(0,.21)*unit
			var lit:bool=state.get("lamp_lit",false)
			if lit:
				for radius:float in [.85,.61,.37]:
					draw_circle(center,radius*unit,Color(1.0,.72,.28,.07),true,-1,true)
			draw_line(hand,center-Vector2(0,.11)*unit,OUTLINE,1.5,true)
			var rim:=_ellipse(center,Vector2(.127,.145)*unit)
			draw_colored_polygon(rim,Color("ffd17a") if lit else Color("c3a17c"))
			draw_polyline(rim,OUTLINE,1.4,true)
			draw_polyline(_ellipse(center,Vector2(.075,.146)*unit),Color("9e7258"),1,true)
			for edge:float in [-.132,.132]:
				draw_line(center+Vector2(-.073,edge)*unit,center+Vector2(.073,edge)*unit,OUTLINE,1.8,true)
		elif state.held == service.FRUIT:
			var words: Dictionary = service.speech.get(id,{})
			if words.has("from") and words.left > 2.2:
				var giver: Vector2 = service._position(words.from)
				if giver.is_finite():
					var t := clampf((2.7-float(words.left))/.5,0,1)
					hand = game.world_to_screen(giver+Vector2(0,.1)).lerp(hand,t)-Vector2(0,sin(t*PI)*unit*.18)
			# During the last part of eating the fruit travels from hand to mouth.
			if state.meal > 0 and state.meal < .65:
				var face := visual.get_node("Skeleton/Hips/Torso/Head") as Node2D
				hand = hand.lerp(face.global_position,1.0-state.meal/.65)
			_berry(self,hand,unit*.075)
		elif state.held >= 0:
			var cup: Dictionary = state.cups[int(state.held)]
			var center := hand+Vector2(visual.actor_facing()*.085,-.03)*unit
			for line in cup.shape:
				var points := PackedVector2Array()
				for pair in line: points.append(center+Vector2(pair[0]*visual.actor_facing(),-pair[1])*unit*.32)
				draw_polyline(points,LIGHT,4.5,true)
				draw_polyline(points,OUTLINE,2.1,true)
			if cup.ink > 0:
				draw_line(center+Vector2(-.075,-.034)*unit,center+Vector2(.075,-.034)*unit,INK,2.0,true)
		if service.speech.has(id):
			var anchor: Vector2 = game.world_to_screen(at+Vector2(0,.66))
			var label_at := anchor+Vector2(visual.actor_facing()*28,-24)
			draw_line(anchor,label_at-Vector2(0,2),OUTLINE,1.4,true)
			var speaker := "村民 · " if service.people.has(id) else ""
			_caption(self,label_at,speaker+str(service.speech[id].words),OUTLINE,game.toolbar.get_theme_font("font"),15)
