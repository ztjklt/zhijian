class_name PaperWeaponMotion
extends RefCounted
## Character-space palm, sword angle and body lean. Rendering and hit tests
## both consume the resulting hand transform through sample_weapon().

const NAMES := ["下劈", "反手上挑", "前刺", "重斩"]
const TIMES := [0.0, 0.20, 0.58, 0.72, 1.0]
const GUARD := Vector4(23, -23, -0.65, 0.10)
const MOVES := [
	[GUARD, Vector4(16, -48, -2.05, -0.15), Vector4(17, -16, 0.70, 0.22), Vector4(19, -17, 0.85, 0.18), GUARD],
	[GUARD, Vector4(16, -17, 0.90, -0.12), Vector4(22, -44, -1.75, 0.17), Vector4(18, -47, -1.95, 0.10), GUARD],
	[GUARD, Vector4(8, -29, -0.20, -0.14), Vector4(29, -32, -0.03, 0.25), Vector4(27, -31, 0.08, 0.20), GUARD],
	[GUARD, Vector4(9, -50, -2.65, -0.24), Vector4(21, -17, 1.25, 0.34), Vector4(20, -15, 1.32, 0.23), GUARD],
]

static func pose(move: int, progress: float) -> Vector4:
	var keys: Array = MOVES[posmod(move, MOVES.size())]
	var p := clampf(progress, 0, 1)
	var segment := 0
	while segment < TIMES.size() - 2 and p > TIMES[segment + 1]: segment += 1
	var span: float = TIMES[segment + 1] - TIMES[segment]
	var t: float = (p - TIMES[segment]) / span
	var a: Vector4 = keys[segment]
	var b: Vector4 = keys[segment + 1]
	var result := Vector4.ZERO
	for axis in range(4):
		var m0 := tangent(keys, segment, axis) * span
		var m1 := tangent(keys, segment + 1, axis) * span
		result[axis] = (2*t*t*t - 3*t*t + 1)*a[axis] + (t*t*t - 2*t*t + t)*m0 + (-2*t*t*t + 3*t*t)*b[axis] + (t*t*t - t*t)*m1
	return result

static func tangent(keys: Array, index: int, axis: int) -> float:
	if index == 0 or index == keys.size() - 1: return 0.0
	var left: float = (keys[index][axis] - keys[index - 1][axis]) / (TIMES[index] - TIMES[index - 1])
	var right: float = (keys[index + 1][axis] - keys[index][axis]) / (TIMES[index + 1] - TIMES[index])
	# Stop at an extremum; carry velocity through a continuing movement.
	if left * right <= 0: return 0.0
	return signf(left) * minf(absf((left + right) * 0.5), 3.0 * minf(absf(left), absf(right)))

static func rear_hand(move: int, progress: float) -> Vector2:
	var p := clampf(progress, 0, 1)
	var windup := smoothstep(0, 0.20, p)
	var cut := smoothstep(0.20, 0.65, p)
	var settle := smoothstep(0.72, 1, p)
	var back := Vector2(-11, -26) if move != 2 else Vector2(-7, -30)
	return Vector2(4, -29).lerp(back, windup).lerp(Vector2(7, -25), cut).lerp(Vector2(4, -29), settle)
