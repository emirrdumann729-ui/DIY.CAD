class_name ModelMesh
extends RefCounted
## Çekirdekten gelen üçgen ağı için yardımcı veri:
## benzersiz köşeler, üçgen komşulukları, özellik kenarları, ışın seçimi, düzlemsel yüz bulma.

const QUANT := 1000.0          # 0.001 mm hassasiyetle köşe birleştirme
const EDGE_ANGLE := 25.0       # bu açıdan keskin kenarlar çizilir
const SLIVER_ALT := 0.004      # bu yükseklikten (mm) ince üçgenler "şerit" sayılır
const SLIVER_AREA := 0.001     # bu alandan (mm²) küçük üçgenlerin normali güvenilmez
const PLANE_TOL := 0.002       # düzlemdeşlik toleransı (mm)

var verts := PackedVector3Array()    # benzersiz köşeler
var tris := PackedInt32Array()       # üçgen başına 3 indeks (Godot sarımı)
var normals := PackedVector3Array()  # üçgen normali (dışa doğru)
var areas := PackedFloat32Array()    # üçgen alanı
var reliable := PackedByteArray()    # normali güvenilir mi (şerit üçgen değil)
var edge_tris := {}                  # kenar anahtarı -> [üçgen indeksleri]
var feature_edges := PackedVector3Array()  # çizilecek kenarlar (çiftler halinde)
var aabb := AABB()
var source: ArrayMesh = null
# B-rep çekirdeğinden (OpenCASCADE) gelen bilgiler; CSG çekirdeğinde boştur.
var brep_src := {}
var tri_face := PackedInt32Array()   # üçgen başına B-rep yüz kimliği
var brep_faces: Array = []           # {id, type, n?, p?, axis?, r?, area, e: [kenar kimlikleri]}
var brep_edges: Array = []           # {id, pts: PackedVector3Array, f: [yüzler], m, d, type, len, r?}
var exact_mass := {}                 # {volume, area, center, tensor} (yoğunluk 1)


func has_brep() -> bool:
	return not tri_face.is_empty()


func tri_count() -> int:
	return tris.size() / 3


func is_empty() -> bool:
	return tris.is_empty()


static func _ekey(i: int, j: int) -> int:
	return (mini(i, j) << 32) | maxi(i, j)


## Ağın yüzey dizileri [[köşeler, sıra]] (ana iş parçacığında alınır; build_surfaces iş parçacığında çalışabilir)
static func surfaces_of(mesh: ArrayMesh) -> Array:
	var out: Array = []
	if mesh == null:
		return out
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		out.append([v, idx if idx is PackedInt32Array else PackedInt32Array()])
	return out


func build(mesh: ArrayMesh, brep := {}) -> void:
	build_surfaces(surfaces_of(mesh), mesh.get_aabb() if mesh != null else AABB(), brep, mesh == null)
	source = mesh


