class_name DrawingExport
extends RefCounted
## Teknik resim çıktıları: PDF (vektörel, çok sayfa), SVG ve DXF (R12, katmanlı).
## Girdi: DrawingRender ilkelleri (sayfa mm, sol alt orijin).

const PT := 72.0 / 25.4
const DASH := {"dash": [3.0, 1.5], "chain": [8.0, 1.5, 1.0, 1.5], "phantom": [8.0, 1.5, 1.0, 1.5, 1.0, 1.5]}


# ---------------------------------------------------------------- PDF

## Türkçe karakterler: WinAnsi tabanı + /Differences ile 128..133 kodlarına Ğ ğ İ ı Ş ş
const PDF_TR := {"Ğ": 128, "ğ": 129, "İ": 130, "ı": 131, "Ş": 132, "ş": 133, "•": 149, "–": 150, "—": 151}


static func _pdf_text(s: String) -> PackedByteArray:
	var out := PackedByteArray()
	for ch in s:
		var code := ch.unicode_at(0)
		if PDF_TR.has(ch):
			code = int(PDF_TR[ch])
		elif code > 255 or (code >= 128 and code < 160):
			code = 63  # '?'
		if code == 40 or code == 41 or code == 92:  # ( ) \
			out.append(92)
		out.append(code)
	return out


static var _pdf_widths: Array = []   # gömülü yazı tipinin genişlikleri (kod 32..255, 1000 birim)


## Metin genişliği (mm): gömülü yazı tipi varsa gerçek glif genişlikleri, yoksa tahmin.
static func _pdf_text_width(s: String, h: float) -> float:
	if _pdf_widths.is_empty():
		return DrawingRender.text_width(s, h)
	var sum := 0.0
	for byte in _pdf_text(s):
		if byte >= 32 and byte != 92:
			sum += float(_pdf_widths[byte - 32])
	return sum / 1000.0 * h * 1.38


static func _f(x: float) -> String:
	return String.num(x, 3)


static func _pdf_content(prims: Array) -> PackedByteArray:
	var b := PackedByteArray()
	var add := func(s: String) -> void: b.append_array(s.to_ascii_buffer())
	add.call("1 J 1 j\n")
	for p in prims:
		match str(p["t"]):
			"l", "pl", "circ":
				var c: Color = p.get("col", Color.BLACK) if p["t"] == "circ" else p.get("c", Color.BLACK)
				add.call("%s %s %s RG %s w " % [_f(c.r), _f(c.g), _f(c.b), _f(maxf(float(p["w"]), 0.1) * PT)])
				var dash: Array = DASH.get(str(p.get("s", "solid")), [])
				if dash.is_empty():
					add.call("[] 0 d\n")
				else:
					var parts: Array = []
					for d in dash:
						parts.append(_f(float(d) * PT))
					add.call("[%s] 0 d\n" % " ".join(parts))
				if p["t"] == "l":
					var a: Vector2 = p["a"]
					var e: Vector2 = p["b"]
					add.call("%s %s m %s %s l S\n" % [_f(a.x * PT), _f(a.y * PT), _f(e.x * PT), _f(e.y * PT)])
				elif p["t"] == "pl":
					var pts: PackedVector2Array = p["pts"]
					add.call("%s %s m" % [_f(pts[0].x * PT), _f(pts[0].y * PT)])
					for i in range(1, pts.size()):
						add.call(" %s %s l" % [_f(pts[i].x * PT), _f(pts[i].y * PT)])
					add.call(" s\n" if bool(p.get("closed", false)) else " S\n")
				else:
					# Daire: dört kübik Bezier
					var cc: Vector2 = p["c"]
					var r := float(p["r"]) * PT
					var k := 0.5523 * r
					var x := cc.x * PT
					var y := cc.y * PT
					add.call("%s %s m %s %s %s %s %s %s c %s %s %s %s %s %s c %s %s %s %s %s %s c %s %s %s %s %s %s c S\n" % [
						_f(x + r), _f(y), _f(x + r), _f(y + k), _f(x + k), _f(y + r), _f(x), _f(y + r),
						_f(x - k), _f(y + r), _f(x - r), _f(y + k), _f(x - r), _f(y),
						_f(x - r), _f(y - k), _f(x - k), _f(y - r), _f(x), _f(y - r),
						_f(x + k), _f(y - r), _f(x + r), _f(y - k), _f(x + r), _f(y)])
			"fill":
				var c2: Color = p.get("c", Color.BLACK)
				var pts2: PackedVector2Array = p["pts"]
				add.call("%s %s %s rg %s %s m" % [_f(c2.r), _f(c2.g), _f(c2.b), _f(pts2[0].x * PT), _f(pts2[0].y * PT)])
				for i in range(1, pts2.size()):
					add.call(" %s %s l" % [_f(pts2[i].x * PT), _f(pts2[i].y * PT)])
				add.call(" f\n")
			"txt":
				var c3: Color = p.get("c", Color.BLACK)
				var h := float(p["h"])
				var size := h * 1.38 * PT   # büyük harf yüksekliği ≈ 0.72 em
				var s: String = p["s"]
				var w := _pdf_text_width(s, h)
				var al := str(p.get("al", "l"))
				var dx := 0.0 if al == "l" else (-w * 0.5 if al == "c" else -w)
				var ang := float(p.get("ang", 0.0))
				var ca := cos(ang)
				var sa := sin(ang)
				var o: Vector2 = p["p"]
				var tx := (o.x + dx * ca) * PT
				var ty := (o.y + dx * sa) * PT
				add.call("BT %s %s %s rg /F1 %s Tf %s %s %s %s %s %s Tm (" % [_f(c3.r), _f(c3.g), _f(c3.b), _f(size), _f(ca), _f(sa), _f(-sa), _f(ca), _f(tx), _f(ty)])
				b.append_array(_pdf_text(s))
				add.call(") Tj ET\n")
	return b


