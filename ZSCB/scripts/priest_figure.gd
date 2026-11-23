extends RefCounted
## Paper cut robes in screen-local coordinates. The sleeve rotates toward the live nib.
const INK := Color("382e31")
const ROBE := Color("805347")
const EDGE := Color("daac75")
const LINEN := Color("f2e4cc")
const SHADE := Color("cdbcb0")
const Ground := preload("res://scripts/priest_ground.gd")
const STRIDE_METERS := 1.0

var facing := 1.0
var phase := 0.25
var walking := 0.0
var airborne := false
var previous := Vector2.INF
var idle_sample_in := 0.0
# Each boot is (forward offset, local screen height, angle of sole).
var front := Vector3(10,0,0)
var back := Vector3(-10,0,0)

func restore(data: Dictionary) -> void:
	facing = -1.0 if data.get("facing",1.0)==-1.0 else 1.0
	var p = data.get("phase",0.25)
	phase = fposmod(float(p),1.0) if (p is float or p is int) and is_finite(p) else 0.25
	var blend = data.get("walking",0.0)
	walking = clampf(float(blend),0.0,1.0) if (blend is float or blend is int) and is_finite(blend) else 0.0
	airborne = false
	previous = Vector2.INF
	idle_sample_in = 0.0

func snapshot() -> Dictionary:
	return {"phase":phase,"facing":facing,"walking":walking}

func advance(world, at: Vector2, delta: float) -> void:
	if at==previous and walking==0.0 and idle_sample_in>0.0:
		idle_sample_in-=delta
		return
	idle_sample_in=0.25
	var dx := at.x-previous.x if previous.is_finite() else 0.0
	var moved := absf(dx)>0.00001 and absf(dx)<STRIDE_METERS
	previous = at
	if moved:
		facing = signf(dx)
		phase = fposmod(phase+absf(dx)/STRIDE_METERS,1.0)
	walking = move_toward(walking,1.0 if moved else 0.0,delta*10.0)
	airborne = Ground.nearby(world,at.x,at.y,0.065).is_empty()
	front = _boot(world,at,phase,0.10)
	back = _boot(world,at,fposmod(phase+0.5,1.0),-0.10)

func _boot(world, at: Vector2, cycle: float, rest: float) -> Vector3:
	if airborne:
		return Vector3(rest*160.0, -9.0 if rest>0 else -20.0, -0.18)
	# Throughout stance the world-space sole stays on the same spot.
	var offset := (0.25-cycle)*STRIDE_METERS
	var lift := 0.0
	if cycle>=0.5:
		var swing := (cycle-0.5)*2.0
		offset = lerpf(-0.25,0.25,smoothstep(0.0,1.0,swing))*STRIDE_METERS
		lift = 0.18*sin(PI*swing)*walking
	offset = lerpf(rest,offset,walking)
	var x := at.x+facing*offset
	var support := Ground.trace(world,at,x)
	if support.is_empty():
		x = at.x
		offset = 0.0
	var floor_y := float(support.get("y",at.y))
	var toe := Ground.trace(world,Vector2(x,floor_y),x+facing*0.10)
	var angle := atan2(floor_y-float(toe.get("y",floor_y)),0.10)
	return Vector3(100.0*offset,100.0*(at.y-floor_y-lift),angle)

static func draw_leg(c: Node2D, hip: Vector2, boot: Vector3, near: bool) -> void:
	var sole := Vector2(boot.x,boot.y)
	var along := Vector2.from_angle(boot.z)
	var up := Vector2(along.y,-along.x)
	var ankle := sole+up*5.0
	var leg := ankle-hip
	var knee := hip+leg*0.5+Vector2(leg.y,-leg.x).normalized()*sqrt(maxf(0.0,25.0*25.0-leg.length_squared()*0.25))
	var joints := PackedVector2Array([hip,knee,ankle])
	c.draw_polyline(joints,INK,8.0,true)
	c.draw_polyline(joints,ROBE if near else SHADE,4.8,true)
	var heel := sole-along*5.0
	var toe := sole+along*7.0
	patch(c,PackedVector2Array([heel,heel+up*6.0,sole+up*8.0,toe+up*3.0,toe]),ROBE if near else SHADE,1.8)

static func patch(c: Node2D, pts: PackedVector2Array, color: Color, width := 2.0) -> void:
	c.draw_colored_polygon(pts,color)
	pts.append(pts[0])
	c.draw_polyline(pts,INK,width,true)

