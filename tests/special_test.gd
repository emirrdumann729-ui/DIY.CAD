extends SceneTree
## Faz 8 testleri (çekirdek gerektirmez): sac metal büküm profili ve açınım, kaynaklı konstrüksiyon kesim
## listesi, konfigürasyonlar ve tasarım tablosu.
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/special_test.gd

var fails := 0
var passes := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		print("  OK   ", label)
	else:
		fails += 1
		print("  FAIL ", label)


func near(a: float, b: float, tol := 1e-3) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	Units.apply_dict({})
	run_sheet()
	run_flat()
	run_weld()
	run_configs()
	run_cam()
	run_analysis()
	print("")
	print("ÖZEL SONUÇ: %d başarılı, %d başarısız" % [passes, fails])
	quit(1 if fails > 0 else 0)


func new_doc() -> CadDocument:
	var d := CadDocument.new()
	d.load_dict({})
	return d


func sketch(doc: CadDocument, plane: SketchPlane) -> CadFeature:
	var s := doc.new_feature("sketch", "Taslak")
	s.plane = plane
	s.sketch = Sketch.new()
	doc.add_feature(s)
	return s


func rect(sk: Sketch, x0: float, y0: float, x1: float, y1: float) -> void:
	sk.add_rect([sk.add_point(Vector2(x0, y0)), sk.add_point(Vector2(x1, y0)), sk.add_point(Vector2(x1, y1)), sk.add_point(Vector2(x0, y1))])


func loop_area(loop: Array) -> float:
	# Yayları 64 parçalı çokgenle yaklaşıkla
	var poly := PackedVector2Array()
	for c in loop:
		if c["t"] == "line":
			poly.append(Vector2(float(c["a"][0]), float(c["a"][1])))
		else:
			var p0 := Vector2(float(c["p"][0][0]), float(c["p"][0][1]))
			var pm := Vector2(float(c["p"][1][0]), float(c["p"][1][1]))
			var p1 := Vector2(float(c["p"][2][0]), float(c["p"][2][1]))
			# Çember merkezi (üç nokta)
			var d := 2.0 * (p0.x * (pm.y - p1.y) + pm.x * (p1.y - p0.y) + p1.x * (p0.y - pm.y))
			var ux := ((p0.length_squared()) * (pm.y - p1.y) + pm.length_squared() * (p1.y - p0.y) + p1.length_squared() * (p0.y - pm.y)) / d
			var uy := ((p0.length_squared()) * (p1.x - pm.x) + pm.length_squared() * (p0.x - p1.x) + p1.length_squared() * (pm.x - p0.x)) / d
			var cc := Vector2(ux, uy)
			var r := cc.distance_to(p0)
			var a0 := (p0 - cc).angle()
			var am := (pm - cc).angle()
			var a1 := (p1 - cc).angle()
			var da := wrapf(a1 - a0, -PI, PI)
			# Orta noktanın tarafına göre yön
			if absf(wrapf(am - a0, -PI, PI)) > absf(da) or signf(wrapf(am - a0, -PI, PI)) != signf(da):
				da = da - signf(da) * TAU
			for k in 64:
				var a := a0 + da * k / 64.0
				poly.append(cc + Vector2(cos(a), sin(a)) * r)
	return absf(Drawing.polygon_area(poly))


