class_name DrawingRender
extends RefCounted
## Teknik resim sayfasını çizim ilkellerine çevirir (sayfa mm, sol alt orijin, y yukarı).
## Aynı liste ekranda (DrawingCanvas), PDF, SVG ve DXF çıktısında kullanılır.
##
## İlkeller:
##   {t:"l", a, b, w, s, c}        çizgi (s: solid | dash | chain | phantom)
##   {t:"pl", pts, w, s, c, closed} çoklu çizgi
##   {t:"circ", c, r, w, s, col}   daire
##   {t:"fill", pts, c}            dolu çokgen (ok başları)
##   {t:"txt", p, h, s, ang, al, c} metin (al: l | c | r; p sol-alt/orta/sağ taban noktası)
## Her ilkel isteğe bağlı "lay" (katman: GORUNUR, GIZLI, EKSEN, OLCU, TARAMA, METIN, CERCEVE) taşır.

const W_VIS := 0.5
const W_THIN := 0.25
const W_HATCH := 0.18
const W_FRAME := 0.7
const TXT_H := 3.5
const ARROW := 3.0
const BLACK := Color(0, 0, 0)
const SEL := Color(0.1, 0.4, 1.0)
const GDT_NAMES := {"position": "Konum", "flatness": "Düzlemsellik", "straightness": "Doğrusallık", "circularity": "Dairesellik",
	"cylindricity": "Silindiriklik", "perpendicularity": "Diklik", "parallelism": "Paralellik", "angularity": "Açısallık",
	"concentricity": "Eş merkezlilik", "symmetry": "Simetri", "profile_line": "Çizgi profili", "profile_surface": "Yüzey profili",
	"runout": "Dairesel salgı", "total_runout": "Toplam salgı"}
const GDT_ORDER := ["position", "flatness", "straightness", "circularity", "cylindricity", "perpendicularity", "parallelism",
	"angularity", "concentricity", "symmetry", "profile_line", "profile_surface", "runout", "total_runout"]


static func _l(P: Array, a: Vector2, b: Vector2, w: float, s := "solid", c := BLACK, lay := "GORUNUR") -> void:
	P.append({"t": "l", "a": a, "b": b, "w": w, "s": s, "c": c, "lay": lay})


static func _pl(P: Array, pts: PackedVector2Array, w: float, s := "solid", c := BLACK, closed := false, lay := "GORUNUR") -> void:
	if pts.size() >= 2:
		P.append({"t": "pl", "pts": pts, "w": w, "s": s, "c": c, "closed": closed, "lay": lay})


static func _circ(P: Array, c: Vector2, r: float, w: float, s := "solid", col := BLACK, lay := "GORUNUR") -> void:
	P.append({"t": "circ", "c": c, "r": r, "w": w, "s": s, "col": col, "lay": lay})


static func _txt(P: Array, p: Vector2, h: float, s: String, al := "l", ang := 0.0, c := BLACK, lay := "METIN") -> void:
	if s != "":
		P.append({"t": "txt", "p": p, "h": h, "s": s, "ang": ang, "al": al, "c": c, "lay": lay})


static func _arrow(P: Array, tip: Vector2, dirv: Vector2, c := BLACK, size := ARROW) -> void:
	var d := dirv.normalized()
	if d.length() < 1e-9:
		return
	var n := Vector2(-d.y, d.x)
	var base := tip - d * size
	P.append({"t": "fill", "pts": PackedVector2Array([tip, base + n * size * 0.17, base - n * size * 0.17]), "c": c, "lay": "OLCU"})


## Metin genişliği (mm) — Helvetica/Arial benzeri karakter genişlikleri (em), yazı boyutu = 1.38 × büyük harf yüksekliği.
static func text_width(s: String, h: float) -> float:
	var em := 0.0
	for ch in s:
		if ch in [" ", ".", ",", ":", ";", "|", "!", "'", "i", "l", "j", "ı", "I", "İ"]:
			em += 0.27
		elif ch in ["f", "t", "r", "(", ")", "-", "[", "]", "/"]:
			em += 0.33
		elif ch in ["m", "w", "M", "W"]:
			em += 0.86
		elif ch >= "0" and ch <= "9":
			em += 0.556
		elif ch >= "A" and ch <= "Z" or ch in ["Ç", "Ğ", "Ö", "Ş", "Ü"]:
			em += 0.69
		elif ch in ["Ø", "±", "°", "+", "="]:
			em += 0.62
		else:
			em += 0.53
	return em * 1.38 * h


static func _rect(P: Array, r: Rect2, w: float, c := BLACK, lay := "CERCEVE") -> void:
	_pl(P, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), w, "solid", c, true, lay)


# ---------------------------------------------------------------- ana giriş

## geo: görünüş kimliği → HLR sonucu; opts: {mass, sel_views: [], sel_anns: [], bboxes (çıktı)}
static func build(doc: Object, sh: Dictionary, geo: Dictionary, opts := {}) -> Array:
	var P: Array = []
	if not opts.has("bboxes"):
		opts["bboxes"] = {}
	_frame(P, sh)
	_title_block(P, doc, sh, opts)
	for v in sh.get("views", []):
		_view(P, sh, v, geo, opts)
	for v in sh.get("views", []):
		_view_marks(P, sh, v)
	for a in sh.get("anns", []):
		var c: Color = SEL if int(a["id"]) in opts.get("sel_anns", []) else BLACK
		_ann(P, doc, sh, a, c)
	if bool(sh.get("bom", false)):
		_bom(P, doc, sh, opts)
	if not (sh.get("revs", []) as Array).is_empty():
		_revs(P, sh)
	return P


