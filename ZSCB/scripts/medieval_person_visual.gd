extends "res://scripts/character_visual.gd"
## Original hero scene, animated without player input or native combat/recolouring.
var entity: RigidBody2D
var visual_state := "idle"
static var head_alpha_bounds := {}
static var friendly_head_material: ShaderMaterial
var friendly_face: Node2D
const Outfit := preload("res://scripts/medieval_person_outfit.gd")

func _ready() -> void:
	# Keep the exact scene skeleton, textures, blink and animation library. The
	# hero's combat overlays are deliberately not installed for unarmed people.
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var hat := Outfit.new()
	hat.name = "IdentityHat"
	hat.part = "hat"
	hat.role = entity.kind
	hat.position = head_contact_point()
	$Skeleton/Hips/Torso/Head.add_child(hat)
	var coat := Outfit.new()
	coat.name = "IdentityCoat"
	coat.part = "coat"
	coat.role = entity.kind
	$Skeleton/Hips/Torso.add_child(coat)
	if entity.is_person():
		var head: Sprite2D = $Skeleton/Hips/Torso/Head/Ink
		# Only the head's bright angry eyes are covered; alpha, texture and
		# the original round silhouette remain exactly those of the hero.
		if friendly_head_material == null:
			var shader := Shader.new()
			shader.code = "shader_type canvas_item; void fragment(){ vec4 ink=texture(TEXTURE,UV)*COLOR; float light=max(ink.r,max(ink.g,ink.b)); ink.rgb=mix(ink.rgb,vec3(0.06,0.055,0.05),smoothstep(0.09,0.3,light)); COLOR=ink; }"
			friendly_head_material = ShaderMaterial.new()
			friendly_head_material.shader = shader
		head.material = friendly_head_material
		friendly_face = Outfit.new()
		friendly_face.name = "GentleEyes"
		friendly_face.part = "eyes"
		$Skeleton/Hips/Torso/Head.add_child(friendly_face)
	_process(0)

func head_contact_point() -> Vector2:
	var head: Sprite2D = $Skeleton/Hips/Torso/Head/Ink
	var texture: Texture2D = head.texture
	if not head_alpha_bounds.has(texture.resource_path):
		head_alpha_bounds[texture.resource_path] = texture.get_image().get_used_rect()
	var used: Rect2i = head_alpha_bounds[texture.resource_path]
	# Sprite2D centers its texture, and the original head has a -1px offset.
	return head.position+Vector2(0,(used.position.y-texture.get_height()*0.5)*head.scale.y+0.3)

func actor_body(): return entity
func actor_facing() -> int: return entity.facing if is_instance_valid(entity) else 1
func actor_weapon() -> Dictionary: return {}
func actor_state(): return null

func _process(delta: float) -> void:
	if game == null or not is_instance_valid(entity): return
	visible = MedievalVisibility.entity_visible(game, entity)
	if not visible: return
	var seated: bool = entity.kind == "driver" and entity.alive and entity.companion_id != ""
	visual_state = "seated" if seated else entity.state
	var next_pose := "walk" if entity.alive and entity.hurt_timer <= 0 and not seated and absf(entity.linear_velocity.x) > 0.2 else "idle"
	if next_pose != current_pose:
		animator.play(next_pose,0.10)
		current_pose = next_pose
	animator.speed_scale = clampf(absf(entity.linear_velocity.x)/0.65,0.7,1.6) if next_pose == "walk" else 1.0
	# Explicit advancement makes the bone overlays deterministic, including when
	# the body is frozen on a wagon or the final corpse must stop moving.
	animator.advance(delta if entity.alive and entity.hurt_timer <= 0 and not seated else 0)
	var anchor := Vector2(0,0.54)
	rotation = 0
	modulate = Color.WHITE
	if not entity.alive:
		animator.seek(0,true)
		_set_prone()
		rotation = float(entity.facing)*PI*0.5
		anchor.y = 0.17
	elif seated:
		rotation = -entity.rotation
		animator.seek(0,true)
		_set_seated()
	elif entity.hurt_timer > 0:
		animator.seek(0,true)
		$Skeleton/Hips/Torso.rotation = -0.2
		$Skeleton/Hips/Torso/Head.rotation = 0.15
		$Skeleton/Hips/Torso/FrontArm.rotation = -0.8
		$Skeleton/Hips/Torso/BackArm.rotation = 0.5
		rotation = clampf(-entity.linear_velocity.x*0.025,-0.25,0.25)
	position = game.world_to_screen(entity.position+anchor)
	scale = Vector2(float(entity.facing),1)*game.PIXELS_PER_UNIT/78.0
	$Skeleton/Hips/Torso/Head/IdentityHat.position = head_contact_point()
	_adapt_grounded_feet()
	pencil.visible = false
	if is_instance_valid(friendly_face):
		var closed: bool = $Skeleton/Hips/Torso/Head/Ink.is_blinking
		if friendly_face.eyes_closed != closed:
			friendly_face.eyes_closed = closed
			friendly_face.queue_redraw()

