class_name Drawing
extends RefCounted
## Teknik resim (Faz 6) veri modeli ve geometri yardımcıları.
## Resim sayfaları belgenin `drawings` dizisinde düz sözlükler olarak saklanır (kaydetme ve geri al için).
##
## Sayfa koordinatları mm, sol alt köşe (0,0), y yukarı. Görünüş koordinatları: modelin görünüş düzlemine
## izdüşümü (mm, gerçek ölçü); sayfaya `pos + p * ölçek` ile yerleşir (kırık görünüş varsa önce kaydırılır).

const SIZES := {
	"A4": Vector2(297, 210), "A3": Vector2(420, 297), "A2": Vector2(594, 420), "A1": Vector2(841, 594), "A0": Vector2(1189, 841),
	"ANSI A": Vector2(279.4, 215.9), "ANSI B": Vector2(431.8, 279.4), "ANSI C": Vector2(558.8, 431.8),
	"ANSI D": Vector2(863.6, 558.8), "ANSI E": Vector2(1117.6, 863.6),
}
const SIZE_ORDER := ["A4", "A3", "A2", "A1", "A0", "ANSI A", "ANSI B", "ANSI C", "ANSI D", "ANSI E"]
const SCALES := [50.0, 20.0, 10.0, 5.0, 2.0, 1.0, 0.5, 0.4, 0.2, 0.1, 0.05, 0.02, 0.01]
const MARGIN := 10.0
const TITLE_W := 180.0
const TITLE_H := 40.0

## Görünüş yönelimleri: dir = cisimden izleyiciye, x = görünüşün sağı (yukarı = dir × x)
const ORIENTS := {
	"front": [Vector3(0, 0, 1), Vector3(1, 0, 0)], "back": [Vector3(0, 0, -1), Vector3(-1, 0, 0)],
	"top": [Vector3(0, 1, 0), Vector3(1, 0, 0)], "bottom": [Vector3(0, -1, 0), Vector3(1, 0, 0)],
	"right": [Vector3(1, 0, 0), Vector3(0, 0, -1)], "left": [Vector3(-1, 0, 0), Vector3(0, 0, 1)],
	"iso": [Vector3(1, 1, 1) / sqrt(3.0), Vector3(1, 0, -1) / sqrt(2.0)],
	"dimetric": [Vector3(0.6124, 0.5, 0.6124), Vector3(0.7071, 0.0, -0.7071)],
}
const ORIENT_NAMES := {"front": "Ön", "back": "Arka", "top": "Üst", "bottom": "Alt", "right": "Sağ", "left": "Sol", "iso": "İzometrik", "dimetric": "Dimetrik"}


static func v3(a: Variant) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func v2(a: Variant) -> Vector2:
	if a is Vector2:
		return a
	return Vector2(float(a[0]), float(a[1]))


static func a3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func a2(v: Vector2) -> Array:
	return [v.x, v.y]


# ---------------------------------------------------------------- sayfa

static func new_sheet(name: String, size := "A3", std := "ISO") -> Dictionary:
	return {"name": name, "size": size, "portrait": false, "std": std, "proj": "first" if std == "ISO" else "third",
		"scale": 1.0, "views": [], "anns": [], "revs": [], "bom": true, "next": 1, "letter": 0,
		"title": {"company": "", "title": "", "number": "", "drawn": "", "checked": "", "date": "", "rev": "", "material": "", "weight": ""}}


static func sheet_size(sh: Dictionary) -> Vector2:
	var s: Vector2 = SIZES.get(str(sh.get("size", "A3")), SIZES["A3"])
	return Vector2(s.y, s.x) if bool(sh.get("portrait", false)) else s


static func next_id(sh: Dictionary) -> int:
	var n := int(sh.get("next", 1))
	sh["next"] = n + 1
	return n


static func next_letter(sh: Dictionary) -> String:
	var n := int(sh.get("letter", 0))
	sh["letter"] = n + 1
	var letters := "ABCDEFGHJKLMNPRSTUVWXYZ"
	return letters[n % letters.length()] + ("" if n < letters.length() else str(n / letters.length()))