# ---------------------------------------------------------------- PDF yazı tipi gömme (TrueType alt kümesi)

## Gömülecek sistem yazı tipleri (ilk bulunan kullanılır). Bulunamazsa gömülmeyen Helvetica kullanılır.
const FONT_CANDIDATES := ["C:/Windows/Fonts/arial.ttf", "C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/tahoma.ttf",
	"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
	"/usr/share/fonts/TTF/DejaVuSans.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf", "/Library/Fonts/Arial.ttf"]
static var font_override := ""      # testler için
static var _font_cache := {}


static func _u16(b: PackedByteArray, o: int) -> int:
	return (b[o] << 8) | b[o + 1]


static func _i16(b: PackedByteArray, o: int) -> int:
	var v := _u16(b, o)
	return v - 65536 if v >= 32768 else v


static func _u32(b: PackedByteArray, o: int) -> int:
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


static func _put16(b: PackedByteArray, v: int) -> void:
	b.append((v >> 8) & 255)
	b.append(v & 255)


static func _put32(b: PackedByteArray, v: int) -> void:
	b.append((v >> 24) & 255)
	b.append((v >> 16) & 255)
	b.append((v >> 8) & 255)
	b.append(v & 255)


## PDF kodu (32..255, WinAnsi + Türkçe farkları) → Unicode
static func _code_unicode(code: int) -> int:
	for ch in PDF_TR:
		if int(PDF_TR[ch]) == code:
			return (ch as String).unicode_at(0)
	if code >= 128 and code < 160:
		# WinAnsi 149-151 (•, –, —) /Differences dışında kalır, kendi kodlarıyla kullanılır
		return -1
	return code


## cmap biçim 4'te Unicode → glif kimliği
static func _cmap4_lookup(b: PackedByteArray, st: int, code: int) -> int:
	var segx2 := _u16(b, st + 6)
	var ends := st + 14
	var starts := ends + segx2 + 2
	var deltas := starts + segx2
	var ranges := deltas + segx2
	for i in segx2 / 2:
		var e := _u16(b, ends + i * 2)
		if code > e:
			continue
		var s := _u16(b, starts + i * 2)
		if code < s:
			return 0
		var ro := _u16(b, ranges + i * 2)
		if ro == 0:
			return (code + _u16(b, deltas + i * 2)) & 0xFFFF
		var ga := ranges + i * 2 + ro + (code - s) * 2
		var g := _u16(b, ga)
		return 0 if g == 0 else (g + _u16(b, deltas + i * 2)) & 0xFFFF
	return 0


