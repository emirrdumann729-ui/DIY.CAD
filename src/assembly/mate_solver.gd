class_name MateSolver
extends RefCounted
## Montaj eşleştirme çözücüsü (Faz 7): her serbest bileşen 6 serbestlik derecesine (öteleme + dönme) sahiptir.
## Eşleştirmeler dünya koordinatındaki geometri varlıkları (düzlem, eksen, nokta, küre, daire) üzerinde
## artık (residual) denklemleri üretir; sönümlü Gauss-Newton (Levenberg-Marquardt) ile çözülür.
## Dönme parametreleri bileşen boyutuyla ölçeklenir (mm ile aynı mertebede kalsın diye).
##
## Varlık (dünya): {t: plane|cyl|cone|sphere|line|circle|point, p, n (düzlem), d (eksen), r, e (çizgi sonu)}

const MAX_ITER := 60


# ---------------------------------------------------------------- geometri yardımcıları

static func v3(a: Variant) -> Vector3:
	if a is Vector3:
		return a
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


## Yerel geometriyi dünya koordinatına taşır.
static func to_world(g: Dictionary, xf: Transform3D) -> Dictionary:
	var w := {"t": str(g.get("t", "point"))}
	if g.has("p"):
		w["p"] = xf * v3(g["p"])
	if g.has("e"):
		w["e"] = xf * v3(g["e"])
	if g.has("n"):
		w["n"] = (xf.basis * v3(g["n"])).normalized()
	if g.has("d"):
		w["d"] = (xf.basis * v3(g["d"])).normalized()
	if g.has("r"):
		w["r"] = float(g["r"])
	return w


static func has_axis(e: Dictionary) -> bool:
	return e["t"] in ["cyl", "cone", "line", "circle"]


static func is_plane(e: Dictionary) -> bool:
	return e["t"] == "plane"


static func is_pointlike(e: Dictionary) -> bool:
	return e["t"] in ["point", "sphere"]


## Varlığın temsil noktası (düzlem noktası, eksen noktası, merkez)
static func pt(e: Dictionary) -> Vector3:
	return e.get("p", Vector3.ZERO)


## Yön (düzlem normali veya eksen yönü)
static func dir(e: Dictionary) -> Vector3:
	return e.get("n", e.get("d", Vector3.UP))


static func _perp(p: Vector3, a: Vector3, d: Vector3) -> Vector3:
	var q := p - a
	return q - d * q.dot(d)


static func _par(a: Vector3, b: Vector3) -> Array:
	var c := a.cross(b)
	return [c.x, c.y, c.z]


static func _align(a: Vector3, b: Vector3, aligned: bool) -> Array:
	var c := a - b if aligned else a + b
	return [c.x, c.y, c.z]


static func _vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _line_dist(p1: Vector3, d1: Vector3, p2: Vector3, d2: Vector3) -> float:
	var c := d1.cross(d2)
	if c.length() < 1e-6:
		return _perp(p2, p1, d1).length()
	return absf((p2 - p1).dot(c.normalized()))


static func _angle(a: Vector3, b: Vector3) -> float:
	return atan2(a.cross(b).length(), a.dot(b))


static func _reflect_p(p: Vector3, s: Dictionary) -> Vector3:
	var n: Vector3 = s["n"]
	return p - n * 2.0 * (p - s["p"]).dot(n)


static func _reflect_d(d: Vector3, s: Dictionary) -> Vector3:
	var n: Vector3 = s["n"]
	return d - n * 2.0 * d.dot(n)


## Bileşenin, referans dönüşümüne göre dünya ekseni d etrafındaki dönme açısı (radyan, -π..π).
static func axis_angle(xf: Transform3D, ref: Transform3D, d: Vector3) -> float:
	var q := xf.basis * ref.basis.inverse()
	var u := d.cross(Vector3.RIGHT)
	if u.length() < 0.3:
		u = d.cross(Vector3.UP)
	u = u.normalized()
	var v := q * u
	v = (v - d * v.dot(d))
	if v.length() < 1e-9:
		return 0.0
	return atan2(u.cross(v).dot(d), u.dot(v))


static func _unwrap(raw: float, rt: Dictionary, key: String) -> float:
	if not rt.has(key):
		rt[key] = [raw, raw]   # [son ham açı, son sürekli açı]
		return raw
	var last: Array = rt[key]
	var dlt := wrapf(raw - float(last[0]), -PI, PI)
	return float(last[1]) + dlt


