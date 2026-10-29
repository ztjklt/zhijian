shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;
	float ink = 1.0 - dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(vec3(0.035, 0.030, 0.025), source.a * ink);
}
