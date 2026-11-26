class_name MateGeom
extends RefCounted
## Montaj eşleştirme referansları: tıklanan yüz / kenar / ana düzlem → bileşen yerel koordinatında geometri.
## B-rep (OpenCASCADE) varsa yüz türü ve topolojik ad kullanılır; parça değişince ad üzerinden yeniden bulunur.
## CSG'de düzlemsel yüzler ve silindir uydurma (normallerden eksen, en küçük kareler çemberi) kullanılır.

const ORIGIN_REFS := {
	"front": ["Ön Düzlem", {"t": "plane", "p": [0, 0, 0], "n": [0, 0, 1]}],
	"top": ["Üst Düzlem", {"t": "plane", "p": [0, 0, 0], "n": [0, 1, 0]}],
	"right": ["Sağ Düzlem", {"t": "plane", "p": [0, 0, 0], "n": [1, 0, 0]}],
	"origin": ["Orijin", {"t": "point", "p": [0, 0, 0]}],
	"axis_x": ["X Ekseni", {"t": "line", "p": [0, 0, 0], "d": [1, 0, 0]}],
	"axis_y": ["Y Ekseni", {"t": "line", "p": [0, 0, 0], "d": [0, 1, 0]}],
	"axis_z": ["Z Ekseni", {"t": "line", "p": [0, 0, 0], "d": [0, 0, 1]}],
}
const TYPE_NAMES := {"plane": "Düzlemsel yüz", "cyl": "Silindirik yüz", "cone": "Konik yüz", "sphere": "Küresel yüz",
	"line": "Doğrusal kenar", "circle": "Dairesel kenar", "point": "Nokta"}


static func a3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func v3(a: Variant) -> Vector3:
	return MateSolver.v3(a)


## B-rep yüz bilgisinden geometri
static func geo_from_face_info(info: Dictionary) -> Dictionary:
	match str(info.get("type", "")):
		"plane":
			return {"t": "plane", "p": info.get("p", [0, 0, 0]), "n": info.get("n", [0, 0, 1])}
		"cylinder":
			return {"t": "cyl", "p": info.get("o", [0, 0, 0]), "d": info.get("axis", [0, 0, 1]), "r": float(info.get("r", 1.0))}
		"cone":
			return {"t": "cone", "p": info.get("o", [0, 0, 0]), "d": info.get("axis", [0, 0, 1])}
		"sphere":
			return {"t": "sphere", "p": info.get("o", [0, 0, 0]), "r": float(info.get("r", 1.0))}
	return {}


## Tıklanan üçgenin yüzünden referans. Dönüş: {kind: face, name, fid, geo, label} veya {}
static func face_ref(model: ModelMesh, tri: int, hit_local: Vector3) -> Dictionary:
	if tri < 0 or tri >= model.tri_count():
		return {}
	if model.has_brep():
		var fid := model.tri_face[tri]
		var info: Dictionary = model.brep_faces[fid] if fid >= 0 and fid < model.brep_faces.size() else {}
		var g := geo_from_face_info(info)
		if g.is_empty():
			g = {"t": "plane", "p": a3(hit_local), "n": a3(model.normals[tri])}
		return {"kind": "face", "name": str(info.get("name", "")), "fid": fid, "geo": g, "label": TYPE_NAMES.get(g["t"], "Yüz"), "tri": tri}
	var fd := model.planar_face(tri)
	if bool(fd.get("planar", false)):
		var n: Vector3 = fd["normal"]
		return {"kind": "face", "name": "", "fid": -1, "geo": {"t": "plane", "p": a3(fd["point"]), "n": a3(n)}, "label": TYPE_NAMES["plane"], "tri": tri}
	var cyl := fit_cylinder(model, fd["tris"])
	if cyl.is_empty():
		return {"kind": "face", "name": "", "fid": -1, "geo": {"t": "plane", "p": a3(hit_local), "n": a3(model.normals[tri])}, "label": "Yüz", "tri": tri}
	return {"kind": "face", "name": "", "fid": -1, "geo": cyl, "label": TYPE_NAMES["cyl"], "tri": tri}