## Sistem TrueType yazı tipini okur, kullanılan glifleri tutan küçük bir alt küme üretir.
## Dönüş: {name, data (ttf alt kümesi), widths[224] (1000 birim), bbox, ascent, descent, cap} veya {}.
static func embedded_font() -> Dictionary:
	var path := font_override
	if path == "":
		for c in FONT_CANDIDATES:
			if FileAccess.file_exists(c):
				path = c
				break
	if path == "" or not FileAccess.file_exists(path):
		return {}
	if _font_cache.has(path):
		return _font_cache[path]
	var res := _subset_ttf(FileAccess.get_file_as_bytes(path))
	if not res.is_empty():
		res["name"] = path.get_file().get_basename().capitalize().replace(" ", "") + "-DIYCAD"
	_font_cache[path] = res
	return res


static func _subset_ttf(b: PackedByteArray) -> Dictionary:
	if b.size() < 12 or not (_u32(b, 0) == 0x00010000 or _u32(b, 0) == 0x74727565):
		return {}   # yalnızca TrueType ana hatları (OTF/CFF ve TTC desteklenmez)
	var tables := {}
	for i in _u16(b, 4):
		var r := 12 + i * 16
		tables[b.slice(r, r + 4).get_string_from_ascii()] = [_u32(b, r + 8), _u32(b, r + 12)]
	for need in ["head", "hhea", "hmtx", "maxp", "loca", "glyf", "cmap"]:
		if not tables.has(need):
			return {}
	if tables.has("OS/2"):
		var fs := _u16(b, int(tables["OS/2"][0]) + 8)
		if (fs & 0x000F) == 2:
			return {}   # lisans gömmeye izin vermiyor
	var head: int = tables["head"][0]
	var upm := _u16(b, head + 18)
	var loc_long := _i16(b, head + 50) == 1
	var n_glyphs := _u16(b, int(tables["maxp"][0]) + 4)
	var hhea: int = tables["hhea"][0]
	var n_hm := _u16(b, hhea + 34)
	var hmtx: int = tables["hmtx"][0]
	var loca: int = tables["loca"][0]
	var glyf: int = tables["glyf"][0]
	# cmap (3,1) veya (0,3) biçim 4
	var cm: int = tables["cmap"][0]
	var st := -1
	for i in _u16(b, cm + 2):
		var pid := _u16(b, cm + 4 + i * 8)
		var eid := _u16(b, cm + 6 + i * 8)
		var off := _u32(b, cm + 8 + i * 8)
		if ((pid == 3 and eid == 1) or (pid == 0 and eid <= 4)) and _u16(b, cm + off) == 4:
			st = cm + off
			break
	if st < 0:
		return {}
	var glyph_off := func(g: int) -> int:
		return glyf + (_u32(b, loca + g * 4) if loc_long else _u16(b, loca + g * 2) * 2)
	var glyph_end := func(g: int) -> int:
		return glyf + (_u32(b, loca + (g + 1) * 4) if loc_long else _u16(b, loca + (g + 1) * 2) * 2)
	var adv := func(g: int) -> int:
		return _u16(b, hmtx + mini(g, n_hm - 1) * 4)
	var keep := {0: true}
	var widths: Array = []
	for code in range(32, 256):
		var u := _code_unicode(code)
		var g := _cmap4_lookup(b, st, u) if u >= 0 else 0
		if g > 0 and g < n_glyphs:
			keep[g] = true
		widths.append(int(round(adv.call(g) * 1000.0 / upm)) if g > 0 else 0)
	# Bileşik gliflerin parçaları
	var stack: Array = keep.keys()
	while not stack.is_empty():
		var g: int = stack.pop_back()
		var o: int = glyph_off.call(g)
		if glyph_end.call(g) - o < 10 or _i16(b, o) >= 0:
			continue
		var q := o + 10
		var guard := 0
		while guard < 64:
			guard += 1
			var flags := _u16(b, q)
			var cg := _u16(b, q + 2)
			if not keep.has(cg) and cg < n_glyphs:
				keep[cg] = true
				stack.append(cg)
			q += 4 + (4 if flags & 0x0001 else 2)
			if flags & 0x0008:
				q += 2
			elif flags & 0x0040:
				q += 4
			elif flags & 0x0080:
				q += 8
			if not (flags & 0x0020):
				break
	# Yeni glyf / loca (uzun biçim); kullanılmayan glifler boş
	var nglyf := PackedByteArray()
	var nloca := PackedByteArray()
	for g in n_glyphs:
		_put32(nloca, nglyf.size())
		if keep.has(g):
			var o2: int = glyph_off.call(g)
			var e2: int = glyph_end.call(g)
			if e2 > o2:
				nglyf.append_array(b.slice(o2, e2))
				while nglyf.size() % 4 != 0:
					nglyf.append(0)
	_put32(nloca, nglyf.size())
	var nhead := b.slice(head, head + int(tables["head"][1]))
	nhead[50] = 0
	nhead[51] = 1   # indexToLocFormat = uzun
	nhead[8] = 0
	nhead[9] = 0
	nhead[10] = 0
	nhead[11] = 0   # checkSumAdjustment
	var out_tables := {"head": nhead, "glyf": nglyf, "loca": nloca}
	for t in ["hhea", "hmtx", "maxp", "cmap", "cvt ", "fpgm", "prep", "OS/2"]:
		if tables.has(t):
			out_tables[t] = b.slice(int(tables[t][0]), int(tables[t][0]) + int(tables[t][1]))
	var tags: Array = out_tables.keys()
	tags.sort()
	var font := PackedByteArray()
	_put32(font, 0x00010000)
	var nt := tags.size()
	var es := 0
	while (1 << (es + 1)) <= nt:
		es += 1
	_put16(font, nt)
	_put16(font, (1 << es) * 16)
	_put16(font, es)
	_put16(font, nt * 16 - (1 << es) * 16)
	var off2 := 12 + nt * 16
	var body := PackedByteArray()
	for t in tags:
		var data: PackedByteArray = out_tables[t]
		var padded := data.duplicate()
		while padded.size() % 4 != 0:
			padded.append(0)
		var sum := 0
		for k in range(0, padded.size(), 4):
			sum = (sum + _u32(padded, k)) & 0xFFFFFFFF
		font.append_array((t as String).to_ascii_buffer())
		_put32(font, sum)
		_put32(font, off2 + body.size())
		_put32(font, data.size())
		body.append_array(padded)
	font.append_array(body)
	var os2: int = tables["OS/2"][0] if tables.has("OS/2") else -1
	var asc := _i16(b, hhea + 4)
	var cap := asc * 0.7
	if os2 >= 0 and _u16(b, os2) >= 2 and int(tables["OS/2"][1]) >= 90:
		cap = _i16(b, os2 + 88)
	var k1000 := 1000.0 / upm
	return {"data": font, "widths": widths, "ascent": int(asc * k1000), "descent": int(_i16(b, hhea + 6) * k1000), "cap": int(cap * k1000),
		"bbox": [int(_i16(b, head + 36) * k1000), int(_i16(b, head + 38) * k1000), int(_i16(b, head + 40) * k1000), int(_i16(b, head + 42) * k1000)]}