static func find_view(sh: Dictionary, id: int) -> Dictionary:
	for v in sh.get("views", []):
		if int(v["id"]) == id:
			return v
	return {}


static func find_ann(sh: Dictionary, id: int) -> Dictionary:
	for a in sh.get("anns", []):
		if int(a["id"]) == id:
			return a
	return {}


## Görünüşün sayfadaki ölçeği (0: sayfa ölçeği; detay görünüşü ebeveyninin katı).
static func view_scale(sh: Dictionary, v: Dictionary) -> float:
	var s := float(v.get("scale", 0.0))
	if v.get("type", "") == "detail":
		var par := find_view(sh, int(v.get("parent", -1)))
		var ps := view_scale(sh, par) if not par.is_empty() else float(sh.get("scale", 1.0))
		return ps * float((v.get("detail", {}) as Dictionary).get("factor", 2.0))
	return s if s > 0.0 else float(sh.get("scale", 1.0))


static func scale_text(s: float) -> String:
	if s >= 1.0:
		return "%s:1" % _num(s)
	return "1:%s" % _num(1.0 / s)


static func _num(x: float) -> String:
	if absf(x - round(x)) < 1e-6:
		return str(int(round(x)))
	return str(snappedf(x, 0.01))


# ---------------------------------------------------------------- görünüş yönelimi

static func view_axes(sh: Dictionary, v: Dictionary) -> Dictionary:
	if v.get("type", "") == "detail":
		var par := find_view(sh, int(v.get("parent", -1)))
		return view_axes(sh, par) if not par.is_empty() else {"dir": Vector3.BACK, "x": Vector3.RIGHT}
	if v.has("dir") and v.has("x"):
		return {"dir": v3(v["dir"]), "x": v3(v["x"])}
	var o: Array = ORIENTS.get(str(v.get("orient", "front")), ORIENTS["front"])
	return {"dir": o[0], "x": o[1]}


## İzdüşüm görünüşü: ebeveynin yanına (right/left/up/down) yerleştirilen çocuğun yönelimi.
## Üçüncü açıda yandaki görünüş o taraftan bakılarak, birinci açıda karşı taraftan bakılarak elde edilir.
static func projected_axes(par_dir: Vector3, par_x: Vector3, side: String, proj: String) -> Dictionary:
	var up := par_dir.cross(par_x)
	var k := 1.0 if proj == "third" else -1.0
	match side:
		"right":
			return {"dir": par_x * k, "x": -par_dir * k}
		"left":
			return {"dir": -par_x * k, "x": par_dir * k}
		"up":
			return {"dir": up * k, "x": par_x}
		"down":
			return {"dir": -up * k, "x": par_x}
	return {"dir": par_dir, "x": par_x}


## Görünüş düzlemindeki 2B noktayı 3B'ye çevirir (derinlik 0).
static func to_3d(axes: Dictionary, p: Vector2) -> Vector3:
	var x: Vector3 = axes["x"]
	var up: Vector3 = (axes["dir"] as Vector3).cross(x)
	return x * p.x + up * p.y


static func project(axes: Dictionary, p: Vector3) -> Vector2:
	var x: Vector3 = axes["x"]
	var up: Vector3 = (axes["dir"] as Vector3).cross(x)
	return Vector2(p.dot(x), p.dot(up))


## Kesit: ebeveyn görünüşte çizilen a→b doğrusu. Dönüş: {o, n, dir, x} (n: kaldırılan taraf / izleyici)
static func section_def(par_axes: Dictionary, a: Vector2, b: Vector2, flip: bool) -> Dictionary:
	var l3 := to_3d(par_axes, b) - to_3d(par_axes, a)
	if l3.length() < 1e-9:
		return {}
	l3 = l3.normalized()
	var n := l3.cross(par_axes["dir"]).normalized()
	if flip:
		n = -n
	var x := l3 if not flip else -l3
	return {"o": to_3d(par_axes, a), "n": n, "dir": n, "x": x}