static func _commit_unwrap(rt: Dictionary, key: String, raw: float) -> void:
	if not rt.has(key):
		rt[key] = [raw, raw]
		return
	var last: Array = rt[key]
	rt[key] = [raw, float(last[1]) + wrapf(raw - float(last[0]), -PI, PI)]


# ---------------------------------------------------------------- eşleştirme ölçüleri

## Uzaklık ölçüsü (mesafe ve mesafe sınırı için): işaretli değer
static func distance_value(a: Dictionary, b: Dictionary) -> float:
	if is_plane(a) and is_plane(b):
		return (pt(b) - pt(a)).dot(a["n"])
	if is_plane(a):
		return (pt(b) - pt(a)).dot(a["n"])
	if is_plane(b):
		return (pt(a) - pt(b)).dot(b["n"])
	if has_axis(a) and has_axis(b):
		return _line_dist(pt(a), a["d"], pt(b), b["d"])
	if has_axis(a):
		return _perp(pt(b), pt(a), a["d"]).length()
	if has_axis(b):
		return _perp(pt(a), pt(b), b["d"]).length()
	return pt(a).distance_to(pt(b))


static func angle_value(a: Dictionary, b: Dictionary, flip: bool) -> float:
	var va := dir(a)
	var vb := dir(b) * (-1.0 if flip else 1.0)
	var ang := _angle(va, vb)
	if is_plane(a) != is_plane(b) and (is_plane(a) or is_plane(b)):
		ang = PI * 0.5 - ang   # düzlem-eksen açısı
	return ang


