class_name SketchSolver
extends RefCounted
## 2B geometrik kısıt çözücü.
##
## Değişkenler: her noktanın x,y'si ve her dairenin yarıçapı (yaylar noktalarla tanımlıdır).
## Her kısıt bir veya iki denklem (artık = 0) üretir. Çözüm, ağırlıklı en küçük değişimli
## Levenberg-Marquardt adımlarıyla bulunur:  dx = -D Jᵀ (J D Jᵀ + λI)⁻¹ F,  D = diag(1/ağırlık)
## Böylece kısıtsız geometri olabildiğince yerinde kalır; sürüklenen nokta (yüksek ağırlık)
## fareyi takip eder, diğerleri uyum sağlar.
##
## Analiz: Jakobiyen'in indirgenmiş satır basamak formu ile rank, serbestlik derecesi (DOF)
## ve hangi değişkenlerin tam belirlendiği (tam tanımlı: siyah, eksik tanımlı: mavi) bulunur.

const TOL := 1e-9          # yakınsama (mm / radyan)
const OK_TOL := 1e-6       # çözüm kabul eşiği
const RANK_TOL := 1e-7

var sk: Sketch
var x := PackedFloat64Array()
var w := PackedFloat64Array()
var frozen := PackedByteArray()
var pt_base := {}      # pid -> x dizisindeki indeks (y = indeks+1)
var rad_idx := {}      # daire eid -> yarıçap indeksi (elipste küçük yarı eksen)
var block_idx := {}    # blok id -> tx indeksi (ty = +1, θ = +2)
var eqs: Array = []    # [{f: Callable, v: PackedInt32Array, cid: int}]


## weights: {"points": {pid: ağırlık}, "radii": {eid: ağırlık}}
## skip_cid: bu kısıt hariç tutulur (bağımsızlık testi için)
func _init(p_sk: Sketch, weights := {}, skip_cid := -1) -> void:
	sk = p_sk
	for pid in sk.points:
		var p: Vector2 = sk.points[pid]
		pt_base[pid] = x.size()
		x.append(p.x)
		x.append(p.y)
	for e in sk.entities:
		if e["type"] == "circle":
			rad_idx[e["id"]] = x.size()
			x.append(float(e["r"]))
		elif e["type"] == "ellipse":
			rad_idx[e["id"]] = x.size()
			x.append(float(e["rb"]))
	# Blok değişkenleri: öteleme (tx, ty) ve dönme açısı
	var block_init := {}
	for bid in sk.blocks:
		var bl: Dictionary = sk.blocks[bid]
		var cen := Vector2.ZERO
		var cnt := 0
		for pid in bl["pts"]:
			if sk.points.has(pid):
				cen += sk.points[pid]
				cnt += 1
		if cnt == 0:
			continue
		cen /= cnt
		var sc := 0.0
		var ss := 0.0
		for pid in bl["pts"]:
			if sk.points.has(pid):
				var l: Vector2 = bl["local"].get(pid, Vector2.ZERO)
				var q: Vector2 = (sk.points[pid] as Vector2) - cen
				sc += l.dot(q)
				ss += l.cross(q)
		block_idx[bid] = x.size()
		x.append(cen.x)
		x.append(cen.y)
		x.append(atan2(ss, sc))
	w.resize(x.size())
	w.fill(1.0)
	frozen.resize(x.size())
	frozen.fill(0)
	_freeze_point(Sketch.ORIGIN)
	_build_blocks()
	# Elips küçük ekseni / parabol: örtük denklemler
	for e in sk.entities:
		if e["type"] == "parabola":
			var iv: int = pt_base[e["v"]]
			var i_f: int = pt_base[e["f"]]
			for key in ["a", "b"]:
				var ip: int = pt_base[e[key]]
				_eq(func(v): return _on_parabola(v, iv, i_f, ip), [iv, iv + 1, i_f, i_f + 1, ip, ip + 1], -1)
	var wp: Dictionary = weights.get("points", {})
	for pid in wp:
		if pt_base.has(pid):
			w[pt_base[pid]] = float(wp[pid])
			w[pt_base[pid] + 1] = float(wp[pid])
	var wr: Dictionary = weights.get("radii", {})
	for eid in wr:
		if rad_idx.has(eid):
			w[rad_idx[eid]] = float(wr[eid])
	# Yayın iki ucu aynı çember üzerinde olmalı (örtük kısıt)
	for e in sk.entities:
		if e["type"] == "arc":
			var ic: int = pt_base[e["c"]]
			var ia: int = pt_base[e["a"]]
			var ib: int = pt_base[e["b"]]
			_eq(func(v): return _dist(v, ib, ic) - _dist(v, ia, ic), [ic, ic + 1, ia, ia + 1, ib, ib + 1], -1)
	for c in sk.constraints:
		if int(c["id"]) == skip_cid:
			continue
		_build(c)