static func _frame(P: Array, sh: Dictionary) -> void:
	var size := Drawing.sheet_size(sh)
	var m := Drawing.MARGIN
	_rect(P, Rect2(Vector2(m, m), size - Vector2(2 * m, 2 * m)), W_FRAME)
	# Bölge işaretleri (kenar ortalarında merkezleme çizgileri)
	for p in [[Vector2(size.x * 0.5, 0), Vector2(size.x * 0.5, m)], [Vector2(size.x * 0.5, size.y - m), Vector2(size.x * 0.5, size.y)],
			[Vector2(0, size.y * 0.5), Vector2(m, size.y * 0.5)], [Vector2(size.x - m, size.y * 0.5), Vector2(size.x, size.y * 0.5)]]:
		_l(P, p[0], p[1], W_FRAME, "solid", BLACK, "CERCEVE")


static func _title_block(P: Array, doc: Object, sh: Dictionary, opts: Dictionary) -> void:
	var size := Drawing.sheet_size(sh)
	var m := Drawing.MARGIN
	var w := minf(Drawing.TITLE_W, size.x - 2 * m)
	var h := Drawing.TITLE_H
	var o := Vector2(size.x - m - w, m)
	var t: Dictionary = sh.get("title", {})
	_rect(P, Rect2(o, Vector2(w, h)), W_FRAME)
	# Satırlar: üstte firma + başlık, ortada bilgiler, altta numara
	var rows := [o.y + 30.0, o.y + 20.0, o.y + 10.0]
	for y in rows:
		_l(P, Vector2(o.x, y), Vector2(o.x + w, y), W_THIN, "solid", BLACK, "CERCEVE")
	var cols := [o.x + w * 0.25, o.x + w * 0.5, o.x + w * 0.75]
	for x in cols:
		_l(P, Vector2(x, o.y), Vector2(x, o.y + 20.0), W_THIN, "solid", BLACK, "CERCEVE")
	var title := str(t.get("title", ""))
	if title == "":
		title = doc.part_name
	var mat := str(t.get("material", ""))
	if mat == "":
		mat = doc.material if doc.material != "" else "—"
	var weight := str(t.get("weight", ""))
	if weight == "" and opts.has("mass"):
		weight = Units.format_mass(float(opts["mass"]))
	_txt(P, Vector2(o.x + 1.5, o.y + 37.2), 1.8, "FİRMA")
	_txt(P, Vector2(o.x + 2, o.y + 31.5), 3.5, str(t.get("company", "")))
	_txt(P, Vector2(o.x + w * 0.5 + 1.5, o.y + 27.2), 1.8, "BAŞLIK")
	_txt(P, Vector2(o.x + w * 0.5 + 2.0, o.y + 21.6), 4.5, title)
	var cells := [["ÇİZEN", str(t.get("drawn", ""))], ["KONTROL", str(t.get("checked", ""))], ["TARİH", str(t.get("date", ""))], ["MALZEME", mat],
		["ÖLÇEK", Drawing.scale_text(float(sh.get("scale", 1.0)))], ["AĞIRLIK", weight], ["BOYUT", str(sh.get("size", "A3"))], ["REV", str(t.get("rev", ""))]]
	for i in cells.size():
		var cx: float = o.x + (i % 4) * w * 0.25 + 1.5
		var cy: float = o.y + (10.0 if i < 4 else 0.0)
		_txt(P, Vector2(cx, cy + 7.0), 1.8, cells[i][0])
		_txt(P, Vector2(cx, cy + 2.0), 3.0, cells[i][1])
	_txt(P, Vector2(o.x + 1.5, o.y + 27.2), 1.8, "RESİM NO")
	_txt(P, Vector2(o.x + 2.0, o.y + 21.8), 3.5, str(t.get("number", "")))
	# İzdüşüm sembolü (sol üst hücrede: kesik koni iki görünüşü)
	_projection_symbol(P, Vector2(o.x + w * 0.5 - 22, o.y + 25), str(sh.get("proj", "first")))
	_txt(P, Vector2(o.x + w - 2, o.y + 36.0), 2.0, "SAYFA 1/1   " + ("1. AÇI" if str(sh.get("proj", "first")) == "first" else "3. AÇI"), "r")


static func _projection_symbol(P: Array, c: Vector2, proj: String) -> void:
	# Kesik koni: yandan görünüş (yamuk) + önden görünüş (iki daire)
	var trap_x := c.x + (6.0 if proj == "first" else -6.0)
	var circ_x := c.x + (-6.0 if proj == "first" else 6.0)
	_pl(P, PackedVector2Array([Vector2(trap_x - 3.5, c.y - 1.5), Vector2(trap_x + 3.5, c.y - 3.0), Vector2(trap_x + 3.5, c.y + 3.0), Vector2(trap_x - 3.5, c.y + 1.5)]), W_THIN, "solid", BLACK, true, "CERCEVE")
	_circ(P, Vector2(circ_x, c.y), 3.0, W_THIN, "solid", BLACK, "CERCEVE")
	_circ(P, Vector2(circ_x, c.y), 1.5, W_THIN, "solid", BLACK, "CERCEVE")


# ---------------------------------------------------------------- görünüşler

static func _polys(raw: Array) -> Array:
	var out: Array = []
	for pl in raw:
		var pts := PackedVector2Array()
		for q in pl:
			pts.append(Vector2(float(q[0]), float(q[1])))
		out.append(pts)
	return out


