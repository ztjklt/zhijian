class_name PaperCreationFeedback
extends Node2D
## Screen-space presentation only. Never changes time scale, physics or input.

const MAX_EVENTS := 24
const MAX_VISIBLE_IMPACTS := 6
const PALETTE := [Color("72cce0"), Color("9b87ed"), Color("ecc66b"), Color("e89bc4"), Color("91d5bb")]
const IMPACT_INK := Color("171419")
const IMPACT_RED := Color("b52335")
const IMPACT_DARK_RED := Color("641b2a")
const DURATIONS := {"create": 1.45, "stroke": 0.34, "grip": 0.42, "swing": 0.36, "hit": 0.48, "break": 0.80, "hurt": 0.45, "clash": 0.48, "draw_bow": 0.42, "shoot": 0.24, "voice": 2.0}
const CUES := ["create", "stroke", "grip", "swing", "hit", "break", "hurt", "clash", "draw_bow", "shoot"]

var game = null
var events: Array[Dictionary] = []
var audio_enabled := true
var sounds: Dictionary = {}
var sound_banks: Dictionary = {}
var last_sound: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var audio_serial := 0
var aura: ColorRect
var aura_material: ShaderMaterial
var title_font: SystemFont
var screen_offset := Vector2.ZERO

func _ready() -> void:
	aura = ColorRect.new()
	aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aura.z_index = -1
	aura_material = ShaderMaterial.new()
	aura_material.shader = preload("res://scripts/creation_aura.gdshader")
	aura.material = aura_material
	aura.visible = false
	add_child(aura)
	title_font = SystemFont.new()
	title_font.font_names = PackedStringArray(["Georgia", "Times New Roman"])
	for cue in CUES:
		sounds[cue] = load("res://assets/audio/feedback/%s.wav" % cue)
		sound_banks[cue] = [sounds[cue]]
		if cue in ["hit", "hurt", "break"]:
			for variant in [2, 3]:
				sound_banks[cue].append(load("res://assets/audio/feedback/%s_%d.wav" % [cue, variant]))
	for key in PaperCombatAudio.KEYS:
		sound_banks[key]=[]
		for variant in range(1,4):sound_banks[key].append(load("res://assets/audio/combat/%s_%d.wav"%[key,variant]))
	for i in range(10):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)

func emit_event(kind: String, world: Vector2, label: String = "") -> void:
	_emit(kind,world,label,kind)

func emit_combat(kind: String,world: Vector2,weapon: String) -> void:
	var cue:=PaperCombatAudio.cue(kind,weapon)
	_emit(kind,world,"",cue if cue!="" else kind)

func emit_audio(cue: String,world: Vector2) -> void:
	if PaperCombatAudio.valid(cue):_emit("voice",world,"",cue)

func emit_remote(kind: String,world: Vector2,cue: String) -> void:
	_emit(kind,world,"",cue if PaperCombatAudio.valid(cue) else kind)

func _emit(kind: String, world: Vector2,label: String,cue: String) -> void:
	if not DURATIONS.has(kind): return
	# Keep one legible creation headline and a bounded number of small accents.
	if kind == "create":
		events = events.filter(func(e: Dictionary) -> bool: return e.kind != "create")
	if events.size() >= MAX_EVENTS: events.pop_front()
	var direction: Vector2 = game.combat.swing_direction if game != null and game.combat != null else Vector2.RIGHT
	if kind in ["shoot","draw_bow"] and game != null and game.combat != null: direction=game.combat.bow_direction
	events.append({"kind": kind, "world": world, "age": 0.0, "duration": DURATIONS[kind], "label": label, "direction": direction, "audio": cue})
	_play_cue(cue,world)
	if kind=="break" and cue!="break":_play_cue("break",world)
	queue_redraw()

