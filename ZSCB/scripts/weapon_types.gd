class_name PaperWeaponTypes
extends RefCounted
## Type chooses behavior; geometry and grip always remain the player's own ink.
const IDS := ["sword", "hammer", "bow", "spear", "firearm"]
const LABELS := {"sword":"剑／刀", "hammer":"锤", "bow":"弓", "spear":"长枪", "firearm":"火枪"}
const HINTS := {"sword":"快速挥砍 · 四式连击", "hammer":"蓄势重击 · 强力击退", "bow":"瞄准拉弓 · 发射箭矢", "spear":"向前突刺 · 直线出击", "firearm":"瞄准射击 · 快速弹丸"}
static func valid(value: Variant) -> bool:
	return value is String and value in IDS
static func kind(weapon: Dictionary) -> String:
	return weapon.get("weapon_type", "sword") if valid(weapon.get("weapon_type", "sword")) else "sword"
static func label(weapon: Dictionary) -> String:
	return LABELS[kind(weapon)]
static func ranged(weapon: Dictionary) -> bool:
	return kind(weapon) in ["bow", "firearm"]
static func duration(weapon: Dictionary) -> float:
	return .72 if kind(weapon)=="hammer" else .46 if kind(weapon)=="spear" else .36
static func attack_cooldown(weapon: Dictionary) -> float:
	return maxf(float(weapon.get("cooldown", .4)), .88 if kind(weapon)=="hammer" else .5 if kind(weapon)=="spear" else .36)
static func damage(weapon: Dictionary, speed: float) -> float:
	return clampf(PaperBladeSweep.model_damage(weapon,speed) * (1.35 if kind(weapon)=="hammer" else 1.0),5,40)
static func impulse(weapon: Dictionary) -> float:
	return 1.8 if kind(weapon)=="hammer" else 1.0
