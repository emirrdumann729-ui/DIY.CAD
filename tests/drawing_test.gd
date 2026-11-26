extends SceneTree
## Faz 6 teknik resim testleri (çekirdek gerektirmez): izdüşüm yönelimleri, kesit, kırık ve detay
## dönüşümleri, tarama, yerleşim, boyut metni, PDF / SVG / DXF çıktıları, belge kaydı.
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/drawing_test.gd

var fails := 0
var passes := 0
var tmp := ""


func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		print("  OK   ", label)
	else:
		fails += 1
		print("  FAIL ", label)


func near(a: float, b: float, tol := 1e-4) -> bool:
	return absf(a - b) <= tol


func vnear(a: Vector3, b: Vector3, tol := 1e-5) -> bool:
	return a.distance_to(b) <= tol


func _initialize() -> void:
	tmp = OS.get_user_data_dir().path_join("drawing_test")
	DirAccess.make_dir_recursive_absolute(tmp)
	Units.apply_dict({})
	run_geometry()
	run_layout()
	run_annotations()
	run_export()
	run_document()
	print("")
	print("RESİM SONUÇ: %d başarılı, %d başarısız" % [passes, fails])
	quit(1 if fails > 0 else 0)


func run_geometry() -> void:
	print("== Sayfa ve izdüşüm")
	var sh := Drawing.new_sheet("S", "A3", "ISO")
	check(Drawing.sheet_size(sh) == Vector2(420, 297) and sh["proj"] == "first", "A3 ISO yatay, 1. açı")
	sh["portrait"] = true
	check(Drawing.sheet_size(sh) == Vector2(297, 420), "dikey sayfa")
	check(Drawing.new_sheet("S", "ANSI B", "ANSI")["proj"] == "third", "ANSI → 3. açı")
	check(Drawing.scale_text(2.0) == "2:1" and Drawing.scale_text(0.5) == "1:2" and Drawing.scale_text(0.4) == "1:2.5", "ölçek metni")
	var fd: Vector3 = Drawing.ORIENTS["front"][0]
	var fx: Vector3 = Drawing.ORIENTS["front"][1]
	# 3. açı: sağa konan görünüş sağdan bakış; 1. açı: soldan bakış sağa konur
	var r3 := Drawing.projected_axes(fd, fx, "right", "third")
	var r1 := Drawing.projected_axes(fd, fx, "right", "first")
	check(vnear(r3["dir"], Vector3(1, 0, 0)) and vnear(r3["x"], Vector3(0, 0, -1)), "3. açı sağ görünüş = sağdan bakış (ORIENTS.right ile aynı)")
	check(vnear(r1["dir"], Vector3(-1, 0, 0)) and vnear(r1["x"], Vector3(0, 0, 1)), "1. açı sağdaki görünüş = soldan bakış")
	var u3 := Drawing.projected_axes(fd, fx, "up", "third")
	var d1 := Drawing.projected_axes(fd, fx, "down", "first")
	check(vnear(u3["dir"], Vector3(0, 1, 0)) and vnear(d1["dir"], Vector3(0, 1, 0)), "üstten bakış: 3. açıda üstte, 1. açıda altta")
	# Yukarı yönler ortak: yan görünüşte yukarı = +Y
	check(vnear((r1["dir"] as Vector3).cross(r1["x"]), Vector3(0, 1, 0)), "yan görünüşte yukarı = +Y")
	var ax := {"dir": fd, "x": fx}
	var p := Vector3(3, 4, 7)
	var q := Drawing.project(ax, p)
	check(q == Vector2(3, 4) and vnear(Drawing.to_3d(ax, q), Vector3(3, 4, 0)), "önden izdüşüm ve geri dönüş")
	var iso := {"dir": Drawing.ORIENTS["iso"][0], "x": Drawing.ORIENTS["iso"][1]}
	check(near(Drawing.project(iso, Vector3(1, 1, 1)).length(), 0.0, 1e-6), "izometrikte (1,1,1) noktaya izdüşer")

	print("== Kesit ve yardımcı görünüş")
	var sd := Drawing.section_def(ax, Vector2(-10, 5), Vector2(10, 5), false)
	check(vnear(sd["o"], Vector3(-10, 5, 0)) and vnear(sd["n"], Vector3(0, -1, 0)), "yatay kesit çizgisi: düzlem y=5, normal -Y")
	check(near((sd["dir"] as Vector3).dot(sd["x"]), 0.0, 1e-9), "kesit görünüşü eksenleri dik")
	var sdf := Drawing.section_def(ax, Vector2(-10, 5), Vector2(10, 5), true)
	check(vnear(sdf["n"], Vector3(0, 1, 0)), "kesit yönü çevrilebilir")
	check(Drawing.section_def(ax, Vector2(1, 1), Vector2(1, 1), false).is_empty(), "sıfır uzunluklu kesit reddedilir")
	var aux := Drawing.aux_axes(ax, Vector2(0, 0), Vector2(10, 10), false)
	var ad: Vector3 = aux["dir"]
	check(near(ad.z, 0.0, 1e-9) and near(ad.dot(Vector3(1, 1, 0).normalized()), 0.0, 1e-6), "yardımcı görünüş kenara dik bakar")

	print("== Kırık görünüş")
	var brs := [{"axis": "x", "a": 60.0, "b": 90.0}, {"axis": "x", "a": 20.0, "b": 40.0}]
	var gap := 6.0
	check(near(Drawing.break_map(Vector2(10, 0), brs, gap).x, 10.0), "ilk kırıktan önce değişmez")
	check(near(Drawing.break_map(Vector2(50, 0), brs, gap).x, 50.0 - 14.0), "ilk kırıktan sonra 20-6=14 kayar")
	check(near(Drawing.break_map(Vector2(100, 0), brs, gap).x, 100.0 - 14.0 - 24.0), "iki kırık sonrası kaydırmalar toplanır")
	var vv := {"id": 1, "type": "model", "pos": [100.0, 50.0], "scale": 1.0, "breaks": brs}
	var sh2 := Drawing.new_sheet("S")
	var ok_rt := true
	for x in [0.0, 15.0, 25.0, 45.0, 59.0, 70.0, 95.0, 130.0]:
		var pt := Vector2(x, 3.0)
		var back := Drawing.sheet_to_view(sh2, vv, Drawing.view_to_sheet(sh2, vv, pt))
		if back.distance_to(pt) > 1e-4:
			ok_rt = false
			print("     ", pt, " → ", back)
	check(ok_rt, "kırıklı görünüşte sayfa ↔ görünüş dönüşümü tersinir")
	var pieces := Drawing.clip_breaks(PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]), brs)
	check(pieces.size() == 3, "kırıklar çizgiyi 3 parçaya böler (%d)" % pieces.size())
	var ln := 0.0
	for pc in pieces:
		ln += (pc as PackedVector2Array)[0].distance_to((pc as PackedVector2Array)[(pc as PackedVector2Array).size() - 1])
	check(near(ln, 50.0), "kalan uzunluk 100-20-30 = 50 (%.3f)" % ln)

	print("== Detay ve tarama")
	var cl := Drawing.clip_circle(PackedVector2Array([Vector2(-20, 0), Vector2(20, 0)]), Vector2.ZERO, 5.0)
	check(cl.size() == 1 and near((cl[0] as PackedVector2Array)[0].distance_to((cl[0] as PackedVector2Array)[1]), 10.0), "daire kırpma: çap kadar parça")
	check(Drawing.clip_circle(PackedVector2Array([Vector2(-20, 9), Vector2(20, 9)]), Vector2.ZERO, 5.0).is_empty(), "daire dışı çizgi atılır")
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var hl := Drawing.hatch_lines([sq], 45.0, 1.0)
	var tot := 0.0
	for seg in hl:
		tot += (seg[0] as Vector2).distance_to(seg[1])
	check(near(tot, 100.0, 1.5), "tarama çizgisi toplam uzunluğu ≈ alan / aralık (%.2f)" % tot)
	var hole := PackedVector2Array([Vector2(3, 3), Vector2(7, 3), Vector2(7, 7), Vector2(3, 7)])
	var tot2 := 0.0
	for seg in Drawing.hatch_lines([sq, hole], 45.0, 1.0):
		tot2 += (seg[0] as Vector2).distance_to(seg[1])
	check(near(tot2, 84.0, 1.5), "delikli bölge taranmaz (çift-tek kuralı) (%.2f)" % tot2)
	check(near(absf(Drawing.polygon_area(sq)), 100.0), "çokgen alanı")


