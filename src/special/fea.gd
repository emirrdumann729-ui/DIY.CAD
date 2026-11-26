class_name Fea
extends RefCounted
## Doğrusal statik analiz (Faz 8): istek hazırlama, sonuç örnekleme ve renk haritalı ağ.
## Çözüm sunucuda: vokselli hex8 (uyumsuz modlu) elemanlar, seyrek doğrudan çözücü (scipy).
## Birimler: mm, N, MPa.

## Malzeme: [E (GPa), Poisson, akma (MPa)]
const MECH := {
	"Düz Karbon Çelik (AISI 1020)": [205.0, 0.29, 350.0], "Paslanmaz Çelik (AISI 304)": [193.0, 0.29, 215.0],
	"Dökme Demir (Gri)": [110.0, 0.26, 150.0], "Alüminyum 6061": [69.0, 0.33, 275.0], "Alüminyum 7075": [72.0, 0.33, 503.0],
	"Pirinç": [100.0, 0.34, 200.0], "Bakır": [117.0, 0.34, 70.0], "Bronz": [110.0, 0.34, 240.0],
	"Titanyum (Ti-6Al-4V)": [114.0, 0.34, 880.0], "PLA": [3.5, 0.36, 50.0], "ABS": [2.2, 0.35, 40.0], "PETG": [2.1, 0.38, 50.0],
	"TPU (esnek)": [0.03, 0.45, 10.0], "Naylon (PA12)": [1.7, 0.39, 48.0], "Akrilik (PMMA)": [3.2, 0.37, 70.0],
	"Polikarbonat (PC)": [2.4, 0.37, 62.0], "POM (Delrin)": [3.0, 0.35, 65.0], "Meşe": [11.0, 0.3, 40.0], "Çam": [9.0, 0.3, 35.0],
	"Kontrplak (Huş)": [8.0, 0.3, 30.0], "MDF": [3.5, 0.25, 15.0],
}
const DIRS := {"normal": "Yüze dik (bastırma)", "x": "+X", "-x": "−X", "y": "+Y", "-y": "−Y", "z": "+Z", "-z": "−Z"}


static func mech_of(material: String) -> Array:
	return MECH.get(material, MECH["Düz Karbon Çelik (AISI 1020)"])


static func force_vector(ld: Dictionary) -> Array:
	var mag := float(ld.get("mag", 100.0))
	var v := Vector3.ZERO
	match str(ld.get("dir", "normal")):
		"normal":
			var n := Vector3(ld["face"]["n"][0], ld["face"]["n"][1], ld["face"]["n"][2]).normalized()
			v = -n
		"x":
			v = Vector3.RIGHT
		"-x":
			v = Vector3.LEFT
		"y":
			v = Vector3.UP
		"-y":
			v = Vector3.DOWN
		"z":
			v = Vector3.BACK
		"-z":
			v = Vector3.FORWARD
	v *= mag
	return [v.x, v.y, v.z]


static func request(st: Dictionary) -> Dictionary:
	var loads: Array = []
	for ld in st.get("loads", []):
		loads.append({"face": ld["face"], "force": force_vector(ld)})
	return {"E": float(st["E"]) * 1000.0, "nu": float(st["nu"]), "elements": int(st.get("elements", 6000)),
		"fixtures": st.get("fix", []), "loads": loads}


## Sonuç ızgarası çözümleme: {origin, h (Vector3), dims, vm (PackedFloat32Array), disp (PackedFloat32Array)}
static func parse(res: Dictionary) -> Dictionary:
	var out := res.duplicate()
	out["vm_arr"] = Marshalls.base64_to_raw(str(res["vm"])).to_float32_array()
	out["disp_arr"] = Marshalls.base64_to_raw(str(res["disp"])).to_float32_array()
	var h: Array = res["h"]
	out["hv"] = Vector3(float(h[0]), float(h[1]), float(h[2]))
	out["ov"] = Vector3(float(res["origin"][0]), float(res["origin"][1]), float(res["origin"][2]))
	return out


