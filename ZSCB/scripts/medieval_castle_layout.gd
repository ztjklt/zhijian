class_name MedievalCastleLayout
extends RefCounted
## Adjacent atlas regions reconstruct one GPT castle concept at identical scale.
## Every occupied tile has its own identity and clipped physical geometry; the
## original image's flags and fine ink remain visible without becoming colliders.
const ATLAS_PATH := "res://assets/medieval/castle_v2/castle_master.png"
const REFERENCE_SIZE := Vector2(1536,1024)
const SOURCE_BOUNDS := Rect2(10,11,1516,933)
const LEFT := 68.0
const FLOOR := 3.4
const WIDTH := 20.0
const SCALE := WIDTH/SOURCE_BOUNDS.size.x
const COLUMNS := [10.0,199.5,389.0,578.5,768.0,957.5,1147.0,1336.5,1526.0]
const ROWS := [11.0,400.0,600.0,780.0,944.0]
# Concept-space silhouette, excluding the ornamental flags and mast lines.
const SILHOUETTE := [Vector2(11,942),Vector2(22,898),Vector2(31,854),Vector2(39,847),Vector2(39,720),Vector2(48,709),Vector2(48,622),Vector2(47,612),Vector2(48,468),Vector2(32,420),Vector2(31,329),Vector2(48,310),Vector2(275,310),Vector2(313,343),Vector2(313,416),Vector2(291,462),Vector2(291,590),Vector2(535,590),Vector2(535,570),Vector2(518,559),Vector2(519,513),Vector2(550,511),Vector2(550,486),Vector2(560,442),Vector2(570,486),Vector2(570,514),Vector2(583,514),Vector2(584,318),Vector2(578,316),Vector2(622,215),Vector2(667,316),Vector2(659,318),Vector2(659,419),Vector2(678,419),Vector2(677,302),Vector2(676,261),Vector2(687,242),Vector2(698,261),Vector2(698,257),Vector2(768,96),Vector2(839,257),Vector2(849,241),Vector2(860,262),Vector2(860,302),Vector2(858,420),Vector2(875,420),Vector2(875,317),Vector2(870,315),Vector2(915,215),Vector2(961,317),Vector2(952,319),Vector2(952,513),Vector2(963,513),Vector2(963,486),Vector2(975,440),Vector2(986,486),Vector2(986,512),Vector2(1017,512),Vector2(1017,561),Vector2(1000,574),Vector2(1000,591),Vector2(1245,591),Vector2(1245,464),Vector2(1217,418),Vector2(1217,347),Vector2(1255,311),Vector2(1486,311),Vector2(1503,329),Vector2(1503,416),Vector2(1481,466),Vector2(1481,611),Vector2(1494,620),Vector2(1489,710),Vector2(1501,718),Vector2(1498,847),Vector2(1510,881),Vector2(1524,942)]
const GATE_VOID := [Vector2(696,960),Vector2(696,801),Vector2(706,775),Vector2(732,744),Vector2(768,714),Vector2(805,743),Vector2(833,777),Vector2(842,802),Vector2(842,960)]
static var _canonical: Array = []

static func project_pixel(point: Vector2) -> Vector2:
	return Vector2(LEFT+(point.x-SOURCE_BOUNDS.position.x)*SCALE,FLOOR+(SOURCE_BOUNDS.end.y-point.y)*SCALE)

static func records() -> Array:
	if _canonical.is_empty():
		var silhouette := PackedVector2Array(SILHOUETTE)
		var material := Geometry2D.clip_polygons(silhouette,PackedVector2Array(GATE_VOID))
		for row in range(ROWS.size()-1):
			for column in range(COLUMNS.size()-1):
				var source := Rect2(COLUMNS[column],ROWS[row],COLUMNS[column+1]-COLUMNS[column],ROWS[row+1]-ROWS[row])
				var tile := PackedVector2Array([source.position,Vector2(source.end.x,source.position.y),source.end,Vector2(source.position.x,source.end.y)])
				var at := project_pixel(Vector2(source.get_center().x,source.end.y))
				var polygons: Array = []
				for solid in material:
					for piece in Geometry2D.intersect_polygons(solid,tile):
						if piece.size() < 3: continue
						var local := PackedVector2Array()
						for point in piece: local.append(project_pixel(point)-at)
						if Geometry2D.is_polygon_clockwise(local): local.reverse()
						polygons.append(local)
				if polygons.is_empty(): continue
				var index: int = row*8+column
				_canonical.append({"kind":"castle_piece","id":"castle-piece-"+str(index),"suffix":index,"x":at.x,"y":at.y,"size":source.size*SCALE,"source_uv":Rect2(source.position/REFERENCE_SIZE,source.size/REFERENCE_SIZE),"polygons":polygons})
	return _canonical.duplicate(true)

static func descriptor(stable_id: String) -> Dictionary:
	for record in records():
		if record.id == stable_id: return record
	return {}

static func entry_position() -> Vector2:
	return project_pixel(Vector2(768,944))

static func role_positions() -> Array:
	var king := project_pixel(Vector2(425,590))
	var queen := project_pixel(Vector2(1105,591))
	return [{"kind":"king","x":king.x,"y":king.y,"patrol_left":project_pixel(Vector2(330,590)).x,"patrol_right":project_pixel(Vector2(500,590)).x},{"kind":"queen","x":queen.x,"y":queen.y,"patrol_left":project_pixel(Vector2(1040,591)).x,"patrol_right":project_pixel(Vector2(1190,591)).x}]