func _freeze_point(pid: int) -> void:
	if pt_base.has(pid):
		frozen[pt_base[pid]] = 1
		frozen[pt_base[pid] + 1] = 1


## Blok noktaları: p = T + R(θ)·yerel. Blok içindeki daire/elips yarıçapları da sabitlenir.
func _build_blocks() -> void:
	for bid in block_idx:
		var bl: Dictionary = sk.blocks[bid]
		var bi: int = block_idx[bid]
		for pid in bl["pts"]:
			if not pt_base.has(pid):
				continue
			var ip: int = pt_base[pid]
			var l: Vector2 = bl["local"].get(pid, Vector2.ZERO)
			var lx := l.x
			var ly := l.y
			_eq(func(v): return v[ip] - (v[bi] + cos(v[bi + 2]) * lx - sin(v[bi + 2]) * ly), [ip, bi, bi + 2], -2)
			_eq(func(v): return v[ip + 1] - (v[bi + 1] + sin(v[bi + 2]) * lx + cos(v[bi + 2]) * ly), [ip + 1, bi + 1, bi + 2], -2)
		for eid in bl.get("entities", []):
			if rad_idx.has(eid):
				frozen[rad_idx[eid]] = 1


## Parabol üzerinde olma: w² = 4·f·u (normalize edilmiş)
static func _on_parabola(v: PackedFloat64Array, iv: int, i_f: int, ip: int) -> float:
	var dx := v[i_f] - v[iv]
	var dy := v[i_f + 1] - v[iv + 1]
	var fl := sqrt(dx * dx + dy * dy) + 1e-12
	var ux := dx / fl
	var uy := dy / fl
	var px := v[ip] - v[iv]
	var py := v[ip + 1] - v[iv + 1]
	var u := px * ux + py * uy
	var ww := -px * uy + py * ux
	return (ww * ww - 4.0 * fl * u) / (4.0 * fl)


func _eq(f: Callable, vars: Array, cid: int) -> void:
	eqs.append({"f": f, "v": PackedInt32Array(vars), "cid": cid})


# ---------------------------------------------------------------- geometri yardımcıları (v: değişken dizisi)

static func _dist(v: PackedFloat64Array, i: int, j: int) -> float:
	return sqrt(pow(v[i] - v[j], 2) + pow(v[i + 1] - v[j + 1], 2))


## (b-a) x (p-a) / |b-a| : p'nin ab doğrusuna işaretli uzaklığı
static func _line_dist(v: PackedFloat64Array, ia: int, ib: int, ip: int) -> float:
	var ux := v[ib] - v[ia]
	var uy := v[ib + 1] - v[ia + 1]
	var L := sqrt(ux * ux + uy * uy) + 1e-12
	return (ux * (v[ip + 1] - v[ia + 1]) - uy * (v[ip] - v[ia])) / L


static func _cross_n(v: PackedFloat64Array, ia: int, ib: int, ic: int, id: int) -> float:
	var ux := v[ib] - v[ia]
	var uy := v[ib + 1] - v[ia + 1]
	var wx := v[id] - v[ic]
	var wy := v[id + 1] - v[ic + 1]
	return (ux * wy - uy * wx) / (sqrt(ux * ux + uy * uy) * sqrt(wx * wx + wy * wy) + 1e-12)


static func _dot_n(v: PackedFloat64Array, ia: int, ib: int, ic: int, id: int) -> float:
	var ux := v[ib] - v[ia]
	var uy := v[ib + 1] - v[ia + 1]
	var wx := v[id] - v[ic]
	var wy := v[id + 1] - v[ic + 1]
	return (ux * wx + uy * wy) / (sqrt(ux * ux + uy * uy) * sqrt(wx * wx + wy * wy) + 1e-12)


func _line_idx(eid: int) -> Array:
	var e := sk.get_entity(eid)
	return [pt_base[e["a"]], pt_base[e["b"]]]


## Daire/yay için {c: merkez indeksi, r: Callable(v)->yarıçap, vars: [...]}
func _round_info(eid: int) -> Dictionary:
	var e := sk.get_entity(eid)
	var ic: int = pt_base[e["c"]]
	if e["type"] == "circle" or e["type"] == "ellipse":
		var ir: int = rad_idx[eid]
		return {"c": ic, "r": func(v): return v[ir], "vars": [ir]}
	var ia: int = pt_base[e["a"]]
	return {"c": ic, "r": func(v): return _dist(v, ia, ic), "vars": [ia, ia + 1, ic, ic + 1]}


