class_name PaperCombatVisual
extends Node2D

var game = null
const OUTLINE := Color("65767c")
const WHITE := Color("fffdf7")
const TEAL := Color("4caaa8")

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if game == null or game.combat == null: return
	if game.knowledge_world != null and game.knowledge_world.overview: return
	for native in game.combat.natives:
		var at: Vector2 = game.world_to_screen(native.position)
		if not get_viewport_rect().grow(100).has_point(at): continue
		_native_label(native)
	draw_set_transform(Vector2.ZERO)
	if game.combat.bow_equipped and game.active_stroke == null:
		var hand: Node2D = game.character_visual.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip")
		var battle = game.combat
		var direction: Vector2 = battle.bow_direction if battle.bow_charge > 0 or battle.shot_recoil > 0 else (game.aim_world - game.player.position).normalized()
		var charge: float = 1.0 - battle.bow_charge / 0.42 if battle.bow_charge > 0 else 0.0
		draw_set_transform(hand.global_position, Vector2(direction.x, -direction.y).angle())
		_bow(Vector2.ZERO, charge, battle.bow_charge > 0, Color("576f7e"))
		draw_set_transform(Vector2.ZERO)
	if not game.combat.bow_equipped and game.combat.is_bow(): _draw_custom_bow()
	for p in game.combat.projectiles:
		if p.get("kind", "") == "bullet":
			var at: Vector2 = game.world_to_screen(p.position)
			var direction := Vector2(p.velocity.x,-p.velocity.y).normalized()
			draw_line(at-direction*18,at,Color("ad2435"),3,true)
			draw_circle(at,2,Color("292428"))
			continue
		if p.get("kind", "") != "arrow": continue
		var direction := Vector2(p.velocity.x, -p.velocity.y).normalized()
		var at: Vector2 = game.world_to_screen(p.position)
		var color := TEAL if p.get("team", "") == "player" else Color("b78261")
		draw_line(at - direction * 62, at - direction * 22, Color(color, 0.15), 5, true)
		draw_line(at - direction * 40, at - direction * 18, Color(color, 0.40), 2, true)
		draw_set_transform(at, direction.angle())
		_arrow(Vector2.ZERO, color)
		draw_set_transform(Vector2.ZERO)
	_draw_hint()

func _draw_custom_bow() -> void:
	var held = game.character_visual.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip/HeldWeapon")
	var paths: Array = held.world_paths()
	var direction: Vector2 = game.combat.bow_direction if game.combat.bow_charge>0 else (game.aim_world-game.player.position).normalized()
	if direction.length_squared()<.01: direction=Vector2(game.facing,0)
	var normal := direction.orthogonal()
	var lower := Vector2.ZERO
	var upper := Vector2.ZERO
	var lo := INF
	var hi := -INF
	for path in paths:
		for point in path:
			var projection: float = point.dot(normal)
			if projection<lo: lo=projection; lower=point
			if projection>hi: hi=projection; upper=point
	if lo==INF: return
	var charge: float = 1.0-game.combat.bow_charge/.42 if game.combat.bow_charge>0 else 0.0
	var pull := (lower+upper)*.5-direction*charge*.32
	draw_polyline(PackedVector2Array([game.world_to_screen(lower),game.world_to_screen(pull),game.world_to_screen(upper)]),Color("8e7762"),1.5,true)
	if game.combat.bow_charge>0:
		draw_set_transform(game.world_to_screen(pull+direction*.35),Vector2(direction.x,-direction.y).angle())
		_arrow(Vector2.ZERO,TEAL)
		draw_set_transform(Vector2.ZERO)

