class_name RefGeom
extends RefCounted
## Referans geometri (Faz 5): düzlem, eksen, nokta ve helis hesapları.
## Referans düzlemler CadFeature.plane alanında hesaplanmış düzlemi tutar; taslak düzlemleri
## `SketchPlane.ref` ile bir referans düzleme bağlıysa her değişiklikte ondan güncellenir.
##
## Düzlem değeri: "front" | "top" | "right" | "pl:<özellik kimliği>"
## Eksen/yön değeri: "x" | "y" | "z" | "ax:<özellik kimliği>" | "v:x,y,z" (seçilen kenardan)

const AXES := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}


static func _v3(a: Variant, def := Vector3.ZERO) -> Vector3:
	if a is Vector3:
		return a
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return def


static func arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func is_reference(f: CadFeature) -> bool:
	return f.type in ["refplane", "refaxis", "refpoint", "helix", "refcsys"]


## Özellik listesinde (önizleme dahil) id'li özellik.
static func _find(doc: CadDocument, id: int, preview: CadFeature = null) -> CadFeature:
	if preview != null and preview.id == id:
		return preview
	return doc.get_feature(id)


static func resolve_plane(doc: CadDocument, v: Variant, preview: CadFeature = null) -> SketchPlane:
	var s := str(v)
	if s.begins_with("pl:"):
		var f := _find(doc, int(s.substr(3)), preview)
		if f and f.type == "refplane":
			if f.plane == null:
				f.plane = plane_of(doc, f, preview)
			return f.plane
		return null
	return SketchPlane.standard(s)


## Referans düzlemin hesaplanmış düzlemi (null: geçersiz).
static func plane_of(doc: CadDocument, f: CadFeature, preview: CadFeature = null) -> SketchPlane:
	var p := f.params
	var mode := str(p.get("mode", "offset"))
	var out: SketchPlane = null
	match mode:
		"offset", "angle":
			var base: SketchPlane = null
			if p.get("base_plane") is Dictionary:
				var bp: Dictionary = p["base_plane"]
				base = SketchPlane.make("Yüz", _v3(bp.get("o")), _v3(bp.get("x"), Vector3.RIGHT), _v3(bp.get("y"), Vector3.UP))
			else:
				base = resolve_plane(doc, p.get("base", "front"), preview)
			if base == null:
				return null
			if mode == "offset":
				var dist := float(p.get("dist", 10.0)) * (-1.0 if bool(p.get("flip", false)) else 1.0)
				out = SketchPlane.make(f.name, base.origin + base.normal() * dist, base.x_dir, base.y_dir)
			else:
				var ang := deg_to_rad(float(p.get("angle", 45.0)))
				if str(p.get("axis", "x")) == "x":
					var y := base.y_dir.rotated(base.x_dir, ang)
					out = SketchPlane.make(f.name, base.origin, base.x_dir, y)
				else:
					var x := base.x_dir.rotated(base.y_dir, -ang)
					out = SketchPlane.make(f.name, base.origin, x, base.y_dir)
		"tangent":
			# Yüzeye teğet: seçilen noktada yüzey normaline dik düzlem (silindirde radyal yön)
			var tp = p.get("tan_p")
			var tn = p.get("tan_n")
			if not (tp is Array) or not (tn is Array) or _v3(tn).length() < 1e-9:
				return null
			out = SketchPlane.from_face(_v3(tp), _v3(tn).normalized(), f.name)
		"3pt":
			var pts: Array = p.get("points", [])
			if pts.size() < 3:
				return null
			var a := _v3(pts[0])
			var b := _v3(pts[1])
			var c := _v3(pts[2])
			var x2 := b - a
			var n := x2.cross(c - a)
			if x2.length() < 1e-9 or n.length() < 1e-9:
				return null
			x2 = x2.normalized()
			n = n.normalized()
			out = SketchPlane.make(f.name, a, x2, n.cross(x2).normalized())
	return out