func _play_cue(kind: String,world: Vector2 = Vector2.INF) -> void:
	if not audio_enabled or DisplayServer.get_name() == "headless" or not sound_banks.has(kind): return
	var distance:=0.0
	if world.is_finite() and game!=null and game.player!=null:distance=game.player.position.distance_to(world)
	if distance>=24:return
	var bank: Array = sound_banks[kind]
	if bank.is_empty():return
	var index := 0
	if bank.size() > 1:
		index = randi_range(0, bank.size() - 2)
		if index >= int(last_sound.get(kind, -1)): index += 1
	var priority:=3 if kind=="create" or kind.begins_with("death_") else 2 if kind.ends_with("_hit") or kind in ["hit","hurt","break","clash"] else 0 if kind in ["stroke","grip"] else 1
	var chosen:AudioStreamPlayer=null
	for voice in voices:
		if not voice.playing:
			chosen=voice
			break
	if chosen==null:
		for voice in voices:
			if voice.get_meta("priority",0)>priority or (voice.playing and voice.stream==sounds.create):continue
			if chosen==null or voice.get_meta("priority",0)<chosen.get_meta("priority",0) or (voice.get_meta("priority",0)==chosen.get_meta("priority",0) and voice.get_meta("serial",0)<chosen.get_meta("serial",0)):chosen=voice
	if chosen==null:return
	last_sound[kind] = index
	chosen.stop()
	chosen.stream=bank[index]
	var gain:float=-9 if kind=="create" else -10 if kind.begins_with("death_") else -8 if priority==2 else -18 if priority==0 else -12
	if kind=="firearm_shoot":gain=-9
	chosen.volume_db=gain+randf_range(-.65,.65)+linear_to_db(maxf(.001,pow(1-distance/24,1.6)))
	chosen.pitch_scale=randf_range(.97,1.03)
	audio_serial+=1
	chosen.set_meta("priority",priority);chosen.set_meta("serial",audio_serial)
	chosen.play()

func _process(delta: float) -> void:
	step(delta)

func step(delta: float) -> void:
	for event in events: event.age += delta
	events = events.filter(func(e: Dictionary) -> bool: return e.age < e.duration)
	screen_offset = Vector2.ZERO
	for event in events:
		var strength: float = {"hit": 4.5, "hurt": 6.0, "break": 7.5, "clash": 8.0, "shoot": 1.8}.get(event.kind, 0.0)
		if strength <= 0 or event.age >= 0.20: continue
		var proximity: float = clampf(1.0 - game.player.position.distance_to(event.world) / 12.0, 0, 1)
		var decay: float = pow(1.0 - event.age / 0.20, 2.0) * strength * proximity
		screen_offset += Vector2(sin(event.age * 160 + 0.8), cos(event.age * 137)) * decay
	screen_offset = screen_offset.limit_length(9.0)
	if aura != null:
		aura.visible = false
		for event in events:
			if event.kind != "create" or event.age >= 1.2: continue
			aura.visible = true
			aura.size = get_viewport_rect().size
			aura_material.set_shader_parameter("canvas_size", aura.size)
			aura_material.set_shader_parameter("origin", game.world_to_screen(event.world))
			aura_material.set_shader_parameter("age", event.age)
	queue_redraw()

func impact_flash_strength() -> float:
	if game==null or game.player==null:return 0.0
	var strength:=0.0
	for event in events:
		if event.kind not in ["hit","break","hurt"] or event.age>=.10:continue
		var proximity:float=clampf(1-game.player.position.distance_to(event.world)/12,0,1)
		var value:float=(.11 if event.kind=="break" else .075)*pow(1-event.age/.10,2)*proximity
		strength=maxf(strength,value)
	return minf(strength,.12)

