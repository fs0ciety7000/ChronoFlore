class_name ClockFlower
extends Control
## "Fleur-horloge": a cream dial ringed by petals (one per lucidity point) with a green
## leaf hand that makes one turn per night. Echoes the logo.

const DIAL_COLOR := Color("#fdf6ea")
const DIAL_EDGE := Color("#e6d9c3")
const PETAL_PINK := Color("#f3a6c0")
const PETAL_LAVENDER := Color("#c9b3f0")
const PETAL_LOST := Color("#b9b2c4")
const NEEDLE_COLOR := Color("#7bbf6a")
const NEEDLE_DARK := Color("#5a9a4c")
const TEXT_COLOR := Color("#4a3f5c")

const DIAL_RADIUS := 34.0
const PETAL_DISTANCE := 54.0
const PETAL_LENGTH := 26.0
const PETAL_WIDTH := 17.0
const NEEDLE_LENGTH := 30.0
const LABEL_SIZE := 24
const LABEL_GAP := 30.0
const NIGHT_MINUTES := 480

## Radians clockwise from 12 o'clock; 8 h = TAU.
var needle_angle: float = 0.0
var lost: int = 0
var max_petals: int = 5
var label_text: String = "0 h 00"
## The title screen hides the time label.
var show_label: bool = true

func _init() -> void:
	custom_minimum_size = Vector2(2.0 * (PETAL_DISTANCE + PETAL_LENGTH * 0.5) + 8.0, \
			2.0 * (PETAL_DISTANCE + PETAL_LENGTH * 0.5) + LABEL_GAP + 14.0)

## "3 h 20" from night minutes.
static func format_time(minutes: int) -> String:
	return "%d h %02d" % [floori(minutes / 60.0), minutes % 60]

func set_state(progress: float, petals: int, p_max_petals: int) -> void:
	var p := clampf(progress, 0.0, 1.0)
	needle_angle = p * TAU
	max_petals = maxi(p_max_petals, 0)
	lost = max_petals - clampi(petals, 0, max_petals)
	label_text = format_time(roundi(p * NIGHT_MINUTES))
	queue_redraw()

func _draw() -> void:
	var c := Vector2(size.x * 0.5, PETAL_DISTANCE + PETAL_LENGTH * 0.5 + 4.0)
	for i in max_petals:
		var a := TAU * float(i) / float(max_petals)
		var dir := Vector2(sin(a), -cos(a))
		var center := c + dir * PETAL_DISTANCE
		var pts := _ellipse(center, PETAL_WIDTH, PETAL_LENGTH * 0.5, a)
		var is_lost := i >= max_petals - lost
		if is_lost:
			var outline := pts.duplicate()
			outline.append(pts[0])
			draw_polyline(outline, PETAL_LOST, 3.0, true)
		else:
			draw_colored_polygon(pts, PETAL_PINK if i % 2 == 0 else PETAL_LAVENDER)
	draw_circle(c, DIAL_RADIUS + 3.0, DIAL_EDGE)
	draw_circle(c, DIAL_RADIUS, DIAL_COLOR)
	for t in 4:
		var ta := TAU * float(t) / 4.0
		var td := Vector2(sin(ta), -cos(ta))
		draw_line(c + td * (DIAL_RADIUS - 8.0), c + td * (DIAL_RADIUS - 3.0), DIAL_EDGE, 3.0, true)
	var nd := Vector2(sin(needle_angle), -cos(needle_angle))
	var side := Vector2(-nd.y, nd.x)
	var leaf := PackedVector2Array([
		c, c + nd * 9.0 + side * 6.0, c + nd * NEEDLE_LENGTH, c + nd * 9.0 - side * 6.0])
	draw_colored_polygon(leaf, NEEDLE_COLOR)
	draw_line(c, c + nd * (NEEDLE_LENGTH - 3.0), NEEDLE_DARK, 1.5, true)
	draw_circle(c, 4.0, NEEDLE_DARK)
	if not show_label:
		return
	var font := get_theme_default_font()
	var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
	var base := Vector2(c.x - text_size.x * 0.5, c.y + PETAL_DISTANCE + PETAL_LENGTH * 0.5 + LABEL_GAP * 0.6 + 8.0)
	draw_string(font, base, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, TEXT_COLOR)

## Ellipse polygon whose long axis (half-length `ry`) points along the angle `a` from 12 o'clock.
static func _ellipse(center: Vector2, width: float, ry: float, a: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rx := width * 0.5
	for k in 20:
		var t := TAU * float(k) / 20.0
		pts.append(center + Vector2(cos(t) * rx, sin(t) * ry).rotated(a))
	return pts