static func _stream(dict_extra: String, data: PackedByteArray, compress := true) -> PackedByteArray:
	var d := data
	var filt := ""
	if compress:
		var z := data.compress(FileAccess.COMPRESSION_DEFLATE)
		if z.size() > 0 and z.size() < data.size():
			d = z
			filt = " /Filter /FlateDecode"
	var s := ("<< /Length %d%s%s >>\nstream\n" % [d.size(), filt, dict_extra]).to_ascii_buffer()
	s.append_array(d)
	s.append_array("\nendstream".to_ascii_buffer())
	return s


## pages: [{size: Vector2 (mm), prims: Array}]
static func write_pdf(path: String, pages: Array, title := "DIY.CAD") -> Error:
	var objs: Array = []   # PackedByteArray gövdeleri, kimlik = indeks + 1
	objs.append(PackedByteArray())  # 1 katalog (sonra)
	objs.append(PackedByteArray())  # 2 sayfalar (sonra)
	var enc := "<< /Type /Encoding /BaseEncoding /WinAnsiEncoding /Differences [128 /Gbreve /gbreve /Idotaccent /dotlessi /Scedilla /scedilla] >>"
	var ef := embedded_font()
	_pdf_widths = ef.get("widths", [])
	if ef.is_empty():
		objs.append(("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding %s >>" % enc).to_ascii_buffer())   # 3 yazı tipi
	else:
		objs.append(PackedByteArray())   # 3 yazı tipi (aşağıda)
		var fd: PackedByteArray = ef["data"]
		objs.append(_stream(" /Length1 %d" % fd.size(), fd))
		var ff_id := objs.size()
		var bb: Array = ef["bbox"]
		objs.append(("<< /Type /FontDescriptor /FontName /%s /Flags 32 /FontBBox [%d %d %d %d] /ItalicAngle 0 /Ascent %d /Descent %d /CapHeight %d /StemV 80 /FontFile2 %d 0 R >>" % [
			ef["name"], bb[0], bb[1], bb[2], bb[3], ef["ascent"], ef["descent"], ef["cap"], ff_id]).to_ascii_buffer())
		var fdesc_id := objs.size()
		var ws: Array = []
		for w in ef["widths"]:
			ws.append(str(w))
		objs[2] = ("<< /Type /Font /Subtype /TrueType /BaseFont /%s /FirstChar 32 /LastChar 255 /Widths [%s] /FontDescriptor %d 0 R /Encoding %s >>" % [
			ef["name"], " ".join(ws), fdesc_id, enc]).to_ascii_buffer()
	var kids: Array = []
	for pg in pages:
		var size: Vector2 = pg["size"]
		objs.append(_stream("", _pdf_content(pg["prims"])))
		var cid := objs.size()
		objs.append(("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %s %s] /Contents %d 0 R /Resources << /Font << /F1 3 0 R >> >> >>" % [
			_f(size.x * PT), _f(size.y * PT), cid]).to_ascii_buffer())
		kids.append("%d 0 R" % objs.size())
	objs[0] = "<< /Type /Catalog /Pages 2 0 R >>".to_ascii_buffer()
	objs[1] = ("<< /Type /Pages /Kids [%s] /Count %d >>" % [" ".join(kids), kids.size()]).to_ascii_buffer()
	objs.append(("<< /Title (%s) /Producer (DIY.CAD) >>" % title.replace("(", "").replace(")", "")).to_ascii_buffer())
	var info_id := objs.size()
	var out := "%PDF-1.4\n%âãÏÓ\n".to_utf8_buffer()
	var offsets: Array = []
	for i in objs.size():
		offsets.append(out.size())
		out.append_array(("%d 0 obj\n" % (i + 1)).to_ascii_buffer())
		out.append_array(objs[i])
		out.append_array("\nendobj\n".to_ascii_buffer())
	var xref := out.size()
	var x := "xref\n0 %d\n0000000000 65535 f \n" % (objs.size() + 1)
	for o in offsets:
		x += "%010d 00000 n \n" % int(o)
	x += "trailer\n<< /Size %d /Root 1 0 R /Info %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % [objs.size() + 1, info_id, xref]
	out.append_array(x.to_ascii_buffer())
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_buffer(out)
	fa.close()
	return OK


