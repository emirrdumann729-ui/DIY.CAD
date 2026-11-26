class_name SpecialUI
extends Node
## Faz 8 arayüzü: Sac Metal ve Kaynaklar araç çubukları, özellik panelleri (taban flanş, kenar flanş,
## yapısal üye), açınım, kesim listesi ve konfigürasyonlar paneli. Ana uygulama (`app`) yönlendirir.

const TYPES := ["sm_base", "sm_edge", "weld", "srf_extrude", "srf_revolve", "srf_loft", "srf_planar", "srf_offset", "srf_knit", "srf_thicken", "srf_trim"]
const AUX := ["cutlist", "configs", "fea", "draft_an", "cam", "render"]
const PREFIX := {"sm_base": "Taban-Flanş", "sm_edge": "Kenar-Flanş", "weld": "Yapısal Üye"}

var app: Node
var toolbar_sm: HFlowContainer
var toolbar_weld: HFlowContainer
var toolbar_srf: HFlowContainer
var toolbar_an: HFlowContainer
var result_mi: MeshInstance3D
var lines_mi: MeshInstance3D             # derinlik testli analiz çizgileri (ayırma çizgisi)
var fea_st := {"fix": [], "loads": [], "pick": "fix", "elements": 6000, "E": 205.0, "nu": 0.29, "yield": 350.0, "show": "vm", "scale": 0.0, "mag": 1000.0, "dir": "normal"}
var fea_res := {}
var fea_busy := false
var draft_st := {"dir": 2, "min": 1.0}
var draft_res := {}
var cam_st := Cam.defaults()
var cam_res := {}
var render_st := {"env": "default", "shadows": true, "ground": true, "ssao": true, "ssr": false, "glow": false, "finish": "auto", "exposure": 1.0, "decal_size": 30.0}
var _render_orig := {}
var _render_nodes := {}
var _decal_tex: Texture2D = null
var _decals: Array = []
const PULL := [["X+", Vector3.RIGHT], ["X−", Vector3.LEFT], ["Y+", Vector3.UP], ["Y−", Vector3.DOWN], ["Z+", Vector3.BACK], ["Z−", Vector3.FORWARD]]
var cfg_name := "Konfigürasyon2"


static func prefix(t: String) -> String:
	if Surfaces.LABELS.has(t):
		return str(Surfaces.LABELS[t]).replace(" ", "-")
	return str(PREFIX.get(t, t))


func _doc() -> CadDocument:
	return app.doc


func build_toolbars(cm: Control) -> void:
	toolbar_sm = HFlowContainer.new()
	toolbar_sm.set_meta("group", "Sac Metal")
	toolbar_sm.visible = false
	cm.add_child(toolbar_sm)
	for it in [["Taban\nFlanş", "sm_base", "Kapalı profilden sac plaka veya açık profilden bükümlü sac", "sm_base"],
			["Kenar\nFlanş", "sm_edge", "Taban flanşın kenarına bükülmüş flanş", "sm_edge"],
			["Kıvırma", "sm_hem", "Kenarı 180° geri kıvır (açık kıvırma, boşluk = 2R)", "sm_hem"], [],
			["Açınım", "sm_flat", "Açınımı göster / bük (düz sac)", "sm_flat"],
			["Açınım\nDXF", "sm_dxf", "Açınımı büküm çizgileriyle DXF olarak kaydet (lazer / abkant)", "sm_dxf"]]:
		if it.is_empty():
			toolbar_sm.add_child(VSeparator.new())
			continue
		app._tb(toolbar_sm, it[0], it[1], it[2], cmd.bind(it[3]), false, 64)
	toolbar_weld = HFlowContainer.new()
	toolbar_weld.set_meta("group", "Kaynaklar")
	toolbar_weld.visible = false
	cm.add_child(toolbar_weld)
	for it2 in [["Yapısal\nÜye", "weld", "Taslak / 3B taslak çizgileri boyunca standart profil", "weld"],
			["Kesim\nListesi", "weld_cutlist", "Profil, boy, açı ve adetlere göre kesim listesi (CSV)", "weld_cutlist"]]:
		app._tb(toolbar_weld, it2[0], it2[1], it2[2], cmd.bind(it2[3]), false, 64)
	toolbar_srf = HFlowContainer.new()
	toolbar_srf.set_meta("group", "Yüzeyler")
	toolbar_srf.visible = false
	cm.add_child(toolbar_srf)
	for it3 in [["Ekstrüde\nYüzey", "srf_extrude", "Taslak eğrilerini yüzey olarak uzat", "srf_extrude"],
			["Döndürülmüş\nYüzey", "srf_revolve", "Taslak eğrilerini merkez çizgisi etrafında döndür", "srf_revolve"],
			["Loft\nYüzey", "srf_loft", "İki veya daha çok taslak arasında yüzey", "srf_loft"],
			["Düzlemsel\nYüzey", "srf_planar", "Kapalı konturdan düz yüzey", "srf_planar"],
			["Ofset\nYüzey", "srf_offset", "Yüzeylerin paralel kopyası", "srf_offset"], [],
			["Yüzey\nDikme", "srf_knit", "Yüzeyleri birleştir; kapalıysa katı oluştur", "srf_knit"],
			["Kalınlaştır", "srf_thicken", "Yüzeyi kalınlaştırarak katı oluştur", "srf_thicken"],
			["Yüzey\nKırp", "srf_trim", "Yüzeyleri bir ana düzlemle kırp", "srf_trim"]]:
		if it3.is_empty():
			toolbar_srf.add_child(VSeparator.new())
			continue
		app._tb(toolbar_srf, it3[0], it3[1], it3[2], cmd.bind(it3[3]), false, 70)
	toolbar_an = HFlowContainer.new()
	toolbar_an.set_meta("group", "Analiz")
	toolbar_an.visible = false
	cm.add_child(toolbar_an)
	for it4 in [["Statik\nAnaliz", "fea", "Doğrusal statik sonlu eleman analizi: von Mises gerilme, yer değiştirme", "fea"],
			["Eğim\nAnalizi", "draft_an", "Kalıp çekme yönüne göre eğim açıları ve ayırma çizgisi", "draft_an"],
			["CAM\nG-kod", "cam", "Taslaktan 2.5 eksen kontur / cep frezeleme G-kodu", "cam"], [],
			["Görsel-\nleştirme", "render", "PBR malzeme, ortam, gölge, çıkartma ve yüksek çözünürlüklü render", "render"]]:
		if it4.is_empty():
			toolbar_an.add_child(VSeparator.new())
			continue
		app._tb(toolbar_an, it4[0], it4[1], it4[2], cmd.bind(it4[3]), false, 70)


func cmd(c: String) -> void:
	match c:
		"sm_base", "sm_edge", "weld", "srf_extrude", "srf_revolve", "srf_loft", "srf_planar", "srf_offset", "srf_knit", "srf_thicken", "srf_trim":
			create(c)
		"sm_hem":
			create("sm_edge")
			if app.editing != null and app.editing.type == "sm_edge":
				var bh := SheetMetal.base_of(_doc())
				var T := float(bh.params.get("T", 2.0))
				app.editing.params.merge({"A": 180.0, "R": maxf(0.1, T * 0.5), "L": 8.0}, true)
				app.editing.name = "Kıvırma"
				app._preview()
				show_feature_panel(app.editing)
		"fea", "draft_an", "cam", "render":
			if c != "render" and app.viewport.model.is_empty():
				app._set_status("Önce bir katı model oluşturun.")
				return
			if c == "fea":
				var mm := Fea.mech_of(_doc().material)
				fea_st["E"] = mm[0]
				fea_st["nu"] = mm[1]
				fea_st["yield"] = mm[2]
			_enter_aux(c)
			if c == "draft_an":
				_draft_run()
			elif c == "cam":
				_cam_run()
			elif c == "render":
				apply_render()
		"sm_flat":
			var base := SheetMetal.base_of(_doc())
			if base == null:
				app._set_status("Önce taban flanş oluşturun.")
				return
			_doc().checkpoint()
			base.params["flat"] = not bool(base.params.get("flat", false))
			app._fit_after_build = true
			_doc().commit()
			app._set_status("Açınım gösteriliyor (düz sac)." if base.params["flat"] else "Bükülmüş hali gösteriliyor.")
		"sm_dxf":
			if SheetMetal.base_of(_doc()) == null:
				app._set_status("Önce taban flanş oluşturun.")
				return
			app._file_dialog(true, ["*.dxf ; DXF"], "Açınımı DXF olarak kaydet", "sm_dxf", _doc().part_name + "_acinim.dxf")
		"weld_cutlist":
			_enter_aux("cutlist")
		"configs":
			_enter_aux("configs")