## Eksen: {o, d} (d birim) veya {} (geçersiz).
static func axis_of(doc: CadDocument, f: CadFeature, preview: CadFeature = null) -> Dictionary:
	var p := f.params
	match str(p.get("mode", "std")):
		"std":
			return {"o": Vector3.ZERO, "d": AXES.get(str(p.get("axis", "y")), Vector3.UP)}
		"2pt":
			var a := _v3(p.get("p1"))
			var b := _v3(p.get("p2"), Vector3.UP)
			if a.distance_to(b) < 1e-9:
				return {}
			return {"o": a, "d": (b - a).normalized()}
		"line":
			var d := _v3(p.get("d"), Vector3.UP)
			if d.length() < 1e-9:
				return {}
			return {"o": _v3(p.get("o")), "d": d.normalized()}
		"planes":
			var p1 := resolve_plane(doc, p.get("plane1", "front"), preview)
			var p2 := resolve_plane(doc, p.get("plane2", "right"), preview)
			if p1 == null or p2 == null:
				return {}
			var n1 := p1.normal()
			var n2 := p2.normal()
			var d2 := n1.cross(n2)
			if d2.length() < 1e-9:
				return {}
			d2 = d2.normalized()
			# Her iki düzlemde de olan nokta: (h1 n2 - h2 n1) x d / |d|² ... genel çözüm
			var h1 := n1.dot(p1.origin)
			var h2 := n2.dot(p2.origin)
			var o := (n2.cross(d2) * h1 + d2.cross(n1) * h2) / d2.dot(n1.cross(n2))
			return {"o": o, "d": d2}
	return {}


static func point_of(f: CadFeature) -> Vector3:
	return _v3(f.params.get("p"))


## Koordinat sistemi: {o, x, y, z} (sağ el, birim) veya {}.
static func csys_of(doc: CadDocument, f: CadFeature, preview: CadFeature = null) -> Dictionary:
	var ax := resolve_axis(doc, f.params.get("x", "x"), preview)
	var ay := resolve_axis(doc, f.params.get("y", "y"), preview)
	if ax.is_empty() or ay.is_empty():
		return {}
	var x: Vector3 = (ax["d"] as Vector3) * (-1.0 if bool(f.params.get("flip_x", false)) else 1.0)
	var y: Vector3 = (ay["d"] as Vector3) * (-1.0 if bool(f.params.get("flip_y", false)) else 1.0)
	var z := x.cross(y)
	if z.length() < 1e-6:
		return {}
	z = z.normalized()
	y = z.cross(x).normalized()
	return {"o": _v3(f.params.get("o")), "x": x.normalized(), "y": y, "z": z}


## Eksen değerini çözer: {o, d} veya {}.
static func resolve_axis(doc: CadDocument, v: Variant, preview: CadFeature = null) -> Dictionary:
	var s := str(v)
	if AXES.has(s):
		return {"o": Vector3.ZERO, "d": AXES[s]}
	if s.begins_with("ax:"):
		var f := _find(doc, int(s.substr(3)), preview)
		if f and f.type == "refaxis":
			return axis_of(doc, f, preview)
		return {}
	if s.begins_with("v:"):
		var parts := s.substr(2).split(",")
		if parts.size() >= 6:
			var o := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
			var d := Vector3(float(parts[3]), float(parts[4]), float(parts[5]))
			if d.length() > 1e-9:
				return {"o": o, "d": d.normalized()}
		elif parts.size() >= 3:
			var d3 := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
			if d3.length() > 1e-9:
				return {"o": Vector3.ZERO, "d": d3.normalized()}
	return {}


static func axis_value_of_line(o: Vector3, d: Vector3) -> String:
	return "v:%f,%f,%f,%f,%f,%f" % [o.x, o.y, o.z, d.x, d.y, d.z]


## Seçim listeleri: [[etiket, değer], ...]
static func axis_choices(doc: CadDocument, before_id := -1) -> Array:
	var out: Array = [["X ekseni", "x"], ["Y ekseni", "y"], ["Z ekseni", "z"]]
	for f in doc.features:
		if before_id >= 0 and f.id == before_id:
			break
		if f.type == "refaxis" and not f.suppressed:
			out.append([f.name, "ax:%d" % f.id])
	return out


static func plane_choices(doc: CadDocument, before_id := -1) -> Array:
	var out: Array = [["Ön Düzlem", "front"], ["Üst Düzlem", "top"], ["Sağ Düzlem", "right"]]
	for f in doc.features:
		if before_id >= 0 and f.id == before_id:
			break
		if f.type == "refplane" and not f.suppressed:
			out.append([f.name, "pl:%d" % f.id])
	return out


## Referans düzlemleri hesaplar ve onlara bağlı taslak düzlemlerini günceller.
static func update(doc: CadDocument, preview: CadFeature = null) -> void:
	var list: Array = doc.features.duplicate()
	if preview != null:
		var idx := doc.index_of(preview.id)
		if idx >= 0:
			list[idx] = preview
	for f in list:
		if f.type == "refplane":
			f.plane = null
	for f in list:
		match f.type:
			"refplane":
				f.plane = plane_of(doc, f, preview)
				f.error = "" if f.plane != null else "Düzlem tanımı geçersiz"
			"sketch":
				if f.plane != null and f.plane.ref >= 0:
					var rf := _find(doc, f.plane.ref, preview)
					if rf and rf.type == "refplane" and rf.plane != null:
						f.plane.origin = rf.plane.origin
						f.plane.x_dir = rf.plane.x_dir
						f.plane.y_dir = rf.plane.y_dir


