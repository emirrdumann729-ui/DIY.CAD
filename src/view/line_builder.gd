class_name LineBuilder
extends RefCounted
## Renkli çizgi ve üçgenleri toplayıp tek bir ArrayMesh'e yazar.

var lv := PackedVector3Array()
var lc := PackedColorArray()
var tv := PackedVector3Array()
var tc := PackedColorArray()


func line(a: Vector3, b: Vector3, c: Color) -> void:
	lv.append(a)
	lv.append(b)
	lc.append(c)
	lc.append(c)


func dashed(a: Vector3, b: Vector3, c: Color, dash: float, gap: float) -> void:
	var L := a.distance_to(b)
	if L < 1e-9 or dash <= 0.0:
		return
	var d := (b - a) / L
	var s := 0.0
	var count := 0
	while s < L and count < 2000:
		var e := minf(s + dash, L)
		line(a + d * s, a + d * e, c)
		s = e + gap
		count += 1


func polyline(pts: PackedVector3Array, c: Color, closed := false) -> void:
	for i in pts.size() - 1:
		line(pts[i], pts[i + 1], c)
	if closed and pts.size() > 2:
		line(pts[pts.size() - 1], pts[0], c)


func dashed_polyline(pts: PackedVector3Array, c: Color, dash: float, gap: float) -> void:
	for i in pts.size() - 1:
		dashed(pts[i], pts[i + 1], c, dash, gap)


## Düzlem içinde kalın çizgi (normal: düzlem normali, hw: yarı kalınlık).
func thick(a: Vector3, b: Vector3, col: Color, hw: float, normal: Vector3) -> void:
	var d := b - a
	if d.length_squared() < 1e-18:
		return
	var side := d.cross(normal).normalized() * hw
	tri(a - side, b - side, b + side, col)
	tri(a - side, b + side, a + side, col)


func thick_polyline(pts: PackedVector3Array, col: Color, hw: float, normal: Vector3) -> void:
	for i in pts.size() - 1:
		thick(pts[i], pts[i + 1], col, hw, normal)


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	tv.append(a)
	tv.append(b)
	tv.append(c)
	tc.append(col)
	tc.append(col)
	tc.append(col)


func quad(center: Vector3, u: Vector3, v: Vector3, col: Color) -> void:
	var p0 := center - u - v
	var p1 := center + u - v
	var p2 := center + u + v
	var p3 := center - u + v
	tri(p0, p1, p2, col)
	tri(p0, p2, p3, col)


func commit(mesh: ArrayMesh) -> void:
	mesh.clear_surfaces()
	if not lv.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = lv
		arr[Mesh.ARRAY_COLOR] = lc
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	if not tv.is_empty():
		var arr2 := []
		arr2.resize(Mesh.ARRAY_MAX)
		arr2[Mesh.ARRAY_VERTEX] = tv
		arr2[Mesh.ARRAY_COLOR] = tc
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