func _set_seated() -> void:
	$Skeleton/Hips.position = Vector2(0,-12.5)
	$Skeleton/Hips/Torso.rotation = 0.04
	$Skeleton/Hips/FrontLeg.rotation = -1.45
	$Skeleton/Hips/BackLeg.rotation = -1.25
	$Skeleton/Hips/FrontLeg/Shin.rotation = 1.5
	$Skeleton/Hips/BackLeg/Shin.rotation = 1.4
	$Skeleton/Hips/FrontLeg/Shin/Foot.rotation = -0.1
	$Skeleton/Hips/BackLeg/Shin/Foot.rotation = -0.1
	$Skeleton/Hips/Torso/FrontArm.rotation = -1.05
	$Skeleton/Hips/Torso/FrontArm/Forearm.rotation = -0.45
	$Skeleton/Hips/Torso/BackArm.rotation = -0.8
	$Skeleton/Hips/Torso/BackArm/Forearm.rotation = -0.55

func _set_prone() -> void:
	$Skeleton/Hips.position = Vector2.ZERO
	$Skeleton/Hips/Torso.rotation = 0.1
	$Skeleton/Hips/Torso/Head.rotation = -0.08
	$Skeleton/Hips/FrontLeg.rotation = -0.06
	$Skeleton/Hips/BackLeg.rotation = 0.13
	$Skeleton/Hips/FrontLeg/Shin.rotation = 0.1
	$Skeleton/Hips/BackLeg/Shin.rotation = 0.16
	$Skeleton/Hips/FrontLeg/Shin/Foot.rotation = -0.1
	$Skeleton/Hips/BackLeg/Shin/Foot.rotation = -0.15
	$Skeleton/Hips/Torso/FrontArm.rotation = -0.18
	$Skeleton/Hips/Torso/BackArm.rotation = 0.35
	$Skeleton/Hips/Torso/FrontArm/Forearm.rotation = -0.2
	$Skeleton/Hips/Torso/BackArm/Forearm.rotation = -0.25

func _nearby_support_edges(world) -> Array:
	var edges: Array = []
	if entity.kind not in ["king","queen"]: return edges
	var bodies = world.get("entities") if world != null else null
	if not bodies is Array: return edges
	for body in bodies:
		if not is_instance_valid(body) or body == entity or not body.alive or body.is_actor(): continue
		# Bound the collection before transforming detailed castle polygons.
		var bounds: Rect2 = body.bounds()
		if not bounds.intersects(Rect2(entity.position-Vector2(0.75,0.22),Vector2(1.5,0.44)),true): continue
		for segment in body.world_walk_segments():
			var a: Vector2 = segment[0]
			var b: Vector2 = segment[1]
			var edge := b-a
			if absf(edge.x) < .00001: continue
			if maxf(a.x,b.x) < entity.position.x-0.75 or minf(a.x,b.x) > entity.position.x+0.75: continue
			if maxf(a.y,b.y) < entity.position.y-0.22 or minf(a.y,b.y) > entity.position.y+0.22: continue
			edges.append({"a":a,"b":b,"slope":edge.y/edge.x})
	return edges