## Tek eşleştirmenin artıkları. E: dünya varlıkları (refs sırasıyla), X: bileşen dönüşümleri, m: eşleştirme
static func mate_residuals(m: Dictionary, E: Array, X: Dictionary) -> Array:
	var t := str(m["type"])
	var a: Dictionary = E[0]
	var b: Dictionary = E[1] if E.size() > 1 else {}
	var aligned := str(m.get("align", "")) == "aligned"
	var s := -1.0 if bool(m.get("flip", false)) else 1.0
	var val := float(m.get("value", 0.0))
	match t:
		"coincident":
			return _coincident(a, b, aligned)
		"concentric":
			return _concentric(a, b)
		"parallel":
			if is_plane(a) and is_plane(b):
				return _par(a["n"], b["n"])
			if is_plane(a) or is_plane(b):
				return [dir(a).dot(dir(b))]
			return _par(dir(a), dir(b))
		"perpendicular":
			if is_plane(a) != is_plane(b) and (is_plane(a) or is_plane(b)):
				return _par(dir(a), dir(b))
			return [dir(a).dot(dir(b))]
		"tangent":
			return _tangent(a, b, s)
		"distance":
			return _distance(a, b, val, s, aligned)
		"angle":
			return [(angle_value(a, b, bool(m.get("flip", false))) - deg_to_rad(val)) * 50.0]
		"lock":
			var ca: Transform3D = X[int(m["refs"][0]["comp"])]
			var cb: Transform3D = X[int(m["refs"][1]["comp"])]
			var rel0 := CadAssembly.xf_from_array(m.get("ref_xf", []))
			var rel := ca.affine_inverse() * cb
			var dq := (rel.basis * rel0.basis.inverse()).get_rotation_quaternion()
			var dv := Vector3(dq.x, dq.y, dq.z) * (100.0 if dq.w >= 0.0 else -100.0)
			var dp := rel.origin - rel0.origin
			return [dp.x, dp.y, dp.z, dv.x, dv.y, dv.z]
		"width":
			var c: Dictionary = E[2]
			var d: Dictionary = E[3]
			var n: Vector3 = c["n"]
			var r2: Array = _par(dir(a), n)
			r2.append(((pt(a) + pt(b)) * 0.5 - (pt(c) + pt(d)) * 0.5).dot(n))
			return r2
		"symmetric":
			var sp: Dictionary = E[2]
			if is_plane(a) and is_plane(b):
				var r3: Array = _align(_reflect_d(a["n"], sp), b["n"], true)
				r3.append((_reflect_p(pt(a), sp) - pt(b)).dot(b["n"]))
				return r3
			if has_axis(a) and has_axis(b):
				var r4: Array = _par(_reflect_d(a["d"], sp), b["d"])
				r4.append_array(_vec(_perp(_reflect_p(pt(a), sp), pt(b), b["d"])))
				return r4
			return _vec(_reflect_p(pt(a), sp) - pt(b))
		"limit_distance":
			var v := distance_value(a, b)
			var lo := minf(float(m.get("min", 0.0)), float(m.get("max", 0.0)))
			var hi := maxf(float(m.get("min", 0.0)), float(m.get("max", 0.0)))
			var r5: Array = []
			if is_plane(a) and is_plane(b):
				r5 = _par(a["n"], b["n"])
			r5.append(v - clampf(v, lo, hi))
			return r5
		"limit_angle":
			var av := angle_value(a, b, bool(m.get("flip", false)))
			var alo := deg_to_rad(minf(float(m.get("min", 0.0)), float(m.get("max", 90.0))))
			var ahi := deg_to_rad(maxf(float(m.get("min", 0.0)), float(m.get("max", 90.0))))
			return [(av - clampf(av, alo, ahi)) * 50.0]
		"hinge":
			var r6 := _concentric(a, b)
			r6.append_array(_coincident(E[2], E[3], str(m.get("align", "")) == "aligned"))
			return r6
		"gear", "rack", "screw", "drive":
			return _mechanical(m, E, X)
		"cam":
			return [_cam_residual(m, a, X)]
		"slot":
			# a: pim (eksen veya nokta), b: kanal orta çizgisi (doğru parçası)
			var lp: Vector3 = pt(b)
			var ld: Vector3 = b["d"]
			var r7: Array = []
			var tp := 0.0
			if has_axis(a):
				var cr: Vector3 = (a["d"] as Vector3).cross(ld)
				if cr.length() > 1e-6:
					r7.append((lp - pt(a)).dot(cr.normalized()))
					# Pim ekseninin kanal doğrusuna en yakın noktasının doğru üzerindeki parametresi
					var w0 := pt(a) - lp
					var bb := (a["d"] as Vector3).dot(ld)
					var dd := (a["d"] as Vector3).dot(w0)
					var ee := ld.dot(w0)
					var den := 1.0 - bb * bb
					tp = (ee - bb * dd) / den if absf(den) > 1e-9 else ee
				else:
					r7.append_array(_vec(_perp(pt(a), lp, ld)))
					tp = (pt(a) - lp).dot(ld)
			else:
				r7.append_array(_vec(_perp(pt(a), lp, ld)))
				tp = (pt(a) - lp).dot(ld)
			var ln := (b.get("e", lp) as Vector3).distance_to(lp)
			if ln > 1e-9:
				r7.append(tp - clampf(tp, 0.0, ln))
			return r7
	return []


static func _coincident(a: Dictionary, b: Dictionary, aligned: bool) -> Array:
	if is_plane(a) and is_plane(b):
		var r: Array = _align(a["n"], b["n"], aligned)
		r.append((pt(b) - pt(a)).dot(a["n"]))
		return r
	if is_plane(b) and not is_plane(a):
		return _coincident(b, a, aligned)
	if is_plane(a):
		var n: Vector3 = a["n"]
		match str(b["t"]):
			"line", "cyl", "cone":
				return [(b["d"] as Vector3).dot(n), (pt(b) - pt(a)).dot(n)]
			"circle":
				var r2: Array = [(pt(b) - pt(a)).dot(n)]
				r2.append_array(_par(b["d"], n))
				return r2
		return [(pt(b) - pt(a)).dot(n)]
	if a["t"] == "line" and b["t"] == "line":
		var r3: Array = _par(a["d"], b["d"])
		r3.append_array(_vec(_perp(pt(b), pt(a), a["d"])))
		return r3
	if a["t"] == "circle" and b["t"] == "circle":
		var r4: Array = _vec(pt(a) - pt(b))
		r4.append_array(_par(a["d"], b["d"]))
		return r4
	if a["t"] in ["line", "cyl", "cone"] and is_pointlike(b):
		return _vec(_perp(pt(b), pt(a), a["d"]))
	if b["t"] in ["line", "cyl", "cone"] and is_pointlike(a):
		return _vec(_perp(pt(a), pt(b), b["d"]))
	if a["t"] == "sphere" and b["t"] == "point":
		return [pt(a).distance_to(pt(b)) - float(a["r"])]
	if b["t"] == "sphere" and a["t"] == "point":
		return [pt(a).distance_to(pt(b)) - float(b["r"])]
	return _vec(pt(a) - pt(b))


