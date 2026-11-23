extends RefCounted
## Dry pigment belongs to the surviving soil. Positions are in metres until draw.
const TYPES := ["soil","stone","bank","paper"]
const LEVELS := [0.0,.16,.48,.92,1.53,2.05]
const TONES := {
	"soil":[Color("#ddc5a0"),Color("#dfc8aa"),Color("#e8d8ba"),Color("#eee3cb"),Color("#f1e7d1"),Color("#f6edd9")],
	"stone":[Color("#cfbfa5"),Color("#cabbab"),Color("#d5cfc2"),Color("#e1dace"),Color("#e9e2d5"),Color("#f2ebdc")],
	"bank":[Color("#dbcca7"),Color("#e4d5b3"),Color("#e6dabb"),Color("#ede2ca"),Color("#f1ead8"),Color("#f4efdf")]
}
const OPACITY := [.91,.93,.82,.58,.21,0.0]
var baked:Dictionary={}

func clear() -> void:
	baked.clear()

func draw(canvas:Node2D,game,terrain,left:float,right:float) -> void:
	var ink=terrain.east_ink
	var tip:Vector2=terrain.profile[-1]
	if right<=ink.ORIGINAL_EDGE.x or left>=tip.x:return
	for i in range(maxi(0,ink._drawing_at(left)),ink.drawings.size()+1):
		var pending:bool=i==ink.drawings.size()
		if pending and ink.preview.is_empty():break
		var drawing:Dictionary=ink.preview if pending else ink.drawings[i]
		var path:PackedVector2Array=drawing.contour
		if path[0].x>right:break
		var end_x:=minf(tip.x,path[-1].x)
		if end_x<=maxf(left,path[0].x) or drawing.material=="paper":continue
		var previous:String=ink.drawings[i-1].material if i>0 else "paper"
		var next:="paper"
		if i+1<ink.drawings.size():
			next=ink.drawings[i+1].material
		elif not pending and tip.x>end_x:
			next=ink.preview.get("material","paper")
		var key:=[end_x,previous,next]
		if not baked.has(i) or baked[i].key!=key:
			if baked.size()>=48 and not baked.has(i):baked.erase(baked.keys()[0])
			baked[i]={"key":key,"mesh":_section(terrain,path[0].x,end_x,drawing.material,previous,next)}
		var mesh:ArrayMesh=baked[i].mesh
		if mesh==null:continue
		canvas.draw_set_transform(game.world_to_screen(Vector2(path[0].x,0)),0,Vector2(1,-1)*game.PIXELS_PER_UNIT)
		canvas.draw_mesh(mesh,null)
	canvas.draw_set_transform(Vector2.ZERO)

