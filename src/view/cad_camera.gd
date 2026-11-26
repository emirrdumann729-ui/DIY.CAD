class_name CadCamera
extends Camera3D
## CAD kamerası: hedef etrafında döndürme (turntable), kaydırma, imlece doğru yakınlaştırma,
## standart görünümler, sığdırma ve yumuşak geçiş animasyonları.

signal view_changed

const ORTHO_DIST := 50000.0
const ROT_SPEED := 0.008

var target := Vector3.ZERO
var view_size := 200.0          # görünen yükseklik (mm)
var orient := Basis.IDENTITY    # kamera yönelimi (x sağ, y yukarı, z geriye)
var perspective := false

var _anim_t := 1.0
var _anim_dur := 0.35
var _from_q := Quaternion.IDENTITY
var _to_q := Quaternion.IDENTITY
var _from_target := Vector3.ZERO
var _to_target := Vector3.ZERO
var _from_size := 200.0
var _to_size := 200.0


func _ready() -> void:
	orient = standard_basis("iso")
	apply()


static func standard_basis(view_name: String) -> Basis:
	match view_name:
		"front":
			return Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
		"back":
			return Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
		"top":
			return Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
		"bottom":
			return Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
		"right":
			return Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
		"left":
			return Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
		"iso":
			var z := Vector3(1, 1, 1).normalized()
			var x := Vector3.UP.cross(z).normalized()
			var y := z.cross(x).normalized()
			return Basis(x, y, z)
	return Basis.IDENTITY


func apply() -> void:
	var dist: float
	if perspective:
		projection = PROJECTION_PERSPECTIVE
		fov = 30.0
		dist = view_size * 0.5 / tan(deg_to_rad(fov * 0.5))
		near = maxf(dist * 0.002, 0.001)
		far = dist * 200.0 + 10000.0
	else:
		projection = PROJECTION_ORTHOGONAL
		size = view_size
		dist = ORTHO_DIST
		near = 10.0
		far = ORTHO_DIST * 2.0
	global_transform = Transform3D(orient, target + orient.z * dist)
	view_changed.emit()


func viewport_height() -> float:
	return maxf(get_viewport().get_visible_rect().size.y, 1.0)


func viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size


## Bir pikselin model alanındaki karşılığı (mm).
func world_per_pixel() -> float:
	return view_size / viewport_height()


## Çizgilerin yüzeylerin önünde görünmesi için önerilen derinlik kaydırması.
func depth_bias() -> float:
	if perspective:
		return view_size * 0.004
	return view_size * 0.003


func orbit(dx: float, dy: float) -> void:
	_anim_t = 1.0
	var r_yaw := Basis(Vector3.UP, -dx * ROT_SPEED)
	var r_pitch := Basis(orient.x, -dy * ROT_SPEED)
	orient = (r_yaw * r_pitch * orient).orthonormalized()
	apply()


func pan(dx: float, dy: float) -> void:
	_anim_t = 1.0
	var w := world_per_pixel()
	target += (-orient.x * dx + orient.y * dy) * w
	apply()


## Fare imlecinin altındaki nokta sabit kalacak şekilde yakınlaştırır.
func zoom_at(factor: float, mouse: Vector2) -> void:
	_anim_t = 1.0
	var vs := viewport_size()
	var old := view_size
	var new_size := clampf(old * factor, 0.01, 1.0e6)
	var off := mouse - vs * 0.5
	var w := old / maxf(vs.y, 1.0)
	var world_off := orient.x * off.x * w - orient.y * off.y * w
	target += world_off * (1.0 - new_size / old)
	view_size = new_size
	apply()


func toggle_perspective() -> void:
	perspective = not perspective
	apply()


func animate_to(b: Basis, new_target: Vector3, new_size: float, animate := true) -> void:
	if not animate:
		orient = b.orthonormalized()
		target = new_target
		view_size = new_size
		_anim_t = 1.0
		apply()
		return
	_from_q = orient.get_rotation_quaternion()
	_to_q = b.orthonormalized().get_rotation_quaternion()
	_from_target = target
	_to_target = new_target
	_from_size = view_size
	_to_size = new_size
	_anim_t = 0.0


func set_standard_view(view_name: String, animate := true) -> void:
	animate_to(standard_basis(view_name), target, view_size, animate)


## AABB'yi verilen yönelimde ekrana sığdıracak hedef ve boyutu hesaplar.
func fit_params(box: AABB, b: Basis) -> Array:
	var center := box.get_center()
	var vs := viewport_size()
	var aspect := vs.x / maxf(vs.y, 1.0)
	var hx := 0.0
	var hy := 0.0
	for i in 8:
		var c := box.get_endpoint(i) - center
		hx = maxf(hx, absf(c.dot(b.x)))
		hy = maxf(hy, absf(c.dot(b.y)))
	var s := maxf(maxf(hy * 2.0, hx * 2.0 / maxf(aspect, 0.1)) * 1.2, 1.0)
	return [center, s]


func fit(box: AABB, animate := true) -> void:
	var p := fit_params(box, orient)
	animate_to(orient, p[0], p[1], animate)


func rotate_step(axis: String, deg: float) -> void:
	var r: Basis
	if axis == "yaw":
		r = Basis(orient.y, deg_to_rad(deg))
	else:
		r = Basis(orient.x, deg_to_rad(deg))
	animate_to(r * orient, target, view_size, true)


func is_animating() -> bool:
	return _anim_t < 1.0


func _process(delta: float) -> void:
	if _anim_t >= 1.0:
		return
	_anim_t = minf(_anim_t + delta / _anim_dur, 1.0)
	var s := _anim_t * _anim_t * (3.0 - 2.0 * _anim_t)
	orient = Basis(_from_q.slerp(_to_q, s))
	target = _from_target.lerp(_to_target, s)
	view_size = lerpf(_from_size, _to_size, s)
	apply()