## Görünüşün geometrisi (detay ise ebeveyninden kırpılmış). Dönüş: {visible, hidden, tangent, hatch: [[loops]], circles}
static func view_geometry(sh: Dictionary, v: Dictionary, geo: Dictionary) -> Dictionary:
	if v.get("type", "") == "detail":
		var par := Drawing.find_view(sh, int(v.get("parent", -1)))
		var pg := view_geometry(sh, par, geo) if not par.is_empty() else {}
		var det: Dictionary = v.get("detail", {})
		var c := Drawing.v2(det.get("c", [0, 0]))
		var r := float(det.get("r", 10.0))
		var out := {"visible": [], "hidden": [], "tangent": [], "hatch": [], "circles": []}
		for key in ["visible", "hidden", "tangent"]:
			for pl in pg.get(key, []):
				out[key].append_array(Drawing.clip_circle(pl, c, r))
		for cc in pg.get("circles", []):
			if Drawing.v2(cc["c"]).distance_to(c) + float(cc["r"]) <= r + 1e-6:
				out["circles"].append(cc)
		# Detayda tarama: ebeveyn tarama çizgileri kırpılır
		out["hatch_lines"] = []
		for seg in pg.get("hatch_lines", []):
			out["hatch_lines"].append_array(Drawing.clip_circle(PackedVector2Array(seg), c, r))
		return out
	var g: Dictionary = geo.get(int(v["id"]), {})
	var out2 := {"visible": _polys(g.get("visible", [])), "hidden": _polys(g.get("hidden", [])), "tangent": _polys(g.get("tangent", [])),
		"circles": g.get("circles", []), "error": g.get("error", "")}
	var lines: Array = []
	var s := Drawing.view_scale(sh, v)
	for region in g.get("hatch", []):
		var loops: Array = []
		for lp in region:
			var pts := PackedVector2Array()
			for q in lp:
				pts.append(Vector2(float(q[0]), float(q[1])))
			loops.append(pts)
		for seg in Drawing.hatch_lines(loops, 45.0, 2.5 / s):
			lines.append(PackedVector2Array([seg[0], seg[1]]))
		for lp in loops:
			var closed: PackedVector2Array = lp.duplicate()
			closed.append(lp[0])
			out2["visible"].append(closed)
	out2["hatch_lines"] = lines
	return out2


static func _map_polys(sh: Dictionary, v: Dictionary, polys: Array) -> Array:
	var out: Array = []
	var breaks: Array = v.get("breaks", [])
	for pl in polys:
		for piece in Drawing.clip_breaks(pl, breaks):
			var pts := PackedVector2Array()
			for q in piece:
				pts.append(Drawing.view_to_sheet(sh, v, q))
			out.append(pts)
	return out


static func _view(P: Array, sh: Dictionary, v: Dictionary, geo: Dictionary, opts: Dictionary) -> void:
	var g := view_geometry(sh, v, geo)
	var sel: bool = int(v["id"]) in opts.get("sel_views", [])
	var col := SEL if sel else BLACK
	var bb := Rect2()
	var have := false
	var vis := _map_polys(sh, v, g.get("visible", []))
	for pts in vis:
		_pl(P, pts, W_VIS, "solid", col, false, "GORUNUR")
		for q in pts:
			if not have:
				bb = Rect2(q, Vector2.ZERO)
				have = true
			else:
				bb = bb.expand(q)
	if str(v.get("hidden", "visible_hidden")) != "removed":
		for pts in _map_polys(sh, v, g.get("hidden", [])):
			_pl(P, pts, W_THIN, "dash", col, false, "GIZLI")
	if str(v.get("tangent", "show")) == "show":
		for pts in _map_polys(sh, v, g.get("tangent", [])):
			_pl(P, pts, W_THIN, "solid", col.lerp(Color(0.4, 0.4, 0.4), 0.5) if not sel else col, false, "GORUNUR")
	for pts in _map_polys(sh, v, g.get("hatch_lines", [])):
		_pl(P, pts, W_HATCH, "solid", col, false, "TARAMA")
	if not have:
		var p0 := Drawing.v2(v["pos"])
		bb = Rect2(p0 - Vector2(15, 10), Vector2(30, 20))
		if str(g.get("error", "")) != "":
			_txt(P, p0, 2.5, "Görünüş hesaplanamadı", "c", 0.0, Color(0.8, 0.1, 0.1))
		else:
			_txt(P, p0, 2.5, "Görünüş hesaplanıyor...", "c", 0.0, Color(0.5, 0.5, 0.5))
	# Kırık çizgileri
	for br in v.get("breaks", []):
		var s := Drawing.view_scale(sh, v)
		var gap := 6.0 / s
		for edge in [float(br["a"]), float(br["a"]) + gap]:
			var horizontal := str(br.get("axis", "x")) == "x"
			var a2: Vector2
			var b2: Vector2
			if horizontal:
				a2 = Vector2(Drawing.view_to_sheet(sh, v, Vector2(float(br["a"]), 0)).x + (edge - float(br["a"])) * s, bb.position.y - 2)
				b2 = Vector2(a2.x, bb.end.y + 2)
			else:
				a2 = Vector2(bb.position.x - 2, Drawing.view_to_sheet(sh, v, Vector2(0, float(br["a"]))).y + (edge - float(br["a"])) * s)
				b2 = Vector2(bb.end.x + 2, a2.y)
			_zigzag(P, a2, b2)
	opts["bboxes"][int(v["id"])] = bb
	# Görünüş etiketi
	var label := ""
	match str(v.get("type", "")):
		"section":
			label = "KESİT %s-%s" % [str((v.get("section", {}) as Dictionary).get("label", "A")), str((v.get("section", {}) as Dictionary).get("label", "A"))]
		"detail":
			label = "DETAY %s (%s)" % [str((v.get("detail", {}) as Dictionary).get("label", "B")), Drawing.scale_text(Drawing.view_scale(sh, v))]
		"aux":
			label = "GÖRÜNÜŞ %s" % str(v.get("label", ""))
	if label == "" and float(v.get("scale", 0.0)) > 0.0 and absf(float(v["scale"]) - float(sh.get("scale", 1.0))) > 1e-9:
		label = "ÖLÇEK " + Drawing.scale_text(float(v["scale"]))
	if label != "":
		_txt(P, Vector2(bb.get_center().x, bb.position.y - 8.0), 3.5, label, "c", 0.0, col)