func _section(terrain,start:float,end:float,material:String,previous:String,next:String) -> ArrayMesh:
	var vertices:=PackedVector2Array()
	var colors:=PackedColorArray()
	var indices:=PackedInt32Array()
	var profile:PackedVector2Array=terrain.profile
	var shores:Array=[]
	var repairs:Array=[]
	if terrain.paper_space!=null:
		var box:=Rect2(Vector2(start-1,terrain.BOTTOM),Vector2(end-start+2, terrain.EastInk.LIMITS.max_y-terrain.BOTTOM+1))
		for entry in terrain.paper_space.nearby(box):
			if entry.record.get("ink_treatment") == "soil_repair":
				repairs.append(entry)
			if entry.record.mode!="water":continue
			var origin:Vector2=terrain.paper_space.origin_for(entry.frame)
			for rim in entry.lines:shores.append([origin+rim[0],origin+rim[1]])
	for i in range(terrain.profile_span(profile,start),terrain.profile_span(profile,end)+1):
		var a:=profile[i-1]
		var b:=profile[i]
		var left:=maxf(a.x,start)
		var right:=minf(b.x,end)
		if right<=left:continue
		var cut:Dictionary={}
		var fixture_index:int=i-terrain._base_profile_size
		if terrain.paper_space!=null and not terrain.paper_space.modified_legacy.is_empty() and is_instance_valid(terrain._east_soil) and fixture_index>=0 and fixture_index<terrain._east_soil.get_child_count():
			var fixture=terrain._east_soil.get_child(fixture_index)
			cut=terrain.paper_space.modified_legacy.get(fixture.get_instance_id(),{})
		var cut_fragments:Array=[]
		for part:PackedVector2Array in cut.get("parts",[]):
			cut_fragments.append(Transform2D(0,Vector2(-start,0))*part)
		if not cut.is_empty() and not repairs.is_empty():
			var repaired_parts := []
			for entry:Dictionary in repairs:
				if entry.box.end.x<=left or entry.box.position.x>=right:continue
				var shift := Transform2D(0,terrain.paper_space.origin_for(entry.frame)-Vector2(start,0))
				for part:PackedVector2Array in entry.parts: repaired_parts.append(shift*part)
			if not repaired_parts.is_empty():
				var original := [terrain.paper_space.clean_part(Transform2D(0,Vector2(-start,0))*cut.source)]
				var holes: Array = terrain.paper_space.subtract(original,cut_fragments)
				var remaining: Array = terrain.paper_space.subtract(holes,repaired_parts)
				cut_fragments=terrain.paper_space.subtract(original,remaining)
		var slices:=ceili((right-left)/.26)
		var left_column:=_column(terrain,left,start,end,material,previous,next,shores)
		for slice in slices:
			var right_column:=_column(terrain,lerpf(left,right,float(slice+1)/slices),start,end,material,previous,next,shores)
			for j in LEVELS.size()-1:
				var quad:=PackedVector2Array([left_column.points[j],right_column.points[j],right_column.points[j+1],left_column.points[j+1]])
				var pieces:Array=[quad]
				if not cut.is_empty():
					pieces=[]
					for local:PackedVector2Array in cut_fragments:
						pieces.append_array(Geometry2D.intersect_polygons(quad,local))
				for piece:PackedVector2Array in pieces:
					var first:=vertices.size()
					for p in piece:
						var along:=clampf(inverse_lerp(quad[0].x,quad[1].x,p.x),0,1)
						var high:=lerpf(quad[0].y,quad[1].y,along)
						var low:=lerpf(quad[3].y,quad[2].y,along)
						var down:=clampf((high-p.y)/maxf(.00001,high-low),0,1)
						var left_color:Color=left_column.colors[j].lerp(left_column.colors[j+1],down)
						var right_color:Color=right_column.colors[j].lerp(right_column.colors[j+1],down)
						vertices.append(p)
						colors.append(left_color.lerp(right_color,along))
					for k in range(2,piece.size()):
						indices.append(first)
						indices.append(first+k-1)
						indices.append(first+k)
			left_column=right_column
	if indices.is_empty():return null
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _column(terrain,x:float,start:float,end:float,material:String,previous:String,next:String,shores:Array) -> Dictionary:
	var y:float=terrain.surface_height(x)
	var slope:float=absf(terrain.surface_height(x+.36)-terrain.surface_height(x-.36))/.72
	var shoulder:=smoothstep(.045,.17,slope)
	var paper:=(1.0-shoulder)*smoothstep(.04,.90,sin(x*1.41+.65*sin(.44*x)))
	var broad:=.81+.16*sin(x*.83)+.08*sin(x*2.14+.8)+.37*shoulder-.45*paper
	var strength:=1.0-.72*paper
	var shore:=1.0
	for line in shores:
		var rim:Vector2=Geometry2D.get_closest_point_to_segment(Vector2(x,y),line[0],line[1])
		shore=minf(shore,smoothstep(.12,.92,rim.distance_to(Vector2(x,y))))
	broad*=lerpf(.43,1.,shore)
	strength*=lerpf(.26,1.,shore)
	if previous=="paper":strength*=smoothstep(0,.85,x-start)
	if next=="paper":strength*=smoothstep(0,.80,end-x)
	var palette:Array=TONES[material]
	var points:=PackedVector2Array()
	var colors:=PackedColorArray()
	var rock:=clampf(1.0-absf(fposmod(x*.51+.14*sin(x*.83),1.0)-.48)*3.8,0,1)
	for band in LEVELS.size():
		var deposit:=broad+.055*sin(x*1.37+band*.74)
		var color:Color=palette[band]
		if material=="soil" and band<3:color=color.lerp(Color("#cfa77a"),.18*shoulder)
		if material=="bank":deposit*=.73
		if material=="stone" and band in [1,2]:
			deposit+=rock*(.48 if band==1 else -.20)
			color=color.lerp(Color("#849399"),rock*(.46 if band==1 else .17))
		if previous!=material and previous!="paper":
			color=TONES[previous][band].lerp(color,smoothstep(0,.80,x-start))
		color.a=OPACITY[band]*strength
		colors.append(color)
		points.append(Vector2(x-start,maxf(terrain.BOTTOM,y-float(LEVELS[band])*deposit)))
	return {"points":points,"colors":colors}