## Asıl işleme: sahne / RenderingServer'a dokunmaz, iş parçacığında güvenle çalışır (Faz 9)
func build_surfaces(surfs: Array, box: AABB, brep := {}, is_null := false) -> void:
	source = null
	brep_src = brep
	verts.clear()
	tris.clear()
	normals.clear()
	areas.clear()
	reliable.clear()
	edge_tris.clear()
	feature_edges.clear()
	tri_face.clear()
	brep_faces = brep.get("faces", [])
	brep_edges = brep.get("edges", [])
	exact_mass = brep.get("mass", {}) if brep.get("mass") is Dictionary else {}
	var in_face: PackedInt32Array = brep.get("tri_face", PackedInt32Array())
	if is_null:
		aabb = AABB()
		return
	var vmap := {}
	for sf in surfs:
		var v: PackedVector3Array = sf[0]
		var idx: PackedInt32Array = sf[1]
		var order := PackedInt32Array()
		if idx.size() > 0:
			order = idx
		else:
			order.resize(v.size())
			for i in v.size():
				order[i] = i
		for i in order:
			var p: Vector3 = v[i]
			var k := Vector3i(roundi(p.x * QUANT), roundi(p.y * QUANT), roundi(p.z * QUANT))
			if not vmap.has(k):
				vmap[k] = verts.size()
				verts.append(p)
			tris.append(vmap[k])
	# Normaller ve kenar komşulukları
	var t := 0
	var valid := PackedInt32Array()
	var use_faces := in_face.size() * 3 == tris.size()
	while t < tris.size():
		var a := verts[tris[t]]
		var b := verts[tris[t + 1]]
		var c := verts[tris[t + 2]]
		# Godot'da ön yüz saat yönündedir; dış normal (c-a)x(b-a)
		var n := (c - a).cross(b - a)
		if n.length_squared() > 1e-18 and tris[t] != tris[t + 1] and tris[t + 1] != tris[t + 2] and tris[t] != tris[t + 2]:
			valid.append(tris[t])
			valid.append(tris[t + 1])
			valid.append(tris[t + 2])
			normals.append(n.normalized())
			if use_faces:
				tri_face.append(in_face[t / 3])
		t += 3
	tris = valid
	var nt := tri_count()
	areas.resize(nt)
	reliable.resize(nt)
	for ti in nt:
		var a := verts[tris[ti * 3]]
		var b := verts[tris[ti * 3 + 1]]
		var c := verts[tris[ti * 3 + 2]]
		var area := (c - a).cross(b - a).length() * 0.5
		var longest := maxf((b - a).length(), maxf((c - b).length(), (a - c).length()))
		areas[ti] = area
		# Çok ince (şerit) üçgenlerin normali sayısal olarak güvenilmez
		reliable[ti] = 1 if 2.0 * area / maxf(longest, 1e-12) > SLIVER_ALT and area > SLIVER_AREA else 0
		for k in 3:
			var key := _ekey(tris[ti * 3 + k], tris[ti * 3 + (k + 1) % 3])
			if not edge_tris.has(key):
				edge_tris[key] = []
			edge_tris[key].append(ti)
	if has_brep():
		# Gerçek kenarlar çekirdekten gelir
		for e in brep_edges:
			var pts: PackedVector3Array = e["pts"]
			for i in pts.size() - 1:
				feature_edges.append(pts[i])
				feature_edges.append(pts[i + 1])
		aabb = box
		return
	_fix_sliver_normals()
	var cos_t := cos(deg_to_rad(EDGE_ANGLE))
	for key in edge_tris:
		var lst: Array = edge_tris[key]
		var draw := false
		if lst.size() != 2:
			draw = true
		elif reliable[lst[0]] == 1 and reliable[lst[1]] == 1 and normals[lst[0]].dot(normals[lst[1]]) < cos_t:
			# Küçük üçgen büyüğünün düzleminde yatıyorsa gerçek kenar değildir
			var big: int = lst[0] if areas[lst[0]] >= areas[lst[1]] else lst[1]
			var small: int = lst[1] if big == lst[0] else lst[0]
			var nbig := normals[big]
			var dbig := nbig.dot(verts[tris[big * 3]])
			for j in 3:
				if absf(nbig.dot(verts[tris[small * 3 + j]]) - dbig) > PLANE_TOL:
					draw = true
					break
		if draw:
			feature_edges.append(verts[key >> 32])
			feature_edges.append(verts[key & 0xFFFFFFFF])
	aabb = box


