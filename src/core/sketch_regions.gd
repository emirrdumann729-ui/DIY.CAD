class_name SketchRegions
extends RefCounted
## Bölge seçme (Contour Select): kesişen/çakışan eğrilerden oluşan düzlemsel yüzleri bulur.
## Tüm eğriler parçalara ayrılır, kesişim noktalarından bölünür, sarkan kenarlar atılır ve
## yarım kenar dolaşımıyla sınırlı yüzler çıkarılır. Delikler, onları içeren en küçük yüze atanır.
##
## Dönüş: [{outer: PackedVector2Array (CCW), holes: [PackedVector2Array], area: float, sample: Vector2}]

const Q := 100000.0   # köşe birleştirme ızgarası (0.00001 mm)


static func _key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * Q), roundi(p.y * Q))


static func faces(sk: Sketch) -> Array:
	# 1) Eğrileri parçalara böl
	var segs: Array = []   # [a: Vector2, b: Vector2]
	for e in sk.entities:
		if e.get("construction", false):
			continue
		for poly in sk.entity_polylines(e):
			var pl: PackedVector2Array = poly
			for i in pl.size() - 1:
				if pl[i].distance_to(pl[i + 1]) > 1e-7:
					segs.append([pl[i], pl[i + 1]])
	var ns := segs.size()
	if ns < 3:
		return []
	# 2) Izgara ile kesişim adayları
	var bb := Rect2(segs[0][0], Vector2.ZERO)
	for s in segs:
		bb = bb.expand(s[0]).expand(s[1])
	var cell := maxf(maxf(bb.size.x, bb.size.y) / 48.0, 1e-3)
	var grid := {}
	for i in ns:
		var a: Vector2 = segs[i][0]
		var b: Vector2 = segs[i][1]
		var x0 := int(floor(minf(a.x, b.x) / cell))
		var x1 := int(floor(maxf(a.x, b.x) / cell))
		var y0 := int(floor(minf(a.y, b.y) / cell))
		var y1 := int(floor(maxf(a.y, b.y) / cell))
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				var gk := Vector2i(gx, gy)
				if not grid.has(gk):
					grid[gk] = []
				grid[gk].append(i)
	var splits: Array = []
	splits.resize(ns)
	for i in ns:
		splits[i] = []
	var tested := {}
	for gk in grid:
		var lst: Array = grid[gk]
		for ii in lst.size():
			for jj in range(ii + 1, lst.size()):
				var i: int = lst[ii]
				var j: int = lst[jj]
				var pk := (mini(i, j) << 32) | maxi(i, j)
				if tested.has(pk):
					continue
				tested[pk] = true
				var a1: Vector2 = segs[i][0]
				var b1: Vector2 = segs[i][1]
				var a2: Vector2 = segs[j][0]
				var b2: Vector2 = segs[j][1]
				var hit = Geometry2D.segment_intersects_segment(a1, b1, a2, b2)
				if hit != null:
					var h: Vector2 = hit
					if h.distance_to(a1) > 1e-6 and h.distance_to(b1) > 1e-6:
						splits[i].append(h)
					if h.distance_to(a2) > 1e-6 and h.distance_to(b2) > 1e-6:
						splits[j].append(h)
				else:
					# T bağlantısı: bir parçanın ucu diğerinin üzerinde
					for pr in [[a2, i], [b2, i], [a1, j], [b1, j]]:
						var p: Vector2 = pr[0]
						var si: int = pr[1]
						var sa: Vector2 = segs[si][0]
						var sb: Vector2 = segs[si][1]
						var cp := Geometry2D.get_closest_point_to_segment(p, sa, sb)
						if cp.distance_to(p) < 1e-6 and p.distance_to(sa) > 1e-6 and p.distance_to(sb) > 1e-6:
							splits[si].append(p)
	# 3) Kenarlar (yönsüz, tekrarsız)
	var vpos := {}
	var edges := {}
	for i in ns:
		var a: Vector2 = segs[i][0]
		var b: Vector2 = segs[i][1]
		var pts: Array = [a]
		var sp: Array = splits[i]
		sp.sort_custom(func(p, q): return (p as Vector2).distance_squared_to(a) < (q as Vector2).distance_squared_to(a))
		pts.append_array(sp)
		pts.append(b)
		for k in pts.size() - 1:
			var ka := _key(pts[k])
			var kb := _key(pts[k + 1])
			if ka == kb:
				continue
			vpos[ka] = pts[k]
			vpos[kb] = pts[k + 1]
			var ek := [ka, kb] if (ka.x < kb.x or (ka.x == kb.x and ka.y < kb.y)) else [kb, ka]
			edges[str(ek)] = ek
	# 4) Komşuluk + sarkan kenarları budama
	var adj := {}
	for ek in edges.values():
		for t in 2:
			var u: Vector2i = ek[t]
			var v: Vector2i = ek[1 - t]
			if not adj.has(u):
				adj[u] = []
			if not (v in adj[u]):
				adj[u].append(v)
	var changed := true
	while changed:
		changed = false
		for u in adj.keys():
			if (adj[u] as Array).size() < 2:
				for v in adj[u]:
					(adj[v] as Array).erase(u)
				adj.erase(u)
				changed = true
	if adj.is_empty():
		return []
	# 5) Açıya göre sırala
	for u in adj:
		var pu: Vector2 = vpos[u]
		(adj[u] as Array).sort_custom(func(p, q): return ((vpos[p] as Vector2) - pu).angle() < ((vpos[q] as Vector2) - pu).angle())
	# 6) Yarım kenar dolaşımı (yüz solda)
	var visited := {}
	var cycles: Array = []
	for u in adj:
		for v in adj[u]:
			var hk := str([u, v])
			if visited.has(hk):
				continue
			var cyc := PackedVector2Array()
			var cu: Vector2i = u
			var cv: Vector2i = v
			var guard := 0
			while guard < 200000:
				var k2 := str([cu, cv])
				if visited.has(k2):
					break
				visited[k2] = true
				cyc.append(vpos[cu])
				var lst: Array = adj[cv]
				var idx := lst.find(cu)
				var nw: Vector2i = lst[(idx - 1 + lst.size()) % lst.size()]
				cu = cv
				cv = nw
				guard += 1
			if cyc.size() >= 3:
				cycles.append(cyc)
	# 7) Sınırlı yüzler ve delikler
	var outers: Array = []
	var holes: Array = []
	for cyc in cycles:
		var ar := Sketch.polygon_area(cyc)
		if ar > 1e-9:
			outers.append({"outer": cyc, "holes": [], "area": ar})
		elif ar < -1e-9:
			holes.append(cyc)
	for hcyc in holes:
		var hp: PackedVector2Array = hcyc
		# Deliğin dışındaki (solundaki) bir nokta: ilk kenarın ortasından sola küçük adım
		var d := (hp[1] - hp[0])
		var probe := (hp[0] + hp[1]) * 0.5 + Vector2(-d.y, d.x).normalized() * 1e-4
		var best := -1
		var best_a := INF
		for i in outers.size():
			var o: Dictionary = outers[i]
			if float(o["area"]) < best_a and float(o["area"]) > absf(Sketch.polygon_area(hp)) - 1e-9 and Geometry2D.is_point_in_polygon(probe, o["outer"]):
				best = i
				best_a = o["area"]
		if best >= 0:
			outers[best]["holes"].append(hp)
	for o in outers:
		o["sample"] = _interior_point(o["outer"], o["holes"])
		var net: float = o["area"]
		for h in o["holes"]:
			net -= absf(Sketch.polygon_area(h))
		o["net_area"] = net
	return outers


static func _interior_point(outer: PackedVector2Array, hs: Array) -> Vector2:
	var tri := Geometry2D.triangulate_polygon(outer)
	var best := outer[0]
	var best_a := -1.0
	for t in range(0, tri.size(), 3):
		var a := outer[tri[t]]
		var b := outer[tri[t + 1]]
		var c := outer[tri[t + 2]]
		var cen := (a + b + c) / 3.0
		var ar := absf((b - a).cross(c - a))
		if ar <= best_a:
			continue
		var in_hole := false
		for h in hs:
			if Geometry2D.is_point_in_polygon(cen, h):
				in_hole = true
				break
		if not in_hole:
			best_a = ar
			best = cen
	return best


## Noktayı içeren yüzün indeksi (-1: yok).
static func face_at(fs: Array, p: Vector2) -> int:
	var best := -1
	var best_a := INF
	for i in fs.size():
		var f: Dictionary = fs[i]
		if not Geometry2D.is_point_in_polygon(p, f["outer"]):
			continue
		var in_hole := false
		for h in f["holes"]:
			if Geometry2D.is_point_in_polygon(p, h):
				in_hole = true
		if not in_hole and float(f["area"]) < best_a:
			best = i
			best_a = f["area"]
	return best
