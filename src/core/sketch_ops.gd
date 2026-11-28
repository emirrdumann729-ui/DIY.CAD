class_name SketchOps
extends RefCounted
## Taslak düzenleme işlemleri (Faz 3): kesişimler, kırp, uzat, ofset, aynala, köşe yuvarlatma,
## pah, çokgen, kanal, kopyala / taşı / döndür / ölçekle / çoğalt.
## Hepsi doğrudan Sketch verisini değiştirir; çağıran taraf sonra kısıt çözücüyü çalıştırır.
## Dönüş sözlüğü: {ok: bool, msg: String, ...}

const EPS := 1e-7


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "msg": msg}


# ================================================================ kesişimler

## Öğeyi temel parçalara ayırır: ["seg", A, B] veya ["circ", C, r, yay_öğesi|null]
static func _prims(sk: Sketch, e: Dictionary) -> Array:
	match e["type"]:
		"line":
			return [["seg", sk.points[e["a"]], sk.points[e["b"]]]]
		"circle":
			return [["circ", sk.points[e["c"]], float(e["r"]), null]]
		"arc":
			return [["circ", sk.points[e["c"]], sk.entity_radius(e), e]]
		"spline", "ellipse", "parabola":
			var out: Array = []
			var poly := sk.entity_polyline(e)
			for i in poly.size() - 1:
				out.append(["seg", poly[i], poly[i + 1]])
			return out
	return []


static func _on_arc(sk: Sketch, arc, p: Vector2) -> bool:
	if arc == null:
		return true
	var d := sk.arc_data(arc)
	var ang := fposmod((p - (d["c"] as Vector2)).angle() - float(d["a0"]), TAU)
	return ang <= float(d["sweep"]) + 1e-7 or ang >= TAU - 1e-7


static func _line_circle(a: Vector2, b: Vector2, c: Vector2, r: float, segment := true) -> Array:
	var d := b - a
	var f := a - c
	var A := d.dot(d)
	var B := 2.0 * f.dot(d)
	var C := f.dot(f) - r * r
	var disc := B * B - 4.0 * A * C
	if A < 1e-18 or disc < -1e-12:
		return []
	disc = sqrt(maxf(disc, 0.0))
	var out: Array = []
	for t in [(-B - disc) / (2.0 * A), (-B + disc) / (2.0 * A)]:
		if not segment or (t >= -1e-9 and t <= 1.0 + 1e-9):
			out.append(a + d * t)
	return out


static func _circle_circle(c1: Vector2, r1: float, c2: Vector2, r2: float) -> Array:
	var d := c1.distance_to(c2)
	if d < 1e-12 or d > r1 + r2 + 1e-9 or d < absf(r1 - r2) - 1e-9:
		return []
	var a := (r1 * r1 - r2 * r2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(r1 * r1 - a * a, 0.0))
	var u := (c2 - c1) / d
	var m := c1 + u * a
	var n := Vector2(-u.y, u.x)
	if h < 1e-9:
		return [m]
	return [m + n * h, m - n * h]


## İki öğenin kesişim noktaları.
static func intersections(sk: Sketch, e: Dictionary, o: Dictionary) -> Array:
	return prim_intersections(sk, _prims(sk, e), _prims(sk, o))


## Parça listeleri arasındaki kesişimler.
static func prim_intersections(sk: Sketch, A: Array, B: Array) -> Array:
	var out: Array = []
	for p1 in A:
		for p2 in B:
			var pts: Array = []
			if p1[0] == "seg" and p2[0] == "seg":
				var hit = Geometry2D.segment_intersects_segment(p1[1], p1[2], p2[1], p2[2])
				if hit != null:
					pts.append(hit)
			elif p1[0] == "seg":
				pts = _line_circle(p1[1], p1[2], p2[1], p2[2])
			elif p2[0] == "seg":
				pts = _line_circle(p2[1], p2[2], p1[1], p1[2])
			else:
				pts = _circle_circle(p1[1], p1[2], p2[1], p2[2])
			for q in pts:
				if (p1[0] != "circ" or _on_arc(sk, p1[3], q)) and (p2[0] != "circ" or _on_arc(sk, p2[3], q)):
					var dup := false
					for z in out:
						if (z as Vector2).distance_to(q) < 1e-6:
							dup = true
					if not dup:
						out.append(q)
	return out


## Nokta öğe üzerinde hangi parametrede? Çizgi: 0..1, yay: 0..süpürme, daire: 0..2π
static func param_of(sk: Sketch, e: Dictionary, p: Vector2) -> float:
	match e["type"]:
		"line":
			var a: Vector2 = sk.points[e["a"]]
			var d: Vector2 = (sk.points[e["b"]] as Vector2) - a
			return (p - a).dot(d) / maxf(d.length_squared(), 1e-18)
		"arc":
			var ad := sk.arc_data(e)
			return fposmod((p - (ad["c"] as Vector2)).angle() - float(ad["a0"]), TAU)
		"circle":
			return fposmod((p - (sk.points[e["c"]] as Vector2)).angle(), TAU)
	return 0.0


## Kesişim noktasına uç noktası üretir: orada zaten diğer öğenin noktası varsa onu kullanır,
## yoksa yeni nokta + çakışık ilişkisi ekler.
static func _end_point(sk: Sketch, p: Vector2, oid: int) -> int:
	var o := sk.get_entity(oid)
	for pid in Sketch.entity_point_ids(o):
		if (sk.points[pid] as Vector2).distance_to(p) < 1e-6:
			return pid
	var np := sk.add_point(p)
	if o["type"] in ["line", "circle", "arc"]:
		sk.add_constraint({"type": "coincident", "p1": np, "e1": oid})
	return np


static func _dissolve_group(sk: Sketch, e: Dictionary) -> void:
	var gid := int(e.get("group", 0))
	if gid == 0:
		return
	sk.groups.erase(gid)
	for x in sk.entities:
		if int(x.get("group", 0)) == gid:
			x["group"] = 0


# ================================================================ kırp / uzat