func run_sheet() -> void:
	print("== Sac metal: büküm payı ve bükümlü profil")
	check(near(SheetMetal.bend_allowance(90.0, 2.0, 0.44, 2.0), PI * 0.5 * 2.88), "BA = A·(R + K·T)")
	# L profil: (0,0)→(50,0)→(50,30), T=2, R=3, malzeme solda (köşenin iç tarafı) → çizgi dış yüz (r=5)
	var bp := SheetMetal.bent_profile([Vector2(0, 0), Vector2(50, 0), Vector2(50, 30)], 2.0, 3.0, 0.44, 1.0)
	check(not bp.has("error") and near(float(bp["straights"][0]), 45.0) and near(float(bp["straights"][1]), 25.0), "düz boylar 45 / 25 (geri çekme R+T)")
	var A := loop_area(bp["loop"])
	check(near(A, 2.0 * 70.0 + PI * 0.25 * (25.0 - 9.0), 0.05), "kesit alanı = düzler + çeyrek halka (%.3f)" % A)
	check(near(float(bp["flat_len"]), 70.0 + PI * 0.5 * (3.0 + 0.88)), "açınım boyu (%.4f)" % float(bp["flat_len"]))
	var bp2 := SheetMetal.bent_profile([Vector2(0, 0), Vector2(50, 0), Vector2(50, 30)], 2.0, 3.0, 0.44, -1.0)
	check(near(float(bp2["straights"][0]), 47.0) and near(loop_area(bp2["loop"]), 2.0 * 74.0 + PI * 0.25 * 16.0, 0.05), "malzeme dışta: çizgi iç yüz (geri çekme R)")
	var z := SheetMetal.bent_profile([Vector2(0, 0), Vector2(30, 0), Vector2(30, 20), Vector2(60, 20)], 1.5, 1.0, 0.4, 1.0)
	check(not z.has("error") and (z["bends"] as Array).size() == 2, "Z profil: iki büküm")
	check(SheetMetal.bent_profile([Vector2(0, 0), Vector2(3, 0), Vector2(3, 30)], 2.0, 3.0, 0.44, 1.0).has("error"), "kısa çizgi uyarısı")
	var sec := SheetMetal.flange_section(2.0, 2.0, 90.0, 20.0)
	check(near(loop_area(sec), PI * 0.25 * (16.0 - 4.0) + 2.0 * 20.0, 0.05), "kenar flanşı kesiti: büküm + düz flanş")
	check(SheetMetal.parse_edge(["F5:s:12", "F5:b:3"]) == {"fid": 5, "eid": 12, "cap": "b"}, "kenar adı → taban öğesi ve kapak")
	check(SheetMetal.parse_edge(["F5:s:12", "F7:s:1"]).is_empty(), "taban kenarı olmayan kenar reddedilir")


func tray_doc() -> CadDocument:
	var doc := new_doc()
	var s := sketch(doc, SketchPlane.standard("top"))
	rect(s.sketch, -50, -30, 50, 30)
	var b := doc.new_feature("sm_base", "Taban-Flanş")
	b.params = SheetMetal.DEFAULTS.duplicate()
	b.params["sketch"] = s.id
	doc.add_feature(b)
	var e := doc.new_feature("sm_edge", "Kenar-Flanş")
	var refs: Array = []
	for ent in s.sketch.entities:
		if ent["type"] == "line":
			refs.append({"fn": ["F%d:s:%d" % [b.id, int(ent["id"])], "F%d:b:x" % b.id]})
	e.params = {"edges": refs, "L": 20.0, "A": 90.0, "R": -1.0, "flip": false, "off1": 0.0, "off2": 0.0}
	doc.add_feature(e)
	return doc


func run_flat() -> void:
	print("== Açınım")
	var doc := tray_doc()
	var fp := SheetMetal.flat_pattern(doc)
	var W := PI * 0.5 * (2.0 + 0.44 * 2.0) + 20.0
	var area := 0.0
	for p in fp["outline"]:
		area += absf(Drawing.polygon_area(p))
	check((fp["outline"] as Array).size() == 1, "açınım tek dış sınır (artı şekli)")
	check(near(area, 6000.0 + 320.0 * W, 0.01), "açınım alanı = taban + şeritler (%.3f)" % area)
	check((fp["bends"] as Array).size() == 4 and str(fp["bends"][0]["note"]).begins_with("YUKARI 90°"), "4 büküm çizgisi, not")
	check(near((fp["size"] as Vector2).x, 100.0 + 2.0 * W, 1e-3), "açınım boyutu %.2f" % (fp["size"] as Vector2).x)
	var e: CadFeature = doc.features[2]
	var items := SheetMetal.edge_items(doc, e)
	check(not items.has("error") and (items["items"] as Array).size() == 4, "kenar flanşı: 4 prizma")
	# Flanş dışa doğru: ilk öğenin düzlem x ekseni (dışa) tabandan uzağa bakar
	var it: Dictionary = items["items"][0]
	var o := Vector3(it["plane"]["o"][0], it["plane"]["o"][1], it["plane"]["o"][2])
	var x := Vector3(it["plane"]["x"][0], it["plane"]["x"][1], it["plane"]["x"][2])
	check((o + x * 5.0).distance_to(Vector3.ZERO) > o.distance_to(Vector3.ZERO), "flanş tabanın dışına bakar")
	var prims := SheetMetal.flat_prims(fp)
	var tmp := OS.get_user_data_dir().path_join("special_test")
	DirAccess.make_dir_recursive_absolute(tmp)
	var dxf := tmp.path_join("acinim.dxf")
	check(DrawingExport.write_dxf(dxf, prims) == OK and FileAccess.get_file_as_bytes(dxf).get_string_from_ascii().contains("EKSEN"), "açınım DXF (büküm çizgileri EKSEN katmanında)")
	e.params["off1"] = 3.0
	e.params["off2"] = 3.0
	var fp2 := SheetMetal.flat_pattern(doc)
	var a2 := 0.0
	for p2 in fp2["outline"]:
		a2 += absf(Drawing.polygon_area(p2))
	check(near(a2, 6000.0 + (320.0 - 24.0) * W, 0.01), "kenar boşlukları şeridi kısaltır")


