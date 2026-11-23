extends RefCounted

const GODS := ["companion", "priest", "war_god"]
const ALL := ["companion", "priest", "war_god", "adventurer-lizhou"]
const NAMES := {"companion":"画家阿靛", "priest":"牧师", "war_god":"战神"}
const NODES := {"companion":"SandboxCompanion", "priest":"SandboxPriest", "war_god":"SandboxWarGod", "adventurer-lizhou":"SandboxAdventurer"}
const CHAT := {"companion":"与阿靛交谈", "priest":"与牧师交谈", "war_god":"与战神交谈"}
const VISIT := {"companion":"去看画家续画", "priest":"去看牧师造生", "war_god":"去看战神"}
const PROMPTS := {"companion":"给阿靛说句话，或描述想画的地形…", "priest":"给牧师说句话，或描述想创造的生物…", "war_god":"给战神说句话，或问问村里的情况…"}

static func enabled() -> Array:
	return GODS if ProjectSettings.get_setting("paper/war_god_enabled", true) else ["companion", "priest"]

# Undelivered chat is returned for explicit resubmission after a session change.
static func read_held_chat(saved:Variant) -> Array:
	var lines:=[]
	if saved is Array:
		for line in saved.slice(-16):
			if line is String and not line.strip_edges().is_empty() and line.length()<=600:
				lines.append(line)
	return lines

static func original_chat_line(messages:Array,words:String) -> Dictionary:
	for i in range(messages.size()-1,-1,-1):
		var row:Dictionary=messages[i]
		if row.get("speaker")=="player" and row.get("text")==words and row.get("delivery","unsent")=="unsent":
			return row
	return {}

static func snapshot_held_chat(held:Array,queued:String,draft:String) -> Array:
	var lines:=held.duplicate()
	if not queued.is_empty() and not draft.is_empty():lines.append(queued)
	return lines.slice(-16)