# ---------------------------------------------------------------- SVG

static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func svg_string(size: Vector2, prims: Array) -> String:
	var H := size.y
	var o := PackedStringArray()
	o.append('<?xml version="1.0" encoding="UTF-8"?>')
	o.append('<svg xmlns="http://www.w3.org/2000/svg" width="%smm" height="%smm" viewBox="0 0 %s %s">' % [_f(size.x), _f(size.y), _f(size.x), _f(size.y)])
	o.append('<rect width="100%" height="100%" fill="white"/>')
	o.append('<g fill="none" stroke-linecap="round" stroke-linejoin="round">')
	for p in prims:
		var c: Color = p.get("col", Color.BLACK) if p["t"] == "circ" else p.get("c", Color.BLACK)
		var dash := ""
		var da: Array = DASH.get(str(p.get("s", "solid")), [])
		if not da.is_empty():
			var parts: Array = []
			for d in da:
				parts.append(_f(float(d)))
			dash = ' stroke-dasharray="%s"' % ",".join(parts)
		match str(p["t"]):
			"l":
				var a: Vector2 = p["a"]
				var b: Vector2 = p["b"]
				o.append('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="%s"%s/>' % [_f(a.x), _f(H - a.y), _f(b.x), _f(H - b.y), _hex(c), _f(float(p["w"])), dash])
			"pl":
				var pts: PackedVector2Array = p["pts"]
				var s := PackedStringArray()
				for q in pts:
					s.append("%s,%s" % [_f(q.x), _f(H - q.y)])
				o.append('<%s points="%s" stroke="%s" stroke-width="%s"%s/>' % ["polygon" if bool(p.get("closed", false)) else "polyline", " ".join(s), _hex(c), _f(float(p["w"])), dash])
			"circ":
				var cc: Vector2 = p["c"]
				o.append('<circle cx="%s" cy="%s" r="%s" stroke="%s" stroke-width="%s"%s/>' % [_f(cc.x), _f(H - cc.y), _f(float(p["r"])), _hex(c), _f(float(p["w"])), dash])
			"fill":
				var pts2: PackedVector2Array = p["pts"]
				var s2 := PackedStringArray()
				for q in pts2:
					s2.append("%s,%s" % [_f(q.x), _f(H - q.y)])
				o.append('<polygon points="%s" fill="%s" stroke="none"/>' % [" ".join(s2), _hex(c)])
			"txt":
				var tp: Vector2 = p["p"]
				var anchor: String = {"l": "start", "c": "middle", "r": "end"}.get(str(p.get("al", "l")), "start")
				var ang := -rad_to_deg(float(p.get("ang", 0.0)))
				o.append('<text x="%s" y="%s" font-family="Arial, Helvetica, sans-serif" font-size="%s" fill="%s" stroke="none" text-anchor="%s"%s>%s</text>' % [
					_f(tp.x), _f(H - tp.y), _f(float(p["h"]) * 1.38), _hex(c), anchor,
					(' transform="rotate(%s %s %s)"' % [_f(ang), _f(tp.x), _f(H - tp.y)]) if absf(ang) > 1e-6 else "", _esc(p["s"])])
	o.append("</g>")
	o.append("</svg>")
	return "\n".join(o)