## Yardımcı görünüş: ebeveyndeki kenara dik bakış.
static func aux_axes(par_axes: Dictionary, a: Vector2, b: Vector2, flip: bool) -> Dictionary:
	var e2 := (b - a).normalized()
	var n2 := Vector2(-e2.y, e2.x) * (-1.0 if flip else 1.0)
	return {"dir": to_3d(par_axes, n2).normalized(), "x": to_3d(par_axes, e2 * (-1.0 if flip else 1.0)).normalized(), "n2": n2}


# ---------------------------------------------------------------- kırık görünüş ve detay

## Kırık görünüş: [a, b] aralığı çıkarılır, sonrası boşluk bırakılarak kaydırılır (görünüş koordinatlarında).
static func break_map(p: Vector2, breaks: Array, gap: float) -> Vector2:
	var q := p
	for ax in [0, 1]:
		var brs: Array = []
		for br in breaks:
			if (0 if str(br.get("axis", "x")) == "x" else 1) == ax:
				brs.append(br)
		if brs.is_empty():
			continue
		brs.sort_custom(func(m: Dictionary, n: Dictionary) -> bool: return float(m["a"]) < float(n["a"]))
		var c: float = p[ax]
		var off := 0.0
		var res := INF
		for br in brs:
			var a := float(br["a"])
			var b := float(br["b"])
			if c >= b:
				off += (b - a) - gap
			elif c > a:
				res = a - off + (c - a) / (b - a) * gap
				break
			else:
				break
		q[ax] = res if res != INF else c - off
	return q


static func in_break(p: Vector2, breaks: Array) -> bool:
	for br in breaks:
		var c := p.x if str(br.get("axis", "x")) == "x" else p.y
		if c > float(br["a"]) + 1e-9 and c < float(br["b"]) - 1e-9:
			return true
	return false


## Çoklu çizgiyi kırık bölgelerin dışında kalan parçalara böler.
static func clip_breaks(poly: PackedVector2Array, breaks: Array) -> Array:
	if breaks.is_empty():
		return [poly]
	var out: Array = []
	var cur := PackedVector2Array()
	for i in poly.size():
		var p := poly[i]
		if i > 0:
			var q := poly[i - 1]
			# Segmenti kırık sınırlarında böl
			var ts: Array = [0.0, 1.0]
			for br in breaks:
				var ax := 0 if str(br.get("axis", "x")) == "x" else 1
				for lim in [float(br["a"]), float(br["b"])]:
					var d := p[ax] - q[ax]
					if absf(d) > 1e-12:
						var t: float = (float(lim) - q[ax]) / d
						if t > 1e-9 and t < 1.0 - 1e-9:
							ts.append(t)
			ts.sort()
			for k in range(1, ts.size()):
				var s0: Vector2 = q.lerp(p, ts[k - 1])
				var s1: Vector2 = q.lerp(p, ts[k])
				if in_break((s0 + s1) * 0.5, breaks):
					if cur.size() >= 2:
						out.append(cur)
					cur = PackedVector2Array()
				else:
					if cur.is_empty():
						cur.append(s0)
					cur.append(s1)
		elif not in_break(p, breaks):
			cur.append(p)
	if cur.size() >= 2:
		out.append(cur)
	return out