func _draw() -> void:
	if game == null: return
	var flash:=impact_flash_strength()
	if flash>0:draw_rect(get_viewport_rect(),Color(1.0,.88,.72,flash))
	# The nib light follows actual ink without spawning particles or audio each frame.
	if game.active_stroke != null and not game.active_stroke.points.is_empty():
		var tip: Vector2 = game.world_to_screen(game.active_stroke.points.back())
		_glow(tip, 12.0, Color("8f8cdc"), 0.22)
		_star(tip, 5.5, Color("fff5cf"), 0.0)
	var remaining_impacts:=0
	for event in events:
		if event.kind in ["hit","break","hurt"]:remaining_impacts+=1
	for event in events:
		var center: Vector2 = game.world_to_screen(event.world)
		var progress: float = event.age / event.duration
		match event.kind:
			"create": _draw_creation(event, center, progress)
			"stroke", "grip": _draw_ink(center, progress, event.kind == "grip")
			"swing": pass # Sound cue only; the held ink supplies the actual visual motion.
			"clash": _draw_clash(center, progress)
			"draw_bow": pass # Actual bow string and nocked arrow show the charge.
			"shoot": _draw_shot(center,progress,event.direction)
			_:
				remaining_impacts-=1
				if remaining_impacts>=MAX_VISIBLE_IMPACTS:continue
				draw_set_transform(center,0,Vector2.ONE*PaperGuiScale.factor(get_viewport_rect().size))
				_draw_impact(event,Vector2.ZERO,progress)
				draw_set_transform(Vector2.ZERO)

func _glow(center: Vector2, radius: float, tint: Color, alpha: float) -> void:
	for i in range(5, 0, -1):
		var color := tint
		color.a = alpha / 5.0
		draw_circle(center, radius * float(i) / 5.0, color)

func _star(center: Vector2, radius: float, color: Color, rotation: float) -> void:
	if radius < 0.35 or color.a < 0.02: return
	# Lines stay stable as a sparkle shrinks below a pixel; concave polygons do not.
	var axis := Vector2.from_angle(rotation) * radius
	var cross_axis := axis.orthogonal()
	var width := clampf(radius * 0.24, 0.7, 1.8)
	draw_line(center - axis, center + axis, color, width, true)
	draw_line(center - cross_axis, center + cross_axis, color, width, true)
	draw_circle(center, maxf(0.4, radius * 0.16), color)

func _draw_creation(event: Dictionary, center: Vector2, progress: float) -> void:
	var fade: float = pow(1.0 - progress, 1.15)
	var opening: float = 1.0 - pow(1.0 - minf(progress * 3.0, 1.0), 3.0)
	_glow(center, 82.0 + progress * 50.0, Color("9d8be3"), fade * 0.65)
	_glow(center, 40.0, Color("fff3c4"), fade)
	# Broken orbital rings and a rising constellation give the ink a birth point.
	for ring in range(3):
		var color: Color = PALETTE[ring]
		color.a = fade * 0.75
		var radius: float = 24.0 + opening * (30.0 + ring * 18.0) + progress * 48.0
		var turn: float = event.age * (0.6 if ring % 2 == 0 else -0.4)
		for arc in range(4):
			var start: float = turn + arc * TAU / 4.0 + ring * 0.25
			draw_arc(center, radius, start, start + 0.95, 20, color, 1.6, true)
	for i in range(46):
		var angle: float = float(i) * 2.399963
		var travel: float = (28.0 + float(i % 9) * 17.0) * opening + progress * 75.0
		var direction := Vector2.from_angle(angle)
		var point := center + direction * travel + Vector2(0, -progress * progress * 70.0)
		var color: Color = PALETTE[i % PALETTE.size()]
		color.a = fade * (0.55 + 0.45 * absf(sin(event.age * 8.0 + i)))
		draw_line(point - direction * (4.0 + 10.0 * fade), point, color, 1.4, true)
		_star(point, (2.5 + float(i % 4)) * fade, color, angle + progress)
	_star(center, 17.0 * fade + 4.0, Color(1, 0.97, 0.83, fade), PI / 4.0)
	_draw_headline(event, progress)

