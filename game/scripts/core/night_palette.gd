class_name NightPalette
extends RefCounted
## Sky/light colours as a function of night progress (0 = 0 h, 1 = 8 h), linearly interpolated.

# Each key: [progress, background, sun_color, sun_energy, ambient_color, sun_pitch_deg, plant_glow,
#             saturation (Environment adjustment), tint (0..1 mix towards ambient_color via fog)]
const KEYS := [
	[0.0, "f6efe0", "fff7ea", 0.15, "f3efe9", -55.0, 0.0, 0.85, 0.0],
	[0.25, "f6ece0", "ffe8d2", 0.14, "f5e9e2", -40.0, 0.0, 0.85, 0.0],
	[0.375, "3b3d78", "c0b2ff", 0.1, "aea2ff", -60.0, 1.0, 1.15, 0.22],
	[0.75, "3b3d78", "c0b2ff", 0.1, "aea2ff", -60.0, 1.0, 1.15, 0.22],
	[1.0, "f7c9d4", "ffc9bd", 0.17, "ffc4dc", -20.0, 0.3, 1.05, 0.2],
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
		"saturation": lerpf(float(a[7]), float(b[7]), k),
		"tint": lerpf(float(a[8]), float(b[8]), k),
	}
