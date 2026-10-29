shader_type spatial;
// Net swoosh trail on a flat ring sector: UV.x runs along the sweep (0 = start), UV.y from the
// inner edge (0) to the outer rim (1). The head sits at `progress`; behind it the trail fades
// over `trail`, ahead of it nothing is drawn yet.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float progress = 0.0;
uniform float trail = 0.6;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.99, 0.96, 1.0);
uniform vec4 inner_color : source_color = vec4(1.0, 0.7, 0.84, 1.0);

void fragment() {
	float behind = progress - UV.x;
	float fade = 1.0 - clamp(behind / trail, 0.0, 1.0);
	float alpha = step(0.0, behind) * fade * fade;
	float r = UV.y;
	alpha *= smoothstep(0.0, 0.4, r) * (0.55 + 0.45 * r);
	ALBEDO = mix(inner_color.rgb, rim_color.rgb, smoothstep(0.45, 0.95, r));
	ALPHA = clamp(alpha * opacity, 0.0, 1.0);
}