func run_weld() -> void:
	print("== Kaynaklı konstrüksiyon")
	var p := Weldment.profile("shs", "40x40x3")
	check(near(float(p["area"]), 1600.0 - 34.0 * 34.0), "kare profil alanı")
	check(near(float(Weldment.profile("chs", "48.3x2.9")["area"]), PI * (48.3 * 48.3 - 42.5 * 42.5) / 4.0), "boru alanı")
	check(near(float(Weldment.profile("ipe", "100")["area"]), 2.0 * 55.0 * 5.7 + (100.0 - 11.4) * 4.1), "IPE 100 alanı")
	var doc := new_doc()
	var s := sketch(doc, SketchPlane.standard("front"))
	rect(s.sketch, 0, 0, 400, 300)
	var w := doc.new_feature("weld", "Yapısal Üye")
	w.params = {"sketch": s.id, "ptype": "shs", "psize": "40x40x3", "rot": 0.0, "corner": "miter"}
	doc.add_feature(w)
	var r := Weldment.build(doc, w)
	check(not r.has("error") and (r["members"] as Array).size() == 4, "dikdörtgen çerçeve: 4 üye")
	var cl: Array = r["cutlist"]
	check(cl.size() == 2 and int(cl[0]["qty"]) == 2 and int(cl[1]["qty"]) == 2, "kesim listesi: 2 grup × 2 adet")
	check(near(float(cl[0]["angles"][0]), 45.0) and near(float(cl[0]["angles"][1]), 45.0), "gönye açıları 45°")
	var cuts: Array = r["members"][0]["cuts"]
	check(cuts.size() == 2, "her üyede iki gönye kesimi")
	# T birleşimi: ortaya dikey üye
	var mid := s.sketch.add_line(s.sketch.add_point(Vector2(200, 0)), s.sketch.add_point(Vector2(200, 300)))
	var r2 := Weldment.build(doc, w)
	var tm: Dictionary = r2["members"][4]
	check((r2["members"] as Array).size() == 5 and (tm["trim_by"] as Array).size() == 2, "T birleşimi: orta üye iki üyeye göre kırpılır")
	var found := false
	for g in r2["cutlist"]:
		if near(float(g["length"]), 260.0) and int(g["qty"]) == 1:
			found = true
	check(found, "kırpılan üyenin kesim boyu 300 − 2×20 = 260")
	w.params["corner"] = "butt"
	var r3 := Weldment.build(doc, w)
	var lens: Array = []
	for g3 in r3["cutlist"]:
		lens.append(float(g3["length"]))
	check(lens.has(440.0) or lens.has(420.0) or lens.has(380.0) or lens.has(360.0), "alın birleşimi boyları uzatılır / kısaltılır (%s)" % str(lens))
	var tmp := OS.get_user_data_dir().path_join("special_test")
	var csv := tmp.path_join("kesim.csv")
	check(Weldment.write_cutlist_csv(csv, Weldment.doc_cutlist(doc)) == OK and FileAccess.get_file_as_string(csv).contains("Kare profil 40x40x3"), "kesim listesi CSV")


