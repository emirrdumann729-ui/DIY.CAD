class_name Sketch3D
extends RefCounted
## Temel 3B taslak: uzayda noktalar ve onları birleştiren çizgiler.
## Faz 5'te süpürme (sweep) yolu ve loft kılavuzu olarak kullanılacak.

var points := {}      # int -> Vector3
var lines: Array = [] # [[a, b], ...]
var next_id := 1


func add_point(p: Vector3) -> int:
	var id := next_id
	next_id += 1
	points[id] = p
	return id


func add_line(a: int, b: int) -> void:
	if a == b:
		return
	for l in lines:
		if (l[0] == a and l[1] == b) or (l[0] == b and l[1] == a):
			return
	lines.append([a, b])


func remove_point(pid: int) -> void:
	var keep: Array = []
	for l in lines:
		if l[0] != pid and l[1] != pid:
			keep.append(l)
	lines = keep
	cleanup()


func remove_line(idx: int) -> void:
	if idx >= 0 and idx < lines.size():
		lines.remove_at(idx)
	cleanup()


func cleanup() -> void:
	var used := {}
	for l in lines:
		used[l[0]] = true
		used[l[1]] = true
	for pid in points.keys():
		if not used.has(pid):
			points.erase(pid)


func is_empty() -> bool:
	return lines.is_empty()


func total_length() -> float:
	var s := 0.0
	for l in lines:
		s += (points[l[0]] as Vector3).distance_to(points[l[1]])
	return s


func aabb() -> AABB:
	var first := true
	var box := AABB()
	for pid in points:
		var p: Vector3 = points[pid]
		if first:
			box = AABB(p, Vector3.ZERO)
			first = false
		else:
			box = box.expand(p)
	return box


func to_dict() -> Dictionary:
	var pts := {}
	for pid in points:
		var p: Vector3 = points[pid]
		pts[str(pid)] = [p.x, p.y, p.z]
	return {"points": pts, "lines": lines.duplicate(true), "next_id": next_id}


static func from_dict(d: Dictionary) -> Sketch3D:
	var s := Sketch3D.new()
	var pts: Dictionary = d.get("points", {})
	for k in pts:
		var v: Array = pts[k]
		s.points[int(k)] = Vector3(float(v[0]), float(v[1]), float(v[2]))
	for l in d.get("lines", []):
		s.lines.append([int(l[0]), int(l[1])])
	s.next_id = int(d.get("next_id", 1))
	return s
