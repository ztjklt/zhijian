class_name PaperExperience
extends Control
## A reviewable entry into the actual sandbox, sharing its map and combat code.

const VERSION := "v0.54 · 携物交互改进"
var game = null
var panel: PanelContainer
var scroll: ScrollContainer
var actions: GridContainer
var chapters: GridContainer
var restore_button: Button
var map_button: Button
var previous_weapon: Dictionary = {}
var previous_bow := false
var trial_weapon: Dictionary = {}
var trial_active := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = PaperTheme.create_menu()
	var shade := ColorRect.new()
	shade.color = Color(0.12, 0.18, 0.18, 0.32)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = PanelContainer.new()
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_label(column, "纸间  ·  " + VERSION + " 本版体验", 23)
	_label(column, "在同一个世界里探索地图、画出造物、跳跃攀爬和交手。", 14, PaperTheme.MENU_MUTED)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)
	_section(content, "墨线边境 · 与纸上山野融合", "穿过丘陵、村庄、集市与高地城堡，继续探索风车麦田、磨坊渡口、古修道院和边境营地。房屋下方可通行，树冠、屋顶、窗沿与城堡檐口可以逐层跳上，双击S可下穿当前落脚面。青草可斩断，建筑受击会缺失局部图片。山体、河床与桥面按同一几何显示和碰撞，水体可进入；山水由实际地形构成。村民、车夫、将军、骑士、国王和女王沿用主角的火柴人身体与骨骼，帽冠贴头，眼神温和；落脚与马车车轮适应坡面。宏伟城堡从统一GPT概念图无缝拆成32个可破坏部件，可以登上城墙，再画大砖块砸坏主堡；房屋和城堡也可被刀剑、箭矢破坏，中世纪作品仍独立保存。")
	actions = GridContainer.new()
	content.add_child(actions)
	_button(actions, "武器试打 · 方案对照", func():game.open_weapon_lab())
	_button(actions, "近战 · 试用短剑", try_sword)
	_button(actions, "弓箭 · 切换短弓", try_bow)
	map_button = _button(actions, "地图 · 六章全景", show_map)
	_button(actions, "开启 / 关闭练习靶", func():
		game.combat.set_training(not game.combat.training)
		close()
		game.message("练习靶 / 墨弹已开启 · 画武器打靶，画建筑挡弹" if game.combat.training else "练习已关闭"))
	_button(actions, "开启 / 关闭土著", func():
		game.combat.set_natives(not game.combat.natives_enabled)
		close()
		game.message("纸间土著已进入地图 · 接近后可以试打" if game.combat.natives_enabled else "土著已离场，可以安静创作"))
	restore_button = _button(actions, "恢复试用前的武器", restore_weapon)
	_button(actions, "返回地图选择", func(): game.return_to_map_select())
	_button(actions, "选图 · 课本文字", func(): game.change_map("knowledge-v1"); close())
	_button(actions, "选图 · 山野中世纪", func(): game.change_map("medieval-v1"); close())
	_button(actions,"地图事件 · 磨坊试桥",func():
		if game.medieval_world == null:
			game.message("请先进入墨线边境，再从地图面板前往磨坊试桥")
			return
		close()
		game.map_controls.visit_trial())
	_section(content,"武器试打 · 画完再试","作品菜单或武器工具里打开试打，布置自己的近／中／远试靶。关面板后正常攻击，真实命中才记录伤害；可保留当前对照，再复制完整笔迹回画布补画、重选握点和类型。原装备与图纸保留，记录仅本次会话，联网由服务器计算，双方各自试靶。")
	_section(content,"结构连接 · 固定与转轴","先分别画出部件，按4进入移动工具，再点操作按钮切换固定连接、转轴或解除。依次点两件相邻部件的接缝，固定连接一起受力，转轴允许旋转；绿色点表示连接。部件被砍掉锚点或拆除时连接断开，重试试桥保留搭建。连接跟随作品保存，联网可连接自己的或作者已开放协作的部件；图纸仍收藏单件。")
	_section(content,"双人共同搭建","作品菜单或4移动中的双人协作：逐件允许朋友搬动／连接，组合两人画的部件。拆除仍归作者，朋友不能抢占编辑锁；可随时撤回，任一人断线会清空许可，完成的结构保留并可保存。")
	_section(content,"可选事件 · 磨坊试桥","先布置两端试桥台，用自己的笔迹画桥、搭斜坡或组合支撑，再投放小货车。货物靠真实碰撞通过，落到右台并稳定才算送达；掉落可重试，搭建都保留。地图面板可前往，联机与朋友共享事件、沿路走过去。")
	_section(content, "01  选地图，向天空探索", "课本文字世界保留六章诗文、公式、图形与天空平台；山野已融合进中世纪地图，沿真实山坡、河谷和城堡探索。地图分别保留搭建；旧版山野作品可从开始界面的继续入口恢复。课本中 M 看全景，Home 回安全地面；也可以直接选一处：")
	chapters = GridContainer.new()
	content.add_child(chapters)
	for i in range(6):
		var index := i
		_button(chapters, ["数学", "语文", "历史", "物理", "化学", "函数"][i], func(): visit_chapter(index))
	_section(content, "02  移动与穿越", "A / D 或方向键移动；W / 空格起跳，松开再按二连跳。朝墙按住方向自动攀爬，空格跳离；梯旁 W / S 攀梯。双击 S 下穿脚下文字 / 平台，底层地面不可穿透。走、跑、跳、落地、攀爬与绘画保持原角色动作。")
	_section(content, "03  绘画、移动／拆除与图纸", "1 自由造物，2 建筑，3 武器，4 移动／拆除，5 塑形，6 图纸。多笔补画后再按当前数字确认，松手不生成。建筑碰到文字地形会寻找附近安全空位，整件移出去生成。4 可以按住自己生成的物件拖动，选中后拆除／Delete；6 收藏已生成的作品，选图纸即可再次放置或装备，绑定 Shift+数字可快速复用，不需要重画。5 的 44 种塑形继续保留。")
	_section(content, "04  四式近战、弓箭与交击", "装备武器后连续按 R / 攻击，依次下劈 → 反手上挑 → 前刺 → 重斩。收势时可提前输入下一击，停手就回防；无草稿时也可右键攻击。Q 切弓，鼠标瞄准、R 拉弓放箭。真实剑模相碰、剑刃挡箭、敌我箭相碰都会交击：碎光、金属声、镜头震动和短暂回弹。")
	_section(content, "05  灰色纸间土著", "土著复用原主角模型，只换灰色；附近 6 名持剑 / 持弓游荡，接近后追击出招。受击有击退、硬直、倒地和恢复。N 或上方按钮可开关；你自己的手绘剑也能与它们试打。")
	_section(content, "06  创造反馈、画质与保存", "造物成功出现 CREATED! / FORGED! / SHAPED!，配合虹彩、星屑和音效；预览或失败不误播成功反馈。世界开启 4× 2D 抗锯齿、角色 Mipmap 过滤与轻锐化。6 / B 管理图纸，Shift + 1–6 取快捷图纸；作品菜单手动保存 / 读取，体验按钮不会自动保存。")
	_section(content, "当前边界", "单人体验保留。多人入口已接入纸间 Railway 云服务器；中世纪与课本地图通过公网双客户端测试，服务重启后可恢复存档。不同网络的两台电脑实玩与延迟手感仍待验收。核心工程已接入五类手绘武器与类型轮盘；剑、锤、长枪已有可区分的待机持握姿态，切回空手或绘画会恢复基础动画；4 选中部件后按 G 可拿起、携带移动，再按 G 放下。公网版以实际发布版本为准。")
	var footer := HBoxContainer.new()
	column.add_child(footer)
	var play := _button(footer, "开始 / 继续游玩", close)
	PaperTheme.primary(play)
	_button(footer, "重看绘画引导", func():
		close()
		game.onboarding.restart(not game.objects.is_empty() or not game.equipped_weapon.is_empty()))
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false