static func _zigzag(P: Array, a: Vector2, b: Vector2) -> void:
	var d := b - a
	var L := d.length()
	if L < 1e-6:
		return
	var u := d / L
	var n := Vector2(-u.y, u.x)
	var m := a + d * 0.5
	var pts := PackedVector2Array([a, m - u * 2.0, m - u * 0.7 + n * 2.0, m + u * 0.7 - n * 2.0, m + u * 2.0, b])
	_pl(P, pts, W_THIN, "solid", BLACK, false, "GORUNUR")


## Ebeveyn görünüşlerde kesit çizgisi ve detay dairesi.
static func _view_marks(P: Array, sh: Dictionary, v: Dictionary) -> void:
	var par := Drawing.find_view(sh, int(v.get("parent", -1)))
	if par.is_empty():
		return
	match str(v.get("type", "")):
		"section":
			var sec: Dictionary = v.get("section", {})
			var a := Drawing.view_to_sheet(sh, par, Drawing.v2(sec["a"]))
			var b := Drawing.view_to_sheet(sh, par, Drawing.v2(sec["b"]))
			var u := (b - a).normalized()
			var a0 := a - u * 4.0
			var b0 := b + u * 4.0
			_l(P, a0, b0, W_THIN, "chain", BLACK, "EKSEN")
			_l(P, a0, a0 + u * 5.0, W_VIS, "solid", BLACK, "EKSEN")
			_l(P, b0, b0 - u * 5.0, W_VIS, "solid", BLACK, "EKSEN")
			# Bakış yönü: kalan malzemeye doğru (kesit normalinin tersi)
			var pax := Drawing.view_axes(sh, par)
			var look := -Drawing.project(pax, Drawing.v3(v["dir"]))
			if look.length() < 1e-9:
				look = Vector2(-u.y, u.x)
			look = look.normalized()
			for e in [a0, b0]:
				_l(P, e, e + look * 7.0, W_THIN, "solid", BLACK, "OLCU")
				_arrow(P, e + look * 7.0, look)
				_txt(P, e + look * 10.0 - Vector2(0, 1.75), 3.5, str(sec.get("label", "A")), "c")
		"detail":
			var det: Dictionary = v.get("detail", {})
			var c := Drawing.view_to_sheet(sh, par, Drawing.v2(det.get("c", [0, 0])))
			var r := float(det.get("r", 10.0)) * Drawing.view_scale(sh, par)
			_circ(P, c, r, W_THIN, "chain", BLACK, "EKSEN")
			_txt(P, c + Vector2(r * 0.75 + 1.5, r * 0.75 + 1.0), 3.5, str(det.get("label", "B")), "l")
		"aux":
			var ax: Dictionary = v.get("aux", {})
			var pa := Drawing.view_to_sheet(sh, par, Drawing.v2(ax.get("a", [0, 0])))
			var pb := Drawing.view_to_sheet(sh, par, Drawing.v2(ax.get("b", [0, 0])))
			var m := (pa + pb) * 0.5
			var n2 := Drawing.v2(ax.get("n2", [0, 1]))
			_l(P, m + n2 * 12.0, m + n2 * 4.0, W_THIN, "solid", BLACK, "OLCU")
			_arrow(P, m + n2 * 4.0, -n2)
			_txt(P, m + n2 * 15.0 - Vector2(0, 1.75), 3.5, str(v.get("label", "")), "c")


# ---------------------------------------------------------------- açıklamalar

## Uzunluk metni: belge hassasiyetinde, ISO resim alışkanlığıyla sondaki sıfırlar atılır (25.00 → 25).
static func _len(v: float) -> String:
	var t := Units.format_length(v, false)
	if t.contains(".") or t.contains(","):
		t = t.rstrip("0")
		t = t.rstrip(".,")
	return t


## Boyut değeri metni (birim, hassasiyet, tolerans).
static func dim_text(a: Dictionary, value: float) -> Dictionary:
	var kind := str(a.get("kind", "a"))
	var main := ""
	if kind == "ang":
		main = Units.format_angle(value)
	else:
		main = _len(value)
	if str(a.get("text", "")) != "":
		main = str(a["text"])
	var pre := "Ø" if kind == "dia" else ("R" if kind == "rad" else "")
	main = pre + main
	var tol: Dictionary = a.get("tol", {})
	var up := float(tol.get("up", 0.0))
	var lo := float(tol.get("lo", 0.0))
	var extra := ""
	var stack := []
	match str(tol.get("type", "none")):
		"sym":
			extra = " ±" + _len(up)
		"dev":
			stack = ["+" + _len(up), ("-" if lo > 0 else "+") + _len(absf(lo))]
		"limit":
			var lu := _len(value + up)
			var ll := _len(value - absf(lo))
			main = pre
			stack = [lu, ll]
		"fit":
			extra = " " + str(tol.get("fit", "H7"))
	if bool(a.get("ref", false)):
		main = "(" + main
		extra += ")"
	return {"main": main, "extra": extra, "stack": stack}