## CSG birleşimlerinde oluşan ince şerit üçgenler, komşu güvenilir üçgenin düzleminde
## yatıyorsa onun normalini alır. Böylece sahte kenar çizgileri ve yüz seçimi hataları önlenir.
func _fix_sliver_normals() -> void:
	var nt := tri_count()
	for pass_i in 4:
		var changed := false
		for ti in nt:
			if reliable[ti] == 1:
				continue
			var done := false
			for k in 3:
				if done:
					break
				var key := _ekey(tris[ti * 3 + k], tris[ti * 3 + (k + 1) % 3])
				for nb in edge_tris.get(key, []):
					if nb == ti or reliable[nb] == 0:
						continue
					var nn := normals[nb]
					var d := nn.dot(verts[tris[nb * 3]])
					var on_plane := true
					for j in 3:
						if absf(nn.dot(verts[tris[ti * 3 + j]]) - d) > PLANE_TOL:
							on_plane = false
							break
					if on_plane:
						normals[ti] = nn
						reliable[ti] = 1
						changed = true
						done = true
						break
		if not changed:
			break


## Ekranda gösterilecek mesh: küçük açılı komşu üçgenlerde normaller yumuşatılır
## (silindirler pürüzsüz, keskin köşeler keskin görünür).
func display_mesh(smooth_deg := 30.0) -> ArrayMesh:
	return mesh_from_arrays(display_arrays(smooth_deg))


