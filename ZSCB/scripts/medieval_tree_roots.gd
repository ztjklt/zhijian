class_name MedievalTreeRoots
extends RefCounted
## Fit only the root flare to soil. The rest of the original tree stays upright.
## Source alpha is measured once; the fitted mesh is rebuilt only on placement
## or damage, never while drawing a frame.
static var _source_feet: Dictionary = {}
var size := Vector2.ONE
var band := 0.0
var feet := PackedFloat32Array()
var soil := PackedFloat32Array()
var columns: Array[int] = []

func _init(entity, terrain) -> void:
	size = entity.size
	var source: Rect2 = entity.source_rect
	var key: String = entity.texture.resource_path+str(source)
	if not _source_feet.has(key):
		_source_feet[key] = _measure_feet(entity.texture.get_image(),source)
	var normalized: PackedFloat32Array = _source_feet[key]
	band = size.y*.24
	for column in normalized.size():
		var x := (float(column)/(normalized.size()-1)-.5)*size.x
		feet.append(normalized[column]*size.y)
		var ground: float = terrain.surface_height(entity.position.x+x)-entity.position.y
		soil.append(ground)
		# Keep the mapping monotone even on a crest or for a scaled-up tree.
		band = maxf(band,ground+.15)
	_simplify_columns()

func _simplify_columns() -> void:
	# Keep full-resolution measurements for fit/unfit. Mesh cells need only
	# contour bends: at most 2mm error in either root ink or actual soil.
	var pending: Array[Vector2i] = [Vector2i(0,feet.size()-1)]
	var keep := {0:true,feet.size()-1:true}
	while not pending.is_empty():
		var span: Vector2i = pending.pop_back()
		var split := -1
		var worst := .002
		for i in range(span.x+1,span.y):
			var t := float(i-span.x)/(span.y-span.x)
			var error := maxf(absf(feet[i]-lerpf(feet[span.x],feet[span.y],t)),absf(soil[i]-lerpf(soil[span.x],soil[span.y],t)))
			if error>worst: worst=error;split=i
		if split>=0:
			keep[split] = true
			pending.append(Vector2i(span.x,split))
			pending.append(Vector2i(split,span.y))
	# A tall strip interpolates affinely on the GPU, whereas fit/unfit varies
	# with both x and y. Limit its width as well as its contact-profile error,
	# so bark pixels and their damage coordinates remain aligned inside it.
	var steps := ceili(size.x/.025)
	for i in range(1,steps): keep[roundi(float(i)*(feet.size()-1)/steps)] = true
	for index: int in keep: columns.append(index)
	columns.sort()

static func _measure_feet(image: Image, source: Rect2) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(int(source.size.x)+1)
	result.fill(NAN)
	var previous := -1
	for column in result.size():
		var x := mini(int(source.end.x)-1,int(source.position.x)+column)
		# Do not mistake the crown's overhang or a low twig for a root.
		for y in range(int(source.end.y)-1,int(source.end.y-source.size.y*.08),-1):
			if image.get_pixel(x,y).a < .12: continue
			result[column] = 1-(float(y)-source.position.y)/source.size.y
			for empty in range(previous+1,column):
				result[empty] = result[column] if previous<0 else lerpf(result[previous],result[column],float(empty-previous)/(column-previous))
			previous = column
			break
	for column in range(previous+1,result.size()):
		result[column] = 0.0 if previous<0 else result[previous]
	return result

func _contact(x: float) -> Vector2:
	var at := clampf((x/size.x+.5)*(feet.size()-1),0,feet.size()-1)
	var left := mini(int(at),feet.size()-2)
	var t := at-left
	return Vector2(lerpf(feet[left],feet[left+1],t),lerpf(soil[left],soil[left+1],t))

func fit(point: Vector2) -> Vector2:
	if point.y>=band: return point
	var contact := _contact(point.x)
	return Vector2(point.x,band+(point.y-band)*(band-contact.y)/(band-contact.x))

func unfit(point: Vector2) -> Vector2:
	if point.y>=band: return point
	var contact := _contact(point.x)
	return Vector2(point.x,band+(point.y-band)*(band-contact.x)/(band-contact.y))

func fit_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		var steps := maxi(1,ceili(absf(b.x-a.x)/.05)) if minf(a.y,b.y)<band else 1
		var breaks: Array[float] = []
		for j in steps: breaks.append(float(j)/steps)
		if (a.y-band)*(b.y-band)<0: breaks.append((band-a.y)/(b.y-a.y))
		breaks.sort()
		for t in breaks: result.append(fit(a.lerp(b,t)))
	return result

func _append_cell(entity, cell: PackedVector2Array, vertices: PackedVector3Array, uvs: PackedVector2Array) -> void:
	var pieces: Array = [cell]
	if not entity.cuts.is_empty():
		pieces = []
		for remaining in entity.render_polygons:
			pieces.append_array(Geometry2D.intersect_polygons(cell,remaining))
	for piece: PackedVector2Array in pieces:
		var indices := Geometry2D.triangulate_polygon(piece)
		for index in indices:
			var original := piece[index]
			var point := fit(original)
			vertices.append(Vector3(point.x,-point.y,0))
			uvs.append(entity.texture_uv(original))

func build_mesh(entity) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if entity.render_polygons.is_empty(): return mesh
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var half := size.x*.5
	_append_cell(entity,PackedVector2Array([Vector2(-half,band),Vector2(half,band),Vector2(half,size.y),Vector2(-half,size.y)]),vertices,uvs)
	# Contact rows retain measured root/soil bends without thousands of empty
	# pixel-wide strips to clip synchronously on every hit.
	for i in range(columns.size()-1):
		var a := columns[i]
		var b := columns[i+1]
		var left := (float(a)/(feet.size()-1)-.5)*size.x
		var right := (float(b)/(feet.size()-1)-.5)*size.x
		for bounds in [[0.0,0.0,feet[a],feet[b]],[feet[a],feet[b],band,band]]:
			_append_cell(entity,PackedVector2Array([Vector2(left,bounds[0]),Vector2(right,bounds[1]),Vector2(right,bounds[3]),Vector2(left,bounds[2])]),vertices,uvs)
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