static func _elem_value(r: Dictionary, p: Vector3) -> float:
	var dims: Array = r["dims"]
	var nx := int(dims[0])
	var ny := int(dims[1])
	var nz := int(dims[2])
	var q: Vector3 = (p - (r["ov"] as Vector3)) / (r["hv"] as Vector3)
	var i := clampi(int(floor(q.x)), 0, nx - 1)
	var j := clampi(int(floor(q.y)), 0, ny - 1)
	var k := clampi(int(floor(q.z)), 0, nz - 1)
	var vm: PackedFloat32Array = r["vm_arr"]
	var v := vm[(i * ny + j) * nz + k]
	if v >= 0.0:
		return v
	# Yüzeydeki nokta boş voksele düşebilir: komşulardan en yakını
	var best := -1.0
	var bd := INF
	for di in range(-1, 2):
		for dj in range(-1, 2):
			for dk in range(-1, 2):
				var ii := i + di
				var jj := j + dj
				var kk := k + dk
				if ii < 0 or jj < 0 or kk < 0 or ii >= nx or jj >= ny or kk >= nz:
					continue
				var vv := vm[(ii * ny + jj) * nz + kk]
				if vv < 0.0:
					continue
				var c: Vector3 = (r["ov"] as Vector3) + (Vector3(ii, jj, kk) + Vector3(0.5, 0.5, 0.5)) * (r["hv"] as Vector3)
				var dd := c.distance_squared_to(p)
				if dd < bd:
					bd = dd
					best = vv
	return maxf(best, 0.0)


## Izgara düğüm yer değiştirmesi (üç doğrusal)
static func disp_at(r: Dictionary, p: Vector3) -> Vector3:
	var dims: Array = r["dims"]
	var nx := int(dims[0]) + 1
	var ny := int(dims[1]) + 1
	var nz := int(dims[2]) + 1
	var q: Vector3 = (p - (r["ov"] as Vector3)) / (r["hv"] as Vector3)
	var i := clampi(int(floor(q.x)), 0, nx - 2)
	var j := clampi(int(floor(q.y)), 0, ny - 2)
	var k := clampi(int(floor(q.z)), 0, nz - 2)
	var f := Vector3(clampf(q.x - i, 0, 1), clampf(q.y - j, 0, 1), clampf(q.z - k, 0, 1))
	var D: PackedFloat32Array = r["disp_arr"]
	var acc := Vector3.ZERO
	var wsum := 0.0
	for c in 8:
		var a := c & 1
		var b := (c >> 1) & 1
		var e := (c >> 2) & 1
		var w := (f.x if a else 1.0 - f.x) * (f.y if b else 1.0 - f.y) * (f.z if e else 1.0 - f.z)
		var idx := ((i + a) * ny + (j + b)) * nz + (k + e)
		var v := Vector3(D[idx * 3], D[idx * 3 + 1], D[idx * 3 + 2])
		if v != Vector3.ZERO or w > 0.99:
			acc += v * w
			wsum += w
	return acc / wsum if wsum > 1e-9 else Vector3.ZERO


static func ramp(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	var stops := [Color(0.1, 0.2, 0.9), Color(0.0, 0.75, 0.95), Color(0.1, 0.85, 0.2), Color(0.98, 0.9, 0.1), Color(0.95, 0.15, 0.1)]
	var s := t * (stops.size() - 1)
	var i := mini(int(s), stops.size() - 2)
	return (stops[i] as Color).lerp(stops[i + 1], s - i)


## Renkli sonuç ağı. mode: "vm" | "disp"; scale: şekil değiştirme büyütmesi.
## Model üçgenleri eleman boyuna göre alt üçgenlere bölünür (iri üçgenlerde renk enterpolasyonu yanıltmasın).
static func colored_mesh(model: ModelMesh, r: Dictionary, mode: String, scale: float, max_tris := 160000) -> Dictionary:
	var hv: Vector3 = r["hv"]
	var step := minf(hv.x, minf(hv.y, hv.z)) * 0.8
	var est := 0.0
	for ti in model.tri_count():
		var n0 := ceilf(_max_edge(model, ti) / step)
		est += n0 * n0
	if est > max_tris:
		step *= sqrt(est / max_tris)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var vals := PackedFloat32Array()
	var lo := INF
	var hi := -INF
	for ti in model.tri_count():
		var a := model.verts[model.tris[ti * 3]]
		var b := model.verts[model.tris[ti * 3 + 1]]
		var c := model.verts[model.tris[ti * 3 + 2]]
		var fn := model.normals[ti]
		var n := clampi(int(ceil(_max_edge(model, ti) / step)), 1, 128)
		var gp := PackedVector3Array()
		var gv := PackedFloat32Array()
		for i in n + 1:
			for j in n + 1 - i:
				var p := a + (b - a) * (float(i) / n) + (c - a) * (float(j) / n)
				var dv := disp_at(r, p)
				var v := dv.length() if mode == "disp" else _elem_value(r, p)
				gp.append(p + dv * scale)
				gv.append(v)
				lo = minf(lo, v)
				hi = maxf(hi, v)
		for i in n:
			for j in n - i:
				var i0 := _gidx(n, i, j)
				var i1 := _gidx(n, i + 1, j)
				var i2 := _gidx(n, i, j + 1)
				_push_tri(pos, nrm, vals, gp, gv, i0, i1, i2, fn)
				if j < n - i - 1:
					_push_tri(pos, nrm, vals, gp, gv, i1, _gidx(n, i + 1, j + 1), i2, fn)
	lo = 0.0
	if mode == "vm":
		hi = maxf(hi, float(r.get("vm_max", hi)))
	else:
		hi = maxf(hi, float(r.get("u_max", hi)))
	var span := maxf(hi - lo, 1e-12)
	var col := PackedColorArray()
	col.resize(vals.size())
	for k in vals.size():
		col[k] = ramp((vals[k] - lo) / span)
	var am := ArrayMesh.new()
	if not pos.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_COLOR] = col
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return {"mesh": am, "min": lo, "max": hi, "tris": pos.size() / 3}


