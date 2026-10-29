shader_type spatial;
// Cartoon net bag: translucent white with a bright mesh grid (UV.x around, UV.y along the bag),
// a little self-lit so it reads at night from the iso camera.
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 mesh_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float cells_around = 14.0;
uniform float cells_along = 5.0;
uniform float line_width : hint_range(0.0, 0.5) = 0.16;
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.38;

void fragment() {
	vec2 g = fract(vec2(UV.x * cells_around, UV.y * cells_along));
	vec2 d = min(g, 1.0 - g);
	float line = 1.0 - smoothstep(line_width * 0.5, line_width, min(d.x, d.y));
	ALBEDO = mesh_color.rgb;
	EMISSION = mesh_color.rgb * (0.15 + 0.25 * line);
	ROUGHNESS = 0.9;
	ALPHA = mix(fill_alpha, 1.0, line);
}
