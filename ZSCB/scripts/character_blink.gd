extends Sprite2D

@export var blink_texture: Texture2D
var open_texture: Texture2D
var is_blinking := false
var artwork_size := Vector2.ZERO

func _ready() -> void:
	open_texture = texture
	if texture:
		artwork_size = texture.get_size() * scale

func set_blinking(value: bool) -> void:
	is_blinking = value
	texture = blink_texture if value and blink_texture else open_texture
	if texture and artwork_size != Vector2.ZERO:
		scale = artwork_size / texture.get_size()

func _process(_delta: float) -> void:
	var next_blink := fmod(Time.get_ticks_msec() * 0.001, 4.7) > 4.56
	if next_blink != is_blinking:
		set_blinking(next_blink)