static func _dim_label(P: Array, p: Vector2, ang: float, a: Dictionary, value: float, c: Color) -> void:
	var t := dim_text(a, value)
	var h := TXT_H
	var main: String = t["main"] + t["extra"]
	var stack: Array = t["stack"]
	var w := text_width(main, h) + (text_width(str(stack[0]), h * 0.6) + 0.8 if not stack.is_empty() else 0.0)
	var u := Vector2(cos(ang), sin(ang))
	var start := p - u * w * 0.5
	_txt(P, start, h, main, "l", ang, c, "OLCU")
	if not stack.is_empty():
		var n := Vector2(-u.y, u.x)
		var sx := start + u * (text_width(main, h) + 0.8)
		_txt(P, sx + n * h * 0.55, h * 0.6, str(stack[0]), "l", ang, c, "OLCU")
		_txt(P, sx - n * h * 0.05, h * 0.6, str(stack[1]), "l", ang, c, "OLCU")


## Model boyutlarının (taslak boyutu bağlantısı) güncel geometrisi görünüş koordinatlarında.
static func _model_dim_points(doc: Object, sh: Dictionary, v: Dictionary, a: Dictionary) -> Dictionary:
	var src: Dictionary = a.get("src", {})
	if src.is_empty():
		return {}
	if not (doc is CadDocument):
		return {}
	var sk: CadFeature = (doc as CadDocument).get_feature(int(src.get("sketch", 0)))
	if sk == null or sk.sketch == null:
		return {}
	var c := sk.sketch.get_constraint(int(src.get("cid", 0)))
	if c.is_empty():
		return {}
	var ax := Drawing.view_axes(sh, v)
	var pr := func(q: Vector2) -> Vector2: return Drawing.project(ax, sk.plane.to_world(q))
	match str(c["type"]):
		"distance", "hdistance", "vdistance":
			return {"p1": pr.call(sk.sketch.points[int(c["p1"])]), "p2": pr.call(sk.sketch.points[int(c["p2"])])}
		"diameter", "radius":
			var e := sk.sketch.get_entity(int(c["e1"]))
			if e.is_empty():
				return {}
			return {"c": pr.call(sk.sketch.points[int(e["c"])]), "r": sk.sketch.entity_radius(e)}
	return {}


static func dim_value(doc: Object, sh: Dictionary, a: Dictionary) -> float:
	var v := Drawing.find_view(sh, int(a.get("view", -1)))
	var g := a.duplicate()
	if not v.is_empty():
		g.merge(_model_dim_points(doc, sh, v, a), true)
	match str(a.get("kind", "a")):
		"h":
			return absf(Drawing.v2(g["p2"]).x - Drawing.v2(g["p1"]).x)
		"v":
			return absf(Drawing.v2(g["p2"]).y - Drawing.v2(g["p1"]).y)
		"a":
			return Drawing.v2(g["p1"]).distance_to(Drawing.v2(g["p2"]))
		"dia":
			return float(g["r"]) * 2.0
		"rad":
			return float(g["r"])
		"ang":
			var d1 := Drawing.v2(g["l1"][1]) - Drawing.v2(g["l1"][0])
			var d2 := Drawing.v2(g["l2"][1]) - Drawing.v2(g["l2"][0])
			var ang := rad_to_deg(absf(d1.angle_to(d2)))
			return ang if ang <= 90.0 or not bool(a.get("acute", true)) else 180.0 - ang
	return 0.0


static func _ann(P: Array, doc: Object, sh: Dictionary, a: Dictionary, c: Color) -> void:
	match str(a.get("type", "")):
		"dim":
			_dim(P, doc, sh, a, c)
		"centermark":
			var v := Drawing.find_view(sh, int(a.get("view", -1)))
			if v.is_empty():
				return
			var cc := Drawing.view_to_sheet(sh, v, Drawing.v2(a["c"]))
			var r := float(a["r"]) * Drawing.view_scale(sh, v)
			var e := r + 2.5
			_l(P, cc - Vector2(e, 0), cc + Vector2(e, 0), W_THIN, "chain", c, "EKSEN")
			_l(P, cc - Vector2(0, e), cc + Vector2(0, e), W_THIN, "chain", c, "EKSEN")
		"centerline":
			var v2 := Drawing.find_view(sh, int(a.get("view", -1)))
			if v2.is_empty():
				return
			var p1 := Drawing.view_to_sheet(sh, v2, Drawing.v2(a["a"]))
			var p2 := Drawing.view_to_sheet(sh, v2, Drawing.v2(a["b"]))
			var u := (p2 - p1).normalized()
			_l(P, p1 - u * 3.0, p2 + u * 3.0, W_THIN, "chain", c, "EKSEN")
		"note":
			var pos := Drawing.v2(a["pos"])
			var h := float(a.get("h", TXT_H))
			var lines := str(a.get("text", "")).split("\n")
			for i in lines.size():
				_txt(P, pos - Vector2(0, i * h * 1.5), h, lines[i], "l", 0.0, c)
			if a.get("leader") is Array:
				var tgt := Drawing.v2(a["leader"])
				var start := pos + Vector2(-1.0, h * 0.4)
				_l(P, start, tgt, W_THIN, "solid", c, "OLCU")
				_arrow(P, tgt, tgt - start, c)
		"balloon":
			var bp := Drawing.v2(a["pos"])
			var r2 := 4.5
			_circ(P, bp, r2, W_THIN, "solid", c, "OLCU")
			_txt(P, bp - Vector2(0, 1.75), 3.5, str(a.get("num", "1")), "c", 0.0, c)
			if a.get("target") is Array:
				var tg := Drawing.v2(a["target"])
				var d := (tg - bp).normalized()
				_l(P, bp + d * r2, tg, W_THIN, "solid", c, "OLCU")
				_circ(P, tg, 0.6, W_THIN, "solid", c, "OLCU")
		"surface":
			_surface(P, a, c)
		"gdt":
			_gdt(P, a, c)
		"datum":
			var dp := Drawing.v2(a["pos"])
			var box := Rect2(dp - Vector2(3.5, 0), Vector2(7, 7))
			_rect(P, box, W_THIN, c, "OLCU")
			_txt(P, dp + Vector2(0, 1.75), 3.5, str(a.get("label", "A")), "c", 0.0, c)
			var tgt2 := Drawing.v2(a.get("target", [dp.x, dp.y - 10]))
			_l(P, dp, tgt2 + Vector2(0, 2.5) if tgt2.y < dp.y else tgt2, W_THIN, "solid", c, "OLCU")
			P.append({"t": "fill", "pts": PackedVector2Array([tgt2 + Vector2(-2, 0), tgt2 + Vector2(2, 0), tgt2 + Vector2(0, 2.5)]), "c": c, "lay": "OLCU"})
		"weld":
			_weld(P, a, c)