func run_configs() -> void:
	print("== Konfigürasyonlar ve tasarım tablosu")
	var doc := new_doc()
	var s := sketch(doc, SketchPlane.standard("top"))
	rect(s.sketch, -20, -10, 20, 10)
	var ln := -1
	for e in s.sketch.entities:
		if e["type"] == "line":
			ln = int(e["id"])
			break
	var ent := s.sketch.get_entity(ln)
	s.sketch.add_constraint(SketchSolver.make_dimension(s.sketch, {"type": "distance", "p1": int(ent["a"]), "p2": int(ent["b"])}, Vector2(0, -15)))
	var ex := doc.new_feature("extrude", "Ekstrüzyon")
	ex.params = {"sketch": s.id, "depth": 10.0, "end": "blind", "reverse": false, "cut": false}
	doc.add_feature(ex)
	var fil := doc.new_feature("fillet", "Köşe Yuvarlatma")
	doc.add_feature(fil)
	var p := Configs.capture(doc)
	check(p.has("D1@Taslak1") and p.has("D1@Ekstrüzyon1") and p.has("$BASTIR@Köşe Yuvarlatma1"), "parametreler: taslak boyutu, derinlik, bastırma (%s)" % str(p.keys()))
	check(Configs.add(doc, "Uzun") and doc.active_config == "Uzun" and doc.configs.size() == 2, "yeni konfigürasyon etkin")
	ex.params["depth"] = 30.0
	fil.suppressed = true
	Configs.activate(doc, "Varsayılan")
	check(near(float(ex.params["depth"]), 10.0) and not fil.suppressed, "Varsayılan: derinlik 10, yuvarlatma etkin")
	Configs.activate(doc, "Uzun")
	check(near(float(ex.params["depth"]), 30.0) and fil.suppressed, "Uzun: derinlik 30, yuvarlatma bastırılmış")
	var tmp := OS.get_user_data_dir().path_join("special_test")
	var csv := tmp.path_join("tablo.csv")
	check(Configs.write_csv(doc, csv) == OK, "tasarım tablosu yazıldı")
	var txt := FileAccess.get_file_as_string(csv)
	check(txt.contains("Konfigürasyon;") and txt.contains("Uzun;"), "CSV başlık ve satırlar")
	# Yeni satır: Kısa (derinlik 5, taslak boyutu 60)
	var lines := txt.trim_prefix("﻿").strip_edges().split("\n")
	var head := lines[0].split(";")
	var row: Array = ["Kısa"]
	for j in range(1, head.size()):
		match head[j]:
			"D1@Ekstrüzyon1":
				row.append("5")
			"D1@Taslak1":
				row.append("60")
			_:
				row.append("")
	var fa := FileAccess.open(csv, FileAccess.WRITE)
	fa.store_string("\n".join(lines) + "\n" + ";".join(row) + "\n")
	fa.close()
	var r := Configs.read_csv(doc, csv)
	check(not r.has("error") and int(r["configs"]) == 3 and not Configs.find(doc, "Kısa").is_empty(), "CSV'den konfigürasyon eklendi")
	Configs.activate(doc, "Kısa")
	var c := s.sketch.get_constraint(int(s.sketch.constraints[s.sketch.constraints.size() - 1]["id"]))
	var pa: Vector2 = s.sketch.points[int(ent["a"])]
	var pb: Vector2 = s.sketch.points[int(ent["b"])]
	check(near(float(ex.params["depth"]), 5.0) and near(pa.distance_to(pb), 60.0, 1e-3), "Kısa: derinlik 5, taslak yeniden çözüldü (çizgi %.3f)" % pa.distance_to(pb))
	var d2 := CadDocument.new()
	d2.load_dict(doc.to_dict())
	check(d2.configs.size() == 3 and d2.active_config == "Kısa", "konfigürasyonlar belgeyle saklanır")
	check(not Configs.remove(doc, "Kısa") and Configs.remove(doc, "Uzun"), "etkin olan silinemez, diğeri silinir")


func run_cam() -> void:
	print("== CAM")
	var doc := new_doc()
	var s := sketch(doc, SketchPlane.standard("top"))
	rect(s.sketch, 0, 0, 40, 20)
	s.sketch.add_circle(s.sketch.add_point(Vector2(20, 10)), 5.0)
	var p := Cam.defaults()
	p["tool"] = 6.0
	var tp := Cam.toolpaths(s.sketch, p)
	check(not tp.has("error") and (tp["paths"] as Array).size() == 1, "dış kontur: tek yol")
	var a := absf(Drawing.polygon_area(tp["paths"][0]))
	var want := 40.0 * 20.0 + 2.0 * 3.0 * 60.0 + PI * 9.0
	check(near(a, want, 6.0), "dış kontur takım merkezi r=3 ofset (alan %.1f ≈ %.1f)" % [a, want])
	p["op"] = "inside"
	var ti := Cam.toolpaths(s.sketch, p)
	check(not ti.has("error") and near(absf(Drawing.polygon_area(ti["paths"][0])), PI * 4.0, 0.5), "iç kontur: Ø10 delikte r=3 → r=2 yol")
	p["op"] = "pocket"
	p["stepover"] = 50.0
	var tk := Cam.toolpaths(s.sketch, p)
	check(not tk.has("error") and (tk["paths"] as Array).size() >= 2, "cep: halkalar (%d yol, ada çevresinde)" % (tk["paths"] as Array).size())
	p["op"] = "outside"
	p["depth"] = 5.0
	p["step"] = 2.0
	var g := Cam.gcode(tp["paths"], p, "Test")
	var code: String = g["gcode"]
	check(int(g["passes"]) == 3 and code.begins_with("(DIY.CAD CAM") and code.contains("G21 G90") and code.strip_edges().ends_with("M30"), "G-kod: başlık, 3 paso (2+2+1), M30")
	check(code.contains("G1 Z-2.000") and code.contains("G1 Z-4.000") and code.contains("G1 Z-5.000"), "paso derinlikleri -2 / -4 / -5")
	check(near(float(g["length"]), 3.0 * _perim(tp["paths"][0]), 0.5), "kesme boyu = 3 × kontur çevresi (%.2f / %.2f)" % [float(g["length"]), 3.0 * _perim(tp["paths"][0])])