static func write_svg(path: String, size: Vector2, prims: Array) -> Error:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_string(svg_string(size, prims))
	fa.close()
	return OK


# ---------------------------------------------------------------- DXF (R12)

const CP1254 := {"Ç": 0xC7, "ç": 0xE7, "Ğ": 0xD0, "ğ": 0xF0, "İ": 0xDD, "ı": 0xFD, "Ö": 0xD6, "ö": 0xF6, "Ş": 0xDE, "ş": 0xFE,
	"Ü": 0xDC, "ü": 0xFC, "°": 0xB0, "±": 0xB1, "Ø": 0xD8, "ø": 0xF8, "²": 0xB2, "³": 0xB3, "µ": 0xB5, "•": 0x95, "–": 0x96, "—": 0x97}
const LAYERS := {"0": ["CONTINUOUS", 7], "GORUNUR": ["CONTINUOUS", 7], "GIZLI": ["DASHED", 8], "EKSEN": ["CENTER", 1],
	"OLCU": ["CONTINUOUS", 3], "TARAMA": ["CONTINUOUS", 8], "METIN": ["CONTINUOUS", 7], "CERCEVE": ["CONTINUOUS", 7]}


static func _cp(s: String) -> PackedByteArray:
	var out := PackedByteArray()
	for ch in s:
		var code := ch.unicode_at(0)
		if CP1254.has(ch):
			out.append(int(CP1254[ch]))
		elif code < 128:
			out.append(code)
		else:
			out.append(63)
	return out


