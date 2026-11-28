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
	run_export()
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
	check(I18n.LANGS.keys() == ["tr", "en", "de", "ru", "zh"], "diller: Türkçe, İngilizce, Almanca, Rusça, Çince")
	var expect := {"de": ["Optionen", "Skizze"], "ru": ["Параметры", "Эскиз"], "zh": ["选项", "草图"]}
	for lang in I18n.LANGS:
		if lang == "tr":
			continue
		var dl := I18n.load_dict(lang)
		var missing := 0
		for k in d:
			if not dl.has(k) or str(dl[k]).strip_edges() == "":
				missing += 1
		check(dl.size() == d.size() and missing == 0, "%s sözlüğü tam (%d girdi, %d eksik)" % [lang, dl.size(), missing])
		check(str(dl.get("Türkçe", "")) == "Türkçe" and str(dl.get("English", "")) == "English", "%s: dil adları çevrilmez" % lang)
		if expect.has(lang):
			I18n.set_language(lang, false)
			check(I18n.t("Seçenekler") == expect[lang][0] and TranslationServer.translate("Taslak") == expect[lang][1], "%s: çeviri sunucusu" % lang)
	I18n.set_language("tr", false)


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
	var heads := {"en": "MOUSE", "de": "MAUS", "ru": "МЫШЬ", "zh": "鼠标"}
	for lang in I18n.LANGS:
		if lang == "tr":
			continue
		var dl := I18n.load_dict(lang)
		var bad := 0
		var ws := 0
		var nl := 0
		for key in dl:
			var a: Array = []
			for m in re.search_all(str(key)):
				a.append(m.get_string())
			var b: Array = []
			for m2 in re.search_all(str(dl[key])):
				b.append(m2.get_string())
			if a != b:
				bad += 1
			if str(key).ends_with(" ") != str(dl[key]).ends_with(" "):
				ws += 1
			if lang != "en" and str(d.get(key, "")).count("\n") != str(dl[key]).count("\n"):
				nl += 1      # iki satırlı araç çubuğu düğmeleri İngilizcedeki gibi kalır
		check(bad == 0, "%s: biçim belirteçleri aynı sırada (%d uyumsuz)" % [lang, bad])
		check(ws == 0, "%s: sondaki boşluklar korunur (birleştirilen metinler için, %d uyumsuz)" % [lang, ws])
		check(nl == 0, "%s: satır sayısı İngilizceyle aynı (iki satırlı düğmeler, %d uyumsuz)" % [lang, nl])
		var hp := "res://i18n/help_%s.txt" % lang
		var htxt := FileAccess.get_file_as_string(hp) if FileAccess.file_exists(hp) else ""
		check(htxt.begins_with(str(heads.get(lang, "?"))) and (htxt.contains("Ctrl+E") or htxt.contains("Strg+E")), "%s yardım metni" % lang)

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