func _etype(eid: int) -> String:
	return str(sk.get_entity(eid).get("type", ""))


## İki öğenin (çizgi/yay uçları) ortak noktası; yoksa -1.
func _shared_point(e1: int, e2: int) -> int:
	var A := sk.get_entity(e1)
	var B := sk.get_entity(e2)
	if not (Sketch.is_edge(A) and Sketch.is_edge(B)):
		return -1
	for p in Sketch.edge_ends(A):
		if p in Sketch.edge_ends(B):
			return int(p)
	return -1


# ---------------------------------------------------------------- denklemler

func _build(c: Dictionary) -> void:
	var t: String = c["type"]
	var cid: int = c["id"]
	if t == "fix":
		if c.has("p1"):
			_freeze_point(int(c["p1"]))
		if c.has("e1"):
			var e := sk.get_entity(int(c["e1"]))
			for pid in Sketch.entity_point_ids(e):
				_freeze_point(pid)
			if rad_idx.has(int(c["e1"])):
				frozen[rad_idx[int(c["e1"])]] = 1
		return
	if Sketch.is_dimension(c) and bool(c.get("driven", false)):
		return
	var val := float(c.get("value", 0.0))
	match t:
		"horizontal", "vertical":
			var k := 1 if t == "horizontal" else 0
			var i1: int
			var i2: int
			if c.has("e1"):
				var L := _line_idx(int(c["e1"]))
				i1 = L[0]
				i2 = L[1]
			else:
				i1 = pt_base[int(c["p1"])]
				i2 = pt_base[int(c["p2"])]
			_eq(func(v): return v[i1 + k] - v[i2 + k], [i1 + k, i2 + k], cid)
		"parallel", "perpendicular", "collinear":
			var A := _line_idx(int(c["e1"]))
			var B := _line_idx(int(c["e2"]))
			var a: int = A[0]
			var b: int = A[1]
			var cc: int = B[0]
			var d: int = B[1]
			var vars := [a, a + 1, b, b + 1, cc, cc + 1, d, d + 1]
			if t == "perpendicular":
				_eq(func(v): return _dot_n(v, a, b, cc, d), vars, cid)
			else:
				_eq(func(v): return _cross_n(v, a, b, cc, d), vars, cid)
			if t == "collinear":
				_eq(func(v): return _line_dist(v, a, b, cc), [a, a + 1, b, b + 1, cc, cc + 1], cid)
		"equal":
			var e1 := int(c["e1"])
			var e2 := int(c["e2"])
			if _etype(e1) == "line":
				var A2 := _line_idx(e1)
				var B2 := _line_idx(e2)
				var a2: int = A2[0]
				var b2: int = A2[1]
				var c2: int = B2[0]
				var d2: int = B2[1]
				_eq(func(v): return _dist(v, a2, b2) - _dist(v, c2, d2), [a2, a2 + 1, b2, b2 + 1, c2, c2 + 1, d2, d2 + 1], cid)
			else:
				var R1 := _round_info(e1)
				var R2 := _round_info(e2)
				var f1: Callable = R1["r"]
				var f2: Callable = R2["r"]
				_eq(func(v): return f1.call(v) - f2.call(v), R1["vars"] + R2["vars"], cid)
		"concentric":
			var C1: int = _round_info(int(c["e1"]))["c"]
			var C2: int = _round_info(int(c["e2"]))["c"]
			_eq(func(v): return v[C1] - v[C2], [C1, C2], cid)
			_eq(func(v): return v[C1 + 1] - v[C2 + 1], [C1 + 1, C2 + 1], cid)
		"tangent":
			var ea := int(c["e1"])
			var eb := int(c["e2"])
			if _etype(eb) == "line":
				var tmp := ea
				ea = eb
				eb = tmp
			# Not: teğet noktası ortak bir uç noktaysa "mesafe = r" çift köklüdür (Jakobiyen sıfırlanır).
			# Bu durumda diklik (çizgi-yay) veya doğrusallık (yay-yay) denklemi kullanılır.
			var shared := _shared_point(ea, eb)
			if _etype(ea) == "line":
				var L3 := _line_idx(ea)
				var la: int = L3[0]
				var lb: int = L3[1]
				var R := _round_info(eb)
				var rc: int = R["c"]
				var rf: Callable = R["r"]
				if shared >= 0:
					var it: int = pt_base[shared]
					_eq(func(v): return _dot_n(v, la, lb, it, rc), [la, la + 1, lb, lb + 1, it, it + 1, rc, rc + 1], cid)
				else:
					var side := signf(_line_dist(x, la, lb, rc))
					if side == 0.0:
						side = 1.0
					_eq(func(v): return _line_dist(v, la, lb, rc) * side - rf.call(v),
						[la, la + 1, lb, lb + 1, rc, rc + 1] + R["vars"], cid)
			else:
				var Ra := _round_info(ea)
				var Rb := _round_info(eb)
				var ca: int = Ra["c"]
				var cb: int = Rb["c"]
				var fa: Callable = Ra["r"]
				var fb: Callable = Rb["r"]
				if shared >= 0:
					var it2: int = pt_base[shared]
					_eq(func(v): return _cross_n(v, it2, ca, it2, cb), [it2, it2 + 1, ca, ca + 1, cb, cb + 1], cid)
				else:
					var internal := bool(c.get("internal", false))
					var bigger := 1.0 if float(fa.call(x)) >= float(fb.call(x)) else -1.0
					var ftan := func(v) -> float:
						var rr: float = (fa.call(v) - fb.call(v)) * bigger if internal else fa.call(v) + fb.call(v)
						return _dist(v, ca, cb) - rr
					_eq(ftan, [ca, ca + 1, cb, cb + 1] + Ra["vars"] + Rb["vars"], cid)
		"coincident":
			var ip: int = pt_base[int(c["p1"])]
			var eid := int(c["e1"])
			if _etype(eid) == "line":
				var L4 := _line_idx(eid)
				var a4: int = L4[0]
				var b4: int = L4[1]
				_eq(func(v): return _line_dist(v, a4, b4, ip), [a4, a4 + 1, b4, b4 + 1, ip, ip + 1], cid)
			else:
				var R4 := _round_info(eid)
				var c4: int = R4["c"]
				var f4: Callable = R4["r"]
				_eq(func(v): return _dist(v, ip, c4) - f4.call(v), [ip, ip + 1, c4, c4 + 1] + R4["vars"], cid)
		"midpoint":
			var im: int = pt_base[int(c["p1"])]
			var L5 := _line_idx(int(c["e1"]))
			var a5: int = L5[0]
			var b5: int = L5[1]
			_eq(func(v): return v[im] - (v[a5] + v[b5]) * 0.5, [im, a5, b5], cid)
			_eq(func(v): return v[im + 1] - (v[a5 + 1] + v[b5 + 1]) * 0.5, [im + 1, a5 + 1, b5 + 1], cid)
		"symmetric":
			var p1: int = pt_base[int(c["p1"])]
			var p2: int = pt_base[int(c["p2"])]
			var L6 := _line_idx(int(c["e1"]))
			var a6: int = L6[0]
			var b6: int = L6[1]
			var vars6 := [p1, p1 + 1, p2, p2 + 1, a6, a6 + 1, b6, b6 + 1]
			var fs1 := func(v) -> float:
				var ux: float = v[b6] - v[a6]
				var uy: float = v[b6 + 1] - v[a6 + 1]
				var L := sqrt(ux * ux + uy * uy) + 1e-12
				var mx: float = (v[p1] + v[p2]) * 0.5 - v[a6]
				var my: float = (v[p1 + 1] + v[p2 + 1]) * 0.5 - v[a6 + 1]
				return (ux * my - uy * mx) / L
			var fs2 := func(v) -> float:
				var ux: float = v[b6] - v[a6]
				var uy: float = v[b6 + 1] - v[a6 + 1]
				var L := sqrt(ux * ux + uy * uy) + 1e-12
				return ((v[p2] - v[p1]) * ux + (v[p2 + 1] - v[p1 + 1]) * uy) / L
			_eq(fs1, vars6, cid)
			_eq(fs2, vars6, cid)
		"offset":
			# Ofset ilişkisi: yeni öğe, orijinalden "value" (veya ana boyutun değeri) kadar uzakta
			var ov := val
			if c.has("master"):
				var mc := sk.get_constraint(int(c["master"]))
				if not mc.is_empty():
					ov = float(mc.get("value", val))
			var osg := float(c.get("s", 1.0))
			var ne := int(c["e1"])
			var oe := int(c["e2"])
			if _etype(ne) == "line":
				var NL := _line_idx(ne)
				var OL := _line_idx(oe)
				var na: int = NL[0]
				var nb: int = NL[1]
				var oa: int = OL[0]
				var ob: int = OL[1]
				_eq(func(v): return _line_dist(v, oa, ob, na) * osg - ov, [oa, oa + 1, ob, ob + 1, na, na + 1], cid)
				_eq(func(v): return _line_dist(v, oa, ob, nb) * osg - ov, [oa, oa + 1, ob, ob + 1, nb, nb + 1], cid)
			else:
				var RN := _round_info(ne)
				var RO := _round_info(oe)
				var rn: Callable = RN["r"]
				var ro: Callable = RO["r"]
				_eq(func(v): return rn.call(v) - ro.call(v) - osg * ov, RN["vars"] + RO["vars"], cid)
		"distance":
			var q1: int = pt_base[int(c["p1"])]
			var q2: int = pt_base[int(c["p2"])]
			_eq(func(v): return _dist(v, q1, q2) - val, [q1, q1 + 1, q2, q2 + 1], cid)
		"hdistance", "vdistance":
			var k2 := 0 if t == "hdistance" else 1
			var h1: int = pt_base[int(c["p1"])] + k2
			var h2: int = pt_base[int(c["p2"])] + k2
			var sg := float(c.get("s", 1.0))
			_eq(func(v): return (v[h2] - v[h1]) * sg - val, [h1, h2], cid)
		"pl_distance":
			var pp: int = pt_base[int(c["p1"])]
			var L7 := _line_idx(int(c["e1"]))
			var a7: int = L7[0]
			var b7: int = L7[1]
			var sg2 := float(c.get("s", 1.0))
			_eq(func(v): return _line_dist(v, a7, b7, pp) * sg2 - val, [pp, pp + 1, a7, a7 + 1, b7, b7 + 1], cid)
		"radius", "diameter":
			var R8 := _round_info(int(c["e1"]))
			var f8: Callable = R8["r"]
			var mul := 2.0 if t == "diameter" else 1.0
			_eq(func(v): return f8.call(v) * mul - val, R8["vars"], cid)
		"angle":
			var A9 := _line_idx(int(c["e1"]))
			var B9 := _line_idx(int(c["e2"]))
			var a9: int = A9[0]
			var b9: int = A9[1]
			var c9: int = B9[0]
			var d9: int = B9[1]
			var su := float(c.get("su", 1.0))
			var sv := float(c.get("sv", 1.0))
			var s9 := float(c.get("s", 1.0))
			var target := deg_to_rad(val) * s9
			var fang := func(v) -> float:
				var ux: float = (v[b9] - v[a9]) * su
				var uy: float = (v[b9 + 1] - v[a9 + 1]) * su
				var wx: float = (v[d9] - v[c9]) * sv
				var wy: float = (v[d9 + 1] - v[c9 + 1]) * sv
				return wrapf(atan2(ux * wy - uy * wx, ux * wx + uy * wy) - target, -PI, PI)
			_eq(fang, [a9, a9 + 1, b9, b9 + 1, c9, c9 + 1, d9, d9 + 1], cid)


