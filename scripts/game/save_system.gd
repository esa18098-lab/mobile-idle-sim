extends RefCounted
## Saves: JSON plus a checksum. The checksum catches corrupt or hand-edited
## files; real cheat protection comes from the server check at the galaxy stage.

const PATH := "user://save.json"
const BACKUP := "user://save.bad.json"
const SALT := "mobile-idle-sim/save/v1"


static func checksum(payload: String) -> String:
	return (SALT + payload).sha256_text()


## Writes the sim state and the wall-clock time it was saved at.
static func write(state: Dictionary, saved_unix: float, path: String = PATH) -> bool:
	var payload := JSON.stringify({"saved_unix": saved_unix, "state": state}, "", true, true)  # full float precision
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		push_error("Can't write save: %d" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify({"payload": payload, "checksum": checksum(payload)}))
	f.close()
	# Write-then-rename so a crash mid-save never leaves half a file.
	return DirAccess.rename_absolute(path + ".tmp", path) == OK


## Returns {ok, state, saved_unix, error}. A bad checksum keeps a copy aside.
static func read(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "no save"}
	var outer = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(outer) != TYPE_DICTIONARY or not outer.has("payload") or not outer.has("checksum"):
		return _reject(path, "unreadable save")
	if checksum(outer.payload) != outer.checksum:
		return _reject(path, "checksum mismatch")
	var inner = JSON.parse_string(outer.payload)
	if typeof(inner) != TYPE_DICTIONARY:
		return _reject(path, "unreadable payload")
	return {"ok": true, "state": inner.state, "saved_unix": float(inner.saved_unix), "error": ""}


static func _reject(path: String, why: String) -> Dictionary:
	DirAccess.copy_absolute(path, BACKUP)
	push_warning("Save rejected (%s); a copy is in %s" % [why, BACKUP])
	return {"ok": false, "error": why}
