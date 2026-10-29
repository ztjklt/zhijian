class_name PaperWeaponTrace
extends RefCounted
## Pure presentation: immutable world-space copies of the real displayed ink.
## No fabricated tip arc, connecting ribbon, collision shape, or damage callback.
const MAX_SNAPSHOTS := 4
const MAX_VERTICES := 4096
const LIFETIME := .072
const INTERVAL := 1.0 / 90.0
var snapshots: Array[Dictionary] = []
var sample_clock := INTERVAL
func clear() -> void:
	snapshots.clear()
	sample_clock = INTERVAL
func advance(delta: float, paths: Array, active: bool) -> void:
	for snapshot in snapshots: snapshot.age += maxf(0,delta)
	snapshots = snapshots.filter(func(snapshot:Dictionary)->bool:return snapshot.age<LIFETIME)
	sample_clock = minf(INTERVAL,sample_clock+maxf(0,delta))
	if not active or paths.is_empty() or sample_clock<INTERVAL: return
	var vertices:=0
	for path in paths: vertices+=path.size()
	if vertices>MAX_VERTICES:
		clear()
		return
	var copied:Array=[]
	for path in paths: copied.append(path.duplicate())
	snapshots.append({"paths":copied,"age":0.0})
	if snapshots.size()>MAX_SNAPSHOTS: snapshots.pop_front()
	sample_clock=0
static func opacity(age: float) -> float:
	return .22*pow(clampf(1.0-age/LIFETIME,0,1),2)