func run_export() -> void:
	print("== Dışa aktarma formatları")
	var ids := {}
	var dup := false
	var desc_ok := true
	for f in ExportFormats.FORMATS:
		dup = dup or ids.has(f["id"])
		ids[f["id"]] = true
		desc_ok = desc_ok and str(f.get("desc", "")) != "" and not (f["ext"] as Array).is_empty()
	check(not dup and desc_ok and ExportFormats.FORMATS.size() >= 45, "format listesi: %d format, kimlikler benzersiz, açıklama ve uzantı var" % ExportFormats.FORMATS.size())
	var untr: Array = []
	for lang in ["en", "de", "ru", "zh"]:
		var dl := I18n.load_dict(lang)
		for f in ExportFormats.FORMATS:
			for k in ["group", "label", "desc"]:
				if not dl.has(str(f[k])) and not untr.has(lang + ":" + str(f[k])):
					untr.append(lang + ":" + str(f[k]))
	check(untr.is_empty(), "format metinlerinin tüm dillerde çevirisi var %s" % str(untr.slice(0, 3)))
	check(ExportFormats.with_ext("a/b", ExportFormats.by_id("step203")) == "a/b.step" and ExportFormats.with_ext("a/b.STP", ExportFormats.by_id("step214")) == "a/b.STP", "uzantı tamamlama")
	var p := TMP.path_join("kutu_exp.stl")
	write_box_stl(p, Vector3(0, 0, 0), Vector3(100, 10, 20))
	var tris := StlImport.read(p)
	var groups := ExportFormats.one_group(tris, "Kutu", Color(0.8, 0.2, 0.1))
	for id in ["stl", "obj", "3mf", "amf", "ply", "off", "fbx", "glb", "gltf", "wrl", "xaml", "ifc", "html"]:
		var out := TMP.path_join("kutu_exp." + id)
		var err := ExportFormats.write_mesh(id, out, tris, groups, "Kutu")
		check(err == OK and FileAccess.get_file_as_bytes(out).size() > 50, "%s yazıldı (%d bayt)" % [id, FileAccess.get_file_as_bytes(out).size()])
	check(ExportFormats.write_mesh("ply", TMP.path_join("bos.ply"), PackedVector3Array(), []) != OK, "boş ağ hata verir")
	var ply := FileAccess.get_file_as_bytes(TMP.path_join("kutu_exp.ply")).get_string_from_ascii()
	check(ply.begins_with("ply\nformat binary_little_endian") and ply.contains("element vertex 8") and ply.contains("element face 12"), "PLY: 8 köşe, 12 yüz")
	check(FileAccess.get_file_as_string(TMP.path_join("kutu_exp.off")).split("\n")[2] == "8 12 0", "OFF: 8 köşe, 12 yüz")
	var zr := ZIPReader.new()
	var model := ""
	if zr.open(TMP.path_join("kutu_exp.3mf")) == OK:
		model = zr.read_file("3D/3dmodel.model").get_string_from_utf8()
		check(zr.get_files().has("[Content_Types].xml") and zr.get_files().has("_rels/.rels"), "3MF paket yapısı")
		zr.close()
	check(model.count("<vertex ") == 8 and model.count("<triangle ") == 12 and model.contains('unit="millimeter"') and model.contains("#CC331A"), "3MF: 8 köşe, 12 üçgen, mm, renk")
	for id in ["amf", "xaml", "3mf_model"]:
		var txt := model if id == "3mf_model" else FileAccess.get_file_as_string(TMP.path_join("kutu_exp." + id))
		check(_xml_ok(txt), "%s geçerli XML" % id)
	check(FileAccess.get_file_as_string(TMP.path_join("kutu_exp.amf")).count("<triangle>") == 12, "AMF: 12 üçgen")
	var gj = JSON.parse_string(FileAccess.get_file_as_string(TMP.path_join("kutu_exp.gltf")))
	check(gj is Dictionary and int(gj["accessors"][0]["count"]) == 36 and is_equal_approx(float(gj["accessors"][0]["max"][0]), 0.1), "glTF: 36 köşe, metre birimi")
	var aabbs := {}
	for id in ["glb", "gltf"]:
		var gd := GLTFDocument.new()
		var st := GLTFState.new()
		var e := gd.append_from_file(ProjectSettings.globalize_path(TMP.path_join("kutu_exp." + id)), st)
		var scene := gd.generate_scene(st) if e == OK else null
		aabbs[id] = _scene_aabb(scene)
		if scene:
			scene.free()
	check(aabbs["glb"].size.is_equal_approx(Vector3(0.1, 0.01, 0.02)) and aabbs["gltf"].size.is_equal_approx(Vector3(0.1, 0.01, 0.02)), "GLB / glTF Godot ile geri okundu: %s" % str(aabbs["glb"].size))
	if ClassDB.class_exists("FBXDocument"):
		var fd: Object = ClassDB.instantiate("FBXDocument")
		var fs: Object = ClassDB.instantiate("FBXState")
		var fe: int = fd.call("append_from_file", ProjectSettings.globalize_path(TMP.path_join("kutu_exp.fbx")), fs)
		var fsc: Node = fd.call("generate_scene", fs) if fe == OK else null
		var fb := _scene_aabb(fsc)
		check(fe == OK and fb.size.length() > 0.0, "FBX Godot ile geri okundu: %s" % str(fb.size))
		if fsc:
			fsc.free()
	var ifc := FileAccess.get_file_as_string(TMP.path_join("kutu_exp.ifc"))
	check(ifc.begins_with("ISO-10303-21;") and ifc.contains("FILE_SCHEMA(('IFC4'))") and ifc.contains("IFCTRIANGULATEDFACESET") and ifc.contains("IFCBUILDINGELEMENTPROXY") and ifc.strip_edges().ends_with("END-ISO-10303-21;"), "IFC4 yapısı")
	check(FileAccess.get_file_as_string(TMP.path_join("kutu_exp.wrl")).begins_with("#VRML V2.0 utf8") and FileAccess.get_file_as_string(TMP.path_join("kutu_exp.wrl")).contains("IndexedFaceSet"), "VRML yapısı")
	var html := FileAccess.get_file_as_string(TMP.path_join("kutu_exp.html"))
	check(html.begins_with("<!DOCTYPE html>") and html.contains("getContext('webgl'") and not html.contains("__POS__"), "HTML görüntüleyici (veri gömülü)")
	check(FileAccess.file_exists(TMP.path_join("kutu_exp.mtl")) and FileAccess.get_file_as_string(TMP.path_join("kutu_exp.obj")).count("\nf ") == 12, "OBJ + MTL")
	# Görüntüler
	var img := Image.create(64, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.4, 0.8))
	img.set_pixel(5, 7, Color(1, 0, 0))
	for id in ["png", "jpg", "bmp", "tif", "psd"]:
		var out := TMP.path_join("resim." + id)
		check(ExportFormats.write_image(out, img, id) == OK and FileAccess.file_exists(out), "%s görüntüsü yazıldı" % id)
	var bmp := Image.new()
	bmp.load_bmp_from_buffer(FileAccess.get_file_as_bytes(TMP.path_join("resim.bmp")))
	check(bmp.get_size() == Vector2i(64, 48) and bmp.get_pixel(5, 7).r > 0.95 and bmp.get_pixel(20, 20).b > 0.75, "BMP geri okundu (boyut ve pikseller)")
	var tif := FileAccess.get_file_as_bytes(TMP.path_join("resim.tif"))
	check(tif[0] == 0x49 and tif[1] == 0x49 and tif.decode_u16(2) == 42 and tif.size() == 8 + 2 + 11 * 12 + 4 + 8 + 64 * 48 * 4, "TIFF başlığı ve boyutu")
	var psd := FileAccess.get_file_as_bytes(TMP.path_join("resim.psd"))
	check(psd.slice(0, 4).get_string_from_ascii() == "8BPS" and psd[13] == 3 and psd[17] == 48 and psd[21] == 64 and psd.size() == 26 + 12 + 2 + 64 * 48 * 3, "PSD başlığı ve boyutu")
	var jp := Image.new()
	check(jp.load_jpg_from_buffer(FileAccess.get_file_as_bytes(TMP.path_join("resim.jpg"))) == OK and jp.get_width() == 64, "JPEG geri okundu")
	# XML ve ZIP
	var xp := TMP.path_join("veri.xml")
	ExportFormats.write_xml(xp, "diycad", {"part": {"name": "Kutu & <1>"}, "features": [{"name": "Ekstrüzyon1"}, {"name": "Kesme1"}], "mass": 12.5})
	var xt := FileAccess.get_file_as_string(xp)
	check(_xml_ok(xt) and xt.contains("<feature>") and xt.contains("Kutu &amp; &lt;1&gt;"), "XML yapısı ve kaçışlar")
	var zp := TMP.path_join("paket.zip")
	ExportFormats.write_zip(zp, [{"name": "a.xml", "path": xp}, {"name": "b.ply", "path": TMP.path_join("kutu_exp.ply")}])
	var zr2 := ZIPReader.new()
	check(zr2.open(zp) == OK and zr2.get_files().size() == 2 and zr2.read_file("a.xml").get_string_from_utf8() == xt, "ZIP paketi")
	zr2.close()
	# Yerel dosya türleri
	var doc := CadDocument.new()
	doc.part_name = "Şablon"
	var dp := TMP.path_join("resim.ddrw")
	check(doc.write_copy(dp) == OK and doc.file_path == "", "yerel kopya yazıldı, belge durumu değişmedi")
	var doc2 := CadDocument.new()
	check(doc2.load_from(dp) == OK and doc2.doc_kind == "drawing", "teknik resim dosyası (.ddrw) türüyle açıldı")
	doc.write_copy(TMP.path_join("sablon.dcadt"))
	check(doc2.load_from(TMP.path_join("sablon.dcadt")) == OK and doc2.doc_kind == "part_template", "parça şablonu (.dcadt)")


static func _xml_ok(txt: String) -> bool:
	var x := XMLParser.new()
	if x.open_buffer(txt.to_utf8_buffer()) != OK:
		return false
	var depth := 0
	var seen := false
	while true:
		var e := x.read()
		if e == ERR_FILE_EOF:
			break
		if e != OK:
			return false
		if x.get_node_type() == XMLParser.NODE_ELEMENT and not x.is_empty():
			depth += 1
			seen = true
		elif x.get_node_type() == XMLParser.NODE_ELEMENT_END:
			depth -= 1
	return seen and depth == 0


static func _scene_aabb(n: Node) -> AABB:
	var bb := AABB()
	if n == null:
		return bb
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var b := (c as MeshInstance3D).mesh.get_aabb()
			bb = b if first else bb.merge(b)
			first = false
		stack.append_array(c.get_children())
	return bb