func _enter_aux(m: String) -> void:
	app._exit_sketch3d()
	if app.mode == "sketch":
		app._exit_sketch()
	if app.mode == "feature":
		app._cancel_feature()
	app._leave_aux_mode()
	app.mode = m
	app._refresh_panel()


func create(type: String) -> void:
	if not app.viewport.kernel.is_brep():
		app._set_status("Sac metal ve kaynaklı konstrüksiyon OpenCASCADE (B-rep) çekirdeği gerektirir: Araçlar → Geometri çekirdeği.")
		return
	app._exit_sketch3d()
	if app.mode == "feature":
		app._cancel_feature()
	app._leave_aux_mode()
	var f := CadFeature.new()
	f.id = 0
	f.type = type
	match type:
		"sm_base":
			var sk: CadFeature = app._resolve_sketch()
			if sk == null:
				app._set_status("Önce bir taslak çizin (kapalı profil: plaka, açık çizgi zinciri: bükümlü sac).")
				return
			if SheetMetal.base_of(_doc()) != null:
				app._set_status("Parçada zaten bir taban flanş var (tek sac gövde).")
				return
			f.params = SheetMetal.DEFAULTS.duplicate()
			f.params["sketch"] = sk.id
		"sm_edge":
			if SheetMetal.base_of(_doc()) == null:
				app._set_status("Önce taban flanş oluşturun.")
				return
			f.params = {"edges": [], "L": 20.0, "A": 90.0, "R": -1.0, "flip": false, "off1": 0.0, "off2": 0.0}
		"weld":
			var src := _weld_source()
			if src == null:
				app._set_status("Önce çizgilerden oluşan bir taslak veya 3B taslak çizin / seçin.")
				return
			f.params = {"sketch": src.id, "ptype": "shs", "psize": "40x40x3", "rot": 0.0, "corner": "miter"}
		_:
			f.params = Surfaces.defaults(type)
			if type in Surfaces.SKETCH_TYPES:
				var sk2: CadFeature = app._resolve_sketch()
				if sk2 == null:
					app._set_status("Önce bir taslak çizin veya seçin.")
					f.params = {}
				else:
					f.params["sketch"] = sk2.id
			elif type == "srf_loft":
				var sks: Array = []
				for g in _doc().features:
					if g.is_sketch() and not g.suppressed:
						sks.append(g.id)
				if sks.size() < 2:
					app._set_status("Loft yüzey için en az iki taslak gerekli.")
					f.params = {}
				else:
					f.params["sketches"] = sks.slice(sks.size() - 2)
	if f.params.is_empty() and Surfaces.TYPES.has(type):
		return
	f.name = f.type_label()
	app.editing = f
	app.editing_is_new = true
	app.mode = "feature"
	app._region_pick = false
	app._preview()
	app._show_feature_panel()
	if type == "sm_edge":
		app._set_status("Taban flanşın üst veya alt kenarlarına tıklayın (birden çok kenar seçilebilir).")


func _weld_source() -> CadFeature:
	var sel: Dictionary = app.selection
	if sel.get("kind", "") == "feature":
		var f := _doc().get_feature(int(sel["id"]))
		if f != null and (f.type == "sketch3d" or f.is_sketch()):
			return f
	for i in range(_doc().features.size() - 1, -1, -1):
		var g: CadFeature = _doc().features[i]
		if (g.type == "sketch3d" or g.is_sketch()) and not g.suppressed:
			return g
	return null


# ---------------------------------------------------------------- özellik panelleri

