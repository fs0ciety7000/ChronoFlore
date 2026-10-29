shader_type spatial;
// Soft ground sign announcing a hostile attack: a pulsing rim plus a fill that grows until the
// impact. Unshaded so it reads the same by day and at night. shape 0 = disc (UV centre),
// shape 1 = lane (UV.y from the start (0) to the end (1), with chevrons pointing along it).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 rim_color : source_color = vec4(1.0, 0.45, 0.5, 1.0);
uniform vec4 fill_color : source_color = vec4(1.0, 0.7, 0.72, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float pulse_rate = 6.0;
uniform int shape = 0;

void fragment() {
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_rate);
	float rim = 0.0;
	float fill = 0.0;
	float base = 0.0;
	if (shape == 0) {
		float r = length(UV * 2.0 - 1.0);
		float inside = 1.0 - smoothstep(0.97, 1.0, r);
		rim = smoothstep(0.80, 0.86, r) * inside;
		base = 0.22 * inside;
		fill = (1.0 - smoothstep(progress - 0.04, progress, r)) * inside;
	} else {
		float x = abs(UV.x * 2.0 - 1.0);
		float y = UV.y;
		float inside = (1.0 - smoothstep(0.94, 1.0, x)) * step(0.0, y) * step(y, 1.0);
		rim = smoothstep(0.72, 0.8, x) * inside;
		base = 0.2 * inside;
		fill = (1.0 - smoothstep(progress - 0.03, progress, y)) * inside;
		float chevron = fract(y * 5.0 - x * 0.6 - TIME * 1.5);
		rim = max(rim, smoothstep(0.0, 0.08, chevron) * (1.0 - smoothstep(0.16, 0.24, chevron)) * inside * 0.8);
	}
	vec3 col = mix(fill_color.rgb, rim_color.rgb, rim);
	float a = max(base, max(rim * pulse, fill * 0.55));
	ALBEDO = col;
	ALPHA = clamp(a * opacity, 0.0, 1.0);
}