# ---------------------------------------------------------------- çözüm

func _eval(v: PackedFloat64Array) -> PackedFloat64Array:
	var f := PackedFloat64Array()
	f.resize(eqs.size())
	for i in eqs.size():
		f[i] = float((eqs[i]["f"] as Callable).call(v))
	return f


static func _maxabs(f: PackedFloat64Array) -> float:
	var m := 0.0
	for a in f:
		m = maxf(m, absf(a))
	return m


static func _sumsq(f: PackedFloat64Array) -> float:
	var s := 0.0
	for a in f:
		s += a * a
	return s


## Seyrek Jakobiyen satırları: [[sütun indeksi (x'teki), türev], ...]
func _jacobian_rows(v: PackedFloat64Array) -> Array:
	var rows: Array = []
	for eq in eqs:
		var f: Callable = eq["f"]
		var row: Array = []
		var seen := {}
		for j in eq["v"]:
			if frozen[j] == 1 or seen.has(j):
				continue
			seen[j] = true
			var old := v[j]
			var h := 1e-7 * (1.0 + absf(old))
			v[j] = old + h
			var fp := float(f.call(v))
			v[j] = old - h
			var fm := float(f.call(v))
			v[j] = old
			var dfdx := (fp - fm) / (2.0 * h)
			if absf(dfdx) > 1e-14:
				row.append([j, dfdx])
		rows.append(row)
	return rows