func show_feature_panel(f: CadFeature) -> void:
	var panel: PropertyPanel = app.panel
	panel.clear()
	panel.title(f.type_label() if app.editing_is_new else f.name, Icons.get_icon(f.type, 22))
	panel.ok_cancel(app._ok_feature, app._cancel_feature)
	if f.error != "":
		panel.info(I18n.t("Hata: ") + f.error, Color(1.0, 0.45, 0.4))
	var prev := func() -> void: app._preview()
	var setp := func(v: Variant, key: String) -> void:
		f.params[key] = v
		app._preview()
	match f.type:
		"sm_base":
			var sketches: Array = _doc().sketches()
			var names: Array = []
			var si := 0
			for i in sketches.size():
				names.append(sketches[i].name)
				if sketches[i].id == f.sketch_ref():
					si = i
			var on_sk := func(i: int) -> void:
				f.params["sketch"] = sketches[i].id
				app._preview()
				show_feature_panel(f)
			panel.option("Taslak", names, si, on_sk)
			panel.section("Sac")
			panel.number("Kalınlık (T)", float(f.params["T"]), setp.bind("T"), "length", 0.01)
			panel.number("Büküm yarıçapı (R)", float(f.params["R"]), setp.bind("R"), "length", 0.01)
			panel.number("K-faktörü", float(f.params["K"]), setp.bind("K"), "plain", 0.0, 1.0)
			panel.check("Kalınlık yönünü çevir", bool(f.params.get("reverse", false)), setp.bind("reverse"))
			var sk_f := _doc().get_feature(f.sketch_ref())
			var closed: bool = sk_f != null and not (sk_f.sketch.extract_profiles()["loops"] as Array).is_empty()
			if not closed:
				panel.section("Açık profil")
				panel.number("Derinlik", float(f.params["depth"]), setp.bind("depth"), "length", 0.01)
				panel.check("Orta düzlem", bool(f.params.get("midplane", false)), setp.bind("midplane"))
				panel.check("Malzeme tarafını çevir", bool(f.params.get("flip", false)), setp.bind("flip"))
				var chain := SheetMetal.open_chain(sk_f.sketch) if sk_f != null else []
				if not chain.is_empty():
					var bp := SheetMetal.bent_profile(chain, float(f.params["T"]), float(f.params["R"]), float(f.params["K"]), -1.0 if bool(f.params.get("flip", false)) else 1.0)
					if not bp.has("error"):
						panel.info(I18n.t("Büküm: %d   Açınım boyu: %s") % [(bp["bends"] as Array).size(), Units.format_length(float(bp["flat_len"]))], Color(0.55, 0.85, 1.0))
			else:
				panel.info("Kapalı profil: düz sac plaka. Kenarlarına Kenar Flanş eklenebilir.", Color(0.6, 0.66, 0.72))
			panel.info("Büküm payı: BA = açı × (R + K·T)", Color(0.55, 0.6, 0.66))
		"sm_edge":
			var base := SheetMetal.base_of(_doc())
			var sh := SheetMetal.sheet(base) if base != null else {"T": 2.0, "R": 2.0, "K": 0.44}
			panel.info(I18n.t("Seçili kenar: %d (taban flanşın üst / alt kenarlarına tıklayın)") % (f.params.get("edges", []) as Array).size(), Color(0.55, 0.85, 1.0))
			var clear := func() -> void:
				f.params["edges"] = []
				app._preview()
				app._update_brep_highlight()
				show_feature_panel(f)
			panel.button("Seçimi temizle", clear, Icons.get_icon("delete", 16))
			panel.section("Flanş")
			panel.number("Flanş boyu (L)", float(f.params["L"]), setp.bind("L"), "length", 0.0)
			panel.number("Açı", float(f.params["A"]), setp.bind("A"), "angle", 1.0, 180.0)
			var use_sheet := float(f.params.get("R", -1.0)) <= 0.0
			var on_rs := func(b: bool) -> void:
				f.params["R"] = -1.0 if b else float(sh["R"])
				app._preview()
				show_feature_panel(f)
			panel.check(I18n.t("Sacın büküm yarıçapını kullan (%s)") % Units.format_length(float(sh["R"])), use_sheet, on_rs)
			if not use_sheet:
				panel.number("Büküm yarıçapı", float(f.params["R"]), setp.bind("R"), "length", 0.01)
			panel.check("Büküm yönünü çevir", bool(f.params.get("flip", false)), setp.bind("flip"))
			panel.number("Başlangıç boşluğu", float(f.params.get("off1", 0.0)), setp.bind("off1"), "length", 0.0)
			panel.number("Bitiş boşluğu", float(f.params.get("off2", 0.0)), setp.bind("off2"), "length", 0.0)
			var R := float(f.params["R"]) if not use_sheet else float(sh["R"])
			panel.info(I18n.t("Büküm payı: %s   Açınım şeridi: %s") % [Units.format_length(SheetMetal.bend_allowance(float(f.params["A"]), R, float(sh["K"]), float(sh["T"]))),
				Units.format_length(SheetMetal.bend_allowance(float(f.params["A"]), R, float(sh["K"]), float(sh["T"])) + float(f.params["L"]))], Color(0.6, 0.66, 0.72))
			var on_show := func(b: bool) -> void:
				app._brep_show_result = b
				app._preview()
			panel.check("Sonucu önizle (seçim kapalı)", app._brep_show_result, on_show)
		"srf_extrude", "srf_revolve", "srf_planar":
			var sketches2: Array = _doc().sketches()
			var names2: Array = []
			var si2 := 0
			for i in sketches2.size():
				names2.append(sketches2[i].name)
				if sketches2[i].id == f.sketch_ref():
					si2 = i
			var on_sk2 := func(i: int) -> void:
				f.params["sketch"] = sketches2[i].id
				app._preview()
			panel.option("Taslak", names2, si2, on_sk2)
			if f.type == "srf_extrude":
				panel.number("Derinlik", float(f.params["depth"]), setp.bind("depth"), "length", 0.001)
				panel.check("Yönü çevir", bool(f.params.get("reverse", false)), setp.bind("reverse"))
				panel.check("Orta düzlem", bool(f.params.get("midplane", false)), setp.bind("midplane"))
			elif f.type == "srf_revolve":
				panel.number("Açı", float(f.params["angle"]), setp.bind("angle"), "angle", 0.1, 360.0)
				panel.info("Eksen: taslaktaki merkez çizgisi (yoksa taslağın dikey ekseni).", Color(0.6, 0.66, 0.72))
			else:
				panel.info("Kapalı konturlar düz yüzeye dönüşür (delikler korunur).", Color(0.6, 0.66, 0.72))
		"srf_loft":
			var sk3: Array = _doc().sketches()
			var cur_ids: Array = f.params.get("sketches", [])
			for sk in sk3:
				var sid: int = sk.id
				var on_chk := func(b: bool) -> void:
					var ids: Array = f.params.get("sketches", []).duplicate()
					if b and not (sid in ids):
						ids.append(sid)
					elif not b:
						ids.erase(sid)
					f.params["sketches"] = ids
					app._preview()
				panel.check(sk.name, sid in cur_ids, on_chk)
			panel.check("Düz geçiş (ruled)", bool(f.params.get("ruled", false)), setp.bind("ruled"))
		"srf_offset":
			panel.number("Ofset mesafesi", float(f.params["d"]), setp.bind("d"), "length")
			panel.info("Modeldeki tüm yüzey gövdelerinin ofseti alınır (negatif: ters yön).", Color(0.6, 0.66, 0.72))
		"srf_knit":
			panel.check("Kapalıysa katı oluştur", bool(f.params.get("solid", true)), setp.bind("solid"))
			panel.number("Dikiş toleransı", float(f.params.get("tol", 0.01)), setp.bind("tol"), "length", 0.0001)
		"srf_thicken":
			panel.number("Kalınlık", float(f.params["t"]), setp.bind("t"), "length", 0.001)
			panel.check("Yönü çevir", bool(f.params.get("flip", false)), setp.bind("flip"))
			panel.check("İki yöne (orta)", bool(f.params.get("mid", false)), setp.bind("mid"))
			panel.check("Katılarla birleştir", bool(f.params.get("merge", true)), setp.bind("merge"))
		"srf_trim":
			var pls := ["front", "top", "right"]
			var on_pl := func(i: int) -> void:
				f.params["plane"] = pls[i]
				app._preview()
			panel.option("Kırpma düzlemi", ["Ön Düzlem", "Üst Düzlem", "Sağ Düzlem"], maxi(pls.find(str(f.params["plane"])), 0), on_pl)
			panel.number("Düzlem ofseti", float(f.params.get("off", 0.0)), setp.bind("off"), "length")
			panel.check("Korunan tarafı çevir", bool(f.params.get("flip", false)), setp.bind("flip"))
		"weld":
			var srcs: Array = []
			var sn: Array = []
			var cur := 0
			for g in _doc().features:
				if (g.is_sketch() or g.type == "sketch3d") and not g.suppressed:
					if g.id == int(f.params.get("sketch", 0)):
						cur = srcs.size()
					srcs.append(g)
					sn.append(g.name)
			var on_src := func(i: int) -> void:
				f.params["sketch"] = srcs[i].id
				app._preview()
				show_feature_panel(f)
			panel.option("Çizgiler (taslak / 3B taslak)", sn, cur, on_src)
			panel.section("Profil")
			var types: Array = Weldment.TYPES.keys()
			var tn: Array = []
			for t in types:
				tn.append(Weldment.TYPES[t])
			var on_t := func(i: int) -> void:
				f.params["ptype"] = types[i]
				f.params["psize"] = Weldment.SIZES[types[i]][mini(2, (Weldment.SIZES[types[i]] as Array).size() - 1)]
				app._preview()
				show_feature_panel(f)
			panel.option("Tür", tn, maxi(types.find(str(f.params["ptype"])), 0), on_t)
			var sizes: Array = Weldment.SIZES.get(str(f.params["ptype"]), [])
			var on_s := func(i: int) -> void:
				f.params["psize"] = sizes[i]
				app._preview()
				show_feature_panel(f)
			panel.option("Ölçü", sizes, maxi(sizes.find(str(f.params["psize"])), 0), on_s)
			panel.number("Profil dönüşü", float(f.params.get("rot", 0.0)), setp.bind("rot"), "angle")
			var cs := ["miter", "butt"]
			var on_c := func(i: int) -> void:
				f.params["corner"] = cs[i]
				app._preview()
			panel.option("Köşe birleşimi", ["Gönye (45°)", "Alın"], maxi(cs.find(str(f.params.get("corner", "miter"))), 0), on_c)
			var r := Weldment.build(_doc(), f)
			if not r.has("error"):
				panel.info(I18n.t("Üye: %d   Toplam boy: %s") % [(r["members"] as Array).size(), Units.format_length(float(r["total_length"]))], Color(0.55, 0.85, 1.0))


# ---------------------------------------------------------------- yardımcı paneller

func show_aux(m: String) -> void:
	var panel: PropertyPanel = app.panel
	panel.clear()
	match m:
		"fea":
			_panel_fea(panel)
		"draft_an":
			_panel_draft(panel)
		"cam":
			_panel_cam(panel)
		"render":
			_panel_render(panel)
		"cutlist":
			panel.title("Kesim Listesi", Icons.get_icon("weld_cutlist", 22))
			var rows := Weldment.doc_cutlist(_doc())
			if rows.is_empty():
				panel.info("Parçada yapısal üye yok.")
			var total := 0.0
			var i := 1
			for r in rows:
				panel.info(I18n.t("%d.  %s   × %d\n     Boy %s   Açılar %s° / %s°   %s") % [i, r["profile"], int(r["qty"]), Units.format_length(float(r["length"])),
					str(r["angles"][0]), str(r["angles"][1]), Units.format_mass(float(r["mass"]) * int(r["qty"]))], Color(0.8, 0.83, 0.88))
				total += float(r["length"]) * int(r["qty"])
				i += 1
			if not rows.is_empty():
				panel.info(I18n.t("Toplam profil boyu: %s") % Units.format_length(total), Color(0.55, 0.85, 1.0))
				var save := func() -> void: app._file_dialog(true, ["*.csv ; CSV"], "Kesim listesini kaydet", "weld_csv", _doc().part_name + "_kesim.csv")
				panel.button("CSV olarak kaydet", save, Icons.get_icon("export", 16))
		"configs":
			panel.title("Konfigürasyonlar", Icons.get_icon("configs", 22))
			Configs.ensure_default(_doc())
			panel.info(I18n.t("Etkin: ") + _doc().active_config, Color(0.55, 0.85, 1.0))
			var act := func(n: String) -> void:
				Configs.activate(_doc(), n)
				_doc().commit()
				app._set_status(I18n.t("Konfigürasyon: ") + n)
			var rm := func(n: String) -> void:
				if Configs.remove(_doc(), n):
					_doc().commit()
				else:
					app._set_status("Etkin konfigürasyon veya tek konfigürasyon silinemez.")
			for c in _doc().configs:
				var nm := str(c["name"])
				if nm == _doc().active_config:
					panel.info("● " + nm + "  (etkin)", Color(0.9, 0.92, 0.95))
				else:
					panel.button(I18n.t("Etkinleştir: ") + nm, act.bind(nm), Icons.get_icon("configs", 14))
					panel.item_row("    sil: " + nm, Icons.get_icon("delete", 14), rm.bind(nm))
			panel.section("Yeni konfigürasyon")
			var on_name := func(t: String) -> void: cfg_name = t
			panel.text_field("Ad", cfg_name, on_name)
			var add := func() -> void:
				if Configs.add(_doc(), cfg_name.strip_edges()):
					_doc().commit()
					app._set_status(I18n.t("Konfigürasyon eklendi: ") + cfg_name + " (boyut ve bastırma değişiklikleri bu konfigürasyona kaydedilir)")
					cfg_name = "Konfigürasyon%d" % (_doc().configs.size() + 1)
				else:
					app._set_status("Ad boş veya zaten var.")
			panel.button("Ekle (etkin değerlerden kopyala)", add, Icons.get_icon("new", 16))
			panel.section("Tasarım tablosu")
			var out := func() -> void: app._file_dialog(true, ["*.csv ; CSV"], "Tasarım tablosunu kaydet", "cfg_csv_out", _doc().part_name + "_tasarim_tablosu.csv")
			var inp := func() -> void: app._file_dialog(false, ["*.csv ; CSV"], "Tasarım tablosunu içe aktar", "cfg_csv_in")
			panel.button("Dışa aktar (CSV)", out, Icons.get_icon("export", 16))
			panel.button("İçe aktar (CSV)", inp, Icons.get_icon("import", 16))
			panel.info("Sütunlar: D1@Taslak1 (boyut), D1@Ekstrüzyon1 (derinlik), $BASTIR@Özellik (1/0). Değerler ekran biriminde.", Color(0.55, 0.6, 0.66))