func _support_at(x: float, edges: Array, terrain) -> Dictionary:
	var best := {}
	var nearest := INF
	for edge in edges:
		if x < minf(edge.a.x,edge.b.x) or x > maxf(edge.a.x,edge.b.x): continue
		var y: float = edge.a.y+(x-edge.a.x)*edge.slope
		var gap := absf(y-entity.position.y)
		if gap <= 0.22 and gap < nearest:
			nearest = gap
			best = {"y":y,"slope":edge.slope}
	if terrain != null and terrain.has_method("travel_height"):
		var y: float = terrain.travel_height(x)
		var gap := absf(y-entity.position.y)
		# A grounded root sits above the uphill part of its footprint. Downhill
		# soles may be farther below it while still on the same continuous road.
		# The center/airborne gate in _adapt_grounded_feet remains strict.
		var center_y: float = terrain.travel_height(entity.position.x)
		var foot_band := 0.22 + minf(0.7, absf(y-center_y))
		if gap <= foot_band and gap < nearest:
			best = {"y":y,"slope":(terrain.travel_height(x+0.07)-terrain.travel_height(x-0.07))/0.14}
	return best

func _adapt_grounded_feet() -> void:
	if not entity.alive or entity.hurt_timer > 0 or visual_state == "seated" or entity.linear_velocity.y > 1.0: return
	var world = entity.get_parent()
	var terrain = world.get("terrain") if world != null else null
	# Gather once, then sample only center and the two soles. The narrow vertical
	# band follows the actual body support, not the highest castle roof at X.
	var edges := _nearby_support_edges(world)
	var center := _support_at(entity.position.x,edges,terrain)
	if center.is_empty() or absf(entity.position.y-center.y) > 0.18: return
	rotation = clampf(-atan(center.slope)*0.45,-0.3,0.3)
	var hips: Bone2D = $Skeleton/Hips
	var original_hips := hips.position
	hips.position.y = 15.0
	var contacts: Array = []
	for side in ["FrontLeg","BackLeg"]:
		var upper: Bone2D = get_node("Skeleton/Hips/"+side)
		var foot: Bone2D = upper.get_node("Shin/Foot")
		var current_screen := foot.to_global(Vector2(2.4,4.25))
		var world_x: float = entity.position.x+(current_screen.x-position.x)/game.PIXELS_PER_UNIT
		var support := _support_at(world_x,edges,terrain)
		if support.is_empty():
			hips.position = original_hips
			rotation = 0
			return
		contacts.append({"upper":upper,"x":world_x,"support":support})
	# Lower the hips just enough for the downhill leg to reach. Clamping an
	# overextended ankle to33px otherwise leaves that sole hovering on slopes.
	var extension := 0.0
	for contact in contacts:
		var angle: float = -atan(contact.support.slope)
		var sole_offset: Vector2 = Vector2(2.4*float(entity.facing),4.25).rotated(angle)*game.PIXELS_PER_UNIT/78.0
		contact["ankle"] = game.world_to_screen(Vector2(contact.x,contact.support.y))-sole_offset
		var upper: Bone2D = contact.upper
		var target: Vector2 = upper.get_parent().to_local(contact.ankle)-upper.position
		extension = maxf(extension,target.length()-32.7)
	if extension > 0:
		hips.position.y += minf(extension+0.35,12.0)
	for contact in contacts:
		var upper: Bone2D = contact.upper
		var shin: Bone2D = upper.get_node("Shin")
		var foot: Bone2D = shin.get_node("Foot")
		var sole := Vector2(2.4,4.25)
		var screen_angle: float = -atan(contact.support.slope)
		var ankle_screen: Vector2 = contact.ankle
		var local_target: Vector2 = upper.get_parent().to_local(ankle_screen)-upper.position
		var distance := clampf(local_target.length(),0.1,32.95)
		var bend := acos(clampf((16.0*16.0+distance*distance-17.0*17.0)/(32.0*distance),-1,1))
		upper.rotation = local_target.angle()-PI*0.5-bend
		shin.rotation = PI-acos(clampf((16.0*16.0+17.0*17.0-distance*distance)/(2.0*16.0*17.0),-1,1))
		var tangent_screen := Vector2(cos(screen_angle),sin(screen_angle))*float(entity.facing)
		var ankle_local: Vector2 = foot.get_parent().to_local(ankle_screen)
		var direction_local: Vector2 = foot.get_parent().to_local(ankle_screen+tangent_screen)-ankle_local
		foot.rotation = direction_local.angle()