## Güç kırpma: tıklanan parçayı en yakın kesişimler arasında siler.
static func trim(sk: Sketch, eid: int, click: Vector2) -> Dictionary:
	var e := sk.get_entity(eid)
	if e.is_empty():
		return _fail(I18n.t("Öğe bulunamadı."))
	if not (e["type"] in ["line", "circle", "arc"]):
		return _fail(I18n.t("Bu öğe türü kırpılamaz (yalnızca çizgi, daire, yay)."))
	var cuts: Array = []
	for o in sk.entities:
		if o["id"] == eid or o["type"] == "text":
			continue
		for p in intersections(sk, e, o):
			cuts.append([param_of(sk, e, p), p, o["id"]])
	_dissolve_group(sk, e)
	match e["type"]:
		"line", "arc":
			var span := 1.0 if e["type"] == "line" else float(sk.arc_data(e)["sweep"])
			var tq := clampf(param_of(sk, e, click), 0.0, span)
			var tol := 1e-6 * maxf(span, 1.0)
			var lo = null
			var hi = null
			for c in cuts:
				var t: float = c[0]
				if t <= tol or t >= span - tol:
					continue
				if t < tq and (lo == null or t > float(lo[0])):
					lo = c
				elif t > tq and (hi == null or t < float(hi[0])):
					hi = c
			if lo == null and hi == null:
				sk.remove_entity(eid)
				return {"ok": true, "msg": I18n.t("Kesişim yok: öğe tamamen silindi.")}
			if lo == null:
				e["a"] = _end_point(sk, hi[1], hi[2])
			elif hi == null:
				e["b"] = _end_point(sk, lo[1], lo[2])
			else:
				var old_b: int = e["b"]
				var q1 := _end_point(sk, lo[1], lo[2])
				var q2 := _end_point(sk, hi[1], hi[2])
				e["b"] = q1
				var nid: int
				if e["type"] == "line":
					nid = sk.add_line(q2, old_b, e.get("construction", false))
					sk.add_constraint({"type": "collinear", "e1": eid, "e2": nid})
				else:
					nid = sk.add_arc(e["c"], q2, old_b, e.get("construction", false))
					sk.add_constraint({"type": "equal", "e1": eid, "e2": nid})
		"circle":
			if cuts.size() < 2:
				sk.remove_entity(eid)
				return {"ok": true, "msg": I18n.t("Dairede iki kesişim yok: tamamen silindi.")}
			var tq2 := param_of(sk, e, click)
			var lo2 = null
			var hi2 = null
			for c in cuts:
				var t2: float = c[0]
				var after := fposmod(t2 - tq2, TAU)
				var before := fposmod(tq2 - t2, TAU)
				if hi2 == null or after < fposmod(float(hi2[0]) - tq2, TAU):
					hi2 = c
				if lo2 == null or before < fposmod(tq2 - float(lo2[0]), TAU):
					lo2 = c
			var pa := _end_point(sk, hi2[1], hi2[2])
			var pb := _end_point(sk, lo2[1], lo2[2])
			var aid := sk.add_arc(e["c"], pa, pb, e.get("construction", false))
			for c in sk.constraints:
				for k in ["e1", "e2"]:
					if c.has(k) and int(c[k]) == eid:
						c[k] = aid
			for i in sk.entities.size():
				if sk.entities[i]["id"] == eid:
					sk.entities.remove_at(i)
					break
	sk._cleanup()
	return {"ok": true, "msg": I18n.t("Kırpıldı.")}


## Çizginin tıklanan ucunu ilk kesiştiği öğeye kadar uzatır.
static func extend(sk: Sketch, eid: int, click: Vector2) -> Dictionary:
	var e := sk.get_entity(eid)
	if not e.is_empty() and e["type"] == "arc":
		return _extend_arc(sk, e, click)
	if e.is_empty() or e["type"] != "line":
		return _fail(I18n.t("Uzatma çizgi ve yaylar için çalışır."))
	var A: Vector2 = sk.points[e["a"]]
	var B: Vector2 = sk.points[e["b"]]
	var key := "a" if click.distance_to(A) < click.distance_to(B) else "b"
	var P: Vector2 = A if key == "a" else B
	var Q: Vector2 = B if key == "a" else A
	var d := (P - Q).normalized()
	var far := P + d * 1.0e5
	var best := INF
	var best_p := Vector2.ZERO
	var best_o := -1
	for o in sk.entities:
		if o["id"] == eid or o["type"] == "text":
			continue
		for pr in _prims(sk, o):
			var hits: Array = []
			if pr[0] == "seg":
				var h = Geometry2D.segment_intersects_segment(P, far, pr[1], pr[2])
				if h != null:
					hits.append(h)
			else:
				for h2 in _line_circle(P, far, pr[1], pr[2]):
					if _on_arc(sk, pr[3], h2):
						hits.append(h2)
			for h3 in hits:
				var t := ((h3 as Vector2) - P).dot(d)
				if t > 1e-6 and t < best:
					best = t
					best_p = h3
					best_o = o["id"]
	if best_o < 0:
		return _fail(I18n.t("Uzatılacak bir sınır bulunamadı."))
	_dissolve_group(sk, e)
	var pid: int = e[key]
	if sk.point_users(pid).size() > 1 or pid == Sketch.ORIGIN:
		e[key] = _end_point(sk, best_p, best_o)
	else:
		var reuse := -1
		for opid in Sketch.entity_point_ids(sk.get_entity(best_o)):
			if (sk.points[opid] as Vector2).distance_to(best_p) < 1e-6:
				reuse = opid
		if reuse >= 0:
			e[key] = reuse
		else:
			sk.points[pid] = best_p
			var oe := sk.get_entity(best_o)
			if oe["type"] in ["line", "circle", "arc"]:
				sk.add_constraint({"type": "coincident", "p1": pid, "e1": best_o})
	sk._cleanup()
	return {"ok": true, "msg": I18n.t("Uzatıldı.")}