static func _concentric(a: Dictionary, b: Dictionary) -> Array:
	if has_axis(a) and has_axis(b):
		var r: Array = _par(a["d"], b["d"])
		r.append_array(_vec(_perp(pt(b), pt(a), a["d"])))
		return r
	if has_axis(a):
		return _vec(_perp(pt(b), pt(a), a["d"]))
	if has_axis(b):
		return _vec(_perp(pt(a), pt(b), b["d"]))
	return _vec(pt(a) - pt(b))


static func _tangent(a: Dictionary, b: Dictionary, s: float) -> Array:
	if is_plane(b) and not is_plane(a):
		return _tangent(b, a, s)
	if is_plane(a):
		var n: Vector3 = a["n"]
		match str(b["t"]):
			"cyl":
				return [(b["d"] as Vector3).dot(n), (pt(b) - pt(a)).dot(n) - s * float(b["r"])]
			"sphere":
				return [(pt(b) - pt(a)).dot(n) - s * float(b["r"])]
		return [(pt(b) - pt(a)).dot(n)]
	if a["t"] == "cyl" and b["t"] == "cyl":
		var r: Array = _par(a["d"], b["d"])
		var want := float(a["r"]) + float(b["r"]) if s > 0 else absf(float(a["r"]) - float(b["r"]))
		r.append(_line_dist(pt(a), a["d"], pt(b), b["d"]) - want)
		return r
	if a["t"] == "sphere" and b["t"] == "sphere":
		var want2 := float(a["r"]) + float(b["r"]) if s > 0 else absf(float(a["r"]) - float(b["r"]))
		return [pt(a).distance_to(pt(b)) - want2]
	if a["t"] == "cyl" and b["t"] == "sphere":
		return [_perp(pt(b), pt(a), a["d"]).length() - (float(a["r"]) + float(b["r"]))]
	if b["t"] == "cyl" and a["t"] == "sphere":
		return [_perp(pt(a), pt(b), b["d"]).length() - (float(a["r"]) + float(b["r"]))]
	return _coincident(a, b, false)


static func _distance(a: Dictionary, b: Dictionary, d: float, s: float, aligned: bool) -> Array:
	if is_plane(a) and is_plane(b):
		var r: Array = _align(a["n"], b["n"], aligned)
		r.append((pt(b) - pt(a)).dot(a["n"]) - s * d)
		return r
	if is_plane(b) and not is_plane(a):
		return _distance(b, a, d, s, aligned)
	if is_plane(a):
		var n: Vector3 = a["n"]
		var r2: Array = []
		if has_axis(b):
			r2.append((b["d"] as Vector3).dot(n) if b["t"] != "circle" else 0.0)
			if b["t"] == "circle":
				r2 = _par(b["d"], n)
		r2.append((pt(b) - pt(a)).dot(n) - s * d)
		return r2
	if has_axis(a) and has_axis(b):
		var r3: Array = _par(a["d"], b["d"])
		r3.append(_line_dist(pt(a), a["d"], pt(b), b["d"]) - d)
		return r3
	return [distance_value(a, b) - d]