static func mesh_from_arrays(arr: Array) -> ArrayMesh:
	var am := ArrayMesh.new()
	if not arr.is_empty() and arr[Mesh.ARRAY_VERTEX] != null and (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


## Gösterim dizileri (yumuşatılmış normaller). Köşe → üçgen listesi sıkıştırılmış satır (CSR) düzeninde.
func display_arrays(smooth_deg := 30.0) -> Array:
	if is_empty():
		return []
	var nv := verts.size()
	var start := PackedInt32Array()
	start.resize(nv + 1)
	for vi0 in tris:
		start[vi0 + 1] += 1
	for i in nv:
		start[i + 1] += start[i]
	var fill := start.duplicate()
	var lst := PackedInt32Array()
	lst.resize(tris.size())
	for t0 in tri_count():
		for k0 in 3:
			var v0 := tris[t0 * 3 + k0]
			lst[fill[v0]] = t0
			fill[v0] += 1
	var brep_mode := has_brep()
	var cos_s := cos(deg_to_rad(smooth_deg))
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	pos.resize(tris.size())
	nor.resize(tris.size())
	for ti in tri_count():
		var n0 := normals[ti]
		for k in 3:
			var vi := tris[ti * 3 + k]
			var acc := Vector3.ZERO
			for li in range(start[vi], start[vi + 1]):
				var tj := lst[li]
				var nj := normals[tj]
				var same := tri_face[tj] == tri_face[ti] if brep_mode else nj.dot(n0) >= cos_s
				if same:
					acc += nj * maxf(areas[tj], 1e-9)
			pos[ti * 3 + k] = verts[vi]
			nor[ti * 3 + k] = acc.normalized() if acc.length_squared() > 1e-12 else n0
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	return arr


## Başka bir (iş parçacığında hazırlanmış) modelin verisini al
func copy_from(o: ModelMesh) -> void:
	verts = o.verts
	tris = o.tris
	normals = o.normals
	areas = o.areas
	reliable = o.reliable
	edge_tris = o.edge_tris
	feature_edges = o.feature_edges
	aabb = o.aabb
	source = o.source
	brep_src = o.brep_src
	tri_face = o.tri_face
	brep_faces = o.brep_faces
	brep_edges = o.brep_edges
	exact_mass = o.exact_mass


## Dışa aktarma için üçgen listesi (dış normale göre saat yönü tersine: a, c, b).
func ccw_triangles() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(tris.size())
	for ti in tri_count():
		out[ti * 3] = verts[tris[ti * 3]]
		out[ti * 3 + 1] = verts[tris[ti * 3 + 2]]
		out[ti * 3 + 2] = verts[tris[ti * 3 + 1]]
	return out


## Işın ile en yakın üçgen. Dönüş: {tri, point, dist} veya {}.
func raycast(from: Vector3, dir: Vector3) -> Dictionary:
	if is_empty():
		return {}
	if not aabb.grow(0.01).intersects_ray(from, dir):
		return {}
	var best := INF
	var best_t := -1
	for ti in tri_count():
		var a := verts[tris[ti * 3]]
		var b := verts[tris[ti * 3 + 1]]
		var c := verts[tris[ti * 3 + 2]]
		var e1 := b - a
		var e2 := c - a
		var pv := dir.cross(e2)
		var det := e1.dot(pv)
		if absf(det) < 1e-12:
			continue
		var inv := 1.0 / det
		var tv := from - a
		var u := tv.dot(pv) * inv
		if u < 0.0 or u > 1.0:
			continue
		var qv := tv.cross(e1)
		var v := dir.dot(qv) * inv
		if v < 0.0 or u + v > 1.0:
			continue
		var d := e2.dot(qv) * inv
		if d > 0.0 and d < best:
			best = d
			best_t = ti
	if best_t < 0:
		return {}
	return {"tri": best_t, "point": from + dir * best, "dist": best}


## Başlangıç üçgenine bağlı, aynı düzlemdeki üçgenler (bir yüz).
## Dönüş: {tris: PackedInt32Array, planar: bool, normal: Vector3, point: Vector3}
func planar_face(start_tri: int) -> Dictionary:
	if has_brep():
		return brep_face_region(tri_face[start_tri], start_tri)
	var n0 := normals[start_tri]
	var p0 := verts[tris[start_tri * 3]]
	var d0 := n0.dot(p0)
	var visited := {start_tri: true}
	var stack := [start_tri]
	var out := PackedInt32Array()
	var planar := true
	var cos_t := cos(deg_to_rad(EDGE_ANGLE))
	while not stack.is_empty():
		var ti: int = stack.pop_back()
		out.append(ti)
		for k in 3:
			var key := _ekey(tris[ti * 3 + k], tris[ti * 3 + (k + 1) % 3])
			for nb in edge_tris.get(key, []):
				if visited.has(nb):
					continue
				var nn := normals[nb]
				var on_plane := true
				for j in 3:
					if absf(n0.dot(verts[tris[nb * 3 + j]]) - d0) > PLANE_TOL:
						on_plane = false
						break
				var same_plane := on_plane and (reliable[nb] == 0 or nn.dot(n0) > 0.999)
				if same_plane:
					visited[nb] = true
					stack.append(nb)
				elif reliable[nb] == 1 and reliable[ti] == 1 and nn.dot(normals[ti]) > cos_t:
					# Kenar keskin değil ama düzlem değişiyor: eğri yüzey
					planar = false
	if not planar:
		out = smooth_region(start_tri)
	return {"tris": out, "planar": planar, "normal": n0, "point": p0}


## B-rep yüzünün tüm üçgenleri. Dönüş planar_face ile aynı biçimde (+ face, info).
func brep_face_region(fid: int, start_tri := -1) -> Dictionary:
	var out := PackedInt32Array()
	for ti in tri_count():
		if tri_face[ti] == fid:
			out.append(ti)
	var info: Dictionary = brep_faces[fid] if fid >= 0 and fid < brep_faces.size() else {}
	var st := start_tri if start_tri >= 0 else (out[0] if not out.is_empty() else 0)
	var planar: bool = info.get("type", "") == "plane"
	var n := normals[st] if st < normals.size() else Vector3.UP
	var p := verts[tris[st * 3]] if st * 3 < tris.size() else Vector3.ZERO
	if planar and info.has("n"):
		n = _v3(info["n"])
		if info.has("p"):
			p = _v3(info["p"])
	return {"tris": out, "planar": planar, "normal": n, "point": p, "face": fid, "info": info}


static func _v3(a: Variant) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Ekran noktasına en yakın B-rep kenarı (piksel toleransı içinde). to_screen: Callable(Vector3) -> Vector2.
## Dönüş: {edge, point (dünya), dist_px} veya {}.
func pick_edge(screen: Vector2, to_screen: Callable, tol_px := 8.0) -> Dictionary:
	var best := {}
	var bd := tol_px
	for e in brep_edges:
		var pts: PackedVector3Array = e["pts"]
		for i in pts.size() - 1:
			var a: Vector2 = to_screen.call(pts[i])
			var b: Vector2 = to_screen.call(pts[i + 1])
			var q := Geometry2D.get_closest_point_to_segment(screen, a, b)
			var d := q.distance_to(screen)
			if d < bd:
				var L := a.distance_to(b)
				var t := 0.0 if L < 1e-9 else a.distance_to(q) / L
				bd = d
				best = {"edge": int(e["id"]), "point": pts[i].lerp(pts[i + 1], t), "dist_px": d}
	return best


## Keskin kenara kadar uzanan pürüzsüz bölge (ör. silindirin tüm yan yüzü).
func smooth_region(start_tri: int) -> PackedInt32Array:
	if has_brep():
		return brep_face_region(tri_face[start_tri])["tris"]
	var cos_t := cos(deg_to_rad(EDGE_ANGLE))
	var visited := {start_tri: true}
	var stack := [start_tri]
	var out := PackedInt32Array()
	while not stack.is_empty():
		var ti: int = stack.pop_back()
		out.append(ti)
		for k in 3:
			var key := _ekey(tris[ti * 3 + k], tris[ti * 3 + (k + 1) % 3])
			for nb in edge_tris.get(key, []):
				if visited.has(nb):
					continue
				if normals[nb].dot(normals[ti]) > cos_t:
					visited[nb] = true
					stack.append(nb)
	return out


func face_triangles(tri_list: PackedInt32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for ti in tri_list:
		out.append(verts[tris[ti * 3]])
		out.append(verts[tris[ti * 3 + 1]])
		out.append(verts[tris[ti * 3 + 2]])
	return out


static func _subexp(w0: float, w1: float, w2: float) -> Array:
	var t0 := w0 + w1
	var f1 := t0 + w2
	var t1 := w0 * w0
	var t2 := t1 + w1 * t0
	var f2 := t2 + w2 * f1
	var f3 := w0 * t1 + w1 * t2 + w2 * f2
	var g0 := f2 + w0 * (f1 + w0)
	var g1 := f2 + w1 * (f1 + w1)
	var g2 := f2 + w2 * (f1 + w2)
	return [f1, f2, f3, g0, g1, g2]


## Kütle özellikleri (Eberly, "Polyhedral Mass Properties").
## density: g/cm³. Dönüş: hacim mm³, alan mm², kütle g, ağırlık merkezi mm,
## atalet tensörü g·mm² (ağırlık merkezinde, global eksenlere hizalı), asal momentler.
func mass_properties(density_g_cm3: float) -> Dictionary:
	if not exact_mass.is_empty():
		var rho0 := density_g_cm3 / 1000.0
		var c0 := _v3(exact_mass["center"])
		var t0: Array = exact_mass["tensor"]
		var ten := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
		for i in 3:
			for j in 3:
				ten[i][j] = float(t0[i][j]) * rho0
		var v0 := float(exact_mass["volume"])
		return {"volume": v0, "area": float(exact_mass["area"]), "mass": v0 * rho0, "center": c0,
			"cx": c0.x, "cy": c0.y, "cz": c0.z, "tensor": ten, "principal": principal_moments(ten), "exact": true}
	var intg := PackedFloat64Array()
	intg.resize(10)
	intg.fill(0.0)
	var area := 0.0
	for ti in tri_count():
		# Dış normale göre saat yönü tersine sıra: v0, v2, v1 (Godot sarımı tersine çevrilir)
		var p0 := verts[tris[ti * 3]]
		var p1 := verts[tris[ti * 3 + 2]]
		var p2 := verts[tris[ti * 3 + 1]]
		var x0 := float(p0.x)
		var y0 := float(p0.y)
		var z0 := float(p0.z)
		var x1 := float(p1.x)
		var y1 := float(p1.y)
		var z1 := float(p1.z)
		var x2 := float(p2.x)
		var y2 := float(p2.y)
		var z2 := float(p2.z)
		var a1 := x1 - x0
		var b1 := y1 - y0
		var c1 := z1 - z0
		var a2 := x2 - x0
		var b2 := y2 - y0
		var c2 := z2 - z0
		var d0 := b1 * c2 - b2 * c1
		var d1 := a2 * c1 - a1 * c2
		var d2 := a1 * b2 - a2 * b1
		area += sqrt(d0 * d0 + d1 * d1 + d2 * d2) * 0.5
		var sx := _subexp(x0, x1, x2)
		var sy := _subexp(y0, y1, y2)
		var sz := _subexp(z0, z1, z2)
		intg[0] += d0 * float(sx[0])
		intg[1] += d0 * float(sx[1])
		intg[2] += d1 * float(sy[1])
		intg[3] += d2 * float(sz[1])
		intg[4] += d0 * float(sx[2])
		intg[5] += d1 * float(sy[2])
		intg[6] += d2 * float(sz[2])
		intg[7] += d0 * (y0 * float(sx[3]) + y1 * float(sx[4]) + y2 * float(sx[5]))
		intg[8] += d1 * (z0 * float(sy[3]) + z1 * float(sy[4]) + z2 * float(sy[5]))
		intg[9] += d2 * (x0 * float(sz[3]) + x1 * float(sz[4]) + x2 * float(sz[5]))
	var mult := [1.0 / 6.0, 1.0 / 24.0, 1.0 / 24.0, 1.0 / 24.0, 1.0 / 60.0, 1.0 / 60.0, 1.0 / 60.0, 1.0 / 120.0, 1.0 / 120.0, 1.0 / 120.0]
	for i in 10:
		intg[i] *= float(mult[i])
	var vol := intg[0]
	var rho := density_g_cm3 / 1000.0   # g/mm³
	var mass := vol * rho
	var cm := Vector3.ZERO
	var cx := 0.0
	var cy := 0.0
	var cz := 0.0
	if absf(vol) > 1e-12:
		cx = intg[1] / vol
		cy = intg[2] / vol
		cz = intg[3] / vol
		cm = Vector3(cx, cy, cz)
	# Ağırlık merkezine göre atalet (yoğunlukla çarpılmış)
	var ixx := (intg[5] + intg[6] - vol * (cy * cy + cz * cz)) * rho
	var iyy := (intg[4] + intg[6] - vol * (cz * cz + cx * cx)) * rho
	var izz := (intg[4] + intg[5] - vol * (cx * cx + cy * cy)) * rho
	var ixy := -(intg[7] - vol * cx * cy) * rho
	var iyz := -(intg[8] - vol * cy * cz) * rho
	var ixz := -(intg[9] - vol * cz * cx) * rho
	var tensor := [[ixx, ixy, ixz], [ixy, iyy, iyz], [ixz, iyz, izz]]
	return {"volume": vol, "area": area, "mass": mass, "center": cm, "cx": cx, "cy": cy, "cz": cz,
		"tensor": tensor, "principal": principal_moments(tensor)}


## Simetrik 3x3 matrisin özdeğerleri (Jacobi dönüşümleri), küçükten büyüğe.
static func principal_moments(m: Array) -> Array:
	var a := [[float(m[0][0]), float(m[0][1]), float(m[0][2])],
		[float(m[1][0]), float(m[1][1]), float(m[1][2])],
		[float(m[2][0]), float(m[2][1]), float(m[2][2])]]
	for sweep in 50:
		var off := absf(a[0][1]) + absf(a[0][2]) + absf(a[1][2])
		if off < 1e-12 * (absf(a[0][0]) + absf(a[1][1]) + absf(a[2][2]) + 1e-30):
			break
		for pq in [[0, 1], [0, 2], [1, 2]]:
			var p: int = pq[0]
			var q: int = pq[1]
			if absf(a[p][q]) < 1e-300:
				continue
			var theta: float = (float(a[q][q]) - float(a[p][p])) / (2.0 * float(a[p][q]))
			var t := signf(theta) / (absf(theta) + sqrt(theta * theta + 1.0)) if theta != 0.0 else 1.0
			var c := 1.0 / sqrt(t * t + 1.0)
			var s := t * c
			for k in 3:
				var akp: float = a[k][p]
				var akq: float = a[k][q]
				a[k][p] = c * akp - s * akq
				a[k][q] = s * akp + c * akq
			for k in 3:
				var apk: float = a[p][k]
				var aqk: float = a[q][k]
				a[p][k] = c * apk - s * aqk
				a[q][k] = s * apk + c * aqk
	var ev := [float(a[0][0]), float(a[1][1]), float(a[2][2])]
	ev.sort()
	return ev


## Üçgen kümesinin alanı ve sınır uzunluğu (yüz ölçümü için).
func region_area_perimeter(tri_list: PackedInt32Array) -> Vector2:
	var inside := {}
	for ti in tri_list:
		inside[ti] = true
	var area := 0.0
	var perim := 0.0
	for ti in tri_list:
		area += areas[ti]
		for k in 3:
			var i0 := tris[ti * 3 + k]
			var i1 := tris[ti * 3 + (k + 1) % 3]
			var lst: Array = edge_tris.get(_ekey(i0, i1), [])
			var shared := false
			for nb in lst:
				if nb != ti and inside.has(nb):
					shared = true
			if not shared:
				perim += verts[i0].distance_to(verts[i1])
	return Vector2(area, perim)


## Üçgen bölgesinin sınır döngüleri (yüz kenarları), sıralı köşe listeleri olarak.
func region_boundary_loops(tri_list: PackedInt32Array) -> Array:
	var inside := {}
	for ti in tri_list:
		inside[ti] = true
	var nxt := {}
	for ti in tri_list:
		for k in 3:
			var i0 := tris[ti * 3 + k]
			var i1 := tris[ti * 3 + (k + 1) % 3]
			var shared := false
			for nb in edge_tris.get(_ekey(i0, i1), []):
				if nb != ti and inside.has(nb):
					shared = true
			if not shared:
				nxt[i0] = i1
	var loops: Array = []
	var used := {}
	for s in nxt.keys():
		if used.has(s):
			continue
		var loop := PackedVector3Array()
		var cur: int = s
		var guard := 0
		while not used.has(cur) and nxt.has(cur) and guard < 100000:
			used[cur] = true
			loop.append(verts[cur])
			cur = nxt[cur]
			guard += 1
		if loop.size() >= 3:
			loops.append(loop)
	return loops


## Üçgenin köşelerinden verilen noktaya en yakın olanı.
func nearest_vertex_of(tri: int, p: Vector3) -> Vector3:
	var best := verts[tris[tri * 3]]
	for k in range(1, 3):
		var v := verts[tris[tri * 3 + k]]
		if v.distance_to(p) < best.distance_to(p):
			best = v
	return best


## Hacim (mm³) ve yüzey alanı (mm²). B-rep çekirdeğinde kesin değerler.
func volume_and_area() -> Vector2:
	if not exact_mass.is_empty():
		return Vector2(float(exact_mass["volume"]), float(exact_mass["area"]))
	var vol := 0.0
	var area := 0.0
	for ti in tri_count():
		var a := verts[tris[ti * 3]]
		var c := verts[tris[ti * 3 + 1]]
		var b := verts[tris[ti * 3 + 2]]
		vol += a.dot(b.cross(c)) / 6.0
		area += (b - a).cross(c - a).length() * 0.5
	return Vector2(vol, area)
