shader_type canvas_item;
render_mode unshaded;
uniform sampler2D world_screen : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0, 0.4) = 0.18;

void fragment() {
	vec2 step_uv = SCREEN_PIXEL_SIZE;
	vec3 center = texture(world_screen, SCREEN_UV).rgb;
	vec3 n = texture(world_screen, SCREEN_UV + vec2(0, -step_uv.y)).rgb;
	vec3 s = texture(world_screen, SCREEN_UV + vec2(0, step_uv.y)).rgb;
	vec3 e = texture(world_screen, SCREEN_UV + vec2(step_uv.x, 0)).rgb;
	vec3 w = texture(world_screen, SCREEN_UV + vec2(-step_uv.x, 0)).rgb;
	vec3 lo = min(center, min(min(n, s), min(e, w)));
	vec3 hi = max(center, max(max(n, s), max(e, w)));
	// Neighborhood clamp retains smooth alpha edges without bright/dark halos.
	vec3 sharpened = clamp(center + (center - (n + s + e + w) * 0.25) * strength, lo, hi);
	COLOR = vec4(sharpened, 1.0);
}
