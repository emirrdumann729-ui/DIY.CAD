class_name SheetMetal
extends RefCounted
## Sac metal (Faz 8): taban flanş, kenar flanş, büküm payı (K-faktörü), açınım ve açınım DXF'i.
##
## Taban flanş ("sm_base"): kapalı profil → kalınlık T'lik plaka; açık çizgi zinciri → köşeleri büküm
##   yarıçapıyla yuvarlatılmış, T kalınlığında bükümlü profil (derinlik boyunca).
## Kenar flanş ("sm_edge"): taban plakanın üst / alt kenarlarına; büküm dışarıda (taban değişmez),
##   iç yarıçap R, açı A, düz flanş boyu L. Kenarlar topolojik addan taban taslağının öğesine eşlenir.
## Açınım: taban profili + her kenar flanşı için (BA + L) genişliğinde şerit; BA = A·(R + K·T).

const DEFAULTS := {"T": 2.0, "R": 2.0, "K": 0.44, "depth": 50.0, "reverse": false, "flip": false, "flat": false}


static func base_of(doc: CadDocument) -> CadFeature:
	for f in doc.features:
		if f.type == "sm_base" and not f.suppressed:
			return f
	return null


static func bend_allowance(angle_deg: float, R: float, K: float, T: float) -> float:
	return deg_to_rad(absf(angle_deg)) * (R + K * T)


static func _a2(v: Vector2) -> Array:
	return [v.x, v.y]


static func _arc(c: Vector2, r: float, a0: float, a1: float, k: String) -> Dictionary:
	var am := (a0 + a1) * 0.5
	return {"t": "arc", "p": [_a2(c + Vector2(cos(a0), sin(a0)) * r), _a2(c + Vector2(cos(am), sin(am)) * r), _a2(c + Vector2(cos(a1), sin(a1)) * r)], "k": k}


static func _line(a: Vector2, b: Vector2, k: String) -> Dictionary:
	return {"t": "line", "a": _a2(a), "b": _a2(b), "k": k}


## Açık çizgi zincirinden bükümlü profil. pts: sketch düzlemi 2B noktaları; side +1: malzeme yolun solunda.
## Dönüş: {loop: [eğriler], straights: [düz boylar], bends: [{angle, r}], flat_len} veya {error}
static func bent_profile(pts: Array, T: float, R: float, K: float, side: float) -> Dictionary:
	var n := pts.size()
	if n < 2:
		return {"error": "Açık profil en az bir çizgi içermeli"}
	var dirs: Array = []
	for i in n - 1:
		var d: Vector2 = (pts[i + 1] as Vector2) - (pts[i] as Vector2)
		if d.length() < 1e-9:
			return {"error": "Sıfır uzunluklu çizgi"}
		dirs.append(d.normalized())
	var corners: Array = []   # her iç köşe: {q_in, q_out, c, r_line, r_other, a0, a1, theta, left}
	var setback := []
	setback.resize(n)
	setback.fill(0.0)
	var bends: Array = []
	for i in range(1, n - 1):
		var din: Vector2 = dirs[i - 1]
		var dout: Vector2 = dirs[i]
		var cr := din.cross(dout)
		var th := atan2(cr, din.dot(dout))
		if absf(th) < 1e-6:
			corners.append({})
			continue
		var left := th > 0.0
		var r_line := (R + T) if (left == (side > 0.0)) else R
		var t := r_line * tan(absf(th) * 0.5)
		setback[i] = t
		var p: Vector2 = pts[i]
		var nin := Vector2(-din.y, din.x) if left else Vector2(din.y, -din.x)
		var q_in := p - din * t
		var q_out := p + dout * t
		var c := q_in + nin * r_line
		var r_other := r_line - T if r_line > R else r_line + T
		corners.append({"q_in": q_in, "q_out": q_out, "c": c, "r_line": r_line, "r_other": r_other, "left": left,
			"a0": (q_in - c).angle(), "a1": (q_out - c).angle(), "theta": th})
		bends.append({"angle": rad_to_deg(absf(th)), "r": R})
	# Düz parçalar
	var straights: Array = []
	for i in n - 1:
		var L: float = ((pts[i + 1] as Vector2) - (pts[i] as Vector2)).length() - float(setback[i]) - float(setback[i + 1])
		if L < -1e-6:
			return {"error": "Çizgi büküm yarıçapı için çok kısa (%d. çizgi)" % (i + 1)}
		straights.append(maxf(L, 0.0))
	var off := func(d: Vector2) -> Vector2: return Vector2(-d.y, d.x) * side * T
	# Taslak yüzü (ileri) + uç + ofset yüzü (geri) + uç
	var fw: Array = []
	var bw: Array = []
	var start: Vector2 = pts[0]
	for i in n - 1:
		var co: Dictionary = corners[i] if i < n - 2 else {}
		var seg_end: Vector2 = co["q_in"] if not co.is_empty() else pts[i + 1]
		var o: Vector2 = off.call(dirs[i])
		fw.append(_line(start, seg_end, "L%d" % i))
		bw.append(_line(seg_end + o, start + o, "O%d" % i))
		if co.is_empty():
			start = pts[i + 1]
			continue
		var a0: float = co["a0"]
		var da := wrapf(float(co["a1"]) - a0, -PI, PI)
		fw.append(_arc(co["c"], co["r_line"], a0, a0 + da, "A%d" % i))
		bw.append(_arc(co["c"], co["r_other"], a0 + da, a0, "B%d" % i))
		start = co["q_out"]
	var loop: Array = fw.duplicate()
	var end_p: Vector2 = pts[n - 1]
	loop.append(_line(end_p, end_p + off.call(dirs[n - 2]), "E1"))
	bw.reverse()
	loop.append_array(bw)
	loop.append(_line(pts[0] + off.call(dirs[0]), pts[0], "E0"))
	var flat := 0.0
	for s in straights:
		flat += float(s)
	for b in bends:
		flat += bend_allowance(float(b["angle"]), R, K, T)
	return {"loop": loop, "straights": straights, "bends": bends, "flat_len": flat}