static func _solve_dense(A: PackedFloat64Array, b: PackedFloat64Array, n: int) -> PackedFloat64Array:
	# Kısmi pivotlu Gauss eliminasyonu (A: n x n, satır öncelikli)
	for col in n:
		var piv := col
		var best := absf(A[col * n + col])
		for r in range(col + 1, n):
			var a := absf(A[r * n + col])
			if a > best:
				best = a
				piv = r
		if best < 1e-300:
			return PackedFloat64Array()
		if piv != col:
			for k in n:
				var t := A[col * n + k]
				A[col * n + k] = A[piv * n + k]
				A[piv * n + k] = t
			var tb := b[col]
			b[col] = b[piv]
			b[piv] = tb
		var d := A[col * n + col]
		for r in range(col + 1, n):
			var fct := A[r * n + col] / d
			if fct == 0.0:
				continue
			for k in range(col, n):
				A[r * n + k] -= fct * A[col * n + k]
			b[r] -= fct * b[col]
	var out := PackedFloat64Array()
	out.resize(n)
	for i in range(n - 1, -1, -1):
		var s := b[i]
		for k in range(i + 1, n):
			s -= A[i * n + k] * out[k]
		out[i] = s / A[i * n + i]
	return out


## Çözer. Başarılıysa x güncellenir (sketch'e yazmak için apply() çağrılır).
func solve(max_iter := 60) -> Dictionary:
	var m := eqs.size()
	if m == 0:
		return {"ok": true, "err": 0.0, "iter": 0}
	var f := _eval(x)
	var err := _maxabs(f)
	var lam := 1e-10
	var it := 0
	while it < max_iter:
		if err < TOL:
			break
		it += 1
		var rows := _jacobian_rows(x)
		# A = J D Jᵀ
		var A := PackedFloat64Array()
		A.resize(m * m)
		var maps: Array = []
		for r in rows:
			var dct := {}
			for pr in r:
				dct[pr[0]] = pr[1]
			maps.append(dct)
		for i in m:
			for k in range(i, m):
				var s := 0.0
				var small: Dictionary = maps[i]
				var other: Dictionary = maps[k]
				if small.size() > other.size():
					small = maps[k]
					other = maps[i]
				for j in small:
					if other.has(j):
						s += float(small[j]) * float(other[j]) / w[j]
				A[i * m + k] = s
				A[k * m + i] = s
		var trace := 0.0
		for i in m:
			trace += A[i * m + i]
		var scale := maxf(trace / m, 1e-12)
		var improved := false
		var f2 := _sumsq(f)
		for attempt in 12:
			var Areg := A.duplicate()
			for i in m:
				Areg[i * m + i] += lam * scale
			var y := _solve_dense(Areg, f.duplicate(), m)
			if y.is_empty():
				lam *= 10.0
				continue
			var xn := x.duplicate()
			for i in m:
				if y[i] == 0.0:
					continue
				for pr in rows[i]:
					var j: int = pr[0]
					xn[j] -= float(pr[1]) * y[i] / w[j]
			var fn := _eval(xn)
			if _sumsq(fn) < f2:
				x = xn
				f = fn
				err = _maxabs(f)
				lam = maxf(lam * 0.1, 1e-14)
				improved = true
				break
			lam *= 10.0
		if not improved:
			break
	return {"ok": err < OK_TOL, "err": err, "iter": it}


