extends Node2D

const Brush := preload("res://scripts/architecture/scenery_brush.gd")
const EastInk := preload("res://scripts/medieval_east_ink.gd")
const Life := preload("res://scripts/ink_life_form.gd")
var paths := []
var layout := {}
var mesh: ArrayMesh
var form
var vista_size := Vector2.ZERO
var vista_strokes: Array = []
var bounds := Rect2()
var highlight := -1
var centre := Vector2.ZERO
var PIXELS_PER_UNIT := 60.0

func world_to_screen(at: Vector2) -> Vector2:
	return centre+at*Vector2(PIXELS_PER_UNIT,-PIXELS_PER_UNIT)

func set_sheet(sheet: Dictionary, focus := -1) -> void:
	paths=[]
	layout={}
	mesh=null
	form=null
	highlight=focus
	var recipe: Dictionary = sheet.get("recipe",{})
	vista_size=Vector2.ZERO
	vista_strokes.clear()
	if sheet.get("entry",{}).get("format")=="distant":
		vista_size=Vector2(recipe.size[0],recipe.size[1])
		vista_strokes=recipe.strokes.duplicate()
		queue_redraw()
		return
	var source: Array = recipe.get("strokes",[]).duplicate()
	if recipe.has("design") and not recipe.design.is_empty():
		form=Life.new(recipe.design)
		bounds=form.body_bounds
		if not bounds.has_area():
			for line in form.strokes:
				for point in line.points:bounds=bounds.expand(point)
	var segments: Array=recipe.get("segments",[])
	if recipe.has("segment"):segments=[recipe.segment]
	for segment: Dictionary in segments:
		var baked:=EastInk._drawing(segment)
		source.append({"points":baked.contour,"brush":"bold"})
		for i in baked.marks.size():
			source.append({"points":baked.marks[i],"brush":baked.weights[i] if i<baked.weights.size() else "fine"})
	if recipe.has("record") or recipe.has("records"):
		var records: Array=recipe.get("records",[])
		if recipe.has("record"): records=[recipe.record]
		layout={"supports":[]}
		for record: Dictionary in records:
			var points: Array = record.points.duplicate()
			var closed: bool = record.mode in ["water","rock","carve","backdrop"]
			if closed and points.size()>2 and points[0]!=points[-1]:points.append(points[0])
			var line_brush: String=record.get("brush","fine") if record.mode=="scenery" else "bold"
			source.append({"points":points,"brush":"wash" if closed else line_brush,"pigment":record.get("pigment","indigo" if record.mode=="water" else "inherit")})
			if record.anchor.kind!="free":layout.supports.append(record.anchor.at)
	for stroke in source:
		var points: Array = []
		for p in stroke.points: points.append(p if p is Vector2 else Vector2(p[0],p[1]))
		var brush: String = stroke.get("brush","fine")
		if sheet.get("entry",{}).get("format") == "reference":
			points = Brush.reference_points(points,brush)
		var path := {"points":points,"brush":brush,"pigment":stroke.get("pigment","inherit")}
		if stroke.has("ink_treatment"): path.ink_treatment = stroke.ink_treatment
		paths.append(path)
	if not paths.is_empty():
		var area := ShapeMatcher.bounds(paths)
		if not area.is_empty(): bounds=Rect2(area.min_x,area.min_y,area.width,area.height)
		mesh=Brush.mesh_for(paths,Color("343035") if recipe.get("style","ink")=="ink" else Color("627781"))
		layout=recipe.get("layout",layout)
	queue_redraw()

func _draw() -> void:
	var area: Vector2 = get_parent().size
	draw_rect(Rect2(Vector2.ZERO,area),Color("f7f1df"))
	if vista_size.x>0 and vista_size.y>0:
		var factor := minf((area.x-30)/vista_size.x,(area.y-20)/vista_size.y)
		if factor>0:
			var size_on_page := vista_size*factor
			var rect := Rect2((area-size_on_page)*.5,size_on_page)
			preload("res://scripts/distant_sheet.gd").preview(self,rect,vista_strokes,highlight)
		return
	if form!=null:
		var box: Rect2=bounds
		PIXELS_PER_UNIT=minf((area.x-24)/maxf(.2,box.size.x),(area.y-18)/maxf(.2,box.size.y))
		centre=area*.5-(box.get_center()-Vector2(0,form.foot_offset))*Vector2(PIXELS_PER_UNIT,-PIXELS_PER_UNIT)
		form.paint(self,self,Vector2.ZERO,0.0,1,"",0.0,"rest",0.0,INF)
		return
	if mesh==null or mesh.get_surface_count()==0: return
	PIXELS_PER_UNIT=minf((area.x-30)/maxf(.15,bounds.size.x),(area.y-20)/maxf(.15,bounds.size.y))
	centre=area*.5-bounds.get_center()*Vector2(PIXELS_PER_UNIT,-PIXELS_PER_UNIT)
	draw_mesh(mesh,null,Transform2D(Vector2(PIXELS_PER_UNIT,0),Vector2(0,-PIXELS_PER_UNIT),centre))
	if highlight>=0 and highlight<paths.size():
		var line:=PackedVector2Array()
		for pt in paths[highlight].points:line.append(world_to_screen(pt))
		if line.size()>1:draw_polyline(line,Color(.15,.44,.5,.65),1.5,true)
	for p in layout.get("supports",[]):draw_circle(world_to_screen(Vector2(p[0],p[1])),3,Color("855f42"))
	for p in layout.get("access",[]):draw_arc(world_to_screen(Vector2(p[0],p[1])),5,0,TAU,20,Color("527e87"),1.4,true)