## Taslağın açık çizgi zinciri (yalnızca doğrular). Dönüş: [Vector2] veya []
static func open_chain(sk: Sketch) -> Array:
	for ch in sk.curve_chains():
		var pts: Array = []
		var ok := true
		for c in ch:
			if str(c.get("t", "")) != "line":
				ok = false
				break
			if pts.is_empty():
				pts.append(Vector2(float(c["a"][0]), float(c["a"][1])))
			pts.append(Vector2(float(c["b"][0]), float(c["b"][1])))
		if ok and pts.size() >= 2 and (pts[0] as Vector2).distance_to(pts[pts.size() - 1]) > 1e-6:
			return pts
	return []


static func _plane_dict(o: Vector3, x: Vector3, y: Vector3) -> Dictionary:
	var n := x.cross(y).normalized()
	return {"o": [o.x, o.y, o.z], "x": [x.x, x.y, x.z], "y": [y.x, y.y, y.z], "n": [n.x, n.y, n.z]}


static func _v3a(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## Özellik yükü (OCC). d: {fid, type} doldurulur; false: atla (hata f.error'da)
static func payload(doc: CadDocument, f: CadFeature, d: Dictionary) -> bool:
	var base := base_of(doc)
	if f.type == "sm_base":
		return _base_payload(doc, f, d)
	if base == null:
		f.error = "Önce taban flanş oluşturun"
		return false
	if bool(base.params.get("flat", false)):
		return false   # açınım gösterilirken flanşlar açınıma dahildir
	var res := edge_items(doc, f)
	if res.has("error"):
		f.error = res["error"]
		return false
	d["type"] = "prisms"
	d["items"] = res["items"]
	return true


static func _base_payload(doc: CadDocument, f: CadFeature, d: Dictionary) -> bool:
	var sk_f := doc.get_feature(f.sketch_ref())
	if sk_f == null or sk_f.sketch == null:
		f.error = "Taslak bulunamadı"
		return false
	var T := maxf(0.01, float(f.params.get("T", 2.0)))
	var pl := sk_f.plane
	var nrm := -pl.normal() if bool(f.params.get("reverse", false)) else pl.normal()
	if bool(f.params.get("flat", false)):
		var fp := flat_pattern(doc)
		if fp.has("error"):
			f.error = fp["error"]
			return false
		var loops: Array = []
		for poly in fp["outline"]:
			loops.append({"depth": 0, "parent": -1, "curves": _poly_curves(poly, "F")})
		var pi := 0
		for hole in fp["holes"]:
			loops.append({"depth": 1, "parent": 0, "curves": _poly_curves(hole, "H%d_" % pi)})
			pi += 1
		var fr: Dictionary = fp["frame"]
		d["type"] = "prisms"
		d["items"] = [{"key": "flat", "plane": _plane_dict(fr["o"], fr["x"], fr["y"]), "loops": loops, "vec": _v3a((fr["n"] as Vector3) * T)}]
		return true
	var prof := sk_f.sketch.extract_profiles()
	if not (prof["loops"] as Array).is_empty():
		var loops2: Array = []
		for L in prof["loops"]:
			loops2.append({"depth": L["depth"], "parent": L["parent"], "curves": L["curves"]})
		d["type"] = "extrude"
		d["plane"] = OccKernel._plane_dict(pl)
		d["sketch_fid"] = sk_f.id
		d["loops"] = loops2
		d["vec"] = _v3a(nrm * T)
		d["offset"] = [0.0, 0.0, 0.0]
		d["end"] = "blind"
		d["cut"] = false
		d["merge"] = true
		return true
	var chain := open_chain(sk_f.sketch)
	if chain.is_empty():
		f.error = "Taslakta kapalı kontur veya açık çizgi zinciri yok"
		return false
	var side := -1.0 if bool(f.params.get("flip", false)) else 1.0
	var bp := bent_profile(chain, T, maxf(0.01, float(f.params.get("R", 2.0))), float(f.params.get("K", 0.44)), side)
	if bp.has("error"):
		f.error = bp["error"]
		return false
	var depth := maxf(0.01, float(f.params.get("depth", 50.0)))
	var off := Vector3.ZERO
	if bool(f.params.get("midplane", false)):
		off = -nrm * depth * 0.5
	d["type"] = "prisms"
	d["items"] = [{"key": "0", "plane": _plane_dict(pl.origin + off, pl.x_dir, pl.y_dir), "loops": [{"depth": 0, "parent": -1, "curves": bp["loop"]}],
		"vec": _v3a(nrm * depth)}]
	return true


static func _poly_curves(poly: PackedVector2Array, kp: String) -> Array:
	var out: Array = []
	for i in poly.size():
		out.append(_line(poly[i], poly[(i + 1) % poly.size()], "%s%d" % [kp, i]))
	return out


## Topolojik ad listesinden taban taslak öğesi ve kapak: {fid, eid, cap} veya {}
static func parse_edge(fn: Array) -> Dictionary:
	var side := {}
	var cap := {}
	var re := RegEx.new()
	re.compile("^F(\\d+):([sab]):(.+)$")
	for nm in fn:
		var m := re.search(str(nm))
		if m == null:
			continue
		if m.get_string(2) == "s":
			side = {"fid": int(m.get_string(1)), "k": m.get_string(3)}
		else:
			cap = {"fid": int(m.get_string(1)), "cap": m.get_string(2)}
	if side.is_empty() or cap.is_empty() or int(side["fid"]) != int(cap["fid"]):
		return {}
	return {"fid": int(side["fid"]), "eid": int(str(side["k"]).get_slice(".", 0)), "cap": cap["cap"]}


## Taban taslağı döngüleri (çokgen) — malzeme içi testi için
static func _loop_polys(sk: Sketch) -> Array:
	var out: Array = []
	for L in sk.extract_profiles()["loops"]:
		var poly := PackedVector2Array()
		for c in L["curves"]:
			match str(c["t"]):
				"line":
					poly.append(Vector2(float(c["a"][0]), float(c["a"][1])))
				"arc":
					for q in c["p"]:
						poly.append(Vector2(float(q[0]), float(q[1])))
				"circle":
					var cc := Vector2(float(c["c"][0]), float(c["c"][1]))
					for k in 48:
						var a := TAU * k / 48.0
						poly.append(cc + Vector2(cos(a), sin(a)) * float(c["r"]))
				_:
					for q in c.get("p", []):
						if q is Array:
							poly.append(Vector2(float(q[0]), float(q[1])))
		if poly.size() >= 3:
			out.append({"poly": poly, "depth": int(L["depth"])})
	return out


static func _in_material(q: Vector2, polys: Array) -> bool:
	var cnt := 0
	for p in polys:
		if Geometry2D.is_point_in_polygon(q, p["poly"]):
			cnt += 1
	return cnt % 2 == 1


## Kenar flanşının bir kenarının taslak (2B) ve 3B tanımı. Dönüş: {a2, b2, o2, e2, len, cap} veya {error}
static func edge_frame(doc: CadDocument, base: CadFeature, ref: Dictionary) -> Dictionary:
	var pe := parse_edge(ref.get("fn", []))
	if pe.is_empty() or int(pe["fid"]) != base.id:
		return {"error": "Kenar flanşı yalnızca taban flanşın üst / alt kenarlarına eklenebilir"}
	var sk_f := doc.get_feature(base.sketch_ref())
	var e := sk_f.sketch.get_entity(int(pe["eid"]))
	if e.is_empty() or str(e["type"]) != "line":
		return {"error": "Seçilen kenar doğrusal bir taslak çizgisine ait değil"}
	var a2: Vector2 = sk_f.sketch.points[int(e["a"])]
	var b2: Vector2 = sk_f.sketch.points[int(e["b"])]
	var e2 := (b2 - a2).normalized()
	var p2 := Vector2(-e2.y, e2.x)
	var polys := _loop_polys(sk_f.sketch)
	var m2 := (a2 + b2) * 0.5
	var eps := maxf(1e-3, (b2 - a2).length() * 1e-3)
	var o2 := p2 if not _in_material(m2 + p2 * eps, polys) else -p2
	return {"a2": a2, "b2": b2, "o2": o2, "e2": e2, "len": (b2 - a2).length(), "cap": pe["cap"], "eid": int(pe["eid"])}


## Kenar flanşı kesit profili (yerel u: dışa, v: büküm yönü). Taban plaka v∈[0, T], u ≤ 0.
static func flange_section(T: float, R: float, A_deg: float, L: float) -> Array:
	var A := deg_to_rad(clampf(A_deg, 1.0, 180.0))
	var C := Vector2(0, T + R)
	var a0 := -PI * 0.5
	var a1 := a0 + A
	var Ro := R + T
	var tdir := Vector2(cos(A), sin(A))
	var P0 := C + Vector2(cos(a0), sin(a0)) * Ro
	var P1 := C + Vector2(cos(a1), sin(a1)) * Ro
	var Pi1 := C + Vector2(cos(a1), sin(a1)) * R
	var Pi0 := C + Vector2(cos(a0), sin(a0)) * R
	var curves: Array = [_arc(C, Ro, a0, a1, "bo")]
	if L > 1e-6:
		curves.append(_line(P1, P1 + tdir * L, "fo"))
		curves.append(_line(P1 + tdir * L, Pi1 + tdir * L, "ft"))
		curves.append(_line(Pi1 + tdir * L, Pi1, "fi"))
	else:
		curves.append(_line(P1, Pi1, "ft"))
	curves.append(_arc(C, R, a1, a0, "bi"))
	curves.append(_line(Pi0, P0, "bs"))
	return curves


static func sheet(base: CadFeature) -> Dictionary:
	return {"T": maxf(0.01, float(base.params.get("T", 2.0))), "R": maxf(0.01, float(base.params.get("R", 2.0))), "K": float(base.params.get("K", 0.44))}


## Kenar flanşı özelliğinin OCC prizmaları
static func edge_items(doc: CadDocument, f: CadFeature) -> Dictionary:
	var base := base_of(doc)
	var sk_f := doc.get_feature(base.sketch_ref())
	if sk_f == null:
		return {"error": "Taban taslağı bulunamadı"}
	if (sk_f.sketch.extract_profiles()["loops"] as Array).is_empty():
		return {"error": "Kenar flanşı şimdilik yalnızca düz (kapalı profilli) taban flanşa eklenebilir"}
	var edges: Array = f.params.get("edges", [])
	if edges.is_empty():
		return {"error": "Kenar seçilmedi"}
	var sh := sheet(base)
	var T: float = sh["T"]
	var R := float(f.params.get("R", -1.0))
	if R <= 0.0:
		R = sh["R"]
	var A := float(f.params.get("A", 90.0))
	var L := maxf(0.0, float(f.params.get("L", 20.0)))
	var pl := sk_f.plane
	var nrm := base_normal_doc(doc, base)
	var items: Array = []
	var i := 0
	for ref in edges:
		var fr := edge_frame(doc, base, ref)
		if fr.has("error"):
			return fr
		var off1 := float(f.params.get("off1", 0.0))
		var off2 := float(f.params.get("off2", 0.0))
		var length: float = float(fr["len"]) - off1 - off2
		if length <= 1e-6:
			return {"error": "Kenar boşlukları kenar boyundan büyük"}
		var up := (str(fr["cap"]) == "b") != bool(f.params.get("flip", false))
		var o3 := pl.x_dir * (fr["o2"] as Vector2).x + pl.y_dir * (fr["o2"] as Vector2).y
		var a3 := pl.to_world(fr["a2"])
		var e3 := (pl.to_world(fr["b2"]) - a3).normalized()
		var origin := a3 + e3 * off1
		var vaxis := nrm
		if not up:
			origin += nrm * T
			vaxis = -nrm
		items.append({"key": "e%d" % i, "plane": _plane_dict(origin, o3, vaxis), "loops": [{"depth": 0, "parent": -1, "curves": flange_section(T, R, A, L)}],
			"vec": _v3a(e3 * length)})
		i += 1
	return {"items": items}


static func base_normal_doc(doc: CadDocument, base: CadFeature) -> Vector3:
	var sk_f := doc.get_feature(base.sketch_ref())
	var n := sk_f.plane.normal() if sk_f != null else Vector3.UP
	return -n if bool(base.params.get("reverse", false)) else n


# ---------------------------------------------------------------- açınım

## Açınım: {outline: [PackedVector2Array], holes: [...], bends: [{a, b, note}], frame: {o, x, y, n}, size: Vector2, T}
static func flat_pattern(doc: CadDocument) -> Dictionary:
	var base := base_of(doc)
	if base == null:
		return {"error": "Taban flanş yok"}
	var sk_f := doc.get_feature(base.sketch_ref())
	if sk_f == null:
		return {"error": "Taban taslağı bulunamadı"}
	var sh := sheet(base)
	var T: float = sh["T"]
	var K: float = sh["K"]
	var pl := sk_f.plane
	var nrm := base_normal_doc(doc, base)
	var polys := _loop_polys(sk_f.sketch)
	var bends: Array = []
	if polys.is_empty():
		# Açık profil: dikdörtgen açınım
		var chain := open_chain(sk_f.sketch)
		if chain.is_empty():
			return {"error": "Taslakta profil yok"}
		var side := -1.0 if bool(base.params.get("flip", false)) else 1.0
		var bp := bent_profile(chain, T, sh["R"], K, side)
		if bp.has("error"):
			return bp
		var depth := maxf(0.01, float(base.params.get("depth", 50.0)))
		var W: float = bp["flat_len"]
		var x := 0.0
		var straights: Array = bp["straights"]
		for i in (bp["bends"] as Array).size():
			x += float(straights[i])
			var b: Dictionary = bp["bends"][i]
			var ba := bend_allowance(float(b["angle"]), sh["R"], K, T)
			bends.append({"a": Vector2(x + ba * 0.5, 0), "b": Vector2(x + ba * 0.5, depth), "note": "%s %.0f° R%s" % ["BÜKÜM", float(b["angle"]), _n(sh["R"])], "ba": ba})
			x += ba
		var d0: Vector2 = ((chain[1] as Vector2) - (chain[0] as Vector2)).normalized()
		var o := pl.to_world(chain[0])
		var xd := (pl.x_dir * d0.x + pl.y_dir * d0.y).normalized()
		var thick_dir := (pl.x_dir * -d0.y + pl.y_dir * d0.x) * side
		return {"outline": [PackedVector2Array([Vector2.ZERO, Vector2(W, 0), Vector2(W, depth), Vector2(0, depth)])], "holes": [], "bends": bends,
			"frame": {"o": o, "x": xd, "y": nrm, "n": thick_dir.normalized()}, "size": Vector2(W, depth), "T": T}
	var outline: Array = []
	var holes: Array = []
	for p in polys:
		if int(p["depth"]) % 2 == 0:
			outline.append(p["poly"])
		else:
			holes.append(p["poly"])
	# Kenar flanşları: (BA + L) genişliğinde şeritler
	for f in doc.features:
		if f.type != "sm_edge" or f.suppressed or doc.is_rolled_back(f):
			continue
		var R := float(f.params.get("R", -1.0))
		if R <= 0.0:
			R = sh["R"]
		var A := float(f.params.get("A", 90.0))
		var L := maxf(0.0, float(f.params.get("L", 20.0)))
		var ba := bend_allowance(A, R, K, T)
		for ref in f.params.get("edges", []):
			var fr := edge_frame(doc, base, ref)
			if fr.has("error"):
				continue
			var e2: Vector2 = fr["e2"]
			var o2: Vector2 = fr["o2"]
			var s0: Vector2 = (fr["a2"] as Vector2) + e2 * float(f.params.get("off1", 0.0))
			var s1: Vector2 = (fr["b2"] as Vector2) - e2 * float(f.params.get("off2", 0.0))
			var rect := PackedVector2Array([s0, s1, s1 + o2 * (ba + L), s0 + o2 * (ba + L)])
			outline = _union(outline, rect)
			var up := (str(fr["cap"]) == "b") != bool(f.params.get("flip", false))
			bends.append({"a": s0 + o2 * ba * 0.5, "b": s1 + o2 * ba * 0.5, "note": "%s %.0f° R%s" % ["YUKARI" if up else "AŞAĞI", A, _n(R)], "ba": ba})
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for poly in outline:
		for q in poly:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var o3 := pl.origin
	if bool(base.params.get("reverse", false)):
		o3 = pl.origin   # plaka düzlemden ters yöne: açınım aynı düzlemde
	return {"outline": outline, "holes": holes, "bends": bends, "frame": {"o": o3, "x": pl.x_dir, "y": pl.y_dir, "n": nrm}, "size": hi - lo, "T": T, "min": lo}


static func _n(x: float) -> String:
	return str(snappedf(x, 0.01)).trim_suffix(".0")


static func _union(polys: Array, rect: PackedVector2Array) -> Array:
	var acc := rect
	var rest: Array = []
	for p in polys:
		var m := Geometry2D.merge_polygons(p, acc)
		# Birleşince tek dış sınır (+ olası delikler) döner
		var outer: Array = []
		for q in m:
			if not Geometry2D.is_polygon_clockwise(q):
				outer.append(q)
		if m.size() >= 1 and outer.size() == 1:
			acc = outer[0]
		elif m.size() == 1:
			acc = m[0]
		else:
			rest.append(p)
	rest.append(acc)
	return rest


## Açınım DXF / çizim ilkelleri (DrawingExport ile yazılır)
static func flat_prims(fp: Dictionary) -> Array:
	var P: Array = []
	var lo: Vector2 = fp.get("min", Vector2.ZERO)
	var sh := func(q: Vector2) -> Vector2: return q - lo + Vector2(10, 10)
	for poly in fp["outline"]:
		var pts := PackedVector2Array()
		for q in poly:
			pts.append(sh.call(q))
		P.append({"t": "pl", "pts": pts, "w": 0.35, "s": "solid", "c": Color.BLACK, "closed": true, "lay": "GORUNUR"})
	for poly2 in fp["holes"]:
		var pts2 := PackedVector2Array()
		for q2 in poly2:
			pts2.append(sh.call(q2))
		P.append({"t": "pl", "pts": pts2, "w": 0.35, "s": "solid", "c": Color.BLACK, "closed": true, "lay": "GORUNUR"})
	for b in fp["bends"]:
		var a: Vector2 = sh.call(b["a"])
		var bb: Vector2 = sh.call(b["b"])
		P.append({"t": "l", "a": a, "b": bb, "w": 0.18, "s": "chain", "c": Color.BLACK, "lay": "EKSEN"})
		var d := (bb - a).normalized()
		P.append({"t": "txt", "p": (a + bb) * 0.5 + Vector2(-d.y, d.x) * 1.5, "h": 2.5, "s": str(b["note"]), "ang": atan2(d.y, d.x), "al": "c", "c": Color.BLACK, "lay": "METIN"})
	return P