func on_file(action: String, path: String) -> Error:
	match action:
		"cam_nc":
			if not (path.get_extension().to_lower() in ["nc", "gcode", "ngc", "tap"]):
				path += ".nc"
			var fa := FileAccess.open(path, FileAccess.WRITE)
			if fa == null or not cam_res.has("gcode"):
				app._set_status("G-kod yazılamadı")
				return ERR_CANT_CREATE
			fa.store_string(str(cam_res["gcode"]))
			fa.close()
			app._set_status("G-kod kaydedildi: " + path)
			return OK
		"render_png":
			if path.get_extension().to_lower() != "png":
				path += ".png"
			render_to(path, 2)
			return OK
		"render_hdri":
			var img := Image.load_from_file(path)
			if img == null or img.is_empty():
				app._set_status(I18n.t("HDRI / panorama görüntüsü açılamadı: ") + path)
				return ERR_FILE_UNRECOGNIZED
			render_st["hdri_tex"] = ImageTexture.create_from_image(img)
			render_st["env"] = "hdri"
			apply_render()
			app._refresh_panel()
			return OK
		"decal_img":
			var img2 := Image.load_from_file(path)
			if img2 == null or img2.is_empty():
				app._set_status(I18n.t("Görüntü açılamadı: ") + path)
				return ERR_FILE_UNRECOGNIZED
			_decal_tex = ImageTexture.create_from_image(img2)
			app._set_status("Çıkartmanın yerleşeceği yüze tıklayın.")
			return OK
		"sm_dxf":
			if path.get_extension().to_lower() != "dxf":
				path += ".dxf"
			var fp := SheetMetal.flat_pattern(_doc())
			if fp.has("error"):
				app._set_status(I18n.t("Açınım hesaplanamadı: ") + str(fp["error"]))
				return ERR_INVALID_DATA
			var err := DrawingExport.write_dxf(path, SheetMetal.flat_prims(fp))
			app._set_status((I18n.t("Açınım kaydedildi: %s (%s × %s)") % [path, Units.format_length((fp["size"] as Vector2).x), Units.format_length((fp["size"] as Vector2).y)]) if err == OK else "DXF yazılamadı")
			return err
		"weld_csv":
			if path.get_extension().to_lower() != "csv":
				path += ".csv"
			var err2 := Weldment.write_cutlist_csv(path, Weldment.doc_cutlist(_doc()))
			app._set_status((I18n.t("Kesim listesi kaydedildi: ") + path) if err2 == OK else "CSV yazılamadı")
			return err2
		"cfg_csv_out":
			if path.get_extension().to_lower() != "csv":
				path += ".csv"
			var err3 := Configs.write_csv(_doc(), path)
			app._set_status((I18n.t("Tasarım tablosu kaydedildi: ") + path) if err3 == OK else "CSV yazılamadı")
			return err3
		"cfg_csv_in":
			_doc().checkpoint()
			var r := Configs.read_csv(_doc(), path)
			if r.has("error"):
				_doc().drop_checkpoint()
				app._set_status(I18n.t("Tasarım tablosu okunamadı: ") + str(r["error"]))
				return ERR_INVALID_DATA
			_doc().commit()
			app._set_status(I18n.t("Tasarım tablosu: %d konfigürasyon, %d parametre.") % [r["configs"], r["params"]])
			return OK
	return ERR_INVALID_PARAMETER


# ---------------------------------------------------------------- örnekler (tanıtım / ekran görüntüsü)

## stage 1: model oluştur; stage 2: (sac) taban kurulduktan sonra kenar flanşlarını ekle
func demo(kind: String, stage: int) -> void:
	var doc := _doc()
	if stage == 1:
		doc.load_dict({})
		if kind == "sheet":
			doc.part_name = "OrnekSacKutu"
			doc.material = "Paslanmaz Çelik (AISI 304)"
			var s := doc.new_feature("sketch", "Taslak")
			s.plane = SketchPlane.standard("top")
			s.sketch = Sketch.new()
			doc.add_feature(s)
			var sk := s.sketch
			sk.add_rect([sk.add_point(Vector2(-60, -40)), sk.add_point(Vector2(60, -40)), sk.add_point(Vector2(60, 40)), sk.add_point(Vector2(-60, 40))])
			sk.add_circle(sk.add_point(Vector2(0, 0)), 15.0)
			var b := doc.new_feature("sm_base", "Taban-Flanş")
			b.params = SheetMetal.DEFAULTS.duplicate()
			b.params["sketch"] = s.id
			b.params["T"] = 1.5
			doc.add_feature(b)
		elif kind == "surf":
			# Döndürülmüş yüzey (spline profilli vazo, 270°) + düzlemsel taban yüzeyi
			doc.part_name = "OrnekYuzey"
			doc.material = "PETG"
			var sv := doc.new_feature("sketch", "Profil")
			sv.plane = SketchPlane.standard("front")
			sv.sketch = Sketch.new()
			doc.add_feature(sv)
			var kv := sv.sketch
			var pp: Array = []
			for q2 in [Vector2(22, 0), Vector2(30, 18), Vector2(20, 45), Vector2(16, 62), Vector2(24, 80)]:
				pp.append(kv.add_point(q2))
			kv.add_spline(pp)
			kv.add_line(kv.add_point(Vector2(0, -5)), kv.add_point(Vector2(0, 85)), true)
			var rv := doc.new_feature("srf_revolve", "Döndürülmüş Yüzey")
			rv.params = {"sketch": sv.id, "angle": 270.0}
			doc.add_feature(rv)
			var sb := doc.new_feature("sketch", "Taban")
			sb.plane = SketchPlane.standard("top")
			sb.sketch = Sketch.new()
			doc.add_feature(sb)
			sb.sketch.add_circle(Sketch.ORIGIN, 22.0)
			var pl2 := doc.new_feature("srf_planar", "Düzlemsel Yüzey")
			pl2.params = {"sketch": sb.id}
			doc.add_feature(pl2)
		elif kind == "fea":
			# Delikli konsol plaka: sol uçtan sabit, sağ uca aşağı yük
			doc.part_name = "OrnekKonsol"
			doc.material = "Alüminyum 6061"
			var sf := doc.new_feature("sketch", "Taslak")
			sf.plane = SketchPlane.standard("front")
			sf.sketch = Sketch.new()
			doc.add_feature(sf)
			var kf := sf.sketch
			kf.add_rect([kf.add_point(Vector2(0, 0)), kf.add_point(Vector2(120, 0)), kf.add_point(Vector2(120, 30)), kf.add_point(Vector2(0, 30))])
			kf.add_circle(kf.add_point(Vector2(45, 15)), 8.0)
			var ex := doc.new_feature("extrude", "Ekstrüzyon")
			ex.params = {"sketch": sf.id, "depth": 12.0, "end": "blind", "reverse": false, "cut": false}
			doc.add_feature(ex)
		else:
			doc.part_name = "OrnekCerceve"
			doc.material = "Düz Karbon Çelik (AISI 1020)"
			var s3 := doc.new_feature("sketch3d", "3B Taslak")
			s3.sketch3d = Sketch3D.new()
			doc.add_feature(s3)
			var k := s3.sketch3d
			var P: Array = []
			for q in [Vector3(-300, 0, -200), Vector3(300, 0, -200), Vector3(300, 0, 200), Vector3(-300, 0, 200),
					Vector3(-300, 500, -200), Vector3(300, 500, -200), Vector3(300, 500, 200), Vector3(-300, 500, 200)]:
				P.append(k.add_point(q))
			for e in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
				k.add_line(P[e[0]], P[e[1]])
			var w := doc.new_feature("weld", "Yapısal Üye")
			w.params = {"sketch": s3.id, "ptype": "shs", "psize": "40x40x3", "rot": 0.0, "corner": "miter"}
			doc.add_feature(w)
		doc.dirty = false
		doc.changed.emit()
		return
	if kind == "sheet":
		var base := SheetMetal.base_of(doc)
		var refs: Array = []
		for e2 in app.viewport.model.brep_edges:
			var pe := SheetMetal.parse_edge(e2.get("fn", []))
			if not pe.is_empty() and str(pe["cap"]) == "b" and int(pe["fid"]) == base.id and str(e2.get("type", "")) == "line":
				refs.append({"m": e2["m"], "d": e2["d"], "fn": e2.get("fn", [])})
		var ef := doc.new_feature("sm_edge", "Kenar-Flanş")
		ef.params = {"edges": refs, "L": 25.0, "A": 90.0, "R": -1.0, "flip": false, "off1": 0.0, "off2": 0.0}
		doc.add_feature(ef)
		app._fit_after_build = true
		doc.changed.emit()
	elif kind == "fea":
		app._show_toolbar(8)
		cmd("fea")
		fea_st["fix"] = [_face_ref(Vector3.LEFT)]
		fea_st["loads"] = [{"face": _face_ref(Vector3.RIGHT), "mag": 1500.0, "dir": "-y"}]
		fea_st["deform"] = 1.0
		run_fea()


