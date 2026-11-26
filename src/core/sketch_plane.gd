class_name SketchPlane
extends RefCounted
## Taslak düzlemi: orijin + düzlem içi X/Y eksenleri. Normal = X x Y.
## Standart yönelimler: Ön = XY, Üst = XZ (yukarı bakar), Sağ = YZ.

var name := ""
var origin := Vector3.ZERO
var x_dir := Vector3.RIGHT
var y_dir := Vector3.UP
## Yüzeye çizilen taslakta destek yüzü başvurusu {name, p, n} (OpenCASCADE çekirdeği düzlemi yüzle taşır)
var support := {}
## Referans düzleme bağlı taslak: o referans düzlemin özellik kimliği (-1: yok)
var ref := -1


static func make(p_name: String, p_origin: Vector3, p_x: Vector3, p_y: Vector3) -> SketchPlane:
	var p := SketchPlane.new()
	p.name = p_name
	p.origin = p_origin
	p.x_dir = p_x.normalized()
	p.y_dir = p_y.normalized()
	return p


const STANDARD_IDS := ["front", "top", "right"]


static func standard(id: String) -> SketchPlane:
	match id:
		"front":
			return make("Ön Düzlem", Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 1, 0))
		"top":
			return make("Üst Düzlem", Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 0, -1))
		"right":
			return make("Sağ Düzlem", Vector3.ZERO, Vector3(0, 0, -1), Vector3(0, 1, 0))
	return null


## Düzlemsel bir yüzeyden taslak düzlemi üretir (normal dışarı bakar).
static func from_face(point: Vector3, n: Vector3, p_name := "Yüzey") -> SketchPlane:
	n = n.normalized()
	var x: Vector3
	if absf(n.y) > 0.999:
		x = Vector3.RIGHT
	else:
		x = Vector3.UP.cross(n).normalized()
	var y := n.cross(x).normalized()
	var o := n * n.dot(point)
	return make(p_name, o, x, y)


func normal() -> Vector3:
	return x_dir.cross(y_dir).normalized()


func basis() -> Basis:
	return Basis(x_dir, y_dir, normal())


func to_world(p: Vector2) -> Vector3:
	return origin + x_dir * p.x + y_dir * p.y


func dir_to_world(d: Vector2) -> Vector3:
	return x_dir * d.x + y_dir * d.y


func to_local(w: Vector3) -> Vector2:
	var d := w - origin
	return Vector2(d.dot(x_dir), d.dot(y_dir))


## Işın-düzlem kesişimi. Kesişim yoksa null.
func intersect_ray(from: Vector3, dir: Vector3) -> Variant:
	var n := normal()
	var denom := n.dot(dir)
	if absf(denom) < 1e-9:
		return null
	var t := n.dot(origin - from) / denom
	return from + dir * t


func to_dict() -> Dictionary:
	return {
		"name": name,
		"origin": [origin.x, origin.y, origin.z],
		"x": [x_dir.x, x_dir.y, x_dir.z],
		"y": [y_dir.x, y_dir.y, y_dir.z],
	}.merged({"support": support.duplicate(true)} if not support.is_empty() else {}).merged({"ref": ref} if ref >= 0 else {})


static func _v3(a: Variant, def: Vector3) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return def


static func from_dict(d: Dictionary) -> SketchPlane:
	var p := make(str(d.get("name", "")), _v3(d.get("origin"), Vector3.ZERO),
		_v3(d.get("x"), Vector3.RIGHT), _v3(d.get("y"), Vector3.UP))
	if d.get("support") is Dictionary:
		p.support = (d["support"] as Dictionary).duplicate(true)
	p.ref = int(d.get("ref", -1))
	return p


func clone() -> SketchPlane:
	var p := make(name, origin, x_dir, y_dir)
	p.support = support.duplicate(true)
	p.ref = ref
	return p