func run_layout() -> void:
	print("== Standart yerleşim")
	for proj in ["first", "third"]:
		var sh := Drawing.new_sheet("S", "A3", "ISO" if proj == "first" else "ANSI")
		sh["size"] = "A3"
		var aabb := AABB(Vector3(-50, 0, -30), Vector3(100, 40, 60))
		var lay := Drawing.standard_layout(sh, aabb)
		var s: float = lay["scale"]
		var rects: Array = []
		var front := Vector2.ZERO
		for item in lay["views"]:
			var axes := {}
			if item.has("orient"):
				axes = {"dir": Drawing.ORIENTS[item["orient"]][0], "x": Drawing.ORIENTS[item["orient"]][1]}
			else:
				axes = Drawing.projected_axes(Drawing.ORIENTS["front"][0], Drawing.ORIENTS["front"][1], item["side"], proj)
			var r := Drawing.box_rect(axes, aabb)
			var pos: Vector2 = item["pos"]
			rects.append(Rect2(pos + r.position * s, r.size * s))
			if item.get("orient", "") == "front":
				front = pos + r.get_center() * s
		var inside := true
		var overlap := false
		var frame := Rect2(Vector2(10, 10), Drawing.sheet_size(sh) - Vector2(20, 20))
		for i in rects.size():
			if not frame.encloses(rects[i]):
				inside = false
			for j in range(i + 1, rects.size()):
				if (rects[i] as Rect2).grow(-0.01).intersects(rects[j]):
					overlap = true
		check(inside and not overlap, "%s açı: 4 görünüş çerçeve içinde, çakışmasız (ölçek %s)" % [proj, Drawing.scale_text(s)])
		var top_c: Vector2 = (rects[2] as Rect2).get_center()
		check((top_c.y < front.y) == (proj == "first") and near(top_c.x, front.x, 1e-3), "%s açı: üstten görünüş %s" % [proj, "altta" if proj == "first" else "üstte"])
		check(near((rects[1] as Rect2).get_center().y, front.y, 1e-3), "%s açı: yan görünüş ön görünüşle hizalı" % proj)
	var big := Drawing.standard_layout(Drawing.new_sheet("S"), AABB(Vector3.ZERO, Vector3(1000, 400, 300)))
	check(float(big["scale"]) < 0.25, "büyük parça küçültülür (%s)" % Drawing.scale_text(big["scale"]))
	var tiny := Drawing.standard_layout(Drawing.new_sheet("S"), AABB(Vector3.ZERO, Vector3(8, 4, 3)))
	check(float(tiny["scale"]) >= 5.0, "küçük parça büyütülür (%s)" % Drawing.scale_text(tiny["scale"]))