func _label(parent: Node, text: String, font_size: int, color: Color = PaperTheme.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", PaperTheme.menu_font_size(font_size))
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _section(parent: Node, title: String, body: String) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	parent.add_child(column)
	_label(column, title, 18, PaperTheme.TEAL)
	_label(column, body, 14)

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", PaperTheme.menu_font_size(14))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _layout() -> void:
	var viewport := PaperGuiScale.apply(self)
	var desired := Vector2(minf(920, viewport.x - 24), minf(640, viewport.y - 24))
	panel.position = (viewport - desired) * 0.5
	panel.size = desired
	actions.columns = 1 if viewport.x < 500 else 3
	chapters.columns = 3 if viewport.x < 500 else 6

func _process(_delta: float) -> void:
	# CJK wrapping and grid columns settle after the first container layout.
	# Godot grows a panel for that initial minimum but does not shrink it back.
	if visible: _layout()

func open() -> void:
	if game.cooperation_open():game.cooperation_panel.close()
	if game.bag_open: game.toggle_bag()
	game.retain_active_stroke()
	game.cancel_pointer()
	game.touch_controls.reset()
	game.combat.cancel_draw()
	game.wall_climb.reset(game.player)
	game.onboarding.visible = false
	restore_button.disabled = not trial_active
	map_button.disabled = game.knowledge_world == null
	for button in chapters.get_children(): button.disabled = game.knowledge_world == null
	if game.knowledge_world != null:
		var names: Array = game.knowledge_world.navigation_names()
		for i in chapters.get_child_count(): chapters.get_child(i).text = names[i]
	visible = true
	_layout()

func close() -> void:
	visible = false
	game.touch_controls.reset()

func _release_attack() -> void:
	game.cancel_weapon_grip(false)
	game.combat.cancel_draw()
	game.combat.swing = 0
	game.combat.impact_hold = 0
	game.combat.cooldown = 0
	game.combat.player_paths.clear()
	game.combat.previous_player_paths.clear()

func try_sword() -> void:
	if not trial_active or game.equipped_weapon != trial_weapon:
		previous_weapon = game.equipped_weapon.duplicate(true)
		previous_bow = game.combat.bow_equipped
	trial_weapon = PaperWeaponGrip.practice_sword()
	trial_active = true
	_release_attack()
	game.equipped_weapon = trial_weapon.duplicate(true)
	game.combat.bow_equipped = false
	close()
	game.message("试用短剑 · 连按 R 接四式，Q 切弓 · 本版体验可恢复原武器")

func restore_weapon() -> void:
	if trial_active and game.equipped_weapon == trial_weapon:
		_release_attack()
		game.equipped_weapon = previous_weapon.duplicate(true)
		game.combat.bow_equipped = previous_bow
	trial_active = false
	previous_weapon.clear()
	close()
	game.message("已结束短剑试用 · 继续使用自己的装备")

func try_bow() -> void:
	_release_attack()
	game.combat.bow_equipped = true
	close()
	game.message("短弓已就绪 · 鼠标瞄准，R 拉弓放箭，Q 切回近战")

func visit_chapter(index: int) -> void:
	if game.knowledge_world == null: return
	close()
	game.knowledge_world.visit(index)

func show_map() -> void:
	if game.knowledge_world == null: return
	close()
	if not game.knowledge_world.overview: game.knowledge_world.toggle_overview()