static func _dim(P: Array, doc: Object, sh: Dictionary, a: Dictionary, c: Color) -> void:
	var v := Drawing.find_view(sh, int(a.get("view", -1)))
	if v.is_empty():
		return
	var g := a.duplicate()
	g.merge(_model_dim_points(doc, sh, v, a), true)
	var value := dim_value(doc, sh, a)
	var kind := str(a.get("kind", "a"))
	var off := Drawing.view_to_sheet(sh, v, Drawing.v2(a.get("off", [0, 0])))
	match kind:
		"h", "v", "a":
			var p1 := Drawing.view_to_sheet(sh, v, Drawing.v2(g["p1"]))
			var p2 := Drawing.view_to_sheet(sh, v, Drawing.v2(g["p2"]))
			var u: Vector2
			if kind == "h":
				u = Vector2.RIGHT
			elif kind == "v":
				u = Vector2.UP
			else:
				u = (p2 - p1).normalized()
				if u.length() < 1e-9:
					u = Vector2.RIGHT
			var n := Vector2(-u.y, u.x)
			var d1 := p1 + n * (off - p1).dot(n)
			var d2 := p2 + n * (off - p2).dot(n)
			for pair in [[p1, d1], [p2, d2]]:
				var e: Vector2 = pair[1] - pair[0]
				if e.length() > 1.0:
					var en := e.normalized()
					_l(P, pair[0] + en * 1.0, pair[1] + en * 2.0, W_THIN, "solid", c, "OLCU")
			_l(P, d1, d2, W_THIN, "solid", c, "OLCU")
			var dd := d2 - d1
			if dd.length() > 1e-6:
				_arrow(P, d1, -dd, c)
				_arrow(P, d2, dd, c)
			var ang := u.angle()
			if ang > PI * 0.5 + 1e-6 or ang < -PI * 0.5 + 1e-6:
				ang += PI
			var mid := (d1 + d2) * 0.5
			var up := Vector2(-sin(ang), cos(ang))
			_dim_label(P, mid + up * 1.0, ang, a, value, c)
		"dia", "rad":
			var cc := Drawing.view_to_sheet(sh, v, Drawing.v2(g["c"]))
			var r := float(g["r"]) * Drawing.view_scale(sh, v)
			var dirv := (off - cc)
			if dirv.length() < 1e-6:
				dirv = Vector2(1, 1)
			dirv = dirv.normalized()
			var edge := cc + dirv * r
			if kind == "dia":
				var other := cc - dirv * r
				_l(P, other, off, W_THIN, "solid", c, "OLCU")
				_arrow(P, edge, dirv * -1.0 if off.distance_to(cc) > r else dirv, c)
				_arrow(P, other, -dirv, c)
			else:
				_l(P, cc, off, W_THIN, "solid", c, "OLCU")
				_arrow(P, edge, dirv, c)
			var tx := text_width(dim_text(a, value)["main"] + dim_text(a, value)["extra"], TXT_H)
			var shelf := off + Vector2(tx + 2.0 if dirv.x >= 0 else -tx - 2.0, 0)
			_l(P, off, shelf, W_THIN, "solid", c, "OLCU")
			_dim_label(P, (off + shelf) * 0.5 + Vector2(0, 1.0), 0.0, a, value, c)
		"ang":
			var a1 := Drawing.view_to_sheet(sh, v, Drawing.v2(g["l1"][0]))
			var b1 := Drawing.view_to_sheet(sh, v, Drawing.v2(g["l1"][1]))
			var a2 := Drawing.view_to_sheet(sh, v, Drawing.v2(g["l2"][0]))
			var b2 := Drawing.view_to_sheet(sh, v, Drawing.v2(g["l2"][1]))
			var I = Geometry2D.line_intersects_line(a1, b1 - a1, a2, b2 - a2)
			if I == null:
				return
			var Ip: Vector2 = I
			var rr := Ip.distance_to(off)
			var u1 := (b1 - a1).normalized()
			var u2 := (b2 - a2).normalized()
			var qd := (off - Ip).normalized()
			if u1.dot(qd) < 0:
				u1 = -u1
			if u2.dot(qd) < 0:
				u2 = -u2
			var t0 := u1.angle()
			var t1 := u2.angle()
			var sweep := wrapf(t1 - t0, -PI, PI)
			var arc := PackedVector2Array()
			for k in 33:
				var t := t0 + sweep * k / 32.0
				arc.append(Ip + Vector2(cos(t), sin(t)) * rr)
			_pl(P, arc, W_THIN, "solid", c, false, "OLCU")
			_arrow(P, arc[0], arc[0] - arc[1], c)
			_arrow(P, arc[arc.size() - 1], arc[arc.size() - 1] - arc[arc.size() - 2], c)
			var tm := t0 + sweep * 0.5
			_dim_label(P, Ip + Vector2(cos(tm), sin(tm)) * (rr + 2.5), 0.0, a, value, c)


