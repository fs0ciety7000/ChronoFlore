class_name PlantIcon
extends Control
## Small drawn bud used on herbarium pages. Unknown species show as a flat silhouette.

const SILHOUETTE := Color("#cfc6dc")
const STEM := Color("#7bbf6a")

var known: bool = false
var tint: Color = Color("#f3a6c0")

func _init() -> void:
	custom_minimum_size = Vector2(120, 120)

func set_species(p_known: bool, p_tint: Color) -> void:
	known = p_known
	tint = p_tint
	queue_redraw()

func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.9)
	var stem := SILHOUETTE if not known else STEM
	var bloom := SILHOUETTE if not known else tint
	draw_line(c, c + Vector2(0, -48), stem, 6.0, true)
	draw_colored_polygon(_leaf(c + Vector2(0, -22), -1.0), stem)
	draw_colored_polygon(_leaf(c + Vector2(0, -34), 1.0), stem)
	draw_circle(c + Vector2(0, -62), 26.0, bloom)
	if known:
		draw_circle(c + Vector2(-9, -66), 3.5, Color("#4a3f5c"))
		draw_circle(c + Vector2(9, -66), 3.5, Color("#4a3f5c"))
		draw_arc(c + Vector2(0, -58), 7.0, 0.3, PI - 0.3, 10, Color("#4a3f5c"), 2.5, true)
	else:
		draw_string(get_theme_default_font(), c + Vector2(-9, -52), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("#fdf6ea"))

static func _leaf(origin: Vector2, side: float) -> PackedVector2Array:
	return PackedVector2Array([origin, origin + Vector2(22.0 * side, -16), origin + Vector2(34.0 * side, -4), origin + Vector2(18.0 * side, 4)])
