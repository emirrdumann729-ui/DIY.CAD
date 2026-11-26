extends SceneTree
## Faz 9 testleri (çekirdek gerektirmez): ayarlar ve son dosyalar, otomatik kayıt kayıtları, kısayol haritası,
## fare hareketi yönleri, makro başvuru eşleme, sözlük ve tema.
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/pro_test.gd

var fails := 0
var passes := 0
const TMP := "user://test_pro"


func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		print("  OK   ", label)
	else:
		fails += 1
		print("  FAIL ", label)


func _initialize() -> void:
	# Kullanıcının gerçek ayarlarına / otomatik kayıtlarına dokunma
	DirAccess.make_dir_recursive_absolute(TMP)
	AppSettings.PATH = TMP.path_join("settings.cfg")
	Autosave.DIR = TMP.path_join("autosave")
	if FileAccess.file_exists(AppSettings.PATH):
		DirAccess.remove_absolute(AppSettings.PATH)
	run_settings()
	run_autosave()
	run_keymap()
	run_gesture()
	run_macro_remap()
	run_i18n()
	run_theme()
	run_perf()
	run_plugins()
	run_i18n_fmt()
	run_stl()
	print("")
	print("PRO SONUÇ: %d başarılı, %d başarısız" % [passes, fails])
	quit(1 if fails > 0 else 0)


func run_settings() -> void:
	print("== Ayarlar ve son dosyalar")
	check(str(AppSettings.get_v("ui", "theme")) == "dark" and float(AppSettings.get_v("autosave", "interval_min")) == 5.0, "varsayılan değerler")
	AppSettings.set_v("ui", "scale", 1.25)
	check(float(AppSettings.get_v("ui", "scale")) == 1.25, "ayar yazılıp okunur")
	check(AppSettings.is_internal_path(OS.get_user_data_dir().path_join("x.dcad")) and AppSettings.is_internal_path("user://a.dcad"), "kullanıcı veri klasörü iç yol sayılır")
	AppSettings.add_recent("user://test.dcad")
	check(AppSettings.recent().is_empty(), "iç yollar son dosyalara girmez")
	for i in 12:
		AppSettings.add_recent("C:/Parcalar/p%d.dcad" % i)
	AppSettings.add_recent("C:\\Parcalar\\p3.dcad")
	var r := AppSettings.recent()
	check(r.size() == AppSettings.MAX_RECENT and r[0] == "C:/Parcalar/p3.dcad" and r.count("C:/Parcalar/p3.dcad") == 1, "en yeni başta, tekrar yok, en çok %d (%s)" % [AppSettings.MAX_RECENT, r[0]])
	AppSettings.remove_recent("C:/Parcalar/p3.dcad")
	check(not AppSettings.recent().has("C:/Parcalar/p3.dcad"), "listeden çıkarma")
	AppSettings.clear_recent()
	check(AppSettings.recent().is_empty(), "liste temizlenir")


func _write_rec(name: String, pid: int) -> void:
	DirAccess.make_dir_recursive_absolute(Autosave.DIR)
	var fa := FileAccess.open(Autosave.DIR.path_join(name), FileAccess.WRITE)
	fa.store_string(JSON.stringify({"kind": "part", "name": name, "pid": pid, "time": Time.get_unix_time_from_system(), "source": "", "data": {"features": []}}))
	fa.close()


func run_autosave() -> void:
	print("== Otomatik kayıt kayıtları")
	_write_rec("part_1.json", 1)                       # ölü süreç (pid 1 Windows'ta kullanıcı süreci değildir)
	_write_rec("part_self.json", OS.get_process_id())  # bu süreç: kurtarılmaz
	var p := Autosave.pending()
	var names: Array = []
	for rec in p:
		names.append(str(rec["name"]))
	check(names.has("part_1.json") and not names.has("part_self.json"), "yalnız çalışmayan süreçlerin kayıtları kurtarılır (%s)" % str(names))
	for rec2 in p:
		Autosave.discard(rec2)
	DirAccess.remove_absolute(Autosave.DIR.path_join("part_self.json"))
	check(Autosave.pending().is_empty(), "kayıt silinir")
	check(Autosave.path_for("asm", 42).ends_with("asm_42.json"), "kayıt dosya adı tür + süreç kimliği")


