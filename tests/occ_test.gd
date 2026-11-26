extends SceneTree
## OpenCASCADE (B-rep) çekirdeği testleri: analitik hacimler, yuvarlatma/pah/kabuk,
## bölge seçimi, kenar başvurusu kararlılığı, STEP/IGES/STL, CSG ile karşılaştırma.
## Çalıştır: Godot --headless --path . --script res://tests/occ_test.gd -- --kernel=occ

var kernel: GeoKernel
var passed := 0
var failed := 0
var tmp_dir := ""


func _initialize() -> void:
	kernel = GeoKernel.new()
	root.add_child(kernel)
	tmp_dir = OS.get_user_data_dir().path_join("occ_test")
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	_run()


func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("  ok   ", msg)
	else:
		failed += 1
		print("  FAIL ", msg)


func near(a: float, b: float, rel := 1e-4) -> bool:
	return absf(a - b) <= rel * maxf(absf(b), 1.0)


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


func extrude(doc: CadDocument, sk_f: CadFeature, depth: float, cut := false, end := "blind") -> CadFeature:
	var e := doc.new_feature("extrude", "Ekstrüzyon")
	e.params = {"sketch": sk_f.id, "depth": depth, "end": end, "reverse": false, "cut": cut}
	doc.add_feature(e)
	return e


func rect(sk: Sketch, x0: float, y0: float, x1: float, y1: float) -> void:
	sk.add_rect([sk.add_point(Vector2(x0, y0)), sk.add_point(Vector2(x1, y0)),
		sk.add_point(Vector2(x1, y1)), sk.add_point(Vector2(x0, y1))])


func build(doc: CadDocument) -> ArrayMesh:
	kernel.rebuild(doc)
	var mesh = await kernel.built
	return mesh


func vol() -> float:
	var m = kernel.brep.get("mass", {})
	if not (m is Dictionary):
		return 0.0
	return float(m.get("volume", 0.0)) if not m.is_empty() else 0.0


## Kutu: Üst düzlemde 40 x 20 (X x Z), +Y yönünde 10 mm.
func box_doc(h := 10.0) -> Array:
	var doc := new_doc()
	var s := sketch(doc, SketchPlane.standard("top"))
	rect(s.sketch, -20, -10, 20, 10)
	var e := extrude(doc, s, h)
	return [doc, s, e]


func edges_where(cond: Callable) -> Array:
	var out: Array = []
	for e in kernel.brep.get("edges", []):
		if cond.call(e):
			out.append({"m": e["m"], "d": e["d"]})
	return out


func _run() -> void:
	await process_frame
	var t0 := Time.get_ticks_msec()
	while kernel.occ.state == "starting" or kernel.occ.state == "off":
		await process_frame
		if Time.get_ticks_msec() - t0 > 60000:
			break
	print("== OpenCASCADE sunucusu: ", kernel.occ.state, " ", kernel.occ.version, " (%d ms)" % (Time.get_ticks_msec() - t0))
	if not kernel.occ.is_ready():
		check(false, "OCC çekirdeği hazır değil: " + kernel.occ.fail_reason)
		_finish()
		return
	check(kernel.backend() == "occ", "etkin çekirdek OCC")

	print("== Kutu ve topoloji")
	var bx := box_doc()
	var doc: CadDocument = bx[0]
	await build(doc)
	check(near(vol(), 8000.0, 1e-9), "kutu hacmi 8000 (kesin) = %.6f" % vol())
	check((kernel.brep["faces"] as Array).size() == 6, "6 yüz (%d)" % (kernel.brep["faces"] as Array).size())
	check((kernel.brep["edges"] as Array).size() == 12, "12 kenar (%d)" % (kernel.brep["edges"] as Array).size())
	check(bool(kernel.brep.get("valid", false)), "B-rep geçerli")
	var mass: Dictionary = kernel.brep["mass"]
	check(near(float(mass["area"]), 2 * (40 * 20 + 40 * 10 + 20 * 10), 1e-9), "yüzey alanı 2800")
	var c := ModelMesh._v3(mass["center"])
	check(c.distance_to(Vector3(0, 5, 0)) < 1e-9, "ağırlık merkezi (0,5,0)")
	var ten: Array = mass["tensor"]
	check(near(float(ten[0][0]), 8000.0 * (10 * 10 + 20 * 20) / 12.0, 1e-9), "Ixx = V(b²+c²)/12")
	var planes := 0
	for f in kernel.brep["faces"]:
		if f["type"] == "plane":
			planes += 1
	check(planes == 6, "tüm yüzler düzlem")

	print("== Köşe yuvarlatma (4 dikey kenar, R3)")
	var vert := edges_where(func(e): return absf(float(e["d"][1])) > 0.99)
	check(vert.size() == 4, "4 dikey kenar bulundu")
	var fil := doc.new_feature("fillet", "Köşe Yuvarlatma")
	fil.params = {"r": 3.0, "edges": vert}
	doc.add_feature(fil)
	await build(doc)
	var exp_f := 8000.0 - 4.0 * (9.0 - PI * 9.0 / 4.0) * 10.0
	check(fil.error == "", "yuvarlatma hatasız (%s)" % fil.error)
	check(near(vol(), exp_f, 1e-6), "yuvarlatılmış hacim %.4f ≈ %.4f" % [vol(), exp_f])
	var cyl := 0
	for f in kernel.brep["faces"]:
		if f["type"] == "cylinder":
			cyl += 1
			check(near(float(f["r"]), 3.0, 1e-9), "silindir yüz yarıçapı 3")
	check(cyl == 4, "4 silindirik yüz (%d)" % cyl)

	print("== Kenar başvurusu kararlılığı (yükseklik 10 → 15)")
	var ext: CadFeature = bx[2]
	ext.params["depth"] = 15.0
	await build(doc)
	var exp_f2 := 40.0 * 20.0 * 15.0 - 4.0 * (9.0 - PI * 9.0 / 4.0) * 15.0
	check(fil.error == "", "yuvarlatma hâlâ hatasız (%s)" % fil.error)
	check(near(vol(), exp_f2, 1e-6), "yeni yükseklikte hacim %.4f ≈ %.4f" % [vol(), exp_f2])
	check(absf(float(fil.params["edges"][0]["m"][1]) - 7.5) < 1e-6, "kenar imzası güncellendi (orta y = 7.5)")

	print("== Aşırı yarıçap hatası")
	fil.params["r"] = 50.0
	await build(doc)
	check(fil.error != "", "R50 hata verdi: " + fil.error)
	check(near(vol(), 40.0 * 20.0 * 15.0, 1e-9), "hatalı özellik atlandı, önceki gövde korundu")
	doc.remove_feature(fil.id)

	print("== Pah (üst ön kenar, 2 mm)")
	ext.params["depth"] = 10.0
	await build(doc)
	var top_x := edges_where(func(e): return absf(float(e["d"][0])) > 0.99 and absf(float(e["m"][1]) - 10.0) < 1e-6 and float(e["m"][2]) > 9.0)
	check(top_x.size() == 1, "üst ön kenar bulundu")
	var ch := doc.new_feature("chamfer", "Pah")
	ch.params = {"d": 2.0, "edges": top_x}
	doc.add_feature(ch)
	await build(doc)
	check(ch.error == "", "pah hatasız (%s)" % ch.error)
	check(near(vol(), 8000.0 - 0.5 * 4.0 * 40.0, 1e-6), "pahlı hacim %.4f ≈ 7920" % vol())
	doc.remove_feature(ch.id)

	print("== Kabuk (üst yüz açık, 1 mm)")
	var sh := doc.new_feature("shell", "Kabuk")
	sh.params = {"t": 1.0, "faces": [{"p": [0.0, 10.0, 0.0], "n": [0.0, 1.0, 0.0]}], "outward": false}
	doc.add_feature(sh)
	await build(doc)
	check(sh.error == "", "kabuk hatasız (%s)" % sh.error)
	check(near(vol(), 8000.0 - 38.0 * 18.0 * 9.0, 1e-6), "kabuk hacmi %.4f ≈ 1844" % vol())
	sh.params["faces"] = []
	await build(doc)
	check(sh.error == "", "kapalı kabuk hatasız (%s)" % sh.error)
	check(near(vol(), 8000.0 - 38.0 * 18.0 * 8.0, 1e-6), "içi boş kapalı gövde %.4f ≈ 2528" % vol())
	doc.remove_feature(sh.id)

	print("== Delikli profil ve kesme")
	var doc2 := new_doc()
	var s2 := sketch(doc2, SketchPlane.standard("top"))
	rect(s2.sketch, -20, -10, 20, 10)
	s2.sketch.add_circle(s2.sketch.add_point(Vector2(0, 0)), 5.0)
	extrude(doc2, s2, 10.0)
	await build(doc2)
	check(near(vol(), (800.0 - PI * 25.0) * 10.0, 1e-7), "delikli plaka hacmi kesin (%.4f)" % vol())
	var s3 := sketch(doc2, SketchPlane.from_face(Vector3(0, 10, 0), Vector3.UP))
	s3.sketch.add_circle(s3.sketch.add_point(Vector2(12, 0)), 3.0)
	extrude(doc2, s3, 0.0, true, "through")
	await build(doc2)
	check(near(vol(), (800.0 - PI * 25.0 - PI * 9.0) * 10.0, 1e-7), "tümünden kesme hacmi kesin (%.4f)" % vol())

	print("== Döndürme")
	var doc3 := new_doc()
	var s4 := sketch(doc3, SketchPlane.standard("front"))
	rect(s4.sketch, 10, 0, 20, 10)
	var rv := doc3.new_feature("revolve", "Döndürme")
	rv.params = {"sketch": s4.id, "angle": 360.0, "axis": "y", "reverse": false, "cut": false}
	doc3.add_feature(rv)
	await build(doc3)
	check(near(vol(), PI * (400.0 - 100.0) * 10.0, 1e-7), "360° döndürme hacmi kesin (%.4f)" % vol())
	rv.params["angle"] = 90.0
	var m_occ: ArrayMesh = await build(doc3)
	check(near(vol(), PI * 300.0 * 10.0 / 4.0, 1e-7), "90° döndürme hacmi kesin")
	var a_occ := m_occ.get_aabb()
	kernel.csg.rebuild(doc3)
	var m_csg: ArrayMesh = await kernel.csg.built
	var a_csg := m_csg.get_aabb()
	var dc := (a_occ.get_center() - a_csg.get_center()).length()
	check(dc < 0.5, "OCC ve CSG 90° döndürme aynı yönde (merkez farkı %.3f; OCC %s, CSG %s)" % [dc, a_occ.get_center(), a_csg.get_center()])

	print("== Elips, parabol, spline")
	var doc4 := new_doc()
	var s5 := sketch(doc4, SketchPlane.standard("top"))
	var ec := s5.sketch.add_point(Vector2(0, 0))
	s5.sketch.add_ellipse(ec, s5.sketch.add_point(Vector2(20, 0)), 10.0)
	extrude(doc4, s5, 5.0)
	await build(doc4)
	check(near(vol(), PI * 20.0 * 10.0 * 5.0, 1e-7), "elips hacmi kesin (%.4f)" % vol())
	var doc5 := new_doc()
	var s6 := sketch(doc5, SketchPlane.standard("top"))
	var k6 := s6.sketch
	var pa := k6.add_point(Vector2(-10, 5))
	var pb := k6.add_point(Vector2(10, 5))
	k6.add_parabola(k6.add_point(Vector2(0, 0)), k6.add_point(Vector2(0, 5)), pa, pb)
	k6.add_line(pa, pb)
	extrude(doc5, s6, 3.0)
	await build(doc5)
	check(near(vol(), (2.0 / 3.0) * 20.0 * 5.0 * 3.0, 1e-7), "kapalı parabol hacmi kesin (%.4f)" % vol())
	var doc6 := new_doc()
	var s7 := sketch(doc6, SketchPlane.standard("top"))
	var k7 := s7.sketch
	var sp0 := k7.add_point(Vector2(-10, 0))
	var sp1 := k7.add_point(Vector2(10, 0))
	k7.add_spline([sp0, k7.add_point(Vector2(-5, 6)), k7.add_point(Vector2(5, 8)), sp1])
	k7.add_line(sp1, sp0)
	extrude(doc6, s7, 2.0)
	await build(doc6)
	var poly_area := 0.0
	for L in k7.extract_profiles()["loops"]:
		poly_area += Sketch.polygon_area(L["poly"])
	check(vol() > 0.0 and near(vol(), poly_area * 2.0, 0.01), "spline profili hacmi ≈ çokgen yaklaşımı (%.3f / %.3f)" % [vol(), poly_area * 2.0])

	print("== Bölge seçimi (kesişen iki daire, mercek)")
	var doc7 := new_doc()
	var s8 := sketch(doc7, SketchPlane.standard("top"))
	s8.sketch.add_circle(s8.sketch.add_point(Vector2(-5, 0)), 10.0)
	s8.sketch.add_circle(s8.sketch.add_point(Vector2(5, 0)), 10.0)
	var e8 := extrude(doc7, s8, 2.0)
	e8.params["regions"] = [[0.0, 0.0]]
	await build(doc7)
	var lens := 2.0 * 100.0 * acos(0.5) - 5.0 * sqrt(300.0)
	check(e8.error == "", "bölge ekstrüzyonu hatasız (%s)" % e8.error)
	check(near(vol(), lens * 2.0, 1e-7), "mercek bölgesi hacmi kesin (%.4f ≈ %.4f)" % [vol(), lens * 2.0])
	e8.params["regions"] = [[-12.0, 0.0], [12.0, 0.0]]
	await build(doc7)
	var one := PI * 100.0 - lens
	check(near(vol(), one * 2.0 * 2.0, 1e-7), "iki hilal bölgesi hacmi kesin")

	print("== Örnek parçalar: OCC ve CSG karşılaştırması")
	for demo in ["bracket", "nameplate"]:
		var dd := new_doc()
		if demo == "bracket":
			DemoParts.build_bracket(dd)
		else:
			DemoParts.build_nameplate(dd)
		Equations.apply(dd)
		await build(dd)
		var v_occ := vol()
		var errs := []
		for f in dd.features:
			if f.error != "":
				errs.append(f.name + ": " + f.error)
		check(errs.is_empty(), "%s: özellik hatası yok %s" % [demo, str(errs)])
		check(bool(kernel.brep.get("valid", false)), "%s: B-rep geçerli" % demo)
		kernel.csg.rebuild(dd)
		var mc: ArrayMesh = await kernel.csg.built
		var mm := ModelMesh.new()
		mm.build(mc)
		var v_csg := mm.volume_and_area().x
		check(v_occ > 0.0 and absf(v_occ - v_csg) / v_occ < 0.004, "%s: OCC %.2f ≈ CSG %.2f mm³" % [demo, v_occ, v_csg])
		if demo == "bracket":
			var mp_mesh := mm.mass_properties(1000.0)
			var t_occ: Array = kernel.brep["mass"]["tensor"]
			var t_mesh: Array = mp_mesh["tensor"]
			var ok_t := true
			for i in 3:
				for j in 3:
					var a := float(t_occ[i][j])
					var b := float(t_mesh[i][j])
					if absf(a - b) > 0.01 * maxf(absf(float(t_occ[i][i])), 1.0):
						ok_t = false
			check(ok_t, "bracket: atalet tensörü (işaretler dahil) ağ yöntemiyle uyumlu")

	print("== STEP / IGES / STL dışa aktarma ve STEP içe aktarma")
	var bx2 := box_doc()
	await build(bx2[0])
	var step_path := tmp_dir.path_join("kutu.step")
	var igs_path := tmp_dir.path_join("kutu.igs")
	var stl_path := tmp_dir.path_join("kutu.stl")
	for pr in [["step", step_path], ["iges", igs_path]]:
		kernel.request_export(pr[0], pr[1])
		var r: Dictionary = await kernel.export_done
		check(bool(r.get("ok", false)) and FileAccess.file_exists(pr[1]), "%s yazıldı (%d bayt)" % [pr[0], int(r.get("bytes", 0))])
	kernel.request_export("stl", stl_path, {"lin": 0.01, "ang_deg": 5.0})
	var rs: Dictionary = await kernel.export_done
	check(bool(rs.get("ok", false)) and int(rs.get("bytes", 0)) > 84, "STL yazıldı (%d bayt)" % int(rs.get("bytes", 0)))
	var doc8 := new_doc()
	var imp := doc8.new_feature("import", "İçe Aktarılan")
	imp.params = {"path": step_path, "scale": 1.0}
	doc8.add_feature(imp)
	await build(doc8)
	check(imp.error == "" and near(vol(), 8000.0, 1e-6), "STEP içe aktarıldı, hacim korundu (%.4f) %s" % [vol(), imp.error])
	var s9 := sketch(doc8, SketchPlane.from_face(Vector3(0, 10, 0), Vector3.UP))
	s9.sketch.add_circle(s9.sketch.add_point(Vector2(0, 0)), 4.0)
	extrude(doc8, s9, 3.0, true)
	await build(doc8)
	check(near(vol(), 8000.0 - PI * 16.0 * 3.0, 1e-7), "içe aktarılan gövdeye kesme uygulandı (%.4f)" % vol())
	var doc9 := new_doc()
	var imp2 := doc9.new_feature("import", "İçe Aktarılan")
	imp2.params = {"path": igs_path, "scale": 2.0}
	doc9.add_feature(imp2)
	await build(doc9)
	check(imp2.error == "" and near(vol(), 8000.0 * 8.0, 1e-4), "IGES içe aktarma + ölçek 2 (hacim x8: %.2f) %s" % [vol(), imp2.error])

	print("== CSG çekirdeğinde B-rep özelliği")
	var bx3 := box_doc()
	var d3: CadDocument = bx3[0]
	var fl3 := d3.new_feature("fillet", "Köşe Yuvarlatma")
	fl3.params = {"r": 1.0, "edges": []}
	d3.add_feature(fl3)
	kernel.csg.rebuild(d3)
	await kernel.csg.built
	check(fl3.error.contains("OpenCASCADE"), "CSG'de yuvarlatma anlaşılır hata verir")
	await run_4b()
	await run_5()
	await run_5b()
	await run_6()
	await run_8()
	await run_8b()
	await run_stl()
	_finish()