func _draw_headline(event: Dictionary, progress: float) -> void:
	var viewport := get_viewport_rect().size
	var alpha: float = 1.0 - smoothstep(0.52, 1.0, progress)
	var pop: float = sin(minf(progress / 0.16, 1.0) * PI) * 0.10
	var font_size := int(clampf(viewport.x * 0.029, 23.0, 34.0) * (1.0 + pop))
	var center := Vector2(viewport.x * 0.5, maxf(155.0, viewport.y * 0.27) - progress * 15.0)
	if viewport.x < 600 or viewport.y < 500:
		center.y = maxf(center.y, game.toolbar.bottom.position.y + game.toolbar.bottom.size.y + 44.0 - progress * 10.0)
	var word: String = event.label if not event.label.is_empty() else "CREATED!"
	var width := title_font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := center + Vector2(-width * 0.5, 0)
	# Fine ivory outline keeps the modest title readable over bright paper and ink.
	draw_string_outline(title_font, baseline, word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(1, 0.98, 0.89, alpha * 0.9))
	draw_string(title_font, baseline, word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.27, 0.25, 0.44, alpha))
	var caption := "A NEW IDEA COMES TO LIFE"
	var font := ThemeDB.fallback_font
	var caption_width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, center + Vector2(-caption_width * 0.5, 21), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.40, 0.36, 0.48, alpha * 0.85))
	for side in [-1.0, 1.0]:
		var edge := center + Vector2(side * (width * 0.5 + 18), -11)
		_star(edge, 5, Color(0.70, 0.51, 0.24, alpha), 0)
		draw_line(edge + Vector2(side * 11, 0), edge + Vector2(side * 40, 0), Color(0.70, 0.51, 0.24, alpha * 0.5), 1, true)

func _draw_ink(center: Vector2, progress: float, grip: bool) -> void:
	var color := Color("9a80d5") if grip else Color("59bdb9")
	color.a = 1.0 - progress
	draw_arc(center, 5.0 + progress * 23.0, 0, TAU, 32, color, 1.2, true)
	for i in range(5):
		var at := center + Vector2.from_angle(i * TAU / 5.0) * (8.0 + progress * 23.0)
		_star(at, 3.5 * (1.0 - progress), color, progress)

func _draw_shot(center: Vector2, progress: float, direction: Vector2) -> void:
	var axis:=Vector2(direction.x,-direction.y).normalized()
	var fade:=pow(1.0-progress,3)
	# A few tiny directional ink fibres, never an expanding range ring.
	for i in 5:
		var side:=axis.orthogonal()*(i-2)*2.0
		var travel:=progress*(14+i*3)
		var tip:=center+axis*travel+side*(1+progress)
		draw_line(tip-axis*(3+fade*5),tip,Color(IMPACT_INK,fade*.75),1.2,true)

func _draw_clash(center: Vector2, progress: float) -> void:
	var fade := pow(1.0 - progress, 1.8)
	_glow(center, 68 * (1 - progress), Color("ffe3a0"), fade)
	# Sharp crossed core, expanding pressure ring, directional metal splinters.
	for side in [-1.0, 1.0]:
		var axis := Vector2(1, side * 0.85).normalized() * (18 + progress * 32)
		draw_line(center - axis, center + axis, Color(0.24, 0.47, 0.53, fade * 0.5), 7 * fade + 0.5, true)
		draw_line(center - axis, center + axis, Color(1, 0.97, 0.80, fade), 3 * fade + 0.5, true)
	draw_arc(center, 10 + sqrt(progress) * 75, 0, TAU, 44, Color(0.44, 0.77, 0.8, fade * 0.8), 2.5 * fade + 0.3, true)
	for i in range(22):
		var angle := float(i) * 2.399963
		var direction := Vector2.from_angle(angle)
		var point := center + direction * (15 + progress * (70 + float(i % 5) * 20))
		var color := Color(1, 0.76, 0.35, fade) if i % 2 == 0 else Color(0.45, 0.76, 0.85, fade)
		draw_line(point - direction * (10 + 15 * fade), point, color, 1 + 2 * fade, true)
	_star(center, 23 * fade, Color(1, 0.99, 0.90, fade), PI / 4)
	draw_string(ThemeDB.fallback_font, center + Vector2(-24, -39 - progress * 14), "CLASH!", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.27, 0.48, 0.50, fade))

