extends SceneTree
## Otomatik testler. Çalıştırma:
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/selftest.gd

var fails := 0
var passes := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		print("  OK   ", label)
	else:
		fails += 1
		print("  FAIL ", label)


func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	_run()


func _wait_build(kernel: CsgKernel) -> ArrayMesh:
	var result: Array = []
	var cb := func(m): result.append(m)
	kernel.built.connect(cb, CONNECT_ONE_SHOT)
	for i in 20:
		await process_frame
		if not result.is_empty():
			break
	return result[0] if not result.is_empty() else null


func _run() -> void:
	print("== Birimler")
	check(near(Units.evaluate("10/4"), 2.5, 1e-9), "10/4 = 2.5 (tamsayı bölmesi yok)")
	check(near(Units.evaluate("12,5"), 12.5, 1e-9), "virgüllü ondalık 12,5")
	check(near(Units.evaluate("2*(3+4)"), 14.0, 1e-9), "parantezli ifade")
	check(near(Units.evaluate("1in"), 25.4, 1e-9), "1in = 25.4 mm")
	check(near(Units.evaluate("1in + 3mm"), 28.4, 1e-9), "karışık birimler")
	check(Units.evaluate("abc") == null, "geçersiz ifade null")

	print("== Taslak konturları")
	var sk := Sketch.new()
	sk.add_rect([sk.add_point(Vector2(0, 0)), sk.add_point(Vector2(40, 0)), sk.add_point(Vector2(40, 20)), sk.add_point(Vector2(0, 20))])
	sk.add_circle(sk.add_point(Vector2(20, 10)), 5)
	var prof := sk.extract_profiles()
	var loops: Array = prof["loops"]
	check(loops.size() == 2, "dikdörtgen + daire = 2 kontur")
	check(loops.size() == 2 and loops[0]["depth"] == 0 and loops[1]["depth"] == 1, "daire delik (depth 1)")
	var sk2 := Sketch.new()
	var a := sk2.add_point(Vector2(0, 0))
	var b := sk2.add_point(Vector2(10, 0))
	var c := sk2.add_point(Vector2(10, 10))
	sk2.add_line(a, b)
	sk2.add_line(b, c)
	check((sk2.extract_profiles()["loops"] as Array).is_empty() and sk2.extract_profiles()["open"] == 1, "açık zincir kontur değil")
	sk2.add_line(c, a)
	check((sk2.extract_profiles()["loops"] as Array).size() == 1, "kapanan üçgen 1 kontur")
	var cl := sk2.add_point(Vector2(-5, -5))
	var cl2 := sk2.add_point(Vector2(-5, 15))
	sk2.add_line(cl, cl2, true)
	check((sk2.extract_profiles()["loops"] as Array).size() == 1, "yapı çizgisi konturu bozmaz")

	print("== Örnek parça (CSG çekirdeği)")
	var doc := CadDocument.new()
	DemoParts.build_bracket(doc)
	var kernel := CsgKernel.new()
	root.add_child(kernel)
	kernel.rebuild(doc)
	var mesh := await _wait_build(kernel)
	check(mesh != null, "mesh üretildi")
	var errs := []
	for f in doc.features:
		if f.error != "":
			errs.append(f.name + ": " + f.error)
	check(errs.is_empty(), "özellik hatası yok " + str(errs))
	var mm := ModelMesh.new()
	mm.build(mesh)
	check(mm.tri_count() > 100, "üçgen sayısı: %d" % mm.tri_count())
	var va := mm.volume_and_area()
	var expected := 32000.0 - 4.0 * PI * 3.5 * 3.5 * 8.0 - (20.0 * 5.0 + PI * 2.5 * 2.5) * 8.0 \
		+ PI * 14.0 * 14.0 * 22.0 - PI * 7.0 * 7.0 * 30.0 + PI * (19.0 * 19.0 - 14.0 * 14.0) * 6.0
	print("    hacim = %.1f mm³ (beklenen ≈ %.1f)" % [va.x, expected])
	check(absf(va.x - expected) / expected < 0.01, "hacim %1 içinde")
	check(mm.feature_edges.size() > 0, "kenar çizgileri: %d" % (mm.feature_edges.size() / 2))
	var hit := mm.raycast(Vector3(0, 100, 20), Vector3.DOWN)
	check(not hit.is_empty() and near(hit["point"].y, 8.0, 0.01), "ışın plakanın üst yüzüne (y=8) çarpar")
	if not hit.is_empty():
		var face := mm.planar_face(hit["tri"])
		check(face["planar"] and (face["normal"] as Vector3).dot(Vector3.UP) > 0.999, "üst yüz düzlemsel, normal +Y")
	var hit2 := mm.raycast(Vector3(0, 20, 100), Vector3.FORWARD)
	if not hit2.is_empty():
		var face2 := mm.planar_face(hit2["tri"])
		check(not face2["planar"], "silindir yüzü düzlemsel değil")

	print("== Dışa aktarma")
	var tmp := OS.get_user_data_dir().path_join("selftest")
	DirAccess.make_dir_recursive_absolute(tmp)
	var stl := tmp.path_join("demo.stl")
	check(Exporters.write_stl(stl, mm.ccw_triangles(), "demo") == OK, "STL yazıldı")
	var fsize := FileAccess.get_file_as_bytes(stl).size()
	check(fsize == 84 + 50 * mm.tri_count(), "STL boyutu doğru (%d bayt)" % fsize)
	check(Exporters.write_obj(tmp.path_join("demo.obj"), mm) == OK, "OBJ yazıldı")
	check(Exporters.write_dxf(tmp.path_join("plate.dxf"), doc.features[0].sketch) == OK, "DXF yazıldı")
	check(Exporters.write_svg(tmp.path_join("slot.svg"), doc.get_feature(7).sketch) == OK, "SVG yazıldı")
	# STL normal yönü: üst yüz üçgeninin normali +Y olmalı
	var tris := mm.ccw_triangles()
	var up_ok := false
	for t in tris.size() / 3:
		var p0 := tris[t * 3]
		var p1 := tris[t * 3 + 1]
		var p2 := tris[t * 3 + 2]
		if near(p0.y, 30.0, 0.001) and near(p1.y, 30.0, 0.001) and near(p2.y, 30.0, 0.001):
			up_ok = (p1 - p0).cross(p2 - p0).y > 0.0
			break
	check(up_ok, "STL üçgenleri dışa bakıyor (saat yönü tersine)")

	print("== Kaydet / aç")
	var path := tmp.path_join("demo.dcad")
	check(doc.save_to(path) == OK, "kaydedildi")
	var doc2 := CadDocument.new()
	check(doc2.load_from(path) == OK, "açıldı")
	check(JSON.stringify(doc2.to_dict()) == JSON.stringify(doc.to_dict()), "kaydet/aç sonrası belge aynı")
	kernel.rebuild(doc2)
	var mesh2 := await _wait_build(kernel)
	var mm2 := ModelMesh.new()
	mm2.build(mesh2)
	check(near(mm2.volume_and_area().x, va.x, 0.5), "açılan belgenin hacmi aynı")

	print("== Geri al / yinele")
	var n0 := doc2.features.size()
	doc2.checkpoint()
	doc2.remove_feature(doc2.features[n0 - 1].id)
	doc2.commit()
	check(doc2.features.size() == n0 - 1, "özellik silindi")
	doc2.undo()
	check(doc2.features.size() == n0, "geri alındı")
	doc2.redo()
	check(doc2.features.size() == n0 - 1, "yinelendi")

	print("== Ekstrüzyon seçenekleri")
	var d3 := CadDocument.new()
	var s := d3.new_feature("sketch", "Taslak")
	s.plane = SketchPlane.standard("front")
	s.sketch = Sketch.new()
	s.sketch.add_rect([s.sketch.add_point(Vector2(0, 0)), s.sketch.add_point(Vector2(10, 0)), s.sketch.add_point(Vector2(10, 10)), s.sketch.add_point(Vector2(0, 10))])
	d3.add_feature(s)
	var e := d3.new_feature("extrude", "Ekstrüzyon")
	e.params = {"sketch": s.id, "depth": 20.0, "end": "midplane", "reverse": false, "cut": false}
	d3.add_feature(e)
	kernel.rebuild(d3)
	var m3 := await _wait_build(kernel)
	check(m3 != null and near(m3.get_aabb().position.z, -10.0, 0.01) and near(m3.get_aabb().end.z, 10.0, 0.01), "orta düzlem: z -10..10")
	e.params["end"] = "blind"
	e.params["reverse"] = true
	kernel.rebuild(d3)
	m3 = await _wait_build(kernel)
	check(m3 != null and near(m3.get_aabb().end.z, 0.0, 0.01) and near(m3.get_aabb().position.z, -20.0, 0.01), "ters yön: z -20..0")
	e.type = "revolve"
	e.params = {"sketch": s.id, "angle": 180.0, "axis": "y", "reverse": false, "cut": false}
	kernel.rebuild(d3)
	m3 = await _wait_build(kernel)
	var mm3 := ModelMesh.new()
	mm3.build(m3)
	var expect_rev := PI * 100.0 * 10.0 * 0.5
	check(m3 != null and absf(mm3.volume_and_area().x - expect_rev) / expect_rev < 0.01, "180° döndürme hacmi (%.1f ≈ %.1f)" % [mm3.volume_and_area().x, expect_rev])

	print("== Faz 2: birim sistemleri")
	Units.set_system("IPS")
	check(Units.format_length(25.4) == "1.000 in", "IPS: 25.4 mm = %s" % Units.format_length(25.4))
	check(near(Units.parse_length("2"), 50.8, 1e-9), "IPS girdisi 2 = 50.8 mm")
	check(near(Units.parse_length("10mm"), 10.0, 1e-9), "IPS'de '10mm' yazılınca 10 mm")
	check(Units.format_mass(453.59237) == "1 lb", "kütle: %s" % Units.format_mass(453.59237))
	Units.set_system("MKS")
	check(Units.format_length(1234.5) == "1.2345 m", "MKS: %s" % Units.format_length(1234.5))
	check(Units.format_volume(1.0e9) == "1 m³", "hacim: %s" % Units.format_volume(1.0e9))
	Units.set_custom("cm", "g")
	check(Units.system == "CGS", "cm + g = CGS sistemi")
	Units.set_custom("mm", "kg")
	check(Units.system == "custom" and Units.system_short() == "Özel (mm, kg)", "özel sistem: %s" % Units.system_short())
	var ud := CadDocument.new()
	Units.set_system("IPS")
	var saved := ud.to_dict()
	Units.reset()
	ud.load_dict(saved)
	check(Units.system == "IPS", "birim sistemi belgeyle kaydedilip açılıyor")
	Units.reset()

	print("== Faz 2: kütle özellikleri")
	var bd := CadDocument.new()
	var bs := bd.new_feature("sketch", "Taslak")
	bs.plane = SketchPlane.standard("front")
	bs.sketch = Sketch.new()
	bs.sketch.add_rect([bs.sketch.add_point(Vector2(0, 0)), bs.sketch.add_point(Vector2(10, 0)), bs.sketch.add_point(Vector2(10, 20)), bs.sketch.add_point(Vector2(0, 20))])
	bd.add_feature(bs)
	var be := bd.new_feature("extrude", "Ekstrüzyon")
	be.params = {"sketch": bs.id, "depth": 30.0, "end": "blind", "reverse": false, "cut": false}
	bd.add_feature(be)
	kernel.rebuild(bd)
	var bm := await _wait_build(kernel)
	var bmm := ModelMesh.new()
	bmm.build(bm)
	var mp := bmm.mass_properties(1.0)
	check(near(mp["volume"], 6000.0, 0.01), "kutu hacmi 6000 mm³")
	check(near(mp["mass"], 6.0, 1e-5), "kütle 6 g (1 g/cm³)")
	check((mp["center"] as Vector3).is_equal_approx(Vector3(5, 10, 15)), "ağırlık merkezi (5,10,15): %s" % mp["center"])
	var t: Array = mp["tensor"]
	check(near(t[0][0], 6.0 * (400.0 + 900.0) / 12.0, 0.01), "Ixx = m(b²+c²)/12 = 650 (%.3f)" % t[0][0])
	check(near(t[1][1], 6.0 * (100.0 + 900.0) / 12.0, 0.01) and near(t[2][2], 6.0 * (100.0 + 400.0) / 12.0, 0.01), "Iyy, Izz doğru")
	check(absf(t[0][1]) < 1e-6 and absf(t[1][2]) < 1e-6, "çarpım momentleri sıfır (simetrik kutu)")
	var pm: Array = mp["principal"]
	check(near(pm[0], 250.0, 0.01) and near(pm[2], 650.0, 0.01), "asal momentler 250 / 500 / 650")
	var steel := bmm.mass_properties(Materials.density_of("Düz Karbon Çelik (AISI 1020)"))
	check(near(steel["mass"], 6.0 * 7.87, 1e-3), "çelik kutu 47.22 g")

	print("== Faz 2: örnek parça taslakları tam tanımlı")
	var sk_status := []
	for f in doc.sketches():
		sk_status.append(str(SketchSolver.analyze_sketch(f.sketch)["status"]))
	check(sk_status[0] == "full", "plaka taslağı tam tanımlı (%s)" % sk_status[0])
	check(sk_status[1] == "full" and sk_status[2] == "full" and sk_status[4] == "full", "silindir, yaka, delik taslakları tam tanımlı %s" % str(sk_status))
	check(sk_status[3] == "under", "kanal taslağı eksik tanımlı (bilerek)")
	var plate: Sketch = doc.sketches()[0].sketch
	for cc in plate.constraints:
		if cc["type"] == "hdistance" and absf(float(cc["value"]) - 80.0) < 1e-6:
			cc["value"] = 100.0
	check(SketchSolver.solve_sketch(plate), "plaka genişliği 100 yapılıp çözüldü")
	kernel.rebuild(doc)
	var mesh5 := await _wait_build(kernel)
	check(mesh5 != null and near(mesh5.get_aabb().size.x, 100.0, 0.01), "model 100 mm genişliğe güncellendi (%.3f)" % mesh5.get_aabb().size.x)

	print("")
	print("SONUÇ: %d başarılı, %d başarısız" % [passes, fails])
	quit(1 if fails > 0 else 0)