func edge_ref(e: Dictionary) -> Dictionary:
	return {"m": e["m"], "d": e["d"], "fn": e.get("fn", [])}


func find_edges(cond: Callable) -> Array:
	var out: Array = []
	for e in kernel.brep.get("edges", []):
		if cond.call(e):
			out.append(edge_ref(e))
	return out


func face_named(prefix: String) -> Array:
	var out: Array = []
	for f in kernel.brep.get("faces", []):
		if str(f.get("name", "")).begins_with(prefix):
			out.append(f)
	return out


func run_4b() -> void:
	print("== Değişken yarıçaplı yuvarlatma (R2 → R4)")
	var bx := box_doc()
	var doc: CadDocument = bx[0]
	await build(doc)
	var one := find_edges(func(e): return absf(float(e["d"][1])) > 0.99 and float(e["m"][0]) > 19.0 and float(e["m"][2]) > 9.0)
	check(one.size() == 1, "ön sağ dikey kenar bulundu")
	check((one[0]["fn"] as Array).size() == 2, "kenar komşu yüz adlarını taşıyor %s" % str(one[0]["fn"]))
	var vf := doc.new_feature("fillet", "Köşe Yuvarlatma")
	vf.params = {"r": 2.0, "r2": 4.0, "variable": true, "edges": one}
	doc.add_feature(vf)
	await build(doc)
	var exp_v := 8000.0 - (1.0 - PI / 4.0) * (64.0 - 8.0) / 0.6
	check(vf.error == "", "değişken yuvarlatma hatasız (%s)" % vf.error)
	check(near(vol(), exp_v, 2e-4), "değişken yarıçap hacmi %.4f ≈ %.4f" % [vol(), exp_v])
	doc.remove_feature(vf.id)

	print("== Pah çeşitleri (iki mesafe, açı-mesafe)")
	await build(doc)
	var top_x := find_edges(func(e): return absf(float(e["d"][0])) > 0.99 and absf(float(e["m"][1]) - 10.0) < 1e-6 and float(e["m"][2]) > 9.0)
	var c2 := doc.new_feature("chamfer", "Pah")
	c2.params = {"d": 2.0, "d2": 3.0, "mode": "dist2", "edges": top_x}
	doc.add_feature(c2)
	await build(doc)
	check(c2.error == "" and near(vol(), 8000.0 - 0.5 * 2.0 * 3.0 * 40.0, 1e-6), "iki mesafeli pah hacmi %.4f ≈ 7880 %s" % [vol(), c2.error])
	c2.params["mode"] = "angle"
	c2.params["angle"] = 30.0
	await build(doc)
	var ea := 8000.0 - 0.5 * 2.0 * 2.0 * tan(deg_to_rad(30.0)) * 40.0
	var eb := 8000.0 - 0.5 * 2.0 * 2.0 / tan(deg_to_rad(30.0)) * 40.0
	check(c2.error == "" and (near(vol(), ea, 1e-6) or near(vol(), eb, 1e-6)), "açı-mesafe pah hacmi %.4f (%.4f / %.4f)" % [vol(), ea, eb])
	doc.remove_feature(c2.id)

	print("== Eğim (4 yan yüz, tarafsız alt yüz, 5°)")
	var draft := doc.new_feature("draft", "Eğim")
	var sides: Array = []
	for p in [[20.0, 5.0, 0.0, 1.0, 0.0, 0.0], [-20.0, 5.0, 0.0, -1.0, 0.0, 0.0], [0.0, 5.0, 10.0, 0.0, 0.0, 1.0], [0.0, 5.0, -10.0, 0.0, 0.0, -1.0]]:
		sides.append({"p": [p[0], p[1], p[2]], "n": [p[3], p[4], p[5]], "name": ""})
	draft.params = {"angle": 5.0, "faces": sides, "neutral": {"p": [0.0, 0.0, 0.0], "n": [0.0, -1.0, 0.0], "name": ""}, "reverse": false}
	doc.add_feature(draft)
	await build(doc)
	var k := 10.0 * tan(deg_to_rad(5.0))
	var v_in := 10.0 / 6.0 * (800.0 + 4.0 * (40.0 - k) * (20.0 - k) + (40.0 - 2.0 * k) * (20.0 - 2.0 * k))
	var v_out := 10.0 / 6.0 * (800.0 + 4.0 * (40.0 + k) * (20.0 + k) + (40.0 + 2.0 * k) * (20.0 + 2.0 * k))
	check(draft.error == "", "eğim hatasız (%s)" % draft.error)
	check(near(vol(), v_in, 1e-5), "eğim içe doğru: hacim %.4f ≈ %.4f (dışa: %.4f)" % [vol(), v_in, v_out])
	draft.params["reverse"] = true
	await build(doc)
	check(near(vol(), v_out, 1e-5), "ters yön dışa doğru: hacim %.4f ≈ %.4f" % [vol(), v_out])
	doc.remove_feature(draft.id)

	print("== Kaburga (L köşebent, çapraz çizgi, 4 mm)")
	var dl := new_doc()
	var sl := sketch(dl, SketchPlane.standard("front"))
	var kl := sl.sketch
	var lp := [Vector2(0, 0), Vector2(60, 0), Vector2(60, 5), Vector2(5, 5), Vector2(5, 60), Vector2(0, 60)]
	var pids: Array = []
	for q in lp:
		pids.append(kl.add_point(q))
	for i in pids.size():
		kl.add_line(pids[i], pids[(i + 1) % pids.size()])
	extrude(dl, sl, 40.0, false, "midplane")
	await build(dl)
	var v_l := vol()
	check(near(v_l, (60.0 * 5.0 + 55.0 * 5.0) * 40.0, 1e-9), "L köşebent hacmi %.1f" % v_l)
	var sr := sketch(dl, SketchPlane.standard("front"))
	sr.sketch.add_line(sr.sketch.add_point(Vector2(5, 45)), sr.sketch.add_point(Vector2(45, 5)))
	var rib := dl.new_feature("rib", "Kaburga")
	rib.params = {"sketch": sr.id, "t": 4.0}
	dl.add_feature(rib)
	await build(dl)
	check(rib.error == "", "kaburga hatasız (%s)" % rib.error)
	check(near(vol() - v_l, 0.5 * 40.0 * 40.0 * 4.0, 1e-4), "kaburga hacmi %.3f ≈ 3200" % (vol() - v_l))

	print("== Çoklu gövde: ayrı gövde, birleştir, taşı/kopyala, böl")
	var dm := new_doc()
	var s1 := sketch(dm, SketchPlane.standard("top"))
	rect(s1.sketch, -20, -10, 20, 10)
	extrude(dm, s1, 10.0)
	var s2 := sketch(dm, SketchPlane.standard("top"))
	s2.sketch.add_circle(s2.sketch.add_point(Vector2(20, 0)), 5.0)
	var e2 := extrude(dm, s2, 20.0)
	e2.params["merge"] = false
	await build(dm)
	var vb := 8000.0
	var vc := PI * 25.0 * 20.0
	check(int(kernel.brep["mass"]["solids"]) == 2, "birleştirme kapalı: 2 gövde (%d)" % int(kernel.brep["mass"]["solids"]))
	check(near(vol(), vb + vc, 1e-7), "örtüşen ayrı gövdelerin hacim toplamı %.3f" % vol())
	var bodies := {}
	for f in kernel.brep["faces"]:
		bodies[int(f["body"])] = true
	check(bodies.size() == 2, "yüzler gövde numarası taşıyor")
	var cb := dm.new_feature("combine", "Birleştir")
	cb.params = {"op": "add", "bodies": [{"p": [0.0, 10.0, 0.0], "name": ""}, {"p": [20.0, 20.0, 0.0], "name": ""}]}
	dm.add_feature(cb)
	await build(dm)
	var overlap := PI * 25.0 / 2.0 * 10.0
	check(cb.error == "" and int(kernel.brep["mass"]["solids"]) == 1, "birleştir (ekle): tek gövde %s" % cb.error)
	check(near(vol(), vb + vc - overlap, 1e-7), "ekle hacmi %.3f" % vol())
	check(str((cb.params["bodies"][0] as Dictionary).get("name", "")) != "", "gövde başvurusu yüz adıyla güncellendi")
	cb.params["op"] = "subtract"
	await build(dm)
	check(near(vol(), vb - overlap, 1e-7), "çıkar hacmi %.3f ≈ %.3f" % [vol(), vb - overlap])
	cb.params["op"] = "common"
	await build(dm)
	check(near(vol(), overlap, 1e-7), "kesiştir hacmi %.3f ≈ %.3f" % [vol(), overlap])
	cb.params["op"] = "add"
	var mv := dm.new_feature("move_body", "Gövde Taşı/Kopyala")
	mv.params = {"body": {"p": [0.0, 10.0, 0.0], "name": ""}, "t": [0.0, 0.0, 50.0], "axis": "y", "angle": 0.0, "copy": true}
	dm.add_feature(mv)
	await build(dm)
	var vadd := vb + vc - overlap
	check(mv.error == "" and int(kernel.brep["mass"]["solids"]) == 2 and near(vol(), 2.0 * vadd, 1e-7), "kopyala: 2 gövde, hacim iki katı %s" % mv.error)
	mv.params["copy"] = false
	mv.params["angle"] = 90.0
	await build(dm)
	check(int(kernel.brep["mass"]["solids"]) == 1 and near(vol(), vadd, 1e-7), "taşı + döndür: tek gövde, hacim korunur")
	var c3 := ModelMesh._v3(kernel.brep["mass"]["center"])
	check(c3.z > 40.0, "gövde +Z yönünde taşındı (ağırlık merkezi z=%.2f)" % c3.z)
	dm.remove_feature(mv.id)
	var spf := dm.new_feature("split", "Böl")
	spf.params = {"plane": "right", "offset": 0.0, "keep": "both"}
	dm.add_feature(spf)
	await build(dm)
	check(spf.error == "" and int(kernel.brep["mass"]["solids"]) == 2 and near(vol(), vadd, 1e-7), "sağ düzlemle böl: 2 gövde, hacim korunur %s" % spf.error)
	spf.params["keep"] = "neg"
	await build(dm)
	check(int(kernel.brep["mass"]["solids"]) == 1 and near(vol(), 4000.0, 1e-7), "yalnızca -X tarafı kaldı (hacim %.3f ≈ 4000)" % vol())

	print("== Topolojik adlandırma: büyük değişiklikte kenar ve yüzey taslağı")
	var dn := new_doc()
	var sn := sketch(dn, SketchPlane.standard("top"))
	rect(sn.sketch, 0, 0, 40, 20)
	var en := extrude(dn, sn, 10.0)
	await build(dn)
	var caps := face_named("F%d:b:" % en.id)
	check(caps.size() == 1, "üst kapak yüzü adlandırıldı %s" % (str(caps[0]["name"]) if caps.size() == 1 else ""))
	# Ön (z = 0, taslakta y = 0) üst kenar
	var fe := find_edges(func(e): return absf(float(e["d"][0])) > 0.99 and absf(float(e["m"][1]) - 10.0) < 1e-6 and absf(float(e["m"][2])) < 1e-6)
	check(fe.size() == 1, "ön üst kenar bulundu")
	var nf := dn.new_feature("fillet", "Köşe Yuvarlatma")
	nf.params = {"r": 2.0, "edges": fe}
	dn.add_feature(nf)
	var sup := sketch(dn, SketchPlane.from_face(Vector3(20, 10, -10), Vector3.UP))
	sup.plane.support = {"name": str(caps[0]["name"]) if caps.size() == 1 else "", "p": [20.0, 10.0, -10.0], "n": [0.0, 1.0, 0.0]}
	var cc := sup.plane.to_local(Vector3(20, 10, -12))
	sup.sketch.add_circle(sup.sketch.add_point(cc), 3.0)
	extrude(dn, sup, 5.0)
	await build(dn)
	var base_v := 40.0 * 20.0 * 10.0 - (4.0 - PI) * 40.0 + PI * 9.0 * 5.0
	check(near(vol(), base_v, 1e-6), "başlangıç hacmi %.3f ≈ %.3f" % [vol(), base_v])
	# Dikdörtgeni 40x20 → 100x30 büyüt, yüksekliği 10 → 25 yap
	var pts := sn.sketch.points
	for pid in pts.keys():
		if pid == Sketch.ORIGIN:
			continue
		var q: Vector2 = pts[pid]
		pts[pid] = Vector2(100.0 if q.x > 1.0 else 0.0, 30.0 if q.y > 1.0 else 0.0)
	en.params["depth"] = 25.0
	await build(dn)
	check(nf.error == "", "yuvarlatma büyük değişiklikten sonra hatasız (%s)" % nf.error)
	var cyl_ok := false
	for f in kernel.brep["faces"]:
		if f["type"] == "cylinder" and absf(float(f.get("r", 0.0)) - 2.0) < 1e-6:
			var o := ModelMesh._v3(f["o"])
			var ax := ModelMesh._v3(f["axis"])
			cyl_ok = absf(ax.x) > 0.99 and absf(o.y - 23.0) < 1e-6 and absf(o.z + 2.0) < 1e-6
	check(cyl_ok, "yuvarlatma hâlâ ön üst kenarda (ad ile bulundu)")
	check(absf(sup.plane.origin.y - 25.0) < 1e-6, "yüzey taslağının düzlemi yeni üst yüze kaydı (y=%.3f)" % sup.plane.origin.y)
	var exp_n := 100.0 * 30.0 * 25.0 - (4.0 - PI) * 100.0 + PI * 9.0 * 5.0
	check(near(vol(), exp_n, 1e-6), "çıkıntı yeni üst yüzde: hacim %.3f ≈ %.3f" % [vol(), exp_n])