## Çözümü taslağa yazar.
func apply() -> void:
	for pid in pt_base:
		var i: int = pt_base[pid]
		if pid == Sketch.ORIGIN:
			continue
		sk.points[pid] = Vector2(x[i], x[i + 1])
	for e in sk.entities:
		if e["type"] == "circle" and rad_idx.has(e["id"]):
			e["r"] = maxf(x[rad_idx[e["id"]]], 1e-6)
		elif e["type"] == "ellipse" and rad_idx.has(e["id"]):
			e["rb"] = maxf(x[rad_idx[e["id"]]], 1e-6)


# ---------------------------------------------------------------- analiz

## Rank, DOF ve belirlenmiş değişkenler.
func analyze() -> Dictionary:
	var free: Array = []
	var col_of := {}
	for j in x.size():
		if frozen[j] == 0:
			col_of[j] = free.size()
			free.append(j)
	var n := free.size()
	var m := eqs.size()
	var J := PackedFloat64Array()
	J.resize(m * n)
	J.fill(0.0)
	var rows := _jacobian_rows(x.duplicate())
	for i in m:
		var mx := 0.0
		for pr in rows[i]:
			mx = maxf(mx, absf(float(pr[1])))
		if mx <= 0.0:
			continue
		for pr in rows[i]:
			if col_of.has(pr[0]):
				J[i * n + int(col_of[pr[0]])] = float(pr[1]) / mx
	# İndirgenmiş satır basamak formu
	var pivot_cols: Array = []
	var row := 0
	for col in n:
		if row >= m:
			break
		var piv := row
		var best := absf(J[row * n + col])
		for r in range(row + 1, m):
			var a := absf(J[r * n + col])
			if a > best:
				best = a
				piv = r
		if best < RANK_TOL:
			continue
		if piv != row:
			for k in n:
				var t := J[row * n + k]
				J[row * n + k] = J[piv * n + k]
				J[piv * n + k] = t
		var d := J[row * n + col]
		for k in n:
			J[row * n + k] /= d
		for r in m:
			if r == row:
				continue
			var fct := J[r * n + col]
			if absf(fct) < 1e-300:
				continue
			for k in n:
				J[r * n + k] -= fct * J[row * n + k]
		pivot_cols.append(col)
		row += 1
	var rank := row
	var pivot_set := {}
	for pc in pivot_cols:
		pivot_set[pc] = true
	var determined := {}   # x indeksi -> true
	for j in x.size():
		if frozen[j] == 1:
			determined[j] = true
	for i in pivot_cols.size():
		var pc: int = pivot_cols[i]
		var ok := true
		for k in n:
			if not pivot_set.has(k) and absf(J[i * n + k]) > 1e-6:
				ok = false
				break
		if ok:
			determined[free[pc]] = true
	var pstat := {}
	for pid in pt_base:
		var b: int = pt_base[pid]
		pstat[pid] = determined.has(b) and determined.has(b + 1)
	var estat := {}
	for e in sk.entities:
		var full := true
		for pid in Sketch.entity_point_ids(e):
			if not pstat.get(pid, false):
				full = false
		if (e["type"] == "circle" or e["type"] == "ellipse") and not determined.has(rad_idx[e["id"]]):
			full = false
		estat[e["id"]] = full
	var resid := _maxabs(_eval(x))
	# Tüm değişkenleri sabit (dondurulmuş) denklemler rank'a katkı vermez; fazlalık sayılmaz
	var active := 0
	for i in m:
		var has_free := false
		for j in eqs[i]["v"]:
			if frozen[j] == 0:
				has_free = true
				break
		if has_free:
			active += 1
	var status := "under"
	if resid > OK_TOL * 100.0 or rank < active:
		status = "over"
	elif n - rank == 0:
		status = "full"
	return {"dof": n - rank, "rank": rank, "eqs": m, "status": status, "points": pstat, "entities": estat}