func fake_doc() -> CadDocument:
	var d := CadDocument.new()
	d.load_dict({})
	d.part_name = "Flanş ĞİŞ"
	d.material = "Çelik"
	return d


func box_geo() -> Dictionary:
	return {"visible": [[[0, 0], [40, 0]], [[40, 0], [40, 20]], [[40, 20], [0, 20]], [[0, 20], [0, 0]]],
		"hidden": [[[10, 0], [10, 20]]], "tangent": [], "circles": [{"c": [20, 10], "r": 5.0, "full": true}],
		"hatch": [[[[0, 0], [40, 0], [40, 20], [0, 20]]]]}


func run_annotations() -> void:
	print("== Boyut metni ve açıklamalar")
	check(DrawingRender.dim_text({"kind": "h"}, 25.0)["main"] == "25", "doğrusal boyut")
	check(DrawingRender.dim_text({"kind": "dia"}, 12.5)["main"] == "Ø12.5", "çap ön eki")
	check(DrawingRender.dim_text({"kind": "rad"}, 3.0)["main"] == "R3", "yarıçap ön eki")
	var t1 := DrawingRender.dim_text({"kind": "h", "tol": {"type": "sym", "up": 0.1}}, 25.0)
	check(t1["extra"] == " ±0.1", "simetrik tolerans")
	var t2 := DrawingRender.dim_text({"kind": "h", "tol": {"type": "dev", "up": 0.2, "lo": 0.1}}, 25.0)
	check(t2["stack"] == ["+0.2", "-0.1"], "sapma toleransı (üst/alt)")
	var t3 := DrawingRender.dim_text({"kind": "h", "tol": {"type": "limit", "up": 0.2, "lo": 0.1}}, 25.0)
	check(t3["stack"] == ["25.2", "24.9"], "sınır boyutları")
	var t4 := DrawingRender.dim_text({"kind": "dia", "tol": {"type": "fit", "fit": "H7"}}, 10.0)
	check(t4["main"] + t4["extra"] == "Ø10 H7", "geçme toleransı")
	check(DrawingRender.dim_text({"kind": "h", "ref": true}, 5.0)["main"].begins_with("("), "referans boyut parantezli")
	var sh := Drawing.new_sheet("S")
	sh["views"].append({"id": Drawing.next_id(sh), "type": "model", "orient": "front", "pos": [100.0, 150.0], "hidden": "visible_hidden", "tangent": "show"})
	var doc := fake_doc()
	var dims := [{"kind": "h", "p1": [0, 0], "p2": [40, 0]}, {"kind": "v", "p1": [40, 0], "p2": [40, 20]}, {"kind": "a", "p1": [0, 0], "p2": [30, 40]},
		{"kind": "dia", "c": [0, 0], "r": 5.0}, {"kind": "ang", "l1": [[0, 0], [10, 0]], "l2": [[0, 0], [10, 10]]}]
	var exp := [40.0, 20.0, 50.0, 10.0, 45.0]
	var all_ok := true
	for i in dims.size():
		var a: Dictionary = dims[i]
		a["view"] = 1
		if not near(DrawingRender.dim_value(doc, sh, a), exp[i], 1e-4):
			all_ok = false
	check(all_ok, "boyut değerleri: yatay, dikey, hizalı, çap, açı")
	var types := ["dim", "note", "balloon", "surface", "gdt", "datum", "weld", "centermark", "centerline"]
	sh["anns"] = [
		{"id": 10, "type": "dim", "view": 1, "kind": "h", "p1": [0, 0], "p2": [40, 0], "off": [20, -8], "tol": {"type": "sym", "up": 0.05}},
		{"id": 11, "type": "note", "pos": [40, 40], "text": "KESKİN KÖŞELERİ KIR\nGENEL TOLERANS ISO 2768-m", "h": 3.5},
		{"id": 12, "type": "balloon", "pos": [180, 200], "target": [120, 160], "num": "1"},
		{"id": 13, "type": "surface", "pos": [150, 120], "ra": "1.6", "mode": "removal"},
		{"id": 14, "type": "gdt", "pos": [200, 120], "target": [140, 150], "sym": "position", "tol": "0.05", "dia": true, "mod": "M", "datums": ["A", "B"]},
		{"id": 15, "type": "datum", "pos": [90, 130], "target": [100, 150], "label": "A"},
		{"id": 16, "type": "weld", "pos": [220, 180], "target": [140, 170], "kind": "fillet", "size": "5", "side": "both", "all_around": true, "note": "111"},
		{"id": 17, "type": "centermark", "view": 1, "c": [20, 10], "r": 5.0},
		{"id": 18, "type": "centerline", "view": 1, "a": [0, 10], "b": [40, 10]},
	]
	sh["revs"] = [{"rev": "A", "desc": "İlk yayın", "date": "2026-11-22", "by": "ED"}]
	var opts := {"mass": 123.4}
	var prims := DrawingRender.build(doc, sh, {1: box_geo()}, opts)
	var texts := []
	var n_dash := 0
	var n_chain := 0
	for p in prims:
		if p["t"] == "txt":
			texts.append(p["s"])
		if str(p.get("s", "")) == "dash":
			n_dash += 1
		if str(p.get("s", "")) == "chain":
			n_chain += 1
	check("Flanş ĞİŞ" in texts, "antette parça adı")
	check("Çelik" in texts, "antette malzeme")
	check("40 ±0.05" in texts, "toleranslı boyut metni çizilir")
	check("KESKİN KÖŞELERİ KIR" in texts and "GENEL TOLERANS ISO 2768-m" in texts, "çok satırlı not")
	check("Ra 1.6" in texts and "Ø0.05" in texts and "A" in texts and "111" in texts, "yüzey, GD&T, datum ve kaynak metinleri")
	check("İlk yayın" in texts, "revizyon tablosu")
	check(n_dash >= 1, "gizli çizgi kesikli")
	check(n_chain >= 2, "merkez işareti / çizgisi noktalı-çizgi")
	var bb: Dictionary = opts["bboxes"]
	check(bb.has(1) and (bb[1] as Rect2).has_point(Vector2(120, 160)), "görünüş sınır kutusu sayfada (%s)" % str(bb.get(1)))
	sh["views"][0]["hidden"] = "removed"
	var n_dash2 := 0
	for p in DrawingRender.build(doc, sh, {1: box_geo()}, {}):
		if str(p.get("s", "")) == "dash" and p.get("lay", "") == "GIZLI":
			n_dash2 += 1
	check(n_dash2 == 0, "gizli çizgiler kaldırılabilir")
	# Detay görünüşü: ebeveyn geometrisi daireyle kırpılır ve büyütülür
	sh["views"].append({"id": 2, "type": "detail", "parent": 1, "pos": [300.0, 150.0], "detail": {"c": [40, 0], "r": 6.0, "factor": 3.0, "label": "B"}})
	var dg := DrawingRender.view_geometry(sh, sh["views"][1], {1: box_geo()})
	var ok_in := not (dg["visible"] as Array).is_empty()
	for pl in dg["visible"]:
		for q in pl:
			if (q as Vector2).distance_to(Vector2(40, 0)) > 6.0 + 1e-4:
				ok_in = false
	check(ok_in, "detay görünüşü daire içinde kırpılır")
	check(near(Drawing.view_scale(sh, sh["views"][1]), 3.0), "detay ölçeği = ebeveyn × büyütme")
	check(Drawing.view_to_sheet(sh, sh["views"][1], Vector2(40, 0)).is_equal_approx(Vector2(300, 150)), "detay merkezi görünüş konumuna oturur")
	# Kesit taraması bölge içinde
	var sg := DrawingRender.view_geometry(sh, sh["views"][0], {1: box_geo()})
	var hl: Array = sg["hatch_lines"]
	var ok_h := hl.size() > 5
	for seg in hl:
		for q in seg:
			if not Rect2(-0.01, -0.01, 40.02, 20.02).has_point(q):
				ok_h = false
	check(ok_h, "kesit taraması bölge içinde (%d çizgi)" % hl.size())


