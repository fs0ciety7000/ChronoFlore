class_name NightPalette
extends RefCounted
## Sky/light colours as a function of night progress (0 = 0 h, 1 = 8 h), linearly interpolated.

# Each key: [progress, background, sun_color, sun_energy, ambient_color, sun_pitch_deg, plant_glow]
const KEYS := [
	[0.0, "f6efe0", "fff4e0", 1.0, "fdf6ea", -55.0, 0.0],
	[0.25, "f6efe0", "ffe9cc", 0.95, "f7efe6", -40.0, 0.0],
	[0.375, "2e2f63", "8d8fd8", 0.45, "5a5c9e", -60.0, 1.0],
	[0.75, "2e2f63", "8d8fd8", 0.45, "5a5c9e", -60.0, 1.0],
	[1.0, "f7c9d4", "ffd1dc", 0.8, "f0d4e8", -20.0, 0.3],
]

static func sample(progress: float) -> Dictionary:
	var t := clampf(progress, 0.0, 1.0)
	var i := 0
	while i < KEYS.size() - 2 and t > float(KEYS[i + 1][0]):
		i += 1
	var a: Array = KEYS[i]
	var b: Array = KEYS[i + 1]
	var span: float = float(b[0]) - float(a[0])
	var k: float = clampf((t - float(a[0])) / span, 0.0, 1.0)
	return {
		"background": Color(a[1]).lerp(Color(b[1]), k),
		"sun_color": Color(a[2]).lerp(Color(b[2]), k),
		"sun_energy": lerpf(float(a[3]), float(b[3]), k),
		"ambient_color": Color(a[4]).lerp(Color(b[4]), k),
		"sun_pitch_deg": lerpf(float(a[5]), float(b[5]), k),
		"plant_glow": lerpf(float(a[6]), float(b[6]), k),
	}