# ---------------------------------------------------------------- kolay kullanım

## Taslağı çözer ve sonucu yazar. Başarı döner.
static func solve_sketch(p_sk: Sketch, weights := {}) -> bool:
	var s := SketchSolver.new(p_sk, weights)
	var r := s.solve()
	if r["ok"]:
		s.apply()
	return r["ok"]


static func analyze_sketch(p_sk: Sketch) -> Dictionary:
	return SketchSolver.new(p_sk).analyze()


## Kısıt bağımsız mı (taslağı aşırı tanımlamıyor mu)?
static func is_independent(p_sk: Sketch, cid: int) -> bool:
	var with := SketchSolver.new(p_sk)
	var without := SketchSolver.new(p_sk, {}, cid)
	var c := p_sk.get_constraint(cid)
	if c.get("type", "") == "fix":
		# Sabitleme: dondurulan değişkenler zaten belirlenmişse gereksizdir
		var a_without := without.analyze()
		var pids: Array = []
		if c.has("p1"):
			pids.append(int(c["p1"]))
		if c.has("e1"):
			pids.append_array(Sketch.entity_point_ids(p_sk.get_entity(int(c["e1"]))))
		for pid in pids:
			if not a_without["points"].get(pid, false):
				return true
		return false
	var n_eq := 0
	for eq in with.eqs:
		if eq["cid"] == cid:
			n_eq += 1
	if n_eq == 0:
		return true
	return with.analyze()["rank"] - without.analyze()["rank"] == n_eq


# ---------------------------------------------------------------- boyut ölçümü / oluşturma

## Boyutun geometrideki güncel değeri (mm veya derece, işaretsiz).
static func measure(p_sk: Sketch, c: Dictionary) -> float:
	var t: String = c["type"]
	match t:
		"distance":
			return (p_sk.points[int(c["p1"])] as Vector2).distance_to(p_sk.points[int(c["p2"])])
		"hdistance":
			return absf((p_sk.points[int(c["p2"])] as Vector2).x - (p_sk.points[int(c["p1"])] as Vector2).x)
		"vdistance":
			return absf((p_sk.points[int(c["p2"])] as Vector2).y - (p_sk.points[int(c["p1"])] as Vector2).y)
		"pl_distance":
			return absf(signed_line_dist(p_sk, int(c["e1"]), p_sk.points[int(c["p1"])]))
		"radius":
			return p_sk.entity_radius(p_sk.get_entity(int(c["e1"])))
		"diameter":
			return p_sk.entity_radius(p_sk.get_entity(int(c["e1"]))) * 2.0
		"angle":
			var u := line_dir(p_sk, int(c["e1"])) * float(c.get("su", 1.0))
			var v := line_dir(p_sk, int(c["e2"])) * float(c.get("sv", 1.0))
			return rad_to_deg(absf(atan2(u.cross(v), u.dot(v))))
	return 0.0


