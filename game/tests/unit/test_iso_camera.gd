extends "res://tests/test_case.gd"

const CAMERA_SCENE := "res://scenes/camera/iso_camera.tscn"

func _make(target_pos: Vector3, bounds: Rect2) -> Array:
	var root := Node3D.new()
	tree.root.add_child(root)
	var target := Node3D.new()
	root.add_child(target)
	target.position = target_pos
	var cam := (load(CAMERA_SCENE) as PackedScene).instantiate() as IsoCamera
	cam.bounds = bounds
	root.add_child(cam)
	cam.set_target(target)
	return [root, cam, target]

func test_clamped_focus() -> void:
	var parts := _make(Vector3(30, 0, 0), Rect2(-10, -10, 20, 20))
	var cam := parts[1] as IsoCamera
	cam.snap_to_target()
	assert_near(cam.focus_point().x, 10.0, 0.001, "x clamped to bounds edge")
	assert_near(cam.focus_point().z, 0.0, 0.001, "z untouched")
	var camera := cam.get_node("Camera3D") as Camera3D
	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "orthographic")
	assert_near(camera.size, 22.0, 0.001, "ortho size")
	(parts[0] as Node).free()

func test_camera_iso_angle() -> void:
	var parts := _make(Vector3.ZERO, Rect2())
	var cam := parts[1] as IsoCamera
	var camera := cam.get_node("Camera3D") as Camera3D
	var fwd := -camera.global_transform.basis.z
	assert_near(rad_to_deg(asin(fwd.y)), -35.264, 0.01, "pitch")
	assert_near(fwd.x, fwd.z, 0.001, "yaw 45 deg looks along (-1,-1)")
	assert_true(fwd.x < 0.0, "looks towards -x/-z")
	assert_near(camera.position.length(), 40.0, 0.001, "40 m from focus")
	(parts[0] as Node).free()

func test_follow_is_smoothed() -> void:
	var parts := _make(Vector3.ZERO, Rect2())
	var cam := parts[1] as IsoCamera
	var target := parts[2] as Node3D
	cam.snap_to_target()
	target.position = Vector3(4, 0, 0)
	cam._process(1.0 / 60.0)
	var expected := 4.0 * (1.0 - exp(-6.0 / 60.0))
	assert_near(cam.focus_point().x, expected, 0.001, "lerp factor 1 - exp(-6 dt)")
	(parts[0] as Node).free()