## Çoklu çizgiyi daire içinde kalan parçalara kırpar (detay görünüşü).
static func clip_circle(poly: PackedVector2Array, c: Vector2, r: float) -> Array:
	var out: Array = []
	var cur := PackedVector2Array()
	for i in range(1, poly.size()):
		var a := poly[i - 1]
		var b := poly[i]
		var d := b - a
		var f := a - c
		var A := d.dot(d)
		var ts: Array = [0.0, 1.0]
		if A > 1e-18:
			var B := 2.0 * f.dot(d)
			var C := f.dot(f) - r * r
			var disc := B * B - 4.0 * A * C
			if disc > 0.0:
				var sq := sqrt(disc)
				for t in [(-B - sq) / (2.0 * A), (-B + sq) / (2.0 * A)]:
					if t > 1e-9 and t < 1.0 - 1e-9:
						ts.append(t)
		ts.sort()
		for k in range(1, ts.size()):
			var s0: Vector2 = a.lerp(b, ts[k - 1])
			var s1: Vector2 = a.lerp(b, ts[k])
			if ((s0 + s1) * 0.5).distance_to(c) <= r:
				if cur.is_empty() or cur[cur.size() - 1].distance_to(s0) > 1e-9:
					if cur.size() >= 2:
						out.append(cur)
					cur = PackedVector2Array([s0])
				cur.append(s1)
			else:
				if cur.size() >= 2:
					out.append(cur)
				cur = PackedVector2Array()
	if cur.size() >= 2:
		out.append(cur)
	return out


# ---------------------------------------------------------------- tarama (hatch)

## Çokgen bölge(ler)i için tarama çizgileri (çift-tek kuralı). loops: [PackedVector2Array]
static func hatch_lines(loops: Array, angle_deg: float, spacing: float) -> Array:
	var out: Array = []
	if loops.is_empty() or spacing <= 0.0:
		return out
	var ang := deg_to_rad(angle_deg)
	var dirv := Vector2(cos(ang), sin(ang))
	var nrm := Vector2(-dirv.y, dirv.x)
	var lo := INF
	var hi := -INF
	for lp in loops:
		for p in lp:
			var s: float = (p as Vector2).dot(nrm)
			lo = minf(lo, s)
			hi = maxf(hi, s)
	var k := ceilf(lo / spacing)
	var guard := 0
	while k * spacing <= hi and guard < 5000:
		var s0 := k * spacing
		var ts: Array = []
		for lp in loops:
			var n: int = (lp as PackedVector2Array).size()
			for i in n:
				var a: Vector2 = lp[i]
				var b: Vector2 = lp[(i + 1) % n]
				var da := a.dot(nrm) - s0
				var db := b.dot(nrm) - s0
				if (da < 0.0) != (db < 0.0):
					var t := da / (da - db)
					ts.append(a.lerp(b, t).dot(dirv))
		ts.sort()
		var j := 0
		while j + 1 < ts.size():
			out.append([nrm * s0 + dirv * float(ts[j]), nrm * s0 + dirv * float(ts[j + 1])])
			j += 2
		k += 1.0
		guard += 1
	return out