func run_keymap() -> void:
	print("== Kısayol haritası")
	var k := InputEventKey.new()
	k.keycode = KEY_S
	k.ctrl_pressed = true
	k.shift_pressed = true
	check(Keymap.shortcut_of(k) == "Ctrl+Shift+S", "olay → kısayol metni (%s)" % Keymap.shortcut_of(k))
	var e := Keymap.event_of("Ctrl+Alt+F5")
	check(e.ctrl_pressed and e.alt_pressed and not e.shift_pressed and e.keycode == KEY_F5 and Keymap.shortcut_of(e) == "Ctrl+Alt+F5", "kısayol metni → olay → metin")
	var mod := InputEventKey.new()
	mod.keycode = KEY_CTRL
	mod.ctrl_pressed = true
	check(Keymap.shortcut_of(mod) == "", "yalnız değiştirici tuş kısayol değildir")
	var km := Keymap.new()
	check(km.find("global", "Ctrl+Z") == "undo" and km.find("sketch", "L") == "tool:line" and km.find("global", "L") == "", "varsayılan atamalar ve bağlamlar")
	check(km.shortcuts_for("redo").size() == 2 and km.is_default(), "yinele iki kısayol; harita varsayılan")
	var lost := km.assign("global", "extrude", "Ctrl+Z")
	check(lost == "undo" and km.find("global", "Ctrl+Z") == "extrude" and km.shortcut_for("undo") == "", "çakışan kısayol önceki komuttan alınır")
	km.assign("global", "extrude", "E")
	check(km.find("global", "Ctrl+Z") == "" and km.find("global", "E") == "extrude" and km.find("sketch", "E") == "tool:extend", "yeniden atama eskisini kaldırır; taslak bağlamı ayrı")
	check(not km.is_default() and Keymap.is_fixed("Escape") and not Keymap.is_fixed("F5"), "değişen harita; sabit tuşlar")
	km.save_settings()
	var km2 := Keymap.new()
	km2.load_settings()
	check(km2.find("global", "E") == "extrude" and km2.bindings.size() == km.bindings.size(), "ayarlar dosyasına kaydedilip yüklenir")
	km2.reset()
	check(km2.is_default(), "varsayılana dönüş")
	AppSettings.erase_section("keys")


func run_gesture() -> void:
	print("== Fare hareketleri")
	check(MouseGesture.dir_index(Vector2(0, -60)) == 0 and MouseGesture.dir_index(Vector2(60, 0)) == 2 and MouseGesture.dir_index(Vector2(0, 60)) == 4 and MouseGesture.dir_index(Vector2(-60, 0)) == 6, "dört ana yön")
	check(MouseGesture.dir_index(Vector2(50, -50)) == 1 and MouseGesture.dir_index(Vector2(-50, -50)) == 7 and MouseGesture.dir_index(Vector2(50, 50)) == 3, "çapraz yönler")
	check(MouseGesture.dir_index(Vector2(10, 5)) == -1, "ölü bölge")
	check(MouseGesture.mapping("sketch")[0] == "tool:line" and MouseGesture.mapping("part")[2] == "view_right", "varsayılan atamalar")
	var arr := MouseGesture.mapping("part")
	arr[0] = "extrude"
	MouseGesture.save_mapping("part", arr)
	check(MouseGesture.mapping("part")[0] == "extrude", "atama kaydedilir")
	AppSettings.erase_section("gestures")
	check(MouseGesture.mapping("part")[0] == "view_top", "silinince varsayılan")


func run_macro_remap() -> void:
	print("== Makro başvuru eşleme")
	var ids := {3: 10, 5: 12}
	var p: Variant = MacroApi._remap({"sketch": 3, "features": [3, 4], "path": {"kind": "sketch", "id": 5}, "depth": 3,
		"edges": [{"fn": ["F3:s:2", "F4:a"]}], "plane": "pl:5", "axis": "ax:3"}, ids)
	check(int(p["sketch"]) == 10 and p["features"] == [10, 4] and int(p["path"]["id"]) == 12, "taslak / özellik listesi / yol kimlikleri")
	check(int(p["depth"]) == 3, "sayısal parametreler değişmez")
	check(p["edges"][0]["fn"] == ["F10:s:2", "F4:a"] and p["plane"] == "pl:12" and p["axis"] == "ax:10", "topolojik adlar ve referans değerleri")


