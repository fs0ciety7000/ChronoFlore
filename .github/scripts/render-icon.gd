# Renders an SVG to a square PNG with Godot's own SVG rasterizer (no extra
# packages on the runner).
# Usage: godot --headless --script .github/scripts/render-icon.gd -- in.svg out.png 256
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("usage: -- <in.svg> <out.png> <size>")
		quit(2)
		return
	var svg := FileAccess.get_file_as_string(args[0])
	var size := int(args[2])
	var probe := Image.new()
	if svg.is_empty() or probe.load_svg_from_string(svg) != OK:
		printerr("cannot read SVG: %s" % args[0])
		quit(1)
		return
	var image := Image.new()
	image.load_svg_from_string(svg, float(size) / max(probe.get_width(), probe.get_height()))
	if image.get_width() != size or image.get_height() != size:
		image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var err := image.save_png(args[1])
	if err != OK:
		printerr("cannot write PNG: %s" % args[1])
	quit(0 if err == OK else 1)