static func polygon_area(lp: PackedVector2Array) -> float:
	var s := 0.0
	for i in lp.size():
		var a := lp[i]
		var b := lp[(i + 1) % lp.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


# ---------------------------------------------------------------- yerleşim

## Model sınır kutusunun görünüş düzlemindeki dikdörtgeni (görünüş koordinatları).
static func box_rect(axes: Dictionary, aabb: AABB) -> Rect2:
	var r := Rect2()
	var first := true
	for i in 8:
		var c := aabb.position + Vector3(aabb.size.x * (i & 1), aabb.size.y * ((i >> 1) & 1), aabb.size.z * ((i >> 2) & 1))
		var p := project(axes, c)
		if first:
			r = Rect2(p, Vector2.ZERO)
			first = false
		else:
			r = r.expand(p)
	return r


## Standart 3 görünüş + izometrik için ölçek ve konumlar. Dönüş: [{orient, pos, side?}], scale
static func standard_layout(sh: Dictionary, aabb: AABB) -> Dictionary:
	var size := sheet_size(sh)
	var proj := str(sh.get("proj", "first"))
	var fr := projected_axes(ORIENTS["front"][0], ORIENTS["front"][1], "right", proj)
	var vside := "down" if proj == "first" else "up"
	var fd := projected_axes(ORIENTS["front"][0], ORIENTS["front"][1], vside, proj)
	var rf := box_rect({"dir": ORIENTS["front"][0], "x": ORIENTS["front"][1]}, aabb)
	var rs := box_rect(fr, aabb)
	var rd := box_rect(fd, aabb)
	var avail := Vector2(size.x - 2.0 * MARGIN - 20.0, size.y - 2.0 * MARGIN - TITLE_H - 20.0)
	var gap := 15.0
	var need := Vector2(rf.size.x + rs.size.x, rf.size.y + rd.size.y)
	var scale: float = SCALES[SCALES.size() - 1]
	for s: float in SCALES:
		if need.x * s + gap * 2.0 <= avail.x * 0.72 and need.y * s + gap <= avail.y:
			scale = s
			break
	var cx := MARGIN + 10.0 + (avail.x * 0.72 - (need.x * scale + gap)) * 0.5 + rf.size.x * scale * 0.5
	var top_y := size.y - MARGIN - 10.0
	var cy := top_y - rf.size.y * scale * 0.5 - (avail.y - (need.y * scale + gap)) * 0.5
	if vside == "up":
		cy -= (rd.size.y * scale + gap)
	var front_c := Vector2(cx, cy) - rf.get_center() * scale
	var side_dx := (rf.size.x * 0.5 + gap + rs.size.x * 0.5) * scale
	var down_dy := (rf.size.y * 0.5 + gap + rd.size.y * 0.5) * scale
	# Birinci açıda sağdan bakış solda, üstten bakış altta (bizim "right"/"down" yerleşimimiz projeksiyona göre)
	var out: Array = [{"orient": "front", "pos": front_c}]
	out.append({"side": "right", "pos": Vector2(cx + side_dx, cy) - rs.get_center() * scale})
	out.append({"side": vside, "pos": Vector2(cx, cy + (down_dy if vside == "up" else -down_dy)) - rd.get_center() * scale})
	var ri := box_rect({"dir": ORIENTS["iso"][0], "x": ORIENTS["iso"][1]}, aabb)
	out.append({"orient": "iso", "pos": Vector2(size.x - MARGIN - 15.0 - ri.size.x * scale * 0.5, top_y - ri.size.y * scale * 0.5 - 5.0) - ri.get_center() * scale})
	return {"views": out, "scale": scale}


## Sayfa noktası → görünüş koordinatı (kırıklar ters çevrilir).
static func _origin(v: Dictionary) -> Vector2:
	if v.get("type", "") == "detail":
		return v2((v.get("detail", {}) as Dictionary).get("c", [0, 0]))
	return Vector2.ZERO


static func sheet_to_view(sh: Dictionary, v: Dictionary, p: Vector2) -> Vector2:
	var s := view_scale(sh, v)
	var q := (p - v2(v["pos"])) / s + _origin(v)
	var breaks: Array = v.get("breaks", [])
	if breaks.is_empty():
		return q
	# Kırık dönüşümünün tersi: her eksende kırıklar küçükten büyüğe, kaydırma birikerek açılır
	var gap := 6.0 / s
	var r := q
	for ax in [0, 1]:
		var brs: Array = []
		for br in breaks:
			if (0 if str(br.get("axis", "x")) == "x" else 1) == ax:
				brs.append(br)
		brs.sort_custom(func(m: Dictionary, n: Dictionary) -> bool: return float(m["a"]) < float(n["a"]))
		var c: float = q[ax]
		var off := 0.0
		var res := INF
		for br in brs:
			var a := float(br["a"])
			var b := float(br["b"])
			var am := a - off
			if c >= am + gap:
				off += (b - a) - gap
			elif c > am:
				res = a + (c - am) / gap * (b - a)
				break
			else:
				break
		r[ax] = res if res != INF else c + off
	return r


static func view_to_sheet(sh: Dictionary, v: Dictionary, p: Vector2) -> Vector2:
	var s := view_scale(sh, v)
	var breaks: Array = v.get("breaks", [])
	var q := break_map(p, breaks, 6.0 / s) if not breaks.is_empty() else p
	return v2(v["pos"]) + (q - _origin(v)) * s
