extends Node
## Uçtan uca arayüz testi: gerçek fare olaylarıyla taslak çizer, ekstrüzyon yapar, yüzeye taslak açar.
## Çalıştırma:
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --uitest

var app: Node
var passes := 0
var fails := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		print("  OK   ", label)
	else:
		fails += 1
		print("  FAIL ", label)


func _ready() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func settle() -> void:
	# OpenCASCADE çekirdeği asenkron çalışır: kare sayısı yerine süreye göre bekle
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		if not app.viewport.camera.is_animating() and not app.viewport.kernel.is_busy():
			break
	await frames(2)


func screen_of(plane: SketchPlane, p: Vector2) -> Vector2:
	return app.viewport.world_to_screen(plane.to_world(p))


func send_click(pos: Vector2, button := MOUSE_BUTTON_LEFT, dbl := false) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	app.viewport._on_gui_input(mm)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = pos
	ev.pressed = true
	ev.double_click = dbl
	app.viewport._on_gui_input(ev)
	var ev2 := ev.duplicate() as InputEventMouseButton
	ev2.pressed = false
	ev2.double_click = false
	app.viewport._on_gui_input(ev2)


func send_drag(from: Vector2, to: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = from
	app.viewport._on_gui_input(mm)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = from
	ev.pressed = true
	app.viewport._on_gui_input(ev)
	for i in 5:
		var m2 := InputEventMouseMotion.new()
		m2.position = from.lerp(to, float(i + 1) / 5.0)
		app.viewport._on_gui_input(m2)
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.position = to
	ev2.pressed = false
	app.viewport._on_gui_input(ev2)


func sketch_click(p: Vector2) -> void:
	send_click(screen_of(app.editor.plane(), p))


func volume() -> float:
	return app.viewport.model.volume_and_area().x


func find_entity(sk: Sketch, type: String) -> Dictionary:
	for e in sk.entities:
		if e["type"] == type:
			return e
	return {}


func dims_of(sk: Sketch) -> Array:
	var out: Array = []
	for c in sk.constraints:
		if Sketch.is_dimension(c):
			out.append(c)
	return out


func type_into_dim_editor(text: String) -> void:
	var f: NumField = app.editor._edit_field
	f.text = text
	f.text_submitted.emit(text)


func fresh_doc() -> void:
	app.doc.dirty = false
	app._cmd("new")
	await settle()


func phase3b() -> void:
	print("== Faz 3b: elips ve parabol araçları")
	await fresh_doc()
	app._select({"kind": "plane", "id": "front"})
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(true)
	app.editor.set_tool("ellipse")
	sketch_click(Vector2(0, 0))
	sketch_click(Vector2(20, 0))
	sketch_click(Vector2(10, 10))
	var sk: Sketch = app.editor.sketch()
	var el := find_entity(sk, "ellipse")
	check(not el.is_empty() and el["c"] == Sketch.ORIGIN, "elips orijin merkezli çizildi")
	if not el.is_empty():
		var ax := sk.ellipse_axes(el)
		check(absf(float(ax["a"]) - 20.0) < 1e-3 and absf(float(ax["b"]) - 10.0) < 1e-3, "a=20, b=10")
	app.editor.set_tool("parabola")
	for q in [Vector2(50, -10), Vector2(50, 0), Vector2(30, 0), Vector2(70, 0)]:
		sketch_click(q)
	sk = app.editor.sketch()
	var pb := find_entity(sk, "parabola")
	check(not pb.is_empty(), "parabol çizildi")
	if not pb.is_empty():
		var fr := sk.parabola_frame(pb)
		check(absf(float(fr["fl"]) - 10.0) < 1e-3, "odak uzaklığı 10")
	app.editor.set_tool("line")
	sketch_click(sk.points[pb["a"]] if not pb.is_empty() else Vector2(30, 0))
	sketch_click(sk.points[pb["b"]] if not pb.is_empty() else Vector2(50, 0))
	app.editor.cancel()
	check((app.editor.sketch().extract_profiles()["loops"] as Array).size() == 2, "elips + kapalı parabol: 2 kontur")
	app._cmd("extrude")
	app.editing.params["depth"] = 5.0
	app._ok_feature()
	await settle()
	var exp := PI * 200.0 * 5.0 + (2.0 / 3.0) * 40.0 * 10.0 * 5.0
	check(absf(volume() - exp) / exp < 0.01, "elips + parabol ekstrüzyon hacmi %.1f ≈ %.1f" % [volume(), exp])

	print("== Faz 3b: varlıkları dönüştür")
	app._select({"kind": "plane", "id": "front"})
	app._cmd("sketch")
	await settle()
	app.viewport.camera.set_standard_view("front", false)
	await frames(2)
	app.editor.set_tool("convert")
	send_click(app.viewport.world_to_screen(Vector3(15, 0, 5)))
	sk = app.editor.sketch()
	var n_conv := sk.entities.size()
	check(n_conv >= 1 and find_entity(sk, "circle").is_empty() == false or n_conv >= 1, "elips yüzünün kenarları taslağa alındı (%d öğe)" % n_conv)
	check(SketchSolver.analyze_sketch(sk)["status"] == "full", "dönüştürülen öğeler sabit (tam tanımlı)")
	app._exit_sketch()

	print("== Faz 3b: bölge seçerek ekstrüzyon")
	await fresh_doc()
	app._select({"kind": "plane", "id": "front"})
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(false)
	app.editor.set_tool("circle")
	sketch_click(Vector2(-5, 0))
	sketch_click(Vector2(-5, 10))
	sketch_click(Vector2(5, 0))
	sketch_click(Vector2(5, 10))
	app._cmd("extrude")
	check(app.mode == "feature", "ekstrüzyon paneli")
	app._toggle_region_pick()
	check(app._region_pick, "bölge seçme modu açık")
	var plane: SketchPlane = app.doc.sketches()[0].plane
	send_click(app.viewport.world_to_screen(plane.to_world(Vector2(0, 0))))
	await settle()
	check((app.editing.params.get("regions", []) as Array).size() == 1, "mercek bölgesi seçildi")
	app.editing.params["depth"] = 10.0
	app._preview()
	app._ok_feature()
	await settle()
	var lens := (200.0 * acos(0.5) - 5.0 * sqrt(300.0)) * 10.0
	check(absf(volume() - lens) / lens < 0.02, "yalnızca mercek ekstrüde edildi: %.1f ≈ %.1f" % [volume(), lens])

	print("== Faz 3b: bloklar")
	await fresh_doc()
	app._select({"kind": "plane", "id": "front"})
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(true)
	app.editor.set_tool("rect")
	sketch_click(Vector2(10, 10))
	sketch_click(Vector2(30, 20))
	app.editor.set_tool("select")
	app.editor.selected_entities.clear()
	for e in app.editor.sketch().entities:
		app.editor.selected_entities[e["id"]] = true
	app._cmd("op_block")
	sk = app.editor.sketch()
	check(sk.blocks.size() == 1, "blok oluşturuldu")
	var corner_pid: int = sk.groups.values()[0]["pts"][2] if not sk.groups.is_empty() else (sk.blocks.values()[0]["pts"][2])
	var c_before: Vector2 = sk.points[corner_pid]
	var other_pid: int = sk.blocks.values()[0]["pts"][0]
	var d_before: float = c_before.distance_to(sk.points[other_pid])
	app.editor.clear_selection()
	send_drag(screen_of(app.editor.plane(), c_before), screen_of(app.editor.plane(), c_before + Vector2(10, 10)))
	sk = app.editor.sketch()
	check((sk.points[corner_pid] as Vector2).distance_to(c_before + Vector2(10, 10)) < 0.05, "blok köşesi fareyi izledi")
	check(absf((sk.points[corner_pid] as Vector2).distance_to(sk.points[other_pid]) - d_before) < 1e-3, "blok şekli korundu (rijit)")
	app._exit_sketch()

	print("== Faz 3b: 3B taslak")
	await fresh_doc()
	app._cmd("sketch3d")
	check(app.mode == "sketch3d", "3B taslak modu")
	await frames(2)
	var e3: Sketch3DEditor = app.editor3d
	e3.grid_snap = true
	e3.set_plane("XY")
	send_click(app.viewport.world_to_screen(Vector3(0, 0, 0)))
	send_click(app.viewport.world_to_screen(Vector3(20, 0, 0)))
	send_click(app.viewport.world_to_screen(Vector3(20, 20, 0)))
	check(e3.sk().lines.size() == 2, "XY düzleminde iki çizgi")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	app._input(tab)
	app._input(tab)
	check(e3.plane_name == "YZ", "Tab ile düzlem değişti (YZ)")
	var p_last: Vector3 = e3.sk().points.values().back()
	var target := p_last + Vector3(0, 0, -15)
	send_click(app.viewport.world_to_screen(target))
	check(e3.sk().lines.size() == 3, "üçüncü çizgi YZ düzleminde (uzayda)")
	var zmax := 0.0
	for q in e3.sk().points.values():
		zmax = maxf(zmax, absf((q as Vector3).z))
	check(zmax > 1.0, "nokta Z yönünde (3B): %.2f" % zmax)
	app._escape()
	app._escape()
	check(app.mode == "idle" and app.doc.features.size() == 1 and app.doc.features[0].type == "sketch3d", "3B taslak ağaçta kaldı")
	var back := CadDocument.new()
	back.load_dict(app.doc.to_dict())
	check(back.features[0].sketch3d != null and back.features[0].sketch3d.lines.size() == 3, "3B taslak kaydedilip açılıyor")


func phase3() -> void:
	print("== Faz 3: kırp (fare ile)")
	await fresh_doc()
	await settle()
	app._select({"kind": "plane", "id": "front"})
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(true)
	app.editor.set_tool("line")
	sketch_click(Vector2(-20, 0))
	sketch_click(Vector2(20, 0))
	app.editor.cancel()
	sketch_click(Vector2(0, -15))
	sketch_click(Vector2(0, 15))
	app.editor.cancel()
	var sk: Sketch = app.editor.sketch()
	check(sk.entities.size() == 2, "iki kesişen çizgi")
	app.editor.set_tool("trim")
	sketch_click(Vector2(12, 0))
	sk = app.editor.sketch()
	var right_gone := true
	for e in sk.entities:
		for pid in Sketch.entity_point_ids(e):
			if (sk.points[pid] as Vector2).x > 1.0:
				right_gone = false
	check(right_gone, "tıklanan sağ parça kırpıldı")
	app._cmd("undo")
	check(app.editor.sketch().entities.size() == 2 and (app.editor.sketch().bounds().end.x > 19.0), "kırpma geri alındı")

	print("== Faz 3: köşe yuvarlatma aracı")
	await fresh_doc()
	await settle()
	app._select({"kind": "plane", "id": "top"})
	app._cmd("sketch")
	await settle()
	app.editor.set_tool("rect")
	sketch_click(Vector2(-20, -10))
	sketch_click(Vector2(20, 10))
	app.editor.set_tool("fillet")
	app.editor.fillet_radius = 4.0
	sketch_click(Vector2(20, 10))
	sk = app.editor.sketch()
	var fa := find_entity(sk, "arc")
	check(not fa.is_empty() and absf(sk.entity_radius(fa) - 4.0) < 1e-4, "köşeye tıklayınca R4 yuvarlatıldı")
	check(app.editor.selected_constraints.size() == 1, "yarıçap boyutu seçili (değiştirmeye hazır)")
	var rdim: int = app.editor.selected_constraints.keys()[0]
	app.editor.set_dimension_value(rdim, 6.0)
	check(absf(app.editor.sketch().entity_radius(app.editor.sketch().get_entity(fa["id"])) - 6.0) < 1e-4, "yarıçap boyutu 6 yapıldı")
	check((app.editor.sketch().extract_profiles()["loops"] as Array).size() == 1, "yuvarlatılmış dikdörtgen kapalı kontur")

	print("== Faz 3: ofset (seçim + panel)")
	app.editor.set_tool("select")
	app.editor.selected_entities.clear()
	for e in app.editor.sketch().entities:
		if not e.get("construction", false):
			app.editor.selected_entities[e["id"]] = true
	app._cmd("op_offset")
	check(app._sketch_op == "offset" and not app.editor.preview_paths.is_empty(), "ofset paneli + önizleme açıldı")
	app._op_params["dist"] = 3.0
	app._op_params["flip"] = true
	app._apply_offset()
	sk = app.editor.sketch()
	var loops: Array = sk.extract_profiles()["loops"]
	check(loops.size() == 2 and int(loops[1]["depth"]) == 1, "içe ofset ile et kalınlığı (2 kontur, iç delik)")
	check(app._sketch_op == "", "ofset paneli kapandı")

	print("== Faz 3: çokgen, spline, metin araçları")
	await fresh_doc()
	await settle()
	app._select({"kind": "plane", "id": "front"})
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(true)
	app.editor.set_tool("polygon")
	app.editor.polygon_sides = 6
	sketch_click(Vector2(0, 0))
	sketch_click(Vector2(10, 0))
	sk = app.editor.sketch()
	var nl := 0
	for e in sk.entities:
		if e["type"] == "line":
			nl += 1
	check(nl == 6, "altıgen çizildi")
	check(int(SketchSolver.analyze_sketch(sk)["dof"]) == 2, "merkezi orijine bağlı altıgen: 2 serbestlik")
	app.editor.set_tool("spline")
	for q in [Vector2(20, 0), Vector2(30, 10), Vector2(40, 0), Vector2(30, -10)]:
		sketch_click(q)
	sketch_click(Vector2(20, 0))
	sk = app.editor.sketch()
	var spl := find_entity(sk, "spline")
	check(not spl.is_empty() and spl["pts"][0] == spl["pts"][spl["pts"].size() - 1], "ilk noktaya tıklayınca kapalı spline oluştu")
	app.editor.set_tool("text")
	app.editor.text_default = "AB"
	app.editor.text_height = 8.0
	sketch_click(Vector2(-10, 20))
	sk = app.editor.sketch()
	var tx := find_entity(sk, "text")
	check(not tx.is_empty() and tx["text"] == "AB", "metin eklendi")
	app._edit_text(tx["id"], "DIY", -1.0)
	check(str(app.editor.sketch().get_entity(tx["id"])["text"]) == "DIY", "metin panelden değiştirildi")
	var n_loops: int = (app.editor.sketch().extract_profiles()["loops"] as Array).size()
	check(n_loops >= 6, "altıgen + spline + metin konturları (%d)" % n_loops)
	app._cmd("extrude")
	app._ok_feature()
	await settle()
	check(not app.viewport.model.is_empty() and app.doc.features[1].error == "", "metin ve spline dahil ekstrüzyon")

	print("== Faz 3: denklemler (= ile)")
	await fresh_doc()
	await settle()
	app.doc.checkpoint()
	app.doc.variables.append({"name": "genislik", "expr": "50"})
	app.doc.commit()
	app._select({"kind": "plane", "id": "front"})
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(true)
	app.editor.set_tool("rect")
	sketch_click(Vector2(0, 0))
	sketch_click(Vector2(20, 10))
	app.editor.set_tool("dimension")
	sketch_click(Vector2(10, 0))
	sketch_click(Vector2(10, -8))
	check(app.editor.is_editing_dimension(), "boyut kutusu açıldı")
	if app.editor.is_editing_dimension():
		type_into_dim_editor("=genislik")
	await frames(2)
	sk = app.editor.sketch()
	var wdim := {}
	for c in sk.constraints:
		if Sketch.is_dimension(c):
			wdim = c
	check(str(wdim.get("expr", "")) == "genislik" and absf(float(wdim["value"]) - 50.0) < 1e-4, "boyut '=genislik' ile 50 oldu")
	var lbl_sigma := false
	for l in app.editor._labels:
		if l.visible and l.text.begins_with("Σ"):
			lbl_sigma = true
	check(lbl_sigma, "denklemli boyut Σ ile gösteriliyor")
	app._exit_sketch()
	app._cmd("extrude")
	var nfe: CadFeature = app.editing
	app._set_feature_expr(nfe, "depth", "genislik / 5")
	check(absf(float(nfe.params["depth"]) - 10.0) < 1e-4, "derinlik =genislik/5 → 10")
	app._ok_feature()
	await settle()
	app._cmd("equations")
	check(app.mode == "equations", "denklemler paneli açıldı")
	app._set_variable(0, "", "80")
	await settle()
	var s_after: Sketch = app.doc.sketches()[0].sketch
	var w_after := 0.0
	for c in s_after.constraints:
		if Sketch.is_dimension(c):
			w_after = float(c["value"])
	check(absf(w_after - 80.0) < 1e-4, "değişken 80 olunca boyut güncellendi")
	check(absf(float(app.doc.features[1].params["depth"]) - 16.0) < 1e-4, "derinlik de 16 oldu")
	check(absf(app.viewport.model.aabb.size.x - 80.0) < 0.01 and absf(app.viewport.model.aabb.size.z - 16.0) < 0.01, "model 80 x 16 güncellendi")
	app._escape()


func phase2() -> void:
	print("== Faz 2: Akıllı Boyut (fare ile)")
	app._cmd("new")
	await settle()
	app._select({"kind": "plane", "id": "front"})
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(true)
	app.editor.set_tool("rect")
	sketch_click(Vector2(-20, -10))
	sketch_click(Vector2(20, 10))
	var sk: Sketch = app.editor.sketch()
	check(int(SketchSolver.analyze_sketch(sk)["dof"]) == 4, "dikdörtgen: 4 serbestlik derecesi")
	check(app.def_label.text.begins_with("Eksik Tanımlı"), "durum çubuğu: '%s'" % app.def_label.text)
	app.editor.set_tool("dimension")
	sketch_click(Vector2(0, 10))
	sketch_click(Vector2(0, 22))
	sk = app.editor.sketch()
	var dims := dims_of(sk)
	check(dims.size() == 1 and dims[0]["type"] == "hdistance", "üst kenara yatay boyut eklendi")
	check(app.editor.is_editing_dimension(), "değer kutusu açıldı (Modify)")
	if app.editor.is_editing_dimension():
		type_into_dim_editor("60")
	await frames(2)
	sk = app.editor.sketch()
	var top := sk.get_entity(dims[0]["e1"]) if dims[0].has("e1") else {}
	var w := absf((sk.points[dims[0]["p2"]] as Vector2).x - (sk.points[dims[0]["p1"]] as Vector2).x)
	check(absf(w - 60.0) < 1e-3, "yazılan değerle genişlik 60 oldu (%.4f)" % w)
	var lbl_ok := false
	for l in app.editor._labels:
		if l.visible and l.text == "60.00":
			lbl_ok = true
	check(lbl_ok, "ekranda '60.00' etiketi var")
	# Sol kenara dikey boyut: sol kenarın ortasına tıkla, sola yerleştir
	var left := {}
	for e in sk.entities:
		if e["type"] == "line":
			var a: Vector2 = sk.points[e["a"]]
			var b: Vector2 = sk.points[e["b"]]
			if absf(a.x - b.x) < 1e-6 and (left.is_empty() or a.x < (sk.points[left["a"]] as Vector2).x):
				left = e
	var lm: Vector2 = sk.line_midpoint(left)
	sketch_click(lm)
	sketch_click(lm + Vector2(-12, 0))
	if app.editor.is_editing_dimension():
		type_into_dim_editor("25")
	await frames(2)
	sk = app.editor.sketch()
	left = sk.get_entity(left["id"])
	var hgt := absf((sk.points[left["a"]] as Vector2).y - (sk.points[left["b"]] as Vector2).y)
	check(absf(hgt - 25.0) < 1e-3, "yükseklik 25 (%.4f)" % hgt)
	check(int(SketchSolver.analyze_sketch(sk)["dof"]) == 2, "artık 2 serbestlik derecesi (konum)")

	print("== Faz 2: ilişkiler")
	# Köşegen yapı çizgisi + orijine orta nokta ilişkisi = dikdörtgen ortalanır
	var corners: Array = sk.groups.values()[0]["pts"]
	var before_n: int = sk.constraints.size()
	app.editor.set_tool("centerline")
	sketch_click(sk.points[corners[0]])
	sketch_click(sk.points[corners[2]])
	app.editor.cancel()
	sk = app.editor.sketch()
	var diag := {}
	for e in sk.entities:
		if e.get("construction", false):
			diag = e
	check(not diag.is_empty(), "köşegen merkez çizgisi çizildi")
	app.editor.set_tool("select")
	app.editor.selected_entities = {diag["id"]: true}
	app.editor.selected_points = {Sketch.ORIGIN: true}
	var avail: Array = []
	for a2 in app.editor.available_relations():
		avail.append(a2[0])
	check("midpoint" in avail and "coincident" in avail, "nokta+çizgi için Orta Nokta/Çakışık öneriliyor %s" % str(avail))
	check(app.editor.add_relation("midpoint"), "orta nokta ilişkisi eklendi")
	sk = app.editor.sketch()
	var mid: Vector2 = sk.line_midpoint(sk.get_entity(diag["id"]))
	check(mid.length() < 1e-4, "dikdörtgen orijine ortalandı")
	var an := SketchSolver.analyze_sketch(sk)
	check(an["status"] == "full", "taslak tam tanımlı (%s, DOF %d)" % [an["status"], an["dof"]])
	check(app.def_label.text == "Tam Tanımlı", "durum çubuğu: Tam Tanımlı")
	# Gereksiz ilişki reddedilir
	var n_before: int = sk.constraints.size()
	app.editor.selected_points.clear()
	app.editor.selected_entities = {top["id"]: true} if not top.is_empty() else {}
	if top.is_empty():
		for e in sk.entities:
			if e["type"] == "line" and not e.get("construction", false):
				app.editor.selected_entities = {e["id"]: true}
				break
	app.editor.add_relation("horizontal")
	check(app.editor.sketch().constraints.size() == n_before, "gereksiz (zaten yatay) ilişki eklenmedi")
	# Tam tanımlı nokta sürüklenemez
	var c0: Vector2 = app.editor.sketch().points[corners[0]]
	app.editor.set_tool("select")
	send_drag(screen_of(app.editor.plane(), c0), screen_of(app.editor.plane(), c0 + Vector2(8, 5)))
	check((app.editor.sketch().points[corners[0]] as Vector2).distance_to(c0) < 1e-3, "tam tanımlı köşe sürüklemede yerinde kaldı")

	print("== Faz 2: daire, çap boyutu, eğik çizgiye yatay ilişki")
	app.editor.set_grid_snap(false)
	app.editor.set_tool("circle")
	# Köşegen yapı çizgisinden uzak bir yöne tıkla (yoksa çizgi üzerine yakalanır)
	sketch_click(Vector2(0.2, 0.1))
	sketch_click(Vector2(0, 4.6))
	sk = app.editor.sketch()
	var circ := find_entity(sk, "circle")
	check(not circ.is_empty() and circ["c"] == Sketch.ORIGIN, "daire merkezi orijin noktasına bağlandı")
	app.editor.set_tool("dimension")
	var ce: Vector2 = Vector2.from_angle(1.9) * float(circ["r"])
	sketch_click(ce)
	sketch_click(ce * 2.0)
	if app.editor.is_editing_dimension():
		type_into_dim_editor("10")
	await frames(2)
	sk = app.editor.sketch()
	check(absf(float(sk.get_entity(circ["id"])["r"]) - 5.0) < 1e-4, "çap 10 (yarıçap %.4f)" % float(sk.get_entity(circ["id"])["r"]))
	check(dims_of(sk).back()["type"] == "diameter", "daireye çap boyutu")
	app.editor.set_tool("line")
	sketch_click(Vector2(45, 3))
	sketch_click(Vector2(60, 9))
	app.editor.cancel()
	sk = app.editor.sketch()
	var slant := {}
	for e in sk.entities:
		if e["type"] == "line" and (sk.points[e["a"]] as Vector2).x > 40:
			slant = e
	app.editor.set_tool("select")
	app.editor.select_entity(slant["id"])
	check(app.editor.add_relation("horizontal"), "eğik çizgiye yatay ilişki eklendi")
	sk = app.editor.sketch()
	slant = sk.get_entity(slant["id"])
	check(absf((sk.points[slant["a"]] as Vector2).y - (sk.points[slant["b"]] as Vector2).y) < 1e-5, "çizgi yatay oldu")
	check(app.def_label.text.begins_with("Eksik Tanımlı"), "serbest çizgi taslağı eksik tanımlı yaptı")
	app.editor.select_entity(slant["id"])
	app.editor.delete_selection()
	check(app.def_label.text == "Tam Tanımlı", "serbest çizgi silinince tekrar tam tanımlı")

	print("== Faz 2: birim değiştirme")
	app._on_units_menu(3)
	await frames(1)
	check(Units.length_unit == "in" and app.units_btn.text.strip_edges() == "IPS", "IPS seçildi")
	var inch_ok := false
	for l in app.editor._labels:
		if l.visible and l.text == "2.362":
			inch_ok = true
	check(inch_ok, "60 mm boyutu '2.362' (inç) olarak gösteriliyor")
	app._cmd("undo")
	check(Units.length_unit == "mm", "birim değişikliği geri alındı")
	app._on_units_menu(0)

	print("== Faz 2: ekstrüzyon, ölç, kütle, malzeme")
	app._cmd("extrude")
	app.editing.params["depth"] = 10.0
	app._ok_feature()
	await settle()
	var tree_txt: String = app.tree.get_root().get_child(5).get_child(0).get_text(0)
	check(tree_txt == app.doc.features[0].name, "tam tanımlı taslakta (-) öneki yok: '%s'" % tree_txt)
	app.viewport.camera.set_standard_view("iso", false)
	await frames(2)
	app._cmd("measure")
	check(app.mode == "measure", "ölç modu")
	var bb: AABB = app.viewport.model.aabb
	app._measure_pick(app.viewport.world_to_screen(Vector3(bb.get_center().x + 20, bb.end.y, 5)), false)
	app._measure_pick(app.viewport.world_to_screen(Vector3(bb.position.x, bb.position.y, bb.end.z)), false)
	var res: Array = app._measure_results()
	check(app._measure_picks.size() == 2 and app._measure_picks[0]["kind"] == "face" and app._measure_picks[1]["kind"] == "vertex", "üst yüz + köşe seçildi")
	check(res.size() > 0 and str(res[0]) == "Normal mesafe: 25.00 mm", "normal mesafe = yükseklik: %s" % str(res))
	app._cmd("mass")
	check(app.mode == "mass" and not app._mass_result.is_empty(), "kütle özellikleri modu")
	var exp_v := 60.0 * 25.0 * 10.0 - PI * 25.0 * 10.0
	check(absf(float(app._mass_result["volume"]) - exp_v) / exp_v < 0.002, "hacim %.1f ≈ %.1f" % [app._mass_result["volume"], exp_v])
	app._set_material("PLA")
	await settle()
	check(absf(float(app._mass_result["mass"]) - exp_v * 1.24 / 1000.0) < 0.01, "PLA kütlesi %.3f g" % app._mass_result["mass"])
	check(app.viewport.model_mat.albedo_color.is_equal_approx(Materials.color_of("PLA")), "model rengi malzemeye göre değişti")
	var txt: String = app._mass_text()
	check(txt.contains("Kütle =") and txt.contains("Ağırlık merkezi"), "kütle raporu metni üretildi")
	app._escape()
	check(app.mode == "idle", "Esc ile kütle panelinden çıkıldı")


func _run() -> void:
	await frames(5)
	# Hata ayıklama: yalnızca bir bölümü çalıştır (-- --uitest --only=phase3b)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			await call(a.substr(7))
			print("")
			print("UI SONUÇ: %d başarılı, %d başarısız" % [passes, fails])
			get_tree().quit(1 if fails > 0 else 0)
			return
	print("== Yeni parça, Üst düzlemde taslak")
	app._cmd("new")
	await settle()
	app._select({"kind": "plane", "id": "top"})
	app._cmd("sketch")
	check(app.mode == "sketch", "taslak moduna girildi")
	check(app.editor.tool == "line", "varsayılan araç çizgi")
	await settle()
	var f: CadFeature = app.editor.feature
	check(f != null and f.plane.normal().is_equal_approx(Vector3.UP), "taslak düzlemi Üst (normal +Y)")

	print("== Dikdörtgen (fare ile)")
	app.editor.set_tool("rect")
	sketch_click(Vector2(-20, -10))
	sketch_click(Vector2(20, 10))
	var sk: Sketch = app.editor.sketch()
	check(sk.entities.size() == 4, "dikdörtgen 4 çizgi (%d)" % sk.entities.size())
	check(sk.groups.size() == 1, "dikdörtgen grubu oluştu")
	if sk.groups.size() == 1:
		var gid: int = sk.groups.keys()[0]
		var ri := sk.rect_info(gid)
		check((ri["size"] as Vector2).is_equal_approx(Vector2(40, 20)), "boyut 40 x 20 (%s)" % ri["size"])
		app.editor.edit_rect(gid, ri["pos"], Vector2(50, 20))
		check(sk.rect_info(gid)["size"].is_equal_approx(Vector2(50, 20)), "panelden genişlik 50 yapıldı")
		app.editor.edit_rect(gid, Vector2(-25, -10), Vector2(50, 20))

	print("== Daire (orijine yakalanır, ızgara kapalı)")
	app.editor.set_grid_snap(false)
	app.editor.set_tool("circle")
	sketch_click(Vector2(0.3, -0.2))
	sketch_click(Vector2(5, 0))
	sk = app.editor.sketch()
	var circle := {}
	for e in sk.entities:
		if e["type"] == "circle":
			circle = e
	check(not circle.is_empty(), "daire oluştu")
	if not circle.is_empty():
		check((sk.points[circle["c"]] as Vector2).length() < 1e-4, "merkez orijine yakalandı")
		check(absf(float(circle["r"]) - 5.0) < 1e-3, "yarıçap 5")
	var prof := sk.extract_profiles()
	check((prof["loops"] as Array).size() == 2, "2 kontur (dış + delik)")

	print("== Geri al / yinele (taslak içinde)")
	var n_before: int = sk.entities.size()
	app._cmd("undo")
	check(app.mode == "sketch" and app.editor.sketch().entities.size() == n_before - 1, "geri al: daire silindi")
	app._cmd("redo")
	check(app.editor.sketch().entities.size() == n_before, "yinele: daire geri geldi")

	print("== Ekstrüzyon")
	app._cmd("extrude")
	check(app.mode == "feature" and app.editing != null, "ekstrüzyon paneli açıldı")
	app.editing.params["depth"] = 15.0
	app._preview()
	app._ok_feature()
	await settle()
	check(app.doc.features.size() == 2, "özellik eklendi")
	var expected := 50.0 * 20.0 * 15.0 - PI * 25.0 * 15.0
	check(absf(volume() - expected) / expected < 0.005, "hacim %.1f ≈ %.1f" % [volume(), expected])
	check(app.viewport.model.aabb.end.y > 14.99 and app.viewport.model.aabb.position.y > -0.01, "katı +Y yönünde 0..15")

	print("== Yüz seçip yüzeye taslak + kesme")
	var top_pt := Vector3(15, 15, 0)
	app._pick_at(app.viewport.world_to_screen(top_pt), false)
	check(app.selection.get("kind", "") == "face" and app.selection.get("planar", false), "üst yüz seçildi (düzlemsel)")
	app._cmd("sketch")
	await settle()
	check(app.mode == "sketch" and absf(app.editor.plane().origin.y - 15.0) < 1e-3, "yüzey taslağı y=15 düzleminde")
	app.editor.set_grid_snap(false)
	app.editor.set_tool("circle")
	sketch_click(Vector2(15, 0))
	sketch_click(Vector2(18, 0))
	app._cmd("cut")
	check(app.mode == "feature" and app.editing.is_cut(), "kesme paneli açıldı")
	app.editing.params["end"] = "through"
	app._preview()
	app._ok_feature()
	await settle()
	var exp2 := expected - PI * 9.0 * 15.0
	check(absf(volume() - exp2) / exp2 < 0.005, "kesme sonrası hacim %.1f ≈ %.1f" % [volume(), exp2])

	print("== Çizgi zinciri ile kapalı üçgen + döndürme")
	app._select({"kind": "plane", "id": "front"})
	app._cmd("sketch")
	await settle()
	app.editor.set_tool("line")
	for q in [Vector2(40, 0), Vector2(50, 0), Vector2(40, 10), Vector2(40, 0)]:
		sketch_click(q)
	sk = app.editor.sketch()
	# points içinde her zaman taslak orijini (0) da bulunur
	check(sk.entities.size() == 3 and sk.points.size() - 1 == 3, "zincir kapandı: 3 çizgi, 3 ortak nokta (%d, %d)" % [sk.entities.size(), sk.points.size() - 1])
	check((sk.extract_profiles()["loops"] as Array).size() == 1, "kapalı kontur")
	check(app.editor._stage == 0, "kapatınca zincir bitti")
	# Nokta sürükleme: bağlı iki çizgi birlikte uzamalı
	app.editor.set_tool("select")
	send_drag(screen_of(app.editor.plane(), Vector2(50, 0)), screen_of(app.editor.plane(), Vector2(60, 0)))
	sk = app.editor.sketch()
	var moved := false
	for pv in sk.points.values():
		if (pv as Vector2).is_equal_approx(Vector2(60, 0)):
			moved = true
	check(moved and sk.entities.size() == 3, "nokta sürüklendi, çizgiler bağlı kaldı")
	check((sk.extract_profiles()["loops"] as Array).size() == 1, "sürüklemeden sonra kontur hâlâ kapalı")
	app._cmd("undo")
	sk = app.editor.sketch()
	var back := false
	for pv in sk.points.values():
		if (pv as Vector2).is_equal_approx(Vector2(50, 0)):
			back = true
	check(back, "sürükleme tek adımda geri alındı")
	# Klavye kısayolu: Esc ile seçim temizlenir, ikinci Esc taslaktan çıkmaz (araç seç modunda)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	app._unhandled_key_input(esc)
	check(app.mode == "sketch", "Esc taslak modunu korur (seçim temizlendi)")
	app._cmd("revolve")
	check(app.mode == "feature" and app.editing.type == "revolve", "döndürme paneli açıldı")
	app._ok_feature()
	await settle()
	var rev_f: CadFeature = app.doc.features[app.doc.features.size() - 1]
	check(rev_f.type == "revolve" and rev_f.error == "", "döndürme hatasız")
	# Üçgen kesit (40..50 x 0..10) Y ekseni etrafında: V = 2π * x̄ * A, x̄ = 43.33, A = 50
	var exp_rev := TAU * (130.0 / 3.0) * 50.0
	check(absf(volume() - exp2 - exp_rev) / exp_rev < 0.01, "döndürme hacmi eklendi (%.1f)" % (volume() - exp2))

	print("== Özellik düzenleme ve silme")
	var ext_f: CadFeature = app.doc.features[1]
	app._edit_feature(ext_f)
	app.editing.params["depth"] = 20.0
	app._ok_feature()
	await settle()
	check(absf(float(app.doc.features[1].params["depth"]) - 20.0) < 1e-6, "derinlik 20 olarak güncellendi")
	check(app.viewport.model.aabb.end.y > 19.99, "model yüksekliği 20")
	app._select({"kind": "feature", "id": rev_f.id})
	app._cmd("delete")
	await settle()
	check(app.doc.get_feature(rev_f.id) == null, "döndürme silindi")
	app._cmd("undo")
	await settle()
	check(app.doc.get_feature(rev_f.id) != null, "silme geri alındı")

	print("== Kaydet / aç / dışa aktar")
	var tmp := OS.get_user_data_dir().path_join("uitest")
	DirAccess.make_dir_recursive_absolute(tmp)
	var path := tmp.path_join("ui.dcad")
	app.doc.save_to(path)
	var before := JSON.stringify(app.doc.to_dict())
	var vol_before := volume()
	app._cmd("new")
	await settle()
	check(app.doc.features.is_empty(), "yeni belge boş")
	app._pending_file_action = "open"
	app._on_file_selected(path)
	await settle()
	check(JSON.stringify(app.doc.to_dict()) == before, "açılan belge aynı")
	check(absf(volume() - vol_before) < 0.5, "açılan modelin hacmi aynı")
	if FileAccess.file_exists(tmp.path_join("ui.stl")):
		DirAccess.remove_absolute(tmp.path_join("ui.stl"))
	app._pending_file_action = "stl"
	app._on_file_selected(tmp.path_join("ui.stl"))
	if app.viewport.kernel.is_brep():
		await app.viewport.kernel.export_done
	check(FileAccess.file_exists(tmp.path_join("ui.stl")), "STL dosyası yazıldı")
	app._select({"kind": "feature", "id": app.doc.features[0].id})
	app._pending_file_action = "dxf"
	app._on_file_selected(tmp.path_join("ui.dxf"))
	check(FileAccess.get_file_as_string(tmp.path_join("ui.dxf")).contains("CIRCLE"), "DXF yazıldı (daire içeriyor)")

	await phase2()
	await phase3()
	await phase3b()
	await phase4()
	await phase4b()
	await phase5()
	await phase5b()
	await phase6()
	await phase7()
	await phase7b()
	await phase8()
	await phase8b()
	await phase9()
	await phase9b()

	print("")
	print("UI SONUÇ: %d başarılı, %d başarısız" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)


func phase4() -> void:
	if not app.viewport.kernel.is_brep():
		print("== Faz 4 atlandı (OpenCASCADE çekirdeği etkin değil)")
		return
	print("== Faz 4: B-rep kutu + kenar tıklayarak köşe yuvarlatma")
	await fresh_doc()
	app._select({"kind": "plane", "id": "top"})
	app._cmd("sketch")
	await settle()
	app.editor.set_tool("rect")
	sketch_click(Vector2(-20, -10))
	sketch_click(Vector2(20, 10))
	app._cmd("extrude")
	app.editing.params["depth"] = 10.0
	app._preview()
	app._ok_feature()
	await settle()
	check(absf(volume() - 8000.0) < 1e-6, "kutu hacmi kesin 8000 (%.6f)" % volume())
	check(app.viewport.model.has_brep(), "model B-rep yüz/kenar bilgisi taşıyor")
	check(app.viewport.model.brep_edges.size() == 12, "12 gerçek kenar çizildi")
	app.viewport.camera.set_standard_view("iso")
	await settle()
	app._fit(false)
	await settle()
	app._cmd("fillet3d")
	await settle()
	check(app.mode == "feature" and app.editing != null and app.editing.type == "fillet", "köşe yuvarlatma paneli açıldı")
	check(bool(app.viewport.kernel.brep.get("before", false)), "seçim için özellikten önceki gövde gösteriliyor")
	var edge_pt: Vector2 = app.viewport.world_to_screen(Vector3(20, 5, 10))
	send_click(edge_pt)
	await settle()
	check((app.editing.params["edges"] as Array).size() == 1, "dikey kenar tıklanarak seçildi (%d)" % (app.editing.params["edges"] as Array).size())
	send_click(app.viewport.world_to_screen(Vector3(0, 10, 0)))
	await settle()
	check((app.editing.params["edges"] as Array).size() == 5, "üst yüze tıklama 4 kenarını ekledi (%d)" % (app.editing.params["edges"] as Array).size())
	send_click(app.viewport.world_to_screen(Vector3(0, 10, 0)))
	await settle()
	check((app.editing.params["edges"] as Array).size() == 1, "aynı yüze tekrar tıklama kenarlarını kaldırdı")
	app.editing.params["r"] = 2.0
	app._preview()
	await settle()
	check(app.editing.error == "", "önizleme hatasız")
	app._ok_feature()
	await settle()
	var v_f := 8000.0 - (4.0 - PI) * 10.0
	check(absf(volume() - v_f) < 1e-4, "yuvarlatılmış hacim %.4f ≈ %.4f" % [volume(), v_f])
	var cyl := 0
	for f in app.viewport.model.brep_faces:
		if f["type"] == "cylinder":
			cyl += 1
	check(cyl == 1, "bir silindirik yüz oluştu")

	print("== Faz 4: yüz tıklayarak kabuk")
	app._cmd("shell")
	await settle()
	check(app.mode == "feature" and app.editing.type == "shell", "kabuk paneli açıldı")
	send_click(app.viewport.world_to_screen(Vector3(-5, 10, 2)))
	await settle()
	check((app.editing.params["faces"] as Array).size() == 1, "üst yüz kaldırılacak yüz olarak seçildi")
	app.editing.params["t"] = 1.0
	app._ok_feature()
	await settle()
	var v_s := v_f - (38.0 * 18.0 - (1.0 - PI / 4.0)) * 9.0
	check(absf(volume() - v_s) < 1e-3, "kabuk hacmi %.4f ≈ %.4f" % [volume(), v_s])
	var last: CadFeature = app.doc.features[app.doc.features.size() - 1]
	check(last.type == "shell" and last.error == "", "ağaçta Kabuk özelliği hatasız")
	app._cmd("undo")
	await settle()
	check(absf(volume() - v_f) < 1e-4, "geri al: kabuk kaldırıldı")
	app._cmd("redo")
	await settle()
	check(absf(volume() - v_s) < 1e-3, "yinele: kabuk geri geldi")

	print("== Faz 4: önceden seçili yüzle pah, iptal")
	app._pick_at(app.viewport.world_to_screen(Vector3(20, 5, 0)), false)
	check(app.selection.get("kind", "") == "face" and int(app.selection.get("face", -1)) >= 0, "yan yüz seçildi (B-rep yüz kimliği)")
	app._cmd("chamfer3d")
	await settle()
	check(app.mode == "feature" and (app.editing.params["edges"] as Array).size() >= 4, "pah: seçili yüzün kenarları eklendi (%d)" % (app.editing.params["edges"] as Array).size())
	app._cancel_feature()
	await settle()
	check(app.mode == "idle" and absf(volume() - v_s) < 1e-3, "iptal: model değişmedi")

	print("== Faz 4: STEP dışa aktarma ve çekirdek paneli")
	var tmp := OS.get_user_data_dir().path_join("uitest")
	var sp := tmp.path_join("faz4.step")
	if FileAccess.file_exists(sp):
		DirAccess.remove_absolute(sp)
	app._pending_file_action = "step"
	app._on_file_selected(sp)
	var r: Dictionary = await app.viewport.kernel.export_done
	check(bool(r.get("ok", false)) and FileAccess.file_exists(sp), "STEP dosyası yazıldı")
	app._cmd("kernel_options")
	check(app.mode == "kernel", "çekirdek paneli açıldı")
	app._leave_aux_mode()
	check(app.mode == "idle", "çekirdek paneli kapandı")
	var path := tmp.path_join("faz4.dcad")
	app.doc.save_to(path)
	app.doc.dirty = false
	app._cmd("new")
	await settle()
	app._pending_file_action = "open"
	app._on_file_selected(path)
	await settle()
	check(absf(volume() - v_s) < 1e-3, "kaydedilip açılan B-rep parça aynı hacimde")


func box_ui(depth := 10.0) -> void:
	await fresh_doc()
	app._select({"kind": "plane", "id": "top"})
	app._cmd("sketch")
	await settle()
	app.editor.set_tool("rect")
	sketch_click(Vector2(-20, -10))
	sketch_click(Vector2(20, 10))
	app._cmd("extrude")
	app.editing.params["depth"] = depth
	app._preview()
	app._ok_feature()
	await settle()
	app.viewport.camera.set_standard_view("iso")
	await settle()
	app._fit(false)
	await settle()


func phase4b() -> void:
	if not app.viewport.kernel.is_brep():
		print("== Faz 4b atlandı (OpenCASCADE çekirdeği etkin değil)")
		return
	print("== Faz 4b: eğim (tarafsız üst yüz, iki yan yüz)")
	await box_ui()
	app._cmd("draft")
	await settle()
	check(app.mode == "feature" and app.editing.type == "draft", "eğim paneli açıldı")
	app._toggle_draft_neutral()
	send_click(app.viewport.world_to_screen(Vector3(-5, 10, 2)))
	await settle()
	check(not (app.editing.params["neutral"] as Dictionary).is_empty(), "tarafsız yüz tıklanarak seçildi")
	send_click(app.viewport.world_to_screen(Vector3(0, 5, 10)))
	await settle()
	send_click(app.viewport.world_to_screen(Vector3(20, 5, 0)))
	await settle()
	check((app.editing.params["faces"] as Array).size() == 2, "iki yan yüz seçildi (%d)" % (app.editing.params["faces"] as Array).size())
	app.editing.params["angle"] = 5.0
	app._ok_feature()
	await settle()
	var k := 10.0 * tan(deg_to_rad(5.0))
	var v_d := 10.0 / 6.0 * (800.0 + 4.0 * (40.0 - k / 2.0) * (20.0 - k / 2.0) + (40.0 - k) * (20.0 - k))
	var last: CadFeature = app.doc.features[app.doc.features.size() - 1]
	check(last.type == "draft" and last.error == "", "Eğim özelliği hatasız (%s)" % last.error)
	check(absf(volume() - v_d) < 1e-3, "eğimli hacim %.4f ≈ %.4f" % [volume(), v_d])

	print("== Faz 4b: değişken yarıçap ve iki mesafeli pah (panel parametreleri)")
	await box_ui()
	app._cmd("fillet3d")
	await settle()
	send_click(app.viewport.world_to_screen(Vector3(20, 5, 10)))
	await settle()
	app.editing.params["r"] = 2.0
	app.editing.params["variable"] = true
	app.editing.params["r2"] = 4.0
	app._ok_feature()
	await settle()
	var exp_v := 8000.0 - (1.0 - PI / 4.0) * (64.0 - 8.0) / 0.6
	check(absf(volume() - exp_v) / exp_v < 3e-5, "değişken yarıçaplı yuvarlatma hacmi %.3f ≈ %.3f" % [volume(), exp_v])
	app._cmd("chamfer3d")
	await settle()
	send_click(app.viewport.world_to_screen(Vector3(0, 10, 10)))
	await settle()
	check((app.editing.params["edges"] as Array).size() == 1, "üst ön kenar seçildi")
	app.editing.params["mode"] = "dist2"
	app.editing.params["d"] = 1.0
	app.editing.params["d2"] = 1.5
	app._ok_feature()
	await settle()
	var lastc: CadFeature = app.doc.features[app.doc.features.size() - 1]
	check(lastc.type == "chamfer" and lastc.error == "", "iki mesafeli pah hatasız (%s)" % lastc.error)
	# Pah teğet zincir boyunca (yuvarlatmanın üst kenarı) ilerler: düz kenar payından fazlası kalkar
	check(volume() < exp_v - 30.0 and volume() > exp_v - 80.0, "pah hacmi düşürdü (%.3f)" % volume())

	print("== Faz 4b: ayrı gövde, tıklayarak birleştir, taşı, böl")
	await box_ui()
	app._select({"kind": "plane", "id": "top"})
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(false)
	app.editor.set_tool("circle")
	sketch_click(Vector2(20, 0))
	sketch_click(Vector2(25, 0))
	app._cmd("extrude")
	app.editing.params["depth"] = 20.0
	app.editing.params["merge"] = false
	app._preview()
	app._ok_feature()
	await settle()
	check(int(app.viewport.model.exact_mass.get("solids", 0)) == 2, "birleştirme kapalı: iki gövde")
	app._fit(false)
	await settle()
	app._cmd("combine")
	await settle()
	send_click(app.viewport.world_to_screen(Vector3(-10, 10, 0)))
	await settle()
	send_click(app.viewport.world_to_screen(Vector3(20, 20, 0)))
	await settle()
	check((app.editing.params["bodies"] as Array).size() == 2, "iki gövde tıklanarak seçildi (%d)" % (app.editing.params["bodies"] as Array).size())
	app.editing.params["op"] = "add"
	app._ok_feature()
	await settle()
	var vadd := 8000.0 + PI * 25.0 * 20.0 - PI * 25.0 / 2.0 * 10.0
	check(int(app.viewport.model.exact_mass.get("solids", 0)) == 1 and absf(volume() - vadd) < 1e-2, "birleştirildi: tek gövde, hacim %.3f" % volume())
	app._cmd("move_body")
	await settle()
	send_click(app.viewport.world_to_screen(Vector3(-10, 10, 0)))
	await settle()
	check(not (app.editing.params["body"] as Dictionary).is_empty(), "taşınacak gövde seçildi")
	app.editing.params["t"] = [0.0, 30.0, 0.0]
	app.editing.params["copy"] = true
	app._ok_feature()
	await settle()
	check(int(app.viewport.model.exact_mass.get("solids", 0)) == 2 and absf(volume() - 2.0 * vadd) < 1e-2, "kopyalandı: iki gövde")
	app._cmd("split")
	await settle()
	app.editing.params["plane"] = "right"
	app.editing.params["keep"] = "both"
	app._ok_feature()
	await settle()
	check(int(app.viewport.model.exact_mass.get("solids", 0)) == 4, "sağ düzlemle bölündü: 4 gövde (%d)" % int(app.viewport.model.exact_mass.get("solids", 0)))
	app._cmd("undo")
	await settle()
	check(int(app.viewport.model.exact_mass.get("solids", 0)) == 2, "geri al: bölme kaldırıldı")

	print("== Faz 4b: kaburga")
	await fresh_doc()
	app._select({"kind": "plane", "id": "front"})
	app._cmd("sketch")
	await settle()
	var sk: Sketch = app.editor.sketch()
	var lp := [Vector2(0, 0), Vector2(60, 0), Vector2(60, 5), Vector2(5, 5), Vector2(5, 60), Vector2(0, 60)]
	var pids: Array = []
	for q in lp:
		pids.append(sk.add_point(q))
	for i in pids.size():
		sk.add_line(pids[i], pids[(i + 1) % pids.size()])
	app._cmd("extrude")
	app.editing.params["end"] = "midplane"
	app.editing.params["depth"] = 40.0
	app._ok_feature()
	await settle()
	var v_l := volume()
	app._select({"kind": "plane", "id": "front"})
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(false)
	app.editor.set_tool("line")
	sketch_click(Vector2(5, 45))
	sketch_click(Vector2(45, 5))
	app.editor.cancel()
	app._cmd("rib")
	await settle()
	check(app.mode == "feature" and app.editing.type == "rib", "kaburga paneli açıldı")
	app.editing.params["t"] = 4.0
	app._ok_feature()
	await settle()
	var rib_f: CadFeature = app.doc.features[app.doc.features.size() - 1]
	check(rib_f.type == "rib" and rib_f.error == "", "kaburga hatasız (%s)" % rib_f.error)
	check(absf(volume() - v_l - 3200.0) < 0.05, "kaburga hacmi %.3f ≈ 3200" % (volume() - v_l))

	print("== Faz 4b: yüzey taslağı modelle birlikte kayar")
	await box_ui()
	app._pick_at(app.viewport.world_to_screen(Vector3(-5, 10, 2)), false)
	check(app.selection.get("kind", "") == "face", "üst yüz seçildi")
	app._cmd("sketch")
	await settle()
	check(str(app.editor.plane().support.get("name", "")) != "", "taslak destek yüzüne bağlandı (%s)" % str(app.editor.plane().support.get("name", "")))
	var sup_id: int = app.editor.feature.id
	app.editor.set_grid_snap(false)
	app.editor.set_tool("circle")
	var c0: Vector2 = app.editor.plane().to_local(Vector3(0, 10, 0))
	sketch_click(c0)
	sketch_click(c0 + Vector2(3, 0))
	app._cmd("extrude")
	app.editing.params["depth"] = 5.0
	app._ok_feature()
	await settle()
	var v0 := volume()
	check(absf(v0 - (8000.0 + PI * 9.0 * 5.0)) < 1e-3, "çıkıntı üst yüzde (%.3f)" % v0)
	var base_ext: CadFeature = app.doc.features[1]
	app._edit_feature(base_ext)
	app.editing.params["depth"] = 18.0
	app._ok_feature()
	await settle()
	await settle()
	var sup_f: CadFeature = app.doc.get_feature(sup_id)
	check(absf(sup_f.plane.origin.y - 18.0) < 1e-6, "taslak düzlemi yeni üst yüze kaydı (y=%.3f)" % sup_f.plane.origin.y)
	check(absf(volume() - (40.0 * 20.0 * 18.0 + PI * 9.0 * 5.0)) < 1e-3, "çıkıntı yeni yükseklikte (%.3f)" % volume())


func phase5() -> void:
	if not app.viewport.kernel.is_brep():
		print("== Faz 5 atlandı (OpenCASCADE çekirdeği etkin değil)")
		return
	print("== Faz 5: referans düzlem, üzerine taslak, düzlemi taşıma")
	await fresh_doc()
	app._select({"kind": "plane", "id": "top"})
	app._cmd("refplane")
	await settle()
	check(app.mode == "feature" and app.editing.type == "refplane", "referans düzlem paneli açıldı")
	check(str(app.editing.params.get("base", "")) == "top", "seçili ana düzlem taban oldu")
	app.editing.params["dist"] = 20.0
	app._preview()
	app._ok_feature()
	await settle()
	var rp: CadFeature = app.doc.features[app.doc.features.size() - 1]
	check(rp.type == "refplane" and rp.plane != null and absf(rp.plane.origin.y - 20.0) < 1e-6, "Düzlem1 y=20'de")
	var S: float = app.viewport.plane_half * 0.6
	app._pick_at(app.viewport.world_to_screen(rp.plane.to_world(Vector2(S, 0))), false)
	check(app.selection.get("id", -1) == rp.id, "referans düzlem kenarına tıklanarak seçildi")
	app._cmd("sketch")
	await settle()
	check(app.mode == "sketch" and app.editor.plane().ref == rp.id, "taslak referans düzleme bağlandı")
	app.editor.set_tool("rect")
	sketch_click(Vector2(-10, -10))
	sketch_click(Vector2(10, 10))
	app._cmd("extrude")
	app.editing.params["depth"] = 5.0
	app._ok_feature()
	await settle()
	check(absf(volume() - 2000.0) < 1e-6 and app.viewport.model.aabb.position.y > 19.99, "referans düzlemden ekstrüzyon (y 20..25)")
	app._edit_feature(rp)
	app.editing.params["dist"] = 30.0
	app._ok_feature()
	await settle()
	check(app.viewport.model.aabb.position.y > 29.99, "düzlem 30'a taşınınca katı da taşındı")

	print("== Faz 5: Yüzeye Kadar (hedef yüz tıklanarak)")
	await box_ui()
	app._select({"kind": "plane", "id": "top"})
	app._cmd("sketch")
	await settle()
	app.editor.set_tool("rect")
	sketch_click(Vector2(30, -10))
	sketch_click(Vector2(40, 10))
	app._cmd("extrude")
	app.editing.params["depth"] = 30.0
	app.editing.params["merge"] = false
	app._ok_feature()
	await settle()
	app._fit(false)
	await settle()
	app._pick_at(app.viewport.world_to_screen(Vector3(-5, 10, 2)), false)
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(false)
	app.editor.set_tool("circle")
	var c0: Vector2 = app.editor.plane().to_local(Vector3(0, 10, 0))
	sketch_click(c0)
	sketch_click(c0 + Vector2(3, 0))
	app._cmd("extrude")
	app.editing.params["end"] = "face"
	app._preview()
	app._show_feature_panel()
	app._set_pick_target("face")
	send_click(app.viewport.world_to_screen(Vector3(35, 30, 0)))
	await settle()
	check(not (app.editing.params.get("face", {}) as Dictionary).is_empty(), "hedef yüz tıklanarak seçildi")
	app._ok_feature()
	await settle()
	var last: CadFeature = app.doc.features[app.doc.features.size() - 1]
	var vexp := 8000.0 + 10.0 * 20.0 * 30.0 + PI * 9.0 * 20.0
	check(last.error == "" and absf(volume() - vexp) < 0.05, "silindir hedef yüzün düzlemine kadar (hacim %.2f ≈ %.2f) %s" % [volume(), vexp, last.error])

	print("== Faz 5: delik sihirbazı (iki tıklama) ve doğrusal çoğaltma")
	await box_ui()
	app._cmd("hole")
	await settle()
	check(app.mode == "feature" and app.editing.type == "hole", "delik sihirbazı açıldı")
	send_click(app.viewport.world_to_screen(Vector3(-10, 10, 0)))
	await settle()
	send_click(app.viewport.world_to_screen(Vector3(10, 10, 0)))
	await settle()
	check((app.editing.params["points"] as Array).size() == 2, "iki delik konumu tıklandı (%d)" % (app.editing.params["points"] as Array).size())
	app._ok_feature()
	await settle()
	var hole_f: CadFeature = app.doc.features[app.doc.features.size() - 1]
	var vh := 8000.0 - 2.0 * PI * 3.3 * 3.3 * 10.0
	check(hole_f.type == "hole" and hole_f.error == "" and absf(volume() - vh) < 0.05, "iki M6 geçiş deliği (hacim %.2f ≈ %.2f)" % [volume(), vh])
	app._select({"kind": "feature", "id": hole_f.id})
	app._cmd("lpattern")
	await settle()
	check(app.mode == "feature" and hole_f.id in app.editing.params["features"], "seçili delik çoğaltmaya eklendi")
	app.editing.params["dir1"] = "z"
	app.editing.params["spacing1"] = 6.65
	app.editing.params["count1"] = 2
	app._ok_feature()
	await settle()
	var vp := 8000.0 - 4.0 * PI * 3.3 * 3.3 * 10.0
	check(absf(volume() - vp) < 0.05, "doğrusal çoğaltma: 4 delik (hacim %.2f)" % volume())

	print("== Faz 5: kubbe (yüz tıklanarak)")
	await fresh_doc()
	app._select({"kind": "plane", "id": "top"})
	app._cmd("sketch")
	await settle()
	app.editor.set_tool("circle")
	sketch_click(Vector2(0, 0))
	sketch_click(Vector2(10, 0))
	app._cmd("extrude")
	app.editing.params["depth"] = 10.0
	app._ok_feature()
	await settle()
	app.viewport.camera.set_standard_view("iso")
	await settle()
	app._fit(false)
	await settle()
	app._cmd("dome")
	await settle()
	send_click(app.viewport.world_to_screen(Vector3(0, 10, 0)))
	await settle()
	app.editing.params["height"] = 10.0
	app._ok_feature()
	await settle()
	var vd := PI * 1000.0 + 2.0 / 3.0 * PI * 1000.0
	check(absf(volume() - vd) / vd < 0.01, "kubbe hacmi %.1f ≈ %.1f" % [volume(), vd])

	print("== Faz 5: süpürme ve loft komutları")
	await fresh_doc()
	app._select({"kind": "plane", "id": "front"})
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(false)
	app.editor.set_tool("circle")
	sketch_click(Vector2(0, 0))
	sketch_click(Vector2(5, 0))
	var prof_id: int = app.editor.feature.id
	app._exit_sketch()
	app._select({"kind": "plane", "id": "top"})
	app._cmd("sketch")
	await settle()
	app.editor.set_tool("line")
	sketch_click(Vector2(0, 0))
	sketch_click(Vector2(0, -30))
	app.editor.cancel()
	app._exit_sketch()
	await settle()
	app._select({"kind": "feature", "id": prof_id})
	app._cmd("sweep")
	await settle()
	check(app.mode == "feature" and app.editing.type == "sweep" and int((app.editing.params["path"] as Dictionary).get("id", 0)) > 0, "süpürme: profil ve yol otomatik seçildi")
	app._ok_feature()
	await settle()
	check(absf(volume() - PI * 25.0 * 30.0) < 0.05, "süpürme hacmi %.2f ≈ %.2f" % [volume(), PI * 25.0 * 30.0])
	await fresh_doc()
	app._select({"kind": "plane", "id": "top"})
	app._cmd("sketch")
	await settle()
	app.editor.set_tool("rect")
	sketch_click(Vector2(-10, -10))
	sketch_click(Vector2(10, 10))
	app._exit_sketch()
	app._select({"kind": "plane", "id": "top"})
	app._cmd("refplane")
	app.editing.params["dist"] = 10.0
	app._ok_feature()
	await settle()
	var rp2: CadFeature = app.doc.features[app.doc.features.size() - 1]
	app._select({"kind": "feature", "id": rp2.id})
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(false)
	app.editor.set_tool("rect")
	sketch_click(Vector2(-5, -5))
	sketch_click(Vector2(5, 5))
	app._cmd("loft")
	await settle()
	check(app.mode == "feature" and (app.editing.params["sketches"] as Array).size() == 2, "loft: iki profil otomatik seçildi")
	app.editing.params["ruled"] = true
	app._ok_feature()
	await settle()
	check(absf(volume() - 10.0 / 3.0 * 700.0) < 0.05, "loft hacmi %.2f ≈ 2333.33" % volume())

	print("== Faz 5: geri alma çubuğu, taşıma, ebeveyn/çocuk (arayüz)")
	var n_before := volume()
	var loft_f: CadFeature = app.doc.features[app.doc.features.size() - 1]
	app._set_rollback(app.doc.index_of(loft_f.id))
	await settle()
	check(app.doc.rollback >= 0 and app.viewport.model.is_empty(), "geri alma çubuğu loftun önünde: model boş")
	var has_bar := false
	for it in app.tree.get_root().get_children():
		if str(it.get_text(0)).contains("Geri alma"):
			has_bar = true
	check(has_bar, "ağaçta geri alma çubuğu görünüyor")
	app._cmd("undo")
	await settle()
	check(app.doc.rollback < 0 and absf(volume() - n_before) < 1e-6, "geri al: çubuk kaldırıldı")
	check(not app._move_feature(loft_f.id, 0), "loft profillerinin önüne taşınamaz")
	app._show_parents(loft_f)
	check(app.info_dialog.dialog_text.contains("Ebeveynler") and app.info_dialog.dialog_text.contains("Taslak"), "ebeveyn/çocuk penceresi profilleri listeliyor")
	app.info_dialog.hide()


func phase5b() -> void:
	if not app.viewport.kernel.is_brep():
		print("== Faz 5b atlandı (OpenCASCADE çekirdeği etkin değil)")
		return
	print("== Faz 5b: silindire teğet düzlem, sarma ve kabartma")
	await fresh_doc()
	app._select({"kind": "plane", "id": "top"})
	app._cmd("sketch")
	await settle()
	app.editor.set_tool("circle")
	sketch_click(Vector2(0, 0))
	sketch_click(Vector2(20, 0))
	app._cmd("extrude")
	app.editing.params["depth"] = 40.0
	app._ok_feature()
	await settle()
	app.viewport.camera.set_standard_view("iso")
	await settle()
	app._fit(false)
	await settle()
	var vc := PI * 400.0 * 40.0
	app._cmd("refplane")
	app.editing.params["mode"] = "tangent"
	app._show_feature_panel()
	app._set_pick_target("tan_face")
	send_click(app.viewport.world_to_screen(Vector3(0, 20, 20)))
	await settle()
	var tn: Array = app.editing.params.get("tan_n", [0, 0, 0])
	check(absf(float(tn[2]) - 1.0) < 1e-3, "silindirde tıklanan noktada radyal normal (%s)" % str(tn))
	app._ok_feature()
	await settle()
	var tp: CadFeature = app.doc.features[app.doc.features.size() - 1]
	check(tp.type == "refplane" and tp.plane != null and absf(tp.plane.origin.z - 20.0) < 0.05, "teğet düzlem z=20'de")
	app._select({"kind": "feature", "id": tp.id})
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(false)
	var o2: Vector2 = app.editor.plane().to_local(Vector3(0, 20, 20))
	app.editor.set_tool("rect")
	sketch_click(o2 + Vector2(-5, -10))
	sketch_click(o2 + Vector2(5, 10))
	app._cmd("wrap")
	await settle()
	check(app.mode == "feature" and app.editing.type == "wrap", "sarma paneli açıldı")
	app._set_pick_target("face")
	send_click(app.viewport.world_to_screen(Vector3(-14.14, 30, 14.14)))
	await settle()
	app.editing.params["depth"] = 2.0
	app._ok_feature()
	await settle()
	var wr: CadFeature = app.doc.features[app.doc.features.size() - 1]
	check(wr.type == "wrap" and wr.error == "" and absf(volume() - vc - 420.0) < 0.05, "sarma kabartma +%.3f ≈ 420 %s" % [volume() - vc, wr.error])
	app._select({"kind": "feature", "id": tp.id})
	app._cmd("sketch")
	await settle()
	app.editor.set_grid_snap(false)
	app.editor.set_tool("circle")
	var o3: Vector2 = app.editor.plane().to_local(Vector3(10, 20, 20))
	sketch_click(o3)
	sketch_click(o3 + Vector2(3, 0))
	var v_before := volume()
	app._cmd("emboss")
	await settle()
	check(app.mode == "feature" and app.editing.type == "emboss", "kabartma paneli açıldı")
	app.editing.params["depth"] = 1.0
	app._ok_feature()
	await settle()
	var add := volume() - v_before
	check(add > PI * 9.0 * 0.9 and add < PI * 9.0 * 1.2, "kabartma silindir yüzeyine eklendi (+%.3f)" % add)

	print("== Faz 5b: koordinat sistemi ve kütle özellikleri")
	app._cmd("refcsys")
	app.editing.params["x"] = "z"
	app.editing.params["y"] = "x"
	app._ok_feature()
	await settle()
	var csf: CadFeature = app.doc.features[app.doc.features.size() - 1]
	check(csf.type == "refcsys" and csf.error == "", "koordinat sistemi oluşturuldu")
	app._cmd("mass")
	var gc: Vector3 = app._mass_result["center"]
	app._mass_csys = csf.id
	app._compute_mass()
	var m: Dictionary = app._mass_result
	check(absf(float(m["cx"]) - gc.z) < 1e-6 and absf(float(m["cy"]) - gc.x) < 1e-6 and absf(float(m["cz"]) - gc.y) < 1e-6, "ağırlık merkezi koordinat sisteminde (%.3f, %.3f, %.3f)" % [m["cx"], m["cy"], m["cz"]])
	app._mass_csys = -1
	app._leave_aux_mode()

	print("== Faz 5b: projeksiyon eğrisi ve eğri güdümlü çoğaltma")
	await box_ui()
	app._select({"kind": "plane", "id": "top"})
	app._cmd("refplane")
	app.editing.params["dist"] = 20.0
	app._ok_feature()
	await settle()
	var rp: CadFeature = app.doc.features[app.doc.features.size() - 1]
	app._select({"kind": "feature", "id": rp.id})
	app._cmd("sketch")
	await settle()
	app.editor.set_tool("line")
	sketch_click(Vector2(-15, 0))
	sketch_click(Vector2(15, 0))
	app.editor.cancel()
	var src_id: int = app.editor.feature.id
	app._exit_sketch()
	await settle()
	app._select({"kind": "feature", "id": src_id})
	app._cmd("projcurve")
	await settle()
	check(app.mode == "feature" and app.editing.type == "projcurve", "projeksiyon eğrisi paneli açıldı")
	app._set_pick_target("face")
	send_click(app.viewport.world_to_screen(Vector3(-5, 10, 4)))
	await settle()
	app._ok_feature()
	await settle()
	var pc: CadFeature = app.doc.features[app.doc.features.size() - 1]
	var poly: Array = pc.runtime.get("poly", [])
	check(pc.type == "projcurve" and pc.error == "" and not poly.is_empty() and absf(float(poly[0][0][1]) - 10.0) < 1e-4, "eğri üst yüze izdüştü %s" % pc.error)
	app._cmd("hole")
	await settle()
	send_click(app.viewport.world_to_screen(Vector3(-15, 10, 0)))
	await settle()
	app._ok_feature()
	await settle()
	var hole_f: CadFeature = app.doc.features[app.doc.features.size() - 1]
	app._select({"kind": "feature", "id": hole_f.id})
	app._cmd("cvpattern")
	await settle()
	check(app.mode == "feature" and int((app.editing.params["curve"] as Dictionary).get("id", 0)) == pc.id, "eğri güdümlü çoğaltma: projeksiyon eğrisi seçildi")
	app.editing.params["count"] = 3
	app._ok_feature()
	await settle()
	var vexp := 8000.0 - 3.0 * PI * 3.3 * 3.3 * 10.0
	check(absf(volume() - vexp) < 0.05, "eğri boyunca 3 delik (hacim %.2f ≈ %.2f)" % [volume(), vexp])


# ---------------------------------------------------------------- Faz 6: teknik resim

func dw_settle() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		if not app.viewport.kernel.is_busy() and app._dw_pending == 0:
			break
	await frames(2)


func dw_event(pos_sheet: Vector2, pressed: bool, dbl := false) -> void:
	var c: DrawingCanvas = app.drawing_canvas
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = c.to_screen(pos_sheet)
	ev.pressed = pressed
	ev.double_click = dbl
	c._gui_input(ev)


func dw_click(p: Vector2) -> void:
	dw_event(p, true)
	dw_event(p, false)


func dw_drag(from: Vector2, to: Vector2) -> void:
	var c: DrawingCanvas = app.drawing_canvas
	dw_event(from, true)
	for i in 5:
		var mm := InputEventMouseMotion.new()
		mm.position = c.to_screen(from.lerp(to, float(i + 1) / 5.0))
		c._gui_input(mm)
	dw_event(to, false)


func dw_view(type: String, key := "", val := "") -> Dictionary:
	var sh: Dictionary = app._dw_sheet()
	for v in sh.get("views", []):
		if str(v.get("type", "")) == type and (key == "" or str(v.get(key, "")) == val):
			return v
	return {}


func phase6() -> void:
	print("== Faz 6: teknik resim (%s)" % ("OCC" if app.viewport.kernel.is_brep() else "CSG"))
	await box_ui(10.0)
	# Taslağa bir boyut ekle (model boyutu aktarımı için)
	var skf: CadFeature = app.doc.sketches()[0]
	var sk: Sketch = skf.sketch
	var ln := find_entity(sk, "line")
	var pa: Vector2 = sk.points[int(ln["a"])]
	var pb: Vector2 = sk.points[int(ln["b"])]
	var L0 := pa.distance_to(pb)
	app.doc.checkpoint()
	sk.add_constraint(SketchSolver.make_dimension(sk, {"type": "distance", "p1": int(ln["a"]), "p2": int(ln["b"])}, (pa + pb) * 0.5 + Vector2(0, -6)))
	app.doc.commit()
	await settle()
	app._show_toolbar(3)
	await dw_settle()
	check(app.mode == "drawing" and app.drawing_canvas.visible and not app.viewport.visible, "Teknik Resim sekmesi: resim modu, tuval görünür")
	check(app.doc.drawings.size() == 1, "varsayılan A3 sayfası oluşturuldu")
	var sh: Dictionary = app._dw_sheet()
	check((sh["views"] as Array).size() == 4, "standart 3 görünüş + izometrik (%d)" % (sh["views"] as Array).size())
	var front := dw_view("model", "orient", "front")
	var geo: Dictionary = app._dw_geo.get(app._dw_index, {})
	check(not front.is_empty() and not (geo.get(int(front["id"]), {}).get("visible", []) as Array).is_empty(), "ön görünüş çizgileri hesaplandı")
	var s := Drawing.view_scale(sh, front)
	var bb: Rect2 = app._dw_bboxes.get(int(front["id"]), Rect2())
	check(absf(bb.size.x - 40.0 * s) < 0.01 and absf(bb.size.y - 10.0 * s) < 0.01, "ön görünüş 40 × 10 × ölçek (%s)" % str(bb.size))

	print("   akıllı boyut")
	app._dw_cmd("dw_dim")
	dw_click(Drawing.view_to_sheet(sh, front, Vector2(-20, 0)))
	dw_click(Drawing.view_to_sheet(sh, front, Vector2(20, 0)))
	dw_click(Drawing.view_to_sheet(sh, front, Vector2(0, -8)))
	var dim := {}
	for a in sh["anns"]:
		if a["type"] == "dim":
			dim = a
	check(not dim.is_empty() and str(dim["kind"]) == "h" and absf(DrawingRender.dim_value(app.doc, sh, dim) - 40.0) < 1e-4, "yatay boyut 40 (köşelere yakalandı)")
	app._dw_cmd("dw_dim")
	dw_click(Drawing.view_to_sheet(sh, front, Vector2(20, 0)))
	dw_click(Drawing.view_to_sheet(sh, front, Vector2(20, 10)))
	dw_click(Drawing.view_to_sheet(sh, front, Vector2(30, 5)))
	var dim2: Dictionary = sh["anns"][sh["anns"].size() - 1]
	check(str(dim2.get("kind", "")) == "v" and absf(DrawingRender.dim_value(app.doc, sh, dim2) - 10.0) < 1e-4, "dikey boyut 10")

	print("   model boyutları (ilişkili)")
	app._dw_cmd("dw_modeldims")
	var md := {}
	for a in sh["anns"]:
		if a.has("src"):
			md = a
	check(not md.is_empty() and absf(DrawingRender.dim_value(app.doc, sh, md) - L0) < 1e-3, "taslak boyutu üst görünüşe aktarıldı (%.3f)" % L0)
	var mv := Drawing.find_view(sh, int(md.get("view", -1)))
	check(not mv.is_empty() and mv.get("type", "") == "projected", "model boyutu taslak düzlemine paralel görünüşte")

	print("   izdüşüm, detay, kesit")
	app._dw_sel = {"kind": "view", "id": int(front["id"])}
	app._dw_cmd("dw_proj")
	var fbb: Rect2 = app._dw_bboxes[int(front["id"])]
	dw_click(Vector2(fbb.position.x - 40.0, fbb.get_center().y))
	await dw_settle()
	var pl := dw_view("projected", "side", "left")
	var lax := Drawing.view_axes(sh, pl) if not pl.is_empty() else {}
	check(not pl.is_empty() and (lax["dir"] as Vector3).is_equal_approx(Vector3(1, 0, 0)), "sola izdüşüm (1. açı: sağdan bakış)")
	app._dw_sel = {"kind": "view", "id": int(front["id"])}
	app._dw_cmd("dw_detail")
	dw_click(Drawing.view_to_sheet(sh, front, Vector2(20, 0)))
	dw_click(Drawing.view_to_sheet(sh, front, Vector2(26, 0)))
	await dw_settle()
	var det := dw_view("detail")
	var dg := DrawingRender.view_geometry(sh, det, app._dw_geo.get(app._dw_index, {})) if not det.is_empty() else {}
	check(not det.is_empty() and not (dg.get("visible", []) as Array).is_empty() and absf(Drawing.view_scale(sh, det) - 2.0 * s) < 1e-6, "detay görünüşü (2× büyütme, kırpılmış)")
	var topv := dw_view("projected", "side", "down")
	if app.viewport.kernel.is_brep():
		app._dw_sel = {"kind": "view", "id": int(topv["id"])}
		app._dw_cmd("dw_section")
		dw_click(Drawing.view_to_sheet(sh, topv, Vector2(-26, 0.3)))
		dw_click(Drawing.view_to_sheet(sh, topv, Vector2(26, 0.3)))
		await dw_settle()
		var sec := dw_view("section")
		var sg: Dictionary = app._dw_geo.get(app._dw_index, {}).get(int(sec.get("id", -1)), {})
		var area := 0.0
		for region in sg.get("hatch", []):
			var pts := PackedVector2Array()
			for q in region[0]:
				pts.append(Vector2(float(q[0]), float(q[1])))
			area += absf(Drawing.polygon_area(pts))
		check(not sec.is_empty() and absf(area - 400.0) < 1e-3, "kesit görünüşü: tarama alanı 40 × 10 = %.3f" % area)
		var sl := str(sec.get("section", {}).get("label", ""))
		check(sl != "" and sl != str(det.get("detail", {}).get("label", "")), "kesit harfi sıradaki harf (%s), detaydan farklı" % sl)
	else:
		print("   (kesit görünüşü OpenCASCADE gerektirir — atlandı)")

	print("   açıklamalar, taşıma, geri al, silme")
	app._dw_cmd("dw_note")
	dw_click(Vector2(40, 40))
	var note: Dictionary = sh["anns"][sh["anns"].size() - 1]
	check(note.get("type", "") == "note" and app._dw_sel.get("kind", "") == "ann", "not eklendi ve seçildi")
	app._dw_cmd("dw_balloon")
	dw_click(Drawing.view_to_sheet(sh, front, Vector2(0, 10)))
	dw_click(Vector2(fbb.get_center().x, fbb.end.y + 20.0))
	check(sh["anns"][sh["anns"].size() - 1].get("type", "") == "balloon", "balon eklendi")
	app._dw_set_tool("select")
	var f0 := Drawing.v2(front["pos"])
	var kid0 := Drawing.v2(topv["pos"])
	var c0 := (app._dw_bboxes[int(front["id"])] as Rect2).get_center()
	dw_drag(c0, c0 + Vector2(12, 0))
	front = Drawing.find_view(app._dw_sheet(), int(front["id"]))
	topv = Drawing.find_view(app._dw_sheet(), int(topv["id"]))
	check(Drawing.v2(front["pos"]).is_equal_approx(f0 + Vector2(12, 0)) and Drawing.v2(topv["pos"]).is_equal_approx(kid0 + Vector2(12, 0)), "görünüş sürüklendi; izdüşüm çocuğu hizalı taşındı")
	app._cmd("undo")
	await dw_settle()
	sh = app._dw_sheet()
	front = Drawing.find_view(sh, int(front["id"]))
	check(app.mode == "drawing" and Drawing.v2(front["pos"]).is_equal_approx(f0), "geri al: taşıma geri alındı, resim modunda kalındı")
	var n_ann := (sh["anns"] as Array).size()
	app._dw_sel = {"kind": "ann", "id": int(sh["anns"][0]["id"])}
	app._cmd("delete")
	check((app._dw_sheet()["anns"] as Array).size() == n_ann - 1, "Delete seçili açıklamayı siler")
	app._escape()
	check(app._dw_sel.is_empty(), "Esc seçimi temizler")

	print("   ilişkili güncelleme")
	sh = app._dw_sheet()
	var md2 := {}
	for a in sh["anns"]:
		if a.has("src"):
			md2 = a
	var cid := int(md2["src"]["cid"])
	var skf2: CadFeature = app.doc.get_feature(int(md2["src"]["sketch"]))
	app.doc.checkpoint()
	var cons: Dictionary = skf2.sketch.get_constraint(cid)
	cons["value"] = L0 + 10.0
	SketchSolver.solve_sketch(skf2.sketch)
	app.doc.commit()
	await settle()
	await dw_settle()
	sh = app._dw_sheet()
	md2 = Drawing.find_ann(sh, int(md2["id"]))
	check(absf(DrawingRender.dim_value(app.doc, sh, md2) - (L0 + 10.0)) < 1e-3, "taslak boyutu değişince resimdeki model boyutu güncellenir (%.3f)" % DrawingRender.dim_value(app.doc, sh, md2))

	print("   çıktılar")
	var tmp := OS.get_user_data_dir().path_join("uitest")
	DirAccess.make_dir_recursive_absolute(tmp)
	for k in [["dw_pdf", "resim.pdf", "%PDF-"], ["dw_svg", "resim.svg", "<?xml"], ["dw_dxf", "resim.dxf", "0\nSECTION"]]:
		var pth: String = tmp.path_join(k[1])
		if FileAccess.file_exists(pth):
			DirAccess.remove_absolute(pth)
		app._pending_file_action = k[0]
		app._on_file_selected(pth.get_basename())
		check(FileAccess.file_exists(pth) and FileAccess.get_file_as_string(pth).begins_with(k[2]), "%s yazıldı (uzantı eklendi)" % k[1])
	var sp := tmp.path_join("resim.dcad")
	app._pending_file_action = "save"
	app._on_file_selected(sp)
	var d2 := CadDocument.new()
	check(d2.load_from(sp) == OK and d2.drawings.size() == 1 and (d2.drawings[0]["views"] as Array).size() == (app._dw_sheet()["views"] as Array).size(), "resim parça dosyasıyla kaydedilip yüklendi")

	app._show_toolbar(0)
	await settle()
	check(app.mode == "idle" and app.viewport.visible and not app.drawing_canvas.visible, "Özellikler sekmesine dönünce 3B görünüm geri gelir")
	app._show_toolbar(3)
	await dw_settle()
	check(app.mode == "drawing" and app.doc.drawings.size() == 1, "tekrar girince mevcut sayfa kullanılır")
	app._show_toolbar(0)
	await settle()
	# Taslak düzenlerken Teknik Resim sekmesine geçiş: taslak kapanır, resim modu ve sekme tutarlı
	app._edit_sketch(app.doc.sketches()[0])
	await settle()
	app._show_toolbar(3)
	await dw_settle()
	check(app.mode == "drawing" and app.tabs.current_tab == 3 and app.toolbar_drawing.visible and app.drawing_canvas.visible, "taslak modundan Teknik Resim sekmesine geçiş")
	app._cmd("measure")
	await settle()
	check(app.mode != "drawing" and app.viewport.visible and not app.drawing_canvas.visible, "3B komutu resim modundan çıkarır")
	app._escape()
	app._show_toolbar(0)
	await settle()


# ---------------------------------------------------------------- Faz 7: montaj

func asm_settle() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		if not app.viewport.kernel.is_busy() and app.asm_mode._pending == 0:
			break
	await frames(3)


func comp_xf(i: int) -> Transform3D:
	return app.asm_mode.asm.comps[i]["xf"]


func phase7() -> void:
	print("== Faz 7: montaj (%s)" % ("OCC" if app.viewport.kernel.is_brep() else "CSG"))
	var tmp := OS.get_user_data_dir().path_join("uitest")
	DirAccess.make_dir_recursive_absolute(tmp)
	await box_ui(10.0)
	var kutu := tmp.path_join("kutu7.dcad")
	app._pending_file_action = "save"
	app._on_file_selected(kutu)
	check(FileAccess.file_exists(kutu) and not app.doc.dirty, "kutu parçası kaydedildi")
	app._cmd("new_asm")
	await asm_settle()
	var am: AssemblyMode = app.asm_mode
	check(app.mode == "assembly" and am.is_open() and app.tabs.current_tab == 4 and not app.tabs.is_tab_hidden(4) and app.tabs.is_tab_hidden(0), "Yeni Montaj: montaj modu, yalnızca Montaj sekmesi")
	am.insert_file(kutu)
	am.insert_file(kutu)
	await asm_settle()
	var asm: CadAssembly = am.asm
	check(asm.comps.size() == 2 and bool(asm.comps[0]["fixed"]) and not bool(asm.comps[1]["fixed"]), "iki bileşen eklendi, ilki sabit")
	check(comp_xf(1).origin.x > 20.0, "ikinci bileşen yanına yerleşti (x=%.1f)" % comp_xf(1).origin.x)
	var p2: Dictionary = am.parts.get(asm.key_of(asm.comps[1]), {})
	check(bool(p2.get("ok", false)) and am.parts.size() == 1, "aynı parça bir kez derlendi")
	app.viewport.camera.set_standard_view("iso", false)
	am.fit(false)
	await frames(3)
	print("   tıklayarak eşleştirme")
	am.cmd("asm_mate")
	check(am.tool == "mate", "Eşleştir aracı")
	# Üst yüzler (ikisi de yukarı bakar): çakışık → aynı yön
	send_click(app.viewport.world_to_screen(Vector3(5, 10, 3)))
	send_click(app.viewport.world_to_screen(comp_xf(1) * Vector3(5, 10, 3)))
	check(am.mate_refs.size() == 2 and str(am.mate_refs[0]["geo"]["t"]) == "plane", "iki düzlemsel yüz seçildi")
	am.apply_mate("coincident")
	await frames(2)
	check(asm.mates.size() == 1 and absf(comp_xf(1).origin.y) < 1e-3, "çakışık: üst yüzler aynı düzlemde (y=%.4f)" % comp_xf(1).origin.y)
	am.cmd("asm_mate")
	send_click(app.viewport.world_to_screen(Vector3(-5, 4, 10)))
	send_click(app.viewport.world_to_screen(comp_xf(1) * Vector3(-5, 4, 10)))
	am.apply_mate("coincident")
	await frames(2)
	check(asm.mates.size() == 2 and absf(comp_xf(1).origin.z) < 1e-3, "çakışık: ön yüzler hizalı (z=%.4f)" % comp_xf(1).origin.z)
	check(am.dof_of(int(asm.comps[1]["id"])) == 1, "iki çakışık sonrası 1 serbestlik (%d)" % am.dof_of(int(asm.comps[1]["id"])))
	am.cmd("asm_mate")
	send_click(app.viewport.world_to_screen(Vector3(20, 5, 2)))
	send_click(app.viewport.world_to_screen(comp_xf(1) * Vector3(20, 5, 2)))
	am.mate_opts["value"] = 60.0
	am.apply_mate("distance")
	await frames(2)
	check(asm.mates.size() == 3 and absf(comp_xf(1).origin.x - 60.0) < 1e-3, "mesafe 60: sağ yüzler arası (x=%.4f)" % comp_xf(1).origin.x)
	check(am.dof_of(int(asm.comps[1]["id"])) == 0, "tam tanımlı")
	var it: TreeItem = app.tree.get_root().get_child(2)
	check(not it.get_text(0).begins_with("(-)"), "ağaçta tam tanımlı bileşen önek almaz (%s)" % it.get_text(0))
	print("   sürükleme, geri al")
	am.sel = {"kind": "mate", "id": int(asm.mates[2]["id"])}
	am.delete_selected()
	check(asm.mates.size() == 2 and am.dof_of(int(asm.comps[1]["id"])) == 1, "mesafe silindi: 1 serbestlik")
	am.set_tool("select")
	var x0 := comp_xf(1).origin
	var g := comp_xf(1) * Vector3(0, 10, 0)
	send_drag(app.viewport.world_to_screen(g), app.viewport.world_to_screen(g + Vector3(25, 0, 0)))
	await frames(2)
	var x1 := comp_xf(1).origin
	check(absf(x1.x - x0.x) > 5.0 and absf(x1.y) < 1e-3 and absf(x1.z) < 1e-3, "sürükleme eşleştirmelere uyar: x %.1f → %.1f, y/z sabit" % [x0.x, x1.x])
	app._cmd("undo")
	await asm_settle()
	check(comp_xf(1).origin.distance_to(x0) < 1e-3, "geri al: sürükleme geri alındı")
	app._cmd("redo")
	await asm_settle()
	app._cmd("undo")
	await asm_settle()
	print("   bağlantı elemanı, BOM, kütle")
	am.cmd("asm_toolbox")
	am.tb_spec = {"type": "bolt", "size": "M6", "length": 25}
	am.insert_toolbox(am.tb_spec)
	await asm_settle()
	check(asm.comps.size() == 3 and bool(am.parts.get(asm.key_of(asm.comps[2]), {}).get("ok", false)), "cıvata eklendi ve derlendi")
	var rows := am.bom_rows()
	check(rows.size() == 2 and int(rows[0]["qty"]) == 2 and str(rows[1]["name"]) == "Cıvata ISO 4017 M6x25", "malzeme listesi: kutu ×2, cıvata ×1")
	var csv := tmp.path_join("bom7.csv")
	check(am.write_bom_csv(csv) == OK and FileAccess.get_file_as_string(csv).contains("Cıvata ISO 4017 M6x25"), "BOM CSV yazıldı")
	var mt := am.mass_totals()
	check(float(mt["volume"]) > 2.0 * 8000.0, "montaj hacmi parçaların toplamı (%.0f)" % float(mt["volume"]))
	print("   patlatma")
	am.cmd("asm_explode_toggle")
	var te := Time.get_ticks_msec()
	while am.explode_t < 0.999 and Time.get_ticks_msec() - te < 3000:
		await get_tree().process_frame
	check(am.explode_t > 0.99 and not asm.explode.is_empty(), "otomatik patlatma ve animasyon")
	am.cmd("asm_explode_toggle")
	te = Time.get_ticks_msec()
	while am.explode_t > 0.001 and Time.get_ticks_msec() - te < 3000:
		await get_tree().process_frame
	check(am.explode_t < 0.01, "topla")
	if app.viewport.kernel.is_brep():
		print("   girişim ve STEP")
		# İkinci kutuyu ilkiyle 10 mm çakışacak konuma al (mesafe 30 → x=30, kutular 40 genişlikte)
		am.cmd("asm_mate")
		send_click(app.viewport.world_to_screen(Vector3(20, 5, 2)))
		send_click(app.viewport.world_to_screen(comp_xf(1) * Vector3(20, 5, 2)))
		am.mate_opts["value"] = 30.0
		am.apply_mate("distance")
		await frames(2)
		am.cmd("asm_interf")
		var res: Dictionary = await app.viewport.kernel.asm_done
		await frames(2)
		check(am.interf.size() == 1 and absf(float(am.interf[0]["volume"]) - 2000.0) < 0.01, "girişim: 10 × 10 × 20 = %.3f mm³" % (float(am.interf[0]["volume"]) if not am.interf.is_empty() else -1.0))
		var stp := tmp.path_join("montaj7.step")
		am.export_step(stp)
		await app.viewport.kernel.asm_done
		check(FileAccess.file_exists(stp) and FileAccess.get_file_as_string(stp).contains("ISO-10303"), "montaj STEP çıktısı")
	print("   kaydet / aç, parçayı düzenle")
	var ap := tmp.path_join("montaj7.dasm")
	app._pending_file_action = "asm_save"
	app._on_file_selected(ap)
	check(FileAccess.file_exists(ap) and not asm.dirty, "montaj kaydedildi")
	var nm := asm.mates.size()
	app._pending_file_action = "open"
	app._on_file_selected(ap)
	await asm_settle()
	check(app.mode == "assembly" and am.asm.comps.size() == 3 and am.asm.mates.size() == nm and am.asm.comps[0]["src"]["path"] == "kutu7.dcad", "montaj dosyadan açıldı (göreli yol)")
	am.sel = {"kind": "comp", "id": int(am.asm.comps[0]["id"])}
	am.cmd("asm_open")
	await settle()
	check(app.mode == "idle" and app.doc.file_path.get_file() == "kutu7.dcad" and not app.tabs.is_tab_hidden(0) and not app.tabs.is_tab_hidden(4), "Parçayı Aç: parça modu, Montaj sekmesi dönüş için görünür")
	app._show_toolbar(4)
	await asm_settle()
	check(app.mode == "assembly" and am.view.visible, "Montaj sekmesiyle geri dönüldü")
	app.doc.dirty = false
	am.asm.dirty = false
	app._cmd("new")
	await settle()
	check(app.mode == "idle" and not am.is_open() and app.tabs.is_tab_hidden(4) and not app.tabs.is_tab_hidden(0), "Yeni parça: montaj kapandı")


func mref(comp: int, g: Dictionary) -> Dictionary:
	return {"comp": comp, "kind": "face", "name": "", "fid": -1, "geo": g.duplicate(true), "label": "Yüz"}


const TOP := {"t": "plane", "p": [0, 10, 0], "n": [0, 1, 0]}
const BOTTOM := {"t": "plane", "p": [0, 0, 0], "n": [0, -1, 0]}
const FRONT := {"t": "plane", "p": [0, 5, 10], "n": [0, 0, 1]}


## İki kutu: ikincisi üst ve ön yüzleri hizalı, yalnızca X boyunca kayabilir
func two_box_asm(kutu: String) -> AssemblyMode:
	if app.asm_mode.is_open():
		app.asm_mode.asm.dirty = false
	app.doc.dirty = false
	app._cmd("new_asm")
	await asm_settle()
	var am: AssemblyMode = app.asm_mode
	am.insert_file(kutu)
	am.insert_file(kutu)
	await asm_settle()
	var a := int(am.asm.comps[0]["id"])
	var b := int(am.asm.comps[1]["id"])
	am.mate_refs = [mref(a, TOP), mref(b, TOP)]
	am.apply_mate("coincident")
	am.mate_refs = [mref(a, FRONT), mref(b, FRONT)]
	am.apply_mate("coincident")
	return am


func phase7b() -> void:
	print("== Faz 7b: çoğaltma, alt montaj, çarpışma, montaj resmi, bağlamda parça (%s)" % ("OCC" if app.viewport.kernel.is_brep() else "CSG"))
	var tmp := OS.get_user_data_dir().path_join("uitest")
	DirAccess.make_dir_recursive_absolute(tmp)
	await box_ui(10.0)
	var kutu := tmp.path_join("kutu7b.dcad")
	app._pending_file_action = "save"
	app._on_file_selected(kutu)
	var am: AssemblyMode = await two_box_asm(kutu)
	var asm: CadAssembly = am.asm
	var b := int(asm.comps[1]["id"])
	check(am.dof_of(b) == 1, "ikinci kutu X boyunca kayar (1 serbestlik)")

	print("   bileşen çoğaltma")
	am.cmd("asm_pattern")
	am.sel_comps = [b]
	am.pat_opts.merge({"type": "linear", "axis": 0, "count": 3, "spacing": 50.0, "reverse": false}, true)
	var p := am.create_pattern()
	var inst := asm.pattern_instances(int(p["id"]))
	var x0: float = (asm.get_comp(b)["xf"] as Transform3D).origin.x
	var xs: Array = []
	for c in inst:
		xs.append((c["xf"] as Transform3D).origin.x)
	xs.sort()
	check(inst.size() == 2 and absf(float(xs[0]) - (x0 + 50.0)) < 1e-3 and absf(float(xs[1]) - (x0 + 100.0)) < 1e-3, "doğrusal çoğaltma: 2 örnek, 50 mm aralık")
	asm.checkpoint()
	var sx: Transform3D = asm.get_comp(b)["xf"]
	asm.get_comp(b)["xf"] = Transform3D(sx.basis, sx.origin + Vector3(10, 0, 0))
	asm.commit()
	am.solve()
	xs.clear()
	for c in asm.pattern_instances(int(p["id"])):
		xs.append((c["xf"] as Transform3D).origin.x)
	xs.sort()
	check(absf(float(xs[0]) - (x0 + 60.0)) < 1e-3, "çekirdek kayınca örnekler izler")
	p["count"] = 4
	am._regen_instances(p)
	am.solve()
	check(asm.pattern_instances(int(p["id"])).size() == 3, "örnek sayısı 4'e çıkarıldı")
	am.sel = {"kind": "comp", "id": int(asm.pattern_instances(int(p["id"]))[0]["id"])}
	am.delete_selected()
	check(asm.pattern_instances(int(p["id"])).size() == 2 and (p["skip"] as Array).size() == 1, "örnek silinince atlanır")
	var rows := am.bom_rows()
	check(rows.size() == 1 and int(rows[0]["qty"]) == 4, "malzeme listesi örnekleri sayar (%d)" % int(rows[0]["qty"]))
	var tree_ok := false
	var it: TreeItem = app.tree.get_root().get_first_child()
	while it != null:
		if (it.get_metadata(0) as Dictionary).get("kind", "") == "pattern":
			tree_ok = it.get_child_count() == 2
		it = it.get_next()
	check(tree_ok, "ağaçta çoğaltma ve örnekleri")

	print("   alt montaj")
	var subp := tmp.path_join("alt7.dasm")
	am.on_file("asm_save", subp)
	var n_sub := asm.comps.size()
	am.asm.dirty = false
	app._cmd("new_asm")
	await asm_settle()
	am.insert_file(kutu)
	am.insert_file(subp)
	await asm_settle()
	asm = am.asm
	var sc: Dictionary = asm.comps[1]
	var sp: Dictionary = am.parts.get(asm.key_of(sc), {})
	check(sp.get("kind", "") == "asm" and bool(sp.get("ok", false)) and (sp.get("children", []) as Array).size() == n_sub, "alt montaj yüklendi: %d alt bileşen birleşti" % (sp.get("children", []) as Array).size())
	var kt: ModelMesh = am.parts.get("file:" + kutu.simplify_path(), {}).get("model")
	check((sp["model"] as ModelMesh).tri_count() == kt.tri_count() * n_sub, "birleşik model: alt parçaların üçgenleri")
	am.mate_refs = [mref(int(asm.comps[0]["id"]), TOP), mref(int(sc["id"]), BOTTOM)]
	am.apply_mate("coincident")
	check(absf((sc["xf"] as Transform3D).origin.y - 10.0) < 1e-3, "alt montaj tek gövde gibi eşleşir (y=%.3f)" % (sc["xf"] as Transform3D).origin.y)
	am.bom_flat = true
	var fr := am.bom_rows()
	am.bom_flat = false
	var tr := am.bom_rows()
	am.bom_flat = true
	check(str(tr[1]["name"]).begins_with("alt7"), "alt montaj adı dosya adından (%s)" % str(tr[1]["name"]))
	check(fr.size() == 1 and int(fr[0]["qty"]) == n_sub + 1 and tr.size() == 2, "BOM: yalnızca parçalar %d adet / üst düzey 2 kalem" % int(fr[0]["qty"]))
	var mt := am.mass_totals()
	check(absf(float(mt["volume"]) - 8000.0 * (n_sub + 1)) < 1.0, "kütle özellikleri alt montajı açar (%.0f)" % float(mt["volume"]))
	if app.viewport.kernel.is_brep():
		am.cmd("asm_interf")
		await app.viewport.kernel.asm_done
		await frames(2)
		check(am.interf.is_empty(), "alt montaj üstte, girişim yok (iç çiftler atlanır)")

	if app.viewport.kernel.is_brep():
		print("   çarpışma algılama")
		am = await two_box_asm(kutu)
		asm = am.asm
		b = int(asm.comps[1]["id"])
		app.viewport.camera.set_standard_view("front", false)
		am.fit(false)
		await frames(3)
		am.collide_on = true
		am.set_tool("select")
		var g: Vector3 = (asm.get_comp(b)["xf"] as Transform3D) * Vector3(0, 5, 10)
		send_drag(app.viewport.world_to_screen(g), app.viewport.world_to_screen(Vector3(0, 5, 10)))
		var t0 := Time.get_ticks_msec()
		while (am._coll_busy or not am._coll_end_snap.is_empty()) and Time.get_ticks_msec() - t0 < 8000:
			await get_tree().process_frame
		await frames(2)
		var xb: float = (asm.get_comp(b)["xf"] as Transform3D).origin.x
		check(xb >= 40.0 - 1e-3 and xb < 54.0, "sürükleme çarpışmadan önce durdu (x=%.2f, temas 40)" % xb)
		am.cmd("asm_interf")
		await app.viewport.kernel.asm_done
		await frames(2)
		check(am.interf.is_empty(), "çarpışma algılamada girişim oluşmadı")
		am.collide_on = false
		am.set_tool("select")

	print("   montaj teknik resmi")
	am = await two_box_asm(kutu)
	am.insert_toolbox({"type": "bolt", "size": "M6", "length": 20})
	await asm_settle()
	var ap := tmp.path_join("montaj7b.dasm")
	am.on_file("asm_save", ap)
	app._show_toolbar(3)
	await dw_settle()
	check(app.mode == "drawing" and app._dw_in_asm and am.asm.drawings.size() == 1, "Montajda Teknik Resim: sayfa montaj belgesinde")
	var sh: Dictionary = app._dw_sheet()
	check((sh["views"] as Array).size() == 4, "montajın standart görünüşleri")
	var fv: Dictionary = sh["views"][0]
	var geo: Dictionary = app._dw_geo.get(app._dw_index, {})
	check(not (geo.get(int(fv["id"]), {}).get("visible", []) as Array).is_empty(), "montaj görünüşü hesaplandı")
	app._dw_cmd("dw_autoballoon")
	var nb := 0
	for a in sh["anns"]:
		if a.get("type", "") == "balloon":
			nb += 1
	check(nb == 2, "otomatik balon: malzeme listesi kalemi başına bir balon (%d)" % nb)
	var prims := DrawingRender.build(am.asm, sh, geo, {"bom_rows": app._dw_asm_bom()})
	var texts: Array = []
	for pr in prims:
		if pr["t"] == "txt":
			texts.append(pr["s"])
	check("Cıvata ISO 4017 M6x20" in texts and "kutu7b" in texts, "resim BOM tablosunda montaj kalemleri")
	var pdf := tmp.path_join("montaj7b.pdf")
	check(app._dw_export("dw_pdf", pdf) == OK and FileAccess.file_exists(pdf), "montaj resmi PDF")
	app._show_toolbar(4)
	await asm_settle()
	check(app.mode == "assembly" and am.view.visible and not app._dw_in_asm, "Montaj sekmesine dönüldü")
	am.on_file("asm_save", ap)
	var re := CadAssembly.new()
	check(re.load_from(ap) == OK and re.drawings.size() == 1, "montaj resmi .dasm içinde saklandı")

	print("   montaj bağlamında yeni parça")
	var np := tmp.path_join("yeni7.dcad")
	if FileAccess.file_exists(np):
		DirAccess.remove_absolute(np)
	am.new_part_in_context(np)
	await settle()
	check(app.mode == "idle" and am.context_active() and app.doc.part_name == "yeni7", "yeni parça bağlamda açıldı")
	var ch := am.context_pick(Vector3(5, 100, 3), Vector3.DOWN)
	check(not ch.is_empty() and bool(ch["planar"]) and absf((ch["point"] as Vector3).y - 10.0) < 1e-3, "bağlam yüzü seçilebilir (kutunun üst yüzü)")
	app.viewport.camera.set_standard_view("iso", false)
	app._fit(false)
	await settle()
	send_click(app.viewport.world_to_screen(Vector3(5, 10, 3)))
	check(app.selection.get("kind", "") == "face" and app.selection.has("ctx_pts"), "tıklama: bağlamdaki yüz seçildi")
	app._cmd("sketch")
	await settle()
	check(app.mode == "sketch" and absf(app.editor.plane().origin.y - 10.0) < 1e-3, "bağlam yüzüne taslak açıldı (y=10)")
	app.grid_btn.button_pressed = true
	app.editor.set_grid_snap(true)
	app.editor.set_tool("rect")
	sketch_click(Vector2(-10, -10))
	sketch_click(Vector2(10, 10))
	app._cmd("extrude")
	app.editing.params["depth"] = 5.0
	app._preview()
	app._ok_feature()
	await settle()
	check(absf(volume() - 2000.0) < 1.0, "bağlamda modellenen parça hacmi %.1f" % volume())
	app._show_toolbar(4)
	await asm_settle()
	var nk := "file:" + np.simplify_path()
	var nm: ModelMesh = am.parts.get(nk, {}).get("model")
	check(app.mode == "assembly" and not am.context_active() and nm != null and absf(nm.aabb.position.y - 10.0) < 1e-3, "montaja dönüldü: yeni parça kutunun üstünde")
	app.doc.dirty = false
	am.asm.dirty = false
	app._cmd("new")
	await settle()


# ---------------------------------------------------------------- Faz 8: sac metal, kaynaklı konstrüksiyon, konfigürasyonlar

func body_count() -> int:
	var b := {}
	for f in app.viewport.model.brep_faces:
		b[int(f.get("body", -1))] = true
	return b.size()


func rect_sketch(plane_id: String, a: Vector2, b: Vector2) -> void:
	app._select({"kind": "plane", "id": plane_id})
	app._cmd("sketch")
	await settle()
	app.grid_btn.button_pressed = true
	app.editor.set_grid_snap(true)
	app.editor.set_tool("rect")
	sketch_click(a)
	sketch_click(b)
	app._exit_sketch()
	await settle()


func phase8() -> void:
	print("== Faz 8: sac metal, kaynaklı konstrüksiyon, konfigürasyonlar (%s)" % ("OCC" if app.viewport.kernel.is_brep() else "CSG"))
	var tmp := OS.get_user_data_dir().path_join("uitest")
	DirAccess.make_dir_recursive_absolute(tmp)
	await fresh_doc()
	await rect_sketch("top", Vector2(-40, -30), Vector2(40, 30))
	app._show_toolbar(5)
	check(app.special.toolbar_sm.visible and not app.toolbar_features.visible, "Sac Metal sekmesi ve araç çubuğu")
	if not app.viewport.kernel.is_brep():
		app._cmd("sm_base")
		check(app.mode != "feature", "CSG çekirdeğinde sac metal OpenCASCADE gerektirir")
	else:
		app._cmd("sm_base")
		check(app.mode == "feature" and app.editing.type == "sm_base", "Taban Flanş paneli")
		app.editing.params["T"] = 2.0
		app._preview()
		app._ok_feature()
		await settle()
		check(absf(volume() - 80.0 * 60.0 * 2.0) < 0.5, "taban flanş plaka hacmi %.1f" % volume())
		app.viewport.camera.set_standard_view("iso", false)
		app._fit(false)
		await settle()
		app._cmd("sm_edge")
		await settle()
		check(app.mode == "feature" and app.editing.type == "sm_edge", "Kenar Flanş: kenar seçimi")
		var base := SheetMetal.base_of(app.doc)
		var clicked := 0
		var total_len := 0.0
		for e in app.viewport.model.brep_edges:
			if clicked >= 2:
				break
			var pe := SheetMetal.parse_edge(e.get("fn", []))
			if pe.is_empty() or str(pe["cap"]) != "b" or str(e.get("type", "")) != "line":
				continue
			var pts: PackedVector3Array = e["pts"]
			var mid := (pts[0] + pts[pts.size() - 1]) * 0.5
			send_click(app.viewport.world_to_screen(mid))
			total_len += pts[0].distance_to(pts[pts.size() - 1])
			clicked += 1
		check((app.editing.params["edges"] as Array).size() == 2, "iki kenar tıklanarak seçildi")
		app.editing.params["L"] = 15.0
		app._preview()
		app._ok_feature()
		await settle()
		var vexp := 9600.0 + total_len * (PI * 0.25 * (16.0 - 4.0) + 2.0 * 15.0)
		check(absf(volume() - vexp) < 1.0, "iki kenar flanşı: hacim %.1f ≈ %.1f" % [volume(), vexp])
		app._cmd("sm_flat")
		await settle()
		var fp := SheetMetal.flat_pattern(app.doc)
		var area := 0.0
		for p in fp["outline"]:
			area += absf(Drawing.polygon_area(p))
		check(absf(volume() - area * 2.0) < 1.0, "Açınım: düz sac (alan × T = %.1f)" % (area * 2.0))
		app._cmd("sm_flat")
		await settle()
		check(absf(volume() - vexp) < 1.0, "Açınım kapatılınca bükülmüş hali geri gelir")
		var dxf := tmp.path_join("acinim8.dxf")
		app._pending_file_action = "sm_dxf"
		app._on_file_selected(dxf)
		check(FileAccess.file_exists(dxf) and FileAccess.get_file_as_bytes(dxf).get_string_from_ascii().contains("EKSEN"), "Açınım DXF kaydedildi")

		print("   kaynaklı konstrüksiyon")
		await fresh_doc()
		await rect_sketch("front", Vector2(0, 0), Vector2(400, 300))
		app._show_toolbar(6)
		check(app.special.toolbar_weld.visible, "Kaynaklar sekmesi")
		app._cmd("weld")
		check(app.mode == "feature" and app.editing.type == "weld", "Yapısal Üye paneli")
		app._ok_feature()
		await settle()
		var A := 1600.0 - 34.0 * 34.0
		check(body_count() == 4 and absf(volume() - A * 1400.0) < 5.0, "çerçeve: 4 gövde, hacim %.0f" % volume())
		app._cmd("weld_cutlist")
		check(app.mode == "cutlist", "kesim listesi paneli")
		var csv := tmp.path_join("kesim8.csv")
		app._pending_file_action = "weld_csv"
		app._on_file_selected(csv)
		check(FileAccess.file_exists(csv) and FileAccess.get_file_as_string(csv).contains("Kare profil 40x40x3"), "kesim listesi CSV")
		app._escape()

	print("   konfigürasyonlar")
	if not app.viewport.kernel.is_brep():
		await fresh_doc()
		await box_ui(10.0)
	var feat: CadFeature = app.doc.features[app.doc.features.size() - 1]
	app._cmd("configs")
	check(app.mode == "configs" and app.doc.configs.size() == 1 and app.doc.active_config == "Varsayılan", "Konfigürasyonlar paneli, Varsayılan oluştu")
	check(Configs.add(app.doc, "Bastırılmış"), "yeni konfigürasyon")
	app.doc.checkpoint()
	feat.suppressed = true
	app.doc.commit()
	await settle()
	check(app.viewport.model.is_empty(), "bu konfigürasyonda özellik bastırıldı")
	Configs.activate(app.doc, "Varsayılan")
	app.doc.commit()
	await settle()
	check(not app.viewport.model.is_empty() and not feat.suppressed, "Varsayılan'a dönünce özellik geri gelir")
	var root_txt: String = app.tree.get_root().get_text(0)
	check(root_txt.contains("[Varsayılan]"), "ağaç kökünde etkin konfigürasyon (%s)" % root_txt)
	var tcsv := tmp.path_join("tablo8.csv")
	app._pending_file_action = "cfg_csv_out"
	app._on_file_selected(tcsv)
	check(FileAccess.get_file_as_string(tcsv).contains("Bastırılmış;"), "tasarım tablosu CSV")
	app._escape()
	check(app.mode == "idle", "Esc ile panelden çıkılır")
	app.doc.dirty = false
	app._show_toolbar(0)


## Verilen normale sahip B-rep yüzün ekrandaki bir noktası (en büyük üçgenin ağırlık merkezi)
func face_screen_point(n: Vector3) -> Vector2:
	var m: ModelMesh = app.viewport.model
	var best := -1.0
	var out := Vector2(-1, -1)
	for ti in m.tri_count():
		if m.normals[ti].dot(n) < 0.99:
			continue
		if m.areas[ti] > best:
			best = m.areas[ti]
			var c := (m.verts[m.tris[ti * 3]] + m.verts[m.tris[ti * 3 + 1]] + m.verts[m.tris[ti * 3 + 2]]) / 3.0
			out = app.viewport.world_to_screen(c)
	return out


func phase8b() -> void:
	var brep: bool = app.viewport.kernel.is_brep()
	print("== Faz 8b: yüzeyler, kıvırma, statik analiz, eğim analizi, CAM, görselleştirme (%s)" % ("OCC" if brep else "CSG"))
	var tmp := OS.get_user_data_dir().path_join("uitest")
	DirAccess.make_dir_recursive_absolute(tmp)
	var sp: SpecialUI = app.special
	await fresh_doc()
	await rect_sketch("top", Vector2(-20, -10), Vector2(20, 10))
	app._show_toolbar(7)
	check(sp.toolbar_srf.visible and not app.toolbar_features.visible, "Yüzeyler sekmesi ve araç çubuğu")
	app._show_toolbar(8)
	check(sp.toolbar_an.visible and not sp.toolbar_srf.visible, "Analiz sekmesi ve araç çubuğu")
	if not brep:
		app._cmd("srf_extrude")
		check(app.mode != "feature", "CSG çekirdeğinde yüzey özellikleri OpenCASCADE gerektirir")
	else:
		app._cmd("srf_planar")
		check(app.mode == "feature" and app.editing.type == "srf_planar", "Düzlemsel Yüzey paneli")
		app._ok_feature()
		await settle()
		var va: Vector2 = app.viewport.model.volume_and_area()
		check(absf(va.x) < 1e-6 and absf(va.y - 800.0) < 1.0, "düzlemsel yüzey: hacim 0, alan 800 (%.1f, %.1f)" % [va.x, va.y])
		app._cmd("srf_thicken")
		check(app.mode == "feature" and app.editing.type == "srf_thicken", "Kalınlaştır paneli")
		app.editing.params["t"] = 3.0
		app._preview()
		app._ok_feature()
		await settle()
		check(absf(volume() - 2400.0) < 1.0, "kalınlaştır 3 mm: hacim %.1f" % volume())
		check(app.doc.features[app.doc.features.size() - 1].error == "", "yüzey özellikleri hatasız")

		print("   kıvırma (sac metal)")
		await fresh_doc()
		await rect_sketch("top", Vector2(-40, -30), Vector2(40, 30))
		app._cmd("sm_base")
		app.editing.params["T"] = 2.0
		app._ok_feature()
		await settle()
		app.viewport.camera.set_standard_view("iso", false)
		app._fit(false)
		await settle()
		app._cmd("sm_hem")
		await settle()
		check(app.mode == "feature" and app.editing.type == "sm_edge" and is_equal_approx(float(app.editing.params["A"]), 180.0) and app.editing.name == "Kıvırma", "Kıvırma: 180° kenar flanşı hazır")
		var hem_len := 0.0
		for e in app.viewport.model.brep_edges:
			var pe := SheetMetal.parse_edge(e.get("fn", []))
			if pe.is_empty() or str(pe["cap"]) != "b" or str(e.get("type", "")) != "line":
				continue
			var pts: PackedVector3Array = e["pts"]
			send_click(app.viewport.world_to_screen((pts[0] + pts[pts.size() - 1]) * 0.5))
			hem_len = pts[0].distance_to(pts[pts.size() - 1])
			break
		check((app.editing.params["edges"] as Array).size() == 1, "kıvırma kenarı seçildi")
		app._preview()
		app._ok_feature()
		await settle()
		var vh := 9600.0 + hem_len * (PI * 0.5 * (9.0 - 1.0) + 2.0 * 8.0)
		check(absf(volume() - vh) < 1.0, "kıvırma: hacim %.1f ≈ %.1f" % [volume(), vh])

	print("   statik analiz")
	await fresh_doc()
	await rect_sketch("front", Vector2(0, 0), Vector2(100, 10))
	app._cmd("extrude")
	app.editing.params["depth"] = 10.0
	app._preview()
	app._ok_feature()
	await settle()
	app.viewport.camera.set_standard_view("iso", false)
	app._fit(false)
	await settle()
	app._cmd("fea")
	check(app.mode == "fea", "Statik Analiz paneli")
	if not brep:
		sp.run_fea()
		check(sp.fea_res.is_empty() and not sp.fea_busy, "CSG çekirdeğinde analiz çalışmaz, anlamlı mesaj")
	else:
		sp.fea_st["pick"] = "fix"
		send_click(face_screen_point(Vector3.RIGHT))
		sp.fea_st["pick"] = "load"
		sp.fea_st["dir"] = "-y"
		sp.fea_st["mag"] = 100.0
		send_click(face_screen_point(Vector3.UP))
		check((sp.fea_st["fix"] as Array).size() == 1 and (sp.fea_st["loads"] as Array).size() == 1, "sabit yüz ve yük yüzü tıklanarak seçildi")
		sp.fea_st["elements"] = 3000
		sp.run_fea()
		check(sp.fea_busy, "analiz sunucuya gönderildi")
		var t0 := Time.get_ticks_msec()
		while sp.fea_busy and Time.get_ticks_msec() - t0 < 120000:
			await get_tree().process_frame
		await frames(2)
		check(not sp.fea_res.is_empty() and float(sp.fea_res.get("vm_max", 0)) > 0.0 and float(sp.fea_res.get("u_max", 0)) > 0.0,
			"sonuç: σvm %.2f MPa, u %.4f mm" % [float(sp.fea_res.get("vm_max", 0)), float(sp.fea_res.get("u_max", 0))])
		check(sp.result_mi != null and sp.result_mi.visible and not app.viewport.model_mi.visible, "renk haritası gösteriliyor")
		var rr: Array = sp.fea_res.get("reaction", [0, 0, 0])
		check(absf(float(rr[1]) - 100.0) < 0.5, "mesnet tepkisi Ry = %.2f N" % float(rr[1]))
		sp.fea_st["show"] = "disp"
		sp.fea_st["deform"] = 1.0
		sp.update_fea_view()
		check(sp.result_mi.visible and float(sp.fea_res.get("shown_max", 0)) >= float(sp.fea_res.get("u_max", 1)) * 0.999, "yer değiştirme görünümü (şekil değiştirmiş)")
	app._escape()
	check(app.mode == "idle" and app.viewport.model_mi.visible and (sp.result_mi == null or not sp.result_mi.visible), "Esc: sonuç görünümü kapanır")

	print("   eğim analizi")
	app._cmd("draft_an")
	check(app.mode == "draft_an" and not sp.draft_res.is_empty(), "Eğim Analizi paneli ve sonuç")
	# 100×10×10 kutu, çekme +Y: üst pozitif, alt negatif, yanlar eğim gerektirir
	var need := 2200.0 / 4200.0
	check(absf(float(sp.draft_res["need"]) - need) < 0.01 and absf(float(sp.draft_res["pos"]) - 1000.0 / 4200.0) < 0.01, "alan oranları (dik %%%.1f)" % (float(sp.draft_res["need"]) * 100.0))
	check((sp.draft_res["lines"] as Array).size() >= 8, "ayırma çizgisi kenarları (%d)" % (sp.draft_res["lines"] as Array).size())
	sp.draft_st["dir"] = 0
	sp._draft_run()
	check(absf(float(sp.draft_res["pos"]) - 100.0 / 4200.0) < 0.01, "çekme yönü X+: yalnız uç yüz pozitif")
	sp.draft_st["dir"] = 2
	app._escape()

	print("   CAM")
	app._cmd("cam")
	check(app.mode == "cam" and sp.cam_res.has("gcode"), "CAM paneli ve G-kod")
	var per := 2.0 * (100.0 + 10.0) + PI * 6.0
	check(absf(float(sp.cam_res.get("length", 0)) - per * int(sp.cam_res.get("passes", 0))) < per * 0.02, "dış kontur yolu %.1f mm (%d paso)" % [float(sp.cam_res.get("length", 0)), int(sp.cam_res.get("passes", 0))])
	var nc := tmp.path_join("parca8.nc")
	if FileAccess.file_exists(nc):
		DirAccess.remove_absolute(nc)
	app._pending_file_action = "cam_nc"
	app._on_file_selected(nc)
	var gtxt := FileAccess.get_file_as_string(nc)
	check(gtxt.begins_with("(DIY.CAD CAM") and gtxt.contains("G21") and gtxt.contains("Z-5.000") and gtxt.strip_edges().ends_with("M30"), "G-kod dosyası kaydedildi")
	sp.cam_st["op"] = "pocket"
	sp._cam_run()
	check(sp.cam_res.has("gcode") and (sp.cam_res["paths"] as Array).size() >= 1, "cep işlemi yolları (%d halka)" % (sp.cam_res.get("paths", []) as Array).size())
	sp.cam_st["op"] = "outside"
	app._escape()

	print("   görselleştirme")
	app._cmd("render")
	check(app.mode == "render", "Görselleştirme paneli")
	var we := sp._find(app.viewport.world, "WorldEnvironment") as WorldEnvironment
	var bg0 := we.environment.background_mode
	sp.render_st["env"] = "studio"
	sp.apply_render()
	var sun: DirectionalLight3D = sp._render_nodes["sun"]
	check(we.environment.background_mode == Environment.BG_SKY and sun.visible and sun.shadow_enabled and (sp._render_nodes["ground"] as Node3D).visible, "stüdyo ortamı: gökyüzü, gölgeli güneş, zemin")
	check(app.viewport.model_mat.roughness < 0.9, "PBR yüzey ayarı")
	sp.render_st["env"] = "default"
	sp.apply_render()
	check(we.environment.background_mode == bg0 and not sun.visible, "CAD görünümüne geri dönüldü")
	app._escape()
	check(app.mode == "idle", "Esc ile görselleştirmeden çıkılır")
	app.doc.dirty = false
	app._show_toolbar(0)


func rmb_drag(from: Vector2, to: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.position = from
	ev.pressed = true
	app.viewport._on_gui_input(ev)
	for i in 6:
		var m := InputEventMouseMotion.new()
		m.position = from.lerp(to, float(i + 1) / 6.0)
		m.relative = (to - from) / 6.0
		app.viewport._on_gui_input(m)
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_RIGHT
	ev2.position = to
	ev2.pressed = false
	app.viewport._on_gui_input(ev2)


func phase9() -> void:
	var brep: bool = app.viewport.kernel.is_brep()
	print("== Faz 9: kısayollar, seçenekler, fare hareketleri, otomatik kayıt, son dosyalar, makrolar, dil (%s)" % ("OCC" if brep else "CSG"))
	var old_cfg := AppSettings.PATH
	var old_dir := Autosave.DIR
	DirAccess.make_dir_recursive_absolute("user://uitest")
	AppSettings.PATH = "user://uitest/settings9.cfg"
	Autosave.DIR = "user://uitest/autosave9"
	if FileAccess.file_exists(AppSettings.PATH):
		DirAccess.remove_absolute(AppSettings.PATH)
	check(app._commands.has("extrude") and app._commands.has("tool:line") and app._commands.has("fea") and app._commands.has("save"), "komut kaydı (%d komut)" % app._commands.size())
	check(str(app._commands["tool:line"]["ctx"]) == "sketch" and str(app._commands["extrude"]["group"]) == "Özellikler", "komut bağlamı ve grubu")

	print("   makro çalıştırma")
	var r: Dictionary = await app.macro.run_file("res://macros/ornek_flans.gd")
	await settle()
	var vflange := 157777.0
	check(bool(r.get("ok", false)) and absf(volume() - vflange) < vflange * (0.0005 if brep else 0.005), "örnek flanş makrosu: hacim %.0f ≈ %.0f" % [volume(), vflange])
	check(app.doc.part_name == "Flans" and app.doc.features.size() == 8, "makro parçayı kurdu (%d özellik)" % app.doc.features.size())
	var src_part: String = app.macro.part_macro()
	check(src_part.contains("m.new_part(\"Flans\")") and src_part.count("m.add_raw(") == 8, "parçadan makro üretildi")
	await fresh_doc()
	var r2: Dictionary = await app.macro.run_source(src_part, "parca")
	await settle()
	check(bool(r2.get("ok", false)) and absf(volume() - vflange) < vflange * (0.0005 if brep else 0.005), "parça makrosu yeniden oynatıldı: hacim %.0f" % volume())
	var bad: Dictionary = await app.macro.run_source("extends RefCounted\nfunc baska():\n\tpass\n", "hatali")
	check(not bool(bad.get("ok", true)) and str(bad.get("error", "")).contains("run"), "run() olmayan makro reddedilir")

	print("   makro kaydı")
	await fresh_doc()
	app.macro.start_recording()
	await rect_sketch("top", Vector2(-20, -10), Vector2(20, 10))
	app._cmd("extrude")
	app.editing.params["depth"] = 10.0
	app._preview()
	app._ok_feature()
	await settle()
	var rec_src: String = app.macro.stop_recording()
	check(rec_src.count("m.add_raw(") == 2 and not app.macro.recording, "kayıt: taslak + ekstrüzyon")

	print("   otomatik kayıt ve kurtarma")
	check(app.doc.dirty and app.autosave.tick() == 1 and FileAccess.file_exists(Autosave.path_for("part")), "kirli parça otomatik kaydedildi")
	var rec: Variant = JSON.parse_string(FileAccess.get_file_as_string(Autosave.path_for("part")))
	await fresh_doc()
	check(not FileAccess.file_exists(Autosave.path_for("part")), "yeni belgede otomatik kayıt silinir")
	app.recover(rec)
	await settle()
	check(app.doc.features.size() == 2 and app.doc.dirty and absf(volume() - 8000.0) < 1.0, "otomatik kayıttan kurtarıldı (hacim %.0f)" % volume())

	print("   kaydırılmış makro: dolu belgeye oynatma")
	var r3: Dictionary = await app.macro.run_source(rec_src, "kayit")
	await settle()
	check(bool(r3.get("ok", false)) and app.doc.features.size() == 4 and absf(volume() - 8000.0) < 1.0, "kayıt aynı yere ikinci kez eklendi (kimlikler eşlendi, %d özellik)" % app.doc.features.size())
	app.doc.checkpoint()
	app.doc.features.resize(2)
	app.doc.commit()
	await settle()

	print("   son dosyalar ve yedek")
	var tdir := OS.get_environment("TEMP")
	if tdir == "":
		tdir = OS.get_cache_dir()
	var path := tdir.replace("\\", "/").path_join("diycad_uitest9.dcad")
	for p in [path, path + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	app.autosave.tick()
	app._pending_file_action = "save"
	app._on_file_selected(path)
	check(FileAccess.file_exists(path) and AppSettings.recent().size() == 1 and AppSettings.recent()[0] == path, "kaydedilen dosya son dosyalarda")
	check(not FileAccess.file_exists(Autosave.path_for("part")), "kaydedince otomatik kayıt silinir")
	check(app.recent_menu.item_count >= 3, "Dosya → Son Dosyalar menüsü (%d öğe)" % app.recent_menu.item_count)
	AppSettings.set_v("autosave", "backup", true)
	app._cmd("save")
	check(FileAccess.file_exists(path + ".bak"), "kaydederken .bak yedeği")
	await fresh_doc()
	app.open_recent(path)
	await settle()
	check(app.doc.file_path == path and app.doc.features.size() == 2, "son dosyalardan açıldı")
	app.open_recent(tdir.path_join("yok_boyle_bir_dosya.dcad"))
	check(AppSettings.recent().size() == 1, "bulunamayan dosya listeye girmez")

	print("   kısayollar")
	var save_lbl := ""
	for mi in app._menu_items:
		if str(mi[2]) == "save":
			save_lbl = (mi[0] as PopupMenu).get_item_text(int(mi[1]))
	check(save_lbl.ends_with("Ctrl+S"), "menü etiketi kısayol haritasından (%s)" % save_lbl.strip_edges())
	app.keymap.assign("global", "extrude", "Ctrl+E")
	app._refresh_shortcut_labels()
	app._select({"kind": "feature", "id": app.doc.features[0].id})
	app._unhandled_key_input(Keymap.event_of("Ctrl+E"))
	check(app.mode == "feature" and app.editing != null and app.editing.type == "extrude", "özel kısayol (Ctrl+E) Ekstrüzyon açar")
	app._cancel_feature()
	app._select({"kind": "plane", "id": "front"})
	app._cmd("sketch")
	await settle()
	var g0: bool = app.grid_btn.button_pressed
	app._unhandled_key_input(Keymap.event_of("L"))
	app._unhandled_key_input(Keymap.event_of("G"))
	check(app.editor.tool == "line" and app.grid_btn.button_pressed != g0, "taslak bağlamı: L çizgi, G ızgara")

	print("   fare hareketleri")
	app.viewport.rmb_gestures = true
	var c: Vector2 = app.viewport.size * 0.5
	rmb_drag(c, c + Vector2(0, -90))
	check(app.editor.tool == "line" and not app.gesture.visible, "taslakta yukarı hareket: Çizgi")
	app.editor.set_tool("select")
	rmb_drag(c, c + Vector2(64, 64))
	check(app.editor.tool == "arc", "sağ alt: Yay")
	app._exit_sketch()
	await settle()
	app._fit(false)
	rmb_drag(c, c + Vector2(90, 0))
	await settle()
	check(app.status_label.text.begins_with("Fare hareketi") and app.viewport.camera.orient.is_equal_approx(CadCamera.standard_basis("right")), "parçada sağa hareket: Sağ görünüm")
	rmb_drag(c, c + Vector2(8, 3))
	check(not app.gesture.visible, "kısa sürükleme hareket sayılmaz")
	app.viewport.rmb_gestures = false

	print("   seçenekler penceresi")
	app.show_options(1)
	await frames(2)
	var od: OptionsDialog = app.options_dialog
	check(od.visible and od.key_tree.get_root().get_child_count() > 100, "Seçenekler → Klavye kısayolları (%d komut)" % od.key_tree.get_root().get_child_count())
	od.key_search.text = "ekstrüzyon"
	od._fill_keys()
	var hits: int = od.key_tree.get_root().get_child_count()
	check(hits >= 2 and hits < 20, "arama süzer (%d)" % hits)
	od.capturing = "fit"
	od.assign_capture("Ctrl+Shift+F")
	check(app.keymap.find("global", "Ctrl+Shift+F") == "fit", "pencereden kısayol atandı")
	od.capturing = "fit"
	od.assign_capture("Escape")
	check(app.keymap.find("global", "Escape") == "", "sabit tuş atanamaz")
	check(od.gesture_choices("sketch").has("tool:circle") and not od.gesture_choices("part").has("tool:circle"), "fare hareketi seçenekleri bağlama göre")
	od.hide()
	app.keymap.reset()
	app.keymap.save_settings()
	app._refresh_shortcut_labels()

	print("   dil")
	var sk_btn: Button = null
	for ch in app.toolbar_features.get_children():
		if ch is Button and (ch as Button).text == "Taslak":
			sk_btn = ch
	I18n.set_language("en", false)
	app._on_language_changed()
	check(sk_btn != null and sk_btn.atr(sk_btn.text) == "Sketch" and app.tabs.atr("Özellikler") == "Features", "İngilizce: araç çubuğu ve sekmeler")
	save_lbl = ""
	for mi in app._menu_items:
		if str(mi[2]) == "save":
			save_lbl = (mi[0] as PopupMenu).get_item_text(int(mi[1]))
	check(save_lbl.begins_with("Save") and save_lbl.ends_with("Ctrl+S"), "İngilizce menü + kısayol (%s)" % save_lbl.strip_edges())
	I18n.set_language("tr", false)
	app._on_language_changed()
	check(TranslationServer.get_locale().begins_with("tr"), "Türkçeye dönüldü")

	for p2 in [path, path + ".bak"]:
		if FileAccess.file_exists(p2):
			DirAccess.remove_absolute(p2)
	AppSettings.PATH = old_cfg
	Autosave.DIR = old_dir
	app.doc.dirty = false


func phase9b() -> void:
	var brep: bool = app.viewport.kernel.is_brep()
	print("== Faz 9b: arka plan ağ işleme, eklentiler, büyük montaj, çeviri (%s)" % ("OCC" if brep else "CSG"))
	await fresh_doc()
	check(app.viewport.kernel.threaded, "arka plan ağ işleme açık")
	await rect_sketch("top", Vector2(-20, -10), Vector2(20, 10))
	app._cmd("extrude")
	app.editing.params["depth"] = 10.0
	app._preview()
	app._ok_feature()
	await settle()
	check(absf(volume() - 8000.0) < 1.0 and app.viewport.kernel.prepared.is_empty() and app.viewport.kernel.last_post_ms > 0.0,
		"model arka planda hazırlandı (%.1f ms) ve görünüme verildi" % app.viewport.kernel.last_post_ms)
	check(app.viewport.model_mi.mesh != null and app.viewport.model_mi.mesh.get_surface_count() == 1 and not app.viewport.model.feature_edges.is_empty(), "gösterim ağı ve kenarlar")

	print("   eklentiler")
	check(app.plugins.loaded_count() == 2 and app.toolbar_plugins.get_child_count() == 2 and not app.tabs.is_tab_hidden(9), "iki örnek eklenti yüklendi, Eklentiler sekmesi")
	check(app._commands.has("plg_hizli_kutu") and str(app._commands["plg_hizli_kutu"]["group"]) == "Eklentiler", "eklenti komutu kayıtlı (kısayol / fare hareketi atanabilir)")
	app._show_toolbar(9)
	check(app.toolbar_plugins.visible, "Eklentiler araç çubuğu")
	app.run_command("plg_hizli_kutu")
	check(app.mode == "plugin" and app._plugin_panel_api != null and app._plugin_panel_api.plugin_id == "hizli_kutu", "Hızlı Kutu paneli")
	var kutu: Object = null
	var bilgi: Object = null
	for pr in app.plugins._objs:
		if (pr[1] as PluginApi).plugin_id == "hizli_kutu":
			kutu = pr[0]
		elif (pr[1] as PluginApi).plugin_id == "parca_bilgisi":
			bilgi = pr[0]
	kutu.p["et"] = 5.0
	kutu.make()
	await settle()
	var vk := 60.0 * 40.0 * 20.0 - 50.0 * 30.0 * 20.0
	check(app.doc.part_name == "Kutu" and absf(volume() - vk) < 1.0, "eklentiyle içi boş kutu: hacim %.0f ≈ %.0f" % [volume(), vk])
	app.run_command("plg_parca_bilgisi")
	var s: Dictionary = bilgi.summary()
	check(app.mode == "plugin" and int(s["features"]) == 2 and absf(float(s["volume"]) - vk) < 1.0, "Parça Bilgisi özeti (%d özellik)" % int(s["features"]))
	app.doc.checkpoint()
	app.doc.features[1].params["depth"] = 10.0
	app.doc.commit()
	await settle()
	check(absf(float(bilgi.summary()["volume"]) - vk * 0.5) < 1.0 and app.mode == "plugin", "model değişince panel güncel kalır")
	app._escape()
	check(app.mode == "idle", "Esc eklenti panelini kapatır")
	app._show_toolbar(0)

	print("   büyük montaj")
	app.asm_mode.build_demo()
	await asm_settle()
	app.asm_mode.finish_demo()
	await asm_settle()
	var am = app.asm_mode
	check(am.is_open() and am.asm.comps.size() >= 2, "örnek montaj açıldı (%d bileşen)" % am.asm.comps.size())
	var any_meta := true
	for k in am.parts:
		var pm: Mesh = am.parts[k].get("mesh", null)
		if pm == null or not pm.has_meta("tris"):
			any_meta = false
	check(any_meta, "bileşen ağları LOD hazırlığından geçti")
	check(not am.view.large, "küçük montajda büyük montaj modu kapalı")
	am.large_auto = false
	am.large_mode = true
	am.sel = {}
	am.hover = -1
	am.refresh()
	var vis := 0
	for id in am.view.nodes:
		if (am.view.nodes[id]["edges"] as MeshInstance3D).visible:
			vis += 1
	check(am.view.large and vis == 0, "büyük montaj modu: seçimsizken kenar çizgisi yok")
	var cid := int(am.asm.comps[0]["id"])
	am.sel = {"kind": "comp", "id": cid}
	am.refresh()
	check((am.view.nodes[cid]["edges"] as MeshInstance3D).visible, "seçili bileşenin kenarları görünür")
	am.large_auto = true
	am.large_mode = false
	am.sel = {}
	am.refresh()
	app._close_assembly_ui()
	await settle()

	print("   çeviri")
	I18n.set_language("en", false)
	app._set_status(I18n.t("Açıldı: ") + "x.dcad")
	check(app.status_label.text == "Opened: x.dcad", "biçimli durum mesajı İngilizce")
	app._show_help()
	check(app.info_dialog.dialog_text.begins_with("MOUSE"), "İngilizce yardım")
	app.info_dialog.hide()
	I18n.set_language("tr", false)
	app._on_language_changed()
	app.doc.dirty = false
