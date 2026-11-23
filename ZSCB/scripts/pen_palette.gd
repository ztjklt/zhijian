extends RefCounted
## pigment-v1 stores stable material IDs in a stroke. Missing pigment uses the original ink.
const VERSION := "pigment-v1"
const LABELS := {"inherit":"原墨", "ochre":"赭黄", "cinnabar":"朱砂", "indigo":"花青", "malachite":"石绿"}
const COLORS := {"ochre":Color("#ae772f"), "cinnabar":Color("#ae5040"), "indigo":Color("#3f668b"), "malachite":Color("#48816b")}

static func valid(pigment: Variant) -> bool:
	return pigment is String and LABELS.has(pigment)

static func resolve(pigment: String, ink: Color) -> Color:
	return COLORS.get(pigment, ink)

static func swatch(pigment: String) -> ImageTexture:
	var chip := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	chip.fill(Color.TRANSPARENT)
	var tint := resolve(pigment, Color("#343035"))
	for y in 16:
		for x in 16:
			var coverage := clampf(7.0 - Vector2(x-7.5,y-7.5).length(), 0.0, 1.0)
			chip.set_pixel(x,y,Color(tint,coverage))
	return ImageTexture.create_from_image(chip)