static func _surface(P: Array, a: Dictionary, c: Color) -> void:
	var p := Drawing.v2(a["pos"])
	var h := 5.0
	var left := p + Vector2(-h * 0.577, h)
	var right := p + Vector2(h * 1.15, h * 2.0)
	_l(P, left, p, W_THIN, "solid", c, "OLCU")
	_l(P, p, right, W_THIN, "solid", c, "OLCU")
	match str(a.get("mode", "removal")):
		"removal":
			_l(P, left, p + Vector2(h * 0.577, h), W_THIN, "solid", c, "OLCU")
		"no_removal":
			_circ(P, p + Vector2(0, h * 0.55), h * 0.32, W_THIN, "solid", c, "OLCU")
	_l(P, right, right + Vector2(8, 0), W_THIN, "solid", c, "OLCU")
	_txt(P, right + Vector2(0.5, 0.8), 2.5, "Ra " + str(a.get("ra", "1.6")), "l", 0.0, c)
	if a.get("target") is Array:
		var tg := Drawing.v2(a["target"])
		if tg.distance_to(p) > 0.5:
			_l(P, p, tg, W_THIN, "solid", c, "OLCU")


static func _gdt_symbol(P: Array, sym: String, cbox: Vector2, s: float, c: Color) -> void:
	var w := W_THIN
	match sym:
		"position":
			_circ(P, cbox, s * 0.32, w, "solid", c, "OLCU")
			_l(P, cbox - Vector2(s * 0.45, 0), cbox + Vector2(s * 0.45, 0), w, "solid", c, "OLCU")
			_l(P, cbox - Vector2(0, s * 0.45), cbox + Vector2(0, s * 0.45), w, "solid", c, "OLCU")
		"flatness":
			_pl(P, PackedVector2Array([cbox + Vector2(-0.4, -0.18) * s, cbox + Vector2(0.25, -0.18) * s, cbox + Vector2(0.4, 0.18) * s, cbox + Vector2(-0.25, 0.18) * s]), w, "solid", c, true, "OLCU")
		"straightness":
			_l(P, cbox - Vector2(s * 0.4, 0), cbox + Vector2(s * 0.4, 0), w, "solid", c, "OLCU")
		"circularity":
			_circ(P, cbox, s * 0.32, w, "solid", c, "OLCU")
		"cylindricity":
			_circ(P, cbox, s * 0.25, w, "solid", c, "OLCU")
			_l(P, cbox + Vector2(-0.45, -0.38) * s, cbox + Vector2(-0.1, 0.38) * s, w, "solid", c, "OLCU")
			_l(P, cbox + Vector2(0.1, -0.38) * s, cbox + Vector2(0.45, 0.38) * s, w, "solid", c, "OLCU")
		"perpendicularity":
			_l(P, cbox + Vector2(-0.4, -0.35) * s, cbox + Vector2(0.4, -0.35) * s, w, "solid", c, "OLCU")
			_l(P, cbox + Vector2(0, -0.35) * s, cbox + Vector2(0, 0.4) * s, w, "solid", c, "OLCU")
		"parallelism":
			_l(P, cbox + Vector2(-0.35, -0.35) * s, cbox + Vector2(-0.05, 0.4) * s, w, "solid", c, "OLCU")
			_l(P, cbox + Vector2(0.05, -0.35) * s, cbox + Vector2(0.35, 0.4) * s, w, "solid", c, "OLCU")
		"angularity":
			_l(P, cbox + Vector2(-0.4, -0.35) * s, cbox + Vector2(0.4, -0.35) * s, w, "solid", c, "OLCU")
			_l(P, cbox + Vector2(-0.4, -0.35) * s, cbox + Vector2(0.35, 0.35) * s, w, "solid", c, "OLCU")
		"concentricity":
			_circ(P, cbox, s * 0.36, w, "solid", c, "OLCU")
			_circ(P, cbox, s * 0.18, w, "solid", c, "OLCU")
		"symmetry":
			for dy in [-0.28, 0.0, 0.28]:
				var hw: float = 0.4 if dy == 0.0 else 0.25
				_l(P, cbox + Vector2(-hw, dy) * s, cbox + Vector2(hw, dy) * s, w, "solid", c, "OLCU")
		"profile_line", "profile_surface":
			var arc := PackedVector2Array()
			for k in 17:
				var t := PI * k / 16.0
				arc.append(cbox + Vector2(cos(t) * 0.38, sin(t) * 0.38 - 0.15) * s)
			if sym == "profile_surface":
				arc.append(arc[0])
			_pl(P, arc, w, "solid", c, false, "OLCU")
		"runout", "total_runout":
			_l(P, cbox + Vector2(-0.3, -0.35) * s, cbox + Vector2(0.15, 0.35) * s, w, "solid", c, "OLCU")
			_arrow(P, cbox + Vector2(0.2, 0.42) * s, Vector2(0.45, 0.7), c, s * 0.3)
			if sym == "total_runout":
				_l(P, cbox + Vector2(-0.4, -0.38) * s, cbox + Vector2(0.4, -0.38) * s, w, "solid", c, "OLCU")