## Ağ bölgesine silindir uydurur: eksen = normallere dik yön, merkez/yarıçap = çember uydurma.
static func fit_cylinder(model: ModelMesh, tris: PackedInt32Array) -> Dictionary:
	if tris.size() < 4:
		return {}
	var n0 := model.normals[tris[0]]
	var far := n0
	var best := 1.0
	for t in tris:
		var d := model.normals[t].dot(n0)
		if d < best:
			best = d
			far = model.normals[t]
	if best > 0.995:
		return {}
	var axis := n0.cross(far).normalized()
	# İyileştir: eksenle normallerin iç çarpımları sıfıra yakın olmalı
	var acc := Vector3.ZERO
	for i in range(0, tris.size(), maxi(1, tris.size() / 64)):
		for j in range(i + 1, tris.size(), maxi(1, tris.size() / 16)):
			var c := model.normals[tris[i]].cross(model.normals[tris[j]])
			if c.length() > 0.05:
				acc += c if c.dot(axis) >= 0.0 else -c
	if acc.length() > 1e-6:
		axis = acc.normalized()
	var u := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.UP).normalized()
	var v := axis.cross(u)
	# Kasa çember uydurma: x² + y² + D x + E y + F = 0
	var S := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	var R := [0.0, 0.0, 0.0]
	var hsum := 0.0
	for t in tris:
		var c3 := (model.verts[model.tris[t * 3]] + model.verts[model.tris[t * 3 + 1]] + model.verts[model.tris[t * 3 + 2]]) / 3.0
		# Üçgen ağırlık merkezi yüzeyin biraz içindedir: normal yönünde düzelt yok sayılır (küçük hata)
		for k in 3:
			var q := model.verts[model.tris[t * 3 + k]]
			var x := q.dot(u)
			var y := q.dot(v)
			var row := [x, y, 1.0]
			var rhs := -(x * x + y * y)
			for a in 3:
				for b in 3:
					S[a][b] += row[a] * row[b]
				R[a] += row[a] * rhs
		hsum += c3.dot(axis)
	var sol := _solve3(S, R)
	if sol.is_empty():
		return {}
	var cx: float = -sol[0] * 0.5
	var cy: float = -sol[1] * 0.5
	var r2: float = cx * cx + cy * cy - sol[2]
	if r2 <= 0.0:
		return {}
	var h := hsum / tris.size()
	var center := u * cx + v * cy + axis * h
	return {"t": "cyl", "p": a3(center), "d": a3(axis), "r": sqrt(r2)}


static func _solve3(A: Array, b: Array) -> Array:
	var m := [[A[0][0], A[0][1], A[0][2], b[0]], [A[1][0], A[1][1], A[1][2], b[1]], [A[2][0], A[2][1], A[2][2], b[2]]]
	for c in 3:
		var piv := c
		for i in range(c + 1, 3):
			if absf(m[i][c]) > absf(m[piv][c]):
				piv = i
		if absf(m[piv][c]) < 1e-12:
			return []
		var t: Array = m[c]
		m[c] = m[piv]
		m[piv] = t
		for i in 3:
			if i == c:
				continue
			var f: float = m[i][c] / m[c][c]
			for k in range(c, 4):
				m[i][k] -= f * m[c][k]
	return [m[0][3] / m[0][0], m[1][3] / m[1][1], m[2][3] / m[2][2]]


## B-rep kenarından referans
static func edge_ref(model: ModelMesh, eid: int) -> Dictionary:
	if eid < 0 or eid >= model.brep_edges.size():
		return {}
	var e: Dictionary = model.brep_edges[eid]
	var pts: PackedVector3Array = e.get("pts", PackedVector3Array())
	var g := {}
	match str(e.get("type", "")):
		"circle":
			g = {"t": "circle", "p": e.get("o", [0, 0, 0]), "d": e.get("n", [0, 0, 1]), "r": float(e.get("r", 1.0))}
		_:
			if pts.size() < 2:
				return {}
			var a := pts[0]
			var b := pts[pts.size() - 1]
			if a.distance_to(b) < 1e-9:
				return {}
			g = {"t": "line", "p": a3(a), "e": a3(b), "d": a3((b - a).normalized())}
	return {"kind": "edge", "name": JSON.stringify(e.get("fn", [])), "fid": eid, "geo": g, "label": TYPE_NAMES.get(g["t"], "Kenar")}


static func origin_ref(id: String) -> Dictionary:
	var o: Array = ORIGIN_REFS.get(id, ORIGIN_REFS["origin"])
	var g: Dictionary = (o[1] as Dictionary).duplicate(true)
	return {"kind": "plane" if g["t"] == "plane" else ("point" if g["t"] == "point" else "axis"), "name": id, "fid": -1, "geo": g, "label": o[0]}


## Referansın güncel yerel geometrisi: parça değiştiyse topolojik ada göre yeniden bulunur.
static func resolve(ref: Dictionary, model: ModelMesh) -> Dictionary:
	var stored: Dictionary = ref.get("geo", {})
	var kind := str(ref.get("kind", ""))
	if model == null or not model.has_brep() or str(ref.get("name", "")) == "":
		return stored
	if kind == "face":
		var best := {}
		var bd := INF
		for info in model.brep_faces:
			if str(info.get("name", "")) != str(ref["name"]):
				continue
			var g := geo_from_face_info(info)
			if g.is_empty() or g["t"] != stored.get("t", ""):
				continue
			var d := v3(g["p"]).distance_to(v3(stored.get("p", [0, 0, 0])))
			if d < bd:
				bd = d
				best = g
		return best if not best.is_empty() else stored
	if kind == "edge":
		var fid := int(ref.get("fid", -1))
		for e in model.brep_edges:
			if JSON.stringify(e.get("fn", [])) == str(ref["name"]):
				fid = int(e["id"])
				break
		var er := edge_ref(model, fid)
		if not er.is_empty() and er["geo"]["t"] == stored.get("t", ""):
			return er["geo"]
	return stored


