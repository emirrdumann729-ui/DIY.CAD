class_name TextOutline
extends RefCounted
## Metni yazı tipi konturlarına (kapalı çokgenler) çevirir. Taslak metni ekstrüzyonla
## kabartma / gravür yapılabilsin diye. Koordinatlar mm, taban çizgisi y=0, y yukarı.

const BASE_SIZE := 64          # konturların alındığı piksel boyutu
const CURVE_STEPS := 6         # Bezier eğrisi başına parça

static var _cache := {}


static func loops(text: String, height: float) -> Array:
	if text.strip_edges().is_empty() or height <= 0.0:
		return []
	var key := "%s|%.4f" % [text, height]
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var font: Font = ThemeDB.fallback_font
	var ts := TextServerManager.get_primary_interface()
	if font == null or ts == null:
		return out
	var scale := height / float(BASE_SIZE)
	var shaped := ts.create_shaped_text()
	ts.shaped_text_add_string(shaped, text, font.get_rids(), BASE_SIZE)
	ts.shaped_text_shape(shaped)
	var pen := 0.0
	for g in ts.shaped_text_get_glyphs(shaped):
		var frid: RID = g.get("font_rid", RID())
		var idx := int(g.get("index", 0))
		var off: Vector2 = g.get("offset", Vector2.ZERO)
		if frid.is_valid() and idx != 0:
			var data: Dictionary = ts.font_get_glyph_contours(frid, int(g.get("font_size", BASE_SIZE)), idx)
			for poly in _glyph_polys(data):
				var p2 := PackedVector2Array()
				for q in poly:
					# Yazı tipi y aşağı; taslak y yukarı
					p2.append(Vector2((q.x + pen + off.x) * scale, -(q.y + off.y) * scale))
				if p2.size() >= 3 and absf(Sketch.polygon_area(p2)) > 1e-6:
					out.append(p2)
		pen += float(g.get("advance", 0.0)) * int(g.get("repeat", 1))
	ts.free_rid(shaped)
	_cache[key] = out
	return out


static func _quad(a: Vector2, c: Vector2, b: Vector2, out: PackedVector2Array) -> void:
	for i in range(1, CURVE_STEPS + 1):
		var t := float(i) / CURVE_STEPS
		out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))


static func _cubic(a: Vector2, c1: Vector2, c2: Vector2, b: Vector2, out: PackedVector2Array) -> void:
	for i in range(1, CURVE_STEPS + 1):
		var t := float(i) / CURVE_STEPS
		var u := 1.0 - t
		out.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)


## TrueType (ikinci derece) ve CFF (kübik) konturlarını çokgenlere çevirir.
static func _glyph_polys(data: Dictionary) -> Array:
	var result: Array = []
	var pts: PackedVector3Array = data.get("points", PackedVector3Array())
	var ends: PackedInt32Array = data.get("contours", PackedInt32Array())
	var start := 0
	for end_i in ends:
		var n := end_i - start + 1
		if n < 2:
			start = end_i + 1
			continue
		var P: Array = []
		var T: Array = []
		for k in n:
			var v := pts[start + k]
			P.append(Vector2(v.x, v.y))
			T.append(int(v.z))
		# Eğri üzerinde (on) bir başlangıç noktası bul
		var s := -1
		for k in n:
			if T[k] == TextServer.CONTOUR_CURVE_TAG_ON:
				s = k
				break
		var poly := PackedVector2Array()
		var cur: Vector2
		if s < 0:
			cur = ((P[0] as Vector2) + (P[1] as Vector2)) * 0.5
			s = 0
		else:
			cur = P[s]
			s += 1
		poly.append(cur)
		var first := cur
		var k2 := 0
		while k2 < n:
			var i := (s + k2) % n
			var p: Vector2 = P[i]
			var t: int = T[i]
			if t == TextServer.CONTOUR_CURVE_TAG_ON:
				poly.append(p)
				cur = p
				k2 += 1
			elif t == TextServer.CONTOUR_CURVE_TAG_OFF_CONIC:
				var j := (i + 1) % n
				var nxt: Vector2 = P[j] if k2 + 1 < n else first
				var end_p: Vector2
				if k2 + 1 < n and T[j] == TextServer.CONTOUR_CURVE_TAG_OFF_CONIC:
					end_p = (p + nxt) * 0.5
					k2 += 1
				else:
					end_p = nxt
					k2 += 2
				_quad(cur, p, end_p, poly)
				cur = end_p
			else:
				var c2: Vector2 = P[(i + 1) % n]
				var end_c: Vector2 = P[(i + 2) % n] if k2 + 2 < n else first
				_cubic(cur, p, c2, end_c, poly)
				cur = end_c
				k2 += 3
		# Kapanış noktası tekrarını sil
		if poly.size() > 2 and poly[poly.size() - 1].distance_to(poly[0]) < 1e-4:
			poly.remove_at(poly.size() - 1)
		result.append(poly)
		start = end_i + 1
	return result