static func dxf_bytes(prims: Array) -> PackedByteArray:
	var b := PackedByteArray()
	var g := func(code: int, val) -> void:
		b.append_array(("%d\n" % code).to_ascii_buffer())
		if val is PackedByteArray:
			b.append_array(val)
			b.append(10)
		else:
			b.append_array((str(val) + "\n").to_ascii_buffer())
	g.call(0, "SECTION")
	g.call(2, "HEADER")
	g.call(9, "$ACADVER")
	g.call(1, "AC1009")
	g.call(9, "$DWGCODEPAGE")
	g.call(3, "ANSI_1254")
	g.call(9, "$INSUNITS")
	g.call(70, 4)
	g.call(0, "ENDSEC")
	g.call(0, "SECTION")
	g.call(2, "TABLES")
	g.call(0, "TABLE")
	g.call(2, "LTYPE")
	g.call(70, 3)
	for lt in [["CONTINUOUS", "Solid line", []], ["DASHED", "__ __ __", [3.0, -1.5]], ["CENTER", "____ _ ____", [8.0, -1.5, 1.0, -1.5]]]:
		g.call(0, "LTYPE")
		g.call(2, lt[0])
		g.call(70, 0)
		g.call(3, lt[1])
		g.call(72, 65)
		var pat: Array = lt[2]
		g.call(73, pat.size())
		var tot := 0.0
		for v in pat:
			tot += absf(float(v))
		g.call(40, _f(tot))
		for v in pat:
			g.call(49, _f(float(v)))
	g.call(0, "ENDTAB")
	g.call(0, "TABLE")
	g.call(2, "LAYER")
	g.call(70, LAYERS.size())
	for ln in LAYERS:
		g.call(0, "LAYER")
		g.call(2, ln)
		g.call(70, 0)
		g.call(62, LAYERS[ln][1])
		g.call(6, LAYERS[ln][0])
	g.call(0, "ENDTAB")
	g.call(0, "ENDSEC")
	g.call(0, "SECTION")
	g.call(2, "ENTITIES")
	for p in prims:
		var lay := str(p.get("lay", "0"))
		match str(p["t"]):
			"l":
				var a: Vector2 = p["a"]
				var e: Vector2 = p["b"]
				g.call(0, "LINE")
				g.call(8, lay)
				g.call(10, _f(a.x))
				g.call(20, _f(a.y))
				g.call(30, 0)
				g.call(11, _f(e.x))
				g.call(21, _f(e.y))
				g.call(31, 0)
			"pl":
				var pts: PackedVector2Array = p["pts"]
				var n := pts.size()
				var segs := n if bool(p.get("closed", false)) else n - 1
				for i in segs:
					var a2 := pts[i]
					var e2 := pts[(i + 1) % n]
					g.call(0, "LINE")
					g.call(8, lay)
					g.call(10, _f(a2.x))
					g.call(20, _f(a2.y))
					g.call(30, 0)
					g.call(11, _f(e2.x))
					g.call(21, _f(e2.y))
					g.call(31, 0)
			"circ":
				var c: Vector2 = p["c"]
				g.call(0, "CIRCLE")
				g.call(8, lay)
				g.call(10, _f(c.x))
				g.call(20, _f(c.y))
				g.call(30, 0)
				g.call(40, _f(float(p["r"])))
			"fill":
				var q: PackedVector2Array = p["pts"]
				if q.size() >= 3:
					g.call(0, "SOLID")
					g.call(8, lay)
					var order := [0, 1, 2, 2] if q.size() == 3 else [0, 1, 3, 2]
					var codes := [[10, 20], [11, 21], [12, 22], [13, 23]]
					for k in 4:
						var pp := q[order[k]]
						g.call(codes[k][0], _f(pp.x))
						g.call(codes[k][1], _f(pp.y))
			"txt":
				var tp: Vector2 = p["p"]
				var al := str(p.get("al", "l"))
				g.call(0, "TEXT")
				g.call(8, lay)
				g.call(10, _f(tp.x))
				g.call(20, _f(tp.y))
				g.call(30, 0)
				g.call(40, _f(float(p["h"])))
				g.call(1, _cp(p["s"]))
				g.call(50, _f(rad_to_deg(float(p.get("ang", 0.0)))))
				if al != "l":
					g.call(72, 1 if al == "c" else 2)
					g.call(11, _f(tp.x))
					g.call(21, _f(tp.y))
					g.call(31, 0)
	g.call(0, "ENDSEC")
	g.call(0, "EOF")
	return b


static func write_dxf(path: String, prims: Array) -> Error:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_buffer(dxf_bytes(prims))
	fa.close()
	return OK