## Mekanik eşleştirmeler: açılar bileşenlerin eşleştirme oluşturulurken kaydedilen dönüşümlerine göre ölçülür.
static func _mechanical(m: Dictionary, E: Array, X: Dictionary) -> Array:
	var refs: Array = m["refs"]
	var ca := int(refs[0]["comp"])
	var cb := int(refs[1]["comp"]) if refs.size() > 1 else ca
	var r0: Dictionary = m.get("ref_xf", {})
	var xa0 := CadAssembly.xf_from_array(r0.get(str(ca), []))
	var xb0 := CadAssembly.xf_from_array(r0.get(str(cb), []))
	var rt: Dictionary = m.get("_rt", {})
	var a: Dictionary = E[0]
	var s := -1.0 if bool(m.get("flip", false)) else 1.0
	if str(m["type"]) == "drive":
		# Hareket etüdü motoru: bileşenin eksen etrafındaki açısı hedef değere (radyan) sürülür
		var th := _unwrap(axis_angle(X[ca], xa0, a["d"]), rt, "a")
		return [(th - float(m.get("value", 0.0))) * 50.0]
	var b: Dictionary = E[1]
	match str(m["type"]):
		"gear":
			var ra := float(m.get("ratio_a", 1.0))
			var rb := float(m.get("ratio_b", 1.0))
			var ta := _unwrap(axis_angle(X[ca], xa0, a["d"]), rt, "a")
			var tb := _unwrap(axis_angle(X[cb], xb0, b["d"]), rt, "b")
			return [(ta * ra + s * tb * rb) * 1.0]
		"rack":
			# a: kremayer doğrultusu (doğru), b: pinyon ekseni; değer: hatve yarıçapı
			var disp: float = ((X[ca] as Transform3D).origin - xa0.origin).dot(a["d"])
			var tp := _unwrap(axis_angle(X[cb], xb0, b["d"]), rt, "b")
			return [disp - s * float(m.get("value", 10.0)) * tp]
		"screw":
			var r := _concentric(a, b)
			var d: Vector3 = a["d"]
			var rel: float = (((X[cb] as Transform3D).origin - (X[ca] as Transform3D).origin) - (xb0.origin - xa0.origin)).dot(d)
			var th := _unwrap(axis_angle(X[cb], xb0, d), rt, "b") - _unwrap(axis_angle(X[ca], xa0, d), rt, "a")
			r.append(rel - s * float(m.get("value", 1.0)) * th / TAU)
			return r
	return []


## Çözüm kabul edildikten sonra mekanik eşleştirmelerin sürekli açı durumunu ilerletir.
static func commit_runtime(m: Dictionary, E: Array, X: Dictionary) -> void:
	if not (str(m["type"]) in ["gear", "rack", "screw", "drive"]):
		return
	var refs: Array = m["refs"]
	var ca := int(refs[0]["comp"])
	if str(m["type"]) == "drive":
		if not m.has("_rt"):
			m["_rt"] = {}
		_commit_unwrap(m["_rt"], "a", axis_angle(X[ca], CadAssembly.xf_from_array(m.get("ref_xf", {}).get(str(ca), [])), (E[0] as Dictionary).get("d", Vector3.UP)))
		return
	var cb := int(refs[1]["comp"])
	var r0: Dictionary = m.get("ref_xf", {})
	if not m.has("_rt"):
		m["_rt"] = {}
	var rt: Dictionary = m["_rt"]
	var d: Vector3 = (E[0] as Dictionary).get("d", Vector3.UP)
	var db: Vector3 = (E[1] as Dictionary).get("d", Vector3.UP)
	if str(m["type"]) != "rack":
		_commit_unwrap(rt, "a", axis_angle(X[ca], CadAssembly.xf_from_array(r0.get(str(ca), [])), d))
	_commit_unwrap(rt, "b", axis_angle(X[cb], CadAssembly.xf_from_array(r0.get(str(cb), [])), db if str(m["type"]) != "screw" else d))


# ---------------------------------------------------------------- çözücü