func refplane(doc: CadDocument, params: Dictionary) -> CadFeature:
	var f := doc.new_feature("refplane", "Düzlem")
	f.params = params
	doc.add_feature(f)
	RefGeom.update(doc)
	return f


func sketch_on_ref(doc: CadDocument, rf: CadFeature) -> CadFeature:
	var s := sketch(doc, rf.plane.clone())
	s.plane.ref = rf.id
	return s


func bodies_n() -> int:
	return int(kernel.brep.get("mass", {}).get("solids", 0)) if kernel.brep.get("mass") is Dictionary else 0


func center() -> Vector3:
	return ModelMesh._v3(kernel.brep["mass"]["center"])


func run_5() -> void:
	print("== Faz 5: referans geometri")
	var d1 := new_doc()
	var rp := refplane(d1, {"mode": "offset", "base": "top", "dist": 20.0})
	check(rp.plane != null and absf(rp.plane.origin.y - 20.0) < 1e-9, "ofset düzlem y=20")
	var s1 := sketch_on_ref(d1, rp)
	rect(s1.sketch, -5, -5, 5, 5)
	extrude(d1, s1, 5.0)
	await build(d1)
	check(near(vol(), 500.0, 1e-9) and absf(center().y - 22.5) < 1e-9, "referans düzlemdeki taslak: hacim 500, merkez y=22.5")
	rp.params["dist"] = 30.0
	RefGeom.update(d1)
	await build(d1)
	check(absf(s1.plane.origin.y - 30.0) < 1e-9 and absf(center().y - 32.5) < 1e-9, "düzlem 30'a taşınınca taslak da taşındı")
	var ra := refplane(d1, {"mode": "angle", "base": "front", "axis": "x", "angle": 90.0})
	check(absf(absf(ra.plane.normal().y) - 1.0) < 1e-9, "açılı düzlem (Ön, X etrafında 90°) yatay oldu (normal ±Y)")
	ra.params["angle"] = 45.0
	RefGeom.update(d1)
	check(absf(absf(ra.plane.normal().z) - sqrt(0.5)) < 1e-5 and absf(ra.plane.normal().x) < 1e-6, "45° açılı düzlem normali YZ düzleminde 45° %s" % ra.plane.normal())
	var r3 := refplane(d1, {"mode": "3pt", "points": [[0, 0, 0], [1, 0, 0], [0, 0, -1]]})
	check(r3.plane.normal().distance_to(Vector3.UP) < 1e-9, "3 noktalı düzlem normali +Y")
	var ax := d1.new_feature("refaxis", "Eksen")
	ax.params = {"mode": "planes", "plane1": "front", "plane2": "right"}
	d1.add_feature(ax)
	var axd := RefGeom.axis_of(d1, ax)
	check(not axd.is_empty() and absf(absf((axd["d"] as Vector3).y) - 1.0) < 1e-9 and (axd["o"] as Vector3).length() < 1e-9, "Ön ∩ Sağ düzlem = Y ekseni")
	var d2 := new_doc()
	var ax2 := d2.new_feature("refaxis", "Eksen")
	ax2.params = {"mode": "2pt", "p1": [30.0, 0.0, 0.0], "p2": [30.0, 10.0, 0.0]}
	d2.add_feature(ax2)
	var s2 := sketch(d2, SketchPlane.standard("front"))
	rect(s2.sketch, 40, 0, 50, 10)
	var rv := d2.new_feature("revolve", "Döndürme")
	rv.params = {"sketch": s2.id, "angle": 360.0, "axis": "ax:%d" % ax2.id, "reverse": false, "cut": false}
	d2.add_feature(rv)
	await build(d2)
	check(rv.error == "" and near(vol(), TAU * 15.0 * 100.0, 1e-7), "referans eksen etrafında döndürme hacmi %.3f %s" % [vol(), rv.error])

	print("== Faz 5: ekstrüzyon bitiş koşulları")
	var d3 := new_doc()
	var sa := sketch(d3, SketchPlane.standard("top"))
	rect(sa.sketch, -20, -10, 20, 10)
	extrude(d3, sa, 10.0)
	var rpl := refplane(d3, {"mode": "offset", "base": "top", "dist": 30.0})
	var sb := sketch_on_ref(d3, rpl)
	rect(sb.sketch, -30, -15, 30, 15)
	var eb := extrude(d3, sb, 5.0)
	eb.params["merge"] = false
	var sc := sketch(d3, SketchPlane.standard("top"))
	sc.sketch.add_circle(sc.sketch.add_point(Vector2(0, 0)), 3.0)
	var ec := extrude(d3, sc, 1.0)
	ec.params["end"] = "face"
	ec.params["face"] = {"p": [0.0, 30.0, 0.0], "n": [0.0, -1.0, 0.0], "name": ""}
	await build(d3)
	var va := 8000.0
	var vb := 60.0 * 30.0 * 5.0
	check(ec.error == "" and near(vol(), va + vb + PI * 9.0 * 20.0, 1e-7) and bodies_n() == 1, "Yüzeye Kadar: hacim %.3f, gövde %d %s" % [vol(), bodies_n(), ec.error])
	ec.params["end"] = "next"
	# Taslak kutunun alt yüzünde olsaydı ilk yüz kutunun kendi üst yüzü olurdu; üst yüzden başlat
	sc.plane = SketchPlane.from_face(Vector3(0, 10, 0), Vector3.UP)
	await build(d3)
	check(ec.error == "" and near(vol(), va + vb + PI * 9.0 * 20.0, 1e-7), "Sonrakine Kadar aynı sonuç (%.3f) %s" % [vol(), ec.error])
	ec.params["end"] = "face_offset"
	ec.params["face_off"] = 5.0
	await build(d3)
	check(ec.error == "" and near(vol(), va + vb + PI * 9.0 * 15.0, 1e-7) and bodies_n() == 2, "Yüzeyden Ofset 5: hacim %.3f, gövde %d %s" % [vol(), bodies_n(), ec.error])
	var d4 := new_doc()
	var s4 := sketch(d4, SketchPlane.standard("top"))
	rect(s4.sketch, -5, -5, 5, 5)
	var e4 := extrude(d4, s4, 10.0)
	e4.params["dir2"] = true
	e4.params["depth2"] = 4.0
	var m4: ArrayMesh = await build(d4)
	check(near(vol(), 1400.0, 1e-9) and absf(m4.get_aabb().position.y + 4.0) < 1e-3, "İki yön: 10 + 4 (hacim %.1f)" % vol())
	e4.params["dir2"] = false
	e4.params["end"] = "vertex"
	e4.params["vertex"] = [3.0, 7.0, 2.0]
	await build(d4)
	check(e4.error == "" and near(vol(), 700.0, 1e-9), "Köşeye Kadar: derinlik 7 (hacim %.1f) %s" % [vol(), e4.error])
	e4.params["end"] = "blind"
	var d5 := new_doc()
	var s5 := sketch(d5, SketchPlane.standard("top"))
	rect(s5.sketch, -10, -5, 10, 5)
	var e5 := extrude(d5, s5, 10.0)
	e5.params["draft"] = 5.0
	await build(d5)
	var k := 10.0 * tan(deg_to_rad(5.0))
	var vdr := 10.0 / 6.0 * (200.0 + 4.0 * (20.0 - k) * (10.0 - k) + (20.0 - 2.0 * k) * (10.0 - 2.0 * k))
	check(e5.error == "" and near(vol(), vdr, 1e-6), "Eğimli ekstrüzyon 5° içe: %.4f ≈ %.4f %s" % [vol(), vdr, e5.error])
	e5.params["draft_out"] = true
	await build(d5)
	var vdo := 10.0 / 6.0 * (200.0 + 4.0 * (20.0 + k) * (10.0 + k) + (20.0 + 2.0 * k) * (10.0 + 2.0 * k))
	check(near(vol(), vdo, 1e-6), "Eğimli ekstrüzyon dışa: %.4f ≈ %.4f" % [vol(), vdo])
	var d6 := new_doc()
	var s6 := sketch(d6, SketchPlane.standard("top"))
	s6.sketch.add_line(s6.sketch.add_point(Vector2(-20, 0)), s6.sketch.add_point(Vector2(20, 0)))
	var e6 := extrude(d6, s6, 10.0)
	e6.params["thin"] = 2.0
	await build(d6)
	check(e6.error == "" and near(vol(), 800.0, 1e-7), "İnce özellik (açık çizgi, 2 mm): hacim %.3f %s" % [vol(), e6.error])
	var d7 := new_doc()
	var s7 := sketch(d7, SketchPlane.standard("top"))
	rect(s7.sketch, -10, -5, 10, 5)
	var e7 := extrude(d7, s7, 10.0)
	e7.params["thin"] = 1.0
	await build(d7)
	check(e7.error == "" and near(vol(), (21.0 * 11.0 - 19.0 * 9.0) * 10.0, 1e-7), "İnce özellik (kapalı dikdörtgen, 1 mm): hacim %.3f %s" % [vol(), e7.error])
	e7.params["thin_side"] = "a"
	await build(d7)
	check(near(vol(), (22.0 * 12.0 - 200.0) * 10.0, 1e-7), "İnce özellik dışa doğru: hacim %.3f" % vol())

	print("== Faz 5: süpürme ve helis")
	var d8 := new_doc()
	var sp := sketch(d8, SketchPlane.standard("front"))
	sp.sketch.add_circle(sp.sketch.add_point(Vector2(0, 0)), 2.0)
	var pth := sketch(d8, SketchPlane.standard("top"))
	var pk := pth.sketch
	var q0 := pk.add_point(Vector2(0, 0))
	var q1 := pk.add_point(Vector2(0, -30))
	var q2 := pk.add_point(Vector2(20, -50))
	var q3 := pk.add_point(Vector2(50, -50))
	pk.add_line(q0, q1)
	pk.add_arc(pk.add_point(Vector2(20, -30)), q1, q2)
	pk.add_line(q2, q3)
	var sw := d8.new_feature("sweep", "Süpürme")
	sw.params = {"sketch": sp.id, "path": {"kind": "sketch", "id": pth.id}, "cut": false}
	d8.add_feature(sw)
	await build(d8)
	var plen := 60.0 + 10.0 * PI
	check(sw.error == "" and near(vol(), PI * 4.0 * plen, 1e-5), "süpürme (çizgi + yay + çizgi): %.3f ≈ %.3f %s" % [vol(), PI * 4.0 * plen, sw.error])
	var d9 := new_doc()
	var hs := sketch(d9, SketchPlane.standard("top"))
	hs.sketch.add_circle(hs.sketch.add_point(Vector2(0, 0)), 10.0)
	var hx := d9.new_feature("helix", "Helis")
	hx.params = {"sketch": hs.id, "mode": "pitch_turns", "pitch": 5.0, "turns": 4.0}
	d9.add_feature(hx)
	var hp := sketch(d9, SketchPlane.standard("front"))
	hp.sketch.add_circle(hp.sketch.add_point(Vector2(10, 0)), 1.0)
	var spr := d9.new_feature("sweep", "Süpürme")
	spr.params = {"sketch": hp.id, "path": {"kind": "helix", "id": hx.id}, "cut": false}
	d9.add_feature(spr)
	await build(d9)
	var hl := 4.0 * sqrt(pow(TAU * 10.0, 2) + 25.0)
	check(spr.error == "" and near(vol(), PI * hl, 0.01), "yay (helis süpürme): %.2f ≈ %.2f %s" % [vol(), PI * hl, spr.error])
	check(RefGeom.helix_points(RefGeom.helix_spec(d9, hx)).size() > 100, "helis görüntü noktaları üretildi")
	var d10 := new_doc()
	var p10 := sketch(d10, SketchPlane.standard("front"))
	p10.sketch.add_circle(p10.sketch.add_point(Vector2(0, 0)), 2.0)
	var s3d := d10.new_feature("sketch3d", "3B Taslak")
	s3d.sketch3d = Sketch3D.new()
	s3d.sketch3d.add_line(s3d.sketch3d.add_point(Vector3(0, 0, 0)), s3d.sketch3d.add_point(Vector3(0, 0, 40)))
	d10.add_feature(s3d)
	var sw3 := d10.new_feature("sweep", "Süpürme")
	sw3.params = {"sketch": p10.id, "path": {"kind": "sketch3d", "id": s3d.id}, "cut": false}
	d10.add_feature(sw3)
	await build(d10)
	check(sw3.error == "" and near(vol(), PI * 4.0 * 40.0, 1e-7), "3B taslak yolunda süpürme: %.3f %s" % [vol(), sw3.error])

	print("== Faz 5: loft")
	var d11 := new_doc()
	var l1 := sketch(d11, SketchPlane.standard("top"))
	rect(l1.sketch, -10, -10, 10, 10)
	var lr := refplane(d11, {"mode": "offset", "base": "top", "dist": 10.0})
	var l2 := sketch_on_ref(d11, lr)
	rect(l2.sketch, -5, -5, 5, 5)
	var lf := d11.new_feature("loft", "Loft")
	lf.params = {"sketches": [l1.id, l2.id], "ruled": true, "cut": false}
	d11.add_feature(lf)
	await build(d11)
	check(lf.error == "" and near(vol(), 10.0 / 3.0 * (400.0 + 100.0 + 200.0), 1e-7), "kare → kare loft (kesik piramit): %.3f %s" % [vol(), lf.error])
	l1.sketch = Sketch.new()
	l1.sketch.add_circle(l1.sketch.add_point(Vector2.ZERO), 10.0)
	l2.sketch = Sketch.new()
	l2.sketch.add_circle(l2.sketch.add_point(Vector2.ZERO), 5.0)
	lf.params["ruled"] = false
	await build(d11)
	check(near(vol(), PI * 10.0 / 3.0 * (100.0 + 50.0 + 25.0), 1e-4), "daire → daire loft (kesik koni): %.3f" % vol())

	print("== Faz 5: çoğaltma ve aynalama")
	var d12 := new_doc()
	var b12 := sketch(d12, SketchPlane.standard("top"))
	rect(b12.sketch, -20, -20, 20, 20)
	extrude(d12, b12, 10.0)
	var h12 := sketch(d12, SketchPlane.from_face(Vector3(0, 10, 0), Vector3.UP))
	h12.sketch.add_circle(h12.sketch.add_point(h12.plane.to_local(Vector3(-15, 10, 0))), 2.0)
	var c12 := extrude(d12, h12, 0.0, true, "through")
	var lp := d12.new_feature("lpattern", "Doğrusal Çoğaltma")
	lp.params = {"features": [c12.id], "dir1": "x", "spacing1": 10.0, "count1": 4}
	d12.add_feature(lp)
	await build(d12)
	check(lp.error == "" and near(vol(), 16000.0 - 4.0 * PI * 4.0 * 10.0, 1e-7), "doğrusal çoğaltma: 4 delik (%.3f) %s" % [vol(), lp.error])
	lp.params["use2"] = true
	lp.params["dir2"] = "z"
	lp.params["spacing2"] = 10.0
	lp.params["count2"] = 2
	await build(d12)
	check(near(vol(), 16000.0 - 8.0 * PI * 4.0 * 10.0, 1e-7), "iki yönlü doğrusal çoğaltma: 8 delik (%.3f)" % vol())
	d12.remove_feature(lp.id)
	var cp := d12.new_feature("cpattern", "Dairesel Çoğaltma")
	h12.sketch = Sketch.new()
	h12.sketch.add_circle(h12.sketch.add_point(h12.plane.to_local(Vector3(10, 10, 0))), 2.0)
	cp.params = {"features": [c12.id], "axis": "y", "count": 6, "angle": 360.0, "equal": true}
	d12.add_feature(cp)
	await build(d12)
	check(cp.error == "" and near(vol(), 16000.0 - 6.0 * PI * 4.0 * 10.0, 1e-7), "dairesel çoğaltma: 6 delik (%.3f) %s" % [vol(), cp.error])
	cp.params["angle"] = 90.0
	cp.params["count"] = 3
	cp.params["equal"] = false
	await build(d12)
	check(near(vol(), 16000.0 - 3.0 * PI * 4.0 * 10.0, 1e-7), "90° içinde 3 örnek (%.3f)" % vol())
	d12.remove_feature(cp.id)
	var tp := d12.new_feature("tpattern", "Tablo")
	tp.params = {"features": [c12.id], "offsets": [[-20.0, 0.0, 5.0], [-20.0, 0.0, -5.0]]}
	d12.add_feature(tp)
	await build(d12)
	check(tp.error == "" and near(vol(), 16000.0 - 3.0 * PI * 4.0 * 10.0, 1e-7), "tablo güdümlü çoğaltma: 3 delik (%.3f) %s" % [vol(), tp.error])
	d12.remove_feature(tp.id)
	var m12 := sketch(d12, SketchPlane.from_face(Vector3(0, 10, 0), Vector3.UP))
	m12.sketch.add_circle(m12.sketch.add_point(m12.plane.to_local(Vector3(12, 10, 5))), 3.0)
	var boss := extrude(d12, m12, 5.0)
	var mi := d12.new_feature("mirror", "Aynala")
	mi.params = {"features": [boss.id], "plane": "right"}
	d12.add_feature(mi)
	await build(d12)
	var v12 := 16000.0 - PI * 4.0 * 10.0 + 2.0 * PI * 9.0 * 5.0
	check(mi.error == "" and near(vol(), v12, 1e-7), "özellik aynalama: iki çıkıntı (%.3f) %s" % [vol(), mi.error])
	var d13 := new_doc()
	var b13 := sketch(d13, SketchPlane.standard("top"))
	rect(b13.sketch, 0, -10, 20, 10)
	extrude(d13, b13, 10.0)
	var mb := d13.new_feature("mirror", "Aynala")
	mb.params = {"features": [], "bodies": true, "plane": "right"}
	d13.add_feature(mb)
	await build(d13)
	check(mb.error == "" and near(vol(), 8000.0, 1e-9) and bodies_n() == 1, "gövde aynalama: hacim iki katı, birleşik (%.1f, %d gövde)" % [vol(), bodies_n()])

	print("== Faz 5: delik sihirbazı")
	var d14 := new_doc()
	var b14 := sketch(d14, SketchPlane.standard("top"))
	rect(b14.sketch, -20, -10, 20, 10)
	extrude(d14, b14, 10.0)
	var hl14 := d14.new_feature("hole", "Delik")
	hl14.params = {"std": "ISO", "htype": "simple", "size": "M6", "fit": "normal", "end": "through",
		"face": {"p": [0.0, 10.0, 0.0], "n": [0.0, 1.0, 0.0], "name": ""}, "points": [[-10.0, 10.0, 0.0]]}
	d14.add_feature(hl14)
	await build(d14)
	var r6 := 3.3
	check(hl14.error == "" and near(vol(), 8000.0 - PI * r6 * r6 * 10.0, 1e-7), "M6 geçiş deliği (Ø6.6): %.3f %s" % [vol(), hl14.error])
	hl14.params["points"] = [[-10.0, 10.0, 0.0], [10.0, 12.0, 0.0]]
	await build(d14)
	check(near(vol(), 8000.0 - 2.0 * PI * r6 * r6 * 10.0, 1e-7), "iki konum (yüzeye izdüşürüldü): %.3f" % vol())
	hl14.params["points"] = [[-10.0, 10.0, 0.0]]
	hl14.params["htype"] = "cbore"
	await build(d14)
	check(near(vol(), 8000.0 - (PI * r6 * r6 * (10.0 - 6.4) + PI * 5.5 * 5.5 * 6.4), 1e-7), "M6 havşa başlı (Ø11 x 6.4): %.3f" % vol())
	hl14.params["htype"] = "csink"
	await build(d14)
	var hcs := (6.2 - r6)
	var frus := PI * hcs / 3.0 * (6.2 * 6.2 + 6.2 * r6 + r6 * r6) - PI * r6 * r6 * hcs
	check(near(vol(), 8000.0 - PI * r6 * r6 * 10.0 - frus, 1e-6), "M6 konik havşa 90° (Ø12.4): %.3f" % vol())
	hl14.params["htype"] = "tap"
	await build(d14)
	check(near(vol(), 8000.0 - PI * 2.5 * 2.5 * 10.0, 1e-7), "M6 kılavuz (matkap Ø5.0): %.3f" % vol())
	hl14.params["htype"] = "simple"
	hl14.params["end"] = "blind"
	hl14.params["depth"] = 6.0
	await build(d14)
	var tip := r6 / tan(deg_to_rad(59.0))
	check(near(vol(), 8000.0 - PI * r6 * r6 * 6.0 - PI * r6 * r6 * tip / 3.0, 1e-7), "kör delik 6 mm + 118° matkap ucu: %.3f" % vol())
	hl14.params["std"] = "ANSI"
	hl14.params["size"] = "1/4-20"
	hl14.params["end"] = "through"
	await build(d14)
	var ra14 := 0.2660 * 25.4 / 2.0
	check(near(vol(), 8000.0 - PI * ra14 * ra14 * 10.0, 1e-7), "ANSI 1/4 geçiş deliği: %.3f" % vol())

	print("== Faz 5: kubbe")
	var d15 := new_doc()
	var s15 := sketch(d15, SketchPlane.standard("top"))
	s15.sketch.add_circle(s15.sketch.add_point(Vector2.ZERO), 10.0)
	extrude(d15, s15, 10.0)
	var dm := d15.new_feature("dome", "Kubbe")
	dm.params = {"face": {"p": [0.0, 10.0, 0.0], "n": [0.0, 1.0, 0.0], "name": ""}, "height": 10.0}
	d15.add_feature(dm)
	await build(d15)
	var vdome := PI * 100.0 * 10.0 + 2.0 / 3.0 * PI * 1000.0
	check(dm.error == "" and near(vol(), vdome, 0.01), "yarım küre kubbe: %.2f ≈ %.2f %s" % [vol(), vdome, dm.error])

	print("== Faz 5: geri alma çubuğu, sıralama, ebeveyn/çocuk")
	var bx := box_doc()
	var dr: CadDocument = bx[0]
	await build(dr)
	var vert := edges_where(func(e): return absf(float(e["d"][1])) > 0.99)
	var fl := dr.new_feature("fillet", "Köşe Yuvarlatma")
	fl.params = {"r": 3.0, "edges": vert}
	dr.add_feature(fl)
	await build(dr)
	var vf := vol()
	dr.set_rollback(2)
	await build(dr)
	check(near(vol(), 8000.0, 1e-9) and dr.is_rolled_back(fl), "geri alma çubuğu yuvarlatmanın önünde: hacim 8000")
	var extra := dr.new_feature("refpoint", "Nokta")
	extra.params = {"p": [0.0, 0.0, 0.0]}
	dr.add_feature(extra)
	check(dr.index_of(extra.id) == 2 and dr.rollback == 3, "geri alınmışken eklenen özellik çubuğun önüne girdi")
	dr.set_rollback(-1)
	await build(dr)
	check(near(vol(), vf, 1e-9), "geri alma kaldırıldı: yuvarlatma geri geldi")
	var sid: int = (bx[1] as CadFeature).id
	var eid: int = (bx[2] as CadFeature).id
	check(eid in dr.parents_of(fl), "yuvarlatmanın ebeveyni ekstrüzyon (kenar adlarından)")
	check(sid in dr.parents_of(bx[2]) and eid in dr.children_of(sid), "taslak ↔ ekstrüzyon ebeveyn/çocuk")
	check(not dr.can_move(sid, dr.index_of(eid) + 1) and not dr.can_move(fl.id, 0), "ebeveyn/çocuk sırası bozulamaz")
	check(dr.move_feature(extra.id, 0) and dr.index_of(extra.id) == 0, "bağımsız özellik en başa taşındı")
	var d2b := CadDocument.new()
	d2b.load_dict(dr.to_dict())
	check(d2b.rollback == -1 and d2b.features.size() == dr.features.size(), "geri alma ve sıra kaydedilip yüklendi")