func draw(c: Node2D, foot: Vector2, nib: Vector2, ppu: float, t: float, writing: bool) -> void:
	var scale := ppu/100.0
	var orientation := facing
	if writing and absf(nib.x-foot.x)>ppu*0.10: orientation=signf(nib.x-foot.x)
	c.draw_set_transform(foot,0,Vector2(facing,1)*scale)
	draw_leg(c,Vector2(-6,-43),back,false)
	draw_leg(c,Vector2(5,-44),front,true)
	var rise := -2.7*absf(sin(phase*TAU))*walking
	var body := foot+Vector2(0,rise*scale)
	c.draw_set_transform(body,0,Vector2(orientation,1)*scale)
	var lift := sin(t*1.8)*1.2
	# Broken gilt halo and two knotted paper streamers behind the hood.
	c.draw_arc(Vector2(-4,-128+lift),30,-3.50,1.06,42,EDGE,2.1,true)
	c.draw_arc(Vector2(-4,-128+lift),30,1.34,2.61,16,EDGE,1.5,true)
	c.draw_line(Vector2(-4,-162+lift),Vector2(-4,-155+lift),ROBE,2.2,true)
	patch(c,PackedVector2Array([Vector2(-11,-99),Vector2(-31,-85),Vector2(-34,-56),Vector2(-46,-31+lift),Vector2(-35,-34),Vector2(-26,-56),Vector2(-16,-70)]),ROBE)
	var hem := sin(phase*TAU)*4.5*walking
	patch(c,PackedVector2Array([Vector2(-11,-101),Vector2(12,-97),Vector2(23,-57),Vector2(20,-38),Vector2(29+hem,-24),Vector2(13+hem,-20),Vector2(3,-29),Vector2(-8,-21),Vector2(-28+hem,-25),Vector2(-23,-43),Vector2(-22,-76)]),LINEN,2.8)
	patch(c,PackedVector2Array([Vector2(-2,-93),Vector2(13,-96),Vector2(22,-63),Vector2(13,-55),Vector2(16,-27),Vector2(6,-30),Vector2(1,-55),Vector2(-13,-80)]),ROBE)
	c.draw_polyline(PackedVector2Array([Vector2(4,-91),Vector2(-4,-76),Vector2(8,-58),Vector2(12,-25)]),EDGE,2.4,true)
	c.draw_polyline(PackedVector2Array([Vector2(-17,-59),Vector2(-13,-42),Vector2(-21,-28)]),SHADE,2.0,true)
	c.draw_line(Vector2(-10,-40),Vector2(-7,-26),SHADE,1.5,true)
	patch(c,PackedVector2Array([Vector2(-21,-100),Vector2(-26,-116),Vector2(-21,-132),Vector2(-5,-149),Vector2(10,-139),Vector2(20,-116),Vector2(16,-101),Vector2(4,-94)]),LINEN,2.7)
	patch(c,PackedVector2Array([Vector2(-14,-113),Vector2(-5,-127),Vector2(10,-128),Vector2(17,-117),Vector2(13,-106),Vector2(2,-102),Vector2(-8,-106)]),INK,1.4)
	c.draw_line(Vector2(3,-116),Vector2(11,-118),EDGE,2.5,true)
	c.draw_polyline(PackedVector2Array([Vector2(-20,-119),Vector2(-8,-137),Vector2(-3,-141)]),SHADE,2,true)
	var shoulder := Vector2(8,-83)
	var tip_local := (nib-body)/scale*Vector2(orientation,1.0)
	var arm := shoulder.direction_to(tip_local)
	var hand := shoulder + arm*(44.0 if writing else 32.0)
	var cuff := hand-arm*7
	var elbow := shoulder+arm*17+Vector2(0,14)
	var sleeve := PackedVector2Array([shoulder,elbow,cuff])
	c.draw_polyline(sleeve,INK,14.0,true)
	c.draw_polyline(sleeve,LINEN,10.0,true)
	c.draw_line(cuff-arm.orthogonal()*4,cuff+arm.orthogonal()*4,EDGE,2.6,true)
	c.draw_set_transform(Vector2.ZERO)
	preload("res://scripts/companion_brush.gd").draw(c, body+hand*Vector2(orientation,1.0)*scale, nib, ppu)