## asm: CadAssembly; local_geo: Callable(ref) -> yerel geometri sözlüğü; info: {comp_id: {center: Vector3, size: float}}
## opts: pinned (sabit sayılacak bileşenler), drag {comp, local, target}, only_mates (yalnızca bu eşleştirmeler)
## Dönüş: {ok, residual, iters, bad: [mate_id], dof: {comp_id: n}, moved: bool}
static func solve(asm: CadAssembly, local_geo: Callable, info: Dictionary, opts := {}) -> Dictionary:
	var X := {}
	for c in asm.comps:
		X[int(c["id"])] = c["xf"]
	var pinned: Array = opts.get("pinned", [])
	var active: Array = []
	for m in asm.mates:
		if bool(m.get("suppressed", false)):
			continue
		var ok := true
		for r in m["refs"]:
			var c := asm.get_comp(int(r.get("comp", -1)))
			if c.is_empty() or bool(c.get("suppressed", false)):
				ok = false
		if ok:
			active.append(m)
	# Yerel geometri önbelleği
	var geo := {}
	for m in active:
		var gl: Array = []
		for r in m["refs"]:
			gl.append(local_geo.call(r))
		geo[int(m["id"])] = gl
	# Serbest bileşenler: sabit değil, eşleştirmede veya sürüklemede yer alıyor
	var free: Array = []
	var drag: Dictionary = opts.get("drag", {})
	for c in asm.comps:
		var id := int(c["id"])
		if bool(c.get("fixed", false)) or bool(c.get("suppressed", false)) or id in pinned:
			continue
		var used := not drag.is_empty() and int(drag.get("comp", -1)) == id
		if not used:
			for m in active:
				for r in m["refs"]:
					if int(r["comp"]) == id:
						used = true
		if used:
			free.append(id)
	var col := {}
	for i in free.size():
		col[free[i]] = i * 6
	var P := free.size() * 6
	var scale := {}
	var center := {}
	for id in free:
		var inf: Dictionary = info.get(id, {})
		scale[id] = maxf(5.0, float(inf.get("size", 50.0)))
		center[id] = inf.get("center", Vector3.ZERO)
	var tol := float(opts.get("tol", 1e-4))
	var result := {"ok": true, "residual": 0.0, "iters": 0, "bad": [], "dof": {}, "moved": false}
	var eval := func(XX: Dictionary, with_drag: bool) -> Array:
		var out: Array = []
		for m in active:
			var E: Array = []
			var gl: Array = geo[int(m["id"])]
			for k in gl.size():
				E.append(to_world(gl[k], XX[int(m["refs"][k]["comp"])]))
			out.append_array(mate_residuals(m, E, XX))
		if with_drag and not drag.is_empty():
			var w := float(drag.get("w", 0.05))
			var p: Vector3 = (XX[int(drag["comp"])] as Transform3D) * v3(drag["local"])
			var dv: Vector3 = (p - v3(drag["target"])) * w
			out.append_array([dv.x, dv.y, dv.z])
		return out
	var apply := func(XX: Dictionary, dx: Array) -> Dictionary:
		var Y := XX.duplicate()
		for id in free:
			var o: int = col[id]
			var xf: Transform3D = XX[id]
			var L: float = scale[id]
			var wv := Vector3(dx[o + 3], dx[o + 4], dx[o + 5]) / L
			var c: Vector3 = xf * (center[id] as Vector3)
			var nb := xf.basis
			var no := xf.origin
			var ang := wv.length()
			if ang > 1e-12:
				var rb := Basis(wv / ang, ang)
				nb = rb * xf.basis
				no = rb * (xf.origin - c) + c
			no += Vector3(dx[o], dx[o + 1], dx[o + 2])
			Y[id] = Transform3D(nb.orthonormalized(), no)
		return Y
	if P == 0 or active.is_empty() and drag.is_empty():
		var r0: Array = eval.call(X, false)
		result["residual"] = _norm_inf(r0)
		result["ok"] = result["residual"] < tol * 10.0
		_mark_bad(active, geo, X, tol, result)
		return result
	var phases := [true, false] if not drag.is_empty() else [false]
	var iters := 0
	for with_drag in phases:
		var lam := 1e-3
		var r: Array = eval.call(X, with_drag)
		var err := _sq(r)
		for it in MAX_ITER:
			iters += 1
			if _norm_inf(r) < tol * 0.2:
				break
			# Sayısal Jacobian (ileri fark)
			var M := r.size()
			var J: Array = []
			J.resize(P)
			for j in P:
				var h := 1e-3
				var dx: Array = []
				dx.resize(P)
				dx.fill(0.0)
				dx[j] = h
				var rj: Array = eval.call(apply.call(X, dx), with_drag)
				var colj := PackedFloat64Array()
				colj.resize(M)
				for i in M:
					colj[i] = (float(rj[i]) - float(r[i])) / h
				J[j] = colj
			var JTJ: Array = []
			var g := PackedFloat64Array()
			g.resize(P)
			for a in P:
				var row := PackedFloat64Array()
				row.resize(P)
				var ja: PackedFloat64Array = J[a]
				for b in P:
					var jb: PackedFloat64Array = J[b]
					var sum := 0.0
					for i in M:
						sum += ja[i] * jb[i]
					row[b] = sum
				var sg := 0.0
				for i in M:
					sg += ja[i] * float(r[i])
				g[a] = sg
				JTJ.append(row)
			var improved := false
			for _try in 8:
				var A: Array = []
				for a in P:
					var row2: PackedFloat64Array = (JTJ[a] as PackedFloat64Array).duplicate()
					row2[a] += lam * (1.0 + row2[a])
					A.append(row2)
				var rhs := PackedFloat64Array()
				rhs.resize(P)
				for a in P:
					rhs[a] = -g[a]
				var step := _gauss(A, rhs)
				if step.is_empty():
					lam *= 10.0
					continue
				# Adımı sınırla (büyük sıçramaları önle)
				var mx := 0.0
				for v in step:
					mx = maxf(mx, absf(v))
				var lim := 200.0
				var stepa: Array = []
				for v in step:
					stepa.append(v * (lim / mx if mx > lim else 1.0))
				var X2: Dictionary = apply.call(X, stepa)
				var r2: Array = eval.call(X2, with_drag)
				var e2 := _sq(r2)
				if e2 < err:
					X = X2
					r = r2
					err = e2
					lam = maxf(lam * 0.3, 1e-9)
					improved = true
					break
				lam *= 6.0
			if not improved:
				break
	result["iters"] = iters
	var rf: Array = eval.call(X, false)
	result["residual"] = _norm_inf(rf)
	result["ok"] = result["residual"] < tol * 10.0
	_mark_bad(active, geo, X, tol, result)
	if not bool(opts.get("dry", false)):
		for id in free:
			var c := asm.get_comp(id)
			if not (c["xf"] as Transform3D).is_equal_approx(X[id]):
				result["moved"] = true
			c["xf"] = X[id]
		for m in active:
			var E2: Array = []
			var gl2: Array = geo[int(m["id"])]
			for k in gl2.size():
				E2.append(to_world(gl2[k], X[int(m["refs"][k]["comp"])]))
			commit_runtime(m, E2, X)
	result["X"] = X
	if bool(opts.get("dof", true)):
		result["dof"] = dof_analysis(asm, active, geo, X, free, scale, center)
	return result


