class_name PaperCombatAudio
extends RefCounted
## Stable bounded sound keys travel with the originating attack, never equipment at receipt.
const KEYS := ["sword_swing","sword_hit","hammer_swing","hammer_hit","spear_swing","spear_hit","bow_draw","bow_shoot","bow_hit","firearm_shoot","firearm_hit","death_human_low","death_human_high","death_horse","death_rabbit","death_deer","death_bat","death_dragon"]
static func valid(cue: String) -> bool:return cue in KEYS
static func cue(kind: String, weapon: String) -> String:
	if not PaperWeaponTypes.valid(weapon):weapon="sword"
	if kind=="draw_bow":return "bow_draw"
	if kind=="shoot":return "firearm_shoot" if weapon=="firearm" else "bow_shoot"
	if kind=="swing":return weapon+"_swing" if weapon in ["sword","hammer","spear"] else "sword_swing"
	if kind in ["hit","hurt","break"]:return weapon+"_hit"
	return ""
static func death(kind: String) -> String:
	if kind=="queen":return "death_human_high"
	if kind in ["player","native","villager","driver","general","knight","king"]:return "death_human_low"
	if kind in ["horse","rabbit","deer","bat","dragon"]:return "death_"+kind
	return ""
static func impact(feedback,kind: String,at: Vector2,weapon: String="sword") -> void:
	if feedback.has_method("emit_combat"):feedback.emit_combat(kind,at,weapon)
	else:feedback.emit_event(kind,at)
static func cry(feedback,kind: String,at: Vector2) -> void:
	var key:=death(kind)
	if key!="" and feedback!=null and feedback.has_method("emit_audio"):feedback.emit_audio(key,at)
static func projectile(projectile: Dictionary) -> String:
	return "firearm" if projectile.get("kind","")=="bullet" else "bow"