func _draw_impact(event: Dictionary, center: Vector2, progress: float) -> void:
	var broken:bool=event.kind=="break"
	var hurt:bool=event.kind=="hurt"
	var radius:float=135.0 if broken else 86.0
	var fade:=pow(1.0-progress,1.8)
	var opening:=1.0-pow(1.0-progress,4)
	var angle:=Vector2(event.direction.x,-event.direction.y).angle()
	var flash:=pow(1.0-clampf(progress*4,0,1),2)
	# Layered white/gold core with red ink. This burst starts at the confirmed
	# contact and has no attack geometry or owner-centred range representation.
	_glow(center,62.0*flash+10,Color("eaa85e"),flash*.65)
	_glow(center,28.0*flash+3,Color("fff4d1"),flash*.85)
	_star(center,27*flash+3,Color(1,.96,.78,fade),angle+.35)
	_star(center,16*flash,Color(1,1,.96,flash),angle-.45)
	for i in (32 if broken else 22):
		var direction:=Vector2.from_angle(angle+float(i)*2.399963)
		var travel:float=radius*opening*(.32+float(i%5)*.14)
		var point:=center+direction*travel+Vector2(0,progress*progress*42)
		var tint:Color=IMPACT_RED if i%3==0 else IMPACT_INK
		if i%7==0:tint=Color("e0ac5c")
		var width:float=(4.5 if i%2==0 else 2.6)*fade+.3
		var tail:=point-direction*(7+17*fade)
		var normal:=direction.orthogonal()*width*.5
		draw_colored_polygon(PackedVector2Array([tail-normal,tail+normal,point]),Color(tint,fade))
		if i%3==0:_star(point,3.8*fade,Color(1,.88,.55,fade),angle+progress)
		else:draw_circle(point+direction.orthogonal()*4,(1.0+i%3)*fade,Color(IMPACT_DARK_RED,fade*.8))
	# Short angular paper fractures radiate from the actual impact, rather than
	# drawing another broad sweep. They disappear with the particles.
	for i in (9 if broken else 6):
		var axis:=Vector2.from_angle(angle+i*TAU/(9 if broken else 6)+.17)
		var length:float=(26+i%3*11)*opening
		var bend:=axis.orthogonal()*(4+i%3*2)
		var fracture:=PackedVector2Array([center+axis*5,center+axis*length*.4+bend,center+axis*length*.65-bend*.5,center+axis*length])
		draw_polyline(fracture,Color(IMPACT_INK,fade*.8),1.6,true)
		draw_line(fracture[-2],fracture[-1],Color(1,.80,.42,fade*.8),.8,true)
	var slash:=Vector2.from_angle(angle-.65)
	var length:float=(36.0 if broken else 23.0)*(.6+opening*.4)
	draw_line(center-slash*length,center+slash*length,Color(IMPACT_INK,fade),6*fade+.5,true)
	draw_line(center-slash*length*.7+slash.orthogonal()*3,center+slash*length*.85+slash.orthogonal()*3,Color(IMPACT_RED,fade),2.5*fade+.3,true)
	if not hurt:
		var word:="SHATTER!" if broken else "HIT!"
		draw_string_outline(ThemeDB.fallback_font,center+Vector2(-25,-40-progress*24),word,HORIZONTAL_ALIGNMENT_LEFT,-1,18 if broken else 15,3,Color(1,.97,.85,fade))
		draw_string(ThemeDB.fallback_font,center+Vector2(-25,-40-progress*24),word,HORIZONTAL_ALIGNMENT_LEFT,-1,18 if broken else 15,Color(IMPACT_RED if broken else IMPACT_INK,fade))

func _exit_tree() -> void:
	# Stop active tails before audio/resource teardown (including window close).
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	sounds.clear()
	sound_banks.clear()
	last_sound.clear()