func sketch3d_line(doc: CadDocument, a: Vector3, b: Vector3) -> CadFeature:
	var s := doc.new_feature("sketch3d", "3B Taslak")
	s.sketch3d = Sketch3D.new()
	s.sketch3d.add_line(s.sketch3d.add_point(a), s.sketch3d.add_point(b))
	doc.add_feature(s)
	return s


func poly_len(pts: PackedVector3Array) -> float:
	var L := 0.0
	for i in pts.size() - 1:
		L += pts[i].distance_to(pts[i + 1])
	return L


func run_5b() -> void:
	print("== Faz 5b: teğet düzlem ve koordinat sistemi")
	var d0 := new_doc()
	var tp := refplane(d0, {"mode": "tangent", "tan_p": [20.0, 5.0, 0.0], "tan_n": [1.0, 0.0, 0.0]})
	check(tp.plane != null and tp.plane.normal().distance_to(Vector3.RIGHT) < 1e-6 and absf(tp.plane.origin.x - 20.0) < 1e-6, "yüzeye teğet düzlem (x=20, normal +X)")
	var cs := d0.new_feature("refcsys", "Koordinat Sistemi")
	cs.params = {"o": [1.0, 2.0, 3.0], "x": "z", "y": "x"}
	d0.add_feature(cs)
	var c3 := RefGeom.csys_of(d0, cs)
	check(not c3.is_empty() and (c3["z"] as Vector3).distance_to(Vector3.UP) < 1e-6 and (c3["o"] as Vector3).distance_to(Vector3(1, 2, 3)) < 1e-6, "koordinat sistemi (X=z, Y=x → Z=+Y)")

	print("== Faz 5b: kılavuzlu ve bükmeli süpürme, kılavuzlu loft")
	var d1 := new_doc()
	var p1 := sketch(d1, SketchPlane.standard("front"))
	p1.sketch.add_circle(p1.sketch.add_point(Vector2.ZERO), 5.0)
	var path1 := sketch3d_line(d1, Vector3.ZERO, Vector3(0, 0, 40))
	var gd1 := sketch3d_line(d1, Vector3(5, 0, 0), Vector3(10, 0, 40))
	var sw1 := d1.new_feature("sweep", "Süpürme")
	sw1.params = {"sketch": p1.id, "path": {"kind": "sketch3d", "id": path1.id}, "guide": {"kind": "sketch3d", "id": gd1.id}, "cut": false}
	d1.add_feature(sw1)
	await build(d1)
	var vcone := PI * 40.0 / 3.0 * (25.0 + 50.0 + 100.0)
	check(sw1.error == "" and near(vol(), vcone, 1e-4), "kılavuzlu süpürme = kesik koni (%.3f ≈ %.3f) %s" % [vol(), vcone, sw1.error])
	var d2 := new_doc()
	var p2 := sketch(d2, SketchPlane.standard("front"))
	rect(p2.sketch, -5, -5, 5, 5)
	var path2 := sketch3d_line(d2, Vector3.ZERO, Vector3(0, 0, 40))
	var sw2 := d2.new_feature("sweep", "Süpürme")
	sw2.params = {"sketch": p2.id, "path": {"kind": "sketch3d", "id": path2.id}, "twist": 90.0, "cut": false}
	d2.add_feature(sw2)
	await build(d2)
	check(sw2.error == "" and near(vol(), 4000.0, 0.005), "90° bükmeli süpürme: kesit alanı korunur (%.2f ≈ 4000) %s" % [vol(), sw2.error])
	check((kernel.brep["faces"] as Array).size() >= 6, "bükmeli yüzeyler oluştu")
	var d3 := new_doc()
	var l1 := sketch(d3, SketchPlane.standard("top"))
	rect(l1.sketch, -10, -10, 10, 10)
	var lr := refplane(d3, {"mode": "offset", "base": "top", "dist": 20.0})
	var l2 := sketch_on_ref(d3, lr)
	rect(l2.sketch, -10, -10, 10, 10)
	var gl := sketch3d_line(d3, Vector3(10, 0, 10), Vector3(10, 20, 10))
	var lf := d3.new_feature("loft", "Loft")
	lf.params = {"sketches": [l1.id, l2.id], "guide": {"kind": "sketch3d", "id": gl.id}, "cut": false}
	d3.add_feature(lf)
	await build(d3)
	check(lf.error == "" and near(vol(), 8000.0, 1e-6), "kılavuz eğrili loft (%.3f ≈ 8000) %s" % [vol(), lf.error])

	print("== Faz 5b: eğri güdümlü çoğaltma")
	var d4 := new_doc()
	var b4 := sketch(d4, SketchPlane.standard("top"))
	rect(b4.sketch, -30, -10, 30, 10)
	extrude(d4, b4, 10.0)
	var h4 := sketch(d4, SketchPlane.from_face(Vector3(0, 10, 0), Vector3.UP))
	h4.sketch.add_circle(h4.sketch.add_point(h4.plane.to_local(Vector3(-25, 10, 0))), 2.0)
	var c4 := extrude(d4, h4, 0.0, true, "through")
	var cv := sketch(d4, SketchPlane.from_face(Vector3(0, 10, 0), Vector3.UP))
	cv.sketch.add_line(cv.sketch.add_point(cv.plane.to_local(Vector3(-25, 10, 0))), cv.sketch.add_point(cv.plane.to_local(Vector3(25, 10, 0))))
	var cp := d4.new_feature("cvpattern", "Eğri")
	cp.params = {"features": [c4.id], "curve": {"kind": "sketch", "id": cv.id}, "count": 4, "equal": true, "align": true}
	d4.add_feature(cp)
	await build(d4)
	check(cp.error == "" and near(vol(), 12000.0 - 4.0 * PI * 4.0 * 10.0, 1e-7), "eğri boyunca 4 delik (%.3f) %s" % [vol(), cp.error])
	cp.params["equal"] = false
	cp.params["spacing"] = 20.0
	await build(d4)
	check(near(vol(), 12000.0 - 3.0 * PI * 4.0 * 10.0, 1e-7), "20 mm aralıkla: eğriye sığan 3 örnek (%.3f)" % vol())

	print("== Faz 5b: spiral ve konik helis")
	for kind in ["spiral", "taper"]:
		var d5 := new_doc()
		var hs := sketch(d5, SketchPlane.standard("top"))
		hs.sketch.add_circle(hs.sketch.add_point(Vector2.ZERO), 5.0)
		var hx := d5.new_feature("helix", "Helis")
		if kind == "spiral":
			hx.params = {"sketch": hs.id, "kind": "spiral", "pitch": 3.0, "turns": 3.0}
		else:
			hx.params = {"sketch": hs.id, "kind": "helix", "mode": "pitch_turns", "pitch": 4.0, "turns": 4.0, "taper": 10.0}
		d5.add_feature(hx)
		var hp := sketch(d5, SketchPlane.standard("front"))
		hp.sketch.add_circle(hp.sketch.add_point(Vector2(5, 0)), 0.5)
		var sw := d5.new_feature("sweep", "Süpürme")
		sw.params = {"sketch": hp.id, "path": {"kind": "helix", "id": hx.id}, "cut": false}
		d5.add_feature(sw)
		await build(d5)
		var L := poly_len(RefGeom.helix_points(RefGeom.helix_spec(d5, hx)))
		check(sw.error == "" and near(vol(), PI * 0.25 * L, 0.02), "%s süpürme hacmi %.3f ≈ π r² L = %.3f %s" % [kind, vol(), PI * 0.25 * L, sw.error])

	print("== Faz 5b: projeksiyon eğrisi")
	var d6 := new_doc()
	var s6 := sketch(d6, SketchPlane.standard("top"))
	s6.sketch.add_circle(s6.sketch.add_point(Vector2.ZERO), 20.0)
	extrude(d6, s6, 40.0)
	var r6 := refplane(d6, {"mode": "offset", "base": "front", "dist": 30.0})
	var src := sketch_on_ref(d6, r6)
	src.sketch.add_line(src.sketch.add_point(Vector2(-5, 10)), src.sketch.add_point(Vector2(5, 30)))
	var pc := d6.new_feature("projcurve", "Projeksiyon")
	pc.params = {"sketch": src.id, "face": {"p": [0.0, 20.0, 20.0], "n": [0.0, 0.0, 1.0], "name": ""}}
	d6.add_feature(pc)
	await build(d6)
	var poly: Array = pc.runtime.get("poly", [])
	var on_cyl := not poly.is_empty()
	var plen := 0.0
	var first: Vector3 = Vector3.ZERO
	var second: Vector3 = Vector3.ZERO
	for ch in poly:
		for i in (ch as Array).size():
			var q := ModelMesh._v3(ch[i])
			if absf(sqrt(q.x * q.x + q.z * q.z) - 20.0) > 1e-3 or q.z < 0.0:
				on_cyl = false
			if i > 0:
				plen += q.distance_to(ModelMesh._v3(ch[i - 1]))
		if first == Vector3.ZERO and (ch as Array).size() > 1:
			first = ModelMesh._v3(ch[0])
			second = ModelMesh._v3(ch[1])
	check(pc.error == "" and on_cyl, "izdüşen eğri silindirin ön yüzünde (%d zincir, uzunluk %.3f) %s" % [poly.size(), plen, pc.error])
	var tang := (second - first).normalized()
	var pp := sketch(d6, SketchPlane.from_face(first, tang))
	pp.sketch.add_circle(pp.sketch.add_point(pp.plane.to_local(first)), 0.5)
	var swp := d6.new_feature("sweep", "Süpürme")
	swp.params = {"sketch": pp.id, "path": {"kind": "projcurve", "id": pc.id}, "cut": false, "merge": false}
	d6.add_feature(swp)
	await build(d6)
	var vcyl := PI * 400.0 * 40.0
	check(swp.error == "" and near(vol() - vcyl, PI * 0.25 * plen, 0.03), "projeksiyon eğrisi boyunca süpürme (%.3f ≈ %.3f) %s" % [vol() - vcyl, PI * 0.25 * plen, swp.error])

	print("== Faz 5b: sarma (kabartma / oyma / çizgi)")
	var d7 := new_doc()
	var s7 := sketch(d7, SketchPlane.standard("top"))
	s7.sketch.add_circle(s7.sketch.add_point(Vector2.ZERO), 20.0)
	extrude(d7, s7, 40.0)
	var r7 := refplane(d7, {"mode": "offset", "base": "front", "dist": 20.0})
	var w7 := sketch_on_ref(d7, r7)
	rect(w7.sketch, -5, 10, 5, 30)
	var wr := d7.new_feature("wrap", "Sarma")
	wr.params = {"sketch": w7.id, "face": {"p": [0.0, 20.0, 20.0], "n": [0.0, 0.0, 1.0], "name": ""}, "wtype": "emboss", "depth": 2.0}
	d7.add_feature(wr)
	await build(d7)
	var vc7 := PI * 400.0 * 40.0
	check(wr.error == "" and near(vol() - vc7, 420.0, 1e-5), "sarma kabartma: +%.4f ≈ 420 %s" % [vol() - vc7, wr.error])
	wr.params["wtype"] = "deboss"
	await build(d7)
	check(wr.error == "" and near(vc7 - vol(), 380.0, 1e-5), "sarma oyma: -%.4f ≈ 380 %s" % [vc7 - vol(), wr.error])
	wr.params["wtype"] = "scribe"
	await build(d7)
	check(wr.error == "" and near(vol(), vc7, 1e-6) and (kernel.brep["faces"] as Array).size() > 3, "sarma çizgi: hacim aynı, yüz bölündü (%d yüz) %s" % [(kernel.brep["faces"] as Array).size(), wr.error])
	w7.sketch = Sketch.new()
	w7.sketch.add_circle(w7.sketch.add_point(Vector2(0, 20)), 5.0)
	wr.params["wtype"] = "emboss"
	await build(d7)
	var vdisc := PI * 25.0 * (22.0 * 22.0 - 400.0) / (2.0 * 20.0)
	check(wr.error == "" and near(vol() - vc7, vdisc, 0.002), "sarılmış daire kabartması %.3f ≈ %.3f %s" % [vol() - vc7, vdisc, wr.error])

	print("== Faz 5b: kabartma / gravür")
	var d8 := new_doc()
	var b8 := sketch(d8, SketchPlane.standard("top"))
	rect(b8.sketch, -20, -10, 20, 10)
	extrude(d8, b8, 10.0)
	var r8 := refplane(d8, {"mode": "offset", "base": "top", "dist": 20.0})
	var e8s := sketch_on_ref(d8, r8)
	e8s.sketch.add_circle(e8s.sketch.add_point(Vector2.ZERO), 5.0)
	var em := d8.new_feature("emboss", "Kabartma")
	em.params = {"sketch": e8s.id, "depth": 2.0, "etype": "emboss"}
	d8.add_feature(em)
	await build(d8)
	check(em.error == "" and near(vol(), 8000.0 + PI * 25.0 * 2.0, 1e-6), "düz yüze kabartma: +%.4f ≈ %.4f %s" % [vol() - 8000.0, PI * 50.0, em.error])
	em.params["etype"] = "deboss"
	await build(d8)
	check(em.error == "" and near(vol(), 8000.0 - PI * 25.0 * 2.0, 1e-6), "gravür (yalnızca üst yüz, alt yüz etkilenmez): %.4f %s" % [vol(), em.error])
	var d9 := new_doc()
	var s9 := sketch(d9, SketchPlane.standard("top"))
	s9.sketch.add_circle(s9.sketch.add_point(Vector2.ZERO), 20.0)
	extrude(d9, s9, 40.0)
	var r9 := refplane(d9, {"mode": "offset", "base": "front", "dist": 30.0})
	var e9 := sketch_on_ref(d9, r9)
	e9.sketch.add_circle(e9.sketch.add_point(Vector2(0, 20)), 3.0)
	var em9 := d9.new_feature("emboss", "Kabartma")
	em9.params = {"sketch": e9.id, "depth": 1.0, "etype": "emboss"}
	d9.add_feature(em9)
	await build(d9)
	var add9 := vol() - PI * 400.0 * 40.0
	check(em9.error == "" and add9 > PI * 9.0 * 0.95 and add9 < PI * 9.0 * 1.15, "silindir yüzeyine kabartma yüzeyi izler (+%.3f) %s" % [add9, em9.error])