func run_export() -> void:
	print("== PDF / SVG / DXF")
	var sh := Drawing.new_sheet("S")
	sh["views"].append({"id": 1, "type": "model", "orient": "front", "pos": [100.0, 150.0]})
	sh["anns"].append({"id": 2, "type": "note", "pos": [30, 30], "text": "ŞİŞLİ ĞÜÇ ışık", "h": 5.0})
	var doc := fake_doc()
	var prims := DrawingRender.build(doc, sh, {1: box_geo()}, {})
	var size := Drawing.sheet_size(sh)
	var pdf := tmp.path_join("t.pdf")
	check(DrawingExport.write_pdf(pdf, [{"size": size, "prims": prims}, {"size": Vector2(297, 210), "prims": prims}], "Test") == OK, "PDF yazıldı")
	var pb := FileAccess.get_file_as_bytes(pdf)
	var pc := pb.duplicate()   # ikili akışlar: bayt konumlarını koruyarak ASCII'ye indir
	for i in pc.size():
		if pc[i] == 0 or pc[i] > 127:
			pc[i] = 32
	var ptxt := pc.get_string_from_ascii()
	check(ptxt.begins_with("%PDF-1.") and ptxt.strip_edges().ends_with("%%EOF"), "PDF başlığı ve sonu")
	check(ptxt.contains("/Count 2") and ptxt.contains("/MediaBox [0 0 1190.55") and ptxt.contains(" 841.89]"), "PDF: 2 sayfa, A3 = 1190.55 × 841.89 pt")
	check(ptxt.contains("/Differences [128 /Gbreve"), "PDF Türkçe karakter kodlaması")
	# xref tablosu: startxref değeri "xref" anahtar kelimesini göstermeli; her nesne kaydı "N 0 obj" konumunu göstermeli
	var sx := ptxt.rfind("startxref")
	var off := int(ptxt.substr(sx + 9).strip_edges().split("\n")[0])
	check(ptxt.substr(off, 4) == "xref", "PDF xref konumu doğru (%d)" % off)
	var xl := ptxt.substr(off).split("\n")
	var n_obj := int(xl[1].split(" ")[1]) - 1
	var xok := n_obj > 3
	for i in n_obj:
		var o := int(xl[3 + i].substr(0, 10))
		if not ptxt.substr(o).begins_with("%d 0 obj" % (i + 1)):
			xok = false
	check(xok, "PDF xref tablosu %d nesnenin konumunu doğru gösterir" % n_obj)
	var sp := ptxt.find("stream\n")
	check(sp > 0 and ptxt.contains("/FlateDecode") and pb[sp + 7] == 0x78, "PDF akışları zlib ile sıkıştırılmış")
	var ef := DrawingExport.embedded_font()
	if ef.is_empty():
		print("     (sistemde gömülebilir TrueType yazı tipi yok — Helvetica kullanıldı)")
	else:
		check(ptxt.contains("/FontFile2") and ptxt.contains("/Subtype /TrueType"), "Türkçe glifler için TrueType yazı tipi gömüldü (%s)" % ef["name"])
		var wd: Array = ef["widths"]
		check(int(wd[130 - 32]) > 0 and int(wd[131 - 32]) > 0 and int(wd["W".unicode_at(0) - 32]) > int(wd["i".unicode_at(0) - 32]), "İ / ı glifleri alt kümede, genişlikler anlamlı")
		check((ef["data"] as PackedByteArray).size() < 200000, "yazı tipi alt kümesi küçük (%d bayt)" % (ef["data"] as PackedByteArray).size())
		check(pb.size() < 150000, "PDF boyutu makul (%d bayt)" % pb.size())
	var svg := tmp.path_join("t.svg")
	check(DrawingExport.write_svg(svg, size, prims) == OK, "SVG yazıldı")
	var stxt := FileAccess.get_file_as_string(svg)
	check(stxt.contains('width="420') and stxt.contains("<line") and stxt.contains("ŞİŞLİ ĞÜÇ ışık") and stxt.contains("stroke-dasharray"), "SVG içeriği (mm, çizgi, Türkçe metin, kesikli)")
	var xml := XMLParser.new()
	var xerr := xml.open(svg)
	var nodes := 0
	while xerr == OK:
		xerr = xml.read()
		nodes += 1
	check(xerr == ERR_FILE_EOF and nodes > 20, "SVG geçerli XML (%d düğüm)" % nodes)
	var dxf := tmp.path_join("t.dxf")
	check(DrawingExport.write_dxf(dxf, prims) == OK, "DXF yazıldı")
	var db := FileAccess.get_file_as_bytes(dxf)
	var dtxt := db.get_string_from_ascii()
	check(dtxt.contains("$DWGCODEPAGE") and dtxt.contains("ANSI_1254") and dtxt.contains("ENTITIES") and dtxt.strip_edges().ends_with("EOF"), "DXF yapısı (R12, cp1254)")
	check(dtxt.contains("GIZLI") and dtxt.contains("DASHED") and dtxt.contains("CENTER"), "DXF katmanları ve çizgi tipleri")
	check(db.find(0xDE) >= 0 and db.find(0xD0) >= 0 and db.find(0xFD) >= 0, "DXF metninde Ş / Ğ / ı cp1254 baytları")
	var n_lines := dtxt.count("\nLINE\n")
	check(n_lines >= 8, "DXF çizgileri (%d)" % n_lines)
	# Grup kodu / değer çiftleri: satır sayısı çift olmalı
	var rows := dtxt.replace("\r\n", "\n").strip_edges().split("\n")
	check(rows.size() % 2 == 0, "DXF kod/değer çiftleri tam")


func run_document() -> void:
	print("== Belge kaydı ve geri al")
	var doc := fake_doc()
	var sh := Drawing.new_sheet("Sayfa1")
	sh["views"].append({"id": Drawing.next_id(sh), "type": "model", "orient": "front", "pos": [100.0, 150.0]})
	doc.checkpoint()
	doc.drawings.append(sh)
	doc.commit()
	var path := tmp.path_join("t.dcad")
	check(doc.save_to(path) == OK, "parça kaydedildi")
	var d2 := CadDocument.new()
	check(d2.load_from(path) == OK and d2.drawings.size() == 1, "resim sayfası dosyadan yüklendi")
	var v: Dictionary = d2.drawings[0]["views"][0]
	check(str(v["orient"]) == "front" and Drawing.v2(v["pos"]) == Vector2(100, 150), "görünüş bilgileri korunur")
	check(int(d2.drawings[0]["next"]) == 2, "kimlik sayacı korunur")
	doc.undo()
	check(doc.drawings.is_empty(), "geri al resim sayfasını kaldırır")
	doc.redo()
	check(doc.drawings.size() == 1, "yinele geri getirir")