static func line_dir(p_sk: Sketch, eid: int) -> Vector2:
	var e := p_sk.get_entity(eid)
	return (p_sk.points[e["b"]] as Vector2) - (p_sk.points[e["a"]] as Vector2)


static func signed_line_dist(p_sk: Sketch, eid: int, p: Vector2) -> float:
	var e := p_sk.get_entity(eid)
	var a: Vector2 = p_sk.points[e["a"]]
	var u: Vector2 = (p_sk.points[e["b"]] as Vector2) - a
	return u.cross(p - a) / maxf(u.length(), 1e-12)


## İki doğrunun (sonsuz) kesişimi; paralelse null.
static func line_intersection(p_sk: Sketch, e1: int, e2: int) -> Variant:
	var A := p_sk.get_entity(e1)
	var B := p_sk.get_entity(e2)
	return Geometry2D.line_intersects_line(p_sk.points[A["a"]], line_dir(p_sk, e1), p_sk.points[B["a"]], line_dir(p_sk, e2))


## Boyut kısıtı oluşturur: değer ve işaretler güncel geometriden alınır (geometri değişmez).
## spec: {type, p1?, p2?, e1?, e2?}   label: etiketin taslak koordinatındaki yeri
static func make_dimension(p_sk: Sketch, spec: Dictionary, label: Vector2) -> Dictionary:
	var c := spec.duplicate()
	var t: String = c["type"]
	match t:
		"hdistance":
			var dx := (p_sk.points[int(c["p2"])] as Vector2).x - (p_sk.points[int(c["p1"])] as Vector2).x
			c["s"] = 1.0 if dx >= 0.0 else -1.0
		"vdistance":
			var dy := (p_sk.points[int(c["p2"])] as Vector2).y - (p_sk.points[int(c["p1"])] as Vector2).y
			c["s"] = 1.0 if dy >= 0.0 else -1.0
		"pl_distance":
			var sd := signed_line_dist(p_sk, int(c["e1"]), p_sk.points[int(c["p1"])])
			c["s"] = 1.0 if sd >= 0.0 else -1.0
		"angle":
			var ip = line_intersection(p_sk, int(c["e1"]), int(c["e2"]))
			var I: Vector2 = ip if ip != null else Vector2.ZERO
			var q := label - I
			var u := line_dir(p_sk, int(c["e1"]))
			var v := line_dir(p_sk, int(c["e2"]))
			c["su"] = 1.0 if q.dot(u) >= 0.0 else -1.0
			c["sv"] = 1.0 if q.dot(v) >= 0.0 else -1.0
			var uu := u * float(c["su"])
			var vv := v * float(c["sv"])
			c["s"] = 1.0 if uu.cross(vv) >= 0.0 else -1.0
	c["value"] = measure(p_sk, c)
	c["driven"] = false
	c["off"] = label - dimension_anchor(p_sk, c)
	return c


## Boyut etiketinin bağlı olduğu nokta (etiket ofseti buna göredir).
static func dimension_anchor(p_sk: Sketch, c: Dictionary) -> Vector2:
	match str(c["type"]):
		"distance", "hdistance", "vdistance":
			return ((p_sk.points[int(c["p1"])] as Vector2) + (p_sk.points[int(c["p2"])] as Vector2)) * 0.5
		"pl_distance":
			var p: Vector2 = p_sk.points[int(c["p1"])]
			var e := p_sk.get_entity(int(c["e1"]))
			var a: Vector2 = p_sk.points[e["a"]]
			var u := line_dir(p_sk, int(c["e1"])).normalized()
			var foot := a + u * (p - a).dot(u)
			return (p + foot) * 0.5
		"radius", "diameter":
			return p_sk.points[p_sk.get_entity(int(c["e1"]))["c"]]
		"angle":
			var ip = line_intersection(p_sk, int(c["e1"]), int(c["e2"]))
			return ip if ip != null else Vector2.ZERO
	return Vector2.ZERO
