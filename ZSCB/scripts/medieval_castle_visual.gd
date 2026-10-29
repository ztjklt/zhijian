extends Node2D
## Atlas pieces retain separate damage geometry and share identical ink material.
var entity: RigidBody2D
var game
const InkShader := preload("res://scripts/medieval_castle_ink.gdshader")
static var shared_ink_material: ShaderMaterial
var cached_cuts := -1
var cached_polygons: Array = []
var cached_uvs: Array = []

func _ready() -> void:
	if shared_ink_material == null:
		shared_ink_material = ShaderMaterial.new()
		shared_ink_material.shader = InkShader
	material = shared_ink_material
	z_index = 1

func _process(_delta: float) -> void:
	if not is_instance_valid(entity):
		hide()
		return
	visible = entity.alive and MedievalVisibility.entity_visible(game, entity)
	if not visible: return
	queue_redraw()

func _draw() -> void:
	if game == null or not is_instance_valid(entity) or not entity.alive or entity.texture == null: return
	var tint := Color(1,1,1,0.45 if entity.hurt_timer > 0 and int(entity.age*18)%2 == 0 else 1.0)
	if cached_cuts != entity.cuts.size():
		cached_cuts = entity.cuts.size()
		cached_polygons = entity.render_polygons.duplicate(true)
		cached_uvs.clear()
		for polygon in cached_polygons:
			var uvs := PackedVector2Array()
			for p in polygon: uvs.append(entity.texture_uv(p))
			cached_uvs.append(uvs)
	# Projection is one native transform; local vertices/UVs change only at cuts.
	draw_set_transform(game.world_to_screen(entity.position), -entity.rotation, Vector2(game.PIXELS_PER_UNIT, -game.PIXELS_PER_UNIT))
	for i in cached_polygons.size():
		draw_polygon(cached_polygons[i],PackedColorArray([tint]),cached_uvs[i],entity.texture)
	draw_set_transform(Vector2.ZERO)