## Yayı tıklanan ucundan, çemberi boyunca ilk kesiştiği öğeye kadar uzatır.
static func _extend_arc(sk: Sketch, e: Dictionary, click: Vector2) -> Dictionary:
	var ad := sk.arc_data(e)
	var c: Vector2 = ad["c"]
	var r: float = ad["r"]
	var a0: float = ad["a0"]
	var sweep: float = ad["sweep"]
	var key := "a" if click.distance_to(ad["pa"]) < click.distance_to(ad["pb"]) else "b"
	var circ := [["circ", c, r, null]]
	var best := INF
	var best_p := Vector2.ZERO
	var best_o := -1
	for o in sk.entities:
		if o["id"] == e["id"] or o["type"] == "text":
			continue
		for p in prim_intersections(sk, circ, _prims(sk, o)):
			var ang := fposmod(((p as Vector2) - c).angle() - a0, TAU)
			if ang <= sweep + 1e-7:
				continue
			var dist := ang - sweep if key == "b" else TAU - ang
			if dist > 1e-7 and dist < best:
				best = dist
				best_p = p
				best_o = o["id"]
	if best_o < 0:
		return _fail(I18n.t("Yayın uzatılacağı bir sınır bulunamadı."))
	var pid: int = e[key]
	if sk.point_users(pid).size() > 1:
		e[key] = _end_point(sk, best_p, best_o)
	else:
		sk.points[pid] = best_p
		var oe := sk.get_entity(best_o)
		if oe["type"] in ["line", "circle", "arc"]:
			sk.add_constraint({"type": "coincident", "p1": pid, "e1": best_o})
	sk._cleanup()
	return {"ok": true, "msg": I18n.t("Yay uzatıldı.")}


# ================================================================ varlıkları dönüştür