static func _gdt(P: Array, a: Dictionary, c: Color) -> void:
	var p := Drawing.v2(a["pos"])
	var h := 7.0
	var x := p.x
	_rect(P, Rect2(Vector2(x, p.y), Vector2(h, h)), W_THIN, c, "OLCU")
	_gdt_symbol(P, str(a.get("sym", "position")), Vector2(x + h * 0.5, p.y + h * 0.5), h, c)
	x += h
	var tol := ("Ø" if bool(a.get("dia", false)) else "") + str(a.get("tol", "0.05"))
	var mod := str(a.get("mod", ""))
	var tw := text_width(tol, 3.5) + 3.0 + (4.5 if mod != "" else 0.0)
	_rect(P, Rect2(Vector2(x, p.y), Vector2(tw, h)), W_THIN, c, "OLCU")
	_txt(P, Vector2(x + 1.5, p.y + 1.75), 3.5, tol, "l", 0.0, c)
	if mod != "":
		var mc := Vector2(x + tw - 3.0, p.y + h * 0.5)
		_circ(P, mc, 1.9, W_THIN, "solid", c, "OLCU")
		_txt(P, mc - Vector2(0, 1.1), 2.2, mod, "c", 0.0, c)
	x += tw
	for dl in a.get("datums", []):
		if str(dl) == "":
			continue
		_rect(P, Rect2(Vector2(x, p.y), Vector2(h, h)), W_THIN, c, "OLCU")
		_txt(P, Vector2(x + h * 0.5, p.y + 1.75), 3.5, str(dl), "c", 0.0, c)
		x += h
	if a.get("target") is Array:
		var tg := Drawing.v2(a["target"])
		var start := Vector2(p.x, p.y + h * 0.5)
		_l(P, start, Vector2(start.x - 4.0, start.y), W_THIN, "solid", c, "OLCU")
		_l(P, Vector2(start.x - 4.0, start.y), tg, W_THIN, "solid", c, "OLCU")
		_arrow(P, tg, tg - Vector2(start.x - 4.0, start.y), c)


static func _weld(P: Array, a: Dictionary, c: Color) -> void:
	var p := Drawing.v2(a["pos"])
	var L := 22.0
	_l(P, p, p + Vector2(L, 0), W_THIN, "solid", c, "OLCU")
	if a.get("target") is Array:
		var tg := Drawing.v2(a["target"])
		_l(P, p, tg, W_THIN, "solid", c, "OLCU")
		_arrow(P, tg, tg - p, c)
	if bool(a.get("all_around", false)):
		_circ(P, p, 1.5, W_THIN, "solid", c, "OLCU")
	var side := str(a.get("side", "arrow"))
	var sx := p.x + L * 0.45
	for sgn in ([-1.0] if side == "arrow" else ([1.0] if side == "other" else [-1.0, 1.0])):
		var base := Vector2(sx, p.y)
		if str(a.get("kind", "fillet")) == "fillet":
			_pl(P, PackedVector2Array([base, base + Vector2(0, 4.0 * sgn), base + Vector2(4.0, 0)]), W_THIN, "solid", c, true, "OLCU")
		else:
			_l(P, base + Vector2(-2.0, 4.0 * sgn), base, W_THIN, "solid", c, "OLCU")
			_l(P, base, base + Vector2(2.0, 4.0 * sgn), W_THIN, "solid", c, "OLCU")
		_txt(P, Vector2(sx - 1.5, p.y + (1.0 if sgn > 0 else -4.0)), 2.5, str(a.get("size", "5")), "r", 0.0, c)
	# Kuyruk (işlem notu)
	if str(a.get("note", "")) != "":
		_l(P, p + Vector2(L, 0), p + Vector2(L + 3, 3), W_THIN, "solid", c, "OLCU")
		_l(P, p + Vector2(L, 0), p + Vector2(L + 3, -3), W_THIN, "solid", c, "OLCU")
		_txt(P, p + Vector2(L + 4, -1.2), 2.5, str(a["note"]), "l", 0.0, c)


# ---------------------------------------------------------------- tablolar

static func _table(P: Array, origin: Vector2, cols: Array, rows: Array, header: Array, header_top := false) -> void:
	var rh := 6.0
	var all_rows := [header] + rows
	var y := origin.y
	if header_top:
		y = origin.y + rh * all_rows.size()
		rh = -6.0
	for r in all_rows.size():
		var x := origin.x
		var row: Array = all_rows[r]
		for k in cols.size():
			_rect(P, Rect2(Vector2(x, y if rh > 0 else y + rh), Vector2(float(cols[k]), absf(rh))).abs(), W_THIN if r > 0 else W_VIS)
			_txt(P, Vector2(x + 1.5, (y if rh > 0 else y + rh) + 1.8), 2.5 if r > 0 else 2.2, str(row[k]) if k < row.size() else "")
			x += float(cols[k])
		y += rh


static func bom_rows(doc: Object) -> Array:
	return [["1", doc.part_name, doc.material if doc.material != "" else "—", "1"]]


static func _bom(P: Array, doc: Object, sh: Dictionary, opts := {}) -> void:
	var size := Drawing.sheet_size(sh)
	var m := Drawing.MARGIN
	var cols := [12.0, 88.0, 55.0, 25.0]
	var rows: Array = opts.get("bom_rows", bom_rows(doc))
	var w := 180.0
	# Antetin hemen üstüne, satırlar aşağıdan yukarıya (ISO düzeni: başlık en altta)
	var o := Vector2(size.x - m - w, m + Drawing.TITLE_H)
	_table(P, o, cols, rows, ["NO", "PARÇA ADI", "MALZEME", "ADET"])


static func _revs(P: Array, sh: Dictionary) -> void:
	var size := Drawing.sheet_size(sh)
	var m := Drawing.MARGIN
	var cols := [14.0, 96.0, 40.0, 30.0]
	var rows: Array = []
	for r in sh.get("revs", []):
		rows.append([str(r.get("rev", "")), str(r.get("desc", "")), str(r.get("date", "")), str(r.get("by", ""))])
	var h := 6.0 * (rows.size() + 1)
	_table(P, Vector2(size.x - m - 180.0, size.y - m - h), cols, rows, ["REV", "AÇIKLAMA", "TARİH", "ONAY"], true)