# ---------------------------------------------------------------- helis

## Helis tanımı: {o, axis, xdir, r, pitch, turns, ccw} (diziler) veya {error}.
static func helix_spec(doc: CadDocument, f: CadFeature) -> Dictionary:
	var p := f.params
	var sk := doc.get_feature(int(p.get("sketch", 0)))
	if sk == null or sk.sketch == null:
		return {"error": "Helis için daire içeren bir taslak seçin"}
	var circ := {}
	for e in sk.sketch.entities:
		if e["type"] == "circle":
			circ = e
			break
	if circ.is_empty():
		return {"error": "Taslakta daire yok (helis çapı daireden alınır)"}
	var r := float(circ["r"])
	var c: Vector3 = sk.plane.to_world(sk.sketch.points[circ["c"]])
	var axis := sk.plane.normal() * (-1.0 if bool(p.get("reverse", false)) else 1.0)
	var start := deg_to_rad(float(p.get("start_angle", 0.0)))
	var xdir := sk.plane.x_dir.rotated(sk.plane.normal(), start)
	var mode := str(p.get("mode", "pitch_turns"))
	var pitch := float(p.get("pitch", 5.0))
	var turns := float(p.get("turns", 4.0))
	var height := float(p.get("height", 20.0))
	var spiral := str(p.get("kind", "helix")) == "spiral"
	if not spiral:
		match mode:
			"height_turns":
				pitch = height / maxf(turns, 1e-9)
			"height_pitch":
				turns = height / maxf(pitch, 1e-9)
	if r <= 0.0 or pitch <= 0.0 or turns <= 0.0:
		return {"error": "Helis ölçüleri geçersiz"}
	var taper := 0.0 if spiral else float(p.get("taper", 0.0))
	if absf(taper) >= 89.0:
		return {"error": "Koniklik açısı ±89°'den küçük olmalı"}
	if not spiral and r + tan(deg_to_rad(taper)) * pitch * turns <= 0.0:
		return {"error": "Konik helisin yarıçapı sıfırın altına iniyor"}
	return {"o": arr(c), "axis": arr(axis.normalized()), "xdir": arr(xdir), "r": r, "pitch": pitch,
		"turns": turns, "ccw": not bool(p.get("cw", false)), "spiral": spiral, "taper": taper}


static func helix_points(h: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var o := _v3(h["o"])
	var ax := _v3(h["axis"])
	var x := _v3(h["xdir"])
	var y := ax.cross(x)
	var r := float(h["r"])
	var pitch := float(h["pitch"])
	var turns := float(h["turns"])
	var sgn := 1.0 if bool(h.get("ccw", true)) else -1.0
	var spiral := bool(h.get("spiral", false))
	var tk := tan(deg_to_rad(float(h.get("taper", 0.0))))
	var n := int(clampf(turns * 48.0, 16.0, 4000.0))
	for i in n + 1:
		var t := turns * float(i) / float(n)
		var a := TAU * t * sgn
		if spiral:
			out.append(o + (x * cos(a) + y * sin(a)) * (r + pitch * t))
		else:
			out.append(o + (x * cos(a) + y * sin(a)) * (r + tk * pitch * t) + ax * pitch * t)
	return out


## 3B taslak çizgilerini sıralı nokta zincirlerine çevirir.
static func sketch3d_polys(s3: Sketch3D) -> Array:
	var adj := {}
	for i in s3.lines.size():
		var l: Array = s3.lines[i]
		for pid in l:
			if not adj.has(pid):
				adj[pid] = []
			adj[pid].append(i)
	var used := {}
	var out: Array = []
	for i in s3.lines.size():
		if used.has(i):
			continue
		var cur := i
		var pt: int = s3.lines[i][0]
		var guard := 0
		while (adj[pt] as Array).size() == 2 and guard < 10000:
			var other: int = adj[pt][0] if adj[pt][0] != cur else adj[pt][1]
			if other == i:
				break
			cur = other
			pt = s3.lines[cur][0] if s3.lines[cur][1] == pt else s3.lines[cur][1]
			guard += 1
		var poly: Array = [arr(s3.points[pt])]
		var start := cur
		guard = 0
		while guard < 10000:
			used[cur] = true
			var l2: Array = s3.lines[cur]
			pt = l2[1] if l2[0] == pt else l2[0]
			poly.append(arr(s3.points[pt]))
			var nb: Array = adj[pt]
			if nb.size() != 2:
				break
			var nxt: int = nb[0] if nb[0] != cur else nb[1]
			if nxt == start or used.has(nxt):
				break
			cur = nxt
			guard += 1
		out.append(poly)
	return out