static func _max_edge(model: ModelMesh, ti: int) -> float:
	var a := model.verts[model.tris[ti * 3]]
	var b := model.verts[model.tris[ti * 3 + 1]]
	var c := model.verts[model.tris[ti * 3 + 2]]
	return maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a)))


## Üçgensel ızgarada (i, j) düğümünün sırası (i + j <= n)
static func _gidx(n: int, i: int, j: int) -> int:
	return i * (n + 1) - ((i * (i - 1)) >> 1) + j


static func _push_tri(pos: PackedVector3Array, nrm: PackedVector3Array, vals: PackedFloat32Array, gp: PackedVector3Array,
		gv: PackedFloat32Array, i0: int, i1: int, i2: int, fn: Vector3) -> void:
	var nn := (gp[i1] - gp[i0]).cross(gp[i2] - gp[i0])
	if nn.length_squared() < 1e-20:
		nn = fn
	nn = nn.normalized()
	if nn.dot(fn) < 0.0:
		nn = -nn
	pos.append(gp[i0])
	pos.append(gp[i1])
	pos.append(gp[i2])
	nrm.append(nn)
	nrm.append(nn)
	nrm.append(nn)
	vals.append(gv[i0])
	vals.append(gv[i1])
	vals.append(gv[i2])


## Üçgen renkleriyle ağ (kalıp analizi)
static func tri_color_mesh(model: ModelMesh, colors: PackedColorArray) -> ArrayMesh:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	for ti in model.tri_count():
		for k in 3:
			pos.append(model.verts[model.tris[ti * 3 + k]])
			nrm.append(model.normals[ti])
			col.append(colors[ti])
	var am := ArrayMesh.new()
	if not pos.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_COLOR] = col
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


## Eğim (çekme açısı) analizi: üçgen renkleri, ayırma çizgisi kenarları ve alan oranları
static func draft_analysis(model: ModelMesh, pull: Vector3, min_deg: float) -> Dictionary:
	var colors := PackedColorArray()
	colors.resize(model.tri_count())
	var areas := {"pos": 0.0, "neg": 0.0, "need": 0.0}
	var sgn := PackedInt32Array()
	sgn.resize(model.tri_count())
	for ti in model.tri_count():
		var a := rad_to_deg(asin(clampf(model.normals[ti].dot(pull), -1.0, 1.0)))
		var ar := model.areas[ti]
		if a > min_deg:
			colors[ti] = Color(0.2, 0.8, 0.3)
			areas["pos"] += ar
			sgn[ti] = 1
		elif a < -min_deg:
			colors[ti] = Color(0.9, 0.25, 0.2)
			areas["neg"] += ar
			sgn[ti] = -1
		else:
			colors[ti] = Color(0.98, 0.85, 0.15)
			areas["need"] += ar
			sgn[ti] = 0
	# Ayırma çizgisi: yönü pozitiften negatife geçen kenarlar (dik duvarlar üzerinden geçişler dahil)
	var lines: Array = []
	for key in model.edge_tris:
		var tl: Array = model.edge_tris[key]
		if tl.size() != 2:
			continue
		var s0: int = sgn[tl[0]]
		var s1: int = sgn[tl[1]]
		if (s0 == 1 and s1 == -1) or (s0 == -1 and s1 == 1) or (s0 != s1 and (s0 == 0 or s1 == 0) and model.normals[tl[0]].dot(model.normals[tl[1]]) < 0.9):
			var shared: Array = []
			for k in 3:
				var a1 := model.tris[int(tl[0]) * 3 + k]
				for k2 in 3:
					if model.tris[int(tl[1]) * 3 + k2] == a1:
						shared.append(a1)
			if shared.size() == 2:
				lines.append([model.verts[shared[0]], model.verts[shared[1]]])
	var tot := maxf(areas["pos"] + areas["neg"] + areas["need"], 1e-12)
	return {"colors": colors, "lines": lines, "pos": areas["pos"] / tot, "neg": areas["neg"] / tot, "need": areas["need"] / tot}
