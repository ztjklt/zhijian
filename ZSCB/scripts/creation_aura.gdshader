shader_type canvas_item;
render_mode unshaded;

uniform vec2 canvas_size = vec2(1280.0, 720.0);
uniform vec2 origin = vec2(640.0, 360.0);
uniform float age = 0.0;

void fragment() {
	vec2 offset = UV * canvas_size - origin;
	float distance_px = length(offset);
	float progress = clamp(age / 1.2, 0.0, 1.0);
	float fade = pow(1.0 - progress, 1.4);
	float radius = (1.0 - pow(1.0 - progress, 2.3)) * length(canvas_size);
	float wave = exp(-pow((distance_px - radius) / 24.0, 2.0));
	float echo = exp(-pow((distance_px - radius * 0.70) / 8.0, 2.0));
	float angle = atan(offset.y, offset.x);
	vec3 prism = 0.5 + 0.5 * cos(angle * 1.4 + distance_px * 0.008 + vec3(0.0, 2.1, 4.2));
	prism = mix(vec3(0.54, 0.35, 0.88), prism, 0.65);
	float halo = exp(-distance_px / 250.0) * exp(-age * 3.0);
	float rays = pow(max(0.0, cos(angle * 10.0 + age * 0.12)), 24.0);
	rays *= exp(-distance_px / 440.0) * exp(-age * 5.0);
	float wash = sin(progress * 3.14159) * 0.07;
	vec3 tint = mix(vec3(0.19, 0.17, 0.40), prism, clamp(wave + echo + halo, 0.0, 1.0));
	tint = mix(tint, vec3(1.0, 0.92, 0.67), rays * 0.7);
	float alpha = wash + (wave * 0.40 + echo * 0.20 + halo * 0.23 + rays * 0.32) * fade;
	COLOR = vec4(tint, clamp(alpha, 0.0, 0.48));
}