static func _mark_bad(active: Array, geo: Dictionary, X: Dictionary, tol: float, result: Dictionary) -> void:
	for m in active:
		var E: Array = []
		var gl: Array = geo[int(m["id"])]
		for k in gl.size():
			E.append(to_world(gl[k], X[int(m["refs"][k]["comp"])]))
		var r := mate_residuals(m, E, X)
		var bad := _norm_inf(r) > tol * 10.0
		m["error"] = I18n.t("Eşleştirme sağlanamıyor (çelişkili veya geometri uygun değil)") if bad else ""
		if bad:
			result["bad"].append(int(m["id"]))


## Bileşen başına kalan serbestlik derecesi: o bileşenin 6 sütununun Jacobian rankı (diğerleri sabit sayılır).
static func dof_analysis(asm: CadAssembly, active: Array, geo: Dictionary, X: Dictionary, free: Array, scale: Dictionary, center: Dictionary) -> Dictionary:
	var out := {}
	for c in asm.comps:
		var id := int(c["id"])
		out[id] = 0 if bool(c.get("fixed", false)) else 6
	for id in free:
		var rows: Array = []   # her eşleştirme için tabanda artık
		var base: Array = []
		var mates_i: Array = []
		for m in active:
			for r in m["refs"]:
				if int(r["comp"]) == id:
					mates_i.append(m)
					break
		var evalm := func(XX: Dictionary) -> Array:
			var o: Array = []
			for m in mates_i:
				var E: Array = []
				var gl: Array = geo[int(m["id"])]
				for k in gl.size():
					E.append(to_world(gl[k], XX[int(m["refs"][k]["comp"])]))
				o.append_array(mate_residuals(m, E, XX))
			return o
		base = evalm.call(X)
		if base.is_empty():
			continue
		var J: Array = []
		for j in 6:
			var Y := X.duplicate()
			var xf: Transform3D = X[id]
			var h := 1e-3
			if j < 3:
				var dv := Vector3.ZERO
				dv[j] = h
				Y[id] = Transform3D(xf.basis, xf.origin + dv)
			else:
				var ax := Vector3.ZERO
				ax[j - 3] = 1.0
				var L: float = scale[id]
				var c3: Vector3 = xf * (center[id] as Vector3)
				var rb := Basis(ax, h / L)
				Y[id] = Transform3D(rb * xf.basis, rb * (xf.origin - c3) + c3)
			var rj: Array = evalm.call(Y)
			var colj: Array = []
			for i in base.size():
				colj.append((float(rj[i]) - float(base[i])) / h)
			J.append(colj)
		out[id] = 6 - _rank(J, base.size())
	return out