## Verilen normale sahip ilk B-rep yüzün analiz referansı (örnekler için)
func _face_ref(n: Vector3) -> Dictionary:
	var m: ModelMesh = app.viewport.model
	for ti in m.tri_count():
		if m.normals[ti].dot(n) > 0.99 and m.has_brep():
			var fid := m.tri_face[ti]
			var c := (m.verts[m.tris[ti * 3]] + m.verts[m.tris[ti * 3 + 1]] + m.verts[m.tris[ti * 3 + 2]]) / 3.0
			var info: Dictionary = m.brep_faces[fid]
			return {"p": [c.x, c.y, c.z], "n": [n.x, n.y, n.z], "name": str(info.get("name", "")), "fid": fid}
	return {}


# ---------------------------------------------------------------- sonuç ağı (FEA / eğim analizi)

func _show_result(mesh: ArrayMesh) -> void:
	if result_mi == null:
		result_mi = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.7
		result_mi.material_override = mat
		result_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		app.viewport.world.add_child(result_mi)
	result_mi.mesh = mesh
	result_mi.visible = mesh != null
	app.viewport.model_mi.visible = mesh == null


func clear_results() -> void:
	if result_mi != null:
		result_mi.visible = false
		result_mi.mesh = null
	app.viewport.model_mi.visible = true
	(app.viewport.overlay_mi.mesh as ArrayMesh).clear_surfaces()
	if lines_mi != null:
		(lines_mi.mesh as ArrayMesh).clear_surfaces()


func _overlay_lines(segs: Array, col: Color) -> void:
	var lb := LineBuilder.new()
	for sg in segs:
		lb.line(sg[0], sg[1], col)
	lb.commit(app.viewport.overlay_mi.mesh)


## Yardımcı moddan çıkarken (ana uygulama çağırır)
func on_leave_aux(was: String) -> void:
	if was in ["fea", "draft_an", "cam"]:
		clear_results()
		app.viewport.clear_face_highlight()


## Model yeniden oluşturulunca (ana uygulama çağırır)
func on_built() -> void:
	match app.mode:
		"fea":
			fea_res = {}
			clear_results()
			_highlight_fea()
			app._refresh_panel()
		"draft_an":
			_draft_run()
		"cam":
			_cam_run()


func aux_click(pos: Vector2) -> void:
	var r: Array = app.viewport.ray(pos)
	var m: ModelMesh = app.viewport.model
	var hit := m.raycast(r[0], r[1])
	if hit.is_empty():
		return
	var tri := int(hit["tri"])
	match app.mode:
		"fea":
			if not m.has_brep():
				return
			var fid := m.tri_face[tri]
			var info: Dictionary = m.brep_faces[fid]
			var ref := {"p": [hit["point"].x, hit["point"].y, hit["point"].z], "n": info.get("n", [m.normals[tri].x, m.normals[tri].y, m.normals[tri].z]),
				"name": str(info.get("name", "")), "fid": fid}
			var lst: Array = fea_st["fix"] if fea_st["pick"] == "fix" else fea_st["loads"]
			for i in lst.size():
				var fr: Dictionary = lst[i] if fea_st["pick"] == "fix" else lst[i]["face"]
				if int(fr.get("fid", -1)) == fid:
					lst.remove_at(i)
					_highlight_fea()
					app._refresh_panel()
					return
			if fea_st["pick"] == "fix":
				lst.append(ref)
			else:
				lst.append({"face": ref, "mag": float(fea_st["mag"]), "dir": str(fea_st["dir"])})
			fea_res = {}
			clear_results()
			_highlight_fea()
			app._refresh_panel()
		"render":
			if _decal_tex == null:
				return
			var n := m.normals[tri]
			var d := Decal.new()
			d.texture_albedo = _decal_tex
			var sz := float(render_st["decal_size"])
			var asp := float(_decal_tex.get_height()) / maxf(1.0, float(_decal_tex.get_width()))
			d.size = Vector3(sz, sz * 0.5, sz * asp)
			var y := n.normalized()
			var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
			var z := x.cross(y)
			d.transform = Transform3D(Basis(x, y, z), hit["point"])
			app.viewport.world.add_child(d)
			_decals.append(d)
			_decal_tex = null
			app._set_status("Çıkartma yerleştirildi.")
			app._refresh_panel()


func _highlight_fea() -> void:
	var m: ModelMesh = app.viewport.model
	var pts := PackedVector3Array()
	var fids := {}
	for fr in fea_st["fix"]:
		fids[int(fr.get("fid", -1))] = true
	for ld in fea_st["loads"]:
		fids[int(ld["face"].get("fid", -1))] = true
	if m.has_brep():
		for ti in m.tri_count():
			if fids.has(m.tri_face[ti]):
				for k in 3:
					pts.append(m.verts[m.tris[ti * 3 + k]])
	app.viewport.set_face_highlight(pts)


# ---------------------------------------------------------------- FEA paneli

func run_fea() -> void:
	if not app.viewport.kernel.is_brep():
		app._set_status("Statik analiz OpenCASCADE çekirdeği gerektirir.")
		return
	if (fea_st["fix"] as Array).is_empty() or (fea_st["loads"] as Array).is_empty():
		app._set_status("En az bir sabit yüz ve bir yük yüzü seçin.")
		return
	if not app.viewport.kernel.asm_done.is_connected(_on_fea_done):
		app.viewport.kernel.asm_done.connect(_on_fea_done)
	fea_busy = true
	app.viewport.kernel.request_asm("fea", Fea.request(fea_st))
	app._set_status("Analiz çözülüyor...")
	app._refresh_panel()


func _on_fea_done(res: Dictionary) -> void:
	if str(res.get("cmd", "")) != "fea":
		return
	fea_busy = false
	if not bool(res.get("ok", false)):
		fea_res = {}
		app._set_status(I18n.t("Analiz başarısız: ") + str(res.get("error", "")))
		app._refresh_panel()
		return
	fea_res = Fea.parse(res)
	var size: float = app.viewport.model.aabb.size.length()
	if float(fea_st["scale"]) <= 0.0 and float(fea_res["u_max"]) > 1e-12:
		fea_st["scale"] = snappedf(size * 0.08 / float(fea_res["u_max"]), 0.1)
	update_fea_view()
	app._set_status(I18n.t("Analiz tamam: en büyük von Mises %.2f MPa, en büyük yer değiştirme %s (%d eleman, %.1f sn)") % [float(fea_res["vm_max"]),
		Units.format_length(float(fea_res["u_max"])), int(fea_res["elements"]), float(res.get("ms", 0.0)) / 1000.0])
	app._refresh_panel()


