extends RefCounted

const DIGEST := "669d1b0c116a9383992de0b95fd3949be0c71ce996c9d58943dd92444f24de80"
const INSTALLER := "res://tools/macos_credentials/install.py"
var executable := ""

func _ensure() -> bool:
	var path := OS.get_environment("HOME").path_join("Library/Application Support/Zhijian/Credentials/v1/zhijian-credential")
	if executable.is_empty():
		if OS.execute("/usr/bin/python3", ["-I", ProjectSettings.globalize_path(INSTALLER), "ensure"]) != 0:
			return false
	if FileAccess.get_sha256(path) != DIGEST: return false
	executable = path
	return true

func request(operation: String, row: Dictionary, key := "") -> Dictionary:
	if OS.get_name() != "macOS":
		return {"state":"unavailable" if operation == "store" else "missing"}
	if not _ensure(): return {"state":"unavailable"}
	var args := PackedStringArray([operation, OS.get_user_data_dir().sha256_text(), row.id,
		row.provider, str(row.base_url).sha256_text()])
	var pipes := OS.execute_with_pipe(executable, args, true)
	if not pipes.has("stdio"): return {"state":"unavailable"}
	var pipe: FileAccess = pipes.stdio
	if operation == "store":
		if not pipe.store_line(key):
			pipe.close()
			return {"state":"unavailable"}
		pipe.flush()
	var response := pipe.get_line()
	pipe.close()
	if operation == "restore" and response.begins_with("value "):
		return {"state":"ok","key":response.substr(6)}
	if response in ["ok", "missing", "locked"]: return {"state":response}
	return {"state":"unavailable"}