func run_i18n() -> void:
	print("== Dil sözlüğü")
	var d := I18n.load_dict("en")
	check(d.size() > 900, "İngilizce sözlük yüklendi (%d girdi)" % d.size())
	check(d.get("Dosya", "") == "File" and d.get("Ekstrüzyon\nPatron/Taban", "") == "Extruded\nBoss/Base", "menü ve iki satırlı araç çubuğu metni")
	I18n.set_language("en", false)
	check(TranslationServer.translate("Özellikler") == "Features" and I18n.t("Seçenekler") == "Options", "otomatik çeviri sunucusu")
	I18n.set_language("tr", false)
	check(I18n.t("Seçenekler") == "Seçenekler", "Türkçeye dönüş")
	var missing := 0
	for k in d:
		if str(d[k]).strip_edges() == "":
			missing += 1
	check(missing == 0, "boş çeviri yok")


func run_theme() -> void:
	print("== Tema")
	check(UiTheme.build_theme() == null and UiTheme.adapt(Color(0.8, 0.8, 0.8)) == Color(0.8, 0.8, 0.8), "koyu tema: Godot varsayılanı, renkler değişmez")
	UiTheme.light = true
	var t := UiTheme.build_theme()
	var c := UiTheme.adapt(Color(0.75, 0.78, 0.82))
	check(t != null and t.has_stylebox("panel", "PopupMenu") and t.get_color("font_color", "Label").v < 0.3, "açık tema nesnesi")
	check(c.v < 0.5, "açık temada açık metin rengi koyulaştırılır (%.2f)" % c.v)
	UiTheme.light = false


func _big_mesh() -> ArrayMesh:
	var cm := CylinderMesh.new()
	cm.radial_segments = 256
	cm.rings = 48
	cm.height = 40.0
	cm.top_radius = 10.0
	cm.bottom_radius = 10.0
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cm.get_mesh_arrays())
	return am