static func _circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Variant:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 1e-12:
		return null
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	return Vector2((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
		(a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)


## Kapalı nokta döngülerini (ör. model yüzeyinin kenarları) çizgi / yay / daireye çevirir.
## Eşit kirişli ve eşit dönüşlü ardışık parçalar yay, doğrusal parçalar tek çizgi olur.
## Oluşan öğeler sabitlenir ("kenar üzerinde" ilişkisinin karşılığı).
static func convert_loops(sk: Sketch, loops: Array, fix := true) -> Dictionary:
	var new_ids: Array = []
	for loop0 in loops:
		var P := PackedVector2Array()
		for q in loop0:
			if P.is_empty() or (P[P.size() - 1] as Vector2).distance_to(q) > 1e-6:
				P.append(q)
		if P.size() > 2 and P[0].distance_to(P[P.size() - 1]) < 1e-6:
			P.remove_at(P.size() - 1)
		var n := P.size()
		if n < 3:
			continue
		var turn := PackedFloat64Array()
		turn.resize(n)
		var elen := PackedFloat64Array()
		elen.resize(n)
		for k in n:
			elen[k] = P[k].distance_to(P[(k + 1) % n])
		for k in n:
			var ein := P[k] - P[(k - 1 + n) % n]
			var eout := P[(k + 1) % n] - P[k]
			turn[k] = ein.angle_to(eout)
		var is_arc_v := func(k: int, th: float, L: float) -> bool:
			return absf(turn[k]) > 1e-5 and absf(turn[k]) < 0.4 and absf(turn[k] - th) < 1e-4 * maxf(1.0, absf(th) * 50.0) and absf(elen[k] - L) < 1e-4 * maxf(L, 1.0)
		# Tam daire mi?
		var full := true
		for k in n:
			if not is_arc_v.call(k, turn[0], elen[0]):
				full = false
				break
		if full and n >= 8:
			var cc = _circumcenter(P[0], P[n / 3], P[2 * n / 3])
			if cc != null:
				var cid := sk.add_circle(sk.add_point(cc), (cc as Vector2).distance_to(P[0]))
				new_ids.append(cid)
				continue
		# Bir köşeden başla (yay/çizgi devamlılığının bozulduğu yer)
		var start := 0
		for k in n:
			var prev := (k - 1 + n) % n
			var smooth: bool = absf(turn[k]) < 1e-5 or (absf(turn[k] - turn[prev]) < 1e-4 and absf(elen[k] - elen[prev]) < 1e-4 * maxf(elen[k], 1.0))
			if not smooth:
				start = k
				break
		var runs: Array = []
		var run := {"k0": start, "count": 1, "kind": "", "th": 0.0, "L": elen[start]}
		for step in range(1, n):
			var k2 := (start + step) % n
			var t := turn[k2]
			var add := false
			if run["count"] == 1:
				if absf(t) < 1e-5:
					run["kind"] = "line"
					add = true
				elif absf(t) < 0.4 and absf(elen[k2] - float(run["L"])) < 1e-4 * maxf(float(run["L"]), 1.0):
					run["kind"] = "arc"
					run["th"] = t
					add = true
			elif run["kind"] == "line" and absf(t) < 1e-5:
				add = true
			elif run["kind"] == "arc" and is_arc_v.call(k2, float(run["th"]), float(run["L"])):
				add = true
			if add:
				run["count"] = int(run["count"]) + 1
			else:
				runs.append(run)
				run = {"k0": k2, "count": 1, "kind": "", "th": 0.0, "L": elen[k2]}
		runs.append(run)
		# Öğeleri oluştur (ardışık öğeler uç noktalarını paylaşır)
		var pid_at := {}
		var get_pid := func(k: int) -> int:
			var kk := k % n
			if not pid_at.has(kk):
				pid_at[kk] = sk.add_point(P[kk])
			return pid_at[kk]
		for rn in runs:
			var k0: int = rn["k0"]
			var cnt: int = rn["count"]
			var k1 := k0 + cnt
			if rn["kind"] == "arc" and cnt >= 2:
				var mid := P[(k0 + cnt / 2) % n]
				var cc2 = _circumcenter(P[k0 % n], mid, P[k1 % n])
				if cc2 != null:
					var cpid := sk.add_point(cc2)
					var pa: int = get_pid.call(k0)
					var pb: int = get_pid.call(k1)
					new_ids.append(sk.add_arc(cpid, pa, pb) if float(rn["th"]) > 0.0 else sk.add_arc(cpid, pb, pa))
					continue
			new_ids.append(sk.add_line(get_pid.call(k0), get_pid.call(k1)))
	if new_ids.is_empty():
		return _fail(I18n.t("Dönüştürülecek kenar bulunamadı."))
	if fix:
		for eid in new_ids:
			sk.add_constraint({"type": "fix", "e1": eid})
	return {"ok": true, "msg": I18n.t("%d öğe dönüştürüldü (kenarlara sabitlendi).") % new_ids.size(), "ids": new_ids}


## B-rep kenarlarını (OpenCASCADE) taslağa gerçek eğriler olarak alır: çizgi, daire/yay, elips;
## diğer eğriler noktalarından geçen spline olur. Ardışık kenarlar uç noktalarını paylaşır.
## edges: ModelMesh.brep_edges öğeleri {type, pts, o?, r?, r2?, n?, xd?, closed?}
static func convert_brep_edges(sk: Sketch, plane: SketchPlane, edges: Array, fix := true) -> Dictionary:
	var new_ids: Array = []
	var pid_of := {}
	var nrm := plane.normal()
	var get_pid := func(p: Vector2) -> int:
		var key := Vector2i(roundi(p.x * 1e5), roundi(p.y * 1e5))
		if not pid_of.has(key):
			pid_of[key] = sk.add_point(p)
		return pid_of[key]
	for e in edges:
		var pts: PackedVector3Array = e["pts"]
		if pts.size() < 2:
			continue
		var p0 := plane.to_local(pts[0])
		var p1 := plane.to_local(pts[pts.size() - 1])
		var closed: bool = bool(e.get("closed", false)) or pts[0].distance_to(pts[pts.size() - 1]) < 1e-6
		var axis_ok: bool = e.has("n") and absf(ModelMesh._v3(e["n"]).normalized().dot(nrm)) > 0.999999
		var kind := str(e.get("type", ""))
		if kind == "line":
			if p0.distance_to(p1) > 1e-6:
				new_ids.append(sk.add_line(get_pid.call(p0), get_pid.call(p1)))
			continue
		if kind == "circle" and axis_ok:
			var c := plane.to_local(ModelMesh._v3(e["o"]))
			if closed:
				new_ids.append(sk.add_circle(sk.add_point(c), float(e["r"])))
				continue
			var pm := plane.to_local(pts[pts.size() / 2])
			var cp := sk.add_point(c)
			var ia: int = get_pid.call(p0)
			var ib: int = get_pid.call(p1)
			new_ids.append(sk.add_arc(cp, ia, ib) if (p0 - c).cross(pm - c) > 0.0 else sk.add_arc(cp, ib, ia))
			continue
		if kind == "ellipse" and axis_ok and closed:
			var o3 := ModelMesh._v3(e["o"])
			var c2 := plane.to_local(o3)
			var xd := (plane.to_local(o3 + ModelMesh._v3(e["xd"])) - c2).normalized()
			new_ids.append(sk.add_ellipse(sk.add_point(c2), sk.add_point(c2 + xd * float(e["r"])), float(e["r2"])))
			continue
		# Diğer eğriler (B-spline, kesişim eğrileri, eğik izdüşümler): noktalardan geçen spline
		var proj := PackedVector2Array()
		for q in pts:
			var l := plane.to_local(q)
			if proj.is_empty() or proj[proj.size() - 1].distance_to(l) > 1e-4:
				proj.append(l)
		if proj.size() < 2:
			continue
		if proj.size() == 2:
			new_ids.append(sk.add_line(get_pid.call(proj[0]), get_pid.call(proj[1])))
			continue
		var pids: Array = [get_pid.call(proj[0])]
		for i in range(1, proj.size() - 1):
			pids.append(sk.add_point(proj[i]))
		pids.append(pids[0] if closed else get_pid.call(proj[proj.size() - 1]))
		new_ids.append(sk.add_spline(pids))
	if new_ids.is_empty():
		return _fail(I18n.t("Dönüştürülecek kenar bulunamadı."))
	if fix:
		for eid in new_ids:
			sk.add_constraint({"type": "fix", "e1": eid})
	return {"ok": true, "msg": I18n.t("%d kenar dönüştürüldü (B-rep, kenarlara sabitlendi).") % new_ids.size(), "ids": new_ids}


# ================================================================ ofset

## Seçili kenarlardan zincirler: [{items: [[eid, ileri]], closed: bool}] ; daireler ayrı zincir.
static func chains(sk: Sketch, eids: Array) -> Array:
	var edges := {}
	var adj := {}
	var out: Array = []
	for eid in eids:
		var e := sk.get_entity(eid)
		if e.is_empty():
			continue
		if e["type"] == "circle":
			out.append({"items": [[eid, true]], "closed": true})
		elif e["type"] == "line" or e["type"] == "arc":
			edges[eid] = Sketch.edge_ends(e)
			for pid in edges[eid]:
				if not adj.has(pid):
					adj[pid] = []
				adj[pid].append(eid)
	var used := {}
	for eid in edges:
		if used.has(eid):
			continue
		# Zincirin başına git
		var cur: int = eid
		var cur_pt: int = edges[cur][0]
		var guard := 0
		while (adj[cur_pt] as Array).size() == 2 and guard < 1000:
			var other: int = adj[cur_pt][0] if adj[cur_pt][0] != cur else adj[cur_pt][1]
			if other == eid:
				break
			cur = other
			cur_pt = edges[cur][0] if edges[cur][1] == cur_pt else edges[cur][1]
			guard += 1
		# İleri yürü
		var items: Array = []
		var start_edge := cur
		var pt := cur_pt
		var closed := false
		guard = 0
		while guard < 1000:
			used[cur] = true
			var fwd: bool = edges[cur][0] == pt
			items.append([cur, fwd])
			pt = edges[cur][1] if fwd else edges[cur][0]
			var nb: Array = adj[pt]
			if nb.size() != 2:
				break
			var nxt: int = nb[0] if nb[0] != cur else nb[1]
			if nxt == start_edge:
				closed = true
				break
			if used.has(nxt):
				break
			cur = nxt
			guard += 1
		out.append({"items": items, "closed": closed})
	return out


## Ofset geometrisi (önizleme ve oluşturma için). dist > 0: kapalı zincirde dışa, açıkta sola.
## Dönüş: [{"pieces": [{type, eid, ...}], "closed": bool, "joints": [Vector2]}]
static func offset_geometry(sk: Sketch, eids: Array, dist: float) -> Array:
	var result: Array = []
	for ch in chains(sk, eids):
		var items: Array = ch["items"]
		var closed: bool = ch["closed"]
		var pieces: Array = []
		if items.size() == 1 and sk.get_entity(items[0][0])["type"] == "circle":
			var ce := sk.get_entity(items[0][0])
			var r := float(ce["r"]) + dist
			if r <= 1e-6:
				continue
			result.append({"pieces": [{"type": "circle", "eid": ce["id"], "c": ce["c"], "r": r}], "closed": true})
			continue
		# Kapalı zincirin yönüne göre "dış" tarafı belirle
		var sgn := 1.0
		if closed:
			var poly := PackedVector2Array()
			for it in items:
				var pts := sk._edge_points(sk.get_entity(it[0]), it[1])
				for i in pts.size() - 1:
					poly.append(pts[i])
			sgn = -1.0 if Sketch.polygon_area(poly) > 0.0 else 1.0
		var off := dist * sgn
		for it in items:
			var e := sk.get_entity(it[0])
			var fwd: bool = it[1]
			if e["type"] == "line":
				var a: Vector2 = sk.points[e["a"]]
				var b: Vector2 = sk.points[e["b"]]
				if not fwd:
					var t := a
					a = b
					b = t
				var dir := (b - a).normalized()
				var n := Vector2(-dir.y, dir.x)
				pieces.append({"type": "line", "eid": e["id"], "p0": a + n * off, "p1": b + n * off})
			else:
				var ad := sk.arc_data(e)
				var r2: float = float(ad["r"]) - off if fwd else float(ad["r"]) + off
				if r2 <= 1e-6:
					return []
				var c: Vector2 = ad["c"]
				var a0: float = ad["a0"]
				var a1: float = a0 + float(ad["sweep"])
				var s_ang := a0 if fwd else a1
				var e_ang := a1 if fwd else a0
				pieces.append({"type": "arc", "eid": e["id"], "c": e["c"], "cpos": c, "r": r2, "fwd": fwd,
					"p0": c + Vector2.from_angle(s_ang) * r2, "p1": c + Vector2.from_angle(e_ang) * r2})
		# Komşu parçaları birleştir
		var n_p := pieces.size()
		var last := n_p if closed else n_p - 1
		for i in last:
			var A: Dictionary = pieces[i]
			var Bp: Dictionary = pieces[(i + 1) % n_p]
			var j := _join(A, Bp)
			A["p1"] = j
			Bp["p0"] = j
		result.append({"pieces": pieces, "closed": closed})
	return result


static func _join(A: Dictionary, B: Dictionary) -> Vector2:
	var guess: Vector2 = A["p1"]
	var cands: Array = []
	if A["type"] == "line" and B["type"] == "line":
		var h = Geometry2D.line_intersects_line(A["p0"], (A["p1"] as Vector2) - (A["p0"] as Vector2), B["p0"], (B["p1"] as Vector2) - (B["p0"] as Vector2))
		if h != null:
			cands.append(h)
	elif A["type"] == "line":
		cands = _line_circle(A["p0"], A["p1"], B["cpos"], B["r"], false)
	elif B["type"] == "line":
		cands = _line_circle(B["p0"], B["p1"], A["cpos"], A["r"], false)
	else:
		cands = _circle_circle(A["cpos"], A["r"], B["cpos"], B["r"])
	var best := guess
	var bd := INF
	for q in cands:
		var dd := (q as Vector2).distance_to(guess)
		if dd < bd:
			bd = dd
			best = q
	if bd > 1e6:
		return guess
	return best


## Ofseti oluşturur. Çizgilere paralel + tek bir ana ofset boyutu bağlanır.
static func offset(sk: Sketch, eids: Array, dist: float) -> Dictionary:
	var splines: Array = []
	var rest: Array = []
	for eid in eids:
		if sk.get_entity(eid).get("type", "") == "spline":
			splines.append(eid)
		else:
			rest.append(eid)
	var new_ids: Array = []
	for sid in splines:
		var nid := _offset_spline(sk, sid, dist)
		if nid >= 0:
			new_ids.append(nid)
	var geo := offset_geometry(sk, rest, dist) if not rest.is_empty() else []
	if geo.is_empty() and new_ids.is_empty():
		return _fail(I18n.t("Ofset uygulanamadı (seçim boş veya mesafe yayları tersine çeviriyor)."))
	var master := -1
	for ch in geo:
		var pieces: Array = ch["pieces"]
		if pieces.size() == 1 and pieces[0]["type"] == "circle":
			var pc: Dictionary = pieces[0]
			var cid := sk.add_circle(pc["c"], pc["r"])
			new_ids.append(cid)
			var dim := {"type": "offset", "e1": cid, "e2": pc["eid"], "value": absf(dist), "s": signf(dist) if dist != 0.0 else 1.0}
			sk.add_constraint(dim)
			continue
		var closed: bool = ch["closed"]
		var pts: Array = []
		for i in pieces.size():
			pts.append(sk.add_point(pieces[i]["p0"]))
		if not closed:
			pts.append(sk.add_point(pieces[pieces.size() - 1]["p1"]))
		for i in pieces.size():
			var pc2: Dictionary = pieces[i]
			var a: int = pts[i]
			var b: int = pts[(i + 1) % pts.size()] if closed else pts[i + 1]
			var nid: int
			if pc2["type"] == "line":
				nid = sk.add_line(a, b)
				var orig := int(pc2["eid"])
				if master < 0:
					sk.add_constraint({"type": "parallel", "e1": nid, "e2": orig})
					var spec := {"type": "pl_distance", "p1": a, "e1": orig}
					var mc := SketchSolver.make_dimension(sk, spec, ((pc2["p0"] as Vector2) + (pc2["p1"] as Vector2)) * 0.5)
					master = sk.add_constraint(mc)
				else:
					sk.add_constraint({"type": "offset", "e1": nid, "e2": orig, "master": master,
						"s": signf(SketchSolver.signed_line_dist(sk, orig, pc2["p0"]))})
			else:
				nid = sk.add_arc(pc2["c"], a, b) if pc2["fwd"] else sk.add_arc(pc2["c"], b, a)
			new_ids.append(nid)
	return {"ok": true, "msg": I18n.t("Ofset oluşturuldu."), "ids": new_ids, "master": master}


## Spline ofseti: kontrol noktaları eğrinin o noktadaki normali boyunca kaydırılır (yaklaşık ofset).
## dist > 0: kapalı spline'da dışa, açıkta sola.
static func _offset_spline(sk: Sketch, sid: int, dist: float) -> int:
	var e := sk.get_entity(sid)
	var ids: Array = e["pts"]
	var closed: bool = ids.size() > 2 and ids[0] == ids[ids.size() - 1]
	var P: Array = []
	for i in ids.size():
		if closed and i == ids.size() - 1:
			break
		P.append(sk.points[ids[i]])
	var n := P.size()
	if n < 2:
		return -1
	var off := dist
	if closed:
		var poly := sk.spline_points(e)
		if Sketch.polygon_area(poly) > 0.0:
			off = -dist
	var new_pids: Array = []
	for i in n:
		var prev: Vector2 = P[(i - 1 + n) % n] if (closed or i > 0) else P[i]
		var nxt: Vector2 = P[(i + 1) % n] if (closed or i < n - 1) else P[i]
		var t := (nxt - prev).normalized()
		var nrm := Vector2(-t.y, t.x)
		new_pids.append(sk.add_point((P[i] as Vector2) + nrm * off))
	if closed:
		new_pids.append(new_pids[0])
	return sk.add_spline(new_pids, e.get("construction", false))


# ================================================================ aynala

static func reflect(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var d := (b - a).normalized()
	var v := p - a
	return a + d * (2.0 * v.dot(d)) - v


## Seçili öğeleri merkez çizgisine göre aynalar; noktalar arasına simetrik ilişkisi ekler.
static func mirror(sk: Sketch, eids: Array, axis_eid: int) -> Dictionary:
	var ax := sk.get_entity(axis_eid)
	if ax.is_empty() or ax["type"] != "line":
		return _fail(I18n.t("Ayna ekseni bir çizgi olmalı."))
	var A: Vector2 = sk.points[ax["a"]]
	var B: Vector2 = sk.points[ax["b"]]
	var pmap := {}
	var new_ids: Array = []
	for eid in eids:
		if eid == axis_eid:
			continue
		var e := sk.get_entity(eid)
		if e.is_empty() or e["type"] == "text":
			continue
		for pid in Sketch.entity_point_ids(e):
			if pmap.has(pid):
				continue
			var p: Vector2 = sk.points[pid]
			if absf(SketchSolver.signed_line_dist(sk, axis_eid, p)) < 1e-6:
				pmap[pid] = pid
			else:
				var np := sk.add_point(reflect(p, A, B))
				pmap[pid] = np
				sk.add_constraint({"type": "symmetric", "p1": pid, "p2": np, "e1": axis_eid})
		var cons: bool = e.get("construction", false)
		match e["type"]:
			"line":
				new_ids.append(sk.add_line(pmap[e["a"]], pmap[e["b"]], cons))
			"circle":
				var cid := sk.add_circle(pmap[e["c"]], float(e["r"]), cons)
				new_ids.append(cid)
				sk.add_constraint({"type": "equal", "e1": eid, "e2": cid})
			"arc":
				new_ids.append(sk.add_arc(pmap[e["c"]], pmap[e["b"]], pmap[e["a"]], cons))
			"spline":
				var np2: Array = []
				for pid in e["pts"]:
					np2.append(pmap[pid])
				new_ids.append(sk.add_spline(np2, cons))
			"ellipse":
				var mid := sk.add_ellipse(pmap[e["c"]], pmap[e["m"]], float(e["rb"]), cons)
				new_ids.append(mid)
				sk.add_constraint({"type": "equal", "e1": eid, "e2": mid})
			"parabola":
				new_ids.append(sk.add_parabola(pmap[e["v"]], pmap[e["f"]], pmap[e["a"]], pmap[e["b"]], cons))
	if new_ids.is_empty():
		return _fail(I18n.t("Aynalanacak öğe yok."))
	return {"ok": true, "msg": I18n.t("Aynalandı."), "ids": new_ids}


# ================================================================ köşe yuvarlatma / pah

## Köşe noktası (iki çizginin ortak ucu) -> {L1, L2, A, B} veya {}
static func corner_info(sk: Sketch, pid: int) -> Dictionary:
	var users: Array = []
	for eid in sk.point_users(pid):
		if not sk.get_entity(eid).get("construction", false):
			users.append(eid)
	if users.size() != 2:
		return {}
	var e1 := sk.get_entity(users[0])
	var e2 := sk.get_entity(users[1])
	if e1["type"] != "line" or e2["type"] != "line":
		return {}
	var a: int = e1["b"] if e1["a"] == pid else e1["a"]
	var b: int = e2["b"] if e2["a"] == pid else e2["a"]
	return {"L1": e1["id"], "L2": e2["id"], "A": a, "B": b}


## İki çizginin köşesini r yarıçaplı teğet yayla yuvarlatır. Eski köşe sanal köşe olarak kalır.
static func fillet(sk: Sketch, pid: int, r: float) -> Dictionary:
	var ci := corner_info(sk, pid)
	if ci.is_empty():
		return _fail(I18n.t("Köşe yuvarlatma için iki çizginin birleştiği bir köşe seçin."))
	var P: Vector2 = sk.points[pid]
	var u1: Vector2 = ((sk.points[ci["A"]] as Vector2) - P)
	var u2: Vector2 = ((sk.points[ci["B"]] as Vector2) - P)
	var l1 := u1.length()
	var l2 := u2.length()
	u1 = u1.normalized()
	u2 = u2.normalized()
	var th := acos(clampf(u1.dot(u2), -1.0, 1.0))
	if th < 1e-3 or th > PI - 1e-3:
		return _fail(I18n.t("Çizgiler doğrusal; köşe yok."))
	var d := r / tan(th * 0.5)
	if d >= l1 - 1e-6 or d >= l2 - 1e-6:
		return _fail(I18n.t("Yarıçap bu köşe için çok büyük."))
	var T1 := P + u1 * d
	var T2 := P + u2 * d
	var C := P + (u1 + u2).normalized() * (r / sin(th * 0.5))
	var L1 := sk.get_entity(ci["L1"])
	var L2 := sk.get_entity(ci["L2"])
	_dissolve_group(sk, L1)
	_dissolve_group(sk, L2)
	var t1 := sk.add_point(T1)
	var t2 := sk.add_point(T2)
	var c := sk.add_point(C)
	L1["a" if L1["a"] == pid else "b"] = t1
	L2["a" if L2["a"] == pid else "b"] = t2
	var arc: int
	if (T1 - C).cross(T2 - C) > 0.0:
		arc = sk.add_arc(c, t1, t2)
	else:
		arc = sk.add_arc(c, t2, t1)
	sk.virtual_points[pid] = true
	sk.add_constraint({"type": "coincident", "p1": pid, "e1": ci["L1"]})
	sk.add_constraint({"type": "coincident", "p1": pid, "e1": ci["L2"]})
	sk.add_constraint({"type": "tangent", "e1": ci["L1"], "e2": arc})
	sk.add_constraint({"type": "tangent", "e1": ci["L2"], "e2": arc})
	var dim := SketchSolver.make_dimension(sk, {"type": "radius", "e1": arc}, C + (P - C).normalized() * r * 2.2)
	dim["value"] = r
	var dim_id := sk.add_constraint(dim)
	sk._cleanup()
	return {"ok": true, "msg": I18n.t("Köşe yuvarlatıldı (R %s).") % Units.format_length(r), "arc": arc, "dim": dim_id}


## Köşeyi d mesafeli eşit pah ile keser.
static func chamfer(sk: Sketch, pid: int, d: float) -> Dictionary:
	var ci := corner_info(sk, pid)
	if ci.is_empty():
		return _fail(I18n.t("Pah için iki çizginin birleştiği bir köşe seçin."))
	var P: Vector2 = sk.points[pid]
	var v1: Vector2 = (sk.points[ci["A"]] as Vector2) - P
	var v2: Vector2 = (sk.points[ci["B"]] as Vector2) - P
	if d >= v1.length() - 1e-6 or d >= v2.length() - 1e-6:
		return _fail(I18n.t("Pah mesafesi bu köşe için çok büyük."))
	if absf(v1.normalized().cross(v2.normalized())) < 1e-3:
		return _fail(I18n.t("Çizgiler doğrusal; köşe yok."))
	var L1 := sk.get_entity(ci["L1"])
	var L2 := sk.get_entity(ci["L2"])
	_dissolve_group(sk, L1)
	_dissolve_group(sk, L2)
	var t1 := sk.add_point(P + v1.normalized() * d)
	var t2 := sk.add_point(P + v2.normalized() * d)
	L1["a" if L1["a"] == pid else "b"] = t1
	L2["a" if L2["a"] == pid else "b"] = t2
	var ln := sk.add_line(t1, t2)
	sk.virtual_points[pid] = true
	sk.add_constraint({"type": "coincident", "p1": pid, "e1": ci["L1"]})
	sk.add_constraint({"type": "coincident", "p1": pid, "e1": ci["L2"]})
	var mid := (P * 2.0 + (sk.points[t1] as Vector2) + (sk.points[t2] as Vector2)) / 4.0
	var d1 := SketchSolver.make_dimension(sk, {"type": "distance", "p1": pid, "p2": t1}, mid + v1.normalized() * d * 0.5)
	d1["value"] = d
	var id1 := sk.add_constraint(d1)
	var d2 := SketchSolver.make_dimension(sk, {"type": "distance", "p1": pid, "p2": t2}, mid + v2.normalized() * d * 0.5)
	d2["value"] = d
	sk.add_constraint(d2)
	sk._cleanup()
	return {"ok": true, "msg": I18n.t("Pah kırıldı (%s).") % Units.format_length(d), "line": ln, "dim": id1}


# ================================================================ çokgen / kanal

## Düzgün çokgen: yapı çemberi + çember üzerinde köşeler + eşit kenarlar (4 serbestlik).
static func add_polygon(sk: Sketch, center_pid: int, vertex: Vector2, n: int) -> Dictionary:
	n = clampi(n, 3, 64)
	var C: Vector2 = sk.points[center_pid]
	var r := C.distance_to(vertex)
	if r < 1e-6:
		return _fail(I18n.t("Çokgen yarıçapı sıfır."))
	var a0 := (vertex - C).angle()
	var circ := sk.add_circle(center_pid, r, true)
	var pids: Array = []
	for k in n:
		pids.append(sk.add_point(C + Vector2.from_angle(a0 + TAU * k / n) * r))
	var lines: Array = []
	for k in n:
		lines.append(sk.add_line(pids[k], pids[(k + 1) % n]))
		sk.add_constraint({"type": "coincident", "p1": pids[k], "e1": circ})
	for k in range(1, n):
		sk.add_constraint({"type": "equal", "e1": lines[0], "e2": lines[k]})
	return {"ok": true, "msg": I18n.t("%d kenarlı çokgen.") % n, "ids": lines, "circle": circ}


## Düz kanal: iki uç merkezi + genişlik. Merkez çizgisi, iki yay, iki teğet çizgi.
static func add_slot(sk: Sketch, c1_pid: int, c2_pid: int, half_w: float) -> Dictionary:
	var C1: Vector2 = sk.points[c1_pid]
	var C2: Vector2 = sk.points[c2_pid]
	if C1.distance_to(C2) < 1e-6 or half_w < 1e-6:
		return _fail(I18n.t("Kanal boyutları geçersiz."))
	var u := (C2 - C1).normalized()
	var n := Vector2(-u.y, u.x)
	var p1 := sk.add_point(C1 + n * half_w)
	var p2 := sk.add_point(C2 + n * half_w)
	var p3 := sk.add_point(C2 - n * half_w)
	var p4 := sk.add_point(C1 - n * half_w)
	sk.add_line(c1_pid, c2_pid, true)
	var top := sk.add_line(p1, p2)
	var right := sk.add_arc(c2_pid, p3, p2)
	var bottom := sk.add_line(p3, p4)
	var left := sk.add_arc(c1_pid, p1, p4)
	sk.add_constraint({"type": "tangent", "e1": top, "e2": right})
	sk.add_constraint({"type": "tangent", "e1": top, "e2": left})
	sk.add_constraint({"type": "tangent", "e1": bottom, "e2": right})
	sk.add_constraint({"type": "tangent", "e1": bottom, "e2": left})
	sk.add_constraint({"type": "equal", "e1": left, "e2": right})
	return {"ok": true, "msg": I18n.t("Kanal oluşturuldu."), "ids": [top, right, bottom, left]}


# ================================================================ kopyala / taşı / döndür / ölçekle / çoğalt

## Öğeleri dönüşümle kopyalar. İç ilişkiler ve boyutlar da kopyalanır.
## xf: Callable(Vector2) -> Vector2 ; scale: uzunluk boyutları ve yarıçaplar için çarpan ; flip: aynalama (yay yönü)
static func copy_entities(sk: Sketch, eids: Array, xf: Callable, scale := 1.0, flip := false) -> Array:
	var pmap := {}
	var emap := {}
	var sel := {}
	for eid in eids:
		sel[eid] = true
	for eid in eids:
		var e := sk.get_entity(eid)
		if e.is_empty():
			continue
		for pid in Sketch.entity_point_ids(e):
			if not pmap.has(pid):
				pmap[pid] = sk.add_point(xf.call(sk.points[pid]))
		var cons: bool = e.get("construction", false)
		var nid := -1
		match e["type"]:
			"line":
				nid = sk.add_line(pmap[e["a"]], pmap[e["b"]], cons)
			"circle":
				nid = sk.add_circle(pmap[e["c"]], float(e["r"]) * scale, cons)
			"arc":
				nid = sk.add_arc(pmap[e["c"]], pmap[e["b"]], pmap[e["a"]], cons) if flip else sk.add_arc(pmap[e["c"]], pmap[e["a"]], pmap[e["b"]], cons)
			"spline":
				var np: Array = []
				for pid in e["pts"]:
					np.append(pmap[pid])
				nid = sk.add_spline(np, cons)
			"text":
				nid = sk.add_text(pmap[e["p"]], str(e["text"]), float(e["h"]) * scale)
			"ellipse":
				nid = sk.add_ellipse(pmap[e["c"]], pmap[e["m"]], float(e["rb"]) * scale, cons)
			"parabola":
				nid = sk.add_parabola(pmap[e["v"]], pmap[e["f"]], pmap[e["a"]], pmap[e["b"]], cons)
		if nid >= 0:
			emap[eid] = nid
	# Seçim içinde kalan ilişki ve boyutları kopyala
	for c in sk.constraints.duplicate():
		if c["type"] == "fix" or c["type"] == "offset":
			continue
		var inside := true
		for eid in Sketch.constraint_entities(c):
			if not emap.has(eid):
				inside = false
		for pid in Sketch.constraint_points(c):
			if not pmap.has(pid):
				inside = false
		if not inside or (Sketch.constraint_entities(c).is_empty() and Sketch.constraint_points(c).is_empty()):
			continue
		if flip and c["type"] in ["hdistance", "vdistance", "pl_distance", "angle"]:
			continue
		var nc: Dictionary = c.duplicate(true)
		nc.erase("id")
		nc.erase("num")
		for k in ["e1", "e2"]:
			if nc.has(k):
				nc[k] = emap[int(nc[k])]
		for k in ["p1", "p2"]:
			if nc.has(k):
				nc[k] = pmap[int(nc[k])]
		if Sketch.is_dimension(nc) and nc["type"] != "angle":
			nc["value"] = float(nc["value"]) * scale
		sk.add_constraint(nc)
	return emap.values()


## Seçili öğelerin noktalarını yerinde dönüştürür (taşı / döndür / ölçekle). Taşınan noktaları döndürür.
static func transform_points(sk: Sketch, eids: Array, xf: Callable, scale := 1.0) -> Array:
	var moved := {}
	for eid in eids:
		var e := sk.get_entity(eid)
		if e.is_empty():
			continue
		for pid in Sketch.entity_point_ids(e):
			if pid == Sketch.ORIGIN or moved.has(pid):
				continue
			sk.points[pid] = xf.call(sk.points[pid])
			moved[pid] = true
		if e["type"] == "circle":
			e["r"] = float(e["r"]) * scale
		if e["type"] == "ellipse":
			e["rb"] = float(e["rb"]) * scale
		if e["type"] == "text":
			e["h"] = float(e["h"]) * scale
	return moved.keys()


static func linear_pattern(sk: Sketch, eids: Array, step: Vector2, count: int) -> Array:
	var out: Array = []
	for i in range(1, clampi(count, 1, 200)):
		var off := step * i
		out.append_array(copy_entities(sk, eids, func(p: Vector2) -> Vector2: return p + off))
	return out


static func circular_pattern(sk: Sketch, eids: Array, center: Vector2, count: int, total_deg: float) -> Array:
	var out: Array = []
	count = clampi(count, 1, 360)
	var full := absf(absf(total_deg) - 360.0) < 1e-6
	var step := deg_to_rad(total_deg) / (count if full else maxi(count - 1, 1))
	for i in range(1, count):
		var ang := step * i
		out.append_array(copy_entities(sk, eids, func(p: Vector2) -> Vector2: return center + (p - center).rotated(ang)))
	return out