func _native_label(native: FingertipNative) -> void:
	if not is_instance_valid(native.visual): return
	var head: Node2D = native.visual.get_node("Skeleton/Hips/Torso/Head")
	var at: Vector2 = head.global_position
	if native.health <= 0: return
	draw_string(ThemeDB.fallback_font, at + Vector2(-26, -27), "纸间土著", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, OUTLINE)
	if native.health < native.max_health:
		draw_rect(Rect2(at + Vector2(-19, -21), Vector2(38, 3)), Color("cfd9d2"))
		draw_rect(Rect2(at + Vector2(-19, -21), Vector2(38 * native.health / native.max_health, 3)), TEAL)
	if native.state == "windup":
		draw_string(ThemeDB.fallback_font, at + Vector2(-3, -44), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("bb7b47"))
	if native.bow_equipped:
		var hand: Node2D = native.visual.get_node("Skeleton/Hips/Torso/FrontArm/Forearm/Hand/WeaponGrip")
		var aim: Vector2 = native.aim if native.state == "draw" else Vector2(native.facing, 0)
		draw_set_transform(hand.global_position, Vector2(aim.x, -aim.y).angle())
		_bow(Vector2.ZERO, 1.0 - native.bow_charge / 0.42 if native.bow_charge > 0 else 0.0, native.bow_charge > 0, Color("a5886b"))
		draw_set_transform(Vector2.ZERO)

func _bow(at: Vector2, charge: float, nocked: bool, ink: Color) -> void:
	var curve := PackedVector2Array()
	for i in range(19):
		var t := float(i) / 18
		curve.append(at + Vector2(sin(t * PI) * (11 + charge * 4), (t - 0.5) * 48))
	draw_polyline(curve, Color(1, 0.99, 0.94, 0.9), 6, true)
	draw_polyline(curve, ink, 3, true)
	var pull := at - Vector2(3 + charge * 25, 0)
	draw_polyline(PackedVector2Array([curve[0], pull, curve[-1]]), Color("a9b4be"), 1.3, true)
	if nocked:
		_arrow(pull + Vector2(30, 0), ink)
		if charge > 0.7: draw_circle(pull, 2 + sin(charge * 40) * 0.5, Color("e5bb66"))

func _arrow(tip: Vector2, ink: Color) -> void:
	draw_line(tip - Vector2(29, 0), tip, Color("fffdf2"), 4, true)
	draw_line(tip - Vector2(29, 0), tip, ink, 1.8, true)
	draw_polyline(PackedVector2Array([tip + Vector2(-7, -4), tip, tip + Vector2(-7, 4)]), ink, 2, true)
	for x in [23.0, 27.0]: draw_line(tip - Vector2(x, 0), tip - Vector2(x + 5, 4), ink, 1.5, true)

func _draw_hint() -> void:
	if game.toolbar == null: return # Remote rigs render combat without a personal HUD.
	if game.bag_open or (game.experience != null and game.experience.visible): return
	var battle = game.combat
	var viewport := get_viewport_rect().size
	var amount := PaperGuiScale.factor(viewport)
	var logical := viewport / amount
	var compact := logical.x < 600 or logical.y < 500
	var at := Vector2(23 * amount, game.toolbar.bottom.get_global_rect().position.y - 17 * amount)
	if compact:
		at = Vector2(20 * amount, game.toolbar.bottom.get_global_rect().end.y + 20 * amount)
		if game.knowledge_world != null:
			at.y = maxf(at.y, game.knowledge_world.controls.panel.get_global_rect().end.y + 20 * amount)
		elif game.map_controls != null and game.map_controls.panel.is_visible_in_tree():
			at.y = maxf(at.y, game.map_controls.panel.get_global_rect().end.y + 20 * amount)
	var caption := "按 3 画武器 · 选握点 → 选类型 → 装备" if game.equipped_weapon.is_empty() else PaperWeaponTypes.label(game.equipped_weapon) + " · R / 右键使用"
	if battle.bow_equipped: caption = "试用短弓 · Q 返回手绘武器"
	draw_string(ThemeDB.fallback_font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(13 * amount), Color("617579"))
	if battle.natives_enabled:
		draw_string(ThemeDB.fallback_font, at + Vector2(0, 20 * amount), "纸间土著游荡中 · N 开关", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11 * amount), Color("81918b"))
	if battle.bow_charge > 0:
		var center: Vector2 = game.world_to_screen(game.player.position) + Vector2(-22, 34) * amount
		draw_rect(Rect2(center, Vector2(44, 3) * amount), Color("d2d8d1"))
		draw_rect(Rect2(center, Vector2(44 * (1 - battle.bow_charge / 0.42), 3) * amount), TEAL)