func run_perf() -> void:
	print("== Arka plan ağ işleme ve LOD")
	var src := _big_mesh()
	var a := ModelMesh.new()
	a.build(src, {})
	var job := MeshJob.new()
	job.surfs = ModelMesh.surfaces_of(src)
	job.aabb = src.get_aabb()
	var tid := WorkerThreadPool.add_task(job.run)
	WorkerThreadPool.wait_for_task_completion(tid)
	check(job.model != null and job.model.tri_count() == a.tri_count() and job.model.feature_edges.size() == a.feature_edges.size(), "iş parçacığında hazırlanan model aynı (%d üçgen, %.0f ms)" % [job.model.tri_count(), job.ms])
	var disp_a := a.display_arrays()
	check((job.display[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() == (disp_a[Mesh.ARRAY_NORMAL] as PackedVector3Array).size(), "gösterim dizileri aynı boyutta")
	var nm: PackedVector3Array = job.display[Mesh.ARRAY_NORMAL]
	check(absf(nm[0].length() - 1.0) < 1e-3, "yumuşatılmış normaller birim uzunlukta")
	var b := ModelMesh.new()
	b.copy_from(job.model)
	check(b.tri_count() == a.tri_count() and b.aabb.is_equal_approx(a.aabb) and absf(b.volume_and_area().x - a.volume_and_area().x) < 1e-3, "copy_from")
	var disp := a.display_mesh()
	var lod := AsmLod.with_lods(disp)
	check(int(lod.get_meta("tris", 0)) == a.tri_count() and int(lod.get_meta("lods", 0)) > 0, "büyük ağa LOD eklendi (%d seviye)" % int(lod.get_meta("lods", 0)))
	var small := BoxMesh.new()
	var sm := ArrayMesh.new()
	sm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, small.get_mesh_arrays())
	check(AsmLod.with_lods(sm) == sm and int(sm.get_meta("lods", -1)) == 0, "küçük ağ olduğu gibi kalır")


func run_plugins() -> void:
	print("== Eklentiler")
	var found := Plugins.discover()
	var ids: Array = []
	for p in found:
		ids.append(Plugins.id_of(p))
	check(ids.has("hizli_kutu") and ids.has("parca_bilgisi"), "örnek eklentiler bulundu (%s)" % str(ids))
	check(Plugins._const_str(FileAccess.get_file_as_string("res://plugins/hizli_kutu.gd"), "NAME") == "Hızlı Kutu", "eklenti adı kaynaktan okunur")
	check(Plugins.id_of("C:/x/plugins/benim/plugin.gd") == "benim", "klasör eklentisi kimliği")
	Plugins.set_enabled("hizli_kutu", false)
	check(Plugins.disabled() == ["hizli_kutu"], "eklenti kapatılır")
	Plugins.set_enabled("hizli_kutu", true)
	check(Plugins.disabled().is_empty(), "eklenti açılır")
	check(AppSettings.app_dir("plugins").ends_with("plugins") and not OS.has_feature("template"), "program klasörü (geliştirme: proje klasörü)")


func run_i18n_fmt() -> void:
	print("== Biçimli metin çevirisi")
	var d := I18n.load_dict("en")
	var k := "Analiz tamam: en büyük von Mises %.2f MPa, en büyük yer değiştirme %s (%d eleman, %.1f sn)"
	check(d.has(k) and str(d[k]).count("%") == 4, "biçimli mesaj çevirisi belirteçleri korur")
	var re := RegEx.new()
	re.compile("%[-+ 0#]*\\d*(?:\\.\\d+)?[sdfiexXc]")
	var bad := 0
	for key in d:
		var a: Array = []
		for m in re.search_all(str(key)):
			a.append(m.get_string())
		var b: Array = []
		for m2 in re.search_all(str(d[key])):
			b.append(m2.get_string())
		if a != b:
			bad += 1
	check(bad == 0, "tüm çevirilerde biçim belirteçleri aynı sırada (%d uyumsuz)" % bad)
	var ws := 0
	for key2 in d:
		if str(key2).ends_with(" ") != str(d[key2]).ends_with(" "):
			ws += 1
	check(ws == 0, "sondaki boşluklar korunur (birleştirilen metinler için, %d uyumsuz)" % ws)
	check(FileAccess.file_exists("res://i18n/help_en.txt") and FileAccess.get_file_as_string("res://i18n/help_en.txt").begins_with("MOUSE"), "İngilizce yardım metni")

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


func run_stl() -> void:
	print("== STL içe aktarma ve gövde dönüşümü")
	var p := TMP.path_join("kutu.stl")
	write_box_stl(p, Vector3(0, 0, 0), Vector3(100, 10, 20))
	var t := StlImport.read(p)
	check(t.size() == 36, "ikili STL okundu (%d köşe)" % t.size())
	var pa := TMP.path_join("kutu_ascii.stl")
	write_box_stl(pa, Vector3(0, 0, 0), Vector3(100, 10, 20), true)
	check(StlImport.read(pa).size() == 36, "ASCII STL okundu")
	var prm := {"sx": 0.5, "sy": 2.0, "sz": 3.0, "origin": [10.0, 0.0, 0.0], "move": [-10.0, 1.0, 0.0]}
	var bb := StlImport.bounds(StlImport.transformed(t, prm))
	check(bb.position.is_equal_approx(Vector3(-5, 1, 0)) and bb.size.is_equal_approx(Vector3(50, 20, 60)), "eksen bazlı ölçek + merkez + öteleme (%s)" % str(bb))
	prm["stretch"] = {"axis": "x", "a": 20.0, "b": 80.0, "add": 40.0}
	var bb2 := StlImport.bounds(StlImport.transformed(t, prm))
	check(is_equal_approx(bb2.size.x, 90.0) and is_equal_approx(bb2.position.x, -5.0), "bölgesel uzatma son boya +40 mm ekler (%.2f)" % bb2.size.x)
	var mm := ModelMesh.new()
	mm.build(StlImport.to_mesh(StlImport.transformed(t, prm)), {})
	check(absf(mm.volume_and_area().x - 90.0 * 20.0 * 60.0) < 1e-2, "dönüştürülmüş ağ kapalı, hacim %.1f" % mm.volume_and_area().x)
	var mir := StlImport.transformed(t, {"sx": -1.0})
	var mm2 := ModelMesh.new()
	mm2.build(StlImport.to_mesh(mir), {})
	check(mm2.volume_and_area().x > 0.0, "aynalamada sarım düzeltilir (hacim pozitif)")
	check(str(StlImport.xform_of({"stretch": {"axis": "x", "a": 5.0, "b": 5.0, "add": 1.0}})["error"]) != "", "geçersiz uzatma bölgesi hata verir")
	# Kademeli kesit büyütme: x 0→100 boyunca kesit 10×20'den 20×40'a (eklenen mm doğrusal)
	var tp := {"taper": {"axis": "x", "a": 0.0, "b": 100.0, "grow": [10.0, 20.0], "profile": [[0.0, 5.0, 10.0, 10.0, 20.0], [100.0, 5.0, 10.0, 10.0, 20.0]]}}
	var tt := StlImport.transformed(t, tp)
	var bb3 := StlImport.bounds(tt)
	var front := PackedVector3Array()
	for v in tt:
		if absf(v.x) < 1e-6:
			front.append(v)
	var fb := StlImport.bounds(front)
	check(bb3.size.is_equal_approx(Vector3(100, 20, 40)) and fb.size.is_equal_approx(Vector3(0, 10, 20)), "kademeli büyütme: ön kesit aynı, arka kesit +10 / +20 mm (%s)" % str(bb3.size))
	var mm3 := ModelMesh.new()
	mm3.build(StlImport.to_mesh(tt), {})
	check(absf(mm3.volume_and_area().x - 200.0 * 100.0 * 7.0 / 3.0) < 1.0, "kademeli büyütme hacmi (kesik piramit) %.1f" % mm3.volume_and_area().x)
	# Çok bölgeli uzatma: +10 (x 10..20) ve −5 (x 50..60) → boy 105
	var ms := StlImport.transformed(t, {"stretch": [{"axis": "x", "a": 10.0, "b": 20.0, "add": 10.0}, {"axis": "x", "a": 50.0, "b": 60.0, "add": -5.0}]})
	var mm4 := ModelMesh.new()
	mm4.build(StlImport.to_mesh(ms), {})
	check(is_equal_approx(StlImport.bounds(ms).size.x, 105.0) and absf(mm4.volume_and_area().x - 105.0 * 200.0) < 1e-2,
		"çok bölgeli uzatma: boy %.2f, hacim %.1f" % [StlImport.bounds(ms).size.x, mm4.volume_and_area().x])
	# Koruma bölgesi: Y ≥ 6 katmanı (Z'de tamamı) ölçeklenmez, yalnızca +3 (Y) ötelenir; katman altı 2 mm'de normale bağlanır
	var pz := {"sy": 2.0, "sz": 2.0, "protect": {"axis": "x", "a": 20.0, "b": 80.0, "blend": 10.0, "bands": [[6.0, null], null],
		"soft": [2.0, 2.0], "offset": [3.0, 0.0]}}
	var xz := StlImport.xform_of(pz)
	check(str(xz["error"]) == "", "koruma bölgesi ayrıştırıldı %s" % str(xz["error"]))
	var cases := [[Vector3(50, 8, 15), Vector3(50, 11, 15), "bant içi yalnızca ötelenir"],
		[Vector3(50, 5, 15), Vector3(50, 8.5, 22.5), "katman kenarı geçişi doğrusal (şerit yarı etkili)"],
		[Vector3(50, 2, 15), Vector3(50, 4, 30), "katman dışı normal ölçek (şerit etkisiz)"],
		[Vector3(15, 8, 15), Vector3(15, 13.5, 22.5), "bölge ucu geçişi (yarı yolda)"],
		[Vector3(5, 8, 15), Vector3(5, 16, 30), "bölge dışı normal dönüşüm"]]
	for cs: Array in cases:
		var got := StlImport.xform_point(cs[0], xz)
		check(got.is_equal_approx(cs[1]), "koruma: %s (%s)" % [cs[2], str(got)])
	pz["protect"] = {"axis": "x", "a": -1.0, "b": 101.0, "blend": 0.0, "bands": [[6.0, null], null], "soft": [2.0, 2.0], "offset": [3.0, 0.0]}
	var pt := StlImport.transformed(t, pz)
	var mm5 := ModelMesh.new()
	mm5.build(StlImport.to_mesh(pt), {})
	var pb := StlImport.bounds(pt)
	check(pb.size.is_equal_approx(Vector3(100, 13, 40)) and absf(mm5.volume_and_area().x - 43000.0) < 0.1 and pt.size() > 36,
		"koruma bölgeli kutu: %s, hacim %.1f, %d üçgen (kırılma düzlemlerinden kesildi)" % [str(pb.size), mm5.volume_and_area().x, pt.size() / 3])
	var xpf := StlImport.xform_of({"sy": 2.0, "protect": {"axis": "x", "a": 0.0, "b": 100.0, "bands": [[[0.0, 6.0, null], [100.0, 8.0, null]], null], "soft": [2.0, 2.0], "offset": [0.0, 0.0]}})
	var gp := StlImport.xform_point(Vector3(50, 9, 5), xpf)
	check(gp.is_equal_approx(Vector3(50, 9, 5)), "profilli, üstü sınırsız katman (ara konumda NaN yok): %s" % str(gp))
	check(str(StlImport.xform_of({"protect": {"axis": "x", "a": 5.0, "b": 1.0}})["error"]) != "", "geçersiz koruma bölgesi hata verir")
	check(str(StlImport.xform_of({"protect": {"axis": "x", "a": 0.0, "b": 1.0, "bands": [[5.0, 2.0]]}})["error"]) != "", "ters bant hata verir")
