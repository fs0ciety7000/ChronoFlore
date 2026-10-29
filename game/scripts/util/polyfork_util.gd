class_name PolyforkUtil
extends RefCounted
## Helpers for Polyfork GLB assets.

## Polyfork GLBs carry their colours as COLOR_0 vertex colours, but Godot imports them with
## vertex_color_use_as_albedo = false, so they render white. For every MeshInstance3D under root,
## override each BaseMaterial3D surface with a duplicate that uses vertex colours as albedo.
## Duplicates are shared per source material within one call; source materials stay untouched.
static func enable_vertex_colors(root: Node) -> void:
	var fixed: Dictionary = {}
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node: Node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat == null or mat.vertex_color_use_as_albedo:
				continue
			if not fixed.has(mat):
				var copy := mat.duplicate() as BaseMaterial3D
				copy.vertex_color_use_as_albedo = true
				fixed[mat] = copy
			mi.set_surface_override_material(s, fixed[mat])