## Referansın ekranda gösterilecek kısa açıklaması
static func describe(ref: Dictionary, comp_name: String) -> String:
	return "%s @ %s" % [str(ref.get("label", "?")), comp_name]


## Eşleştirme için uygun türleri öner (seçilen iki referansa göre)
static func suggest_mates(a: Dictionary, b: Dictionary) -> Array:
	var ta := str(a.get("t", ""))
	var tb := str(b.get("t", ""))
	var axis_like := ["cyl", "cone", "line", "circle"]
	if ta == "plane" and tb == "plane":
		return ["coincident", "parallel", "perpendicular", "distance", "angle"]
	if ta in axis_like and tb in axis_like:
		if ta == "cyl" and tb == "cyl":
			return ["concentric", "tangent", "parallel", "perpendicular", "distance", "coincident"]
		return ["concentric", "parallel", "perpendicular", "coincident", "distance", "angle"]
	if (ta == "plane" and tb == "cyl") or (ta == "cyl" and tb == "plane"):
		return ["tangent", "coincident", "parallel", "perpendicular", "distance"]
	if ta == "plane" or tb == "plane":
		return ["coincident", "distance", "parallel", "perpendicular"]
	return ["coincident", "concentric", "distance"]


## Kam profili: tıklanan yüzün teğet (pürüzsüz) bölgesinin, bölgeye dik düzlemle kesiti (bileşen yerel).
## Dönüş: {frame: {o, u, v, d}, profile: [[u, v]...]} veya {} (bölge ekstrüzyon yüzeyi değilse)
static func cam_profile(model: ModelMesh, start_tri: int) -> Dictionary:
	if start_tri < 0 or start_tri >= model.tri_count():
		return {}
	var region := model.smooth_region(start_tri)
	if region.size() < 4:
		return {}
	# Ekstrüzyon yönü: tüm normallere dik
	var n0 := model.normals[region[0]]
	var acc := Vector3.ZERO
	for i in range(0, region.size(), maxi(1, region.size() / 48)):
		for j in range(i + 1, region.size(), maxi(1, region.size() / 12)):
			var c := model.normals[region[i]].cross(model.normals[region[j]])
			if c.length() > 0.05:
				acc += c if c.dot(acc) >= 0.0 else -c
	if acc.length() < 1e-6:
		return {}
	var d := acc.normalized()
	var ctr := Vector3.ZERO
	var lo := INF
	var hi := -INF
	for t in region:
		for k in 3:
			var p := model.verts[model.tris[t * 3 + k]]
			ctr += p
			lo = minf(lo, p.dot(d))
			hi = maxf(hi, p.dot(d))
	ctr /= region.size() * 3.0
	var h := (lo + hi) * 0.5
	var o := ctr + d * (h - ctr.dot(d))
	var u := d.cross(Vector3.RIGHT if absf(d.x) < 0.9 else Vector3.UP).normalized()
	var v := d.cross(u)
	# Üçgen-düzlem kesişim parçaları
	var segs: Array = []
	for t in region:
		var pts: Array = []
		for k in 3:
			var a := model.verts[model.tris[t * 3 + k]]
			var b := model.verts[model.tris[t * 3 + (k + 1) % 3]]
			var da := a.dot(d) - h
			var db := b.dot(d) - h
			if (da < 0.0) != (db < 0.0):
				var q := a.lerp(b, da / (da - db))
				pts.append(Vector2((q - o).dot(u), (q - o).dot(v)))
		if pts.size() == 2:
			segs.append(pts)
	if segs.size() < 3:
		return {}
	# Parçaları zincirle
	var tol := 1e-4 * maxf(1.0, model.aabb.size.length())
	var chain: Array = [segs[0][0], segs[0][1]]
	var used := {0: true}
	var progress := true
	while progress:
		progress = false
		var end: Vector2 = chain[chain.size() - 1]
		for i in segs.size():
			if used.has(i):
				continue
			var s: Array = segs[i]
			if (s[0] as Vector2).distance_to(end) < tol:
				chain.append(s[1])
			elif (s[1] as Vector2).distance_to(end) < tol:
				chain.append(s[0])
			else:
				continue
			used[i] = true
			progress = true
			break
	if (chain[0] as Vector2).distance_to(chain[chain.size() - 1]) < tol:
		chain.pop_back()
	var prof: Array = []
	for p2 in chain:
		prof.append([(p2 as Vector2).x, (p2 as Vector2).y])
	return {"frame": {"o": a3(o), "u": a3(u), "v": a3(v), "d": a3(d)}, "profile": prof}