func update_fea_view() -> void:
	if fea_res.is_empty() or app.mode != "fea":
		return
	var cm := Fea.colored_mesh(app.viewport.model, fea_res, str(fea_st["show"]), float(fea_st.get("deform", 0.0)) * float(fea_st["scale"]))
	fea_res["shown_min"] = cm["min"]
	fea_res["shown_max"] = cm["max"]
	_show_result(cm["mesh"])
	app.viewport.clear_face_highlight()


func _legend(panel: PropertyPanel, lo: String, hi: String) -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	g.colors = PackedColorArray([Fea.ramp(0.0), Fea.ramp(0.25), Fea.ramp(0.5), Fea.ramp(0.75), Fea.ramp(1.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 200
	gt.height = 14
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.custom_minimum_size = Vector2(150, 14)
	panel.add_control(lo, tr)
	panel.info(I18n.t("en büyük: ") + hi, Color(0.8, 0.83, 0.88))


func _panel_fea(panel: PropertyPanel) -> void:
	panel.title("Statik Analiz", Icons.get_icon("fea", 22))
	panel.section(I18n.t("Malzeme: ") + (_doc().material if _doc().material != "" else "<belirtilmemiş: çelik>"))
	var setv := func(v: float, k: String) -> void:
		fea_st[k] = v
		fea_res = {}
		clear_results()
	panel.number("E (GPa)", float(fea_st["E"]), setv.bind("E"), "plain", 0.001)
	panel.number("Poisson oranı", float(fea_st["nu"]), setv.bind("nu"), "plain", 0.0, 0.49)
	panel.number("Akma dayanımı (MPa)", float(fea_st["yield"]), setv.bind("yield"), "plain", 0.001)
	var dens := [2000, 6000, 15000]
	var on_d := func(i: int) -> void:
		fea_st["elements"] = dens[i]
		fea_res = {}
	panel.option("Ağ yoğunluğu", ["Kaba (~2 bin)", "Orta (~6 bin)", "İnce (~15 bin)"], maxi(dens.find(int(fea_st["elements"])), 1), on_d)
	panel.section("Sınır koşulları")
	var picks := ["fix", "load"]
	var on_p := func(i: int) -> void:
		fea_st["pick"] = picks[i]
		app._set_status(I18n.t("Modelde %s yüze tıklayın (tekrar tıklamak kaldırır).") % ("sabitlenecek" if i == 0 else "yük uygulanacak"))
	panel.option("Tıklama", ["Sabit yüz seç", "Yük yüzü seç"], picks.find(str(fea_st["pick"])), on_p)
	var rm_fix := func(i: int) -> void:
		(fea_st["fix"] as Array).remove_at(i)
		fea_res = {}
		clear_results()
		_highlight_fea()
		app._refresh_panel()
	for i in (fea_st["fix"] as Array).size():
		panel.item_row("Sabit yüz %d" % (i + 1), Icons.get_icon("asm_fix", 14), rm_fix.bind(i))
	var rm_ld := func(i: int) -> void:
		(fea_st["loads"] as Array).remove_at(i)
		fea_res = {}
		clear_results()
		_highlight_fea()
		app._refresh_panel()
	var dkeys: Array = Fea.DIRS.keys()
	var dnames: Array = []
	for k in dkeys:
		dnames.append(Fea.DIRS[k])
	for i in (fea_st["loads"] as Array).size():
		var ld: Dictionary = fea_st["loads"][i]
		panel.item_row("Yük %d: %.0f N" % [i + 1, float(ld["mag"])], Icons.get_icon("arrow_down", 14), rm_ld.bind(i))
		var on_mag := func(v: float) -> void:
			ld["mag"] = v
			fea_res = {}
		panel.number("    Kuvvet (N)", float(ld["mag"]), on_mag, "plain")
		var on_dir := func(j: int) -> void:
			ld["dir"] = dkeys[j]
			fea_res = {}
		panel.option("    Yön", dnames, maxi(dkeys.find(str(ld["dir"])), 0), on_dir)
	panel.button("Çalıştır" if not fea_busy else "Çözülüyor...", run_fea, Icons.get_icon("fea", 16))
	if fea_res.is_empty():
		panel.info("Sabit yüz(ler) ve yük yüz(ler)i seçip Çalıştır'a basın. Ağ: vokselli altı yüzlü elemanlar.", Color(0.55, 0.6, 0.66))
		return
	panel.section("Sonuçlar")
	var vm := float(fea_res["vm_max"])
	var fs := float(fea_st["yield"]) / maxf(vm, 1e-9)
	panel.info(I18n.t("En büyük von Mises: %.2f MPa\nEn büyük yer değiştirme: %s\nGüvenlik katsayısı (akma): %.2f\nEleman: %d   Düğüm: %d") % [vm, Units.format_length(float(fea_res["u_max"])), fs,
		int(fea_res["elements"]), int(fea_res["nodes"])], Color(0.55, 0.85, 1.0) if fs >= 1.0 else Color(1.0, 0.5, 0.4))
	if fs < 1.0:
		panel.info("Uyarı: gerilme akma dayanımını aşıyor!", Color(1.0, 0.45, 0.4))
	var shows := ["vm", "disp"]
	var on_sh := func(i: int) -> void:
		fea_st["show"] = shows[i]
		update_fea_view()
		app._refresh_panel()
	panel.option("Gösterim", ["von Mises gerilme", "Yer değiştirme"], shows.find(str(fea_st["show"])), on_sh)
	var on_def := func(b: bool) -> void:
		fea_st["deform"] = 1.0 if b else 0.0
		update_fea_view()
	panel.check(I18n.t("Şekil değiştirmiş hal (×%s)") % str(fea_st["scale"]), float(fea_st.get("deform", 0.0)) > 0.0, on_def)
	var on_sc := func(v: float) -> void:
		fea_st["scale"] = v
		update_fea_view()
	panel.number("Büyütme", float(fea_st["scale"]), on_sc, "plain", 0.0)
	var unit := " MPa" if fea_st["show"] == "vm" else " mm"
	_legend(panel, "0" + unit, ("%.3f" % float(fea_res.get("shown_max", 0.0))) + unit)
	var clr := func() -> void:
		fea_res = {}
		clear_results()
		_highlight_fea()
		app._refresh_panel()
	panel.button("Sonuçları temizle", clr, Icons.get_icon("delete", 16))


# ---------------------------------------------------------------- eğim analizi

func _draft_run() -> void:
	if app.viewport.model.is_empty():
		return
	var d: Vector3 = PULL[int(draft_st["dir"])][1]
	draft_res = Fea.draft_analysis(app.viewport.model, d, float(draft_st["min"]))
	_show_result(Fea.tri_color_mesh(app.viewport.model, draft_res["colors"]))
	(app.viewport.overlay_mi.mesh as ArrayMesh).clear_surfaces()
	if lines_mi == null:
		lines_mi = app.viewport._mi(app.viewport.edges_mi.material_override)
	var lb := LineBuilder.new()
	for sg in draft_res["lines"]:
		lb.line(sg[0], sg[1], Color(0.1, 0.2, 1.0))
	lb.commit(lines_mi.mesh)


func _panel_draft(panel: PropertyPanel) -> void:
	panel.title("Eğim Analizi", Icons.get_icon("draft_an", 22))
	var names: Array = []
	for p in PULL:
		names.append(p[0])
	var on_d := func(i: int) -> void:
		draft_st["dir"] = i
		_draft_run()
		app._refresh_panel()
	panel.option("Çekme yönü", names, int(draft_st["dir"]), on_d)
	var on_m := func(v: float) -> void:
		draft_st["min"] = v
		_draft_run()
		app._refresh_panel()
	panel.number("En az eğim açısı", float(draft_st["min"]), on_m, "angle", 0.0, 45.0)
	if draft_res.is_empty():
		return
	panel.info(I18n.t("■ Pozitif eğim (çekme yönüne bakar): %%%.1f") % (float(draft_res["pos"]) * 100.0), Color(0.3, 0.85, 0.4))
	panel.info(I18n.t("■ Negatif eğim (ters yöne bakar): %%%.1f") % (float(draft_res["neg"]) * 100.0), Color(0.95, 0.35, 0.3))
	panel.info(I18n.t("■ Eğim gerekli (dik duvar): %%%.1f") % (float(draft_res["need"]) * 100.0), Color(0.98, 0.85, 0.2))
	panel.info(I18n.t("Mavi çizgi: olası ayırma çizgisi (%d kenar).") % (draft_res["lines"] as Array).size(), Color(0.5, 0.65, 1.0))


# ---------------------------------------------------------------- CAM

func _cam_sketch() -> CadFeature:
	var sid := int(cam_st.get("sketch", -1))
	var f := _doc().get_feature(sid) if sid >= 0 else null
	if f != null and f.is_sketch():
		return f
	var sel: Dictionary = app.selection
	if sel.get("kind", "") == "feature":
		var g := _doc().get_feature(int(sel["id"]))
		if g != null and g.is_sketch():
			cam_st["sketch"] = g.id
			return g
	for g2 in _doc().sketches():
		if not (g2.sketch.extract_profiles()["loops"] as Array).is_empty():
			cam_st["sketch"] = g2.id
			return g2
	return null


func _cam_run() -> void:
	var sk := _cam_sketch()
	(app.viewport.overlay_mi.mesh as ArrayMesh).clear_surfaces()
	cam_res = {}
	if sk == null:
		return
	var tp := Cam.toolpaths(sk.sketch, cam_st)
	if tp.has("error"):
		cam_res = {"error": tp["error"]}
		return
	cam_res = Cam.gcode(tp["paths"], cam_st, _doc().part_name)
	cam_res["paths"] = tp["paths"]
	var segs: Array = []
	var pl := sk.plane
	var nrm := pl.normal()
	var z0 := cam_z0(sk)
	cam_res["z0"] = z0
	# Her paso derinliğindeki yol (çok paso varsa yalnız son)
	var levels: Array = []
	var zz := 0.0
	var depth := absf(float(cam_st["depth"]))
	var stepd := maxf(0.01, absf(float(cam_st["step"])))
	while zz > -depth + 1e-9:
		zz = maxf(zz - stepd, -depth)
		levels.append(zz)
	if levels.size() > 40:
		levels = [levels[levels.size() - 1]]
	for z in levels:
		var h: float = z0 + float(z)
		for path in tp["paths"]:
			var pts: PackedVector2Array = path
			for k in pts.size():
				var a: Vector3 = pl.to_world(pts[k]) + nrm * h
				var b: Vector3 = pl.to_world(pts[(k + 1) % pts.size()]) + nrm * h
				segs.append([a, b])
	_overlay_lines(segs, Color(0.95, 0.45, 0.05))


## CAM Z0 yüksekliği (taslak normali boyunca, taslak düzleminden): "top" = parçanın en üst noktası
func cam_z0(sk: CadFeature) -> float:
	if str(cam_st.get("z0", "top")) != "top" or app.viewport.model.is_empty():
		return 0.0
	var nrm := sk.plane.normal()
	var hi := -INF
	for v in app.viewport.model.verts:
		hi = maxf(hi, (v - sk.plane.origin).dot(nrm))
	return maxf(hi, 0.0)


func _panel_cam(panel: PropertyPanel) -> void:
	panel.title("CAM — G-kod", Icons.get_icon("cam", 22))
	var sks: Array = []
	var names: Array = []
	var cur := 0
	var sk := _cam_sketch()
	for g in _doc().sketches():
		if sk != null and g.id == sk.id:
			cur = sks.size()
		sks.append(g)
		names.append(g.name)
	if sks.is_empty():
		panel.info("Kapalı konturlu bir taslak çizin.")
		return
	var rerun := func() -> void:
		_cam_run()
		app._refresh_panel()
	var on_sk := func(i: int) -> void:
		cam_st["sketch"] = sks[i].id
		rerun.call()
	panel.option("Taslak", names, cur, on_sk)
	var ops: Array = Cam.OPS.keys()
	var on_op := func(i: int) -> void:
		cam_st["op"] = ops[i]
		rerun.call()
	var opn: Array = []
	for o in ops:
		opn.append(Cam.OPS[o])
	panel.option("İşlem", opn, maxi(ops.find(str(cam_st["op"])), 0), on_op)
	var z0s := ["top", "sketch"]
	var on_z := func(i: int) -> void:
		cam_st["z0"] = z0s[i]
		rerun.call()
	panel.option("Z0 referansı", ["Parça üstü (ham malzeme)", "Taslak düzlemi"], maxi(z0s.find(str(cam_st.get("z0", "top"))), 0), on_z)
	var setc := func(v: float, k: String) -> void:
		cam_st[k] = v
		rerun.call()
	panel.number("Takım çapı", float(cam_st["tool"]), setc.bind("tool"), "length", 0.01)
	panel.number("Derinlik", float(cam_st["depth"]), setc.bind("depth"), "length", 0.01)
	panel.number("Paso derinliği", float(cam_st["step"]), setc.bind("step"), "length", 0.01)
	if cam_st["op"] == "pocket":
		panel.number("Yan adım (% çap)", float(cam_st["stepover"]), setc.bind("stepover"), "plain", 5.0, 95.0)
	panel.number("İlerleme (mm/dk)", float(cam_st["feed"]), setc.bind("feed"), "plain", 1.0)
	panel.number("Dalma (mm/dk)", float(cam_st["plunge"]), setc.bind("plunge"), "plain", 1.0)
	panel.number("Devir (dev/dk)", float(cam_st["rpm"]), setc.bind("rpm"), "plain", 1.0)
	panel.number("Güvenli Z", float(cam_st["safe"]), setc.bind("safe"), "length", 0.1)
	if cam_res.has("error"):
		panel.info(str(cam_res["error"]), Color(1.0, 0.45, 0.4))
		return
	if cam_res.is_empty():
		return
	panel.info(I18n.t("Yol: %d   Paso: %d\nKesme boyu: %s\nTahmini süre: %.1f dk") % [(cam_res["paths"] as Array).size(), int(cam_res["passes"]),
		Units.format_length(float(cam_res["length"])), float(cam_res["time_min"])], Color(0.55, 0.85, 1.0))
	var save := func() -> void: app._file_dialog(true, ["*.nc ; G-kod", "*.gcode ; G-kod"], "G-kodu kaydet", "cam_nc", _doc().part_name + ".nc")
	panel.button("G-kodu kaydet", save, Icons.get_icon("export", 16))
	panel.info(I18n.t("Turuncu: takım merkezi yolları (her paso derinliğinde). Z0 = %s; X/Y taslak eksenleri.") % ("parçanın üstü, taslaktan %s yukarıda" % Units.format_length(float(cam_res.get("z0", 0.0))) if str(cam_st.get("z0", "top")) == "top" else "taslak düzlemi"), Color(0.55, 0.6, 0.66))


# ---------------------------------------------------------------- görselleştirme

func _find(node: Node, cls: String) -> Node:
	for c in node.get_children():
		if c.is_class(cls):
			return c
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func apply_render() -> void:
	var vp: CadViewport = app.viewport
	var we := _find(vp.world, "WorldEnvironment") as WorldEnvironment
	if we == null:
		return
	var env := we.environment
	if _render_orig.is_empty():
		_render_orig = {"bg": env.background_mode, "amb_src": env.ambient_light_source, "amb_en": env.ambient_light_energy,
			"transp": vp.subviewport.transparent_bg, "rough": vp.model_mat.roughness, "metal": vp.model_mat.metallic,
			"tone": env.tonemap_mode, "exp": env.tonemap_exposure}
	var preset := str(render_st["env"])
	if not _render_nodes.has("sun"):
		var sun := DirectionalLight3D.new()
		# Sol-üst-önden anahtar ışık (izometrik görünümde gölge sağ-arkaya, görünür tarafa düşer)
		sun.transform.basis = Basis.looking_at(-Vector3(-0.6, 1.4, 1.0).normalized(), Vector3.UP)
		vp.world.add_child(sun)
		_render_nodes["sun"] = sun
		var gm := MeshInstance3D.new()
		gm.mesh = PlaneMesh.new()
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(0.85, 0.86, 0.88)
		gmat.shadow_to_opacity = true
		gm.material_override = gmat
		vp.world.add_child(gm)
		_render_nodes["ground"] = gm
	var sun2: DirectionalLight3D = _render_nodes["sun"]
	var ground: MeshInstance3D = _render_nodes["ground"]
	if preset == "default":
		env.background_mode = _render_orig["bg"]
		env.ambient_light_source = _render_orig["amb_src"]
		env.ambient_light_energy = _render_orig["amb_en"]
		env.tonemap_mode = _render_orig["tone"]
		env.tonemap_exposure = _render_orig["exp"]
		env.ssao_enabled = false
		env.ssr_enabled = false
		env.glow_enabled = false
		vp.subviewport.transparent_bg = _render_orig["transp"]
		vp.model_mat.roughness = _render_orig["rough"]
		vp.model_mat.metallic = _render_orig["metal"]
		sun2.visible = false
		vp.edges_mi.visible = vp.show_edges
		_set_render_lighting(false)
		ground.visible = false
		return
	var sky := Sky.new()
	match preset:
		"studio":
			var ps := ProceduralSkyMaterial.new()
			ps.sky_top_color = Color(0.78, 0.8, 0.84)
			ps.sky_horizon_color = Color(0.93, 0.94, 0.95)
			ps.ground_horizon_color = Color(0.86, 0.86, 0.87)
			ps.ground_bottom_color = Color(0.55, 0.56, 0.58)
			sky.sky_material = ps
		"day":
			var pd := ProceduralSkyMaterial.new()
			pd.sky_top_color = Color(0.32, 0.52, 0.85)
			pd.sky_horizon_color = Color(0.75, 0.83, 0.92)
			pd.ground_bottom_color = Color(0.25, 0.22, 0.18)
			sky.sky_material = pd
		"night":
			var pn := ProceduralSkyMaterial.new()
			pn.sky_top_color = Color(0.02, 0.03, 0.08)
			pn.sky_horizon_color = Color(0.1, 0.12, 0.2)
			pn.ground_bottom_color = Color(0.02, 0.02, 0.03)
			sky.sky_material = pn
		"hdri":
			var pm := PanoramaSkyMaterial.new()
			pm.panorama = render_st.get("hdri_tex", null)
			sky.sky_material = pm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.2 if preset == "night" else 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(render_st["exposure"])
	env.ssao_enabled = bool(render_st["ssao"])
	env.ssr_enabled = bool(render_st["ssr"])
	env.glow_enabled = bool(render_st["glow"])
	vp.subviewport.transparent_bg = false
	sun2.visible = true
	vp.edges_mi.visible = false  # fotogerçekçi görünümde siyah kenar çizgileri yok
	_set_render_lighting(true)
	sun2.shadow_enabled = bool(render_st["shadows"])
	sun2.light_energy = 0.3 if preset == "night" else 1.8
	var bb := vp.model.aabb if not vp.model.is_empty() else AABB(Vector3(-50, 0, -50), Vector3(100, 10, 100))
	(ground.mesh as PlaneMesh).size = Vector2(bb.size.length() * 4.0, bb.size.length() * 4.0)
	ground.position = Vector3(bb.get_center().x, bb.position.y - 0.01, bb.get_center().z)
	ground.visible = bool(render_st["ground"])
	# Gölge mesafesi kamerayı ve modeli kapsamalı (varsayılan 100 birim küçük/büyük parçalarda yetmez)
	var cam_d: float = vp.camera.global_position.distance_to(bb.get_center())
	sun2.directional_shadow_max_distance = maxf(50.0, cam_d + bb.size.length() * 2.0)
	sun2.shadow_bias = 0.03
	var fin := str(render_st["finish"])
	var metal := 0.0
	var rough := 0.5
	if fin == "auto":
		var grp := ""
		for m in Materials.LIST:
			if m["name"] == _doc().material:
				grp = str(m.get("group", ""))
		match grp:
			"Metal":
				metal = 0.85
				rough = 0.32
			"Ahşap":
				rough = 0.8
			_:
				rough = 0.45
	elif fin == "matte":
		rough = 0.9
	elif fin == "gloss":
		rough = 0.12
	elif fin == "metal":
		metal = 1.0
		rough = 0.22
	vp.model_mat.metallic = metal
	vp.model_mat.roughness = rough


## Render ışığı: model gölge düşürür, kameraya bağlı CAD ışıkları kısılır (güneş + gökyüzü baskın olsun)
func _set_render_lighting(on: bool) -> void:
	var vp: CadViewport = app.viewport
	vp.model_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in vp.camera.get_children():
		if c is DirectionalLight3D:
			if not c.has_meta("cad_energy"):
				c.set_meta("cad_energy", c.light_energy)
			var e0: float = c.get_meta("cad_energy")
			c.light_energy = e0 * 0.3 if on else e0


func _panel_render(panel: PropertyPanel) -> void:
	panel.title("Görselleştirme", Icons.get_icon("render", 22))
	var envs := ["default", "studio", "day", "night", "hdri"]
	var on_e := func(i: int) -> void:
		if envs[i] == "hdri" and not render_st.has("hdri_tex"):
			app._file_dialog(false, ["*.hdr, *.exr, *.png, *.jpg ; Panorama görüntüsü"], "HDRI / panorama seç", "render_hdri")
			return
		render_st["env"] = envs[i]
		apply_render()
		app._refresh_panel()
	panel.option("Ortam", ["CAD (varsayılan)", "Stüdyo", "Gün ışığı", "Gece", "HDRI dosyası"], maxi(envs.find(str(render_st["env"])), 0), on_e)
	var hd := func() -> void: app._file_dialog(false, ["*.hdr, *.exr, *.png, *.jpg ; Panorama görüntüsü"], "HDRI / panorama seç", "render_hdri")
	panel.button("HDRI / panorama yükle", hd, Icons.get_icon("import", 16))
	var setb := func(b: bool, k: String) -> void:
		render_st[k] = b
		apply_render()
	panel.check("Gölgeler", bool(render_st["shadows"]), setb.bind("shadows"))
	panel.check("Zemin (gölge yakalayıcı)", bool(render_st["ground"]), setb.bind("ground"))
	panel.check("Ortam kapatma (SSAO)", bool(render_st["ssao"]), setb.bind("ssao"))
	panel.check("Ekran uzayı yansıma (SSR)", bool(render_st["ssr"]), setb.bind("ssr"))
	panel.check("Parlama (glow)", bool(render_st["glow"]), setb.bind("glow"))
	var fins := ["auto", "matte", "gloss", "metal"]
	var on_f := func(i: int) -> void:
		render_st["finish"] = fins[i]
		apply_render()
	panel.option("Yüzey", ["Malzemeden (PBR)", "Mat", "Parlak", "Metal"], maxi(fins.find(str(render_st["finish"])), 0), on_f)
	var on_x := func(v: float) -> void:
		render_st["exposure"] = v
		apply_render()
	panel.number("Pozlama", float(render_st["exposure"]), on_x, "plain", 0.1, 8.0)
	panel.section("Çıkartmalar (decal)")
	var on_ds := func(v: float) -> void: render_st["decal_size"] = v
	panel.number("Çıkartma boyu", float(render_st["decal_size"]), on_ds, "length", 0.1)
	var add := func() -> void: app._file_dialog(false, ["*.png, *.jpg, *.webp ; Görüntü"], "Çıkartma görüntüsü seç", "decal_img")
	panel.button("Çıkartma ekle (görüntü seç, sonra yüze tıkla)", add, Icons.get_icon("new", 16))
	if not _decals.is_empty():
		var clr := func() -> void:
			for d in _decals:
				(d as Node).queue_free()
			_decals.clear()
			app._refresh_panel()
		panel.button(I18n.t("Çıkartmaları temizle (%d)") % _decals.size(), clr, Icons.get_icon("delete", 16))
	panel.section("Çıktı")
	var shot := func() -> void: app._file_dialog(true, ["*.png ; PNG"], "Render kaydet (2× çözünürlük)", "render_png", _doc().part_name + "_render.png")
	panel.button("Render kaydet (2×)", shot, Icons.get_icon("export", 16))


## Görünümü geçici olarak büyütülmüş çözünürlükte çizip PNG kaydeder.
func render_to(path: String, scale: int) -> void:
	var vp: CadViewport = app.viewport
	var old_stretch := vp.container.stretch
	var old_size := vp.subviewport.size
	vp.container.stretch = false
	vp.subviewport.size = old_size * scale
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.subviewport.get_texture().get_image()
	vp.subviewport.size = old_size
	vp.container.stretch = old_stretch
	if img == null or img.is_empty():
		app._set_status("Render alınamadı (görüntü boş).")
		return
	if vp.subviewport.transparent_bg:
		var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		out.fill(Color(0.96, 0.97, 0.99))
		img.convert(Image.FORMAT_RGBA8)
		out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
		img = out
	var err := img.save_png(path)
	app._set_status((I18n.t("Render kaydedildi: %s (%d × %d)") % [path, img.get_width(), img.get_height()]) if err == OK else "Render kaydedilemedi")
