extends PanelContainer
## Draw the stored paths at reading scale using the same mesh as the placed scenery.
const SceneryBrush := preload("res://scripts/architecture/scenery_brush.gd")
var title_label := Label.new()
var sheet := Control.new()
var mesh: ArrayMesh
var bounds := Rect2()
var layout := {}
var font: Font

func _ready() -> void:
	theme = PaperTheme.create()
	font = theme.default_font
	add_theme_stylebox_override("panel",PaperTheme.panel())
	var column := VBoxContainer.new()
	add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	var close_button := Button.new()
	close_button.text = "收起"
	close_button.pressed.connect(hide)
	row.add_child(close_button)
	column.add_child(sheet)
	sheet.draw.connect(_draw_sheet)
	hide()

func show_entry(entry: Dictionary) -> void:
	var paths: Array = entry.paths
	if paths.is_empty(): return
	var frame := ShapeMatcher.bounds(paths)
	bounds = Rect2(frame.min_x,frame.min_y,frame.max_x-frame.min_x,frame.max_y-frame.min_y)
	mesh = SceneryBrush.mesh_for(paths,Color("343035") if entry.ink_style=="ink" else Color("627781"))
	layout = entry.layout
	title_label.text = "图 %d · %s　%d 笔" % [entry.id,entry.name,paths.size()]
	if entry.has("parent_id"): title_label.text += "　改自图 %d" % int(entry.parent_id)
	var space := get_viewport_rect().size
	sheet.custom_minimum_size = Vector2(minf(620,space.x*.76),minf(325,space.y*.56))
	reset_size()
	position = (space-size)*.5
	show()
	move_to_front()
	sheet.queue_redraw()

func _draw_sheet() -> void:
	if mesh == null: return
	var zoom := minf((sheet.size.x-52)/maxf(bounds.size.x,.1),(sheet.size.y-72)/maxf(bounds.size.y,.1))
	var ink_scale := Vector2(zoom,-zoom)
	var origin := (sheet.size-Vector2(0,22))*.5-bounds.get_center()*ink_scale
	sheet.draw_mesh(mesh,null,Transform2D(Vector2(zoom,0),Vector2(0,-zoom),origin))
	for p in layout.get("supports",[]):
		sheet.draw_circle(origin+Vector2(p[0],p[1])*ink_scale,2.8,Color("7e5d49"),true,-1,true)
	for p in layout.get("access",[]):
		sheet.draw_arc(origin+Vector2(p[0],p[1])*ink_scale,6,0,TAU,24,Color("497280"),1.8,true)
	sheet.draw_string(font,Vector2(0,sheet.size.y-6),"● 柱脚　○ 使用位",HORIZONTAL_ALIGNMENT_CENTER,sheet.size.x,14,Color("665c52"))