func _perim(pts: PackedVector2Array) -> float:
	var L := 0.0
	for i in pts.size():
		L += pts[i].distance_to(pts[(i + 1) % pts.size()])
	return L


func run_analysis() -> void:
	print("== Analiz yardımcıları")
	var bm := BoxMesh.new()
	bm.size = Vector3(10, 10, 10)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bm.get_mesh_arrays())
	var mm := ModelMesh.new()
	mm.build(am, {})
	var dr := Fea.draft_analysis(mm, Vector3.UP, 1.0)
	check(near(float(dr["pos"]), 1.0 / 6.0, 1e-3) and near(float(dr["neg"]), 1.0 / 6.0, 1e-3) and near(float(dr["need"]), 4.0 / 6.0, 1e-3),
		"küp, çekme +Y: üst pozitif, alt negatif, yanlar eğim gerektirir")
	check(not (dr["lines"] as Array).is_empty(), "ayırma çizgisi kenarları bulundu (%d)" % (dr["lines"] as Array).size())
	check(Fea.ramp(0.0).b > 0.8 and Fea.ramp(1.0).r > 0.8, "renk skalası mavi → kırmızı")
	# Sonuç ağı: 5×5×5 vokselli (h = 2) yapay sonuç; gerilme x ile doğrusal, yer değiştirme sıfır
	var vm := PackedFloat32Array()
	for i in 5:
		for j in 5:
			for k in 5:
				vm.append(float(i))
	var disp := PackedFloat32Array()
	disp.resize(6 * 6 * 6 * 3)
	var rr := {"dims": [5, 5, 5], "hv": Vector3(2, 2, 2), "ov": Vector3(-5, -5, -5), "vm_arr": vm, "disp_arr": disp, "vm_max": 4.0, "u_max": 0.0}
	var cm := Fea.colored_mesh(mm, rr, "vm", 0.0)
	check(int(cm["tris"]) > mm.tri_count() * 10 and near(float(cm["max"]), 4.0), "sonuç ağı eleman boyuna göre inceltildi (%d → %d üçgen)" % [mm.tri_count(), int(cm["tris"])])
	var cm2 := Fea.colored_mesh(mm, rr, "vm", 0.0, 200)
	check(int(cm2["tris"]) <= 400, "üçgen sınırı uygulanır (%d)" % int(cm2["tris"]))
	var fv := Fea.force_vector({"face": {"n": [0, 1, 0]}, "mag": 50.0, "dir": "normal"})
	check(near(fv[1], -50.0), "yüze dik yük yüzeye doğru bastırır")
	check(Fea.mech_of("Alüminyum 6061")[0] == 69.0 and Fea.mech_of("bilinmeyen")[0] == 205.0, "malzeme mekanik özellikleri (bilinmeyende çelik)")
	var doc := new_doc()
	var s := sketch(doc, SketchPlane.standard("front"))
	var c := s.sketch.add_line(s.sketch.add_point(Vector2(0, -10)), s.sketch.add_point(Vector2(0, 10)), true)
	s.sketch.add_line(s.sketch.add_point(Vector2(5, -5)), s.sketch.add_point(Vector2(10, 5)))
	var ax := Surfaces.revolve_axis(s)
	check((ax[1] as Vector3).is_equal_approx(Vector3.UP), "döndürülmüş yüzey ekseni: merkez çizgisi")
	var f := doc.new_feature("srf_trim", "Yüzey-Kırp")
	f.params = Surfaces.defaults("srf_trim")
	f.params["off"] = 5.0
	var d := {}
	check(Surfaces.payload(doc, f, d) and near(float(d["o"][1]), 5.0) and near(float(d["n"][1]), 1.0), "kırpma düzlemi: Üst düzlem + 5")
	var fe := doc.new_feature("srf_extrude", "Ekstrüde-Yüzey")
	fe.params = Surfaces.defaults("srf_extrude")
	fe.params["sketch"] = s.id
	fe.params["midplane"] = true
	var d2 := {}
	check(Surfaces.payload(doc, fe, d2) and near(float(d2["plane"]["o"][2]), -10.0) and near(float(d2["vec"][2]), 20.0), "ekstrüde yüzey orta düzlem")
