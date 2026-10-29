class_name SaveStore
extends RefCounted
## Reads and writes the Herbarium as JSON. Never crashes on a bad file.

const DEFAULT_PATH := "user://save.json"

## Writes via a temp file so a crash mid-write cannot truncate the previous save.
static func save(h: Herbarium, path: String = DEFAULT_PATH) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(h.to_dict()))
	f.close()
	return DirAccess.rename_absolute(tmp, path)

## Missing, unparsable or invalid file -> fresh Herbarium. An existing file that cannot be
## used is first copied to path + ".bak" so it is not silently lost.
static func load_or_new(path: String = DEFAULT_PATH) -> Herbarium:
	if not FileAccess.file_exists(path):
		return Herbarium.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		var h := Herbarium.from_dict(parsed)
		if h != null:
			return h
	DirAccess.copy_absolute(path, path + ".bak")
	return Herbarium.new()
