shader_type canvas_item;
render_mode unshaded;

// Flat gray recolor; preserve original coverage instead of expanding atlas edges.
uniform vec4 body_color : source_color = vec4(0.46, 0.49, 0.53, 1.0);
uniform vec4 detail_color : source_color = vec4(0.95, 0.97, 0.99, 1.0);
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float luminance = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	vec3 recolored = mix(body_color.rgb, detail_color.rgb, smoothstep(0.60, 0.90, luminance));
	COLOR = vec4(recolored, source.a) * vertex_tint;
}