func _hlr_bbox(polys: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for pl in polys:
		for q in pl:
			var p := Vector2(float(q[0]), float(q[1]))
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	return r


func _loop_area(lp: Array) -> float:
	var pts := PackedVector2Array()
	for q in lp:
		pts.append(Vector2(float(q[0]), float(q[1])))
	return absf(Drawing.polygon_area(pts))


func run_6() -> void:
	print("== Faz 6: teknik resim görünüşleri (HLR)")
	# 40 x 10 x 20 kutu (X, Y, Z), Y boyunca Ø8 boydan boya delik
	var doc := new_doc()
	var hs := sketch(doc, SketchPlane.standard("top"))
	rect(hs.sketch, -20, -10, 20, 10)
	hs.sketch.add_circle(hs.sketch.add_point(Vector2.ZERO), 4.0)
	extrude(doc, hs, 10.0)
	await build(doc)
	check(near(vol(), 8000.0 - PI * 16.0 * 10.0, 1e-6), "delikli kutu hacmi %.4f" % vol())
	var views := [
		{"id": 1, "dir": [0, 0, 1], "x": [1, 0, 0]},
		{"id": 2, "dir": [0, 1, 0], "x": [1, 0, 0]},
		{"id": 3, "dir": [0, 0, 1], "x": [1, 0, 0], "section": {"o": [0, 0, 0], "n": [0, 0, 1]}},
		{"id": 4, "dir": [0.57735, 0.57735, 0.57735], "x": [0.70711, 0, -0.70711]},
	]
	check(kernel.request_hlr(views), "HLR isteği gönderildi")
	var res: Dictionary = await kernel.hlr_done
	check(bool(res.get("ok", false)) and (res.get("views", []) as Array).size() == 4, "4 görünüş hesaplandı (%s ms) %s" % [str(res.get("ms", "?")), str(res.get("error", ""))])
	var by := {}
	for v in res.get("views", []):
		by[int(v["id"])] = v
	var fr: Dictionary = by.get(1, {})
	var fb := _hlr_bbox(fr.get("visible", []))
	check(fb.position.is_equal_approx(Vector2(-20, 0)) and fb.size.is_equal_approx(Vector2(40, 10)), "ön görünüş dış çizgileri 40 × 10 (%s)" % str(fb))
	var hb := _hlr_bbox(fr.get("hidden", []))
	check((fr.get("hidden", []) as Array).size() >= 2 and hb.position.is_equal_approx(Vector2(-4, 0)) and hb.size.is_equal_approx(Vector2(8, 10)), "delik önden gizli çizgi: x = ±4 (%s)" % str(hb))
	var tp: Dictionary = by.get(2, {})
	var tb := _hlr_bbox(tp.get("visible", []))
	check(tb.size.is_equal_approx(Vector2(40, 20)), "üst görünüş 40 × 20 (%s)" % str(tb))
	check((tp.get("hidden", []) as Array).is_empty(), "üstten bakışta gizli kenar yok")
	var circ_ok := false
	for cc in tp.get("circles", []):
		if absf(float(cc["r"]) - 4.0) < 1e-6 and Vector2(float(cc["c"][0]), float(cc["c"][1])).length() < 1e-6:
			circ_ok = true
	check(circ_ok, "üst görünüşte r=4 daire, merkez (0,0)")
	var sc: Dictionary = by.get(3, {})
	var area := 0.0
	for region in sc.get("hatch", []):
		var a0 := _loop_area(region[0])
		for k in range(1, (region as Array).size()):
			a0 -= _loop_area(region[k])
		area += a0
	check(near(area, 320.0, 1e-6), "kesit tarama alanı (40-8) × 10 = 320 (%.6f)" % area)
	var sb := _hlr_bbox(sc.get("visible", []))
	check(sb.size.is_equal_approx(Vector2(40, 10)), "kesit görünüşü dış çizgileri (%s)" % str(sb))
	var iso: Dictionary = by.get(4, {})
	check((iso.get("visible", []) as Array).size() >= 9, "izometrik görünüş kenarları (%d)" % (iso.get("visible", []) as Array).size())
	# Resim çizimine aktarım: aynı sonuç sayfa ilkellerine dönüşür
	var sh := Drawing.new_sheet("S")
	sh["views"] = [{"id": 1, "type": "model", "orient": "front", "pos": [100.0, 150.0], "hidden": "visible_hidden"},
		{"id": 3, "type": "section", "parent": 1, "dir": [0, 0, 1], "x": [1, 0, 0], "pos": [200.0, 150.0],
			"section": {"a": [-30, 5], "b": [30, 5], "o": [0, 0, 0], "n": [0, 0, 1], "label": "A"}}]
	var geo := {1: fr, 3: sc}
	var prims := DrawingRender.build(doc, sh, geo, {})
	var n_hatch := 0
	var n_hidden := 0
	for p in prims:
		if p.get("lay", "") == "TARAMA":
			n_hatch += 1
		if p.get("lay", "") == "GIZLI":
			n_hidden += 1
	check(n_hatch > 5 and n_hidden >= 2, "sayfada tarama (%d) ve gizli çizgi (%d)" % [n_hatch, n_hidden])
	# Boş model: hata döner, çökme yok
	var empty := new_doc()
	await build(empty)
	kernel.request_hlr([{"id": 1, "dir": [0, 0, 1], "x": [1, 0, 0]}])
	var r2: Dictionary = await kernel.hlr_done
	check(not bool(r2.get("ok", true)), "boş modelde anlamlı hata: " + str(r2.get("error", "")))


func n_bodies() -> int:
	var faces: Array = kernel.brep.get("faces", [])
	var b := {}
	for f in faces:
		b[int(f.get("body", -1))] = true
	return b.size()


func run_8() -> void:
	print("== Faz 8: sac metal")
	var doc := new_doc()
	var s := sketch(doc, SketchPlane.standard("top"))
	rect(s.sketch, -50, -30, 50, 30)
	var base := doc.new_feature("sm_base", "Taban-Flanş")
	base.params = SheetMetal.DEFAULTS.duplicate()
	base.params["sketch"] = s.id
	doc.add_feature(base)
	await build(doc)
	check(base.error == "" and near(vol(), 100.0 * 60.0 * 2.0, 1e-9), "taban flanş: 100 × 60 × 2 plaka (%.3f) %s" % [vol(), base.error])
	# Üst kenarları B-rep kenar adlarından seç
	var refs: Array = []
	for e in kernel.brep.get("edges", []):
		var fn: Array = e.get("fn", [])
		var pe := SheetMetal.parse_edge(fn)
		if not pe.is_empty() and str(pe["cap"]) == "b":
			refs.append({"m": e["m"], "d": e["d"], "fn": fn})
	check(refs.size() == 4, "üst kenarlar topolojik addan bulundu (%d)" % refs.size())
	var ef := doc.new_feature("sm_edge", "Kenar-Flanş")
	ef.params = {"edges": refs, "L": 20.0, "A": 90.0, "R": -1.0, "flip": false, "off1": 0.0, "off2": 0.0}
	doc.add_feature(ef)
	await build(doc)
	var vf := 320.0 * (PI * 0.25 * (16.0 - 4.0) + 2.0 * 20.0)
	check(ef.error == "" and near(vol(), 12000.0 + vf, 1e-6), "4 kenar flanşı: hacim %.3f ≈ %.3f %s" % [vol(), 12000.0 + vf, ef.error])
	check(n_bodies() == 1 and bool(kernel.brep.get("valid", false)), "tek gövde, geçerli B-rep")
	base.params["flat"] = true
	await build(doc)
	var W := PI * 0.5 * (2.0 + 0.44 * 2.0) + 20.0
	check(base.error == "" and near(vol(), (6000.0 + 320.0 * W) * 2.0, 1e-4), "açınım: düz sac hacmi = açınım alanı × T (%.3f)" % vol())
	base.params["flat"] = false
	ef.params["A"] = 45.0
	await build(doc)
	check(ef.error == "" and near(vol(), 12000.0 + 320.0 * (PI * 0.125 * 12.0 + 40.0), 1e-6), "45° flanş hacmi")
	print("== Faz 8: bükümlü taban (L profil)")
	var d2 := new_doc()
	var s2 := sketch(d2, SketchPlane.standard("front"))
	var q0 := s2.sketch.add_point(Vector2(0, 0))
	var q1 := s2.sketch.add_point(Vector2(50, 0))
	var q2 := s2.sketch.add_point(Vector2(50, 30))
	s2.sketch.add_line(q0, q1)
	s2.sketch.add_line(q1, q2)
	var b2 := d2.new_feature("sm_base", "Taban-Flanş")
	b2.params = SheetMetal.DEFAULTS.duplicate()
	b2.params.merge({"sketch": s2.id, "T": 2.0, "R": 3.0, "depth": 40.0}, true)
	d2.add_feature(b2)
	await build(d2)
	check(b2.error == "" and near(vol(), 40.0 * (140.0 + PI * 4.0), 1e-6), "L büküm: hacim %.3f ≈ %.3f %s" % [vol(), 40.0 * (140.0 + PI * 4.0), b2.error])
	var cyl := 0
	for f3 in kernel.brep.get("faces", []):
		if str(f3.get("type", "")) == "cylinder":
			cyl += 1
	check(cyl == 2, "büküm bölgesi gerçek silindirik yüzler (%d)" % cyl)
	print("== Faz 8: kaynaklı konstrüksiyon")
	var d3 := new_doc()
	var s3 := sketch(d3, SketchPlane.standard("front"))
	rect(s3.sketch, 0, 0, 400, 300)
	var w := d3.new_feature("weld", "Yapısal Üye")
	w.params = {"sketch": s3.id, "ptype": "shs", "psize": "40x40x3", "rot": 0.0, "corner": "miter"}
	d3.add_feature(w)
	await build(d3)
	var A := 1600.0 - 34.0 * 34.0
	check(w.error == "" and near(vol(), A * 1400.0, 1e-6) and n_bodies() == 4, "gönye çerçeve: 4 gövde, hacim alan × merkez boy (%.1f) %s" % [vol(), w.error])
	w.params["corner"] = "butt"
	await build(d3)
	check(w.error == "" and near(vol(), A * 1400.0, 1e-6) and n_bodies() == 4, "alın birleşimli çerçeve hacmi aynı (%.1f)" % vol())
	s3.sketch.add_line(s3.sketch.add_point(Vector2(200, 0)), s3.sketch.add_point(Vector2(200, 300)))
	w.params["corner"] = "miter"
	await build(d3)
	check(w.error == "" and near(vol(), A * (1400.0 + 260.0), 1e-6) and n_bodies() == 5, "T birleşimli orta üye kırpıldı (%.1f)" % vol())


func surf_area() -> float:
	var a := 0.0
	for f in kernel.brep.get("faces", []):
		if int(f.get("body", -1)) < 0:
			a += float(f.get("area", 0.0))
	return a


func run_8b() -> void:
	print("== Faz 8: yüzey modelleme")
	var doc := new_doc()
	var s := sketch(doc, SketchPlane.standard("top"))
	rect(s.sketch, -20, -10, 20, 10)
	var se := doc.new_feature("srf_extrude", "Ekstrüde-Yüzey")
	se.params = Surfaces.defaults("srf_extrude")
	se.params.merge({"sketch": s.id, "depth": 30.0}, true)
	doc.add_feature(se)
	await build(doc)
	check(se.error == "" and near(surf_area(), 120.0 * 30.0, 1e-6) and near(vol(), 0.0, 1e-9), "ekstrüde yüzey: çevre × derinlik alanı, hacim 0 (%.2f) %s" % [surf_area(), se.error])
	var c1 := sketch(doc, SketchPlane.standard("top"))
	rect(c1.sketch, -20, -10, 20, 10)
	var p1 := doc.new_feature("srf_planar", "Düzlemsel-Yüzey")
	p1.params = {"sketch": c1.id}
	doc.add_feature(p1)
	var c2 := sketch(doc, SketchPlane.from_face(Vector3(0, 30, 0), Vector3.UP))
	rect(c2.sketch, -20, -10, 20, 10)
	var p2 := doc.new_feature("srf_planar", "Düzlemsel-Yüzey")
	p2.params = {"sketch": c2.id}
	doc.add_feature(p2)
	await build(doc)
	check(p2.error == "" and near(surf_area(), 3600.0 + 1600.0, 1e-6), "iki düzlemsel kapak yüzeyi (%.2f)" % surf_area())
	var kn := doc.new_feature("srf_knit", "Yüzey-Dikme")
	kn.params = Surfaces.defaults("srf_knit")
	doc.add_feature(kn)
	await build(doc)
	check(kn.error == "" and near(vol(), 40.0 * 20.0 * 30.0, 1e-4) and near(surf_area(), 0.0, 1e-9), "dikme: kapalı yüzeylerden katı 40×20×30 (%.2f) %s" % [vol(), kn.error])
	var d2 := new_doc()
	var s2 := sketch(d2, SketchPlane.standard("top"))
	rect(s2.sketch, -20, -10, 20, 10)
	var pl := d2.new_feature("srf_planar", "Düzlemsel-Yüzey")
	pl.params = {"sketch": s2.id}
	d2.add_feature(pl)
	var s3 := sketch(d2, SketchPlane.standard("front"))
	rect(s3.sketch, 50, 0, 60, 10)
	var ex := extrude(d2, s3, 10.0)
	await build(d2)
	check(ex.error == "" and near(vol(), 1000.0, 1e-6) and near(surf_area(), 800.0, 1e-6), "yüzey gövdesi sonraki katı özelliğinde korunur (V %.1f, A %.1f) %s" % [vol(), surf_area(), ex.error])
	var th := d2.new_feature("srf_thicken", "Kalınlaştır")
	th.params = Surfaces.defaults("srf_thicken")
	th.params["merge"] = false
	d2.add_feature(th)
	await build(d2)
	check(th.error == "" and near(vol(), 1000.0 + 800.0 * 2.0, 1e-4) and near(surf_area(), 0.0, 1e-9), "kalınlaştır: 40×20 yüzey × 2 mm (%.2f) %s" % [vol(), th.error])
	var d3 := new_doc()
	var s4 := sketch(d3, SketchPlane.standard("front"))
	rect(s4.sketch, -20, -10, 20, 10)
	var pf := d3.new_feature("srf_planar", "Düzlemsel-Yüzey")
	pf.params = {"sketch": s4.id}
	d3.add_feature(pf)
	var tr := d3.new_feature("srf_trim", "Yüzey-Kırp")
	tr.params = {"plane": "top", "off": 0.0, "flip": false}
	d3.add_feature(tr)
	await build(d3)
	check(tr.error == "" and near(surf_area(), 400.0, 1e-6), "kırp: üst düzlemin üstü atıldı (%.2f) %s" % [surf_area(), tr.error])
	var of := d3.new_feature("srf_offset", "Ofset-Yüzey")
	of.params = {"d": 5.0}
	d3.add_feature(of)
	await build(d3)
	check(of.error == "" and near(surf_area(), 800.0, 1e-6), "ofset yüzey eklendi (%.2f)" % surf_area())
	print("== Faz 8: statik analiz (FEA)")
	var d4 := new_doc()
	var s5 := sketch(d4, SketchPlane.standard("right"))
	rect(s5.sketch, -5, 0, 5, 10)   # 10 x 10 kesit
	var bx := extrude(d4, s5, 100.0)
	await build(d4)
	var faces: Array = kernel.brep.get("faces", [])
	var fix := {}
	var tip := {}
	for f in faces:
		if str(f.get("type", "")) == "plane":
			var n := Vector3(f["n"][0], f["n"][1], f["n"][2])
			var pp := Vector3(f["p"][0], f["p"][1], f["p"][2])
			if absf(n.x) > 0.99:
				if fix.is_empty() or pp.x < float(fix["p"][0]):
					fix = {"p": f["p"], "n": f["n"], "name": str(f.get("name", ""))}
				if tip.is_empty() or pp.x > float(tip["p"][0]):
					tip = {"p": f["p"], "n": f["n"], "name": str(f.get("name", ""))}
	var st := {"E": 210.0, "nu": 0.3, "elements": 2000, "fix": [fix], "loads": [{"face": tip, "mag": 100.0, "dir": "-y"}]}
	kernel.request_asm("fea", Fea.request(st))
	var res: Dictionary = await kernel.asm_done
	var L := absf(float(tip["p"][0]) - float(fix["p"][0]))
	var dd := 100.0 * L * L * L / (3.0 * 210000.0 * (10.0 * 1000.0 / 12.0))
	check(bool(res.get("ok", false)) and absf(float(res.get("u_max", 0.0)) / dd - 1.0) < 0.03, "konsol kiriş sehimi %.4f ≈ FL³/3EI = %.4f (%d eleman) %s" % [float(res.get("u_max", 0.0)), dd, int(res.get("elements", 0)), str(res.get("error", ""))])
	var rv: Array = res.get("reaction", [0, 0, 0])
	check(absf(float(rv[1]) - 100.0) < 1e-3 and absf(float(rv[0])) < 1e-3, "mesnet tepkisi = uygulanan kuvvet (Ry %.4f N)" % float(rv[1]))
	var pr := Fea.parse(res)
	var vmax_center := _fea_sample(pr, Vector3(-L * 0.5 + float(fix["p"][0]) + L, 5.0, 0.0))
	check((pr["vm_arr"] as PackedFloat32Array).size() == int(res["dims"][0]) * int(res["dims"][1]) * int(res["dims"][2]), "sonuç ızgarası boyutları")
	kernel.request_asm("fea", {"E": 210000.0, "nu": 0.3, "elements": 500, "fixtures": [], "loads": []})
	var r2: Dictionary = await kernel.asm_done
	check(not bool(r2.get("ok", true)), "sabit yüz yoksa anlamlı hata: " + str(r2.get("error", "")))


func _fea_sample(r: Dictionary, p: Vector3) -> float:
	return Fea._elem_value(r, p)


func _finish() -> void:
	print("")
	print("OCC SONUÇ: %d başarılı, %d başarısız" % [passed, failed])
	kernel.occ.stop()
	quit(1 if failed > 0 else 0)


func run_stl() -> void:
	print("== STL içe aktarma (OpenCASCADE)")
	var p := ProjectSettings.globalize_path("user://occ_kutu.stl")
	write_box_stl(p, Vector3(0, 0, 0), Vector3(100, 10, 20))
	var doc := new_doc()
	var f := doc.new_feature("import", "İçe Aktarılan")
	f.params = {"path": p, "scale": 1.0, "sx": 0.5, "sy": 2.0, "sz": 3.0, "origin": [10.0, 0.0, 0.0], "move": [-10.0, 1.0, 0.0]}
	doc.add_feature(f)
	await build(doc)
	check(f.error == "" and near(vol(), 50.0 * 20.0 * 60.0, 1e-3), "STL kutu: eksen bazlı ölçek, katı hacmi %.1f %s" % [vol(), f.error])
	var nf := 0
	for fc in kernel.brep.get("faces", []):
		nf += 1
	check(nf == 12, "STL üçgenleri B-rep yüzlerine dönüştü (%d yüz)" % nf)
	f.params["stretch"] = {"axis": "x", "a": 20.0, "b": 80.0, "add": 40.0}
	doc.commit()
	await build(doc)
	check(f.error == "" and near(vol(), 90.0 * 20.0 * 60.0, 1e-3), "STL kutu: ölçek + uzatma, katı hacmi %.1f %s" % [vol(), f.error])
	f.params = {"path": p, "scale": 1.0, "stretch": [{"axis": "x", "a": 10.0, "b": 20.0, "add": 10.0}, {"axis": "x", "a": 50.0, "b": 60.0, "add": -5.0}]}
	doc.commit()
	await build(doc)
	check(f.error == "" and near(vol(), 105.0 * 200.0, 1e-3), "STL çok bölgeli uzatma: hacim %.1f %s" % [vol(), f.error])
	f.params = {"path": p, "scale": 1.0, "sy": 2.0, "sz": 2.0, "protect": {"axis": "x", "a": -1.0, "b": 101.0, "blend": 0.0,
		"bands": [[6.0, null], null], "soft": [2.0, 2.0], "offset": [3.0, 0.0]}}
	doc.commit()
	await build(doc)
	check(f.error == "" and near(vol(), 43000.0, 1e-3), "STL koruma bölgesi (OpenCASCADE): hacim %.1f %s" % [vol(), f.error])
	f.params = {"path": p, "scale": 1.0, "taper": {"axis": "x", "a": 0.0, "b": 100.0, "grow": [10.0, 20.0],
		"profile": [[0.0, 5.0, 10.0, 10.0, 20.0], [100.0, 5.0, 10.0, 10.0, 20.0]]}}
	doc.commit()
	await build(doc)
	check(f.error == "" and near(vol(), 200.0 * 100.0 * 7.0 / 3.0, 1e-2), "STL kademeli kesit büyütme (OpenCASCADE): hacim %.1f %s" % [vol(), f.error])


## Test için ikili STL kutu yazar (x0..x1 × y0..y1 × z0..z1, dış normallere göre CCW)
static func write_box_stl(path: String, lo: Vector3, hi: Vector3, ascii := false) -> void:
	var c := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	var q := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [0, 4, 7, 3]]
	var tris: Array = []
	for f in q:
		tris.append([c[f[0]], c[f[1]], c[f[2]]])
		tris.append([c[f[0]], c[f[2]], c[f[3]]])
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if ascii:
		var s := "solid kutu\n"
		for t in tris:
			s += "facet normal 0 0 0\nouter loop\n"
			for v in t:
				s += "vertex %f %f %f\n" % [v.x, v.y, v.z]
			s += "endloop\nendfacet\n"
		fa.store_string(s + "endsolid kutu\n")
	else:
		var hdr := PackedByteArray()
		hdr.resize(80)
		fa.store_buffer(hdr)
		fa.store_32(tris.size())
		for t in tris:
			for k in 3:
				fa.store_float(0.0)
			for v in t:
				fa.store_float(v.x)
				fa.store_float(v.y)
				fa.store_float(v.z)
			fa.store_16(0)
	fa.close()
