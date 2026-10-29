extends PaperCreationFeedback
## The authority records cues; only clients allocate presentation/audio nodes.
var room = null
var source_id := ""
func _ready() -> void:
	pass
func _process(_delta: float) -> void:
	pass
func emit_event(kind: String, world: Vector2, _label: String = "") -> void:
	if room != null: room.record_feedback(kind, world, source_id)

func emit_combat(kind: String,world: Vector2,weapon: String) -> void:
	if room!=null:room.record_feedback(kind,world,source_id,0,PaperCombatAudio.cue(kind,weapon))
func emit_audio(cue: String,world: Vector2) -> void:
	if room!=null and PaperCombatAudio.valid(cue):room.record_feedback("voice",world,source_id,0,cue)

func record_damage(at: Vector2, amount: float) -> void:
	if room == null or amount <= 0: return
	# Damage follows its impact synchronously. Enrich that same numbered event,
	# so clients receive one sound/burst and the actual loss, never two impacts.
	for i in range(room.combat_events.size()-1,maxi(-1,room.combat_events.size()-5),-1):
		var event: Dictionary = room.combat_events[i]
		if event.kind in ["hit", "break"] and event.source == source_id and event.at == room.event_clock and event.position.is_equal_approx(at) and event.amount == 0:
			event.amount = amount
			return
	room.record_feedback("hit", at, source_id, amount)
