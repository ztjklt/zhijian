extends "res://tests/network_feedback_bot.gd"
var replicated_ink_consumption := false

func _process(delta: float) -> bool:
	super(delta)
	if session != null and session.game != null and session.game.ink.amount < 300:
		replicated_ink_consumption = true
	return false

func mark(name: String, value: String = "ok") -> void:
	if name == role + ".checked":
		if not replicated_ink_consumption:
			fail("authority ink consumption was never replicated")
			return
		print("NETWORK VITALS PASS ", role, ": authority ink cost arrived in personal HUD state")
	super(name, value)