static func _rank(cols: Array, m: int) -> int:
	# Satır düzeni: A[i][j] = cols[j][i]
	var A: Array = []
	for i in m:
		var row: Array = []
		for j in cols.size():
			row.append(float(cols[j][i]))
		A.append(row)
	var rank := 0
	var n := cols.size()
	var r := 0
	for c in n:
		var piv := -1
		var best := 1e-3
		for i in range(r, m):
			if absf(A[i][c]) > best:
				best = absf(A[i][c])
				piv = i
		if piv < 0:
			continue
		var tmp: Array = A[r]
		A[r] = A[piv]
		A[piv] = tmp
		for i in range(r + 1, m):
			var f: float = A[i][c] / A[r][c]
			for k in range(c, n):
				A[i][k] -= f * A[r][k]
		r += 1
		rank += 1
		if r >= m:
			break
	return rank


static func _gauss(A: Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var n := b.size()
	var x := b.duplicate()
	for c in n:
		var piv := c
		var best := absf(A[c][c])
		for i in range(c + 1, n):
			if absf(A[i][c]) > best:
				best = absf(A[i][c])
				piv = i
		if best < 1e-14:
			return PackedFloat64Array()
		if piv != c:
			var t: PackedFloat64Array = A[c]
			A[c] = A[piv]
			A[piv] = t
			var tb := x[c]
			x[c] = x[piv]
			x[piv] = tb
		var rowc: PackedFloat64Array = A[c]
		for i in range(c + 1, n):
			var rowi: PackedFloat64Array = A[i]
			var f := rowi[c] / rowc[c]
			if f == 0.0:
				continue
			for k in range(c, n):
				rowi[k] -= f * rowc[k]
			A[i] = rowi
			x[i] -= f * x[c]
	for c in range(n - 1, -1, -1):
		var rowc2: PackedFloat64Array = A[c]
		var s := x[c]
		for k in range(c + 1, n):
			s -= rowc2[k] * x[k]
		x[c] = s / rowc2[c]
	return x


static func _sq(r: Array) -> float:
	var s := 0.0
	for v in r:
		s += float(v) * float(v)
	return s


static func _norm_inf(r: Array) -> float:
	var s := 0.0
	for v in r:
		s = maxf(s, absf(float(v)))
	return s


# ---------------------------------------------------------------- kam

## Noktanın kapalı çokgene işaretli uzaklığı (içeride negatif)
static func signed_dist_poly(q: Vector2, poly: Array) -> float:
	var n := poly.size()
	if n < 2:
		return 0.0
	var best := INF
	var inside := false
	for i in n:
		var a := Vector2(float(poly[i][0]), float(poly[i][1]))
		var b := Vector2(float(poly[(i + 1) % n][0]), float(poly[(i + 1) % n][1]))
		var cp := Geometry2D.get_closest_point_to_segment(q, a, b)
		best = minf(best, cp.distance_to(q))
		if (a.y > q.y) != (b.y > q.y):
			var xi := a.x + (q.y - a.y) / (b.y - a.y) * (b.x - a.x)
			if q.x < xi:
				inside = not inside
	return -best if inside else best


## Kam: izleyici (nokta, küre, silindir/makara) kam profiline değer. Profil kam bileşeninin yerel çerçevesinde
## (o, u, v; d = profil düzleminin normali) 2B çokgen olarak eşleştirmede saklanır.
static func _cam_residual(m: Dictionary, f: Dictionary, X: Dictionary) -> float:
	var cam_id := int(m["refs"][1]["comp"])
	var fr: Dictionary = m.get("frame", {})
	var xf: Transform3D = X[cam_id]
	var q3 := xf.affine_inverse() * pt(f)
	var o := v3(fr.get("o", [0, 0, 0]))
	var q := Vector2((q3 - o).dot(v3(fr.get("u", [1, 0, 0]))), (q3 - o).dot(v3(fr.get("v", [0, 1, 0]))))
	var r := float(f.get("r", 0.0)) if str(f["t"]) in ["cyl", "sphere", "circle"] else 0.0
	return signed_dist_poly(q, m.get("profile", [])) - r
