extends Control
## DIY.CAD ana uygulama: arayüz, komutlar, modlar ve seçim.
##
## Modlar:
##   idle    : seçim (düzlem / yüz / özellik)
##   sketch  : taslak düzenleme (SketchEditor)
##   feature : özellik paneli açık (Ekstrüzyon / Döndürme / Yuvarlatma / Pah / Kabuk), canlı önizleme

const APP_NAME := "DIY.CAD"
const APP_VERSION := "0.9.5 — Faz 9"
const STL_PRESETS := [["Kaba", 0.1, 20.0], ["Normal", 0.02, 10.0], ["İnce", 0.005, 5.0], ["Çok ince", 0.001, 2.0]]

var doc := CadDocument.new()
var viewport: CadViewport
var editor: SketchEditor
var editor3d: Sketch3DEditor
var _sketch3d_new := false
var tree: FeatureTree
var panel: PropertyPanel
var status_label: Label
var coord_label: Label
var tabs: TabBar
var toolbar_features: HFlowContainer
var toolbar_sketch: HFlowContainer
var toolbar_eval: HBoxContainer
var tool_buttons := {}
var grid_btn: Button
var rel_btn: Button
var persp_btn: Button
var units_btn: MenuButton
var def_label: Label
var kernel_label: Button
var props_dialog: AcceptDialog
var context_menu: PopupMenu
var file_dialog: FileDialog
var export_dlg: ExportDialog
var confirm_dialog: ConfirmationDialog
var info_dialog: AcceptDialog
var view_menu: PopupMenu

var mode := "idle"
var selection := {}
var editing: CadFeature = null
var editing_is_new := false
var _error_label: Label = null
var _sketch_was_new := false
var _pending_file_action := ""
var _confirm_action := Callable()
var _syncing_tree := false
var _fit_after_build := false
var _pick_for_sketch := false
var _context_meta := {}
var _sketch_op := ""        # taslakta açık işlem paneli: "offset" | "transform"
var _region_pick := false   # özellik panelinde bölge seçme modu
var _op_params := {"dist": 5.0, "flip": false, "kind": "move", "dx": 10.0, "dy": 0.0, "cx": 0.0, "cy": 0.0, "angle": 90.0, "scale": 2.0, "count": 3, "total": 360.0, "copy": false}
var _measure_picks: Array = []
var _mass_result := {}
var _material_choice := ""
var _brep_show_result := false    # yuvarlatma/pah/kabuk düzenlenirken sonucu göster (seçim kapalı)
var _hover_edge := -1
var _stl_quality := 1             # STL_PRESETS indeksi (B-rep çekirdeğiyle)
var _stl_ascii := false

# Komut satırı ile ekran görüntüsü (test / tanıtım)
var _shot_path := ""
var _shot_mode := ""
var _shot_frames := 0
var _built_once := false
var autosave: Autosave
var recent_menu: PopupMenu
var recovery_dialog: ConfirmationDialog
var _recovery_rec := {}
var _test_mode := false          # --uitest / --shot: otomatik kayıt ve kurtarma kapalı
var keymap := Keymap.new()
var _commands := {}              # komut kimliği -> {label, tip, cb, ctx, group}  (kısayol / fare hareketi / makro)
var _menu_items: Array = []      # [popup, index, cmd, temel etiket]
var options_dialog: OptionsDialog
var macro: MacroApi
var plugins: Plugins
var toolbar_plugins: HFlowContainer
var _plugin_panel_api: PluginApi = null
var _macro_src := ""
var _cmdline_macro := ""
var gesture: MouseGesture


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	UiTheme.apply_settings(get_tree(), _arg_value("--theme="))
	var lang_o := _arg_value("--lang=")
	I18n.set_language(lang_o if lang_o != "" else str(AppSettings.get_v("ui", "lang")), false)
	keymap.load_settings()
	_build_ui()
	_reg_cmd("grid_toggle", "Izgaraya yakala (aç / kapat)", "Taslak ızgara yakalamasını aç/kapat", _toggle_grid, "sketch", "Taslak")
	_refresh_shortcut_labels()
	editor = SketchEditor.new()
	editor.viewport = viewport
	editor.doc = doc
	add_child(editor)
	editor.status.connect(_set_status)
	editor.tool_changed.connect(_on_tool_changed)
	editor.selection_changed.connect(_refresh_panel)
	editor.cursor_moved.connect(_on_cursor_moved)
	editor.definition_changed.connect(_on_definition_changed)
	editor3d = Sketch3DEditor.new()
	editor3d.viewport = viewport
	editor3d.doc = doc
	add_child(editor3d)
	editor3d.status.connect(_set_status)
	editor3d.changed_selection.connect(_refresh_panel)
	doc.changed.connect(_on_doc_changed)
	viewport.kernel.built.connect(_on_built)
	viewport.kernel.backend_changed.connect(_on_backend_changed)
	viewport.kernel.export_done.connect(_on_export_done)
	viewport.kernel.hlr_done.connect(_on_hlr_done)
	var cf := ConfigFile.new()
	if cf.load(GeoKernel.SETTINGS_PATH) == OK:
		_stl_quality = clampi(int(cf.get_value("export", "stl_quality", 1)), 0, STL_PRESETS.size() - 1)
		_stl_ascii = bool(cf.get_value("export", "stl_ascii", false))
	viewport.pointer_input.connect(_on_pointer)
	viewport.gesture_input.connect(_on_gesture)
	viewport.rmb_gestures = str(AppSettings.get_v("mouse", "rmb")) == "gesture"
	gesture = MouseGesture.new()
	viewport.add_child(gesture)
	macro = MacroApi.new(self)
	plugins = Plugins.new(self)
	if not "--no-plugins" in OS.get_cmdline_user_args():
		plugins.load_all()
	viewport.view_changed.connect(_on_view_changed)
	_handle_cmdline()
	autosave = Autosave.new()
	autosave.app = self
	add_child(autosave)
	if _test_mode:
		autosave.enabled = false
		autosave.reload_settings.call_deferred()
	_update_kernel_label()
	_on_doc_changed()
	_set_status("Hazır. Bir düzlem seçip 'Taslak' komutuyla çizime başlayın.")
	if not _test_mode:
		_check_recovery.call_deferred()
	if _cmdline_macro != "":
		_run_macro.call_deferred(_cmdline_macro)


# ================================================================ ARAYÜZ

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.c("bg")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# --- Menü satırı
	var menu_row := HBoxContainer.new()
	menu_row.add_theme_constant_override("separation", 2)
	root.add_child(_padded(menu_row, UiTheme.c("bar")))
	var logo := TextureRect.new()
	logo.texture = Icons.get_icon("part", 20)
	logo.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	menu_row.add_child(logo)
	var file_m := _menu(menu_row, "Dosya", [
		["Yeni\tCtrl+N", "new"], ["Yeni Montaj", "new_asm"], ["Aç...\tCtrl+O", "open"], ["Kaydet\tCtrl+S", "save"],
		["Farklı Kaydet...\tCtrl+Shift+S", "save_as"], [],
		["Dışa Aktar...\tCtrl+E", "export_all"], ["STEP / IGES içe aktar...", "import_step"], [],
		["Örnek parçayı aç", "demo"], ["Örnek montajı aç", "demo_asm"], ["Örnek: isim plakası (metin, spline, denklemler)", "demo2"], [], ["Çıkış", "quit"]])
	file_m.name = "FileMenu"
	recent_menu = PopupMenu.new()
	recent_menu.name = "RecentMenu"
	recent_menu.id_pressed.connect(_on_recent_id)
	var fpm := file_m.get_popup()
	fpm.add_submenu_node_item("Son Dosyalar", recent_menu, 900)
	fpm.set_item_index(fpm.item_count - 1, 3)
	_refresh_recent_menu()
	_menu(menu_row, "Düzen", [
		["Geri Al\tCtrl+Z", "undo"], ["Yinele\tCtrl+Y", "redo"], [],
		["Sil\tDelete", "delete"], ["Yeniden Adlandır\tF2", "rename"]])
	var vm := _menu(menu_row, "Görünüm", [
		["Ekrana Sığdır\tF", "fit"], [],
		["Ön\tCtrl+1", "view_front"], ["Arka\tCtrl+2", "view_back"], ["Sol\tCtrl+3", "view_left"],
		["Sağ\tCtrl+4", "view_right"], ["Üst\tCtrl+5", "view_top"], ["Alt\tCtrl+6", "view_bottom"],
		["İzometrik\tCtrl+7", "view_iso"], ["Düzleme Dik\tCtrl+8", "normal"], [],
		["Perspektif", "persp"], ["Kenarları göster", "edges"], ["Düzlemleri göster", "planes"]])
	view_menu = vm.get_popup()
	_menu(menu_row, "Araçlar", [
		["Akıllı Boyut (taslakta)\tD", "tool_dimension"], ["Denklemler...", "equations"], [],
		["Ölç...", "measure"], ["Kütle Özellikleri...", "mass"], [],
		["Malzeme...", "material"], ["Belge Özellikleri (birimler)...", "doc_props"], [],
		["Geometri çekirdeği ve dışa aktarma...", "kernel_options"], [],
		["Makro çalıştır...", "macro_run"], ["Makro kaydını başlat / durdur", "macro_record"], ["Parçayı makro olarak kaydet...", "macro_export"], [],
		["Seçenekler (kısayollar, fare, tema, dil)...", "options"]])
	_menu(menu_row, "Yardım", [["Fare ve kısayollar", "help"], ["Yol haritası", "roadmap"], ["Hakkında", "about"]])
	menu_row.add_child(VSeparator.new())
	for q in [["new", "Yeni (Ctrl+N)"], ["open", "Aç (Ctrl+O)"], ["save", "Kaydet (Ctrl+S)"],
			["undo", "Geri Al (Ctrl+Z)"], ["redo", "Yinele (Ctrl+Y)"]]:
		var b := Button.new()
		b.icon = Icons.get_icon(q[0], 20)
		b.tooltip_text = q[1]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_cmd.bind(q[0]))
		menu_row.add_child(b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_row.add_child(sp)
	var title_l := Label.new()
	title_l.text = APP_NAME + "  " + APP_VERSION
	title_l.add_theme_color_override("font_color", UiTheme.c("title"))
	menu_row.add_child(title_l)

	# --- Komut yöneticisi
	var cm := VBoxContainer.new()
	cm.add_theme_constant_override("separation", 0)
	root.add_child(_padded(cm, UiTheme.c("cm")))
	tabs = TabBar.new()
	tabs.add_tab("Özellikler")
	tabs.add_tab("Taslak")
	tabs.add_tab("Değerlendir")
	tabs.add_tab("Teknik Resim")
	tabs.add_tab("Montaj")
	tabs.set_tab_hidden(4, true)
	tabs.add_tab("Sac Metal")
	tabs.add_tab("Kaynaklar")
	tabs.add_tab("Yüzeyler")
	tabs.add_tab("Analiz")
	tabs.add_tab("Eklentiler")
	tabs.set_tab_hidden(9, true)
	tabs.tab_changed.connect(_on_tab_changed)
	cm.add_child(tabs)
	toolbar_features = HFlowContainer.new()
	toolbar_features.set_meta("group", "Özellikler")
	cm.add_child(toolbar_features)
	_tb(toolbar_features, "Taslak", "sketch", "Seçili düzlem veya düzlemsel yüzey üzerinde yeni taslak", _cmd.bind("sketch"))
	toolbar_features.add_child(VSeparator.new())
	_tb(toolbar_features, "Ekstrüzyon\nPatron/Taban", "extrude", "Taslağı belirli bir mesafe boyunca uzatarak katı oluşturur", _cmd.bind("extrude"))
	_tb(toolbar_features, "Ekstrüzyon\nKesme", "cut", "Taslak profiliyle malzeme keser", _cmd.bind("cut"))
	_tb(toolbar_features, "Döndürme\nPatron/Taban", "revolve", "Taslağı bir eksen etrafında döndürerek katı oluşturur", _cmd.bind("revolve"))
	_tb(toolbar_features, "Döndürerek\nKesme", "revcut", "Döndürülmüş profil ile malzeme keser", _cmd.bind("revcut"))
	_tb(toolbar_features, "Süpürme", "sweep", "Profili bir yol (taslak, 3B taslak veya helis) boyunca süpür", _cmd.bind("sweep"))
	_tb(toolbar_features, "Süpürme\nKesme", "sweepcut", "Süpürülen profille malzeme kes", _cmd.bind("sweepcut"))
	_tb(toolbar_features, "Loft", "loft", "Profiller arasında geçiş katısı", _cmd.bind("loft"))
	_tb(toolbar_features, "Loft\nKesme", "loftcut", "Loft ile malzeme kes", _cmd.bind("loftcut"))
	toolbar_features.add_child(VSeparator.new())
	_tb(toolbar_features, "Köşe\nYuvarlatma", "fillet3d", "Seçili kenarları yuvarlat (OpenCASCADE çekirdeği)", _cmd.bind("fillet3d"))
	_tb(toolbar_features, "Pah", "chamfer3d", "Seçili kenarlara pah kır (OpenCASCADE çekirdeği)", _cmd.bind("chamfer3d"))
	_tb(toolbar_features, "Kabuk", "shell", "Gövdeyi içten boşalt; seçili yüzler açık kalır (OpenCASCADE çekirdeği)", _cmd.bind("shell"))
	_tb(toolbar_features, "Eğim", "draft", "Yüzlere kalıptan çıkma eğimi ver (tarafsız yüze göre)", _cmd.bind("draft"))
	_tb(toolbar_features, "Kaburga", "rib", "Açık taslak çizgisinden gövdeye dayanan kaburga", _cmd.bind("rib"))
	_tb(toolbar_features, "Delik\nSihirbazı", "hole", "Standart delikler: düz, havşa başlı, havşa, kılavuz (ISO / ANSI)", _cmd.bind("hole"))
	_tb(toolbar_features, "Kubbe", "dome", "Düzlemsel yüze kubbe ekle", _cmd.bind("dome"))
	_tb(toolbar_features, "Sarma", "wrap", "Taslağı silindirik yüze sar: kabartma, oyma veya çizgi", _cmd.bind("wrap"))
	_tb(toolbar_features, "Kabartma", "emboss", "Taslağı yüzeyi izleyerek kabart veya oy (gravür)", _cmd.bind("emboss"))
	_tb_menu(toolbar_features, "Çoğaltma", "lpattern", "Doğrusal / dairesel / tablo güdümlü çoğaltma ve aynalama",
		[["Doğrusal Çoğaltma", "lpattern"], ["Dairesel Çoğaltma", "cpattern"], ["Aynala", "mirror"], ["Tablo Güdümlü Çoğaltma", "tpattern"], ["Eğri Güdümlü Çoğaltma", "cvpattern"]])
	_tb_menu(toolbar_features, "Referans\nGeometri", "refplane", "Referans düzlem, eksen, nokta ve helis",
		[["Düzlem", "refplane"], ["Eksen", "refaxis"], ["Nokta", "refpoint"], ["Koordinat Sistemi", "refcsys"], ["Helis / Spiral", "helix"], ["Projeksiyon Eğrisi", "projcurve"]])
	toolbar_features.add_child(VSeparator.new())
	_tb(toolbar_features, "Gövdeleri\nBirleştir", "combine", "Gövdeleri ekle / çıkar / kesiştir", _cmd.bind("combine"))
	_tb(toolbar_features, "Gövde Taşı\nKopyala", "move_body", "Gövdeyi taşı, döndür veya kopyala", _cmd.bind("move_body"))
	_tb(toolbar_features, "Böl", "split", "Gövdeleri bir ana düzlemle böl", _cmd.bind("split"))
	toolbar_features.add_child(VSeparator.new())
	_tb(toolbar_features, "Dışa\nAktar", "export", "Tüm formatlara dışa aktar: STEP, IGES, STL, 3MF, OBJ, glTF, DXF, PDF, görüntü... (Ctrl+E)", _cmd.bind("export_all"))
	_tb(toolbar_features, "İçe\nAktar", "import", "STEP / IGES / STL dosyasını gövde olarak içe aktar (STL: eksen bazlı ölçek ve uzatma)", _cmd.bind("import_step"))
	toolbar_features.add_child(VSeparator.new())
	_tb(toolbar_features, "Denklemler", "equations", "Global değişkenler ve boyut denklemleri", _cmd.bind("equations"))
	_tb(toolbar_features, "3B Taslak", "sketch3d", "Uzayda çizgi zinciri (süpürme yolu için). Tab: çizim düzlemini değiştir", _cmd.bind("sketch3d"))

	toolbar_sketch = HFlowContainer.new()
	toolbar_sketch.set_meta("group", "Taslak")
	toolbar_sketch.visible = false
	cm.add_child(toolbar_sketch)
	_tb(toolbar_sketch, "Taslaktan\nÇık", "exit_sketch", "Taslağı kapat ve modeli güncelle", _cmd.bind("exit_sketch"), false, 58)
	toolbar_sketch.add_child(VSeparator.new())
	for t in [["select", "Seç", "select", "Seçim ve nokta sürükleme (Esc)"],
			["line", "Çizgi", "line", "Zincirleme çizgi (L)"],
			["centerline", "Merkez\nÇizgisi", "centerline", "Yapı/eksen çizgisi — döndürme ve ayna ekseni (N)"],
			["rect", "Köşe\nDikdörtgen", "rect", "İki köşeden dikdörtgen (R)"],
			["crect", "Merkez\nDikdörtgen", "crect", "Merkez ve köşeden dikdörtgen"],
			["circle", "Daire", "circle", "Merkez ve yarıçaptan daire (C)"],
			["arc", "Merkez\nYay", "arc", "Merkez, başlangıç ve bitişten yay (A)"],
			["polygon", "Çokgen", "polygon", "Düzgün çokgen: merkez + köşe (kenar sayısı panelden) (P)"],
			["ellipse", "Elips", "ellipse", "Elips: merkez, büyük eksen ucu, küçük eksen"],
			["parabola", "Parabol", "parabola", "Parabol: tepe, odak, iki uç"],
			["slot", "Kanal", "slot", "Düz kanal: iki yay merkezi + genişlik"],
			["spline", "Spline", "spline", "Noktalardan geçen eğri (S ile değil; çift tık/Enter bitirir)"],
			["text", "Metin", "text", "Taslak metni — kabartma/gravür için ekstrüzyonla kullanılır"],
			["dimension", "Akıllı\nBoyut", "dimension", "Öğeleri ölçülendir: çizgi = uzunluk, daire = çap, yay = yarıçap, iki çizgi = açı (D)"]]:
		tool_buttons[t[0]] = _tb(toolbar_sketch, t[1], t[2], t[3], _on_tool_button.bind(t[0]), true, 58)
	toolbar_sketch.add_child(VSeparator.new())
	for t in [["trim", "Kırp", "trim", "Güç kırpma: silinecek parçaya tıklayın (T)"],
			["extend", "Uzat", "extend", "Çizgiyi ilk kesiştiği öğeye uzat (E)"],
			["fillet", "Köşe\nYuvarlat", "fillet", "Köşeye tıklayın; yarıçap panelden (F değil, panel)"],
			["chamfer", "Pah", "chamfer", "Köşeye tıklayın; mesafe panelden"],
			["convert", "Varlıkları\nDönüştür", "convert", "Model yüzünün kenarlarını taslağa çizgi/yay olarak al"]]:
		tool_buttons[t[0]] = _tb(toolbar_sketch, t[1], t[2], t[3], _on_tool_button.bind(t[0]), true, 58)
	_tb(toolbar_sketch, "Blok", "block", "Seçili öğelerden rijit blok oluştur", _cmd.bind("op_block"), false, 58)
	_tb(toolbar_sketch, "Ofset", "offset", "Seçili öğelerin ofsetini al (zincirler köşeleriyle birlikte)", _cmd.bind("op_offset"), false, 58)
	_tb(toolbar_sketch, "Aynala", "mirror", "Seçili öğeleri seçili merkez çizgisine göre aynala", _cmd.bind("op_mirror"), false, 58)
	_tb(toolbar_sketch, "Taşı /\nÇoğalt", "pattern", "Taşı, kopyala, döndür, ölçekle, doğrusal/dairesel çoğalt", _cmd.bind("op_transform"), false, 58)
	toolbar_sketch.add_child(VSeparator.new())
	_tb(toolbar_sketch, "İlişki\nEkle", "relation", "Seçili öğelere geometrik ilişki ekle (yatay, dikey, paralel, teğet...)", _cmd.bind("add_relation"), false, 58)
	rel_btn = _tb(toolbar_sketch, "İlişkileri\nGöster", "relations_show", "Taslak ilişki simgelerini göster/gizle", func(): editor.set_show_relations(rel_btn.button_pressed), true, 58)
	rel_btn.button_pressed = true
	grid_btn = _tb(toolbar_sketch, "Izgaraya\nYakala", "grid", "Izgara yakalamayı aç/kapat (G)", func(): editor.set_grid_snap(grid_btn.button_pressed), true, 58)
	grid_btn.button_pressed = true
	_tb(toolbar_sketch, "Yapı\nGeometrisi", "centerline", "Seçili öğeleri yapı (construction) geometrisine çevir / geri al", _cmd.bind("toggle_construction"), false, 58)
	_tb(toolbar_sketch, "Sil", "delete", "Seçili öğeleri sil (Delete)", _cmd.bind("delete"), false, 58)
	toolbar_sketch.add_child(VSeparator.new())
	_tb(toolbar_sketch, "Ekstrüzyon", "extrude", "Taslaktan çık ve ekstrüzyon uygula", _cmd.bind("extrude"), false, 58)
	_tb(toolbar_sketch, "Dışa\nAktar", "export", "Taslağı (DXF, SVG) veya modeli dışa aktar (Ctrl+E)", _cmd.bind("export_all"), false, 58)

	toolbar_eval = HBoxContainer.new()
	toolbar_eval.set_meta("group", "Değerlendir")
	toolbar_eval.visible = false
	cm.add_child(toolbar_eval)
	_tb(toolbar_eval, "Ölç", "measure", "Yüz alanı, mesafe, açı ve koordinat ölç", _cmd.bind("measure"))
	_tb(toolbar_eval, "Kütle\nÖzellikleri", "mass", "Hacim, kütle, ağırlık merkezi ve atalet momentleri", _cmd.bind("mass"))
	toolbar_eval.add_child(VSeparator.new())
	_tb(toolbar_eval, "Malzeme", "material", "Parçanın malzemesini seç (yoğunluk ve görünüm)", _cmd.bind("material"))
	_tb(toolbar_eval, "Birimler", "units", "Belge özellikleri: birim sistemi ve ondalık hassasiyet", _cmd.bind("doc_props"))
	_tb(toolbar_eval, "Konfigürasyon", "configs", "Konfigürasyonlar ve tasarım tablosu (CSV)", _cmd.bind("configs"))
	_build_drawing_toolbar(cm)
	asm_mode = AssemblyMode.new()
	asm_mode.app = self
	add_child(asm_mode)
	asm_mode.build_toolbar(cm)
	special = SpecialUI.new()
	special.app = self
	add_child(special)
	special.build_toolbars(cm)
	toolbar_plugins = HFlowContainer.new()
	toolbar_plugins.set_meta("group", "Eklentiler")
	toolbar_plugins.visible = false
	cm.add_child(toolbar_plugins)

	# --- Ana alan
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var left := VSplitContainer.new()
	left.custom_minimum_size.x = 300
	split.add_child(left)
	tree = FeatureTree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 180
	left.add_child(tree)
	tree.picked.connect(_on_tree_picked)
	tree.activated.connect(_on_tree_activated)
	tree.context_requested.connect(_on_tree_context)
	tree.feature_renamed.connect(_on_renamed)
	tree.move_requested.connect(_on_tree_move)
	panel = PropertyPanel.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 260
	left.add_child(panel)

	viewport = CadViewport.new()
	viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var center := Control.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(center)
	viewport.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(viewport)
	drawing_canvas = DrawingCanvas.new()
	drawing_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drawing_canvas.visible = false
	center.add_child(drawing_canvas)
	drawing_canvas.clicked.connect(_dw_on_click)
	drawing_canvas.dragged.connect(_dw_on_drag)
	drawing_canvas.hovered.connect(func(p: Vector2) -> void: coord_label.text = I18n.t("Sayfa: %.1f, %.1f mm") % [p.x, p.y])
	_build_view_overlay()

	# --- Durum çubuğu
	var sb := HBoxContainer.new()
	root.add_child(_padded(sb, UiTheme.c("bar")))
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	sb.add_child(status_label)
	coord_label = Label.new()
	coord_label.custom_minimum_size.x = 260
	coord_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sb.add_child(coord_label)
	sb.add_child(VSeparator.new())
	def_label = Label.new()
	def_label.custom_minimum_size.x = 150
	def_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sb.add_child(def_label)
	sb.add_child(VSeparator.new())
	kernel_label = Button.new()
	kernel_label.flat = true
	kernel_label.focus_mode = Control.FOCUS_NONE
	kernel_label.icon = Icons.get_icon("kernel", 16)
	kernel_label.tooltip_text = "Geometri çekirdeği (tıklayın: seçenekler)"
	kernel_label.pressed.connect(_cmd.bind("kernel_options"))
	sb.add_child(kernel_label)
	sb.add_child(VSeparator.new())
	units_btn = MenuButton.new()
	units_btn.flat = true
	units_btn.tooltip_text = "Birim sistemi (tıklayın: değiştir)"
	var up := units_btn.get_popup()
	for i in Units.SYSTEM_ORDER.size():
		up.add_item(Units.SYSTEMS[Units.SYSTEM_ORDER[i]]["label"], i)
	up.add_separator()
	up.add_item("Belge özellikleri...", 100)
	up.id_pressed.connect(_on_units_menu)
	sb.add_child(units_btn)

	# --- Diyaloglar
	context_menu = PopupMenu.new()
	add_child(context_menu)
	context_menu.id_pressed.connect(_on_context_id)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)
	export_dlg = ExportDialog.new()
	export_dlg.chosen.connect(_export_chosen)
	add_child(export_dlg)
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = APP_NAME
	confirm_dialog.ok_button_text = "Evet"
	confirm_dialog.cancel_button_text = "Vazgeç"
	confirm_dialog.confirmed.connect(_on_confirmed)
	add_child(confirm_dialog)
	info_dialog = AcceptDialog.new()
	info_dialog.title = APP_NAME
	add_child(info_dialog)


func _on_confirmed() -> void:
	if _confirm_action.is_valid():
		_confirm_action.call()


func _padded(child: Control, color: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	pc.add_child(child)
	return pc


func _menu(parent: Control, text: String, items: Array) -> MenuButton:
	var mb := MenuButton.new()
	mb.text = text
	mb.flat = true
	mb.switch_on_hover = true
	var pm := mb.get_popup()
	var cmds: Array = []
	for it in items:
		if it.is_empty():
			pm.add_separator()
			cmds.append("")
			continue
		var cmd: String = it[1]
		var label: String = str(it[0]).split("\t")[0]
		if cmd in ["persp", "edges", "planes"]:
			pm.add_check_item(label, cmds.size())
			pm.set_item_checked(pm.item_count - 1, cmd == "edges")
		else:
			pm.add_item(label, cmds.size())
		_menu_items.append([pm, pm.item_count - 1, cmd, label])
		_reg_cmd(cmd, label.trim_suffix("..."), "", _cmd.bind(cmd), "global", text, null, label)
		cmds.append(cmd)
	pm.id_pressed.connect(func(id): _cmd(cmds[id]))
	parent.add_child(mb)
	return mb


func _tb(parent: Control, text: String, icon_name: String, tip: String, cb: Callable, toggle := false, width := 70) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = Icons.get_icon(icon_name, 28 if width >= 70 else 24)
	b.tooltip_text = tip
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.flat = true
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 62 if width >= 70 else 56)
	b.add_theme_font_size_override("font_size", 12 if width >= 70 else 11)
	b.pressed.connect(cb)
	parent.add_child(b)
	var args := cb.get_bound_arguments()
	if not args.is_empty() and args[0] is String:
		var cid := str(args[0])
		var tool := cb.get_method() == "_on_tool_button"
		if tool:
			cid = "tool:" + cid
		_reg_cmd(cid, text.replace("-\n", "").replace("\n", " "), tip, cb, "sketch" if tool else "global", str(parent.get_meta("group", "")), b.icon, text)
	return b


## Komut kaydı: kısayol, fare hareketi ve makrolardan çağrılabilir komutlar (ilk kayıt geçerli)
func _reg_cmd(id: String, label: String, tip: String, cb: Callable, ctx := "global", group := "", icon: Texture2D = null, raw := "") -> void:
	if id == "":
		return
	if _commands.has(id):
		if icon != null and _commands[id]["icon"] == null:
			_commands[id]["icon"] = icon
		return
	_commands[id] = {"label": label, "tip": tip, "cb": cb, "ctx": ctx, "group": group, "icon": icon, "raw": raw if raw != "" else label}


## Eklenti komutu: "Eklentiler" sekmesinde düğme + komut kaydı (Faz 9)
func add_plugin_command(id: String, label: String, tip: String, icon_name: String, cb: Callable) -> void:
	var b := _tb(toolbar_plugins, label, icon_name, tip, cb)
	_reg_cmd(id, label.replace("-\n", "").replace("\n", " "), tip, cb, "global", "Eklentiler", b.icon, label)
	tabs.set_tab_hidden(9, mode == "assembly")


func show_plugin_panel(api: PluginApi) -> void:
	_exit_sketch3d()
	if mode == "sketch":
		_exit_sketch()
	if mode == "feature":
		_cancel_feature()
	if mode == "assembly":
		_set_status("Eklenti paneli parça ekranında açılır.")
		return
	_leave_aux_mode()
	_plugin_panel_api = api
	mode = "plugin"
	_refresh_panel()


func show_options(tab := 0) -> void:
	if options_dialog == null:
		options_dialog = OptionsDialog.new()
		options_dialog.app = self
		add_child(options_dialog)
	options_dialog.open_tab(tab)


func _on_language_changed() -> void:
	_refresh_shortcut_labels()
	_update_tree()
	_refresh_panel()
	_set_status(I18n.t("Dil değiştirildi."))


## Fare hareketi halkası (CadViewport sağ tuş sürükleme)
func _on_gesture(phase: String, pos: Vector2) -> void:
	if mode == "drawing":
		return
	match phase:
		"begin":
			var ctx := "sketch" if mode == "sketch" else ("assembly" if mode == "assembly" else "part")
			var slots: Array = []
			for id in MouseGesture.mapping(ctx):
				var c: Dictionary = _commands.get(id, {})
				var ic: Texture2D = c.get("icon", null)
				if ic == null and str(id).begins_with("tool:"):
					ic = Icons.get_icon(str(id).substr(5), 24)
				elif ic == null and (str(id).begins_with("view_") or id in ["fit", "normal"]):
					ic = Icons.get_icon("views" if str(id).begins_with("view_") else str(id), 24)
				slots.append({"cmd": id, "label": I18n.t(str(c.get("label", id))) if id != "" else "", "icon": ic})
			gesture.begin(pos, slots)
		"move":
			gesture.update(pos)
		"end":
			var cmd := gesture.finish(pos)
			if cmd != "":
				_set_status(I18n.t("Fare hareketi") + ": " + I18n.t(command_label(cmd)))
				if not run_command(cmd):
					_cmd(cmd)


## Komutun görünen adı (etkin dilde; iki satırlı araç çubuğu metinleri tek satıra)
func command_label(id: String) -> String:
	if not _commands.has(id):
		return id
	var c: Dictionary = _commands[id]
	return I18n.t(str(c.get("raw", c["label"]))).replace("-\n", "").replace("\n", " ").trim_suffix("...")


## Kayıtlı komutu çalıştır (kısayol / fare hareketi / makro). Dönüş: çalıştı mı
func run_command(id: String) -> bool:
	if id.begins_with("tool:"):
		if mode != "sketch":
			return false
		editor.set_tool(id.substr(5))
		return true
	if _commands.has(id):
		var c: Dictionary = _commands[id]
		if str(c["ctx"]) == "sketch" and mode != "sketch":
			return false
		(c["cb"] as Callable).call()
		return true
	return false


func _toggle_grid() -> void:
	if mode != "sketch":
		return
	grid_btn.button_pressed = not grid_btn.button_pressed
	editor.set_grid_snap(grid_btn.button_pressed)


## Menü etiketlerine geçerli kısayolları yaz
func _refresh_shortcut_labels() -> void:
	for mi in _menu_items:
		var pm: PopupMenu = mi[0]
		var sc := keymap.shortcut_for(str(mi[2]))
		if int(mi[1]) < pm.item_count:
			pm.set_item_text(int(mi[1]), I18n.t(str(mi[3])) + (("        " + sc) if sc != "" else ""))


func _build_view_overlay() -> void:
	var o := viewport.overlay_top
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.94, 0.96, 0.92) if UiTheme.light else Color(0.16, 0.19, 0.24, 0.85)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", sb)
	o.add_child(pc)
	var h := HBoxContainer.new()
	pc.add_child(h)
	var items := [["fit", "fit", "Ekrana sığdır (F)"], ["normal", "normal", "Düzleme dik görünüm (Ctrl+8)"]]
	for it in items:
		var b := Button.new()
		b.icon = Icons.get_icon(it[1], 20)
		b.tooltip_text = it[2]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_cmd.bind(it[0]))
		h.add_child(b)
	var views := MenuButton.new()
	views.icon = Icons.get_icon("views", 20)
	views.tooltip_text = "Görünüm yönü"
	var vp := views.get_popup()
	var vlist := [["Ön", "front"], ["Arka", "back"], ["Sol", "left"], ["Sağ", "right"], ["Üst", "top"], ["Alt", "bottom"], ["İzometrik", "iso"]]
	for i in vlist.size():
		vp.add_item(vlist[i][0], i)
	vp.id_pressed.connect(func(id): _cmd("view_" + vlist[id][1]))
	h.add_child(views)
	persp_btn = Button.new()
	persp_btn.icon = Icons.get_icon("persp", 20)
	persp_btn.tooltip_text = "Perspektif"
	persp_btn.toggle_mode = true
	persp_btn.flat = true
	persp_btn.focus_mode = Control.FOCUS_NONE
	persp_btn.pressed.connect(_cmd.bind("persp"))
	h.add_child(persp_btn)
	for it in [["edges", "Kenarları göster"], ["planes", "Düzlemleri göster"]]:
		var b2 := Button.new()
		b2.icon = Icons.get_icon(it[0], 20)
		b2.tooltip_text = it[1]
		b2.flat = true
		b2.focus_mode = Control.FOCUS_NONE
		b2.pressed.connect(_cmd.bind(it[0]))
		h.add_child(b2)


# ================================================================ KOMUTLAR

const DW_KEEP_CMDS := ["undo", "redo", "save", "save_as", "new", "open", "delete", "fit", "rename", "help", "about", "quit", "export_all"]

func _cmd(c: String) -> void:
	if mode == "assembly" and asm_mode.handle_cmd(c):
		return
	if mode == "drawing" and _dw_in_asm and c in ["undo", "redo", "save", "save_as"]:
		asm_mode.handle_cmd(c)
		_dw_after_doc_change()
		return
	if mode == "drawing" and not (c in DW_KEEP_CMDS):
		_show_toolbar(0)
	match c:
		"new":
			_ask_discard(func(): _new_document())
		"open":
			_ask_discard(func(): _file_dialog(false, OPEN_FILTERS, I18n.t("Aç"), "open"))
		"new_asm":
			_ask_discard(_new_assembly)
		"sm_base", "sm_edge", "sm_flat", "sm_dxf", "weld", "weld_cutlist", "configs", "sm_hem", "fea", "draft_an", "cam", "render", \
				"srf_extrude", "srf_revolve", "srf_loft", "srf_planar", "srf_offset", "srf_knit", "srf_thicken", "srf_trim":
			special.cmd(c)
		"demo_asm":
			_ask_discard(func(): asm_mode.build_demo())
		"save":
			_save()
		"save_as":
			_file_dialog(true, [I18n.t("*.dcad ; DIY.CAD Parça")], I18n.t("Farklı Kaydet"), "save", doc.part_name + ".dcad")
		"export_all":
			_open_export_dialog()
		"export_stl":
			if viewport.model.is_empty():
				_set_status("Dışa aktarılacak katı model yok. Önce bir ekstrüzyon oluşturun.")
			else:
				_file_dialog(true, [I18n.t("*.stl ; STL (3B baskı)")], I18n.t("STL olarak dışa aktar"), "stl", doc.part_name + ".stl")
		"export_obj":
			if viewport.model.is_empty():
				_set_status("Dışa aktarılacak katı model yok.")
			else:
				_file_dialog(true, ["*.obj ; Wavefront OBJ"], I18n.t("OBJ olarak dışa aktar"), "obj", doc.part_name + ".obj")
		"export_step", "export_iges":
			if not viewport.kernel.is_brep() or not viewport.kernel.occ.is_ready():
				_set_status("STEP/IGES için OpenCASCADE çekirdeği gerekli (Araçlar → Geometri çekirdeği).")
			elif viewport.model.is_empty():
				_set_status("Dışa aktarılacak katı model yok.")
			elif c == "export_step":
				_file_dialog(true, ["*.step, *.stp ; STEP AP214"], I18n.t("STEP olarak dışa aktar"), "step", doc.part_name + ".step")
			else:
				_file_dialog(true, ["*.iges, *.igs ; IGES"], I18n.t("IGES olarak dışa aktar"), "iges", doc.part_name + ".igs")
		"import_step":
			if not viewport.kernel.is_brep():
				_file_dialog(false, [I18n.t("*.stl ; STL (CSG çekirdeği: yalnız STL)")], I18n.t("STL içe aktar"), "import")
			else:
				_file_dialog(false, ["*.step, *.stp, *.iges, *.igs, *.stl ; STEP / IGES / STL", "*.stl ; STL"], I18n.t("STEP / IGES / STL içe aktar"), "import")
		"fillet3d":
			_cmd_brep_feature("fillet")
		"chamfer3d":
			_cmd_brep_feature("chamfer")
		"shell":
			_cmd_brep_feature("shell")
		"draft", "combine", "move_body", "split", "hole", "dome":
			_cmd_brep_feature(c)
		"sweep", "sweepcut":
			_cmd_feature("sweep", c == "sweepcut")
		"loft", "loftcut":
			_cmd_feature("loft", c == "loftcut")
		"refplane", "refaxis", "refpoint", "helix", "refcsys":
			_cmd_ref(c)
		"lpattern", "cpattern", "mirror", "tpattern", "cvpattern":
			_cmd_pattern(c)
		"projcurve", "wrap", "emboss":
			_cmd_feature(c, false)
		"rib":
			_cmd_feature("rib", false)
		"kernel_options":
			_enter_aux_mode("kernel")
		"options":
			show_options()
		"macro_run":
			file_dialog.current_dir = AppSettings.app_dir("macros")
			_file_dialog(false, ["*.gd ; DIY.CAD makrosu (GDScript)"], I18n.t("Makro çalıştır"), "macro_run")
		"macro_record":
			if macro.recording:
				_macro_src = macro.stop_recording()
				if _macro_src == "":
					_set_status("Makro kaydı durdu: kayıt süresince özellik eklenmedi.")
				else:
					_file_dialog(true, ["*.gd ; DIY.CAD makrosu (GDScript)"], "Kaydedilen makroyu sakla", "macro_save", "kayit.gd")
			else:
				macro.start_recording()
				_set_status("● Makro kaydı başladı: eklediğiniz özellikler kaydedilir. Durdurmak için Araçlar → Makro kaydı.")
		"macro_export":
			if doc.features.is_empty():
				_set_status("Parça boş.")
			else:
				_macro_src = macro.part_macro()
				_file_dialog(true, ["*.gd ; DIY.CAD makrosu (GDScript)"], I18n.t("Parçayı makro olarak kaydet"), "macro_save", doc.part_name + ".gd")
		"export_dxf", "export_svg":
			var sk := _sketch_for_export()
			if sk == null:
				_set_status("Önce dışa aktarılacak taslağı seçin (ağaçtan veya taslak modunda).")
			elif c == "export_dxf":
				_file_dialog(true, ["*.dxf ; DXF (R12)"], I18n.t("Taslağı DXF olarak dışa aktar"), "dxf", sk.name + ".dxf")
			else:
				_file_dialog(true, ["*.svg ; SVG"], I18n.t("Taslağı SVG olarak dışa aktar"), "svg", sk.name + ".svg")
		"export_png":
			_file_dialog(true, ["*.png ; PNG resmi"], I18n.t("Ekran görüntüsü"), "png", doc.part_name + ".png")
		"demo":
			_ask_discard(func(): _load_demo())
		"demo2":
			_ask_discard(func(): _load_demo(true))
		"quit":
			_request_quit()
		"undo":
			_undo_redo(true)
		"redo":
			_undo_redo(false)
		"delete":
			_delete()
		"rename":
			tree.begin_rename()
		"fit":
			if mode == "drawing":
				drawing_canvas.fit()
			else:
				_fit(true)
		"normal":
			_normal_to()
		"persp":
			viewport.camera.toggle_perspective()
			persp_btn.button_pressed = viewport.camera.perspective
			_set_view_check("persp", viewport.camera.perspective)
		"edges":
			viewport.set_edges_visible(not viewport.show_edges)
			_set_view_check("edges", viewport.show_edges)
		"planes":
			viewport.set_planes_visible(not viewport.show_planes)
			_set_view_check("planes", viewport.show_planes)
		"sketch":
			_cmd_sketch()
		"exit_sketch":
			_exit_sketch()
		"extrude":
			_cmd_feature("extrude", false)
		"cut":
			_cmd_feature("extrude", true)
		"revolve":
			_cmd_feature("revolve", false)
		"revcut":
			_cmd_feature("revolve", true)
		"toggle_construction":
			if mode == "sketch" and not editor.selected_entities.is_empty():
				var ids: Array = editor.selected_entities.keys()
				var e := editor.sketch().get_entity(ids[0])
				editor.edit_construction(ids, not bool(e.get("construction", false)))
		"tool_dimension":
			if mode == "sketch":
				editor.set_tool("dimension")
			else:
				_set_status("Akıllı Boyut taslak içinde kullanılır. Önce bir taslak açın.")
		"add_relation":
			if mode != "sketch":
				_set_status("İlişkiler taslak içinde eklenir. Önce bir taslak açın.")
			elif editor.available_relations().is_empty():
				editor.set_tool("select")
				_set_status("İlişki eklemek için öğeleri seçin (Shift/Ctrl ile çoklu seçim); uygun ilişkiler soldaki panelde listelenir.")
			else:
				_set_status("Seçime uygun ilişkiler soldaki panelde listelendi.")
		"equations":
			_enter_aux_mode("equations")
		"sketch3d":
			_cmd_sketch3d()
		"op_offset", "op_transform":
			if mode != "sketch":
				_set_status("Bu işlem taslak içinde kullanılır. Önce bir taslak açın.")
			elif editor.selected_entities.is_empty():
				editor.set_tool("select")
				_set_status("Önce öğeleri seçin (Shift/Ctrl ile çoklu seçim), sonra tekrar tıklayın.")
			else:
				_sketch_op = "offset" if c == "op_offset" else "transform"
				if _sketch_op == "offset":
					editor.set_offset_preview(_offset_value())
				_refresh_panel()
		"op_mirror":
			if mode != "sketch":
				_set_status("Aynalama taslak içinde kullanılır.")
			else:
				editor.mirror_selection()
		"op_block":
			if mode != "sketch":
				_set_status("Bloklar taslak içinde oluşturulur.")
			else:
				editor.make_block_selection()
		"measure":
			_enter_aux_mode("measure")
		"mass":
			_enter_aux_mode("mass")
		"material":
			_enter_aux_mode("material")
		"doc_props":
			_show_doc_props()
		"help":
			_show_help()
		"roadmap":
			OS.shell_open(ProjectSettings.globalize_path("res://ROADMAP.md"))
		"about":
			var kinfo := viewport.kernel.backend_label()
			if viewport.kernel.occ.is_ready():
				kinfo += " (OCP %s)" % viewport.kernel.occ.version
			info_dialog.dialog_text = I18n.t("%s %s\nGodot %s ile yazılmış parametrik CAD.\n\nGeometri çekirdeği: %s\nYedek çekirdek: Godot CSG (Manifold).") % [APP_NAME, APP_VERSION, Engine.get_version_info()["string"], kinfo]
			info_dialog.popup_centered()
		_:
			if c.begins_with("view_"):
				var vname := c.substr(5)
				viewport.camera.set_standard_view(vname)


func _set_view_check(cmd: String, v: bool) -> void:
	var order := ["fit", "", "view_front", "view_back", "view_left", "view_right", "view_top", "view_bottom", "view_iso", "normal", "", "persp", "edges", "planes"]
	var idx := order.find(cmd)
	if idx >= 0:
		view_menu.set_item_checked(view_menu.get_item_index(idx), v)


func _set_status(t: String) -> void:
	status_label.text = t


func _update_title() -> void:
	if mode == "assembly":
		asm_mode.update_title()
		return
	var t := doc.part_name + (" *" if doc.dirty else "") + " — " + APP_NAME
	get_window().title = t


# ================================================================ BELGE OLAYLARI

func _on_doc_changed() -> void:
	# Denklemler: değişkenleri ve denklemli boyutları güncelle, etkilenen taslakları çöz
	if not doc.variables.is_empty() or _has_expressions():
		var eq := Equations.apply(doc)
		if not (eq["errors"] as Array).is_empty():
			_set_status(I18n.t("Denklem uyarısı: ") + str(eq["errors"][0]))
	_update_title()
	units_btn.text = " " + Units.system_short() + " "
	viewport.model_mat.albedo_color = Materials.color_of(doc.material)
	if mode == "sketch":
		if editor.refresh_feature():
			_update_tree()
			_draw_sketches()
			_refresh_panel()
			return
		editor.end()
		mode = "idle"
		_show_toolbar(0)
	if mode == "sketch3d":
		if editor3d.refresh():
			_update_tree()
			_refresh_panel()
			return
		editor3d.end()
		mode = "idle"
	if mode == "feature":
		# Özellik düzenlenirken belge değiştiyse (ör. geri al) düzenlemeyi iptal et
		editing = null
		mode = "idle"
		_region_pick = false
		viewport.set_edge_highlight([])
		viewport.clear_face_highlight()
	if mode == "drawing":
		_dw_after_doc_change()
	def_label.text = ""
	RefGeom.update(doc)
	viewport.kernel.rebuild(doc)
	_validate_selection()
	_update_tree()
	_draw_sketches()
	_apply_selection_visuals()
	_refresh_panel()


## Özellik parametresine denklem bağlar (önizleme özelliği üzerinde; Tamam ile kaydedilir).
func _set_feature_expr(f: CadFeature, key: String, ex: String) -> void:
	var ctx: Dictionary = Equations.variable_values(doc)["ctx"]
	var r = Equations.evaluate(ex, ctx)
	if r == null:
		_set_status(I18n.t("Denklem hesaplanamadı: '%s'") % ex)
		return
	f.params[key + "_expr"] = ex
	f.params[key] = Units.from_display(r) if key == "depth" else clampf(r, 0.1, 360.0)
	_preview()
	_show_feature_panel()
	_set_status(I18n.t("Denklem bağlandı: D1 = ") + ex)


func _toggle_region_pick() -> void:
	_region_pick = not _region_pick
	if _region_pick:
		_set_status("Bölge seç: profil taslağında kullanılacak kapalı alanlara tıklayın (tekrar tıklamak kaldırır).")
	_show_feature_panel()
	_update_region_highlight()


func _clear_regions() -> void:
	if editing:
		editing.params.erase("regions")
		_preview()
		_show_feature_panel()
		_update_region_highlight()


## Özellik paneli açıkken taslak düzleminde tıklanan bölgeyi seç/bırak.
func _pick_region(screen: Vector2) -> void:
	if editing == null:
		return
	var sk_f := doc.get_feature(editing.sketch_ref())
	if sk_f == null:
		return
	var r := viewport.ray(screen)
	var hit = sk_f.plane.intersect_ray(r[0], r[1])
	if hit == null:
		return
	var p := sk_f.plane.to_local(hit)
	var fs := SketchRegions.faces(sk_f.sketch)
	var fi := SketchRegions.face_at(fs, p)
	if fi < 0:
		_set_status("Burada kapalı bir bölge yok.")
		return
	var regs: Array = editing.params.get("regions", []).duplicate()
	var removed := false
	for i in range(regs.size() - 1, -1, -1):
		var s = regs[i]
		if SketchRegions.face_at(fs, Vector2(float(s[0]), float(s[1]))) == fi:
			regs.remove_at(i)
			removed = true
	if not removed:
		var smp: Vector2 = fs[fi]["sample"]
		regs.append([smp.x, smp.y])
	editing.params["regions"] = regs
	if regs.is_empty():
		editing.params.erase("regions")
	_preview()
	_show_feature_panel()
	_update_region_highlight()


func _update_region_highlight() -> void:
	if mode != "feature" or editing == null:
		return
	var regs: Array = editing.params.get("regions", [])
	var sk_f := doc.get_feature(editing.sketch_ref())
	var tris := PackedVector3Array()
	if sk_f and not regs.is_empty():
		var fs := SketchRegions.faces(sk_f.sketch)
		for s in regs:
			var fi := SketchRegions.face_at(fs, Vector2(float(s[0]), float(s[1])))
			if fi < 0:
				continue
			var face: Dictionary = fs[fi]
			# Delikli bölge: dış - delikler (Clipper ile) sonra üçgenle
			var parts: Array = [face["outer"]]
			for h in face["holes"]:
				var nparts: Array = []
				for pp in parts:
					nparts.append_array(Geometry2D.clip_polygons(pp, h))
				parts = nparts
			for pp in parts:
				var poly: PackedVector2Array = pp
				if Geometry2D.is_polygon_clockwise(poly):
					continue
				var idx := Geometry2D.triangulate_polygon(poly)
				for k in idx:
					tris.append(sk_f.plane.to_world(poly[k]))
	viewport.set_face_highlight(tris)


func _has_expressions() -> bool:
	for f in doc.features:
		if f.is_sketch():
			for c in f.sketch.constraints:
				if str(c.get("expr", "")) != "":
					return true
		elif str(f.params.get("depth_expr", "")) != "" or str(f.params.get("angle_expr", "")) != "":
			return true
	return false


func _on_built(mesh: ArrayMesh) -> void:
	viewport.set_model_mesh(mesh, viewport.kernel.brep)
	if viewport.kernel.occ.plane_moved:
		viewport.kernel.occ.plane_moved = false
		_draw_sketches()
	if selection.get("kind", "") == "face":
		selection = {}
		_apply_selection_visuals()
	if _fit_after_build:
		_fit_after_build = false
		_fit(false)
	if mode == "drawing":
		_dw_request_hlr()
	if mode in ["fea", "draft_an", "cam"]:
		special.on_built()
	if mode == "feature" and editing and editing.is_brep_feature():
		_show_brep_feature_panel()
		_update_brep_highlight()
	elif mode == "feature" and _error_label != null and is_instance_valid(_error_label) and editing:
		_error_label.text = ("Hata: " + editing.error) if editing.error != "" else ""
	elif mode == "idle" or mode == "mass" or mode == "measure":
		if mode == "mass":
			_compute_mass()
		if mode == "measure":
			_measure_picks.clear()
			_update_measure_visuals()
		_refresh_panel()
		_update_tree()
	_built_once = true


func _validate_selection() -> void:
	if selection.get("kind", "") == "feature" and doc.get_feature(int(selection["id"])) == null:
		selection = {}


func _update_tree() -> void:
	if mode == "assembly":
		asm_mode.rebuild_tree()
		return
	_syncing_tree = true
	tree.rebuild(doc, selection)
	_syncing_tree = false


func _draw_sketches() -> void:
	var lb := LineBuilder.new()
	var w := viewport.camera.world_per_pixel()
	for f in doc.sketches():
		if f.suppressed:
			continue
		if mode == "sketch" and editor.feature and f.id == editor.feature.id:
			continue
		var consumed := not doc.consumers_of(f.id).is_empty()
		var sel: bool = selection.get("kind", "") == "feature" and selection.get("id", -1) == f.id
		if mode == "feature" and editing and editing.sketch_ref() == f.id:
			sel = true
		if consumed and not sel:
			continue
		var col := Color(0.1, 0.45, 1.0) if sel else Color(0.22, 0.27, 0.4)
		SketchEditor.draw_sketch(lb, f, w, col, col.lightened(0.35))
	# 3B taslaklar
	for f in doc.features:
		if f.type != "sketch3d" or f.suppressed or f.sketch3d == null:
			continue
		if mode == "sketch3d" and editor3d.feature and f.id == editor3d.feature.id:
			continue
		var sel3: bool = selection.get("kind", "") == "feature" and selection.get("id", -1) == f.id
		Sketch3DEditor.draw_lines(lb, f.sketch3d, Color(0.1, 0.45, 1.0) if sel3 else Color(0.35, 0.3, 0.55))
	_draw_reference(lb)
	lb.commit(viewport.sketches_mi.mesh)


func _on_view_changed() -> void:
	if mode == "sketch":
		editor.redraw()
	elif mode == "sketch3d":
		editor3d.redraw()
	elif mode == "mass":
		_draw_mass_marker()
	elif mode == "measure":
		_update_measure_visuals()
	_draw_sketches()


# ================================================================ SEÇİM

func _on_pointer(ev: InputEvent) -> void:
	if mode == "assembly":
		asm_mode.on_pointer(ev)
		return
	if mode == "sketch":
		editor.on_pointer(ev)
		return
	if mode == "sketch3d":
		editor3d.on_pointer(ev)
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mode == "measure":
			_measure_pick(mb.position, mb.shift_pressed or mb.ctrl_pressed)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mode == "feature" and _pick_target != "":
			_pick_for_target(mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mode == "feature" and _region_pick:
			_pick_region(mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mode == "feature" and editing and editing.is_brep_feature():
			_pick_brep(mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mode == "idle":
			_pick_at(mb.position, mb.double_click)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and (mode == "fea" or mode == "render"):
			special.aux_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
			if mode == "idle" and not selection.is_empty():
				_show_context(selection, viewport.get_global_transform() * mb.position)
	elif ev is InputEventMouseMotion:
		if mode == "feature" and editing and editing.type in ["fillet", "chamfer"] and not _brep_show_result:
			var he := viewport.pick_edge((ev as InputEventMouseMotion).position)
			var hid: int = int(he["edge"]) if not he.is_empty() else -1
			if hid != _hover_edge:
				_hover_edge = hid
				_update_brep_highlight()
		var r := viewport.ray((ev as InputEventMouseMotion).position)
		var hit := viewport.model.raycast(r[0], r[1]) if viewport.model.tri_count() < 60000 else {}
		if not hit.is_empty():
			var p: Vector3 = hit["point"]
			coord_label.text = "X %s  Y %s  Z %s %s" % [Units.format_length(p.x, false), Units.format_length(p.y, false), Units.format_length(p.z, false), Units.length_unit]
		else:
			coord_label.text = ""


func _pick_at(pos: Vector2, dbl: bool) -> void:
	var ref_id := _pick_reference(pos)
	if ref_id >= 0:
		_select({"kind": "feature", "id": ref_id})
		if dbl:
			_activate_feature(ref_id)
		return
	var r := viewport.ray(pos)
	var from: Vector3 = r[0]
	var dir: Vector3 = r[1]
	var best := {}
	var best_d := INF
	var hit := viewport.model.raycast(from, dir)
	if not hit.is_empty():
		var fd := viewport.model.planar_face(int(hit["tri"]))
		best = {"kind": "face", "tris": fd["tris"], "planar": fd["planar"], "normal": fd["normal"], "point": fd["point"],
			"face": int(fd.get("face", -1)), "hit": hit["point"]}
		best_d = float(hit["dist"])
	# Montaj bağlamı: diğer bileşenlerin yüzleri (parça koordinatlarında)
	if asm_mode != null and asm_mode.context_active():
		var ch := asm_mode.context_pick(from, dir)
		if not ch.is_empty() and float(ch["dist"]) < best_d:
			best = {"kind": "face", "tris": PackedInt32Array(), "planar": ch["planar"], "normal": ch["normal"], "point": ch["point"],
				"face": -1, "hit": ch["point"], "ctx_pts": ch["pts"]}
			best_d = float(ch["dist"])
	# Görünür taslaklar
	var w := viewport.camera.world_per_pixel()
	for f in doc.sketches():
		if f.suppressed or not doc.consumers_of(f.id).is_empty():
			continue
		var h = f.plane.intersect_ray(from, dir)
		if h == null:
			continue
		var d: float = (h - from).dot(dir)
		if f.sketch.hit_entity(f.plane.to_local(h), 6.0 * w) >= 0 and d <= best_d + viewport.camera.depth_bias() * 2.0:
			best = {"kind": "feature", "id": f.id}
			best_d = d
	if best.is_empty() or best["kind"] != "feature":
		var ph := viewport.pick_plane(from, dir)
		if not ph.is_empty() and float(ph["dist"]) < best_d:
			best = {"kind": "plane", "id": ph["id"]}
	_select(best)
	if _pick_for_sketch and not best.is_empty():
		_pick_for_sketch = false
		viewport.force_planes = false
		_cmd_sketch()
		return
	if dbl and best.get("kind", "") == "feature":
		_activate_feature(int(best["id"]))


func _select(sel: Dictionary) -> void:
	selection = sel
	_apply_selection_visuals()
	_update_tree()
	_refresh_panel()
	match sel.get("kind", ""):
		"face":
			if sel["planar"]:
				_set_status("Düzlemsel yüz seçildi. 'Taslak' ile bu yüzeye çizebilirsiniz.")
			else:
				_set_status("Eğri yüzey seçildi (üzerine taslak çizilemez).")
		"plane":
			_set_status(I18n.t("%s seçildi. 'Taslak' ile çizime başlayın.") % I18n.t(SketchPlane.standard(sel["id"]).name))
		"feature":
			var f := doc.get_feature(int(sel["id"]))
			if f:
				_set_status(I18n.t("%s seçildi (%s). Çift tık: düzenle.") % [f.name, I18n.t(f.type_label())])
		_:
			_set_status("")


func _apply_selection_visuals() -> void:
	var kind: String = selection.get("kind", "")
	viewport.selected_plane = selection["id"] if kind == "plane" else ""
	viewport.draw_planes()
	if kind == "face" and selection.has("ctx_pts"):
		viewport.set_face_highlight(selection["ctx_pts"])
	elif kind == "face":
		viewport.set_face_highlight(viewport.model.face_triangles(selection["tris"]))
	else:
		viewport.clear_face_highlight()
	_draw_sketches()


func _on_tree_picked(meta: Dictionary) -> void:
	if _syncing_tree:
		return
	if mode == "assembly":
		asm_mode.on_tree_picked(meta)
		return
	if mode == "sketch" or mode == "feature":
		# Özellik paneli açıkken ağaçtan taslak seçmek = profil taslağını değiştir
		if mode == "feature" and editing and meta.get("kind", "") == "feature":
			var f := doc.get_feature(int(meta["id"]))
			if f and f.is_sketch():
				editing.params["sketch"] = f.id
				_show_feature_panel()
				_preview()
		return
	if _is_aux_mode() and mode != "material":
		_leave_aux_mode()
	var k: String = meta.get("kind", "")
	if k == "plane" or k == "feature":
		selection = meta
	else:
		selection = {}
	_apply_selection_visuals()
	_refresh_panel()


func _on_tree_activated(meta: Dictionary) -> void:
	if mode == "assembly":
		asm_mode.on_tree_activated(meta)
		return
	if meta.get("kind", "") == "material" and (mode == "idle" or _is_aux_mode()):
		_cmd("material")
	elif meta.get("kind", "") == "feature" and mode == "idle":
		_activate_feature(int(meta["id"]))


func _activate_feature(id: int) -> void:
	var f := doc.get_feature(id)
	if f == null:
		return
	if f.type == "sketch3d":
		_edit_sketch3d(f)
	elif f.is_sketch():
		_edit_sketch(f)
	else:
		_edit_feature(f)


func _on_tree_context(meta: Dictionary, at: Vector2) -> void:
	if mode == "assembly":
		return
	if mode != "idle" and not (_is_aux_mode() and meta.get("kind", "") == "material"):
		return
	var k: String = meta.get("kind", "")
	if k == "plane" or k == "feature":
		selection = meta
		_apply_selection_visuals()
		_refresh_panel()
	_show_context(meta, at)


func _show_context(meta: Dictionary, at: Vector2) -> void:
	_context_meta = meta
	context_menu.clear()
	var k: String = meta.get("kind", "")
	if k == "plane":
		context_menu.add_item("Taslak çiz", 8)
	elif k == "material":
		context_menu.add_item("Malzemeyi düzenle...", 10)
		if doc.material != "":
			context_menu.add_item("Malzemeyi kaldır", 11)
	elif k == "face":
		if meta.get("planar", false):
			context_menu.add_item("Bu yüzeye taslak çiz", 8)
		else:
			return
	elif k == "feature":
		var f := doc.get_feature(int(meta["id"]))
		if f == null:
			return
		if f.is_sketch():
			context_menu.add_item("Taslağı düzenle", 2)
			context_menu.add_item("Ekstrüzyon uygula", 9)
			context_menu.add_item("DXF olarak dışa aktar", 6)
			context_menu.add_item("SVG olarak dışa aktar", 7)
		else:
			context_menu.add_item("Özelliği düzenle", 1)
			context_menu.add_item("Taslağı düzenle", 2)
			context_menu.add_item("Bastırmayı kaldır" if f.suppressed else I18n.t("Bastır (suppress)"), 3)
		context_menu.add_separator()
		context_menu.add_item("Yukarı taşı", 20)
		context_menu.add_item("Aşağı taşı", 21)
		context_menu.add_item("Geri alma çubuğunu bunun altına taşı", 22)
		if doc.rollback >= 0:
			context_menu.add_item("Geri almayı kaldır (tümünü hesapla)", 23)
		context_menu.add_item("Ebeveyn / Çocuk...", 24)
		context_menu.add_separator()
		context_menu.add_item("Yeniden adlandır", 4)
		context_menu.add_item("Sil", 5)
	elif k == "rollback":
		context_menu.add_item("Geri almayı kaldır (tümünü hesapla)", 23)
	else:
		return
	context_menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _on_context_id(id: int) -> void:
	var meta := _context_meta
	var f: CadFeature = null
	if meta.get("kind", "") == "feature":
		f = doc.get_feature(int(meta["id"]))
	match id:
		1:
			if f:
				_edit_feature(f)
		2:
			if f:
				var sk := f if f.is_sketch() else doc.get_feature(f.sketch_ref())
				if sk:
					_edit_sketch(sk)
		3:
			if f:
				doc.checkpoint()
				f.suppressed = not f.suppressed
				doc.commit()
		4:
			tree.begin_rename()
		5:
			_delete()
		6:
			_cmd("export_dxf")
		7:
			_cmd("export_svg")
		8:
			selection = meta
			_cmd_sketch()
		9:
			_cmd("extrude")
		10:
			_cmd("material")
		11:
			_set_material("")
		20, 21:
			if f:
				_move_feature(f.id, doc.index_of(f.id) + (-1 if id == 20 else 1))
		22:
			if f:
				_set_rollback(doc.index_of(f.id) + 1)
		23:
			_set_rollback(-1)
		24:
			if f:
				_show_parents(f)


func _on_renamed(id: int, new_name: String) -> void:
	var f := doc.get_feature(id)
	if f == null or new_name == "" or new_name == f.name:
		_update_tree()
		return
	doc.checkpoint()
	f.name = new_name
	doc.commit()


func _delete() -> void:
	if mode == "assembly":
		asm_mode.delete_selected()
		return
	if mode == "drawing":
		_dw_delete()
		return
	if mode == "sketch":
		editor.delete_selection()
		return
	if mode == "sketch3d":
		editor3d.delete_selection()
		return
	if mode != "idle":
		return
	if selection.get("kind", "") == "feature":
		var f := doc.get_feature(int(selection["id"]))
		if f == null:
			return
		var extra := ""
		if f.is_sketch() and not doc.consumers_of(f.id).is_empty():
			extra = I18n.t(" (ve onu kullanan özellikler)")
		doc.checkpoint()
		doc.remove_feature(f.id)
		selection = {}
		doc.commit()
		_set_status(f.name + extra + I18n.t(" silindi. Geri almak için Ctrl+Z."))


func _undo_redo(undo: bool) -> void:
	if mode == "feature":
		_cancel_feature()
	var ok := doc.undo() if undo else doc.redo()
	if not ok:
		_set_status(I18n.t("Geri alınacak işlem yok.") if undo else I18n.t("Yinelenecek işlem yok."))


# ================================================================ 3B TASLAK

func _cmd_sketch3d() -> void:
	if mode == "sketch3d":
		_exit_sketch3d()
		return
	if mode == "sketch":
		_exit_sketch()
	if mode == "feature":
		_cancel_feature()
	_leave_aux_mode()
	doc.checkpoint()
	var f := doc.new_feature("sketch3d", "3B Taslak")
	f.sketch3d = Sketch3D.new()
	doc.add_feature(f)
	_sketch3d_new = true
	mode = "sketch3d"
	selection = {}
	editor3d.begin(f)
	doc.commit()
	_set_status("3B Taslak: noktaları tıklayın. Tab ile çizim düzlemini (XY / XZ / YZ) değiştirin; eksene yakın çizgiler X/Y/Z'ye kilitlenir.")


func _edit_sketch3d(f: CadFeature) -> void:
	if mode == "sketch":
		_exit_sketch()
	if mode == "feature":
		_cancel_feature()
	_leave_aux_mode()
	_sketch3d_new = false
	mode = "sketch3d"
	selection = {}
	editor3d.begin(f)
	_apply_selection_visuals()
	_update_tree()
	_refresh_panel()


func _exit_sketch3d() -> void:
	if mode != "sketch3d":
		return
	var f := editor3d.feature
	editor3d.end()
	mode = "idle"
	coord_label.text = ""
	if f and f.sketch3d.is_empty() and _sketch3d_new:
		doc.remove_feature(f.id)
		selection = {}
		doc.commit()
		_set_status("Boş 3B taslak kaldırıldı.")
		return
	if f:
		selection = {"kind": "feature", "id": f.id}
		_set_status(I18n.t("%s: %d çizgi, toplam uzunluk %s.") % [f.name, f.sketch3d.lines.size(), Units.format_length(f.sketch3d.total_length())])
	_on_doc_changed()


func _show_sketch3d_panel() -> void:
	panel.clear()
	var f := editor3d.feature
	if f == null:
		return
	panel.title(f.name, Icons.get_icon("sketch3d", 22))
	panel.button("3B taslaktan çık", _exit_sketch3d, Icons.get_icon("exit_sketch", 18))
	panel.section("Araç")
	var tools := ["line", "select"]
	var on_tool := func(i: int) -> void:
		editor3d.set_tool(tools[i])
	panel.option("Araç", ["Çizgi", "Seç"], tools.find(editor3d.tool), on_tool)
	var on_plane := func(i: int) -> void:
		editor3d.set_plane(Sketch3DEditor.PLANES[i])
		_refresh_panel()
	panel.option("Düzlem (Tab)", ["XY (Ön)", "XZ (Üst)", "YZ (Sağ)"], Sketch3DEditor.PLANES.find(editor3d.plane_name), on_plane)
	var s := f.sketch3d
	var pid := editor3d.selected_point
	if pid >= 0 and s.points.has(pid):
		var p: Vector3 = s.points[pid]
		panel.section("Nokta")
		panel.number("X", p.x, func(v): editor3d.edit_point(pid, Vector3(v, p.y, p.z)))
		panel.number("Y", p.y, func(v): editor3d.edit_point(pid, Vector3(p.x, v, p.z)))
		panel.number("Z", p.z, func(v): editor3d.edit_point(pid, Vector3(p.x, p.y, v)))
		panel.button("Sil", func(): editor3d.delete_selection(), Icons.get_icon("delete", 18))
	elif editor3d.selected_line >= 0:
		var l: Array = s.lines[editor3d.selected_line]
		panel.section("Çizgi")
		panel.info(I18n.t("Uzunluk: ") + Units.format_length((s.points[l[0]] as Vector3).distance_to(s.points[l[1]])))
		panel.button("Sil", func(): editor3d.delete_selection(), Icons.get_icon("delete", 18))
	panel.section("Bilgi")
	panel.info(I18n.t("Çizgi: %d   Nokta: %d\nToplam uzunluk: %s") % [s.lines.size(), s.points.size(), Units.format_length(s.total_length())])
	panel.info("3B taslak, Faz 5'teki süpürme (sweep) özelliği için yol olarak kullanılacak.", Color(0.6, 0.65, 0.7))


# ================================================================ TASLAK

func _cmd_sketch() -> void:
	if mode == "sketch":
		_exit_sketch()
		return
	_exit_sketch3d()
	if mode == "feature":
		_cancel_feature()
	_leave_aux_mode()
	var k: String = selection.get("kind", "")
	if k == "plane":
		_start_sketch_on(SketchPlane.standard(selection["id"]))
	elif k == "face":
		if not selection.get("planar", false):
			_set_status("Seçili yüz düzlemsel değil. Düzlemsel bir yüz veya ana düzlem seçin.")
			return
		var n: Vector3 = selection["normal"]
		var pl := SketchPlane.from_face(selection["point"], n, "Yüzey")
		var sfid := int(selection.get("face", -1))
		if viewport.model.has_brep() and sfid >= 0 and sfid < viewport.model.brep_faces.size():
			# B-rep: taslak, destek yüzüne adıyla bağlanır; model değişince düzlem yüzle birlikte kayar
			var p0: Vector3 = selection["point"]
			pl.support = {"name": str(viewport.model.brep_faces[sfid].get("name", "")), "p": _arr3(p0), "n": _arr3(n)}
		_start_sketch_on(pl)
	elif k == "feature" and doc.get_feature(int(selection["id"])) and doc.get_feature(int(selection["id"])).type == "refplane":
		var rf := doc.get_feature(int(selection["id"]))
		if rf.plane == null:
			_set_status("Referans düzlem geçersiz.")
			return
		var rpl := rf.plane.clone()
		rpl.name = rf.name
		rpl.ref = rf.id
		_start_sketch_on(rpl)
	elif k == "feature" and doc.get_feature(int(selection["id"])) and doc.get_feature(int(selection["id"])).is_sketch():
		_edit_sketch(doc.get_feature(int(selection["id"])))
	else:
		_pick_for_sketch = true
		viewport.force_planes = true
		viewport.draw_planes()
		_set_status("Taslak için bir düzlem (Ön / Üst / Sağ) veya modelin düzlemsel bir yüzünü tıklayın.")


func _start_sketch_on(pl: SketchPlane) -> void:
	doc.checkpoint()
	var f := doc.new_feature("sketch", "Taslak")
	f.plane = pl
	f.sketch = Sketch.new()
	doc.add_feature(f)
	_sketch_was_new = true
	_enter_sketch(f)
	doc.commit()
	editor.set_tool("line")


func _edit_sketch(f: CadFeature) -> void:
	_exit_sketch3d()
	if mode == "feature":
		_cancel_feature()
	_leave_aux_mode()
	_sketch_was_new = false
	_enter_sketch(f)
	_refresh_panel()


func _enter_sketch(f: CadFeature) -> void:
	mode = "sketch"
	selection = {}
	_pick_for_sketch = false
	viewport.force_planes = false
	editor.begin(f)
	editor.set_grid_snap(grid_btn.button_pressed)
	editor.set_show_relations(rel_btn.button_pressed)
	_show_toolbar(1)
	_apply_selection_visuals()
	_update_tree()


func _exit_sketch() -> void:
	if mode != "sketch":
		return
	_sketch_op = ""
	var f := editor.feature
	editor.end()
	mode = "idle"
	_show_toolbar(0)
	coord_label.text = ""
	def_label.text = ""
	if f and f.sketch.is_empty() and _sketch_was_new:
		doc.remove_feature(f.id)
		selection = {}
		doc.commit()
		_set_status("Boş taslak kaldırıldı.")
		return
	if f:
		selection = {"kind": "feature", "id": f.id}
		var prof := f.sketch.extract_profiles()
		var n_loops: int = (prof["loops"] as Array).size()
		if n_loops > 0:
			_set_status(I18n.t("%s: %d kapalı kontur. Ekstrüzyon veya Döndürme uygulayabilirsiniz.") % [f.name, n_loops])
		else:
			_set_status(I18n.t("%s: kapalı kontur yok — katı oluşturmak için konturu kapatın.") % f.name)
	_on_doc_changed()


func _show_toolbar(i: int) -> void:
	tabs.current_tab = i
	_on_tab_changed(i)


func _on_tab_changed(i: int) -> void:
	toolbar_features.visible = i == 0
	toolbar_sketch.visible = i == 1
	toolbar_eval.visible = i == 2
	toolbar_drawing.visible = i == 3
	asm_mode.toolbar.visible = i == 4
	special.toolbar_sm.visible = i == 5
	special.toolbar_weld.visible = i == 6
	special.toolbar_srf.visible = i == 7
	special.toolbar_an.visible = i == 8
	toolbar_plugins.visible = i == 9
	if i == 4:
		if mode == "drawing" and _dw_in_asm:
			_exit_drawing()
			asm_mode.enter()
		elif mode != "assembly" and asm_mode.is_open():
			_return_to_assembly()
		return
	if i == 3:
		if mode != "drawing":
			_enter_drawing()
	elif mode == "drawing" or drawing_canvas.visible:
		_exit_drawing()


func _on_definition_changed(info: Dictionary) -> void:
	if mode != "sketch" or editor.sketch().is_empty():
		def_label.text = ""
		return
	match str(info.get("status", "")):
		"full":
			def_label.text = "Tam Tanımlı"
			def_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
		"over":
			def_label.text = "Aşırı Tanımlı"
			def_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
		_:
			def_label.text = I18n.t("Eksik Tanımlı (%d)") % int(info.get("dof", 0))
			def_label.add_theme_color_override("font_color", Color(0.45, 0.65, 1.0))
	def_label.tooltip_text = I18n.t("Serbestlik derecesi: %d") % int(info.get("dof", 0))


func _on_tool_button(t: String) -> void:
	if mode != "sketch":
		_set_status("Taslak araçları için önce bir taslak açın (Özellikler > Taslak).")
		tool_buttons[t].button_pressed = false
		return
	editor.set_tool(t)


func _on_tool_changed(t: String) -> void:
	for k in tool_buttons:
		tool_buttons[k].button_pressed = (k == t)
	_refresh_panel()


func _on_cursor_moved(l: Vector2) -> void:
	coord_label.text = "x %s   y %s %s" % [Units.format_length(l.x, false), Units.format_length(l.y, false), Units.length_unit]


func _sketch_for_export() -> CadFeature:
	if mode == "sketch":
		return editor.feature
	if selection.get("kind", "") == "feature":
		var f := doc.get_feature(int(selection["id"]))
		if f:
			return f if f.is_sketch() else doc.get_feature(f.sketch_ref())
	return null


# ================================================================ ÖZELLİKLER (Ekstrüzyon / Döndürme)

func _resolve_sketch() -> CadFeature:
	if mode == "sketch":
		var id := editor.feature.id
		_exit_sketch()
		return doc.get_feature(id)
	if selection.get("kind", "") == "feature":
		var f := doc.get_feature(int(selection["id"]))
		if f and f.is_sketch():
			return f
	for i in range(doc.features.size() - 1, -1, -1):
		var f2: CadFeature = doc.features[i]
		if f2.is_sketch() and not f2.suppressed and doc.consumers_of(f2.id).is_empty():
			return f2
	return null


func _default_axis(sk_f: CadFeature) -> Variant:
	for e in sk_f.sketch.entities:
		if e["type"] == "line" and e.get("construction", false):
			return e["id"]
	return "y"


func _cmd_feature(type: String, cut: bool) -> void:
	_exit_sketch3d()
	if mode == "feature":
		_cancel_feature()
	_leave_aux_mode()
	var sk_f := _resolve_sketch()
	if sk_f == null:
		_set_status("Önce kapalı konturlu bir taslak çizin veya ağaçtan bir taslak seçin.")
		return
	var f := CadFeature.new()
	f.id = 0
	f.type = type
	if type == "extrude":
		f.params = {"sketch": sk_f.id, "depth": 10.0, "end": "blind", "reverse": false, "cut": cut}
	elif type == "rib":
		if not viewport.kernel.is_brep():
			_set_status("Kaburga OpenCASCADE (B-rep) çekirdeği gerektirir: Araçlar → Geometri çekirdeği.")
			return
		f.params = {"sketch": sk_f.id, "t": 4.0, "flip": false}
	elif type in ["projcurve", "wrap", "emboss"]:
		if not viewport.kernel.is_brep():
			_set_status("Bu özellik OpenCASCADE (B-rep) çekirdeği gerektirir: Araçlar → Geometri çekirdeği.")
			return
		match type:
			"projcurve":
				f.params = {"sketch": sk_f.id, "face": {}}
			"wrap":
				f.params = {"sketch": sk_f.id, "face": {}, "wtype": "emboss", "depth": 1.0}
			"emboss":
				f.params = {"sketch": sk_f.id, "depth": 1.0, "etype": "emboss", "reverse": false}
	elif type == "sweep" or type == "loft":
		if not viewport.kernel.is_brep():
			_set_status("Süpürme ve loft OpenCASCADE (B-rep) çekirdeği gerektirir: Araçlar → Geometri çekirdeği.")
			return
		if type == "sweep":
			f.params = {"sketch": sk_f.id, "path": _default_path(sk_f.id), "cut": cut}
		else:
			f.params = {"sketches": _default_loft(sk_f.id), "ruled": false, "cut": cut}
	else:
		f.params = {"sketch": sk_f.id, "angle": 360.0, "axis": _default_axis(sk_f), "reverse": false, "cut": cut}
	f.name = f.type_label()
	editing = f
	editing_is_new = true
	mode = "feature"
	_region_pick = false
	_preview()
	_show_feature_panel()


func _edit_feature(f: CadFeature) -> void:
	_exit_sketch3d()
	if mode == "sketch":
		_exit_sketch()
	_leave_aux_mode()
	editing = f.clone()
	editing_is_new = false
	mode = "feature"
	_region_pick = false
	_preview()
	_show_feature_panel()
	_update_region_highlight()


func _preview() -> void:
	if editing == null:
		return
	RefGeom.update(doc, editing)
	viewport.kernel.rebuild(doc, editing, editing.is_brep_feature() and not _brep_show_result)
	_draw_sketches()


func _ok_feature() -> void:
	if editing == null:
		return
	var f := editing
	editing = null
	mode = "idle"
	_region_pick = false
	viewport.clear_face_highlight()
	viewport.set_edge_highlight([])
	_hover_edge = -1
	_pick_target = ""
	doc.checkpoint()
	if editing_is_new:
		var prefix := "Ekstrüzyon" if f.type == "extrude" else "Döndürme"
		match f.type:
			"fillet":
				prefix = "Köşe Yuvarlatma"
			"chamfer":
				prefix = "Pah"
			"shell":
				prefix = "Kabuk"
			"import":
				prefix = "İçe Aktarılan"
			"draft":
				prefix = "Eğim"
			"rib":
				prefix = "Kaburga"
			"combine":
				prefix = "Birleştir"
			"move_body":
				prefix = "Gövde Taşı"
			"split":
				prefix = "Böl"
			"sweep":
				prefix = "Süpürme"
			"loft":
				prefix = "Loft"
			"lpattern":
				prefix = "DoğrusalÇoğaltma"
			"cpattern":
				prefix = "DaireselÇoğaltma"
			"mirror":
				prefix = "Aynala"
			"tpattern":
				prefix = "TabloÇoğaltma"
			"hole":
				prefix = "Delik"
			"dome":
				prefix = "Kubbe"
			"refplane":
				prefix = "Düzlem"
			"refaxis":
				prefix = "Eksen"
			"refpoint":
				prefix = "Nokta"
			"helix":
				prefix = "Helis"
			"refcsys":
				prefix = "KoordinatSistemi"
			"projcurve":
				prefix = "ProjeksiyonEğrisi"
			"cvpattern":
				prefix = "EğriÇoğaltma"
			"wrap":
				prefix = "Sarma"
			"emboss":
				prefix = "Kabartma"
		if f.type in SpecialUI.TYPES:
			prefix = SpecialUI.prefix(f.type)
		if f.is_cut():
			prefix += "-Kesme"
		var nf := doc.new_feature(f.type, prefix)
		nf.params = f.params.duplicate(true)
		doc.add_feature(nf)
		selection = {"kind": "feature", "id": nf.id}
		_set_status(nf.name + I18n.t(" oluşturuldu."))
	else:
		var orig := doc.get_feature(f.id)
		if orig:
			orig.params = f.params.duplicate(true)
		selection = {"kind": "feature", "id": f.id}
	doc.commit()


func _cancel_feature() -> void:
	if mode != "feature":
		return
	editing = null
	mode = "idle"
	_region_pick = false
	viewport.clear_face_highlight()
	viewport.set_edge_highlight([])
	_hover_edge = -1
	_on_doc_changed()


func _show_feature_panel() -> void:
	var f := editing
	if f == null:
		return
	if f.type in SpecialUI.TYPES:
		special.show_feature_panel(f)
		return
	if f.is_brep_feature():
		_show_brep_feature_panel()
		return
	if f.type == "rib":
		_show_rib_panel()
		return
	if f.type in ["projcurve", "wrap", "emboss"]:
		_show_sketchfeat_panel()
		return
	if f.type == "sweep":
		_show_sweep_panel()
		return
	if f.type == "loft":
		_show_loft_panel()
		return
	if f.type in ["lpattern", "cpattern", "mirror", "tpattern", "cvpattern"]:
		_show_pattern_panel()
		return
	if f.is_reference():
		_show_ref_panel()
		return
	panel.clear()
	var icon := "extrude"
	if f.type == "extrude":
		icon = "cut" if f.is_cut() else "extrude"
	else:
		icon = "revcut" if f.is_cut() else "revolve"
	panel.title(f.type_label() if editing_is_new else f.name, Icons.get_icon(icon, 22))
	panel.ok_cancel(_ok_feature, _cancel_feature)
	# Profil taslağı
	var sketches := doc.sketches()
	var names: Array = []
	var sel_i := 0
	for i in sketches.size():
		names.append(sketches[i].name)
		if sketches[i].id == f.sketch_ref():
			sel_i = i
	panel.section("Profil")
	var on_sketch := func(i: int) -> void:
		f.params["sketch"] = sketches[i].id
		if f.type == "revolve":
			f.params["axis"] = _default_axis(sketches[i])
		_preview()
		_show_feature_panel()
	panel.option("Taslak", names, sel_i, on_sketch)
	var on_reverse := func(b: bool) -> void:
		f.params["reverse"] = b
		_preview()
	if f.type == "extrude":
		panel.section("Yön 1")
		var ends := ["blind", "midplane", "through", "next", "vertex", "face", "face_offset"]
		var end_names := ["Kör", I18n.t("Orta Düzlem"), "Tümünden", "Sonrakine Kadar", I18n.t("Köşeye Kadar"), I18n.t("Yüzeye Kadar"), I18n.t("Yüzeyden Ofset")]
		var cur: String = f.params.get("end", "blind")
		var on_end := func(i: int) -> void:
			f.params["end"] = ends[i]
			_preview()
			_show_feature_panel()
		panel.option("Bitiş koşulu", end_names, maxi(ends.find(cur), 0), on_end)
		if cur in ["blind", "midplane"]:
			var on_depth := func(v: float) -> void:
				f.params["depth"] = v
				f.params.erase("depth_expr")
				_preview()
			var df := panel.number("Derinlik", float(f.params.get("depth", 10.0)), on_depth, "length", 0.001)
			df.allow_expr = true
			df.expr_committed.connect(func(ex): _set_feature_expr(f, "depth", ex))
			if str(f.params.get("depth_expr", "")) != "":
				panel.info(I18n.t("Σ Derinlik denklemi: =") + str(f.params["depth_expr"]), Color(0.95, 0.8, 0.4))
		if cur != "midplane":
			panel.check("Yönü ters çevir", bool(f.params.get("reverse", false)), on_reverse)
		_extrude_extra_controls(f, cur)
	else:
		var sk_f := doc.get_feature(f.sketch_ref())
		panel.section("Döndürme ekseni")
		var axis_vals: Array = ["x", "y"]
		var axis_names: Array = [I18n.t("Taslak yatay ekseni (x)"), I18n.t("Taslak dikey ekseni (y)")]
		if sk_f:
			var n := 1
			for e in sk_f.sketch.entities:
				if e["type"] == "line":
					axis_vals.append(e["id"])
					axis_names.append((I18n.t("Merkez çizgisi ") if e.get("construction", false) else I18n.t("Çizgi ")) + str(n))
					n += 1
		for ra in doc.features:
			if ra.type == "refaxis" and not ra.suppressed:
				axis_vals.append("ax:%d" % ra.id)
				axis_names.append(I18n.t("Referans: ") + ra.name)
		var cur_axis = f.params.get("axis", "y")
		var ai := 1
		for i in axis_vals.size():
			if typeof(axis_vals[i]) == typeof(cur_axis) and axis_vals[i] == cur_axis:
				ai = i
		var on_axis := func(i: int) -> void:
			f.params["axis"] = axis_vals[i]
			_preview()
		panel.option("Eksen", axis_names, ai, on_axis)
		panel.section("Yön 1")
		var on_angle := func(v: float) -> void:
			f.params["angle"] = v
			f.params.erase("angle_expr")
			_preview()
		var af := panel.number("Açı", float(f.params.get("angle", 360.0)), on_angle, "angle", 0.1, 360.0)
		af.allow_expr = true
		af.expr_committed.connect(func(ex): _set_feature_expr(f, "angle", ex))
		if str(f.params.get("angle_expr", "")) != "":
			panel.info(I18n.t("Σ Açı denklemi: =") + str(f.params["angle_expr"]), Color(0.95, 0.8, 0.4))
		panel.check("Yönü ters çevir", bool(f.params.get("reverse", false)), on_reverse)
	if not f.is_cut():
		var on_merge := func(b: bool) -> void:
			f.params["merge"] = b
			_preview()
		panel.check("Sonucu birleştir (kapalıysa ayrı gövde)", bool(f.params.get("merge", true)), on_merge)
	var sk2 := doc.get_feature(f.sketch_ref())
	if sk2:
		# Bölge seçme (Contour Select)
		var regs: Array = f.params.get("regions", [])
		panel.section("Profil bölgeleri")
		if regs.is_empty():
			panel.info("Otomatik: taslaktaki tüm kapalı konturlar kullanılıyor.")
		else:
			panel.info(I18n.t("%d bölge seçili (vurgulu alanlar).") % regs.size(), Color(0.55, 0.85, 1.0))
		var pick_btn := panel.button("Bölge seçmeyi bitir" if _region_pick else I18n.t("Bölge seç (taslakta tıkla)"), _toggle_region_pick, Icons.get_icon("region", 18))
		pick_btn.toggle_mode = true
		pick_btn.button_pressed = _region_pick
		if not regs.is_empty():
			panel.button("Otomatiğe dön", _clear_regions, Icons.get_icon("delete", 16))
		var prof := sk2.sketch.extract_profiles()
		if int(prof["open"]) > 0 and regs.is_empty():
			panel.info(I18n.t("Uyarı: taslakta %d açık/dallanan/kesişen kontur var, yok sayıldı. Kesişen eğrilerden oluşan alanları kullanmak için 'Bölge seç'e tıklayın.") % int(prof["open"]), Color(1.0, 0.75, 0.3))
	_error_label = panel.info((I18n.t("Hata: ") + f.error) if f.error != "" else "", Color(1.0, 0.45, 0.4))
	panel.spacer()
	panel.info("Enter: Tamam   Esc: İptal\nSayı alanlarına ifade yazabilirsiniz (ör. 25.4*2).", Color(0.55, 0.6, 0.66))


# ================================================================ PANEL

func _refresh_panel() -> void:
	match mode:
		"cutlist", "configs", "fea", "draft_an", "cam", "render":
			special.show_aux(mode)
		"assembly":
			asm_mode.show_panel()
		"drawing":
			_show_drawing_panel()
		"sketch":
			_show_sketch_panel()
		"feature":
			pass
		"measure":
			_show_measure_panel()
		"mass":
			_show_mass_panel()
		"material":
			_show_material_panel()
		"equations":
			_show_equations_panel()
		"sketch3d":
			_show_sketch3d_panel()
		"kernel":
			_show_kernel_panel()
		"plugin":
			panel.clear()
			if _plugin_panel_api != null:
				_plugin_panel_api.build_panel(panel)
		_:
			_show_idle_panel()


func _show_idle_panel() -> void:
	panel.clear()
	var k: String = selection.get("kind", "")
	if k == "feature":
		var f := doc.get_feature(int(selection["id"]))
		if f:
			panel.title(f.name, tree._feature_icon(f))
			panel.info(f.type_label())
			if f.error != "":
				panel.info(I18n.t("Hata: ") + f.error, Color(1.0, 0.45, 0.4))
			if f.is_sketch():
				var prof := f.sketch.extract_profiles()
				panel.info(I18n.t("Düzlem: %s\nÖğe sayısı: %d\nKapalı kontur: %d\nAçık kontur: %d") % [
					f.plane.name, f.sketch.entities.size(), (prof["loops"] as Array).size(), int(prof["open"])])
				panel.button("Taslağı düzenle", func(): _edit_sketch(f), Icons.get_icon("sketch", 18))
				panel.button("Ekstrüzyon Patron/Taban", func(): _cmd("extrude"), Icons.get_icon("extrude", 18))
				panel.button("Ekstrüzyon Kesme", func(): _cmd("cut"), Icons.get_icon("cut", 18))
				panel.button("Döndürme", func(): _cmd("revolve"), Icons.get_icon("revolve", 18))
				panel.button("DXF olarak dışa aktar", func(): _cmd("export_dxf"), Icons.get_icon("export", 18))
			elif f.is_brep_feature() or f.type in ["rib", "sweep", "loft", "lpattern", "cpattern", "mirror", "tpattern", "cvpattern", "projcurve", "wrap", "emboss"] or f.is_reference():
				panel.info(_brep_summary(f))
				panel.button("Özelliği düzenle", func(): _edit_feature(f), tree._feature_icon(f))
				var rs := doc.get_feature(f.sketch_ref()) if f.type in ["rib", "projcurve", "wrap", "emboss"] else null
				if rs:
					panel.button("Taslağı düzenle", func(): _edit_sketch(rs), Icons.get_icon("sketch", 18))
			else:
				var p := f.params
				if f.type == "extrude":
					var end_names := {"blind": "Kör", "midplane": I18n.t("Orta Düzlem"), "through": "Tümünden"}
					var txt := I18n.t("Bitiş: ") + str(end_names.get(p.get("end", "blind"), ""))
					if p.get("end", "blind") != "through":
						txt += I18n.t("\nDerinlik: ") + Units.format_length(float(p.get("depth", 0.0)))
					panel.info(txt)
				else:
					panel.info(I18n.t("Açı: ") + Units.format_angle(float(p.get("angle", 360.0))))
				var icon_name := "extrude"
				if f.type == "extrude":
					icon_name = "cut" if f.is_cut() else "extrude"
				else:
					icon_name = "revcut" if f.is_cut() else "revolve"
				panel.button("Özelliği düzenle", func(): _edit_feature(f), Icons.get_icon(icon_name, 18))
				var s := doc.get_feature(f.sketch_ref())
				if s:
					panel.button("Taslağı düzenle", func(): _edit_sketch(s), Icons.get_icon("sketch", 18))
			return
	if k == "plane" or (k == "face" and selection.get("planar", false)):
		panel.title(SketchPlane.standard(selection["id"]).name if k == "plane" else "Düzlemsel yüz", Icons.get_icon("plane", 22))
		panel.button("Bu düzlemde taslak çiz", func(): _cmd_sketch(), Icons.get_icon("sketch", 18))
		return
	panel.title(doc.part_name, Icons.get_icon("part", 22))
	var rec_files := AppSettings.recent()
	if doc.features.is_empty() and not rec_files.is_empty():
		panel.section("Son dosyalar")
		for i in mini(rec_files.size(), 6):
			var rp: String = rec_files[i]
			var rb := panel.button(rp.get_file(), func(): open_recent(rp), Icons.get_icon("assembly" if rp.get_extension().to_lower() == "dasm" else "part", 16))
			rb.tooltip_text = rp
			rb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var n_feat := 0
	for f in doc.features:
		if not f.is_sketch():
			n_feat += 1
	var nb := int(viewport.model.exact_mass.get("solids", 1 if not viewport.model.is_empty() else 0)) if not viewport.model.exact_mass.is_empty() else (1 if not viewport.model.is_empty() else 0)
	panel.info(I18n.t("Özellik: %d   Taslak: %d   Gövde: %d   Üçgen: %d") % [n_feat, doc.sketches().size(), nb, viewport.model.tri_count()])
	panel.section("Başlarken")
	panel.info("1. Ağaçtan veya ekrandan bir düzlem seçin.\n2. 'Taslak' ile çizime başlayın, dikdörtgen/daire çizin.\n3. Ölçüleri bu panelden girin.\n4. 'Ekstrüzyon' ile katı oluşturun.\n5. Dışa Aktar (Ctrl+E) ile STL, STEP ve diğer formatlarda çıktı alın.")
	panel.section("Fare")
	panel.info("Orta tuş / sağ tuş sürükle: döndür\nCtrl + orta/sağ tuş: kaydır\nTekerlek: yakınlaştır   F: sığdır")
	panel.button("Örnek parçayı aç", func(): _cmd("demo"), Icons.get_icon("part", 18))


func _show_sketch_panel() -> void:
	panel.clear()
	var f := editor.feature
	if f == null:
		return
	var sk := f.sketch
	panel.title(f.name + I18n.t(" (Taslak)"), Icons.get_icon("sketch", 22))
	panel.button("Taslaktan çık", func(): _exit_sketch(), Icons.get_icon("exit_sketch", 18))
	if _sketch_op != "":
		if editor.selected_entities.is_empty():
			_close_sketch_op()
		else:
			_show_sketch_op_panel()
			return
	var ents: Array = editor.selected_entities.keys()
	var pts: Array = editor.selected_points.keys()
	var cons: Array = editor.selected_constraints.keys()
	var full_e: Dictionary = editor.analysis.get("entities", {})
	var full_p: Dictionary = editor.analysis.get("points", {})
	# Araç seçenekleri (seçim yokken)
	if ents.is_empty() and pts.is_empty() and cons.is_empty() and editor.tool in ["fillet", "chamfer", "polygon", "text"]:
		_tool_options_panel()
		return
	if not cons.is_empty() and ents.is_empty() and pts.is_empty():
		if cons.size() == 1:
			_constraint_panel(sk, sk.get_constraint(cons[0]))
		else:
			panel.info(I18n.t("%d ilişki/boyut seçili.") % cons.size())
			panel.button("Seçilenleri sil", func(): editor.delete_selection(), Icons.get_icon("delete", 18))
		return
	if ents.size() == 1 and pts.is_empty():
		var e := sk.get_entity(ents[0])
		if e.is_empty():
			return
		var eid: int = e["id"]
		var locked: bool = full_e.get(eid, false)
		if locked:
			panel.info("Tam tanımlı (siyah). Değiştirmek için boyutunu çift tıklayıp düzenleyin.", Color(0.7, 0.75, 0.8))
		match e["type"]:
			"line":
				var gid := int(e.get("group", 0))
				var a: Vector2 = sk.points[e["a"]]
				var b: Vector2 = sk.points[e["b"]]
				var L := a.distance_to(b)
				var ang := fposmod(rad_to_deg((b - a).angle()), 360.0)
				if locked:
					panel.section("Çizgi")
					panel.info(I18n.t("Uzunluk: %s\nAçı: %s\nBaşlangıç: (%s, %s)\nBitiş: (%s, %s)") % [
						Units.format_length(L), Units.format_angle(ang), Units.format_length(a.x, false),
						Units.format_length(a.y, false), Units.format_length(b.x, false), Units.format_length(b.y, false)])
				elif gid != 0 and sk.groups.has(gid):
					var ri := sk.rect_info(gid)
					var pos: Vector2 = ri["pos"]
					var rs: Vector2 = ri["size"]
					panel.section("Dikdörtgen")
					panel.number("Genişlik", rs.x, func(v): editor.edit_rect(gid, pos, Vector2(v, rs.y)), "length", 0.0001)
					panel.number("Yükseklik", rs.y, func(v): editor.edit_rect(gid, pos, Vector2(rs.x, v)), "length", 0.0001)
					panel.number("Sol alt X", pos.x, func(v): editor.edit_rect(gid, Vector2(v, pos.y), rs))
					panel.number("Sol alt Y", pos.y, func(v): editor.edit_rect(gid, Vector2(pos.x, v), rs))
					panel.button("Merkezi orijine taşı", func(): editor.edit_rect(gid, -rs * 0.5, rs))
				else:
					panel.section("Merkez çizgisi" if e.get("construction", false) else "Çizgi")
					panel.number("Uzunluk", L, func(v): editor.edit_line(eid, v, ang), "length", 0.0001)
					panel.number("Açı", ang, func(v): editor.edit_line(eid, L, v), "angle")
					panel.section("Başlangıç noktası")
					panel.number("X", a.x, func(v): editor.edit_point(e["a"], Vector2(v, a.y)))
					panel.number("Y", a.y, func(v): editor.edit_point(e["a"], Vector2(a.x, v)))
					panel.section("Bitiş noktası")
					panel.number("X", b.x, func(v): editor.edit_point(e["b"], Vector2(v, b.y)))
					panel.number("Y", b.y, func(v): editor.edit_point(e["b"], Vector2(b.x, v)))
			"circle":
				var c: Vector2 = sk.points[e["c"]]
				var r: float = e["r"]
				panel.section("Daire")
				if locked:
					panel.info(I18n.t("Çap: %s\nMerkez: (%s, %s)") % [Units.format_length(r * 2.0), Units.format_length(c.x, false), Units.format_length(c.y, false)])
				else:
					panel.number("Çap", r * 2.0, func(v): editor.edit_circle(eid, c, v), "length", 0.0001)
					panel.number("Merkez X", c.x, func(v): editor.edit_circle(eid, Vector2(v, c.y), r * 2.0))
					panel.number("Merkez Y", c.y, func(v): editor.edit_circle(eid, Vector2(c.x, v), r * 2.0))
			"arc":
				var d := sk.arc_data(e)
				var c2: Vector2 = d["c"]
				var rad: float = d["r"]
				var a0 := fposmod(rad_to_deg(float(d["a0"])), 360.0)
				var a1 := fposmod(a0 + rad_to_deg(float(d["sweep"])), 360.0)
				panel.section("Yay")
				if locked:
					panel.info(I18n.t("Yarıçap: %s\nMerkez: (%s, %s)\nAçılar: %s → %s") % [Units.format_length(rad), Units.format_length(c2.x, false),
						Units.format_length(c2.y, false), Units.format_angle(a0), Units.format_angle(a1)])
				else:
					panel.number("Yarıçap", rad, func(v): editor.edit_arc(eid, c2, v, a0, a1), "length", 0.0001)
					panel.number("Merkez X", c2.x, func(v): editor.edit_arc(eid, Vector2(v, c2.y), rad, a0, a1))
					panel.number("Merkez Y", c2.y, func(v): editor.edit_arc(eid, Vector2(c2.x, v), rad, a0, a1))
					panel.number("Başlangıç açısı", a0, func(v): editor.edit_arc(eid, c2, rad, v, a1), "angle")
					panel.number("Bitiş açısı", a1, func(v): editor.edit_arc(eid, c2, rad, a0, v), "angle")
			"text":
				panel.section("Metin")
				panel.text_field("Yazı", str(e.get("text", "")), func(t): _edit_text(eid, t, -1.0))
				panel.number("Yazı boyutu", float(e.get("h", 10.0)), func(v): _edit_text(eid, "", v), "length", 0.1)
				var tp: Vector2 = sk.points[e["p"]]
				panel.number("Konum X", tp.x, func(v): editor.edit_point(e["p"], Vector2(v, tp.y)))
				panel.number("Konum Y", tp.y, func(v): editor.edit_point(e["p"], Vector2(tp.x, v)))
				panel.info("Kapalı bir şeklin içine yazıp Ekstrüzyon Kesme ile gravür, tek başına Ekstrüzyon ile kabartma yapılır.", Color(0.6, 0.65, 0.7))
			"spline":
				panel.section("Spline")
				var closed: bool = e["pts"][0] == e["pts"][e["pts"].size() - 1]
				panel.info(I18n.t("%d nokta, %s. Şekli değiştirmek için noktaları sürükleyin.") % [Sketch.entity_point_ids(e).size(), I18n.t("kapalı") if closed else I18n.t("açık")])
			"ellipse":
				var ax := sk.ellipse_axes(e)
				var ec: Vector2 = ax["c"]
				var ea: float = ax["a"]
				var eb: float = ax["b"]
				var eang := fposmod(rad_to_deg(float(ax["phi"])), 360.0)
				panel.section("Elips")
				if locked:
					panel.info(I18n.t("Büyük yarı eksen: %s\nKüçük yarı eksen: %s\nAçı: %s") % [Units.format_length(ea), Units.format_length(eb), Units.format_angle(eang)])
				else:
					panel.number("Büyük yarı eksen", ea, func(v): editor.edit_ellipse(eid, ec, v, eb, eang), "length", 0.0001)
					panel.number("Küçük yarı eksen", eb, func(v): editor.edit_ellipse(eid, ec, ea, v, eang), "length", 0.0001)
					panel.number("Açı", eang, func(v): editor.edit_ellipse(eid, ec, ea, eb, v), "angle")
					panel.number("Merkez X", ec.x, func(v): editor.edit_ellipse(eid, Vector2(v, ec.y), ea, eb, eang))
					panel.number("Merkez Y", ec.y, func(v): editor.edit_ellipse(eid, Vector2(ec.x, v), ea, eb, eang))
				panel.info("Küçük eksen Akıllı Boyut ile (elipse tıklayın), büyük eksen merkez-uç mesafesiyle ölçülendirilir.", Color(0.6, 0.65, 0.7))
			"parabola":
				var fr := sk.parabola_frame(e)
				panel.section("Parabol")
				panel.info(I18n.t("Odak uzaklığı: %s\nŞekli değiştirmek için tepe, odak veya uç noktalarını sürükleyin; uçlar parabol üzerinde kalır.") % Units.format_length(float(fr["fl"])))
		var bid := sk.block_of_entity(eid)
		if bid >= 0:
			var bname := str(sk.blocks[bid]["name"])
			panel.section(I18n.t("Blok: ") + bname)
			panel.button("Bloğu dağıt", func(): editor.explode_block(bid), Icons.get_icon("block", 18))
			panel.button("Bloğu kopyala (+10, +10)", func(): editor.copy_block(bid, Vector2(10, 10)), Icons.get_icon("pattern", 18))
		if e["type"] != "text":
			panel.check("Yapı geometrisi (construction)", bool(e.get("construction", false)), func(v): editor.edit_construction([eid], v))
		panel.button("Sil", func(): editor.delete_selection(), Icons.get_icon("delete", 18))
	elif pts.size() == 1 and ents.is_empty():
		var pid: int = pts[0]
		if not sk.points.has(pid):
			return
		var p: Vector2 = sk.points[pid]
		if pid == Sketch.ORIGIN:
			panel.section("Orijin")
			panel.info("Taslak orijini sabittir. Diğer öğeleri orijine ilişkilendirmek veya boyutlandırmak için birlikte seçin.")
		else:
			panel.section("Nokta")
			if full_p.get(pid, false):
				panel.info(I18n.t("(%s, %s) — tam tanımlı") % [Units.format_length(p.x, false), Units.format_length(p.y, false)])
			else:
				panel.number("X", p.x, func(v): editor.edit_point(pid, Vector2(v, p.y)))
				panel.number("Y", p.y, func(v): editor.edit_point(pid, Vector2(p.x, v)))
			panel.info(I18n.t("Bu noktaya bağlı öğe: %d") % sk.point_users(pid).size())
			panel.button("Sil", func(): editor.delete_selection(), Icons.get_icon("delete", 18))
	elif ents.size() + pts.size() > 1:
		panel.info(I18n.t("%d öğe seçili.") % (ents.size() + pts.size()))
		panel.button("Seçilenleri sil", func(): editor.delete_selection(), Icons.get_icon("delete", 18))
		if not ents.is_empty():
			panel.button("Yapı geometrisi aç/kapat", func(): _cmd("toggle_construction"), Icons.get_icon("centerline", 18))
			panel.button("Seçimden blok oluştur", func(): _cmd("op_block"), Icons.get_icon("block", 18))
	if ents.size() + pts.size() >= 1:
		_relations_section(sk, ents, pts)
		return
	# Hiçbir şey seçili değil: taslak bilgisi
	var an := editor.analysis
	var st: String = an.get("status", "under")
	var st_names := {"full": I18n.t("Tam tanımlı"), "under": I18n.t("Eksik tanımlı"), "over": I18n.t("Aşırı tanımlı")}
	var st_cols := {"full": Color(0.85, 0.9, 0.95), "under": Color(0.45, 0.65, 1.0), "over": Color(1.0, 0.4, 0.35)}
	panel.section("Tanım durumu")
	if sk.is_empty():
		panel.info("Taslak boş.")
	else:
		panel.info(I18n.t("%s — serbestlik derecesi: %d") % [st_names.get(st, st), int(an.get("dof", 0))], st_cols.get(st, Color.WHITE))
	var prof := sk.extract_profiles()
	var n_dim := 0
	for c in sk.constraints:
		if Sketch.is_dimension(c):
			n_dim += 1
	panel.info(I18n.t("Düzlem: %s\nÖğe: %d   Nokta: %d\nBoyut: %d   İlişki: %d\nKapalı kontur: %d   Açık: %d") % [
		f.plane.name, sk.entities.size(), sk.points.size() - 1, n_dim, sk.constraints.size() - n_dim,
		(prof["loops"] as Array).size(), int(prof["open"])])
	panel.section("İpuçları")
	panel.info("• Mavi = eksik tanımlı, siyah = tam tanımlı.\n• Akıllı Boyut (D): çizgiye tıklayıp yerleştirin; değeri yazın.\n• İki öğeyi Shift ile seçin → panelden ilişki (paralel, teğet...) ekleyin.\n• Boyut etiketine çift tıklayınca değer değişir; taslak kendini günceller.\n• Noktaları sürükleyin: ilişkiler korunur.")


func _relations_section(sk: Sketch, ents: Array, pts: Array) -> void:
	var existing := sk.constraints_touching(ents, pts)
	if not existing.is_empty():
		panel.section("Mevcut ilişkiler ve boyutlar")
		for c in existing:
			var cid: int = c["id"]
			var icon := Icons.get_icon("dimension", 16) if Sketch.is_dimension(c) else Icons.get_icon("rel_" + str(c["type"]), 16)
			panel.item_row(SketchEditor.constraint_label(sk, c), icon, func(): editor.delete_constraint(cid))
	var avail := editor.available_relations()
	if not avail.is_empty():
		panel.section("İlişki ekle")
		for a in avail:
			var t: String = a[0]
			panel.button(a[1], func(): editor.add_relation(t), Icons.get_icon("rel_" + t, 18))
	if not ents.is_empty():
		panel.section("Taslak araçları")
		panel.button("Ofset...", func(): _cmd("op_offset"), Icons.get_icon("offset", 18))
		if editor.mirror_axis() >= 0 and ents.size() >= 2:
			panel.button("Merkez çizgisine göre aynala", func(): _cmd("op_mirror"), Icons.get_icon("mirror", 18))
		panel.button("Taşı / kopyala / döndür / çoğalt...", func(): _cmd("op_transform"), Icons.get_icon("pattern", 18))


func _constraint_panel(sk: Sketch, c: Dictionary) -> void:
	if c.is_empty():
		return
	var cid: int = c["id"]
	var t: String = c["type"]
	if Sketch.is_dimension(c):
		var driven := bool(c.get("driven", false))
		panel.section(I18n.t("Boyut: ") + str(SketchEditor.DIM_NAMES.get(t, t)))
		panel.info(I18n.t("Ad: ") + Equations.full_name(c, editor.feature.name) + I18n.t("  (denklemlerde bu adla kullanılır)"), Color(0.6, 0.75, 0.9))
		if driven:
			panel.info(I18n.t("Değer: ") + SketchEditor.dimension_text(c))
		else:
			var kind := "angle" if t == "angle" else "length"
			var nf := panel.number("Değer", float(c["value"]), func(v): editor.set_dimension_value(cid, v), kind, 0.0001)
			nf.allow_expr = true
			nf.expr_committed.connect(func(ex): editor.set_dimension_expr(cid, ex))
			panel.text_field("Denklem", str(c.get("expr", "")), func(tx): editor.set_dimension_expr(cid, tx), I18n.t("ör. genislik / 2"))
			if str(c.get("expr", "")) != "":
				panel.info("Σ Bu boyut denklemle sürülüyor; değeri değişkenler değişince güncellenir.", Color(0.95, 0.8, 0.4))
		panel.check("Güdümlü (referans) boyut", driven, func(b): editor.set_dimension_driven(cid, b))
		panel.info("Sürükleyici boyut geometriyi belirler; güdümlü boyut yalnızca ölçer.", Color(0.6, 0.65, 0.7))
	else:
		panel.section(I18n.t("İlişki: ") + I18n.t(str(SketchEditor.RELATION_NAMES.get(t, t))))
		var parts: Array = []
		for eid in Sketch.constraint_entities(c):
			var e := sk.get_entity(eid)
			parts.append({"line": "Çizgi", "circle": "Daire", "arc": "Yay"}.get(e.get("type", ""), "?"))
		for pid in Sketch.constraint_points(c):
			parts.append("Orijin" if pid == Sketch.ORIGIN else "Nokta")
		panel.info(I18n.t("Öğeler: ") + ", ".join(parts))
	panel.button("Sil", func(): editor.delete_constraint(cid), Icons.get_icon("delete", 18))


# ---------------------------------------------------------------- Taslak işlem panelleri (Faz 3)

func _offset_value() -> float:
	var d := float(_op_params["dist"])
	return -d if bool(_op_params["flip"]) else d


func _close_sketch_op() -> void:
	_sketch_op = ""
	if editor and editor.active:
		editor.clear_preview()


func _tool_options_panel() -> void:
	match editor.tool:
		"fillet":
			panel.section("Köşe yuvarlatma")
			var on_r := func(v: float) -> void:
				editor.fillet_radius = v
				editor._emit_hint()
			panel.number("Yarıçap", editor.fillet_radius, on_r, "length", 0.001)
			panel.info("Köşe noktasına (iki çizginin birleştiği yer) tıklayın. Eklenen yarıçap boyutu sonradan değiştirilebilir; köşeye bağlı boyutlar sanal köşede (×) kalır.")
		"chamfer":
			panel.section("Pah")
			var on_d := func(v: float) -> void:
				editor.chamfer_dist = v
				editor._emit_hint()
			panel.number("Mesafe", editor.chamfer_dist, on_d, "length", 0.001)
			panel.info("Köşe noktasına tıklayın. İki eşit mesafe boyutu eklenir.")
		"polygon":
			panel.section("Çokgen")
			var on_n := func(v: float) -> void:
				editor.polygon_sides = clampi(int(round(v)), 3, 64)
				editor._emit_hint()
			panel.number("Kenar sayısı", float(editor.polygon_sides), on_n, "plain", 3, 64)
			panel.info("Merkezi, sonra bir köşeyi tıklayın. Köşeler yapı çemberi üzerinde, kenarlar eşit kalır.")
		"text":
			panel.section("Yeni metin")
			var on_t := func(t: String) -> void:
				if t.strip_edges() != "":
					editor.text_default = t
			panel.text_field("Yazı", editor.text_default, on_t)
			var on_h := func(v: float) -> void:
				editor.text_height = v
			panel.number("Yazı boyutu", editor.text_height, on_h, "length", 0.1)
			panel.info("Yerleştirmek için taslakta bir noktaya tıklayın.")


func _show_sketch_op_panel() -> void:
	match _sketch_op:
		"offset":
			panel.section(I18n.t("Ofset (%d öğe)") % editor.selected_entities.size())
			var on_dist := func(v: float) -> void:
				_op_params["dist"] = v
				editor.set_offset_preview(_offset_value())
			panel.number("Mesafe", float(_op_params["dist"]), on_dist, "length", 0.001)
			var on_flip := func(b: bool) -> void:
				_op_params["flip"] = b
				editor.set_offset_preview(_offset_value())
			panel.check("Yönü ters çevir (içe / diğer taraf)", bool(_op_params["flip"]), on_flip)
			panel.info("Kesikli turuncu çizgi önizlemedir. Kapalı zincirde varsayılan dışa doğrudur. Ofset kenarları tek bir mesafe boyutuna bağlanır.")
			panel.ok_cancel(_apply_offset, _cancel_sketch_op)
		"transform":
			var kinds := ["move", "rotate", "scale", "linear", "circular"]
			var names := [I18n.t("Taşı"), "Döndür", I18n.t("Ölçekle"), I18n.t("Doğrusal çoğalt"), I18n.t("Dairesel çoğalt")]
			var k: String = _op_params["kind"]
			panel.section(I18n.t("Dönüştür / çoğalt (%d öğe)") % editor.selected_entities.size())
			var on_kind := func(i: int) -> void:
				_op_params["kind"] = kinds[i]
				_refresh_panel()
			panel.option("İşlem", names, maxi(kinds.find(k), 0), on_kind)
			var setp := func(key: String) -> Callable:
				return func(v: float) -> void: _op_params[key] = v
			match k:
				"move", "linear":
					panel.number("dX" if k == "move" else I18n.t("Aralık X"), float(_op_params["dx"]), setp.call("dx"))
					panel.number("dY" if k == "move" else I18n.t("Aralık Y"), float(_op_params["dy"]), setp.call("dy"))
				"rotate", "scale", "circular":
					panel.number("Merkez X", float(_op_params["cx"]), setp.call("cx"))
					panel.number("Merkez Y", float(_op_params["cy"]), setp.call("cy"))
					if k == "rotate":
						panel.number("Açı", float(_op_params["angle"]), setp.call("angle"), "angle")
					elif k == "scale":
						panel.number("Ölçek", float(_op_params["scale"]), setp.call("scale"), "plain", 0.0001)
					else:
						panel.number("Toplam açı", float(_op_params["total"]), setp.call("total"), "angle", 1.0, 360.0)
			if k == "linear" or k == "circular":
				var on_count := func(v: float) -> void:
					_op_params["count"] = clampi(int(round(v)), 2, 200)
				panel.number("Adet (orijinal dahil)", float(_op_params["count"]), on_count, "plain", 2, 200)
			else:
				var on_copy := func(b: bool) -> void:
					_op_params["copy"] = b
				panel.check("Kopya oluştur (orijinali koru)", bool(_op_params["copy"]), on_copy)
			panel.ok_cancel(_apply_transform, _cancel_sketch_op)


func _apply_offset() -> void:
	var r := editor.offset_selection(_offset_value())
	if r.get("ok", false):
		_sketch_op = ""
	_refresh_panel()


func _cancel_sketch_op() -> void:
	_close_sketch_op()
	_refresh_panel()


func _apply_transform() -> void:
	var p := _op_params
	var k: String = p["kind"]
	var a := Vector2.ZERO
	var b := 0.0
	match k:
		"move", "linear":
			a = Vector2(float(p["dx"]), float(p["dy"]))
		"rotate":
			a = Vector2(float(p["cx"]), float(p["cy"]))
			b = float(p["angle"])
		"scale":
			a = Vector2(float(p["cx"]), float(p["cy"]))
			b = float(p["scale"])
		"circular":
			a = Vector2(float(p["cx"]), float(p["cy"]))
			b = float(p["total"])
	var r := editor.transform_selection(k, a, b, int(p["count"]), bool(p["copy"]))
	if r.get("ok", false):
		_sketch_op = ""
	_refresh_panel()


func _edit_text(eid: int, txt: String, h: float) -> void:
	var sk := editor.sketch()
	var e := sk.get_entity(eid)
	if e.is_empty():
		return
	if txt == "" and h <= 0.0:
		return
	var new_t := txt if txt != "" else str(e["text"])
	var new_h := h if h > 0.0 else float(e["h"])
	if new_t == str(e["text"]) and absf(new_h - float(e["h"])) < 1e-9:
		return
	doc.checkpoint()
	e["text"] = new_t
	e["h"] = new_h
	doc.commit()


# ---------------------------------------------------------------- Denklemler

func _show_equations_panel() -> void:
	panel.clear()
	panel.title("Denklemler", Icons.get_icon("equations", 22))
	panel.button("Kapat", func(): _leave_aux_mode(), Icons.get_icon("exit_sketch", 18))
	var vv := Equations.variable_values(doc)
	var vals: Dictionary = vv["values"]
	panel.section("Global değişkenler")
	if doc.variables.is_empty():
		panel.info("Henüz değişken yok. Örnek: genislik = 80, sonra boyuta '=genislik/2' yazın.")
	for i in doc.variables.size():
		var v: Dictionary = doc.variables[i]
		var idx := i
		var vname := str(v["name"])
		var shown := ("= " + Units.fmt_sig(float(vals[vname]), 6)) if vals.has(vname) else "= ?"
		panel.text_field("Ad", vname, func(t): _set_variable(idx, t, ""))
		panel.text_field("İfade", str(v["expr"]), func(t): _set_variable(idx, "", t), I18n.t("ör. 80 veya genislik*2"))
		panel.item_row(vname + " " + shown, Icons.get_icon("equations", 14), func(): _remove_variable(idx))
	panel.button("Değişken ekle", _add_variable, Icons.get_icon("new", 18))
	panel.section("Denklemle sürülen boyutlar")
	var any := false
	for f in doc.sketches():
		for c in f.sketch.constraints:
			if str(c.get("expr", "")) != "":
				any = true
				var fid: int = f.id
				var cid: int = c["id"]
				panel.item_row("%s = %s" % [Equations.full_name(c, f.name), c["expr"]], Icons.get_icon("dimension", 14), func(): _clear_dim_expr(fid, cid))
	for f in doc.features:
		for key in ["depth", "angle"]:
			if str(f.params.get(key + "_expr", "")) != "":
				any = true
				var ff: CadFeature = f
				var kk: String = key
				panel.item_row("D1@%s = %s" % [f.name, f.params[key + "_expr"]], Icons.get_icon("extrude", 14), func(): _clear_feature_expr(ff.id, kk))
	if not any:
		panel.info("Yok. Bir boyutun değer kutusuna '=' ile başlayan ifade yazın (ör. =genislik/2).")
	for err in vv["errors"]:
		panel.info(str(err), Color(1.0, 0.45, 0.4))
	panel.section("Kullanılabilir boyut adları")
	var names := PackedStringArray()
	for n in Equations.dimension_values(doc).keys():
		names.append(str(n))
	panel.info(", ".join(names) if not names.is_empty() else "-", Color(0.6, 0.7, 0.8))


func _add_variable() -> void:
	var n := 1
	var existing := {}
	for v in doc.variables:
		existing[str(v["name"])] = true
	while existing.has("degisken%d" % n):
		n += 1
	doc.checkpoint()
	doc.variables.append({"name": "degisken%d" % n, "expr": "10"})
	doc.commit()


func _set_variable(idx: int, new_name: String, new_expr: String) -> void:
	if idx < 0 or idx >= doc.variables.size():
		return
	if new_name != "":
		if not Equations.valid_var_name(new_name):
			_set_status("Geçersiz değişken adı: harf ile başlamalı, boşluk içermemeli.")
			_refresh_panel()
			return
		doc.checkpoint()
		doc.variables[idx]["name"] = new_name
		doc.commit()
	elif new_expr != "":
		doc.checkpoint()
		doc.variables[idx]["expr"] = new_expr
		doc.commit()


func _remove_variable(idx: int) -> void:
	doc.checkpoint()
	doc.variables.remove_at(idx)
	doc.commit()


func _clear_dim_expr(fid: int, cid: int) -> void:
	var f := doc.get_feature(fid)
	if f == null:
		return
	doc.checkpoint()
	f.sketch.get_constraint(cid).erase("expr")
	doc.commit()


func _clear_feature_expr(fid: int, key: String) -> void:
	var f := doc.get_feature(fid)
	if f == null:
		return
	doc.checkpoint()
	f.params.erase(key + "_expr")
	doc.commit()


# ================================================================ DEĞERLENDİR (Ölç, Kütle, Malzeme, Birimler)

func _is_aux_mode() -> bool:
	return mode == "measure" or mode == "mass" or mode == "material" or mode == "equations" or mode == "kernel" or mode == "plugin" or mode in SpecialUI.AUX


func _enter_aux_mode(m: String) -> void:
	_exit_sketch3d()
	if mode == "sketch":
		_exit_sketch()
	if mode == "feature":
		_cancel_feature()
	_leave_aux_mode()
	if (m == "mass" or m == "measure") and viewport.model.is_empty():
		_set_status("Bu araç için önce bir katı model oluşturun (ör. Ekstrüzyon).")
		return
	mode = m
	selection = {}
	_apply_selection_visuals()
	match m:
		"measure":
			_measure_picks.clear()
			_update_measure_visuals()
			_set_status("Ölç: model üzerinde yüz veya köşe noktasına tıklayın (en fazla 2 seçim). Esc: kapat.")
		"mass":
			_compute_mass()
			_set_status("Kütle özellikleri hesaplandı. Pembe işaret ağırlık merkezidir.")
		"material":
			_material_choice = doc.material
			_set_status("Listeden malzeme seçin; model rengi önizlenir.")
	_refresh_panel()


func _leave_aux_mode() -> void:
	if not _is_aux_mode():
		return
	var was := mode
	mode = "idle"
	special.on_leave_aux(was)
	_measure_picks.clear()
	(viewport.overlay_mi.mesh as ArrayMesh).clear_surfaces()
	viewport.clear_face_highlight()
	if was == "material":
		viewport.model_mat.albedo_color = Materials.color_of(doc.material)
	_refresh_panel()


# ---------------------------------------------------------------- Ölç

func _measure_pick(pos: Vector2, _add: bool) -> void:
	var r := viewport.ray(pos)
	var hit := viewport.model.raycast(r[0], r[1])
	if hit.is_empty():
		_measure_picks.clear()
		_update_measure_visuals()
		_refresh_panel()
		return
	var p: Vector3 = hit["point"]
	var tri := int(hit["tri"])
	var v := viewport.model.nearest_vertex_of(tri, p)
	var pick: Dictionary
	if viewport.world_to_screen(v).distance_to(pos) <= 10.0:
		pick = {"kind": "vertex", "p": v}
	else:
		var fd := viewport.model.planar_face(tri)
		var ap := viewport.model.region_area_perimeter(fd["tris"])
		pick = {"kind": "face", "tris": fd["tris"], "planar": fd["planar"], "normal": fd["normal"],
			"point": fd["point"], "area": ap.x, "perimeter": ap.y}
	if _measure_picks.size() >= 2:
		_measure_picks.clear()
	_measure_picks.append(pick)
	_update_measure_visuals()
	_refresh_panel()


func _update_measure_visuals() -> void:
	var tris := PackedVector3Array()
	var lb := LineBuilder.new()
	var w := viewport.camera.world_per_pixel()
	var col := Color(0.9, 0.2, 0.6)
	var pts: Array = []
	for pk in _measure_picks:
		if pk["kind"] == "face":
			tris.append_array(viewport.model.face_triangles(pk["tris"]))
		else:
			var q: Vector3 = pk["p"]
			pts.append(q)
			var b := viewport.camera.orient
			var s := 6.0 * w
			lb.line(q - b.x * s, q + b.x * s, col)
			lb.line(q - b.y * s, q + b.y * s, col)
	if pts.size() == 2:
		lb.line(pts[0], pts[1], col)
	elif pts.size() == 1 and _measure_picks.size() == 2:
		for pk in _measure_picks:
			if pk["kind"] == "face" and pk["planar"]:
				var n: Vector3 = pk["normal"]
				var q2: Vector3 = pts[0]
				var foot: Vector3 = q2 - n * n.dot(q2 - (pk["point"] as Vector3))
				lb.line(q2, foot, col)
	viewport.set_face_highlight(tris)
	lb.commit(viewport.overlay_mi.mesh)


func _measure_results() -> Array:
	var out: Array = []
	var P := _measure_picks
	if P.size() == 1:
		var a: Dictionary = P[0]
		if a["kind"] == "vertex":
			var q: Vector3 = a["p"]
			out.append(I18n.t("Nokta: X %s  Y %s  Z %s") % [Units.format_length(q.x, false), Units.format_length(q.y, false), Units.format_length(q.z, false)])
		else:
			out.append(I18n.t("Alan: ") + Units.format_area(a["area"]))
			out.append(I18n.t("Çevre: ") + Units.format_length(a["perimeter"]))
			if a["planar"]:
				var n: Vector3 = a["normal"]
				out.append(I18n.t("Düzlemsel yüz, normal: (%.3f, %.3f, %.3f)") % [n.x, n.y, n.z])
			else:
				out.append(I18n.t("Eğri yüz"))
	elif P.size() == 2:
		var a2: Dictionary = P[0]
		var b2: Dictionary = P[1]
		if a2["kind"] == "vertex" and b2["kind"] == "vertex":
			var d: Vector3 = (b2["p"] as Vector3) - (a2["p"] as Vector3)
			out.append(I18n.t("Mesafe: ") + Units.format_length(d.length()))
			out.append("dX: %s   dY: %s   dZ: %s" % [Units.format_length(absf(d.x)), Units.format_length(absf(d.y)), Units.format_length(absf(d.z))])
		elif a2["kind"] != b2["kind"]:
			var vtx: Dictionary = a2 if a2["kind"] == "vertex" else b2
			var fc: Dictionary = b2 if a2["kind"] == "vertex" else a2
			if fc["planar"]:
				var n2: Vector3 = fc["normal"]
				out.append(I18n.t("Normal mesafe: ") + Units.format_length(absf(n2.dot((vtx["p"] as Vector3) - (fc["point"] as Vector3)))))
			out.append(I18n.t("Yüz alanı: ") + Units.format_area(fc["area"]))
		else:
			if a2["planar"] and b2["planar"]:
				var n3: Vector3 = a2["normal"]
				var n4: Vector3 = b2["normal"]
				if absf(n3.dot(n4)) > 0.99999:
					out.append(I18n.t("Mesafe (paralel yüzler): ") + Units.format_length(absf(n3.dot((b2["point"] as Vector3) - (a2["point"] as Vector3)))))
				else:
					out.append("Açı: " + Units.format_angle(rad_to_deg(acos(clampf(n3.dot(n4), -1.0, 1.0)))))
			out.append(I18n.t("Toplam alan: ") + Units.format_area(float(a2["area"]) + float(b2["area"])))
	return out


func _show_measure_panel() -> void:
	panel.clear()
	panel.title("Ölç", Icons.get_icon("measure", 22))
	panel.button("Kapat", func(): _leave_aux_mode(), Icons.get_icon("exit_sketch", 18))
	if _measure_picks.is_empty():
		panel.info("Model üzerinde bir yüze veya köşe noktasına tıklayın. İkinci seçimle mesafe veya açı ölçülür. Boş yere tıklamak seçimi temizler.")
		return
	panel.section(I18n.t("Seçim: %d") % _measure_picks.size())
	var res := _measure_results()
	panel.info("\n".join(res), Color(0.95, 0.85, 0.95))
	panel.button("Panoya kopyala", func(): DisplayServer.clipboard_set("\n".join(res)))
	panel.button("Seçimi temizle", _clear_measure)


func _clear_measure() -> void:
	_measure_picks.clear()
	_update_measure_visuals()
	_refresh_panel()


# ---------------------------------------------------------------- Kütle özellikleri

func _compute_mass() -> void:
	if viewport.model.is_empty():
		_mass_result = {}
		return
	_mass_result = viewport.model.mass_properties(Materials.density_of(doc.material))
	_apply_mass_csys()
	_draw_mass_marker()


func _draw_mass_marker() -> void:
	var lb := LineBuilder.new()
	if mode == "mass" and not _mass_result.is_empty():
		var c: Vector3 = _mass_result["center"]
		var w := viewport.camera.world_per_pixel()
		var s := 14.0 * w
		var col := Color(1.0, 0.2, 0.7)
		lb.line(c - Vector3.RIGHT * s, c + Vector3.RIGHT * s, col)
		lb.line(c - Vector3.UP * s, c + Vector3.UP * s, col)
		lb.line(c - Vector3.BACK * s, c + Vector3.BACK * s, col)
		var b := viewport.camera.orient
		var d := 5.0 * w
		lb.quad(c, b.x * d, b.y * d, col)
	lb.commit(viewport.overlay_mi.mesh)


func _mass_text() -> String:
	var m := _mass_result
	if m.is_empty():
		return ""
	var t: Array = m["tensor"]
	var pm: Array = m["principal"]
	var L := Units.length_unit
	var lines := PackedStringArray()
	lines.append(I18n.t("Malzeme: ") + (I18n.t(doc.material) if doc.material != "" else I18n.t("<belirtilmemiş>")))
	lines.append(I18n.t("Yoğunluk = ") + Units.format_density(Materials.density_of(doc.material)))
	lines.append(I18n.t("Kütle = ") + Units.format_mass(m["mass"]))
	lines.append(I18n.t("Hacim = ") + Units.format_volume(m["volume"]))
	lines.append(I18n.t("Yüzey alanı = ") + Units.format_area(m["area"]))
	lines.append(I18n.t("Ağırlık merkezi (%s): X = %s  Y = %s  Z = %s") % [L, Units.format_length(m["cx"], false), Units.format_length(m["cy"], false), Units.format_length(m["cz"], false)])
	lines.append(I18n.t("Atalet tensörü (ağırlık merkezinde, global eksenler):"))
	var names := ["x", "y", "z"]
	for i in 3:
		lines.append("  L%sx = %s   L%sy = %s   L%sz = %s" % [names[i], Units.format_inertia(t[i][0]), names[i], Units.format_inertia(t[i][1]), names[i], Units.format_inertia(t[i][2])])
	lines.append(I18n.t("Asal atalet momentleri: Px = %s   Py = %s   Pz = %s") % [Units.format_inertia(pm[0]), Units.format_inertia(pm[1]), Units.format_inertia(pm[2])])
	return "\n".join(lines)


func _show_mass_panel() -> void:
	panel.clear()
	panel.title("Kütle Özellikleri", Icons.get_icon("mass", 22))
	panel.button("Kapat", func(): _leave_aux_mode(), Icons.get_icon("exit_sketch", 18))
	var m := _mass_result
	if m.is_empty():
		panel.info("Katı model yok.")
		return
	panel.info(I18n.t("Malzeme: ") + (I18n.t(doc.material) if doc.material != "" else I18n.t("<belirtilmemiş>")))
	panel.info(I18n.t("Yoğunluk: ") + Units.format_density(Materials.density_of(doc.material)))
	if doc.material == "":
		panel.info("Malzeme seçilmediği için yoğunluk 1 g/cm³ (su) varsayıldı.", Color(1.0, 0.75, 0.3))
	var css: Array = [-1]
	var csn: Array = [I18n.t("Global (orijin)")]
	for g in doc.features:
		if g.type == "refcsys" and not g.suppressed:
			css.append(g.id)
			csn.append(g.name)
	if css.size() > 1:
		var on_cs := func(i: int) -> void:
			_mass_csys = css[i]
			_compute_mass()
			_refresh_panel()
		panel.option("Koordinat sistemi", csn, maxi(css.find(_mass_csys), 0), on_cs)
	panel.section("Sonuçlar")
	panel.info(I18n.t("Kütle = %s\nHacim = %s\nYüzey alanı = %s") % [Units.format_mass(m["mass"]), Units.format_volume(m["volume"]), Units.format_area(m["area"])])
	panel.section(I18n.t("Ağırlık merkezi (%s)%s") % [Units.length_unit, ("  — " + str(m["csys"])) if m.has("csys") else ""])
	panel.info("X = %s\nY = %s\nZ = %s" % [Units.format_length(m["cx"], false), Units.format_length(m["cy"], false), Units.format_length(m["cz"], false)])
	panel.section(I18n.t("Atalet tensörü (%s·%s²)") % [Units.mass_unit, Units.length_unit])
	var t: Array = m["tensor"]
	var f := func(v: float) -> String: return Units.fmt_sig(v / Units.mass_factor() / pow(Units.factor(), 2), 5)
	panel.info(I18n.t("Lxx = %s   Lxy = %s   Lxz = %s\nLyx = %s   Lyy = %s   Lyz = %s\nLzx = %s   Lzy = %s   Lzz = %s") % [
		f.call(t[0][0]), f.call(t[0][1]), f.call(t[0][2]), f.call(t[1][0]), f.call(t[1][1]), f.call(t[1][2]),
		f.call(t[2][0]), f.call(t[2][1]), f.call(t[2][2])])
	var pm: Array = m["principal"]
	panel.section("Asal atalet momentleri")
	panel.info(I18n.t("Px = %s\nPy = %s\nPz = %s") % [Units.format_inertia(pm[0]), Units.format_inertia(pm[1]), Units.format_inertia(pm[2])])
	panel.button("Panoya kopyala", func(): DisplayServer.clipboard_set(_mass_text()))
	panel.button("Malzemeyi değiştir...", func(): _cmd("material"), Icons.get_icon("material", 18))


# ---------------------------------------------------------------- Malzeme

func _set_material(material_name: String) -> void:
	if material_name == doc.material:
		return
	doc.checkpoint()
	doc.material = material_name
	doc.commit()
	_set_status(I18n.t("Malzeme: ") + (I18n.t(material_name) if material_name != "" else I18n.t("<belirtilmemiş>")))


func _material_ok() -> void:
	var choice := _material_choice
	_set_material(choice)
	_leave_aux_mode()


func _show_material_panel() -> void:
	panel.clear()
	panel.title("Malzeme", Icons.get_icon("material", 22))
	panel.ok_cancel(_material_ok, _leave_aux_mode)
	var names: Array = ["<belirtilmemiş>"]
	var keys: Array = [""]
	for mt in Materials.LIST:
		names.append(I18n.t(str(mt["group"])) + " — " + I18n.t(str(mt["name"])))
		keys.append(mt["name"])
	var sel := maxi(keys.find(_material_choice), 0)
	var on_pick := func(i: int) -> void:
		_material_choice = keys[i]
		viewport.model_mat.albedo_color = Materials.color_of(_material_choice)
		_show_material_panel()
	panel.option("Malzeme", names, sel, on_pick)
	if _material_choice != "":
		panel.info(I18n.t("Yoğunluk: %s (%s g/cm³)") % [Units.format_density(Materials.density_of(_material_choice)), Units.fmt_sig(Materials.density_of(_material_choice), 4)])
	else:
		panel.info("Malzeme yok: kütle hesabında 1 g/cm³ kullanılır.")
	panel.info("Model rengi malzemeye göre önizlenir. Tamam ile parçaya uygulanır.", Color(0.6, 0.65, 0.7))


# ---------------------------------------------------------------- Birimler / Belge özellikleri

func _on_units_menu(id: int) -> void:
	if id == 100:
		_show_doc_props()
		return
	if id < 0 or id >= Units.SYSTEM_ORDER.size():
		return
	var sname: String = Units.SYSTEM_ORDER[id]
	if sname == Units.system:
		return
	doc.checkpoint()
	Units.set_system(sname)
	doc.commit()
	_set_status(I18n.t("Birim sistemi: ") + str(Units.SYSTEMS[sname]["label"]))


var _pd := {}


func _show_doc_props() -> void:
	if props_dialog == null:
		props_dialog = AcceptDialog.new()
		props_dialog.title = "Belge Özellikleri"
		props_dialog.ok_button_text = "Tamam"
		props_dialog.add_cancel_button(I18n.t("İptal"))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 8)
		props_dialog.add_child(grid)
		var add_row := func(label: String, ctrl: Control) -> void:
			var l := Label.new()
			l.text = label
			grid.add_child(l)
			ctrl.custom_minimum_size.x = 260
			grid.add_child(ctrl)
		var sys := OptionButton.new()
		for k in Units.SYSTEM_ORDER:
			sys.add_item(Units.SYSTEMS[k]["label"])
		sys.add_item("Özel")
		add_row.call(I18n.t("Birim sistemi"), sys)
		var len_ob := OptionButton.new()
		for u in Units.LENGTH_ORDER:
			len_ob.add_item(u)
		add_row.call(I18n.t("Uzunluk birimi"), len_ob)
		var mass_ob := OptionButton.new()
		for u in Units.MASS_ORDER:
			mass_ob.add_item(u)
		add_row.call(I18n.t("Kütle birimi"), mass_ob)
		var dec := SpinBox.new()
		dec.min_value = 0
		dec.max_value = 8
		add_row.call(I18n.t("Uzunluk ondalık basamak"), dec)
		var adec := SpinBox.new()
		adec.min_value = 0
		adec.max_value = 6
		add_row.call(I18n.t("Açı ondalık basamak"), adec)
		var mat := OptionButton.new()
		mat.add_item("<belirtilmemiş>")
		for nm in Materials.names():
			mat.add_item(nm)
		add_row.call("Malzeme", mat)
		_pd = {"sys": sys, "len": len_ob, "mass": mass_ob, "dec": dec, "adec": adec, "mat": mat}
		var on_sys := func(i: int) -> void:
			if i < Units.SYSTEM_ORDER.size():
				var s: Dictionary = Units.SYSTEMS[Units.SYSTEM_ORDER[i]]
				len_ob.selected = Units.LENGTH_ORDER.find(s["length"])
				mass_ob.selected = Units.MASS_ORDER.find(s["mass"])
				dec.value = s["decimals"]
		sys.item_selected.connect(on_sys)
		var to_custom := func(_i: int) -> void:
			var lu: String = Units.LENGTH_ORDER[len_ob.selected]
			var mu: String = Units.MASS_ORDER[mass_ob.selected]
			sys.selected = Units.SYSTEM_ORDER.size()
			for k in Units.SYSTEM_ORDER.size():
				var s2: Dictionary = Units.SYSTEMS[Units.SYSTEM_ORDER[k]]
				if s2["length"] == lu and s2["mass"] == mu:
					sys.selected = k
		len_ob.item_selected.connect(to_custom)
		mass_ob.item_selected.connect(to_custom)
		props_dialog.confirmed.connect(_apply_doc_props)
		add_child(props_dialog)
	var sidx := Units.SYSTEM_ORDER.find(Units.system)
	(_pd["sys"] as OptionButton).selected = sidx if sidx >= 0 else Units.SYSTEM_ORDER.size()
	(_pd["len"] as OptionButton).selected = Units.LENGTH_ORDER.find(Units.length_unit)
	(_pd["mass"] as OptionButton).selected = Units.MASS_ORDER.find(Units.mass_unit)
	(_pd["dec"] as SpinBox).value = Units.decimals
	(_pd["adec"] as SpinBox).value = Units.angle_decimals
	(_pd["mat"] as OptionButton).selected = Materials.names().find(doc.material) + 1
	props_dialog.popup_centered(Vector2i(460, 300))


func _apply_doc_props() -> void:
	var sys: OptionButton = _pd["sys"]
	var lu: String = Units.LENGTH_ORDER[(_pd["len"] as OptionButton).selected]
	var mu: String = Units.MASS_ORDER[(_pd["mass"] as OptionButton).selected]
	var mat_i := (_pd["mat"] as OptionButton).selected
	doc.checkpoint()
	if sys.selected < Units.SYSTEM_ORDER.size():
		Units.set_system(Units.SYSTEM_ORDER[sys.selected])
	Units.set_custom(lu, mu)
	Units.decimals = int((_pd["dec"] as SpinBox).value)
	Units.angle_decimals = int((_pd["adec"] as SpinBox).value)
	doc.material = "" if mat_i <= 0 else str(Materials.names()[mat_i - 1])
	doc.commit()
	_set_status(I18n.t("Belge özellikleri güncellendi: ") + Units.system_short())


# ================================================================ GÖRÜNÜM

func _fit(animate: bool) -> void:
	if mode == "assembly":
		asm_mode.fit(animate)
		return
	var box := viewport.model_aabb()
	for f in doc.sketches():
		if f.sketch.is_empty() or f.suppressed:
			continue
		var r: Rect2 = f.sketch.bounds()
		for c in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
			box = box.expand(f.plane.to_world(c))
	if viewport.model.is_empty() and doc.sketches().is_empty():
		box = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	viewport.camera.fit(box, animate)


func _normal_to() -> void:
	if mode == "sketch":
		editor.look_at_plane()
		return
	var k: String = selection.get("kind", "")
	var b: Basis
	if k == "plane":
		b = SketchPlane.standard(selection["id"]).basis()
	elif k == "face":
		b = SketchPlane.from_face(selection["point"], selection["normal"]).basis()
	elif k == "feature":
		var f := doc.get_feature(int(selection["id"]))
		if f and f.is_sketch():
			b = f.plane.basis()
		else:
			_set_status("Düzleme dik görünüm için bir düzlem, yüz veya taslak seçin.")
			return
	else:
		_set_status("Düzleme dik görünüm için bir düzlem, yüz veya taslak seçin.")
		return
	viewport.camera.animate_to(b, viewport.camera.target, viewport.camera.view_size)


# ================================================================ DOSYA

func _ask_discard(action: Callable) -> void:
	var asm_dirty: bool = asm_mode.is_open() and asm_mode.asm.dirty and mode == "assembly"
	if not doc.dirty and not asm_dirty:
		action.call()
		return
	_confirm_action = action
	confirm_dialog.dialog_text = I18n.t("Kaydedilmemiş değişiklikler kaybolacak. Devam edilsin mi?")
	confirm_dialog.popup_centered()


func _new_document() -> void:
	_close_assembly_ui()
	if mode == "sketch":
		editor.end()
	if mode == "sketch3d":
		editor3d.end()
	_leave_aux_mode()
	mode = "idle"
	editing = null
	selection = {}
	_show_toolbar(0)
	doc.clear()
	autosave.clear("part")
	viewport.camera.animate_to(CadCamera.standard_basis("iso"), Vector3.ZERO, 200.0)
	_set_status("Yeni parça.")


func _load_demo(nameplate := false) -> void:
	if mode == "sketch":
		editor.end()
	if mode == "sketch3d":
		editor3d.end()
	_leave_aux_mode()
	mode = "idle"
	editing = null
	selection = {}
	_show_toolbar(0)
	if nameplate:
		DemoParts.build_nameplate(doc)
	else:
		DemoParts.build_bracket(doc)
	doc.file_path = ""
	_fit_after_build = true
	viewport.camera.orient = CadCamera.standard_basis("iso")
	doc.changed.emit()
	if nameplate:
		_set_status("İsim plakası: köşe yuvarlatma, altıgen, kanal, spline ve metin. Genişliği Denklemler panelinden değiştirin.")
	else:
		_set_status("Örnek parça yüklendi: plaka, silindir, döndürülmüş yaka, kanal ve delik.")


func _save() -> void:
	if doc.file_path == "":
		_cmd("save_as")
		return
	_backup_before_save(doc.file_path)
	var err := doc.save_to(doc.file_path)
	_set_status((I18n.t("Kaydedildi: ") + doc.file_path) if err == OK else (I18n.t("Kaydedilemedi! Hata kodu: %d") % err))
	if err == OK:
		_note_file(doc.file_path, "part")


func _file_dialog(save: bool, filters: Array, title: String, action: String, default_name := "") -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	var tf := PackedStringArray()
	for fl in filters:
		tf.append(I18n.t(str(fl)))
	file_dialog.filters = tf
	file_dialog.title = I18n.t(title)
	file_dialog.current_file = default_name
	_pending_file_action = action
	file_dialog.popup_centered_ratio(0.6)


static func _ensure_ext(path: String, ext: String) -> String:
	if path.get_extension().to_lower() != ext:
		return path + "." + ext
	return path


func _on_file_selected(path: String) -> void:
	var err := OK
	if _pending_file_action.begins_with("exp:"):
		_export_write(_pending_file_action.substr(4), path)
		return
	match _pending_file_action:
		"sm_dxf", "weld_csv", "cfg_csv_out", "cfg_csv_in", "cam_nc", "render_png", "render_hdri", "decal_img":
			special.on_file(_pending_file_action, path)
			return
		"macro_run":
			_run_macro(path)
			return
		"macro_save":
			path = _ensure_ext(path, "gd")
			var fm := FileAccess.open(path, FileAccess.WRITE)
			if fm == null:
				err = FileAccess.get_open_error()
			else:
				fm.store_string(_macro_src)
				fm.close()
		"asm_insert", "asm_save", "asm_step", "asm_bom_csv", "asm_newpart":
			asm_mode.on_file(_pending_file_action, path)
			return
		"open":
			var oext := path.get_extension().to_lower()
			if oext in ["dasm", "dasmt"]:
				if mode == "sketch":
					editor.end()
				if mode == "sketch3d":
					editor3d.end()
				_leave_aux_mode()
				var aerr := asm_mode.open_file(path)
				_set_status((I18n.t("Montaj açıldı: ") + path) if aerr == OK else (I18n.t("Montaj açılamadı (hata %d): %s") % [aerr, path]))
				if aerr == OK and oext == "dasmt":
					# şablon: yeni (adsız) montaj olarak başlar
					asm_mode.asm.file_path = ""
					asm_mode.asm.name = "Montaj1"
					asm_mode.update_title()
				elif aerr == OK:
					_note_file(path, "asm")
				return
			_close_assembly_ui()
			if mode == "sketch":
				editor.end()
			if mode == "sketch3d":
				editor3d.end()
			_leave_aux_mode()
			mode = "idle"
			selection = {}
			_show_toolbar(0)
			err = doc.load_from(path)
			if err == OK:
				_fit_after_build = true
				_set_status(I18n.t("Açıldı: ") + path)
				if oext in ["dcadt", "ddrwt"]:
					# şablon: yeni (adsız) belge olarak başlar
					doc.file_path = ""
					doc.part_name = "Parça1"
					_update_title()
				else:
					_note_file(path, "part")
				if oext in ["ddrw", "ddrwt"]:
					_show_toolbar.call_deferred(3)
			else:
				_set_status(I18n.t("Dosya açılamadı (hata %d): %s") % [err, path])
			return
		"save":
			path = _ensure_ext(path, "dcad")
			_backup_before_save(path)
			err = doc.save_to(path)
			if err == OK:
				_note_file(path, "part")
		"stl":
			path = _ensure_ext(path, "stl")
			if viewport.kernel.is_brep() and viewport.kernel.occ.is_ready():
				var q: Array = STL_PRESETS[_stl_quality]
				viewport.kernel.request_export("stl", path, {"lin": q[1], "ang_deg": q[2], "ascii": _stl_ascii})
				_set_status(I18n.t("STL yazılıyor (%s kalite)...") % q[0])
				return
			err = Exporters.write_stl(path, viewport.model.ccw_triangles(), doc.part_name)
		"step", "iges":
			var ext := "step" if _pending_file_action == "step" else "igs"
			if not (path.get_extension().to_lower() in ["step", "stp", "iges", "igs"]):
				path += "." + ext
			viewport.kernel.request_export(_pending_file_action, path)
			_set_status(I18n.t("Dışa aktarılıyor: ") + path)
			return
		"import":
			_import_body(path)
			return
		"obj":
			path = _ensure_ext(path, "obj")
			err = Exporters.write_obj(path, viewport.model, doc.part_name)
		"dxf":
			path = _ensure_ext(path, "dxf")
			var sk := _sketch_for_export()
			err = Exporters.write_dxf(path, sk.sketch) if sk else ERR_INVALID_DATA
		"svg":
			path = _ensure_ext(path, "svg")
			var sk2 := _sketch_for_export()
			err = Exporters.write_svg(path, sk2.sketch) if sk2 else ERR_INVALID_DATA
		"png":
			path = _ensure_ext(path, "png")
			err = viewport.screenshot(path)
		"dw_pdf", "dw_svg", "dw_dxf":
			path = _ensure_ext(path, _pending_file_action.substr(3))
			err = _dw_export(_pending_file_action, path)
	_set_status((I18n.t("Kaydedildi: ") + path) if err == OK else ("Yazılamadı (hata %d): %s" % [err, path]))


func _request_quit() -> void:
	_ask_discard(_quit_now)


func _quit_now() -> void:
	autosave.clear_all()
	get_tree().quit()


func _new_assembly() -> void:
	autosave.clear("asm")
	asm_mode.new_assembly()


# ---------------------------------------------------------------- son dosyalar, yedek, kurtarma (Faz 9)

## Başarılı aç / kaydet sonrası: son dosyalara ekle, o türün otomatik kaydını sil
func _note_file(path: String, kind: String) -> void:
	AppSettings.add_recent(path)
	if autosave:
		autosave.clear(kind)
	_refresh_recent_menu()


func _backup_before_save(path: String) -> void:
	if bool(AppSettings.get_v("autosave", "backup")) and FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")


func _refresh_recent_menu() -> void:
	if recent_menu == null:
		return
	recent_menu.clear()
	var lst := AppSettings.recent()
	if lst.is_empty():
		recent_menu.add_item("(liste boş)", 998)
		recent_menu.set_item_disabled(0, true)
		return
	for i in lst.size():
		var p: String = lst[i]
		recent_menu.add_item("%d  %s   —   %s" % [i + 1, p.get_file(), p.get_base_dir()], i)
		recent_menu.set_item_tooltip(i, p)
	recent_menu.add_separator()
	recent_menu.add_item("Listeyi temizle", 999)


func _on_recent_id(id: int) -> void:
	if id == 999:
		AppSettings.clear_recent()
		_refresh_recent_menu()
		_refresh_panel()
		return
	var lst := AppSettings.recent()
	if id >= 0 and id < lst.size():
		open_recent(lst[id])


func open_recent(path: String) -> void:
	if not FileAccess.file_exists(path):
		AppSettings.remove_recent(path)
		_refresh_recent_menu()
		_set_status(I18n.t("Dosya bulunamadı, listeden çıkarıldı: ") + path)
		return
	_ask_discard(_open_path.bind(path))


func _open_path(path: String) -> void:
	_pending_file_action = "open"
	_on_file_selected(path)


func _check_recovery() -> void:
	var recs := Autosave.pending()
	if recs.is_empty():
		return
	_recovery_rec = recs[0]
	if recovery_dialog == null:
		recovery_dialog = ConfirmationDialog.new()
		recovery_dialog.title = APP_NAME + I18n.t(" — Belge kurtarma")
		recovery_dialog.ok_button_text = "Kurtar"
		recovery_dialog.cancel_button_text = "Kaydı sil"
		recovery_dialog.confirmed.connect(func(): recover(_recovery_rec))
		recovery_dialog.canceled.connect(_on_recovery_canceled)
		add_child(recovery_dialog)
	var t := Time.get_datetime_string_from_unix_time(int(float(_recovery_rec.get("time", 0))) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60, true)
	var kind_s := I18n.t("montaj") if str(_recovery_rec.get("kind", "")) == "asm" else I18n.t("parça")
	var src := str(_recovery_rec.get("source", ""))
	recovery_dialog.dialog_text = I18n.t("Önceki oturum beklenmedik şekilde kapandı.\n\nOtomatik kaydedilmiş %s bulundu: %s\nKayıt zamanı: %s\n%s\n\nKurtarılsın mı?") % [
		kind_s, str(_recovery_rec.get("name", "?")), t, (I18n.t("Dosya: ") + src) if src != "" else I18n.t("(hiç kaydedilmemiş belge)")]
	recovery_dialog.popup_centered()


## Makro dosyasını çalıştır (Araçlar → Makro çalıştır, komut satırı --macro=)
func _run_macro(path: String) -> void:
	_set_status(I18n.t("Makro çalışıyor: ") + path.get_file())
	var r: Dictionary = await macro.run_file(path)
	if not bool(r.get("ok", false)):
		_set_status(I18n.t("Makro hatası: ") + str(r.get("error", "")))
		return
	var msgs: PackedStringArray = r.get("messages", PackedStringArray())
	_set_status(I18n.t("Makro bitti: ") + "%s%s" % [path.get_file(), (" — " + msgs[msgs.size() - 1]) if not msgs.is_empty() else ""])


func _on_recovery_canceled() -> void:
	Autosave.discard(_recovery_rec)
	_check_recovery.call_deferred()


## Otomatik kayıttan belge kurtar (kurtarma kaydı silinir; belge kirli kalır)
func recover(rec: Dictionary) -> void:
	var data: Dictionary = rec.get("data", {})
	if str(rec.get("kind", "")) == "asm":
		var a := CadAssembly.new()
		a.load_dict(data)
		a.file_path = str(rec.get("source", ""))
		a.name = str(rec.get("name", a.name))
		asm_mode.open_recovered(a)
	else:
		_close_assembly_ui()
		if mode == "sketch":
			editor.end()
		_leave_aux_mode()
		mode = "idle"
		selection = {}
		_show_toolbar(0)
		doc.load_dict(data)
		doc.file_path = str(rec.get("source", ""))
		doc.part_name = str(rec.get("name", doc.part_name))
		doc.dirty = true
		_fit_after_build = true
		doc.changed.emit()
	Autosave.discard(rec)
	_set_status(I18n.t("Belge kurtarıldı: %s — kaydetmeyi unutmayın.") % str(rec.get("name", "")))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_quit()


func _show_help() -> void:
	info_dialog.dialog_text = """FARE
  Orta tuş sürükle ............ döndür
  Sağ tuş sürükle ............. döndür
  Ctrl + orta/sağ tuş ......... kaydır
  Shift + orta tuş ............ yakınlaştır
  Tekerlek .................... imlece doğru yakınlaştır
  Sol tık ..................... seç   (çift tık: düzenle)

KLAVYE
  F ........................... ekrana sığdır
  Ctrl+1..7 ................... Ön, Arka, Sol, Sağ, Üst, Alt, İzometrik
  Ctrl+8 ...................... düzleme dik görünüm
  Ok tuşları .................. görünümü 15° döndür
  Ctrl+Z / Ctrl+Y ............. geri al / yinele
  Ctrl+S / Ctrl+O / Ctrl+N .... kaydet / aç / yeni
  Ctrl+E ...................... Dışa Aktar (tüm formatlar)
  Delete ...................... sil      F2: yeniden adlandır
  Esc ......................... iptal / araçtan çık
  Enter ....................... özellik panelinde Tamam

TASLAK MODU
  L çizgi   N merkez çizgisi   R dikdörtgen   C daire   A yay
  D Akıllı Boyut   S seç   G ızgara yakalama
  P çokgen   T kırp   E uzat
  Boyut kutusuna =ifade yazınca denklem bağlanır (ör. =genislik/2)
  Çift tık / sağ tık: çizgi zincirini bitir
  Boyut etiketine çift tık: değeri değiştir
  Shift/Ctrl + tık: çoklu seçim → panelden ilişki ekle
  Mavi = eksik tanımlı, siyah = tam tanımlı, kırmızı = aşırı tanımlı

MONTAJ (Dosya → Yeni Montaj / .dasm)
  Bileşen Ekle: parça dosyası; ilk bileşen sabittir (f), eksik tanımlı (-)
  Sol tuşla sürükle: bileşeni eşleştirmelere uyarak taşı
  Eşleştir: yüz/kenarlara tıkla → türü seç (★ önerilen)
  Bileşene çift tık (ağaç): parçayı düzenle; 'Montaj' sekmesi: geri dön
  Yeni Parça: montaj içinde parça (diğer bileşenler yarı saydam, yüzlerine taslak)
  Bileşen Çoğaltma, alt montaj (.dasm ekle), Teknik Resim sekmesi: montaj resmi
  Büyük montajlar: otomatik LOD; büyük montaj modunda kenarlar yalnız seçimde

SAC METAL / KAYNAKLAR (sekmeler)
  Taban Flanş: kapalı profil → plaka, açık çizgi zinciri → bükümlü sac
  Kenar Flanş: taban kenarlarına tıkla; Açınım: düz sac, Açınım DXF: büküm çizgileriyle
  Yapısal Üye: taslak / 3B taslak çizgilerine profil; Kesim Listesi (CSV)
  Değerlendir → Konfigürasyon: boyut / bastırma setleri, tasarım tablosu (CSV)
  Yüzeyler: ekstrüde / döndürülmüş / loft / düzlemsel yüzey, dikme, kalınlaştır, kırp
  Analiz: statik FEA (sabit + yük yüzlerine tıkla), eğim analizi, CAM G-kod, görselleştirme

SEÇENEKLER VE MAKROLAR (Araçlar menüsü)
  Seçenekler: dil, tema, arayüz ölçeği, otomatik kaydetme, yedek
  Klavye kısayolları: komuta çift tıkla, tuşa bas (her komut atanabilir)
  Fare hareketleri: sağ tuşu basılı tut + yöne çek → komut halkası
  Makro çalıştır / kaydı başlat-durdur / parçayı makro olarak kaydet
  Eklentiler: plugins/ klasörü, 'Eklentiler' sekmesi; Seçenekler'den aç / kapat
  Dosya → Son Dosyalar; çökmeden sonra açılışta belge kurtarma

TEKNİK RESİM (sekme)
  İlk girişte A3 sayfa + standart 3 görünüş ve izometrik otomatik
  Sol tık: seç / yerleştir   Sürükle: görünüş veya açıklamayı taşı
  Tekerlek: yakınlaştır   Sağ/orta tuş: kaydır   F: sayfaya sığdır
  Delete: seçili görünüş/açıklamayı sil   Esc: aracı bırak / seçimi kaldır
  Dışa Aktar (Ctrl+E): PDF, DXF, SVG, AI, resimler (DWG için DXF'i AutoCAD / ODA ile dönüştürün)"""
	var hp := "res://i18n/help_%s.txt" % I18n.current
	if I18n.current != "tr" and FileAccess.file_exists(hp):
		info_dialog.dialog_text = FileAccess.get_file_as_string(hp)
	info_dialog.popup_centered()


# ================================================================ KLAVYE

## Tab, arayüzde odak gezinmesine gitmeden önce 3B taslakta düzlem değiştirmek için yakalanır.
func _input(event: InputEvent) -> void:
	if mode != "sketch3d":
		return
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_TAB:
		var fo := get_viewport().gui_get_focus_owner()
		if fo is LineEdit:
			return
		editor3d.cycle_plane()
		_refresh_panel()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	var ctrl := k.ctrl_pressed or k.meta_pressed
	var code := k.keycode
	var handled := true
	var sc := Keymap.shortcut_of(k)
	var cmd := ""
	if sc != "" and (ctrl or not k.echo):
		if mode == "sketch":
			cmd = keymap.find("sketch", sc)
		if cmd == "":
			cmd = keymap.find("global", sc)
	if cmd != "":
		if not run_command(cmd):
			_cmd(cmd)
	elif k.echo:
		handled = false
	elif code == KEY_TAB and mode == "sketch3d":
		editor3d.cycle_plane()
		_refresh_panel()
	elif code == KEY_ESCAPE:
		_escape()
	elif code == KEY_ENTER or code == KEY_KP_ENTER:
		if mode == "feature":
			_ok_feature()
		elif mode == "sketch":
			editor.cancel()
	elif code == KEY_LEFT:
		viewport.camera.rotate_step("yaw", -15)
	elif code == KEY_RIGHT:
		viewport.camera.rotate_step("yaw", 15)
	elif code == KEY_UP:
		viewport.camera.rotate_step("pitch", -15)
	elif code == KEY_DOWN:
		viewport.camera.rotate_step("pitch", 15)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _escape() -> void:
	if _pick_for_sketch:
		_pick_for_sketch = false
		viewport.force_planes = false
		viewport.draw_planes()
	match mode:
		"sketch3d":
			if not editor3d.cancel():
				_exit_sketch3d()
		"sketch":
			if _sketch_op != "":
				_cancel_sketch_op()
			elif editor.tool == "select" and not editor.is_busy() and not editor.has_selection():
				_exit_sketch()
			else:
				editor.cancel()
		"feature":
			_cancel_feature()
		"measure", "mass", "material", "cutlist", "configs", "fea", "draft_an", "cam", "render", "plugin":
			_leave_aux_mode()
		"assembly":
			asm_mode.escape()
		"drawing":
			if _dw_tool != "select" or not _dw_pts.is_empty():
				_dw_set_tool("select")
			else:
				_dw_sel = {}
				_dw_render()
				_refresh_panel()
		_:
			_select({})


# ================================================================ KOMUT SATIRI

## Komut satırı kullanıcı argümanı değeri (--ad=değer), yoksa ""
func _arg_value(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


func _handle_cmdline() -> void:
	var args := OS.get_cmdline_user_args()
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.get_extension().to_lower() == "dcad" and FileAccess.file_exists(a):
			doc.load_from(a)
			_fit_after_build = true
			AppSettings.add_recent(a)
		elif a.get_extension().to_lower() in ["dasm", "dasmt", "ddrw", "dcadt", "ddrwt", "dclfp", "dcftp"] and FileAccess.file_exists(a):
			_open_path.call_deferred(a)
	for a in args:
		if a == "--demo":
			DemoParts.build_bracket(doc)
			_fit_after_build = true
		elif a == "--demo2":
			DemoParts.build_nameplate(doc)
			_fit_after_build = true
		elif a.begins_with("--macro="):
			_cmdline_macro = a.substr(8)
		elif a.begins_with("--open="):
			doc.load_from(a.substr(7))
			_fit_after_build = true
		elif a.begins_with("--shot="):
			_shot_path = a.substr(7)
			_test_mode = true
		elif a.begins_with("--shot-mode="):
			_shot_mode = a.substr(12)
		elif a == "--uitest":
			_test_mode = true
			var t: Node = load("res://tests/ui_flow.gd").new()
			t.set("app", self)
			add_child(t)


func _process(_delta: float) -> void:
	if _shot_path == "" or not _built_once:
		return
	if viewport.kernel.is_busy() or viewport.camera.is_animating() or _dw_pending > 0 or asm_mode._pending > 0:
		return
	if (_shot_mode.begins_with("asm_demo") or _shot_mode in ["asm_drawing", "sm_demo", "sm_flat", "weld_demo", "surf_demo", "fea_demo", "export"]) and viewport.kernel.mode != "csg" and viewport.kernel.occ.state == "starting":
		return
	if special.fea_busy:
		return
	_shot_frames += 1
	if _shot_frames == 3 and _shot_mode != "":
		_setup_shot_mode()
	if _shot_mode == "sm_demo" and _shot_frames == 10:
		special.demo("sheet", 2)
	if _shot_mode == "sm_flat" and _shot_frames == 10:
		special.demo("sheet", 2)
	if _shot_mode == "sm_flat" and _shot_frames == 20:
		special.cmd("sm_flat")
	if _shot_mode == "asm_drawing" and _shot_frames == 10:
		asm_mode.finish_demo()
		_show_toolbar(3)
	if _shot_mode == "asm_drawing" and _shot_frames == 20:
		_dw_cmd("dw_autoballoon")
	if _shot_mode.begins_with("asm_demo") and _shot_frames == 10:
		asm_mode.finish_demo()
		if _shot_mode == "asm_demo_explode":
			asm_mode.cmd("asm_explode_toggle")
	if _shot_mode == "fea_demo" and _shot_frames == 10:
		special.demo("fea", 2)
	if _shot_mode == "surf_demo" and _shot_frames == 10:
		_show_toolbar(7)
	if _shot_mode in ["draft_demo", "cam_demo", "render_demo"] and _shot_frames == 10:
		_show_toolbar(8)
		if _shot_mode == "render_demo":
			special.render_st["env"] = "studio"
		if _shot_mode == "cam_demo":
			special.cam_st.merge({"depth": 30.0, "step": 3.0}, true)
		special.cmd(_shot_mode.trim_suffix("_demo").replace("draft", "draft_an"))
	if _shot_mode == "drawing_demo" and _shot_frames == 10:
		_dw_demo(1)
	if _shot_mode == "drawing_demo" and _shot_frames == 20:
		_dw_demo(2)
	if _shot_frames < 30:
		return
	var err := get_viewport().get_texture().get_image().save_png(_shot_path)
	print("SHOT ", _shot_path, " err=", err)
	if _shot_mode == "drawing_demo" or _shot_mode == "asm_drawing":
		for k: String in ["dw_pdf", "dw_svg", "dw_dxf"]:
			var ep := _shot_path.get_basename() + "." + k.substr(3)
			print("SHOT ", ep, " err=", _dw_export(k, ep))
	_shot_path = ""
	get_tree().quit()


func _setup_shot_mode() -> void:
	if _shot_mode in ["sm_demo", "sm_flat"]:
		special.demo("sheet", 1)
		_fit_after_build = true
		return
	if _shot_mode == "weld_demo":
		special.demo("weld", 1)
		_fit_after_build = true
		return
	if _shot_mode in ["surf_demo", "fea_demo"]:
		special.demo(_shot_mode.trim_suffix("_demo"), 1)
		_fit_after_build = true
		return
	if _shot_mode.begins_with("asm_demo") or _shot_mode == "asm_drawing":
		asm_mode.build_demo()
		return
	if _shot_mode == "drawing" or _shot_mode == "drawing_demo":
		_show_toolbar(3)
		return
	if _shot_mode.begins_with("view_"):
		viewport.camera.set_standard_view(_shot_mode.substr(5), false)
		_fit(false)
		return
	match _shot_mode:
		"options_keys", "options_mouse", "options_general":
			show_options({"options_general": 0, "options_keys": 1, "options_mouse": 2}[_shot_mode])
		"export":
			export_dlg.open(_export_reason, "step214")
		"plugin_info":
			_show_toolbar(9)
			run_command("plg_parca_bilgisi")
		"gesture":
			var gc: Vector2 = viewport.size * 0.5
			_on_gesture("begin", gc)
			_on_gesture("move", gc + Vector2(60, -60))
		"sketch":
			for f in doc.sketches():
				if f.sketch.entities.size() >= 4:
					_edit_sketch(f)
					editor.select_entity(f.sketch.entities[0]["id"])
					_refresh_panel()
					editor.redraw()
					break
		"face":
			var r := viewport.ray(viewport.container.size * 0.5)
			var hit := viewport.model.raycast(r[0], r[1])
			if not hit.is_empty():
				_pick_at(viewport.container.size * 0.5, false)
		"extrude":
			for f in doc.features:
				if f.type == "extrude":
					_edit_feature(f)
					break
		"mass":
			_cmd("mass")
		"brep_edit":
			for f in doc.features:
				if f.is_brep_feature():
					_edit_feature(f)
					break
		"sketch_slot":
			for f in doc.sketches():
				if f.sketch.entities.size() == 4 and not f.sketch.groups.size():
					_edit_sketch(f)
					break
		"units":
			_on_units_menu(3)
			for f in doc.sketches():
				if f.sketch.entities.size() >= 4:
					_edit_sketch(f)
					break


# ================================================================ B-REP ÖZELLİKLERİ (Faz 4)

func _cmd_brep_feature(type: String) -> void:
	var pre := selection.duplicate()
	_exit_sketch3d()
	if mode == "sketch":
		_exit_sketch()
	if mode == "feature":
		_cancel_feature()
	_leave_aux_mode()
	if not viewport.kernel.is_brep():
		_set_status("Bu özellik OpenCASCADE (B-rep) çekirdeği gerektirir: Araçlar → Geometri çekirdeği.")
		return
	if viewport.model.is_empty():
		_set_status("Önce bir katı model oluşturun (ör. Ekstrüzyon).")
		return
	var f := CadFeature.new()
	f.id = 0
	f.type = type
	match type:
		"fillet":
			f.params = {"r": 2.0, "edges": []}
		"chamfer":
			f.params = {"d": 1.0, "edges": []}
		"shell":
			f.params = {"t": 1.0, "faces": [], "outward": false}
		"draft":
			f.params = {"angle": 3.0, "faces": [], "neutral": {}, "reverse": false}
		"combine":
			f.params = {"op": "add", "bodies": []}
		"move_body":
			f.params = {"body": {}, "t": [0.0, 0.0, 0.0], "axis": "y", "angle": 0.0, "copy": false}
		"split":
			f.params = {"plane": "front", "offset": 0.0, "keep": "both"}
		"hole":
			f.params = {"std": "ISO", "htype": "simple", "size": "M6", "fit": "normal", "end": "through", "depth": 10.0, "face": {}, "points": []}
		"dome":
			f.params = {"face": {}, "height": 5.0}
	f.name = f.type_label()
	_draft_neutral_pick = false
	editing = f
	editing_is_new = true
	mode = "feature"
	_region_pick = false
	_brep_show_result = false
	_hover_edge = -1
	selection = {}
	viewport.clear_face_highlight()
	# Önceden seçili yüz: yuvarlatma/pah için tüm kenarları, kabuk için kaldırılacak yüz olur
	if pre.get("kind", "") == "face" and int(pre.get("face", -1)) >= 0:
		_toggle_brep_face(int(pre["face"]), pre.get("hit", pre["point"]), pre.get("normal", Vector3.ZERO))
	_preview()
	_show_feature_panel()
	match type:
		"shell":
			_set_status("Kabuk: açık kalacak yüzlere tıklayın (tekrar tıklamak kaldırır), kalınlığı panelden girin.")
		"draft":
			_set_status("Eğim: eğim verilecek yüzlere tıklayın; tarafsız yüz için paneldeki düğmeyi kullanın.")
		"combine":
			_set_status("Gövdeleri Birleştir: gövdelere tıklayın (ilk tıklanan ana gövde).")
		"move_body":
			_set_status("Gövde Taşı/Kopyala: taşınacak gövdeye tıklayın, ötelemeyi ve dönmeyi panelden girin.")
		"split":
			_set_status("Böl: bölme düzlemini ve korunacak tarafı panelden seçin.")
		"hole":
			_set_status("Delik Sihirbazı: düzlemsel bir yüzde delik konumlarına tıklayın; ölçüyü panelden seçin.")
		"dome":
			_set_status("Kubbe: düzlemsel bir yüze tıklayın.")
		_:
			_set_status(I18n.t("%s: kenarlara tıklayın (yüze tıklamak tüm kenarlarını ekler); tekrar tıklamak kaldırır.") % f.type_label())


static func _arr3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _edge_id_of_ref(ref: Dictionary) -> int:
	var m := ModelMesh._v3(ref["m"])
	var best := -1
	var bd := 1e-3
	for e in viewport.model.brep_edges:
		var d := ModelMesh._v3(e["m"]).distance_to(m)
		if d < bd:
			bd = d
			best = int(e["id"])
	return best


## Kayıtlı yüz başvurusunun (nokta + normal) gösterilen modeldeki yüz kimliği.
func _face_id_of_ref(ref: Dictionary) -> int:
	var m := viewport.model
	var p := ModelMesh._v3(ref["p"])
	var n := ModelMesh._v3(ref.get("n", [0, 0, 0]))
	if n.length_squared() < 1e-12:
		n = Vector3.UP
	var from := p + n * 0.05
	var best := -1
	var bd := 0.2
	for ti in m.tri_count():
		var hit = Geometry3D.ray_intersects_triangle(from, -n, m.verts[m.tris[ti * 3]], m.verts[m.tris[ti * 3 + 1]], m.verts[m.tris[ti * 3 + 2]])
		if hit != null:
			var d: float = (hit as Vector3).distance_to(p)
			if d < bd:
				bd = d
				best = m.tri_face[ti]
	return best


func _toggle_brep_edge(eid: int) -> void:
	var e: Dictionary = viewport.model.brep_edges[eid]
	var refs: Array = editing.params.get("edges", [])
	for i in refs.size():
		if _edge_id_of_ref(refs[i]) == eid:
			refs.remove_at(i)
			editing.params["edges"] = refs
			return
	refs.append({"m": e["m"], "d": e["d"], "fn": e.get("fn", [])})
	editing.params["edges"] = refs


func _toggle_brep_face(fid: int, hit_point: Variant, hit_normal := Vector3.ZERO) -> void:
	var m := viewport.model
	if fid < 0 or fid >= m.brep_faces.size():
		return
	var info: Dictionary = m.brep_faces[fid]
	var hp: Vector3 = hit_point if hit_point is Vector3 else ModelMesh._v3(hit_point)
	var hn := hit_normal
	if info.has("n"):
		hn = ModelMesh._v3(info["n"])
	elif hn.length_squared() < 1e-12:
		for ti in m.tri_count():
			if m.tri_face[ti] == fid:
				hn = m.normals[ti]
				break
	var ref := {"p": _arr3(hp), "n": _arr3(hn), "name": str(info.get("name", ""))}
	if editing.type == "draft":
		if _draft_neutral_pick:
			if info.get("type", "") != "plane":
				_set_status("Tarafsız yüz düzlemsel olmalı.")
				return
			editing.params["neutral"] = ref
			_draft_neutral_pick = false
			_set_status("Tarafsız yüz seçildi. Şimdi eğim verilecek yüzlere tıklayın.")
			return
		var dfaces: Array = editing.params.get("faces", [])
		for i in dfaces.size():
			if _face_id_of_ref(dfaces[i]) == fid:
				dfaces.remove_at(i)
				editing.params["faces"] = dfaces
				return
		dfaces.append(ref)
		editing.params["faces"] = dfaces
		return
	if editing.type == "combine":
		var b := int(info.get("body", -1))
		var brefs: Array = editing.params.get("bodies", [])
		for i in brefs.size():
			if _body_of_ref(brefs[i]) == b:
				brefs.remove_at(i)
				editing.params["bodies"] = brefs
				return
		brefs.append(ref)
		editing.params["bodies"] = brefs
		return
	if editing.type == "move_body":
		editing.params["body"] = ref
		return
	if editing.type == "hole" or editing.type == "dome":
		if str(info.get("type", "")) != "plane":
			_set_status("Düzlemsel bir yüz seçin.")
			return
		var cur_face: Dictionary = editing.params.get("face", {})
		var same := not cur_face.is_empty() and _face_id_of_ref(cur_face) == fid
		if not same:
			editing.params["face"] = ref
			if editing.type == "hole":
				editing.params["points"] = []
		if editing.type == "hole":
			var pts: Array = editing.params.get("points", [])
			pts.append(_arr3(hp))
			editing.params["points"] = pts
		return
	if editing.type in ["fillet", "chamfer"]:
		var ids: Array = []
		for id0 in info.get("e", []):
			ids.append(int(id0))
		var refs: Array = editing.params.get("edges", [])
		var have := {}
		for r in refs:
			have[_edge_id_of_ref(r)] = true
		var all_in := true
		for id in ids:
			if not have.has(int(id)):
				all_in = false
		if all_in:
			var keep: Array = []
			for r in refs:
				if not (_edge_id_of_ref(r) in ids):
					keep.append(r)
			editing.params["edges"] = keep
		else:
			for id in ids:
				if not have.has(int(id)):
					var e: Dictionary = m.brep_edges[int(id)]
					refs.append({"m": e["m"], "d": e["d"]})
			editing.params["edges"] = refs
	elif editing.type == "shell":
		var faces: Array = editing.params.get("faces", [])
		for i in faces.size():
			if _face_id_of_ref(faces[i]) == fid:
				faces.remove_at(i)
				editing.params["faces"] = faces
				return
		var p: Vector3 = hit_point if hit_point is Vector3 else ModelMesh._v3(hit_point)
		var n := Vector3.ZERO
		if info.has("n"):
			n = ModelMesh._v3(info["n"])
		else:
			for ti in m.tri_count():
				if m.tri_face[ti] == fid:
					n = m.normals[ti]
					break
		faces.append({"p": _arr3(p), "n": _arr3(n)})
		editing.params["faces"] = faces


func _pick_brep(pos: Vector2) -> void:
	if _brep_show_result:
		_set_status("Seçim yapmak için paneldeki 'Sonucu önizle' kutusunu kapatın.")
		return
	if not viewport.model.has_brep():
		return
	var f := editing
	var r := viewport.ray(pos)
	if f.type in ["fillet", "chamfer"]:
		var he := viewport.pick_edge(pos)
		if not he.is_empty():
			_toggle_brep_edge(int(he["edge"]))
		else:
			var hit := viewport.model.raycast(r[0], r[1])
			if hit.is_empty():
				return
			_toggle_brep_face(viewport.model.tri_face[int(hit["tri"])], hit["point"])
	elif f.type == "sm_edge":
		var hs := viewport.pick_edge(pos)
		if hs.is_empty():
			return
		_toggle_brep_edge(int(hs["edge"]))
		special.show_feature_panel(f)
	elif f.type in ["shell", "draft", "combine", "move_body", "hole", "dome"]:
		var hit2 := viewport.model.raycast(r[0], r[1])
		if hit2.is_empty():
			return
		_toggle_brep_face(viewport.model.tri_face[int(hit2["tri"])], hit2["point"], viewport.model.normals[int(hit2["tri"])])
	else:
		return
	_preview()
	_update_brep_highlight()
	_update_brep_counts()


func _update_brep_highlight() -> void:
	if editing == null or not editing.is_brep_feature() or _brep_show_result or not viewport.model.has_brep():
		viewport.set_edge_highlight([])
		if editing and editing.is_brep_feature():
			viewport.clear_face_highlight()
		return
	if editing.type in ["fillet", "chamfer"]:
		var ids: Array = []
		for ref in editing.params.get("edges", []):
			var id := _edge_id_of_ref(ref)
			if id >= 0:
				ids.append(id)
		viewport.set_edge_highlight(ids, _hover_edge)
		viewport.clear_face_highlight()
	elif editing.type in ["hole", "dome"]:
		viewport.set_edge_highlight([])
		var hf: Dictionary = editing.params.get("face", {})
		var hfid := _face_id_of_ref(hf) if not hf.is_empty() else -1
		viewport.set_face_highlight(viewport.model.face_triangles(viewport.model.brep_face_region(hfid)["tris"]) if hfid >= 0 else PackedVector3Array())
		_draw_sketches()
	elif editing.type in ["shell", "draft"]:
		var tris := PackedInt32Array()
		for ref in editing.params.get("faces", []):
			var fid := _face_id_of_ref(ref)
			if fid >= 0:
				tris.append_array(viewport.model.brep_face_region(fid)["tris"])
		viewport.set_face_highlight(viewport.model.face_triangles(tris))
		var nids: Array = []
		var nref: Dictionary = editing.params.get("neutral", {}) if editing.type == "draft" else {}
		if not nref.is_empty():
			var nfid := _face_id_of_ref(nref)
			if nfid >= 0:
				for id0 in (viewport.model.brep_faces[nfid] as Dictionary).get("e", []):
					nids.append(int(id0))
		viewport.set_edge_highlight(nids)
	elif editing.type in ["combine", "move_body"]:
		viewport.set_edge_highlight([])
		var bset := {}
		var refs: Array = editing.params.get("bodies", []) if editing.type == "combine" else ([editing.params["body"]] if not (editing.params.get("body", {}) as Dictionary).is_empty() else [])
		for r0 in refs:
			bset[_body_of_ref(r0)] = true
		var btris := PackedInt32Array()
		for ti in viewport.model.tri_count():
			var fi := viewport.model.tri_face[ti]
			if fi >= 0 and fi < viewport.model.brep_faces.size() and bset.has(int(viewport.model.brep_faces[fi].get("body", -1))):
				btris.append(ti)
		viewport.set_face_highlight(viewport.model.face_triangles(btris))
	else:
		viewport.set_edge_highlight([])
		viewport.clear_face_highlight()


var _brep_count_label: Label = null


func _brep_count_text() -> String:
	if editing == null:
		return ""
	match editing.type:
		"draft":
			var nd: int = (editing.params.get("faces", []) as Array).size()
			var neu := I18n.t("seçili") if not (editing.params.get("neutral", {}) as Dictionary).is_empty() else I18n.t("SEÇİLMEDİ")
			return I18n.t("%d yüz, tarafsız yüz %s") % [nd, neu]
		"combine":
			var nb: int = (editing.params.get("bodies", []) as Array).size()
			return (I18n.t("%d gövde seçili (ilki ana gövde)") % nb) if nb > 0 else I18n.t("Gövde seçilmedi — gövdelere tıklayın")
		"move_body":
			return "Gövde seçili" if not (editing.params.get("body", {}) as Dictionary).is_empty() else I18n.t("Gövde seçilmedi — gövdeye tıklayın")
		"split":
			return ""
		"hole":
			var npt: int = (editing.params.get("points", []) as Array).size()
			return (I18n.t("%d delik konumu") % npt) if npt > 0 else I18n.t("Konum yok — düzlemsel yüze tıklayın")
		"dome":
			return "Yüz seçili" if not (editing.params.get("face", {}) as Dictionary).is_empty() else I18n.t("Yüz seçilmedi — düzlemsel yüze tıklayın")
	if editing.type == "shell":
		var nf: int = (editing.params.get("faces", []) as Array).size()
		return (I18n.t("%d yüz açık bırakılacak") % nf) if nf > 0 else I18n.t("Yüz seçilmedi: kapalı (içi boş) gövde")
	var ne: int = (editing.params.get("edges", []) as Array).size()
	return (I18n.t("%d kenar seçili") % ne) if ne > 0 else I18n.t("Kenar seçilmedi — modelde kenarlara tıklayın")


func _update_brep_counts() -> void:
	if _brep_count_label != null and is_instance_valid(_brep_count_label):
		_brep_count_label.text = _brep_count_text()
	if _error_label != null and is_instance_valid(_error_label) and editing:
		_error_label.text = ("Hata: " + editing.error) if editing.error != "" else ""


func _clear_brep_selection() -> void:
	if editing == null:
		return
	match editing.type:
		"shell":
			editing.params["faces"] = []
		"draft":
			editing.params["faces"] = []
			editing.params["neutral"] = {}
		"combine":
			editing.params["bodies"] = []
		"move_body":
			editing.params["body"] = {}
		"hole":
			editing.params["points"] = []
			editing.params["face"] = {}
		"dome":
			editing.params["face"] = {}
		_:
			editing.params["edges"] = []
	_preview()
	_update_brep_highlight()
	_update_brep_counts()


func _set_brep_show_result(b: bool) -> void:
	_brep_show_result = b
	_hover_edge = -1
	_preview()
	_update_brep_highlight()


func _show_brep_feature_panel() -> void:
	if editing != null and editing.type in SpecialUI.TYPES:
		special.show_feature_panel(editing)
		return
	var f := editing
	if f == null:
		return
	panel.clear()
	panel.title(f.type_label() if editing_is_new else f.name, tree._feature_icon(f))
	panel.ok_cancel(_ok_feature, _cancel_feature)
	match f.type:
		"fillet":
			panel.section("Yuvarlatma parametreleri")
			var on_r := func(v: float) -> void:
				f.params["r"] = v
				_preview()
			panel.number("Yarıçap" if not bool(f.params.get("variable", false)) else I18n.t("Başlangıç yarıçapı"), float(f.params.get("r", 2.0)), on_r, "length", 0.001)
			var on_var := func(b: bool) -> void:
				f.params["variable"] = b
				if b and not f.params.has("r2"):
					f.params["r2"] = float(f.params.get("r", 2.0)) * 2.0
				_preview()
				_show_brep_feature_panel()
			panel.check("Değişken yarıçap (kenar boyunca doğrusal)", bool(f.params.get("variable", false)), on_var)
			if bool(f.params.get("variable", false)):
				var on_r2 := func(v: float) -> void:
					f.params["r2"] = v
					_preview()
				panel.number("Bitiş yarıçapı", float(f.params.get("r2", 4.0)), on_r2, "length", 0.001)
			panel.section("Yuvarlatılacak kenarlar")
		"chamfer":
			panel.section("Pah parametreleri")
			var on_d := func(v: float) -> void:
				f.params["d"] = v
				_preview()
			var modes := ["equal", "dist2", "angle"]
			var cur_mode := str(f.params.get("mode", "equal"))
			var on_mode := func(i: int) -> void:
				f.params["mode"] = modes[i]
				_preview()
				_show_brep_feature_panel()
			panel.option("Pah türü", ["Eşit mesafe", "İki mesafe", "Açı - mesafe"], maxi(modes.find(cur_mode), 0), on_mode)
			panel.number("Mesafe" if cur_mode == "equal" else I18n.t("Mesafe 1"), float(f.params.get("d", 1.0)), on_d, "length", 0.001)
			if cur_mode == "dist2":
				var on_d2 := func(v: float) -> void:
					f.params["d2"] = v
					_preview()
				panel.number("Mesafe 2", float(f.params.get("d2", 2.0)), on_d2, "length", 0.001)
			elif cur_mode == "angle":
				var on_a := func(v: float) -> void:
					f.params["angle"] = v
					_preview()
				panel.number("Açı", float(f.params.get("angle", 45.0)), on_a, "angle", 0.1, 89.9)
			if cur_mode != "equal":
				var on_flip := func(b: bool) -> void:
					f.params["flip"] = b
					_preview()
				panel.check("Yönü çevir (diğer yüzden ölç)", bool(f.params.get("flip", false)), on_flip)
			panel.section("Pah kırılacak kenarlar")
		"shell":
			panel.section("Kabuk parametreleri")
			var on_t := func(v: float) -> void:
				f.params["t"] = v
				_preview()
			panel.number("Kalınlık", float(f.params.get("t", 1.0)), on_t, "length", 0.001)
			var on_out := func(b: bool) -> void:
				f.params["outward"] = b
				_preview()
			panel.check("Dışa doğru kabuk", bool(f.params.get("outward", false)), on_out)
			panel.section("Kaldırılacak yüzler")
		"draft":
			panel.section("Eğim parametreleri")
			var on_ang := func(v: float) -> void:
				f.params["angle"] = v
				_preview()
			panel.number("Eğim açısı", float(f.params.get("angle", 3.0)), on_ang, "angle", 0.01, 89.0)
			var on_rev := func(b: bool) -> void:
				f.params["reverse"] = b
				_preview()
			panel.check("Çekme yönünü ters çevir", bool(f.params.get("reverse", false)), on_rev)
			var nb := panel.button("Tarafsız yüzü seçmeyi iptal et" if _draft_neutral_pick else I18n.t("Tarafsız yüzü seç (sonraki tıklama)"), _toggle_draft_neutral, Icons.get_icon("plane", 16))
			nb.toggle_mode = true
			nb.button_pressed = _draft_neutral_pick
			panel.section("Eğim verilecek yüzler")
		"combine":
			panel.section("İşlem")
			var ops := ["add", "subtract", "common"]
			var on_op := func(i: int) -> void:
				f.params["op"] = ops[i]
				_preview()
			panel.option("İşlem", ["Ekle (birleşim)", "Çıkar (ana gövdeden)", "Kesiştir (ortak hacim)"], maxi(ops.find(str(f.params.get("op", "add"))), 0), on_op)
			panel.section("Gövdeler")
		"move_body":
			panel.section("Öteleme")
			var tv: Array = f.params.get("t", [0.0, 0.0, 0.0])
			for ai in 3:
				var axis_i := ai
				var on_t := func(v: float) -> void:
					var t2: Array = (f.params.get("t", [0.0, 0.0, 0.0]) as Array).duplicate()
					t2[axis_i] = v
					f.params["t"] = t2
					_preview()
				panel.number(["ΔX", "ΔY", "ΔZ"][ai], float(tv[ai]), on_t, "length")
			panel.section("Döndürme (orijinden geçen eksen)")
			var axes := ["x", "y", "z"]
			var on_ax := func(i: int) -> void:
				f.params["axis"] = axes[i]
				_preview()
			panel.option("Eksen", [I18n.t("X ekseni"), I18n.t("Y ekseni"), I18n.t("Z ekseni")], maxi(axes.find(str(f.params.get("axis", "y"))), 0), on_ax)
			var on_ma := func(v: float) -> void:
				f.params["angle"] = v
				_preview()
			panel.number("Açı", float(f.params.get("angle", 0.0)), on_ma, "angle")
			var on_copy := func(b: bool) -> void:
				f.params["copy"] = b
				_preview()
			panel.check("Kopyala (orijinal gövde kalır)", bool(f.params.get("copy", false)), on_copy)
			panel.section("Gövde")
		"split":
			panel.section("Bölme düzlemi")
			var pls := ["front", "top", "right"]
			var on_pl := func(i: int) -> void:
				f.params["plane"] = pls[i]
				_preview()
			panel.option("Düzlem", ["Ön Düzlem (XY)", "Üst Düzlem (XZ)", "Sağ Düzlem (YZ)"], maxi(pls.find(str(f.params.get("plane", "front"))), 0), on_pl)
			var on_off := func(v: float) -> void:
				f.params["offset"] = v
				_preview()
			panel.number("Ofset (normal yönünde)", float(f.params.get("offset", 0.0)), on_off, "length")
			var keeps := ["both", "pos", "neg"]
			var on_keep := func(i: int) -> void:
				f.params["keep"] = keeps[i]
				_preview()
			panel.option("Korunacak", ["Her iki taraf (ayrı gövdeler)", "Normal tarafı (+)", "Ters taraf (-)"], maxi(keeps.find(str(f.params.get("keep", "both"))), 0), on_keep)
		"hole":
			panel.section("Delik türü")
			var stds := ["ISO", "ANSI"]
			var on_std := func(i: int) -> void:
				f.params["std"] = stds[i]
				var szs := HoleTable.sizes(stds[i])
				if not (str(f.params.get("size", "")) in szs):
					f.params["size"] = szs[mini(5, szs.size() - 1)] if stds[i] == "ISO" else szs[4]
				_preview()
				_show_brep_feature_panel()
			panel.option("Standart", [I18n.t("ISO (metrik)"), "ANSI (inç)"], maxi(stds.find(str(f.params.get("std", "ISO"))), 0), on_std)
			var on_ht := func(i: int) -> void:
				f.params["htype"] = HoleTable.TYPES[i]
				_preview()
				_show_brep_feature_panel()
			panel.option("Tür", HoleTable.TYPE_NAMES, maxi(HoleTable.TYPES.find(str(f.params.get("htype", "simple"))), 0), on_ht)
			var szs2 := HoleTable.sizes(str(f.params.get("std", "ISO")))
			var on_sz := func(i: int) -> void:
				f.params["size"] = szs2[i]
				_preview()
				_show_brep_feature_panel()
			panel.option("Ölçü", szs2, maxi(szs2.find(str(f.params.get("size", "M6"))), 0), on_sz)
			if str(f.params.get("htype", "simple")) != "tap":
				var on_fit := func(i: int) -> void:
					f.params["fit"] = HoleTable.FITS[i]
					_preview()
					_show_brep_feature_panel()
				panel.option("Geçme", HoleTable.FIT_NAMES, maxi(HoleTable.FITS.find(str(f.params.get("fit", "normal"))), 0), on_fit)
			var ends2 := ["through", "blind"]
			var on_en := func(i: int) -> void:
				f.params["end"] = ends2[i]
				_preview()
				_show_brep_feature_panel()
			panel.option("Bitiş", ["Tümünden", "Kör"], maxi(ends2.find(str(f.params.get("end", "through"))), 0), on_en)
			if str(f.params.get("end", "through")) == "blind":
				var on_dp := func(v: float) -> void:
					f.params["depth"] = v
					_preview()
				panel.number("Derinlik", float(f.params.get("depth", 10.0)), on_dp, "length", 0.001)
			var hd := HoleTable.dims(str(f.params.get("std", "ISO")), str(f.params.get("htype", "simple")), str(f.params.get("size", "M6")), str(f.params.get("fit", "normal")))
			if not hd.is_empty():
				var txt := I18n.t("Delik Ø%s") % Units.format_length(float(hd["d"]))
				match str(f.params.get("htype", "simple")):
					"cbore":
						txt += I18n.t("\nHavşa Ø%s x %s") % [Units.format_length(float(hd["cb_d"])), Units.format_length(float(hd["cb_h"]))]
					"csink":
						txt += I18n.t("\nHavşa Ø%s x %s°") % [Units.format_length(float(hd["cs_d"])), str(hd["cs_ang"])]
					"tap":
						txt += I18n.t(" (kılavuz matkabı)\nKozmetik diş: %s") % str(hd["thread"])
				panel.info(txt, Color(0.85, 0.85, 0.6))
			panel.section("Konumlar")
		"dome":
			panel.section("Kubbe")
			var on_dh := func(v: float) -> void:
				f.params["height"] = v
				_preview()
			panel.number("Yükseklik", float(f.params.get("height", 5.0)), on_dh, "length", 0.001)
			panel.section("Yüz")
		"import":
			panel.section("İçe aktarılan dosya")
			panel.info(str(f.params.get("path", "")).get_file())
			var on_s := func(v: float) -> void:
				f.params["scale"] = v
				_preview()
			panel.number("Ölçek", float(f.params.get("scale", 1.0)), on_s, "plain", 1e-6)
			_import_xform_panel(f)
	if f.type == "split":
		_brep_count_label = null
	elif f.type != "import":
		_brep_count_label = panel.info(_brep_count_text(), Color(0.55, 0.85, 1.0))
		panel.button("Seçimi temizle", _clear_brep_selection, Icons.get_icon("delete", 16))
		panel.check("Sonucu önizle (seçim kapalı)", _brep_show_result, _set_brep_show_result)
	_error_label = panel.info((I18n.t("Hata: ") + f.error) if f.error != "" else "", Color(1.0, 0.45, 0.4))
	panel.spacer()
	if f.type == "shell":
		panel.info("Modelde açık kalacak yüzlere tıklayın.\nEnter: Tamam   Esc: İptal", Color(0.55, 0.6, 0.66))
	elif f.type in ["draft", "combine", "move_body", "split", "dome"]:
		panel.info("Enter: Tamam   Esc: İptal", Color(0.55, 0.6, 0.66))
	elif f.type == "hole":
		panel.info("Aynı düzlemsel yüzde her tıklama bir delik konumu ekler.\nEnter: Tamam   Esc: İptal", Color(0.55, 0.6, 0.66))
	elif f.type != "import":
		panel.info("Kenara tıklayın: ekle/kaldır. Yüze tıklayın: tüm kenarları.\nEnter: Tamam   Esc: İptal", Color(0.55, 0.6, 0.66))


func _brep_summary(f: CadFeature) -> String:
	match f.type:
		"fillet":
			return I18n.t("Yarıçap: %s\nKenar: %d") % [Units.format_length(float(f.params.get("r", 0.0))), (f.params.get("edges", []) as Array).size()]
		"chamfer":
			return I18n.t("Mesafe: %s\nKenar: %d") % [Units.format_length(float(f.params.get("d", 0.0))), (f.params.get("edges", []) as Array).size()]
		"shell":
			return I18n.t("Kalınlık: %s%s\nAçık yüz: %d") % [Units.format_length(float(f.params.get("t", 0.0))),
				I18n.t(" (dışa)") if bool(f.params.get("outward", false)) else "", (f.params.get("faces", []) as Array).size()]
		"import":
			return I18n.t("Dosya: %s\nÖlçek: %s   X/Y/Z: %s / %s / %s%s") % [str(f.params.get("path", "")).get_file(), str(f.params.get("scale", 1.0)),
				snappedf(float(f.params.get("sx", 1.0)), 0.0001), snappedf(float(f.params.get("sy", 1.0)), 0.0001), snappedf(float(f.params.get("sz", 1.0)), 0.0001),
				_import_extra_summary(f)]
		"draft":
			return I18n.t("Açı: %s\nYüz: %d") % [Units.format_angle(float(f.params.get("angle", 0.0))), (f.params.get("faces", []) as Array).size()]
		"rib":
			return I18n.t("Kalınlık: %s") % Units.format_length(float(f.params.get("t", 0.0)))
		"combine":
			var opn := {"add": I18n.t("Ekle"), "subtract": I18n.t("Çıkar"), "common": I18n.t("Kesiştir")}
			return I18n.t("İşlem: %s\nGövde: %d") % [opn.get(str(f.params.get("op", "add")), ""), (f.params.get("bodies", []) as Array).size()]
		"move_body":
			var t3: Array = f.params.get("t", [0, 0, 0])
			return I18n.t("Öteleme: (%s, %s, %s)\nDönme: %s%s") % [Units.format_length(float(t3[0]), false), Units.format_length(float(t3[1]), false),
				Units.format_length(float(t3[2]), false), Units.format_angle(float(f.params.get("angle", 0.0))), I18n.t("  (kopya)") if bool(f.params.get("copy", false)) else ""]
		"split":
			var spn := RefGeom.resolve_plane(doc, str(f.params.get("plane", "front")))
			return I18n.t("Düzlem: %s, ofset %s") % [spn.name if spn else "?", Units.format_length(float(f.params.get("offset", 0.0)))]
		"hole":
			var hd := HoleTable.dims(str(f.params.get("std", "ISO")), str(f.params.get("htype", "simple")), str(f.params.get("size", "M6")), str(f.params.get("fit", "normal")))
			var tn: String = I18n.t(HoleTable.TYPE_NAMES[maxi(HoleTable.TYPES.find(str(f.params.get("htype", "simple"))), 0)])
			return I18n.t("%s %s — Ø%s\n%s, %d konum%s") % [str(f.params.get("std", "ISO")), str(f.params.get("size", "")), Units.format_length(float(hd.get("d", 0.0))),
				tn, (f.params.get("points", []) as Array).size(), (I18n.t("\nKozmetik diş: ") + str(hd.get("thread", ""))) if str(f.params.get("htype", "")) == "tap" else ""]
		"dome":
			return I18n.t("Yükseklik: %s") % Units.format_length(float(f.params.get("height", 0.0)))
		"sweep":
			var pf := doc.get_feature(int((f.params.get("path", {}) as Dictionary).get("id", 0)))
			return I18n.t("Yol: %s") % (pf.name if pf else I18n.t("seçilmedi"))
		"loft":
			return I18n.t("Profil: %d%s") % [(f.params.get("sketches", []) as Array).size(), I18n.t("  (düz)") if bool(f.params.get("ruled", false)) else ""]
		"lpattern", "cpattern", "mirror", "tpattern":
			return I18n.t("Özellik: %d%s") % [(f.params.get("features", []) as Array).size(), I18n.t("  (tüm gövdeler)") if bool(f.params.get("bodies", false)) else ""]
		"refplane":
			return I18n.t("Tür: %s") % {"offset": "Ofset", "angle": "Açılı", "3pt": "Üç nokta"}.get(str(f.params.get("mode", "offset")), "")
		"refaxis", "refpoint", "helix", "refcsys":
			return f.type_label()
		"projcurve":
			return I18n.t("Taslak: %s") % (doc.get_feature(f.sketch_ref()).name if doc.get_feature(f.sketch_ref()) else "?")
		"wrap":
			return I18n.t("Tür: %s, derinlik %s") % [{"emboss": "Kabartma", "deboss": I18n.t("Oyma"), "scribe": "Çizgi"}.get(str(f.params.get("wtype", "emboss")), ""), Units.format_length(float(f.params.get("depth", 0.0)))]
		"emboss":
			return "%s: %s" % [I18n.t("Gravür") if str(f.params.get("etype", "")) == "deboss" else "Kabartma", Units.format_length(float(f.params.get("depth", 0.0)))]
		"cvpattern":
			return I18n.t("Özellik: %d, örnek: %d") % [(f.params.get("features", []) as Array).size(), int(f.params.get("count", 0))]
	return ""


## İçe aktarma dönüşüm paneli: eksen bazlı ölçek, merkez, öteleme, bölgesel uzatma (STL)
func _import_xform_panel(f: CadFeature) -> void:
	var setp := func(v: float, k: String) -> void:
		f.params[k] = v
		_preview()
	panel.number(I18n.t("Ölçek X"), float(f.params.get("sx", 1.0)), setp.bind("sx"), "plain", 1e-6)
	panel.number(I18n.t("Ölçek Y"), float(f.params.get("sy", 1.0)), setp.bind("sy"), "plain", 1e-6)
	panel.number(I18n.t("Ölçek Z"), float(f.params.get("sz", 1.0)), setp.bind("sz"), "plain", 1e-6)
	var setv := func(v: float, k: String, i: int) -> void:
		var arr: Array = (f.params.get(k, [0.0, 0.0, 0.0]) as Array).duplicate() if f.params.get(k) is Array else [0.0, 0.0, 0.0]
		arr[i] = v
		f.params[k] = arr
		_preview()
	var o: Array = f.params.get("origin", [0.0, 0.0, 0.0]) if f.params.get("origin") is Array else [0.0, 0.0, 0.0]
	var mv: Array = f.params.get("move", [0.0, 0.0, 0.0]) if f.params.get("move") is Array else [0.0, 0.0, 0.0]
	panel.section(I18n.t("Ölçek merkezi / öteleme"))
	for i in 3:
		panel.number(I18n.t("Merkez ") + "XYZ"[i], float(o[i]), setv.bind("origin", i), "length")
	for i2 in 3:
		panel.number(I18n.t("Öteleme ") + "XYZ"[i2], float(mv[i2]), setv.bind("move", i2), "length")
	if not StlImport.is_stl(str(f.params.get("path", ""))):
		return
	panel.section(I18n.t("Bölgesel uzatma (STL)"))
	var axes := ["x", "y", "z"]
	if f.params.get("stretch") is Array:
		panel.info(I18n.t("Çok bölgeli uzatma: %d bölge (makro / dosyadan). Tek bölgeye dönmek için listeyi silin.") % (f.params["stretch"] as Array).size(), Color(0.6, 0.65, 0.72))
		panel.button(I18n.t("Uzatmayı kaldır"), func() -> void:
			f.params.erase("stretch")
			_preview()
			_show_feature_panel.call_deferred())
	else:
		_import_stretch_rows(f, axes)
	_import_protect_rows(f, axes)


## Tek bölgeli uzatma alanları
func _import_stretch_rows(f: CadFeature, axes: Array) -> void:
	var st: Dictionary = (f.params.get("stretch", {}) as Dictionary).duplicate() if f.params.get("stretch") is Dictionary else {"axis": "x", "a": 0.0, "b": 0.0, "add": 0.0}
	var on_ax := func(i: int) -> void:
		st["axis"] = axes[i]
		f.params["stretch"] = st
		_preview()
	panel.option("Eksen", ["X", "Y", "Z"], maxi(axes.find(str(st.get("axis", "x"))), 0), on_ax)
	var sets := func(v: float, k: String) -> void:
		st[k] = v
		f.params["stretch"] = st
		_preview()
	panel.number(I18n.t("Bölge başı (özgün)"), float(st.get("a", 0.0)), sets.bind("a"), "length")
	panel.number(I18n.t("Bölge sonu (özgün)"), float(st.get("b", 0.0)), sets.bind("b"), "length")
	panel.number(I18n.t("Eklenecek boy"), float(st.get("add", 0.0)), sets.bind("add"), "length")
	panel.info(I18n.t("Bölgedeki köşeler orantılı uzar, sonrası kaydırılır; bölge dışındaki ayrıntılar bozulmaz."), Color(0.6, 0.65, 0.72))


## Koruma bölgesi: bölgedeki (bant içindeki) ayrıntılar ölçeklenmez, yalnızca ötelenir
func _import_protect_rows(f: CadFeature, axes: Array) -> void:
	panel.section(I18n.t("Koruma bölgesi (STL)"))
	var on := f.params.get("protect") is Dictionary and not (f.params["protect"] as Dictionary).is_empty()
	panel.check(I18n.t("Bölgeyi ölçekleme (yalnızca taşı)"), on, func(v: bool) -> void:
		if v:
			f.params["protect"] = {"axis": "x", "a": 0.0, "b": 10.0, "blend": 10.0}
		else:
			f.params.erase("protect")
		_preview()
		_show_feature_panel.call_deferred())
	if not on:
		return
	var pr: Dictionary = (f.params["protect"] as Dictionary).duplicate(true)
	var setp := func(v: Variant, k: String) -> void:
		pr[k] = v
		f.params["protect"] = pr.duplicate(true)
		_preview()
	panel.option("Eksen", ["X", "Y", "Z"], maxi(axes.find(str(pr.get("axis", "x"))), 0), func(i: int) -> void: setp.call(axes[i], "axis"))
	panel.number(I18n.t("Bölge başı (özgün)"), float(pr.get("a", 0.0)), func(v: float) -> void: setp.call(v, "a"), "length")
	panel.number(I18n.t("Bölge sonu (özgün)"), float(pr.get("b", 0.0)), func(v: float) -> void: setp.call(v, "b"), "length")
	panel.number(I18n.t("Geçiş boyu"), float(pr.get("blend", 10.0)), func(v: float) -> void: setp.call(v, "blend"), "length", 0.0)
	var bands: Array = pr.get("bands", []) if pr.get("bands") is Array else []
	var nb := 0
	for b in bands:
		if b is Array and not (b as Array).is_empty():
			nb += 1
	panel.info((I18n.t("Kesit bantları: %d (makro / dosyadan); bant yoksa kesitin tamamı korunur.") % nb) +
		(I18n.t("\nÖteleme: %s") % str(pr["offset"]) if pr.get("offset") is Array else I18n.t("\nÖteleme: normal dönüşümle bölge merkezine göre")), Color(0.6, 0.65, 0.72))


## İçe aktarma özetindeki ek satırlar (uzatma, kademeli büyütme, koruma bölgesi)
func _import_extra_summary(f: CadFeature) -> String:
	var out := ""
	var st: Variant = f.params.get("stretch")
	if st is Dictionary and absf(float((st as Dictionary).get("add", 0.0))) > 1e-9:
		out += I18n.t("\nUzatma: %s +%s mm") % [str(st.get("axis", "x")).to_upper(), snappedf(float(st.get("add", 0.0)), 0.01)]
	elif st is Array and not (st as Array).is_empty():
		var tot := 0.0
		for r in st:
			if r is Dictionary:
				tot += float((r as Dictionary).get("add", 0.0))
		out += I18n.t("\nUzatma: %d bölge, toplam %+.2f mm") % [(st as Array).size(), tot]
	if f.params.get("taper") is Dictionary and not (f.params["taper"] as Dictionary).is_empty():
		out += I18n.t("\nKademeli kesit büyütme")
	var pr: Variant = f.params.get("protect")
	if pr is Dictionary and not (pr as Dictionary).is_empty():
		out += I18n.t("\nKoruma bölgesi: %s %s → %s") % [str(pr.get("axis", "x")).to_upper(), snappedf(float(pr.get("a", 0.0)), 0.01), snappedf(float(pr.get("b", 0.0)), 0.01)]
	return out


func _import_body(path: String) -> void:
	doc.checkpoint()
	var nf := doc.new_feature("import", "İçe Aktarılan")
	nf.params = {"path": path, "scale": 1.0}
	doc.add_feature(nf)
	selection = {"kind": "feature", "id": nf.id}
	_fit_after_build = true
	doc.commit()
	_set_status(I18n.t("İçe aktarılıyor: ") + path.get_file())


# ---------------------------------------------------------------- çekirdek ve dışa aktarma

func _update_kernel_label() -> void:
	if kernel_label:
		kernel_label.text = viewport.kernel.backend_label()


func _on_backend_changed(_b: String) -> void:
	_update_kernel_label()
	if asm_mode.is_open():
		asm_mode.on_backend_changed()
	if mode == "drawing":
		_dw_keys.clear()
		_dw_request_hlr()
	if mode == "kernel":
		_refresh_panel()
	_set_status(viewport.kernel.status_text())


static func _fmt_bytes(n: int) -> String:
	if n >= 1048576:
		return "%.1f MB" % (n / 1048576.0)
	if n >= 1024:
		return "%.0f KB" % (n / 1024.0)
	return "%d B" % n


func _on_export_done(r: Dictionary) -> void:
	if bool(r.get("ok", false)):
		_set_status(I18n.t("Kaydedildi: %s (%s)") % [str(r.get("path", "")), _fmt_bytes(int(r.get("bytes", 0)))])
	else:
		_set_status(I18n.t("Dışa aktarılamadı: ") + str(r.get("error", I18n.t("bilinmeyen hata"))))


func _save_export_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(GeoKernel.SETTINGS_PATH)
	cf.set_value("export", "stl_quality", _stl_quality)
	cf.set_value("export", "stl_ascii", _stl_ascii)
	cf.save(GeoKernel.SETTINGS_PATH)


func _show_kernel_panel() -> void:
	panel.clear()
	var k := viewport.kernel
	panel.title("Geometri Çekirdeği", Icons.get_icon("kernel", 22))
	panel.info(k.status_text())
	var modes := ["auto", "occ", "csg"]
	var names := [I18n.t("Otomatik (OpenCASCADE varsa)"), "OpenCASCADE (B-rep)", I18n.t("CSG (Godot, yalnızca üçgen ağ)")]
	var on_mode := func(i: int) -> void:
		k.set_mode(modes[i])
		_refresh_panel()
	panel.option("Çekirdek", names, maxi(modes.find(k.mode), 0), on_mode)
	if k.occ.is_ready():
		panel.info(I18n.t("OCP (OpenCASCADE) sürümü: %s\nSon yeniden oluşturma: %.0f ms") % [k.occ.version, k.occ.last_ms])
	elif not OccKernel.is_installed():
		panel.info("OpenCASCADE ortamı kurulu değil (occ_env). README → 'Faz 4: OpenCASCADE kurulumu'.", Color(1.0, 0.75, 0.3))
	elif k.occ.state == "failed":
		panel.info(I18n.t("Hata: ") + k.occ.fail_reason, Color(1.0, 0.45, 0.4))
	panel.info("OpenCASCADE: gerçek yüzey/kenar topolojisi, köşe yuvarlatma, pah, kabuk, STEP/IGES.\nCSG: yalnızca ekstrüzyon/döndürme, üçgen ağ.", Color(0.55, 0.6, 0.66))
	panel.section("STL dışa aktarma (OpenCASCADE)")
	var qnames: Array = []
	for q in STL_PRESETS:
		qnames.append(I18n.t("%s (sapma %s mm, %s°)") % [I18n.t(str(q[0])), str(q[1]), str(q[2])])
	var on_q := func(i: int) -> void:
		_stl_quality = i
		_save_export_settings()
	panel.option("Kalite", qnames, _stl_quality, on_q)
	var on_ascii := func(b: bool) -> void:
		_stl_ascii = b
		_save_export_settings()
	panel.check("ASCII STL (varsayılan: ikili)", _stl_ascii, on_ascii)
	var m := viewport.model
	if m.has_brep():
		panel.section("Model (B-rep)")
		var solids := int(m.exact_mass.get("solids", 0)) if not m.exact_mass.is_empty() else 0
		panel.info(I18n.t("Gövde: %d   Yüz: %d   Kenar: %d\nGörüntü üçgeni: %d   Geçerli: %s") % [solids, m.brep_faces.size(), m.brep_edges.size(),
			m.tri_count(), "evet" if bool(m.brep_src.get("valid", true)) else I18n.t("HAYIR")])
	panel.spacer()
	panel.button("Kapat", _leave_aux_mode)


# ---------------------------------------------------------------- Faz 4b yardımcıları

var _draft_neutral_pick := false


func _toggle_draft_neutral() -> void:
	_draft_neutral_pick = not _draft_neutral_pick
	_set_status(I18n.t("Tarafsız yüz için modelde düzlemsel bir yüze tıklayın.") if _draft_neutral_pick else I18n.t("Eğim verilecek yüzlere tıklayın."))
	_show_brep_feature_panel()


func _body_of_ref(ref: Dictionary) -> int:
	var m := viewport.model
	var want := str(ref.get("name", ""))
	if want != "":
		for f in m.brep_faces:
			if str(f.get("name", "")) == want:
				return int(f.get("body", -1))
	var fid := _face_id_of_ref(ref)
	if fid >= 0 and fid < m.brep_faces.size():
		return int(m.brep_faces[fid].get("body", -1))
	return -1


func _show_rib_panel() -> void:
	var f := editing
	panel.clear()
	panel.title(f.type_label() if editing_is_new else f.name, Icons.get_icon("rib", 22))
	panel.ok_cancel(_ok_feature, _cancel_feature)
	var sketches := doc.sketches()
	var names: Array = []
	var sel_i := 0
	for i in sketches.size():
		names.append(sketches[i].name)
		if sketches[i].id == f.sketch_ref():
			sel_i = i
	panel.section("Profil (açık çizgi)")
	var on_sketch := func(i: int) -> void:
		f.params["sketch"] = sketches[i].id
		_preview()
		_show_rib_panel()
	panel.option("Taslak", names, sel_i, on_sketch)
	panel.section("Parametreler")
	var on_t := func(v: float) -> void:
		f.params["t"] = v
		_preview()
	panel.number("Kalınlık", float(f.params.get("t", 4.0)), on_t, "length", 0.001)
	var on_flip := func(b: bool) -> void:
		f.params["flip"] = b
		_preview()
	panel.check("Malzeme tarafını çevir", bool(f.params.get("flip", false)), on_flip)
	_error_label = panel.info((I18n.t("Hata: ") + f.error) if f.error != "" else "", Color(1.0, 0.45, 0.4))
	panel.spacer()
	panel.info("Kaburga, taslak düzleminin iki yanına eşit kalınlıkta, çizgiden gövdeye kadar uzanır.\nEnter: Tamam   Esc: İptal", Color(0.55, 0.6, 0.66))


# ================================================================ FAZ 5

const TOOL_TYPES := ["extrude", "revolve", "sweep", "loft", "hole"]
var _pick_target := ""      # modelden seçim bekleyen alan: vertex | face | dir1 | dir2 | axis | mirror_plane | base_face | points3 | pt2 | refpoint | ref_line


func _tb_menu(parent: Control, text: String, icon_name: String, tip: String, items: Array) -> MenuButton:
	var mb := MenuButton.new()
	mb.text = text
	mb.icon = Icons.get_icon(icon_name, 28)
	mb.tooltip_text = tip
	mb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mb.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	mb.flat = true
	mb.focus_mode = Control.FOCUS_NONE
	mb.custom_minimum_size = Vector2(70, 62)
	mb.add_theme_font_size_override("font_size", 12)
	var pm := mb.get_popup()
	var cmds: Array = []
	for i in items.size():
		pm.add_item(items[i][0], i)
		cmds.append(items[i][1])
		_reg_cmd(str(items[i][1]), str(items[i][0]), tip, _cmd.bind(items[i][1]), "global", str(parent.get_meta("group", "")))
	pm.id_pressed.connect(func(id): _cmd(cmds[id]))
	parent.add_child(mb)
	return mb


static func _fmt_pt(v: Variant) -> String:
	if not (v is Array) or (v as Array).size() < 3:
		return "—"
	return "(%s, %s, %s)" % [Units.format_length(float(v[0]), false), Units.format_length(float(v[1]), false), Units.format_length(float(v[2]), false)]


func _set_pick_target(t: String) -> void:
	_pick_target = "" if _pick_target == t else t
	var msgs := {"vertex": I18n.t("Modelde bir köşeye tıklayın."), "face": I18n.t("Hedef yüze tıklayın."), "dir1": I18n.t("Yön için doğrusal bir kenara (veya düzlemsel yüze) tıklayın."),
		"dir2": I18n.t("Yön 2 için doğrusal bir kenara tıklayın."), "axis": I18n.t("Eksen için dairesel/doğrusal kenara veya silindirik yüze tıklayın."),
		"mirror_plane": I18n.t("Aynalama düzlemi olarak düzlemsel bir yüze tıklayın."), "base_face": I18n.t("Taban olarak düzlemsel bir yüze tıklayın."),
		"points3": I18n.t("Üç köşeye sırayla tıklayın."), "pt2": I18n.t("İki köşeye sırayla tıklayın."), "refpoint": I18n.t("Bir köşeye tıklayın."),
		"ref_line": I18n.t("Doğrusal/dairesel kenara veya silindirik yüze tıklayın."),
		"tan_face": I18n.t("Teğet düzlemin değeceği noktaya (silindir, koni, küre veya düzlem yüzünde) tıklayın."),
		"csys_o": I18n.t("Koordinat sisteminin başlangıcı için bir köşeye tıklayın."),
		"csx": I18n.t("X ekseni için doğrusal bir kenara tıklayın."), "csy": I18n.t("Y ekseni için doğrusal bir kenara tıklayın.")}
	_set_status(str(msgs.get(_pick_target, "")) if _pick_target != "" else I18n.t("Seçim iptal edildi."))
	_show_feature_panel()


func _pick_button(label: String, target: String) -> void:
	var cb := func(): _set_pick_target(target)
	var b := panel.button((I18n.t("Seçimi iptal et") if _pick_target == target else label), cb, Icons.get_icon("select", 16))
	b.toggle_mode = true
	b.button_pressed = _pick_target == target


func _pick_for_target(pos: Vector2) -> void:
	var f := editing
	if f == null:
		return
	var m := viewport.model
	var r := viewport.ray(pos)
	var t := _pick_target
	var hit := m.raycast(r[0], r[1])
	if t == "tan_face":
		if hit.is_empty():
			return
		var fdt := m.planar_face(int(hit["tri"]))
		var it: Dictionary = fdt.get("info", {})
		var tpp: Vector3 = hit["point"]
		var tn: Vector3 = fdt["normal"] if fdt["planar"] else m.normals[int(hit["tri"])]
		if str(it.get("type", "")) == "cylinder" or str(it.get("type", "")) == "cone":
			var o := ModelMesh._v3(it["o"])
			var ad := ModelMesh._v3(it["axis"]).normalized()
			var rv := (tpp - o) - ad * (tpp - o).dot(ad)
			if rv.length() > 1e-9:
				tn = rv.normalized()
		elif str(it.get("type", "")) == "sphere":
			tn = (tpp - ModelMesh._v3(it["o"])).normalized()
		f.params["tan_p"] = RefGeom.arr(tpp)
		f.params["tan_n"] = RefGeom.arr(tn)
		_pick_target = ""
		_preview()
		_show_feature_panel()
		return
	if t == "csys_o":
		if hit.is_empty():
			return
		var cp: Vector3 = hit["point"]
		var cvx := m.nearest_vertex_of(int(hit["tri"]), cp)
		if viewport.world_to_screen(cvx).distance_to(pos) < 12.0:
			cp = cvx
		f.params["o"] = RefGeom.arr(cp)
		_pick_target = ""
		_preview()
		_show_feature_panel()
		return
	if t in ["csx", "csy"]:
		t = "csx_" if t == "csx" else "csy_"
	if t in ["dir1", "dir2", "axis", "ref_line", "csx_", "csy_"]:
		var line := {}
		var he := viewport.pick_edge(pos)
		if not he.is_empty():
			var e: Dictionary = m.brep_edges[int(he["edge"])]
			if str(e.get("type", "")) == "line":
				line = {"o": ModelMesh._v3(e["m"]), "d": ModelMesh._v3(e["d"])}
			elif str(e.get("type", "")) == "circle" and e.has("n"):
				line = {"o": ModelMesh._v3(e["o"]), "d": ModelMesh._v3(e["n"])}
		if line.is_empty() and not hit.is_empty():
			var fd := m.planar_face(int(hit["tri"]))
			var info: Dictionary = fd.get("info", {})
			if str(info.get("type", "")) == "cylinder":
				line = {"o": ModelMesh._v3(info["o"]), "d": ModelMesh._v3(info["axis"])}
			elif fd["planar"] and t != "axis" and t != "ref_line":
				line = {"o": hit["point"], "d": fd["normal"]}
		if line.is_empty():
			_set_status("Doğrusal veya dairesel bir kenar ya da silindirik yüz seçin.")
			return
		var v := RefGeom.axis_value_of_line(line["o"], line["d"])
		match t:
			"dir1":
				f.params["dir1"] = v
			"dir2":
				f.params["dir2"] = v
			"axis":
				f.params["axis"] = v
			"ref_line":
				f.params["mode"] = "line"
				f.params["o"] = RefGeom.arr(line["o"])
				f.params["d"] = RefGeom.arr(line["d"])
			"csx_":
				f.params["x"] = v
			"csy_":
				f.params["y"] = v
		_pick_target = ""
	elif t in ["face", "base_face", "mirror_plane"]:
		if hit.is_empty():
			return
		var fd2 := m.planar_face(int(hit["tri"]))
		var info2: Dictionary = fd2.get("info", {})
		var n: Vector3 = fd2["normal"] if fd2["planar"] else m.normals[int(hit["tri"])]
		var p: Vector3 = hit["point"]
		if t != "face" and not fd2["planar"]:
			_set_status("Düzlemsel bir yüz seçin.")
			return
		match t:
			"face":
				f.params["face"] = {"p": RefGeom.arr(p), "n": RefGeom.arr(n), "name": str(info2.get("name", ""))}
			"base_face":
				var pl := SketchPlane.from_face(p, n)
				f.params["base_plane"] = {"o": RefGeom.arr(pl.origin), "x": RefGeom.arr(pl.x_dir), "y": RefGeom.arr(pl.y_dir)}
			"mirror_plane":
				f.params["plane_face"] = {"o": RefGeom.arr(p), "n": RefGeom.arr(n)}
		_pick_target = ""
	elif t in ["vertex", "points3", "pt2", "refpoint"]:
		if hit.is_empty():
			return
		var p2: Vector3 = hit["point"]
		var vx := m.nearest_vertex_of(int(hit["tri"]), p2)
		if viewport.world_to_screen(vx).distance_to(pos) < 12.0:
			p2 = vx
		match t:
			"vertex":
				f.params["vertex"] = RefGeom.arr(p2)
				_pick_target = ""
			"refpoint":
				f.params["p"] = RefGeom.arr(p2)
				_pick_target = ""
			"points3":
				var pts: Array = f.params.get("points", [])
				if pts.size() >= 3:
					pts = []
				pts.append(RefGeom.arr(p2))
				f.params["points"] = pts
				if pts.size() >= 3:
					_pick_target = ""
			"pt2":
				if not f.params.has("p1") or f.params.has("p2"):
					f.params["p1"] = RefGeom.arr(p2)
					f.params.erase("p2")
				else:
					f.params["p2"] = RefGeom.arr(p2)
					_pick_target = ""
	_preview()
	_show_feature_panel()


func _extrude_extra_controls(f: CadFeature, cur: String) -> void:
	if cur == "vertex":
		panel.info(I18n.t("Köşe: ") + _fmt_pt(f.params.get("vertex")), Color(0.55, 0.85, 1.0))
		_pick_button(I18n.t("Köşe seç (modele tıkla)"), "vertex")
	if cur == "face" or cur == "face_offset":
		var fc: Dictionary = f.params.get("face", {})
		panel.info(I18n.t("Hedef yüz: ") + (I18n.t("seçili") if not fc.is_empty() else I18n.t("seçilmedi")), Color(0.55, 0.85, 1.0))
		_pick_button(I18n.t("Hedef yüzü seç (modele tıkla)"), "face")
		if cur == "face_offset":
			var on_fo := func(v: float) -> void:
				f.params["face_off"] = v
				_preview()
			panel.number("Ofset", float(f.params.get("face_off", 2.0)), on_fo, "length")
	if cur != "midplane":
		var on_d2 := func(b: bool) -> void:
			f.params["dir2"] = b
			_preview()
			_show_feature_panel()
		panel.check("İki yön (Yön 2)", bool(f.params.get("dir2", false)), on_d2)
		if bool(f.params.get("dir2", false)):
			var e2s := ["blind", "through", "next"]
			var on_e2 := func(i: int) -> void:
				f.params["end2"] = e2s[i]
				_preview()
				_show_feature_panel()
			panel.option("Yön 2 bitişi", ["Kör", "Tümünden", "Sonrakine Kadar"], maxi(e2s.find(str(f.params.get("end2", "blind"))), 0), on_e2)
			if str(f.params.get("end2", "blind")) == "blind":
				var on_dp2 := func(v: float) -> void:
					f.params["depth2"] = v
					_preview()
				panel.number("Derinlik 2", float(f.params.get("depth2", 5.0)), on_dp2, "length", 0.001)
	var has_draft := float(f.params.get("draft", 0.0)) != 0.0
	var on_dr := func(b: bool) -> void:
		f.params["draft"] = 3.0 if b else 0.0
		_preview()
		_show_feature_panel()
	panel.check("Eğim açısı", has_draft, on_dr)
	if has_draft:
		var on_da := func(v: float) -> void:
			f.params["draft"] = v
			_preview()
		panel.number("Açı", float(f.params.get("draft", 3.0)), on_da, "angle", 0.01, 60.0)
		var on_do := func(b: bool) -> void:
			f.params["draft_out"] = b
			_preview()
		panel.check("Dışa doğru eğim", bool(f.params.get("draft_out", false)), on_do)
	var has_thin := float(f.params.get("thin", 0.0)) > 0.0
	var on_th := func(b: bool) -> void:
		f.params["thin"] = 1.0 if b else 0.0
		_preview()
		_show_feature_panel()
	panel.check("İnce özellik (açık taslaklar da)", has_thin, on_th)
	if has_thin:
		var on_tt := func(v: float) -> void:
			f.params["thin"] = v
			_preview()
		panel.number("Kalınlık", float(f.params.get("thin", 1.0)), on_tt, "length", 0.001)
		var sides := ["mid", "a", "b"]
		var on_ts := func(i: int) -> void:
			f.params["thin_side"] = sides[i]
			_preview()
		panel.option("Taraf", ["Orta (iki yana)", "Bir yöne", "Diğer yöne"], maxi(sides.find(str(f.params.get("thin_side", "mid"))), 0), on_ts)


# ---------------------------------------------------------------- süpürme ve loft

func _default_path(profile_id: int) -> Dictionary:
	for i in range(doc.features.size() - 1, -1, -1):
		var g: CadFeature = doc.features[i]
		if g.id == profile_id or g.suppressed:
			continue
		if g.type == "helix":
			return {"kind": "helix", "id": g.id}
		if g.type == "sketch3d" and g.sketch3d and not g.sketch3d.lines.is_empty():
			return {"kind": "sketch3d", "id": g.id}
		if g.is_sketch() and doc.consumers_of(g.id).is_empty() and not g.sketch.curve_chains().is_empty():
			return {"kind": "sketch", "id": g.id}
	return {}


func _closed_sketches() -> Array:
	var out: Array = []
	for g in doc.sketches():
		if not g.suppressed and not (g.sketch.extract_profiles()["loops"] as Array).is_empty():
			out.append(g)
	return out


func _default_loft(profile_id: int) -> Array:
	var out: Array = []
	for g in _closed_sketches():
		if g.id == profile_id or doc.consumers_of(g.id).is_empty():
			out.append(g.id)
	return out


func _show_sweep_panel() -> void:
	var f := editing
	panel.clear()
	panel.title(f.type_label() if editing_is_new else f.name, Icons.get_icon("sweepcut" if f.is_cut() else "sweep", 22))
	panel.ok_cancel(_ok_feature, _cancel_feature)
	var sks := doc.sketches()
	var names: Array = []
	var si := 0
	for i in sks.size():
		names.append(sks[i].name)
		if sks[i].id == f.sketch_ref():
			si = i
	panel.section("Profil")
	var on_prof := func(i: int) -> void:
		f.params["sketch"] = sks[i].id
		_preview()
	panel.option("Taslak", names, si, on_prof)
	panel.section("Yol")
	var paths: Array = []
	var pnames: Array = []
	var pi := -1
	var cur: Dictionary = f.params.get("path", {})
	for g in doc.features:
		var kind := ""
		if g.type == "helix":
			kind = "helix"
		elif g.type == "sketch3d":
			kind = "sketch3d"
		elif g.type == "projcurve":
			kind = "projcurve"
		elif g.is_sketch() and g.id != f.sketch_ref():
			kind = "sketch"
		if kind == "":
			continue
		if int(cur.get("id", -1)) == g.id:
			pi = paths.size()
		paths.append({"kind": kind, "id": g.id})
		pnames.append(g.name)
	if paths.is_empty():
		panel.info("Yol yok: bir taslakta açık çizgi zinciri, 3B taslak veya helis oluşturun.", Color(1.0, 0.75, 0.3))
	else:
		var on_path := func(i: int) -> void:
			f.params["path"] = paths[i]
			_preview()
		panel.option("Yol", pnames, maxi(pi, 0), on_path)
		if pi < 0:
			f.params["path"] = paths[0]
	panel.section("Seçenekler")
	var excl: Array = [f.sketch_ref(), int((f.params.get("path", {}) as Dictionary).get("id", -1))]
	_curve_option(I18n.t("Kılavuz eğrisi"), "guide", excl, true)
	if not (f.params.get("guide", {}) as Dictionary).is_empty():
		panel.info("Profil, kılavuza değecek şekilde ölçeklenir.", Color(0.55, 0.6, 0.66))
	else:
		var on_tw := func(v: float) -> void:
			f.params["twist"] = v
			_preview()
		panel.number("Bükme açısı", float(f.params.get("twist", 0.0)), on_tw, "angle", -3600.0, 3600.0)
	if not f.is_cut():
		var on_merge := func(b: bool) -> void:
			f.params["merge"] = b
			_preview()
		panel.check("Sonucu birleştir", bool(f.params.get("merge", true)), on_merge)
	_error_label = panel.info((I18n.t("Hata: ") + f.error) if f.error != "" else "", Color(1.0, 0.45, 0.4))
	panel.spacer()
	panel.info("Profil yolun başında ve yola dik olmalıdır. Helis yolu için profili helisin başlangıç noktasına çizin.\nEnter: Tamam   Esc: İptal", Color(0.55, 0.6, 0.66))


func _show_loft_panel() -> void:
	var f := editing
	panel.clear()
	panel.title(f.type_label() if editing_is_new else f.name, Icons.get_icon("loftcut" if f.is_cut() else "loft", 22))
	panel.ok_cancel(_ok_feature, _cancel_feature)
	panel.section("Profiller (ağaç sırasıyla)")
	var sel: Array = f.params.get("sketches", [])
	for g in _closed_sketches():
		var gid: int = g.id
		var on_t := func(b: bool) -> void:
			var lst: Array = (f.params.get("sketches", []) as Array).duplicate()
			if b and not (gid in lst):
				lst.append(gid)
			elif not b:
				lst.erase(gid)
			lst.sort_custom(func(a, c): return doc.index_of(a) < doc.index_of(c))
			f.params["sketches"] = lst
			_preview()
		panel.check(g.name, gid in sel, on_t)
	var on_r := func(b: bool) -> void:
		f.params["ruled"] = b
		_preview()
	panel.check("Düz geçiş (doğrusal yüzeyler)", bool(f.params.get("ruled", false)), on_r)
	_curve_option(I18n.t("Kılavuz eğrisi"), "guide", sel, true)
	if not (f.params.get("guide", {}) as Dictionary).is_empty():
		panel.info("Kılavuz eğrisi her profilden geçmelidir.", Color(0.55, 0.6, 0.66))
	if not f.is_cut():
		var on_merge := func(b: bool) -> void:
			f.params["merge"] = b
			_preview()
		panel.check("Sonucu birleştir", bool(f.params.get("merge", true)), on_merge)
	_error_label = panel.info((I18n.t("Hata: ") + f.error) if f.error != "" else "", Color(1.0, 0.45, 0.4))
	panel.spacer()
	panel.info("Her taslakta bir kapalı kontur olmalı; profiller farklı (paralel veya açılı) düzlemlerde olur.\nEnter: Tamam   Esc: İptal", Color(0.55, 0.6, 0.66))


# ---------------------------------------------------------------- çoğaltma

func _cmd_pattern(type: String) -> void:
	var pre := selection.duplicate()
	_exit_sketch3d()
	if mode == "sketch":
		_exit_sketch()
	if mode == "feature":
		_cancel_feature()
	_leave_aux_mode()
	if not viewport.kernel.is_brep():
		_set_status("Çoğaltma OpenCASCADE (B-rep) çekirdeği gerektirir: Araçlar → Geometri çekirdeği.")
		return
	if viewport.model.is_empty():
		_set_status("Önce bir katı model oluşturun.")
		return
	var f := CadFeature.new()
	f.id = 0
	f.type = type
	var feats: Array = []
	if pre.get("kind", "") == "feature":
		var g := doc.get_feature(int(pre["id"]))
		if g and g.type in TOOL_TYPES:
			feats.append(g.id)
	match type:
		"lpattern":
			f.params = {"features": feats, "bodies": false, "dir1": "x", "rev1": false, "spacing1": 10.0, "count1": 3, "use2": false, "dir2": "z", "spacing2": 10.0, "count2": 2}
		"cpattern":
			f.params = {"features": feats, "bodies": false, "axis": "y", "count": 4, "angle": 360.0, "equal": true}
		"mirror":
			f.params = {"features": feats, "bodies": feats.is_empty(), "plane": "right"}
		"tpattern":
			f.params = {"features": feats, "bodies": false, "offsets": [[10.0, 0.0, 0.0]]}
		"cvpattern":
			var cc := _curve_candidates([])
			f.params = {"features": feats, "bodies": false, "curve": ({"kind": cc[cc.size() - 1]["kind"], "id": cc[cc.size() - 1]["id"]} if not cc.is_empty() else {}),
				"count": 4, "spacing": 10.0, "equal": true, "align": true}
	f.name = f.type_label()
	editing = f
	editing_is_new = true
	mode = "feature"
	_pick_target = ""
	_preview()
	_show_feature_panel()
	_set_status(I18n.t("%s: çoğaltılacak özellikleri panelden işaretleyin.") % f.type_label())


func _tool_features() -> Array:
	var out: Array = []
	var limit := doc.index_of(editing.id) if editing and editing.id > 0 else doc.features.size()
	for i in mini(limit, doc.features.size()):
		var g: CadFeature = doc.features[i]
		if g.type in TOOL_TYPES and not g.suppressed and not doc.is_rolled_back(g):
			out.append(g)
	return out


func _axis_option(label: String, key: String, def: String, pick: String) -> void:
	var f := editing
	var choices := RefGeom.axis_choices(doc, f.id if f.id > 0 else -1)
	var cur := str(f.params.get(key, def))
	var labels: Array = []
	var vals: Array = []
	for c in choices:
		labels.append(c[0])
		vals.append(c[1])
	if cur.begins_with("v:"):
		labels.append(I18n.t("Seçilen kenar / eksen"))
		vals.append(cur)
	var on_sel := func(i: int) -> void:
		f.params[key] = vals[i]
		_preview()
	panel.option(label, labels, maxi(vals.find(cur), 0), on_sel)
	_pick_button(I18n.t("Modelden seç"), pick)


func _show_pattern_panel() -> void:
	var f := editing
	panel.clear()
	var icons := {"lpattern": "lpattern", "cpattern": "cpattern", "mirror": "mirror3d", "tpattern": "tpattern", "cvpattern": "cvpattern"}
	panel.title(f.type_label() if editing_is_new else f.name, Icons.get_icon(icons.get(f.type, "pattern"), 22))
	panel.ok_cancel(_ok_feature, _cancel_feature)
	panel.section("Çoğaltılacak")
	var on_b := func(b: bool) -> void:
		f.params["bodies"] = b
		_preview()
		_show_feature_panel()
	panel.check("Tüm gövdeleri çoğalt", bool(f.params.get("bodies", false)), on_b)
	if not bool(f.params.get("bodies", false)):
		var tf := _tool_features()
		if tf.is_empty():
			panel.info("Çoğaltılabilecek özellik yok (ekstrüzyon, döndürme, süpürme, loft, delik).", Color(1.0, 0.75, 0.3))
		for g in tf:
			var gid: int = g.id
			var on_t := func(b: bool) -> void:
				var lst: Array = (f.params.get("features", []) as Array).duplicate()
				if b and not (gid in lst):
					lst.append(gid)
				elif not b:
					lst.erase(gid)
				f.params["features"] = lst
				_preview()
			panel.check(g.name, gid in f.params.get("features", []), on_t)
	match f.type:
		"lpattern":
			panel.section("Yön 1")
			_axis_option("Yön", "dir1", "x", "dir1")
			var on_r1 := func(b: bool) -> void:
				f.params["rev1"] = b
				_preview()
			panel.check("Ters yön", bool(f.params.get("rev1", false)), on_r1)
			var on_s1 := func(v: float) -> void:
				f.params["spacing1"] = v
				_preview()
			panel.number("Aralık", float(f.params.get("spacing1", 10.0)), on_s1, "length")
			var on_c1 := func(v: float) -> void:
				f.params["count1"] = int(round(v))
				_preview()
			panel.number("Örnek sayısı", float(f.params.get("count1", 3)), on_c1, "plain", 1, 1000)
			var on_u2 := func(b: bool) -> void:
				f.params["use2"] = b
				_preview()
				_show_feature_panel()
			panel.check("Yön 2", bool(f.params.get("use2", false)), on_u2)
			if bool(f.params.get("use2", false)):
				_axis_option("Yön", "dir2", "z", "dir2")
				var on_r2 := func(b: bool) -> void:
					f.params["rev2"] = b
					_preview()
				panel.check("Ters yön 2", bool(f.params.get("rev2", false)), on_r2)
				var on_s2 := func(v: float) -> void:
					f.params["spacing2"] = v
					_preview()
				panel.number("Aralık 2", float(f.params.get("spacing2", 10.0)), on_s2, "length")
				var on_c2 := func(v: float) -> void:
					f.params["count2"] = int(round(v))
					_preview()
				panel.number("Örnek sayısı 2", float(f.params.get("count2", 2)), on_c2, "plain", 1, 1000)
		"cpattern":
			panel.section("Eksen")
			_axis_option("Eksen", "axis", "y", "axis")
			var on_rv := func(b: bool) -> void:
				f.params["rev"] = b
				_preview()
			panel.check("Ters yön", bool(f.params.get("rev", false)), on_rv)
			var on_cn := func(v: float) -> void:
				f.params["count"] = int(round(v))
				_preview()
			panel.number("Örnek sayısı", float(f.params.get("count", 4)), on_cn, "plain", 1, 1000)
			var on_an := func(v: float) -> void:
				f.params["angle"] = v
				_preview()
			panel.number("Toplam açı", float(f.params.get("angle", 360.0)), on_an, "angle", 0.01, 360.0)
			var on_eq := func(b: bool) -> void:
				f.params["equal"] = b
				_preview()
			panel.check("Eşit aralık (360°'de son örnek başa denk gelmez)", bool(f.params.get("equal", true)), on_eq)
		"mirror":
			panel.section("Aynalama düzlemi")
			var choices := RefGeom.plane_choices(doc, f.id if f.id > 0 else -1)
			var labels: Array = []
			var vals: Array = []
			for c in choices:
				labels.append(c[0])
				vals.append(c[1])
			var custom := f.params.get("plane_face") is Dictionary and not (f.params["plane_face"] as Dictionary).is_empty()
			if custom:
				labels.append(I18n.t("Seçilen yüz"))
				vals.append("custom")
			var cur := "custom" if custom else str(f.params.get("plane", "right"))
			var on_pl := func(i: int) -> void:
				if vals[i] != "custom":
					f.params["plane"] = vals[i]
					f.params.erase("plane_face")
				_preview()
				_show_feature_panel()
			panel.option("Düzlem", labels, maxi(vals.find(cur), 0), on_pl)
			_pick_button(I18n.t("Düzlemsel yüz seç"), "mirror_plane")
		"cvpattern":
			panel.section("Eğri")
			_curve_option("Eğri", "curve", [], false)
			var on_cn := func(v: float) -> void:
				f.params["count"] = int(round(v))
				_preview()
			panel.number("Örnek sayısı", float(f.params.get("count", 4)), on_cn, "plain", 1, 1000)
			var on_eq := func(b: bool) -> void:
				f.params["equal"] = b
				_preview()
				_show_feature_panel()
			panel.check("Eşit aralık (eğri boyunca)", bool(f.params.get("equal", true)), on_eq)
			if not bool(f.params.get("equal", true)):
				var on_sp := func(v: float) -> void:
					f.params["spacing"] = v
					_preview()
				panel.number("Aralık", float(f.params.get("spacing", 10.0)), on_sp, "length", 0.001)
			var on_al := func(b: bool) -> void:
				f.params["align"] = b
				_preview()
			panel.check("Eğriyi izle (döndürerek yerleştir)", bool(f.params.get("align", true)), on_al)
			panel.info("Örnekler eğrinin başlangıcına göre konumlanır; ilk örnek seçili özelliğin kendisidir.", Color(0.55, 0.6, 0.66))
		"tpattern":
			panel.section("Öteleme tablosu")
			var parts: Array = []
			for o in f.params.get("offsets", []):
				parts.append("%s, %s, %s" % [str(o[0]), str(o[1]), str(o[2])])
			var on_tx := func(t: String) -> void:
				var rows: Array = []
				for row in t.split(";"):
					var xs := row.strip_edges().split(",")
					if xs.size() >= 3:
						rows.append([float(xs[0]), float(xs[1]), float(xs[2])])
				f.params["offsets"] = rows
				_preview()
				_show_feature_panel()
			panel.text_field("ΔX, ΔY, ΔZ", "; ".join(parts), on_tx, "10,0,0; 20,0,5")
			panel.info("Her örnek için mm cinsinden öteleme; örnekleri ; ile ayırın.", Color(0.55, 0.6, 0.66))
	_error_label = panel.info((I18n.t("Hata: ") + f.error) if f.error != "" else "", Color(1.0, 0.45, 0.4))
	panel.spacer()
	panel.info("Enter: Tamam   Esc: İptal", Color(0.55, 0.6, 0.66))


# ---------------------------------------------------------------- referans geometri

func _cmd_ref(type: String) -> void:
	var pre := selection.duplicate()
	_exit_sketch3d()
	if mode == "sketch":
		_exit_sketch()
	if mode == "feature":
		_cancel_feature()
	_leave_aux_mode()
	var f := CadFeature.new()
	f.id = 0
	f.type = type
	match type:
		"refplane":
			var base := "front"
			if pre.get("kind", "") == "plane":
				base = str(pre["id"])
			elif pre.get("kind", "") == "feature" and doc.get_feature(int(pre["id"])) and doc.get_feature(int(pre["id"])).type == "refplane":
				base = "pl:%d" % int(pre["id"])
			f.params = {"mode": "offset", "base": base, "dist": 10.0, "flip": false, "axis": "x", "angle": 45.0, "points": []}
			if pre.get("kind", "") == "face" and pre.get("planar", false):
				var pl := SketchPlane.from_face(pre["point"], pre["normal"])
				f.params["base_plane"] = {"o": RefGeom.arr(pl.origin), "x": RefGeom.arr(pl.x_dir), "y": RefGeom.arr(pl.y_dir)}
		"refaxis":
			f.params = {"mode": "std", "axis": "y", "plane1": "front", "plane2": "right"}
		"refpoint":
			f.params = {"p": [0.0, 0.0, 0.0]}
		"refcsys":
			f.params = {"o": [0.0, 0.0, 0.0], "x": "x", "y": "y", "flip_x": false, "flip_y": false}
		"helix":
			var sid := 0
			if pre.get("kind", "") == "feature":
				var g := doc.get_feature(int(pre["id"]))
				if g and g.is_sketch():
					sid = g.id
			if sid == 0:
				for g2 in doc.sketches():
					for e in g2.sketch.entities:
						if e["type"] == "circle":
							sid = g2.id
			f.params = {"sketch": sid, "mode": "pitch_turns", "pitch": 5.0, "turns": 4.0, "height": 20.0, "start_angle": 0.0, "cw": false, "reverse": false}
	f.name = f.type_label()
	editing = f
	editing_is_new = true
	mode = "feature"
	_pick_target = ""
	_preview()
	_show_feature_panel()
	_set_status(I18n.t("%s: değerleri panelden girin; referans geometri ekranda önizlenir.") % f.type_label())


func _show_ref_panel() -> void:
	var f := editing
	panel.clear()
	panel.title(f.type_label() if editing_is_new else f.name, Icons.get_icon(f.type, 22))
	panel.ok_cancel(_ok_feature, _cancel_feature)
	var p := f.params
	match f.type:
		"refplane":
			var modes := ["offset", "angle", "3pt", "tangent"]
			var on_m := func(i: int) -> void:
				p["mode"] = modes[i]
				_preview()
				_show_feature_panel()
			panel.option("Tür", ["Ofset (paralel)", "Açılı", "Üç nokta", "Yüzeye teğet"], maxi(modes.find(str(p.get("mode", "offset"))), 0), on_m)
			var md := str(p.get("mode", "offset"))
			if md == "tangent":
				panel.info(I18n.t("Teğet nokta: %s") % _fmt_pt(p.get("tan_p")), Color(0.55, 0.85, 1.0))
				_pick_button(I18n.t("Yüzeyde nokta seç (silindir, koni, düzlem...)"), "tan_face")
			elif md != "3pt":
				var face_base := p.get("base_plane") is Dictionary
				var choices := RefGeom.plane_choices(doc, f.id if f.id > 0 else -1)
				var labels: Array = []
				var vals: Array = []
				for c in choices:
					labels.append(c[0])
					vals.append(c[1])
				if face_base:
					labels.append(I18n.t("Seçilen yüz"))
					vals.append("face")
				var on_b := func(i: int) -> void:
					if vals[i] != "face":
						p["base"] = vals[i]
						p.erase("base_plane")
					_preview()
					_show_feature_panel()
				panel.option("Taban", labels, maxi(vals.find("face" if face_base else str(p.get("base", "front"))), 0), on_b)
				_pick_button(I18n.t("Taban için yüz seç"), "base_face")
				if md == "offset":
					var on_d := func(v: float) -> void:
						p["dist"] = v
						_preview()
					panel.number("Mesafe", float(p.get("dist", 10.0)), on_d, "length")
					var on_fl := func(b: bool) -> void:
						p["flip"] = b
						_preview()
					panel.check("Ters yön", bool(p.get("flip", false)), on_fl)
				else:
					var axs := ["x", "y"]
					var on_ax := func(i: int) -> void:
						p["axis"] = axs[i]
						_preview()
					panel.option("Dönme ekseni", ["Tabanın yatay ekseni", "Tabanın dikey ekseni"], maxi(axs.find(str(p.get("axis", "x"))), 0), on_ax)
					var on_an := func(v: float) -> void:
						p["angle"] = v
						_preview()
					panel.number("Açı", float(p.get("angle", 45.0)), on_an, "angle", -360.0, 360.0)
			else:
				var pts: Array = p.get("points", [])
				for i in 3:
					panel.info(I18n.t("Nokta %d: %s") % [i + 1, _fmt_pt(pts[i]) if i < pts.size() else "—"])
				_pick_button(I18n.t("Üç köşe seç"), "points3")
		"refaxis":
			var modes2 := ["std", "2pt", "line", "planes"]
			var on_m2 := func(i: int) -> void:
				p["mode"] = modes2[i]
				_preview()
				_show_feature_panel()
			panel.option("Tür", ["Ana eksen", "İki nokta", "Kenar / silindir ekseni", "İki düzlem kesişimi"], maxi(modes2.find(str(p.get("mode", "std"))), 0), on_m2)
			match str(p.get("mode", "std")):
				"std":
					var axs2 := ["x", "y", "z"]
					var on_a := func(i: int) -> void:
						p["axis"] = axs2[i]
						_preview()
					panel.option("Eksen", ["X", "Y", "Z"], maxi(axs2.find(str(p.get("axis", "y"))), 0), on_a)
				"2pt":
					panel.info(I18n.t("Nokta 1: %s\nNokta 2: %s") % [_fmt_pt(p.get("p1")), _fmt_pt(p.get("p2"))])
					_pick_button(I18n.t("İki köşe seç"), "pt2")
				"line":
					panel.info(I18n.t("Eksen: %s yönünde %s") % [_fmt_pt(p.get("o")), _fmt_pt(p.get("d"))])
					_pick_button(I18n.t("Kenar / silindir seç"), "ref_line")
				"planes":
					var choices2 := RefGeom.plane_choices(doc, f.id if f.id > 0 else -1)
					var labels2: Array = []
					var vals2: Array = []
					for c in choices2:
						labels2.append(c[0])
						vals2.append(c[1])
					var on_p1 := func(i: int) -> void:
						p["plane1"] = vals2[i]
						_preview()
					panel.option("Düzlem 1", labels2, maxi(vals2.find(str(p.get("plane1", "front"))), 0), on_p1)
					var on_p2 := func(i: int) -> void:
						p["plane2"] = vals2[i]
						_preview()
					panel.option("Düzlem 2", labels2, maxi(vals2.find(str(p.get("plane2", "right"))), 0), on_p2)
		"refcsys":
			var ov: Array = p.get("o", [0.0, 0.0, 0.0])
			panel.section("Başlangıç noktası")
			for ai in 3:
				var axis_i := ai
				var on_o := func(v: float) -> void:
					var q: Array = (p.get("o", [0.0, 0.0, 0.0]) as Array).duplicate()
					q[axis_i] = v
					p["o"] = q
					_preview()
				panel.number(["X", "Y", "Z"][ai], float(ov[ai]), on_o, "length")
			_pick_button(I18n.t("Köşe seç"), "csys_o")
			panel.section("Eksenler")
			_axis_option(I18n.t("X ekseni"), "x", "x", "csx")
			var on_fx := func(b: bool) -> void:
				p["flip_x"] = b
				_preview()
			panel.check("X'i ters çevir", bool(p.get("flip_x", false)), on_fx)
			_axis_option(I18n.t("Y ekseni"), "y", "y", "csy")
			var on_fy := func(b: bool) -> void:
				p["flip_y"] = b
				_preview()
			panel.check("Y'yi ters çevir", bool(p.get("flip_y", false)), on_fy)
			if RefGeom.csys_of(doc, f).is_empty():
				f.error = I18n.t("X ve Y eksenleri paralel olamaz")
			else:
				f.error = ""
			panel.info("Kütle özellikleri bu koordinat sistemine göre raporlanabilir.", Color(0.55, 0.6, 0.66))
		"refpoint":
			var pv: Array = p.get("p", [0.0, 0.0, 0.0])
			for ai in 3:
				var axis_i := ai
				var on_c := func(v: float) -> void:
					var q: Array = (p.get("p", [0.0, 0.0, 0.0]) as Array).duplicate()
					q[axis_i] = v
					p["p"] = q
					_preview()
				panel.number(["X", "Y", "Z"][ai], float(pv[ai]), on_c, "length")
			_pick_button(I18n.t("Köşe seç"), "refpoint")
		"helix":
			var sks: Array = []
			var names: Array = []
			var si := 0
			for g in doc.sketches():
				for e in g.sketch.entities:
					if e["type"] == "circle":
						if g.id == int(p.get("sketch", 0)):
							si = sks.size()
						sks.append(g.id)
						names.append(g.name)
						break
			if sks.is_empty():
				panel.info("Önce daire içeren bir taslak çizin (helis çapı ve merkezi daireden alınır).", Color(1.0, 0.75, 0.3))
			else:
				var on_s := func(i: int) -> void:
					p["sketch"] = sks[i]
					_preview()
				panel.option("Daire taslağı", names, si, on_s)
				if int(p.get("sketch", 0)) == 0:
					p["sketch"] = sks[0]
			var kinds := ["helix", "spiral"]
			var on_k := func(i: int) -> void:
				p["kind"] = kinds[i]
				_preview()
				_show_feature_panel()
			panel.option("Tür", ["Helis (silindirik / konik)", "Spiral (düzlemsel)"], maxi(kinds.find(str(p.get("kind", "helix"))), 0), on_k)
			var is_spiral := str(p.get("kind", "helix")) == "spiral"
			var hm := ["pitch_turns", "height_turns", "height_pitch"]
			var on_hm := func(i: int) -> void:
				p["mode"] = hm[i]
				_preview()
				_show_feature_panel()
			if not is_spiral:
				panel.option("Tanım", ["Adım ve tur", "Yükseklik ve tur", "Yükseklik ve adım"], maxi(hm.find(str(p.get("mode", "pitch_turns"))), 0), on_hm)
			var mdh := "pitch_turns" if is_spiral else str(p.get("mode", "pitch_turns"))
			if mdh != "height_turns":
				var on_pi := func(v: float) -> void:
					p["pitch"] = v
					_preview()
				panel.number("Adım", float(p.get("pitch", 5.0)), on_pi, "length", 0.001)
			if mdh != "height_pitch":
				var on_tu := func(v: float) -> void:
					p["turns"] = v
					_preview()
				panel.number("Tur sayısı", float(p.get("turns", 4.0)), on_tu, "plain", 0.01)
			if mdh != "pitch_turns":
				var on_he := func(v: float) -> void:
					p["height"] = v
					_preview()
				panel.number("Yükseklik", float(p.get("height", 20.0)), on_he, "length", 0.001)
			if is_spiral:
				panel.info("Spiralde adım, her turdaki yarıçap artışıdır.", Color(0.55, 0.6, 0.66))
			else:
				var on_tp := func(v: float) -> void:
					p["taper"] = v
					_preview()
				panel.number("Koniklik açısı", float(p.get("taper", 0.0)), on_tp, "angle", -85.0, 85.0)
			var on_sa := func(v: float) -> void:
				p["start_angle"] = v
				_preview()
			panel.number("Başlangıç açısı", float(p.get("start_angle", 0.0)), on_sa, "angle")
			var on_cw := func(b: bool) -> void:
				p["cw"] = b
				_preview()
			panel.check("Saat yönünde", bool(p.get("cw", false)), on_cw)
			var on_rv := func(b: bool) -> void:
				p["reverse"] = b
				_preview()
			panel.check("Ters yön (taslağın arkasına)", bool(p.get("reverse", false)), on_rv)
			var hs := RefGeom.helix_spec(doc, f)
			if not hs.has("error"):
				var hpts := RefGeom.helix_points(hs)
				var hl := 0.0
				for hi in hpts.size() - 1:
					hl += hpts[hi].distance_to(hpts[hi + 1])
				panel.info(I18n.t("Uzunluk: %s") % Units.format_length(hl), Color(0.55, 0.85, 1.0))
				f.error = ""
			else:
				f.error = hs["error"]
	var err := f.error
	if f.type == "refplane" and f.plane == null:
		err = I18n.t("Düzlem tanımı geçersiz")
	_error_label = panel.info((I18n.t("Hata: ") + err) if err != "" else "", Color(1.0, 0.45, 0.4))
	panel.spacer()
	panel.info("Enter: Tamam   Esc: İptal", Color(0.55, 0.6, 0.66))


# ---------------------------------------------------------------- referans geometri çizimi ve seçimi

func _draw_reference(lb: LineBuilder) -> void:
	var list: Array = doc.features.duplicate()
	if mode == "feature" and editing and (editing.is_reference() or editing.type == "hole" or editing.type == "projcurve"):
		var idx := doc.index_of(editing.id)
		if idx >= 0:
			list[idx] = editing
		else:
			list.append(editing)
	var S := viewport.plane_half * 0.6
	var w := viewport.camera.world_per_pixel()
	for f in list:
		if f.suppressed or (doc.index_of(f.id) >= 0 and doc.is_rolled_back(f)):
			continue
		var sel: bool = (selection.get("kind", "") == "feature" and selection.get("id", -1) == f.id) or f == editing
		var col := Color(0.1, 0.45, 1.0) if sel else Color(0.45, 0.4, 0.7)
		match f.type:
			"refplane":
				if f.plane == null:
					continue
				var pl: SketchPlane = f.plane
				var c := [pl.to_world(Vector2(-S, -S)), pl.to_world(Vector2(S, -S)), pl.to_world(Vector2(S, S)), pl.to_world(Vector2(-S, S))]
				for i in 4:
					lb.line(c[i], c[(i + 1) % 4], col)
				lb.line(c[0], c[0].lerp(c[1], 0.12), col)
				lb.line(c[0], c[0].lerp(c[3], 0.12), col)
			"refaxis":
				var ax := RefGeom.axis_of(doc, f, editing)
				if ax.is_empty():
					continue
				var o: Vector3 = ax["o"]
				var d: Vector3 = ax["d"]
				lb.dashed(o - d * S * 1.5, o + d * S * 1.5, col, 6.0 * w, 2.0 * w)
			"refpoint":
				var p := RefGeom.point_of(f)
				var cam := viewport.camera.global_transform.basis
				lb.line(p - cam.x * 5.0 * w, p + cam.x * 5.0 * w, col)
				lb.line(p - cam.y * 5.0 * w, p + cam.y * 5.0 * w, col)
			"helix":
				var hs := RefGeom.helix_spec(doc, f)
				if not hs.has("error"):
					lb.polyline(RefGeom.helix_points(hs), col)
			"refcsys":
				var cs := RefGeom.csys_of(doc, f, editing)
				if cs.is_empty():
					continue
				var L := S * 0.35
				var co: Vector3 = cs["o"]
				lb.line(co, co + (cs["x"] as Vector3) * L, Color(0.9, 0.2, 0.2))
				lb.line(co, co + (cs["y"] as Vector3) * L, Color(0.2, 0.7, 0.25))
				lb.line(co, co + (cs["z"] as Vector3) * L, Color(0.2, 0.4, 0.95))
			"projcurve":
				for ch in f.runtime.get("poly", []):
					var pts := PackedVector3Array()
					for q in ch:
						pts.append(ModelMesh._v3(q))
					lb.polyline(pts, Color(0.1, 0.45, 1.0) if sel else Color(0.75, 0.3, 0.85))
			"hole":
				# Kozmetik diş (kılavuz deliklerde majör çapta kesikli daire) ve düzenlemede konum işaretleri
				var fc: Dictionary = f.params.get("face", {})
				if fc.is_empty():
					continue
				var n := ModelMesh._v3(fc.get("n", [0, 1, 0])).normalized()
				var dims := HoleTable.dims(str(f.params.get("std", "ISO")), str(f.params.get("htype", "simple")), str(f.params.get("size", "M6")), "normal")
				for q in f.params.get("points", []):
					var cp := ModelMesh._v3(q)
					var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
					var v := n.cross(u)
					if str(f.params.get("htype", "")) == "tap" and not dims.is_empty():
						var r := float(dims["major"]) * 0.5
						var prev := cp + u * r + n * 0.02
						for k in range(1, 49):
							var a := TAU * k / 48.0
							var nx := cp + (u * cos(a) + v * sin(a)) * r + n * 0.02
							if k % 2 == 0:
								lb.line(prev, nx, Color(0.15, 0.35, 0.9))
							prev = nx
					if f == editing:
						lb.line(cp - u * 6.0 * w, cp + u * 6.0 * w, Color(0.95, 0.38, 0.0))
						lb.line(cp - v * 6.0 * w, cp + v * 6.0 * w, Color(0.95, 0.38, 0.0))


## Ekran noktasına yakın referans geometri (düzlem kenarı, eksen, nokta, helis). Dönüş: özellik kimliği veya -1.
func _pick_reference(pos: Vector2) -> int:
	var S := viewport.plane_half * 0.6
	var best := -1
	var bd := 7.0
	for f in doc.features:
		if f.suppressed or doc.is_rolled_back(f):
			continue
		var segs: Array = []
		match f.type:
			"refplane":
				if f.plane:
					var c := [f.plane.to_world(Vector2(-S, -S)), f.plane.to_world(Vector2(S, -S)), f.plane.to_world(Vector2(S, S)), f.plane.to_world(Vector2(-S, S))]
					for i in 4:
						segs.append([c[i], c[(i + 1) % 4]])
			"refaxis":
				var ax := RefGeom.axis_of(doc, f)
				if not ax.is_empty():
					segs.append([(ax["o"] as Vector3) - (ax["d"] as Vector3) * S * 1.5, (ax["o"] as Vector3) + (ax["d"] as Vector3) * S * 1.5])
			"refpoint":
				var p := RefGeom.point_of(f)
				segs.append([p, p])
			"helix":
				var hs := RefGeom.helix_spec(doc, f)
				if not hs.has("error"):
					var hp := RefGeom.helix_points(hs)
					for i in hp.size() - 1:
						segs.append([hp[i], hp[i + 1]])
			"refcsys":
				var cs := RefGeom.csys_of(doc, f)
				if not cs.is_empty():
					for k in ["x", "y", "z"]:
						segs.append([cs["o"], (cs["o"] as Vector3) + (cs[k] as Vector3) * S * 0.35])
			"projcurve":
				for ch in f.runtime.get("poly", []):
					for i in (ch as Array).size() - 1:
						segs.append([ModelMesh._v3(ch[i]), ModelMesh._v3(ch[i + 1])])
		for sgm in segs:
			var a := viewport.world_to_screen(sgm[0])
			var b := viewport.world_to_screen(sgm[1])
			var d := Geometry2D.get_closest_point_to_segment(pos, a, b).distance_to(pos)
			if d < bd:
				bd = d
				best = f.id
	return best


# ---------------------------------------------------------------- geri alma çubuğu, sıralama, ebeveyn/çocuk

func _set_rollback(index: int) -> void:
	if mode == "feature":
		_cancel_feature()
	doc.checkpoint()
	doc.set_rollback(index)
	doc.commit()
	_set_status(I18n.t("Geri alma çubuğu kaldırıldı: tüm özellikler hesaplanıyor.") if doc.rollback < 0 else I18n.t("Geri alma çubuğu: ilk %d özellik etkin, sonrakiler hesaplanmıyor.") % doc.rollback)


func _move_feature(id: int, new_index: int) -> bool:
	doc.checkpoint()
	if doc.move_feature(id, new_index):
		doc.commit()
		_set_status("Özellik taşındı.")
		return true
	doc.drop_checkpoint()
	_set_status("Taşınamaz: bir özellik ebeveyninden önce veya çocuğundan sonra olamaz.")
	return false


func _on_tree_move(data: Dictionary, target_id: int, after: bool) -> void:
	var ti := doc.index_of(target_id) if target_id >= 0 else doc.features.size() - 1
	if target_id >= 0 and not after:
		ti -= 1
	# ti: hedef konumdan hemen önceki özellik indeksi
	if data.get("kind", "") == "rollback":
		_set_rollback(ti + 1)
		return
	var id := int(data.get("id", -1))
	var old := doc.index_of(id)
	if old < 0:
		return
	var ni := ti + 1
	if old < ni:
		ni -= 1
	if ni != old:
		_move_feature(id, ni)


func _show_parents(f: CadFeature) -> void:
	var lines: Array = ["%s (%s)" % [f.name, f.type_label()], "", I18n.t("Ebeveynler:")]
	var ps := doc.parents_of(f)
	if ps.is_empty():
		lines.append(I18n.t("  (yok)"))
	for pid in ps:
		var g := doc.get_feature(pid)
		lines.append("  • %s (%s)" % [g.name, g.type_label()])
	lines.append("")
	lines.append(I18n.t("Çocuklar:"))
	var cs := doc.children_of(f.id)
	if cs.is_empty():
		lines.append(I18n.t("  (yok)"))
	for cid in cs:
		var g2 := doc.get_feature(cid)
		lines.append("  • %s (%s)" % [g2.name, g2.type_label()])
	info_dialog.dialog_text = "\n".join(lines)
	info_dialog.popup_centered()


# ================================================================ FAZ 5 kalanları

var _mass_csys := -1        # kütle özellikleri için koordinat sistemi (özellik kimliği, -1: global)


## Yol / kılavuz / eğri olarak seçilebilecek eğriler: [{kind, id, name}]
func _curve_candidates(exclude: Array) -> Array:
	var out: Array = []
	for g in doc.features:
		if g.id in exclude or g.suppressed:
			continue
		var kind := ""
		match g.type:
			"helix":
				kind = "helix"
			"sketch3d":
				kind = "sketch3d"
			"projcurve":
				kind = "projcurve"
			"sketch":
				if not g.sketch.curve_chains().is_empty():
					kind = "sketch"
		if kind != "":
			out.append({"kind": kind, "id": g.id, "name": g.name})
	return out


## Eğri seçimi açılır listesi. allow_none: "Yok" seçeneği (kılavuz için).
func _curve_option(label: String, key: String, exclude: Array, allow_none: bool) -> void:
	var f := editing
	var cands := _curve_candidates(exclude)
	var labels: Array = []
	var vals: Array = []
	if allow_none:
		labels.append("Yok")
		vals.append({})
	for c in cands:
		labels.append(c["name"])
		vals.append({"kind": c["kind"], "id": c["id"]})
	var cur: Dictionary = f.params.get(key, {}) if f.params.get(key) is Dictionary else {}
	var sel := 0
	for i in vals.size():
		if (vals[i] as Dictionary).get("id", -1) == cur.get("id", -2):
			sel = i
	if vals.is_empty():
		panel.info("Uygun eğri yok (taslak zinciri, 3B taslak, helis veya projeksiyon eğrisi oluşturun).", Color(1.0, 0.75, 0.3))
		return
	if not allow_none and cur.is_empty():
		f.params[key] = vals[0]
	var on_sel := func(i: int) -> void:
		if (vals[i] as Dictionary).is_empty():
			f.params.erase(key)
		else:
			f.params[key] = vals[i]
		_preview()
	panel.option(label, labels, sel, on_sel)


func _show_sketchfeat_panel() -> void:
	var f := editing
	panel.clear()
	panel.title(f.type_label() if editing_is_new else f.name, Icons.get_icon(f.type, 22))
	panel.ok_cancel(_ok_feature, _cancel_feature)
	var sks := doc.sketches()
	var names: Array = []
	var si := 0
	for i in sks.size():
		names.append(sks[i].name)
		if sks[i].id == f.sketch_ref():
			si = i
	var on_s := func(i: int) -> void:
		f.params["sketch"] = sks[i].id
		_preview()
	panel.section("Taslak")
	panel.option("Taslak", names, si, on_s)
	match f.type:
		"projcurve":
			panel.section("Hedef yüz")
			panel.info(I18n.t("Yüz: ") + (I18n.t("seçili") if not (f.params.get("face", {}) as Dictionary).is_empty() else I18n.t("seçilmedi")), Color(0.55, 0.85, 1.0))
			_pick_button(I18n.t("Hedef yüzü seç"), "face")
			panel.info("Taslak eğrisi, taslak düzlemine dik doğrultuda yüze izdüşürülür. Sonuç süpürme yolu, kılavuz veya çoğaltma eğrisi olarak kullanılabilir.", Color(0.55, 0.6, 0.66))
		"wrap":
			panel.section("Silindirik yüz")
			panel.info(I18n.t("Yüz: ") + (I18n.t("seçili") if not (f.params.get("face", {}) as Dictionary).is_empty() else I18n.t("seçilmedi")), Color(0.55, 0.85, 1.0))
			_pick_button(I18n.t("Silindirik yüzü seç"), "face")
			var wts := ["emboss", "deboss", "scribe"]
			var on_wt := func(i: int) -> void:
				f.params["wtype"] = wts[i]
				_preview()
				_show_feature_panel()
			panel.option("Tür", ["Kabartma (dışa)", "Oyma (içe)", "Çizgi (yüzeyi böl)"], maxi(wts.find(str(f.params.get("wtype", "emboss"))), 0), on_wt)
			if str(f.params.get("wtype", "emboss")) != "scribe":
				var on_d := func(v: float) -> void:
					f.params["depth"] = v
					_preview()
				panel.number("Derinlik", float(f.params.get("depth", 1.0)), on_d, "length", 0.001)
			panel.info("Taslak düzlemi silindir eksenine paralel olmalı (ör. silindire teğet referans düzlem). Taslak yay uzunluğu korunarak sarılır.", Color(0.55, 0.6, 0.66))
		"emboss":
			var ets := ["emboss", "deboss"]
			var on_et := func(i: int) -> void:
				f.params["etype"] = ets[i]
				_preview()
			panel.option("Tür", ["Kabartma (yükselt)", "Gravür (oy)"], maxi(ets.find(str(f.params.get("etype", "emboss"))), 0), on_et)
			var on_h := func(v: float) -> void:
				f.params["depth"] = v
				_preview()
			panel.number("Yükseklik / derinlik", float(f.params.get("depth", 1.0)), on_h, "length", 0.001)
			var on_rv := func(b: bool) -> void:
				f.params["reverse"] = b
				_preview()
			panel.check("Yönü ters çevir", bool(f.params.get("reverse", false)), on_rv)
			panel.info("Profil taslak normali doğrultusunda gövdenin ilk karşılaştığı yüzeylere izdüşer; kabartma yüzeyi izleyerek sabit kalınlıkta eklenir.", Color(0.55, 0.6, 0.66))
	_error_label = panel.info((I18n.t("Hata: ") + f.error) if f.error != "" else "", Color(1.0, 0.45, 0.4))
	panel.spacer()
	panel.info("Enter: Tamam   Esc: İptal", Color(0.55, 0.6, 0.66))


## Kütle özelliklerini seçili koordinat sistemine göre dönüştürür (ağırlık merkezi ve tensör eksenleri).
func _apply_mass_csys() -> void:
	if _mass_csys < 0 or _mass_result.is_empty():
		return
	var cf := doc.get_feature(_mass_csys)
	if cf == null:
		_mass_csys = -1
		return
	var cs := RefGeom.csys_of(doc, cf)
	if cs.is_empty():
		return
	var R := [cs["x"], cs["y"], cs["z"]]
	var c: Vector3 = (_mass_result["center"] as Vector3) - (cs["o"] as Vector3)
	_mass_result["cx"] = c.dot(R[0])
	_mass_result["cy"] = c.dot(R[1])
	_mass_result["cz"] = c.dot(R[2])
	var t: Array = _mass_result["tensor"]
	var tl := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for i in 3:
		for j in 3:
			var acc := 0.0
			for a in 3:
				for b in 3:
					acc += float(R[i][a]) * float(t[a][b]) * float(R[j][b])
			tl[i][j] = acc
	_mass_result["tensor"] = tl
	_mass_result["csys"] = cf.name


# ================================================================ FAZ 6: TEKNİK RESİM

var toolbar_drawing: HFlowContainer
var asm_mode: AssemblyMode
var special: SpecialUI
var drawing_canvas: DrawingCanvas
var _dw_index := 0
var _dw_geo := {}            # sayfa indeksi → {görünüş kimliği → HLR sonucu}
var _dw_keys := {}           # sayfa indeksi → {görünüş kimliği → istek anahtarı}
var _dw_sig := ""            # model imzası (değişince görünüşler yeniden hesaplanır)
var _dw_tool := "select"
var _dw_sel := {}            # {kind: "view"|"ann", id}
var _dw_pts: Array = []      # araç adımları
var _dw_bboxes := {}
var _dw_drag := {}
var _dw_orient := "front"
var _dw_req_sheet := -1
var _dw_pending := 0       # yanıt bekleyen HLR isteği sayısı

const DW_TOOL_HINTS := {
	"select": "Seç: görünüş veya açıklamaya tıklayın, sürükleyerek taşıyın; Delete siler.",
	"model": "Model görünüşü: yerleştirmek için sayfaya tıklayın (yönelim panelden).",
	"proj": "İzdüşüm görünüşü: seçili görünüşün sağına/soluna/üstüne/altına tıklayın.",
	"section": "Kesit: seçili görünüşte kesit çizgisinin iki ucuna tıklayın.",
	"detail": "Detay: seçili görünüşte önce merkeze, sonra daire kenarına tıklayın.",
	"aux": "Yardımcı görünüş: seçili görünüşte bir kenara tıklayın (görünüş kenara dik bakar).",
	"break": "Kırık görünüş: seçili görünüşte kaldırılacak bölgenin iki sınırına tıklayın.",
	"dim": "Akıllı boyut: köşe/daire/kenara tıklayın; ikinci öğe ve ardından boyutun yerine tıklayın.",
	"cmark": "Merkez işareti: bir daireye tıklayın.",
	"cline": "Merkez çizgisi: iki noktaya tıklayın.",
	"note": "Not: yerleştirmek için tıklayın (metni panelden düzenleyin).",
	"balloon": "Balon: önce gösterilecek noktaya, sonra balonun yerine tıklayın.",
	"surface": "Yüzey pürüzlülüğü: sembolün yerine tıklayın.",
	"gdt": "Geometrik tolerans: önce gösterilecek noktaya, sonra çerçevenin yerine tıklayın.",
	"datum": "Datum: önce yüzey/kenara, sonra etiketin yerine tıklayın.",
	"weld": "Kaynak sembolü: önce kaynak yerine, sonra referans çizgisinin yerine tıklayın.",
}


func _build_drawing_toolbar(cm: Control) -> void:
	toolbar_drawing = HFlowContainer.new()
	toolbar_drawing.set_meta("group", "Teknik Resim")
	toolbar_drawing.visible = false
	cm.add_child(toolbar_drawing)
	var items := [
		["Seç", "select", "Görünüş veya açıklama seç, sürükle", "dw_select"],
		["Sayfa", "dw_sheet", "Sayfa boyutu, standart, izdüşüm açısı, antet, sayfalar", "dw_sheetprops"], [],
		["Standart\n3 Görünüş", "dw_std3", "Ön, üst, yan ve izometrik görünüşleri yerleştir", "dw_std3"],
		["Model\nGörünüşü", "dw_model", "Seçilen yönelimde (ön, üst, izometrik...) görünüş ekle", "dw_model"],
		["İzdüşüm\nGörünüşü", "dw_proj", "Seçili görünüşten izdüşüm görünüşü türet", "dw_proj"],
		["Kesit\nGörünüşü", "dw_section", "Seçili görünüşte kesit çizgisi çiz", "dw_section"],
		["Detay\nGörünüşü", "dw_detail", "Seçili görünüşün bir bölgesini büyüt", "dw_detail"],
		["Yardımcı\nGörünüş", "dw_aux", "Bir kenara dik bakan görünüş", "dw_aux"],
		["Kırık\nGörünüş", "dw_break", "Uzun görünüşün ortasını kaldır", "dw_break"], [],
		["Akıllı\nBoyut", "dimension", "Uzunluk, çap, yarıçap, açı boyutu", "dw_dim"],
		["Model\nBoyutları", "dw_modeldims", "Taslak boyutlarını görünüşlere aktar (ilişkili)", "dw_modeldims"],
		["Merkez\nİşareti", "dw_cmark", "Daireye merkez işareti", "dw_cmark"],
		["Merkez\nÇizgisi", "centerline", "İki nokta arasında eksen çizgisi", "dw_cline"],
		["Not", "text", "Metin notu (isteğe bağlı oklu)", "dw_note"],
		["Balon", "dw_balloon", "Parça numarası balonu", "dw_balloon"],
		["Otomatik\nBalon", "dw_autoballoon", "Malzeme listesindeki her kalem için balon (montaj resminde)", "dw_autoballoon"],
		["Yüzey\nPürüzlülüğü", "dw_surface", "Yüzey işleme sembolü (Ra)", "dw_surface"],
		["Geometrik\nTolerans", "dw_gdt", "GD&T kontrol çerçevesi", "dw_gdt"],
		["Datum", "dw_datum", "Datum özellik sembolü", "dw_datum"],
		["Kaynak\nSembolü", "dw_weld", "Kaynak sembolü (köşe / alın)", "dw_weld"], [],
		["Malzeme\nListesi", "dw_bom", "Malzeme listesini göster / gizle", "dw_bom"],
		["Revizyon\nEkle", "dw_rev", "Revizyon tablosuna satır ekle", "dw_rev"], [],
		["Dışa\nAktar", "export", "Sayfayı dışa aktar: PDF, DXF, SVG, AI, görüntü... (Ctrl+E)", "dw_export_all"],
		["Yazdır", "dw_print", "PDF'i varsayılan uygulamada aç ve yazdır", "dw_print"],
	]
	for it in items:
		if it.is_empty():
			toolbar_drawing.add_child(VSeparator.new())
			continue
		_tb(toolbar_drawing, it[0], it[1], it[2], _dw_cmd.bind(it[3]), false, 64)


func _dw_sheet() -> Dictionary:
	if _dwd().drawings.is_empty():
		return {}
	_dw_index = clampi(_dw_index, 0, _dwd().drawings.size() - 1)
	return _dwd().drawings[_dw_index]


func _enter_drawing() -> void:
	var in_asm := mode == "assembly" and asm_mode.is_open()
	if in_asm != _dw_in_asm:
		_dw_geo.clear()
		_dw_keys.clear()
		_dw_sig = ""
		_dw_index = 0
	_dw_in_asm = in_asm
	if in_asm:
		asm_mode.leave()
	_exit_sketch3d()
	if mode == "sketch":
		_exit_sketch()
	if mode == "feature":
		_cancel_feature()
	_leave_aux_mode()
	# Önceki moddan çıkış sekmeyi değiştirmiş olabilir: Teknik Resim sekmesini geri seç
	if tabs.current_tab != 3:
		tabs.set_block_signals(true)
		tabs.current_tab = 3
		tabs.set_block_signals(false)
	toolbar_features.visible = false
	toolbar_sketch.visible = false
	toolbar_eval.visible = false
	toolbar_drawing.visible = true
	mode = "drawing"
	viewport.visible = false
	drawing_canvas.visible = true
	_dw_tool = "select"
	_dw_pts.clear()
	if _dwd().drawings.is_empty():
		_dwd().checkpoint()
		var sh := Drawing.new_sheet("Sayfa1", "A3", "ISO")
		_dwd().drawings.append(sh)
		_dw_index = 0
		if not _dw_no_model():
			_dw_std_views(sh)
		_dw_commit()
	_dw_request_hlr()
	_dw_render()
	_refresh_panel()
	drawing_canvas.fit()
	_set_status("Teknik Resim: araç çubuğundan görünüş, boyut ve açıklama ekleyin. Tekerlek: yakınlaştır, sağ/orta tuş: kaydır.")


func _exit_drawing() -> void:
	_dw_in_asm = false
	drawing_canvas.visible = false
	viewport.visible = true
	_dw_tool = "select"
	_dw_pts.clear()
	if mode != "drawing":
		return
	mode = "idle"
	viewport.visible = true
	_dw_sel = {}
	_refresh_panel()


func _dw_model_sig() -> String:
	if _dw_in_asm:
		var t := ""
		for c in asm_mode.asm.comps:
			t += "%d:%s:%d|" % [int(c["id"]), str(c["xf"]), int(asm_mode.parts.get(asm_mode.asm.key_of(c), {}).get("ver", 0))]
		return t
	var m := viewport.model
	return "%d|%s|%d|%d" % [m.tri_count(), str(m.exact_mass.get("volume", m.volume_and_area().x)), m.brep_faces.size(), m.brep_edges.size()]


func _dw_view_req(sh: Dictionary, v: Dictionary) -> Dictionary:
	var ax := Drawing.view_axes(sh, v)
	var req := {"id": int(v["id"]), "dir": Drawing.a3(ax["dir"]), "x": Drawing.a3(ax["x"])}
	if v.get("type", "") == "section":
		var sec: Dictionary = v.get("section", {})
		req["section"] = {"o": sec["o"], "n": sec["n"]}
	return req


## Değişen görünüşler için gizli çizgi hesabı ister (OpenCASCADE); yoksa ağ kenarlarından yaklaşık görünüş.
func _dw_request_hlr() -> void:
	var sh := _dw_sheet()
	if sh.is_empty() or _dw_no_model() or viewport.kernel.is_busy():
		return  # model hazır olunca _on_built yeniden ister
	var sig := _dw_model_sig()
	if sig != _dw_sig:
		_dw_sig = sig
		_dw_keys.clear()
	var keys: Dictionary = _dw_keys.get(_dw_index, {})
	var geo: Dictionary = _dw_geo.get(_dw_index, {})
	var reqs: Array = []
	for v in sh.get("views", []):
		if v.get("type", "") == "detail":
			continue
		var r := _dw_view_req(sh, v)
		var key := JSON.stringify(r)
		if keys.get(int(v["id"]), "") != key or not geo.has(int(v["id"])):
			keys[int(v["id"])] = key
			reqs.append(r)
	_dw_keys[_dw_index] = keys
	_dw_geo[_dw_index] = geo
	if reqs.is_empty():
		return
	if viewport.kernel.is_brep() and viewport.kernel.occ.is_ready():
		_dw_req_sheet = _dw_index
		if viewport.kernel.request_hlr(reqs, _dw_comps()):
			_dw_pending += 1
	else:
		for r in reqs:
			geo[int(r["id"])] = _dw_mesh_geo(r)
		_dw_render()


## OpenCASCADE yoksa: ağ özellik kenarlarının izdüşümü (gizli çizgi kaldırılmaz).
func _dw_mesh_geo(r: Dictionary) -> Dictionary:
	if r.has("section"):
		return {"error": I18n.t("Kesit görünüşü OpenCASCADE çekirdeği gerektirir")}
	var ax := {"dir": Drawing.v3(r["dir"]), "x": Drawing.v3(r["x"])}
	var vis: Array = []
	var fe := _dw_feature_edges()
	for i in range(0, fe.size() - 1, 2):
		var a := Drawing.project(ax, fe[i])
		var b := Drawing.project(ax, fe[i + 1])
		vis.append([[a.x, a.y], [b.x, b.y]])
	return {"visible": vis, "hidden": [], "tangent": [], "circles": [], "hatch": []}


func _on_hlr_done(res: Dictionary) -> void:
	_dw_pending = maxi(0, _dw_pending - 1)
	var si := _dw_req_sheet
	if si < 0:
		return
	var geo: Dictionary = _dw_geo.get(si, {})
	if not bool(res.get("ok", false)):
		_dw_keys.erase(si)  # sonraki yapımda yeniden denensin
		if not _dw_no_model():
			_set_status(I18n.t("Görünüşler hesaplanamadı: ") + str(res.get("error", "")))
	for v in res.get("views", []):
		geo[int(v["id"])] = v
	_dw_geo[si] = geo
	if mode == "drawing" and si == _dw_index:
		_dw_render()


func _dw_render() -> void:
	if drawing_canvas == null or mode != "drawing":
		return
	var sh := _dw_sheet()
	if sh.is_empty():
		drawing_canvas.set_content([], Vector2(420, 297))
		return
	var opts := {"sel_views": [int(_dw_sel["id"])] if _dw_sel.get("kind", "") == "view" else [],
		"sel_anns": [int(_dw_sel["id"])] if _dw_sel.get("kind", "") == "ann" else []}
	if not _dw_no_model():
		opts["mass"] = _dw_mass()
	if _dw_in_asm:
		opts["bom_rows"] = _dw_asm_bom()
	var prims := DrawingRender.build(_dwd(), sh, _dw_geo.get(_dw_index, {}), opts)
	_dw_bboxes = opts["bboxes"]
	drawing_canvas.set_content(prims, Drawing.sheet_size(sh))


func _dw_change(fn: Callable) -> void:
	_dwd().checkpoint()
	fn.call()
	_dw_commit()


func _dw_std_views(sh: Dictionary) -> void:
	var lay := Drawing.standard_layout(sh, _dw_aabb())
	sh["scale"] = lay["scale"]
	var front_id := -1
	for item in lay["views"]:
		var id := Drawing.next_id(sh)
		var v := {"id": id, "type": "model", "pos": Drawing.a2(item["pos"]), "hidden": "visible_hidden", "tangent": "show"}
		if item.has("orient"):
			v["orient"] = item["orient"]
			if item["orient"] == "front":
				front_id = id
			if item["orient"] == "iso":
				v["hidden"] = "removed"
		else:
			var fa := Drawing.view_axes(sh, Drawing.find_view(sh, front_id))
			var ax := Drawing.projected_axes(fa["dir"], fa["x"], item["side"], str(sh.get("proj", "first")))
			v["type"] = "projected"
			v["parent"] = front_id
			v["side"] = item["side"]
			v["dir"] = Drawing.a3(ax["dir"])
			v["x"] = Drawing.a3(ax["x"])
		sh["views"].append(v)


func _dw_set_tool(t: String) -> void:
	_dw_tool = t
	_dw_pts.clear()
	drawing_canvas.overlay = []
	drawing_canvas.queue_redraw()
	_set_status(str(DW_TOOL_HINTS.get(t, "")))
	_refresh_panel()


func _dw_need_view() -> Dictionary:
	var sh := _dw_sheet()
	if _dw_sel.get("kind", "") != "view":
		_set_status("Önce bir görünüş seçin (Seç aracıyla görünüşe tıklayın).")
		return {}
	return Drawing.find_view(sh, int(_dw_sel["id"]))


func _dw_cmd(c: String) -> void:
	if mode != "drawing":
		_show_toolbar(3)
	var sh := _dw_sheet()
	if sh.is_empty() and c != "dw_select":
		# Sayfa yoksa (ör. ilk sayfa geri alındıysa) yeni A3 sayfası aç
		var mk := func() -> void: _dwd().drawings.append(Drawing.new_sheet("Sayfa1", "A3", "ISO"))
		_dw_change(mk)
		_dw_index = 0
		sh = _dw_sheet()
		_dw_render()
	match c:
		"dw_export_all":
			_open_export_dialog()
		"dw_select":
			_dw_set_tool("select")
		"dw_sheetprops":
			_dw_sel = {}
			_dw_set_tool("select")
			_dw_render()
		"dw_std3":
			if _dw_no_model():
				_set_status("Önce bir katı model oluşturun.")
				return
			var std := func() -> void: _dw_std_views(sh)
			_dw_change(std)
			_dw_request_hlr()
		"dw_model", "dw_dim", "dw_cmark", "dw_cline", "dw_note", "dw_balloon", "dw_surface", "dw_gdt", "dw_datum", "dw_weld":
			_dw_set_tool(c.substr(3))
		"dw_proj", "dw_section", "dw_detail", "dw_aux", "dw_break":
			if _dw_need_view().is_empty():
				return
			_dw_set_tool(c.substr(3))
		"dw_modeldims":
			var n := [0]
			var imp := func() -> void: n[0] = _dw_import_model_dims(sh)
			_dw_change(imp)
			_set_status(I18n.t("%d model boyutu görünüşlere aktarıldı.") % n[0])
		"dw_autoballoon":
			var nb := [0]
			var ab := func() -> void: nb[0] = _dw_auto_balloons(sh)
			_dw_change(ab)
			_dw_render()
			_set_status(I18n.t("%d balon yerleştirildi.") % nb[0])
		"dw_bom":
			var tb := func() -> void: sh["bom"] = not bool(sh.get("bom", false))
			_dw_change(tb)
		"dw_rev":
			var revs: Array = sh.get("revs", [])
			var letters := "ABCDEFGHJKLMNPRSTUVWXYZ"
			var ar := func() -> void:
				revs.append({"rev": letters[revs.size() % letters.length()], "desc": DrawingRender.sheet_t("Açıklama"), "date": Time.get_date_string_from_system(), "by": ""})
				sh["revs"] = revs
				var t: Dictionary = sh.get("title", {})
				t["rev"] = revs[revs.size() - 1]["rev"]
			_dw_change(ar)
		"dw_pdf":
			_file_dialog(true, ["*.pdf ; PDF"], "Teknik resmi PDF olarak kaydet", "dw_pdf", _dwd().part_name + ".pdf")
		"dw_svg":
			_file_dialog(true, ["*.svg ; SVG"], "Teknik resmi SVG olarak kaydet", "dw_svg", _dwd().part_name + ".svg")
		"dw_dxf":
			_file_dialog(true, ["*.dxf ; DXF"], "Teknik resmi DXF olarak kaydet", "dw_dxf", _dwd().part_name + "_resim.dxf")
		"dw_print":
			var pth := OS.get_user_data_dir().path_join("yazdir.pdf")
			if _dw_export("dw_pdf", pth) == OK:
				OS.shell_open(pth)
				_set_status("PDF varsayılan uygulamada açıldı; oradan yazdırabilirsiniz.")


func _dw_export(kind: String, path: String) -> Error:
	var sh := _dw_sheet()
	if sh.is_empty():
		return ERR_DOES_NOT_EXIST
	var opts := {}
	if not _dw_no_model():
		opts["mass"] = _dw_mass()
	if _dw_in_asm:
		opts["bom_rows"] = _dw_asm_bom()
	var prims := DrawingRender.build(_dwd(), sh, _dw_geo.get(_dw_index, {}), opts)
	var size := Drawing.sheet_size(sh)
	match kind:
		"dw_pdf":
			return DrawingExport.write_pdf(path, [{"size": size, "prims": prims}], _dwd().part_name)
		"dw_svg":
			return DrawingExport.write_svg(path, size, prims)
		"dw_dxf":
			return DrawingExport.write_dxf(path, prims)
	return ERR_INVALID_PARAMETER


# ---------------------------------------------------------------- seçim ve yakalama

func _dw_view_at(p: Vector2) -> Dictionary:
	var sh := _dw_sheet()
	var best := {}
	var best_area := INF
	for v in sh.get("views", []):
		var bb: Rect2 = _dw_bboxes.get(int(v["id"]), Rect2())
		if bb.grow(3.0).has_point(p):
			var area := bb.get_area()
			if area < best_area:
				best_area = area
				best = v
	return best


func _dw_ann_anchor(sh: Dictionary, a: Dictionary) -> Vector2:
	if a.has("pos"):
		return Drawing.v2(a["pos"])
	var v := Drawing.find_view(sh, int(a.get("view", -1)))
	if v.is_empty():
		return Vector2(-1e9, -1e9)
	match str(a.get("type", "")):
		"dim":
			return Drawing.view_to_sheet(sh, v, Drawing.v2(a.get("off", [0, 0])))
		"centermark":
			return Drawing.view_to_sheet(sh, v, Drawing.v2(a["c"]))
		"centerline":
			return (Drawing.view_to_sheet(sh, v, Drawing.v2(a["a"])) + Drawing.view_to_sheet(sh, v, Drawing.v2(a["b"]))) * 0.5
	return Vector2(-1e9, -1e9)


func _dw_ann_at(p: Vector2) -> Dictionary:
	var sh := _dw_sheet()
	var best := {}
	var bd := 5.0
	for a in sh.get("anns", []):
		var d := _dw_ann_anchor(sh, a).distance_to(p)
		if d < bd:
			bd = d
			best = a
	return best


## Görünüşte yakalama: want sırasına göre "point" (köşe, daire merkezi), "circle", "line".
func _dw_snap(v: Dictionary, p: Vector2, want: Array) -> Dictionary:
	var sh := _dw_sheet()
	var g := DrawingRender.view_geometry(sh, v, _dw_geo.get(_dw_index, {}))
	var q := Drawing.sheet_to_view(sh, v, p)
	var tol := 3.0 / Drawing.view_scale(sh, v)
	for kind in want:
		match kind:
			"point":
				var best := {}
				var bd := tol
				for cc in g.get("circles", []):
					var c := Drawing.v2(cc["c"])
					if c.distance_to(q) < bd:
						bd = c.distance_to(q)
						best = {"kind": "point", "p": c}
				for pl in g.get("visible", []) + g.get("hidden", []):
					var pts: PackedVector2Array = pl
					if pts.size() == 0:
						continue
					for e in ([pts[0], pts[pts.size() - 1]] if pts.size() > 2 else Array(pts)):
						if (e as Vector2).distance_to(q) < bd:
							bd = (e as Vector2).distance_to(q)
							best = {"kind": "point", "p": e}
				if not best.is_empty():
					return best
			"circle":
				for cc in g.get("circles", []):
					var c2 := Drawing.v2(cc["c"])
					if absf(c2.distance_to(q) - float(cc["r"])) < tol:
						return {"kind": "circle", "c": c2, "r": float(cc["r"])}
			"line":
				var bestl := {}
				var bdl := tol
				for pl in g.get("visible", []):
					var pts2: PackedVector2Array = pl
					if pts2.size() != 2:
						continue
					var cp := Geometry2D.get_closest_point_to_segment(q, pts2[0], pts2[1])
					if cp.distance_to(q) < bdl:
						bdl = cp.distance_to(q)
						bestl = {"kind": "line", "a": pts2[0], "b": pts2[1]}
				if not bestl.is_empty():
					return bestl
	return {"kind": "free", "p": q}


func _dw_add_ann(a: Dictionary) -> void:
	var sh := _dw_sheet()
	var add := func() -> void:
		a["id"] = Drawing.next_id(sh)
		sh["anns"].append(a)
	_dw_change(add)
	_dw_sel = {"kind": "ann", "id": int(a["id"])}
	_dw_render()
	_refresh_panel()


func _dw_add_view(v: Dictionary) -> void:
	var sh := _dw_sheet()
	var add := func() -> void:
		v["id"] = Drawing.next_id(sh)
		sh["views"].append(v)
	_dw_change(add)
	_dw_sel = {"kind": "view", "id": int(v["id"])}
	_dw_tool = "select"
	_dw_request_hlr()
	_dw_render()
	_refresh_panel()


func _dw_on_click(p: Vector2, dbl: bool, _shift: bool) -> void:
	if mode != "drawing":
		return
	var sh := _dw_sheet()
	if sh.is_empty():
		return
	match _dw_tool:
		"select":
			var a := _dw_ann_at(p)
			if not a.is_empty():
				_dw_sel = {"kind": "ann", "id": int(a["id"])}
			else:
				var v := _dw_view_at(p)
				_dw_sel = {"kind": "view", "id": int(v["id"])} if not v.is_empty() else {}
			_dw_render()
			_refresh_panel()
		"model":
			_dw_add_view({"type": "model", "orient": _dw_orient, "pos": Drawing.a2(p), "hidden": "removed" if _dw_orient in ["iso", "dimetric"] else "visible_hidden", "tangent": "show"})
		"proj":
			var par := _dw_need_view()
			if par.is_empty():
				return
			var bb: Rect2 = _dw_bboxes.get(int(par["id"]), Rect2(Drawing.v2(par["pos"]), Vector2.ZERO))
			var d := p - bb.get_center()
			var side := ("right" if d.x > 0 else "left") if absf(d.x) >= absf(d.y) else ("up" if d.y > 0 else "down")
			var pa := Drawing.view_axes(sh, par)
			var ax := Drawing.projected_axes(pa["dir"], pa["x"], side, str(sh.get("proj", "first")))
			var pos := p
			var pp := Drawing.v2(par["pos"])
			if side == "right" or side == "left":
				pos.y = pp.y
			else:
				pos.x = pp.x
			_dw_add_view({"type": "projected", "parent": int(par["id"]), "side": side, "dir": Drawing.a3(ax["dir"]), "x": Drawing.a3(ax["x"]),
				"pos": Drawing.a2(pos), "hidden": str(par.get("hidden", "visible_hidden")), "tangent": "show"})
		"section", "detail", "aux", "break", "cline":
			_dw_multi_click(p)
		"dim":
			_dw_dim_click(p)
		"cmark":
			var v2 := _dw_view_at(p)
			if v2.is_empty():
				return
			var s := _dw_snap(v2, p, ["circle"])
			if s.get("kind", "") != "circle":
				_set_status("Bir dairenin çevresine tıklayın.")
				return
			_dw_add_ann({"type": "centermark", "view": int(v2["id"]), "c": Drawing.a2(s["c"]), "r": s["r"]})
		"note":
			_dw_add_ann({"type": "note", "pos": Drawing.a2(p), "text": "NOT", "h": 3.5})
		"surface":
			_dw_add_ann({"type": "surface", "pos": Drawing.a2(p), "ra": "1.6", "mode": "removal"})
		"balloon", "gdt", "datum", "weld":
			_dw_pts.append(p)
			if _dw_pts.size() == 1:
				_set_status(I18n.t("Şimdi %s yerine tıklayın.") % {"balloon": I18n.t("balonun"), "gdt": I18n.t("çerçevenin"), "datum": I18n.t("etiketin"), "weld": I18n.t("referans çizgisinin")}[_dw_tool])
				return
			var tgt := Drawing.a2(_dw_pts[0])
			var pos2 := Drawing.a2(_dw_pts[1])
			_dw_pts.clear()
			match _dw_tool:
				"balloon":
					var nb := 1
					for an in sh.get("anns", []):
						if an.get("type", "") == "balloon":
							nb += 1
					_dw_add_ann({"type": "balloon", "pos": pos2, "target": tgt, "num": str(nb)})
				"gdt":
					_dw_add_ann({"type": "gdt", "pos": pos2, "target": tgt, "sym": "position", "tol": "0.05", "dia": true, "mod": "", "datums": ["A", "B"]})
				"datum":
					var used := 0
					for an in sh.get("anns", []):
						if an.get("type", "") == "datum":
							used += 1
					_dw_add_ann({"type": "datum", "pos": pos2, "target": tgt, "label": "ABCDEFGH"[used % 8]})
				"weld":
					_dw_add_ann({"type": "weld", "pos": pos2, "target": tgt, "kind": "fillet", "size": "5", "side": "arrow", "all_around": false, "note": ""})


func _dw_multi_click(p: Vector2) -> void:
	var sh := _dw_sheet()
	var par := Drawing.find_view(sh, int(_dw_sel.get("id", -1))) if _dw_sel.get("kind", "") == "view" else {}
	if _dw_tool == "cline":
		var v := _dw_view_at(p) if _dw_pts.is_empty() else Drawing.find_view(sh, int(_dw_pts[0]["view"]))
		if v.is_empty():
			return
		var s := _dw_snap(v, p, ["point"])
		_dw_pts.append({"view": int(v["id"]), "p": s["p"]})
		if _dw_pts.size() == 2:
			_dw_add_ann({"type": "centerline", "view": int(v["id"]), "a": Drawing.a2(_dw_pts[0]["p"]), "b": Drawing.a2(_dw_pts[1]["p"])})
			_dw_pts.clear()
		return
	if par.is_empty():
		_set_status("Önce bir görünüş seçin.")
		return
	if _dw_tool == "aux":
		var sl := _dw_snap(par, p, ["line"])
		if sl.get("kind", "") != "line":
			_set_status("Seçili görünüşte doğrusal bir kenara tıklayın.")
			return
		var pa := Drawing.view_axes(sh, par)
		var ax := Drawing.aux_axes(pa, sl["a"], sl["b"], false)
		var bb: Rect2 = _dw_bboxes.get(int(par["id"]), Rect2())
		var n2: Vector2 = ax["n2"]
		var pos := _dw_place_view(sh, ax, Drawing.view_scale(sh, par), bb, n2)
		_dw_add_view({"type": "aux", "parent": int(par["id"]), "dir": Drawing.a3(ax["dir"]), "x": Drawing.a3(ax["x"]),
			"pos": Drawing.a2(pos), "label": Drawing.next_letter(sh), "aux": {"a": Drawing.a2(sl["a"]), "b": Drawing.a2(sl["b"]), "n2": Drawing.a2(n2)},
			"hidden": "removed", "tangent": "show"})
		return
	var s2 := _dw_snap(par, p, ["point"])
	_dw_pts.append(s2["p"])
	if _dw_pts.size() < 2:
		_set_status({"section": "Kesit çizgisinin ikinci ucuna tıklayın.", "detail": "Detay dairesinin kenarına tıklayın.", "break": "İkinci kırık sınırına tıklayın."}.get(_dw_tool, ""))
		return
	var a: Vector2 = _dw_pts[0]
	var b: Vector2 = _dw_pts[1]
	_dw_pts.clear()
	var pa2 := Drawing.view_axes(sh, par)
	var bb2: Rect2 = _dw_bboxes.get(int(par["id"]), Rect2())
	match _dw_tool:
		"section":
			var sd := Drawing.section_def(pa2, a, b, false)
			if sd.is_empty():
				return
			var look := -Drawing.project(pa2, sd["n"])
			look = look.normalized() if look.length() > 1e-9 else Vector2.DOWN
			var pos2 := _dw_place_view(sh, sd, Drawing.view_scale(sh, par), bb2, look)
			_dw_add_view({"type": "section", "parent": int(par["id"]), "dir": Drawing.a3(sd["dir"]), "x": Drawing.a3(sd["x"]), "pos": Drawing.a2(pos2),
				"section": {"a": Drawing.a2(a), "b": Drawing.a2(b), "o": Drawing.a3(sd["o"]), "n": Drawing.a3(sd["n"]), "label": Drawing.next_letter(sh)},
				"hidden": "removed", "tangent": "show"})
		"detail":
			var r := a.distance_to(b)
			if r < 1e-6:
				return
			var rr := r * Drawing.view_scale(sh, par) * 2.0
			var dsz := Vector2(rr, rr) * 2.0 + Vector2(6, 12)
			var pos3 := _dw_free_center(sh, dsz, Vector2(bb2.end.x + dsz.x * 0.5 + 15.0, bb2.get_center().y), [Vector2.RIGHT, Vector2.DOWN, Vector2.UP, Vector2.LEFT])
			_dw_add_view({"type": "detail", "parent": int(par["id"]), "pos": Drawing.a2(pos3),
				"detail": {"c": Drawing.a2(a), "r": r, "factor": 2.0, "label": Drawing.next_letter(sh)}, "hidden": str(par.get("hidden", "visible_hidden")), "tangent": "show"})
		"break":
			var axis := "x" if absf(b.x - a.x) >= absf(b.y - a.y) else "y"
			var lo := minf(a.x, b.x) if axis == "x" else minf(a.y, b.y)
			var hi := maxf(a.x, b.x) if axis == "x" else maxf(a.y, b.y)
			var addb := func() -> void:
				var brs: Array = par.get("breaks", [])
				brs.append({"axis": axis, "a": lo, "b": hi})
				par["breaks"] = brs
			_dw_change(addb)
			_dw_tool = "select"
			_dw_render()


func _dw_dim_click(p: Vector2) -> void:
	var sh := _dw_sheet()
	if _dw_pts.is_empty():
		var v := _dw_view_at(p)
		if v.is_empty():
			_set_status("Bir görünüşteki köşe, daire veya kenara tıklayın.")
			return
		var s := _dw_snap(v, p, ["point", "circle", "line"])
		if s.get("kind", "") == "free":
			_set_status("Yakalanacak öğe yok: köşe, daire veya kenara tıklayın.")
			return
		s["view"] = int(v["id"])
		_dw_pts.append(s)
		_set_status({"point": I18n.t("İkinci köşeye tıklayın."), "circle": I18n.t("Boyutun yerine tıklayın (çap)."), "line": I18n.t("Başka bir kenara (açı) veya boyutun yerine tıklayın.")}[s["kind"]])
		return
	var first: Dictionary = _dw_pts[0]
	var v2 := Drawing.find_view(sh, int(first["view"]))
	var q := Drawing.sheet_to_view(sh, v2, p)
	if first["kind"] == "circle":
		_dw_pts.clear()
		_dw_add_ann({"type": "dim", "view": int(first["view"]), "kind": "dia", "c": Drawing.a2(first["c"]), "r": first["r"], "off": Drawing.a2(q)})
		return
	if _dw_pts.size() == 1:
		var s2 := _dw_snap(v2, p, ["point", "line"] if first["kind"] == "point" else ["line"])
		if first["kind"] == "point" and s2.get("kind", "") == "point" and (s2["p"] as Vector2).distance_to(first["p"]) > 1e-6:
			_dw_pts.append(s2)
			_set_status("Boyutun yerine tıklayın (yukarı/aşağı: yatay, sağ/sol: dikey ölçü).")
			return
		if first["kind"] == "line" and s2.get("kind", "") == "line":
			_dw_pts.append(s2)
			_set_status("Açı boyutunun yerine tıklayın.")
			return
		if first["kind"] == "line":
			# Kenar uzunluğu: yerleşim tıklaması
			_dw_pts.clear()
			var a: Vector2 = first["a"]
			var b: Vector2 = first["b"]
			var kind := _dw_lin_kind(a, b, q)
			_dw_add_ann({"type": "dim", "view": int(first["view"]), "kind": kind, "p1": Drawing.a2(a), "p2": Drawing.a2(b), "off": Drawing.a2(q)})
			return
		return
	var second: Dictionary = _dw_pts[1]
	_dw_pts.clear()
	if first["kind"] == "line":
		_dw_add_ann({"type": "dim", "view": int(first["view"]), "kind": "ang", "l1": [Drawing.a2(first["a"]), Drawing.a2(first["b"])],
			"l2": [Drawing.a2(second["a"]), Drawing.a2(second["b"])], "off": Drawing.a2(q)})
	else:
		var p1: Vector2 = first["p"]
		var p2: Vector2 = second["p"]
		_dw_add_ann({"type": "dim", "view": int(first["view"]), "kind": _dw_lin_kind(p1, p2, q), "p1": Drawing.a2(p1), "p2": Drawing.a2(p2), "off": Drawing.a2(q)})


## Yerleşime göre ölçü türü: noktaların dışında üstte/altta → yatay, sağda/solda → dikey, arada → hizalı.
func _dw_lin_kind(a: Vector2, b: Vector2, q: Vector2) -> String:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	if absf(a.y - b.y) < 1e-6:
		return "h"
	if absf(a.x - b.x) < 1e-6:
		return "v"
	if q.y > hi.y or q.y < lo.y:
		return "h" if q.x >= lo.x and q.x <= hi.x else ("v" if q.y >= lo.y and q.y <= hi.y else "h")
	if q.x > hi.x or q.x < lo.x:
		return "v"
	return "a"


func _dw_on_drag(from: Vector2, to: Vector2, done: bool) -> void:
	if mode != "drawing" or _dw_tool != "select":
		return
	var sh := _dw_sheet()
	if _dw_drag.is_empty():
		var a := _dw_ann_at(from)
		if not a.is_empty():
			_dw_sel = {"kind": "ann", "id": int(a["id"])}
			_dw_drag = {"kind": "ann", "id": int(a["id"]), "orig": a.duplicate(true)}
		else:
			var v := _dw_view_at(from)
			if v.is_empty():
				return
			_dw_sel = {"kind": "view", "id": int(v["id"])}
			var kids := {}
			for c in sh.get("views", []):
				if int(c.get("parent", -1)) == int(v["id"]) and c.get("type", "") in ["projected", "section", "aux", "detail"]:
					kids[int(c["id"])] = Drawing.v2(c["pos"])
			_dw_drag = {"kind": "view", "id": int(v["id"]), "pos": Drawing.v2(v["pos"]), "kids": kids}
		_dwd().checkpoint()
	var d := to - from
	if _dw_drag["kind"] == "view":
		var v2 := Drawing.find_view(sh, int(_dw_drag["id"]))
		var dd := d
		if v2.get("type", "") == "projected":
			dd = Vector2(d.x, 0) if str(v2.get("side", "")) in ["right", "left"] else Vector2(0, d.y)
		v2["pos"] = Drawing.a2((_dw_drag["pos"] as Vector2) + dd)
		for kid in _dw_drag["kids"]:
			var kv := Drawing.find_view(sh, int(kid))
			kv["pos"] = Drawing.a2((_dw_drag["kids"][kid] as Vector2) + dd)
	else:
		var an := Drawing.find_ann(sh, int(_dw_drag["id"]))
		var orig: Dictionary = _dw_drag["orig"]
		if orig.has("pos"):
			an["pos"] = Drawing.a2(Drawing.v2(orig["pos"]) + d)
		elif orig.has("off"):
			var vv := Drawing.find_view(sh, int(an.get("view", -1)))
			if not vv.is_empty():
				an["off"] = Drawing.a2(Drawing.v2(orig["off"]) + d / Drawing.view_scale(sh, vv))
	_dw_render()
	if done:
		_dw_drag = {}
		_dw_commit()


func _dw_delete() -> void:
	var sh := _dw_sheet()
	if _dw_sel.is_empty() or sh.is_empty():
		return
	var sel := _dw_sel.duplicate()
	var rm := func() -> void:
		if sel["kind"] == "ann":
			var anns: Array = sh["anns"]
			for i in anns.size():
				if int(anns[i]["id"]) == int(sel["id"]):
					anns.remove_at(i)
					break
		else:
			var gone := {int(sel["id"]): true}
			var changed := true
			while changed:
				changed = false
				for v in sh["views"]:
					if gone.has(int(v.get("parent", -1))) and not gone.has(int(v["id"])):
						gone[int(v["id"])] = true
						changed = true
			var keep: Array = []
			for v in sh["views"]:
				if not gone.has(int(v["id"])):
					keep.append(v)
			sh["views"] = keep
			var keep_a: Array = []
			for a in sh["anns"]:
				if not gone.has(int(a.get("view", -1))):
					keep_a.append(a)
			sh["anns"] = keep_a
	_dw_change(rm)
	_dw_sel = {}
	_dw_render()
	_refresh_panel()


# ---------------------------------------------------------------- model boyutları

func _dw_import_model_dims(sh: Dictionary) -> int:
	if _dw_in_asm:
		return 0
	var done := {}
	for a in sh.get("anns", []):
		if a.has("src"):
			done["%d:%d" % [int(a["src"]["sketch"]), int(a["src"]["cid"])]] = true
	var n := 0
	for v in sh.get("views", []):
		if not (str(v.get("type", "")) in ["model", "projected"]):
			continue
		var ax := Drawing.view_axes(sh, v)
		for f: CadFeature in doc.sketches():
			if f.suppressed or doc.is_rolled_back(f) or absf(f.plane.normal().dot(ax["dir"])) < 0.9999:
				continue
			for c in f.sketch.constraints:
				if not Sketch.is_dimension(c) or bool(c.get("driven", false)):
					continue
				var key := "%d:%d" % [f.id, int(c["id"])]
				if done.has(key):
					continue
				var lab: Vector2 = SketchSolver.dimension_anchor(f.sketch, c) + Drawing.v2(c.get("off", [0, 0]))
				var off := Drawing.project(ax, f.plane.to_world(lab))
				var ann := {"type": "dim", "view": int(v["id"]), "off": Drawing.a2(off), "src": {"sketch": f.id, "cid": int(c["id"])}}
				match str(c["type"]):
					"distance", "hdistance", "vdistance":
						var p1 := Drawing.project(ax, f.plane.to_world(f.sketch.points[int(c["p1"])]))
						var p2 := Drawing.project(ax, f.plane.to_world(f.sketch.points[int(c["p2"])]))
						var kind := "a"
						if str(c["type"]) != "distance":
							var dirw := f.plane.x_dir if str(c["type"]) == "hdistance" else f.plane.y_dir
							var pd := Drawing.project(ax, dirw)
							kind = "h" if absf(pd.x) > 0.999 else ("v" if absf(pd.y) > 0.999 else "a")
						ann["kind"] = kind
						ann["p1"] = Drawing.a2(p1)
						ann["p2"] = Drawing.a2(p2)
					"diameter", "radius":
						var e := f.sketch.get_entity(int(c["e1"]))
						if e.is_empty():
							continue
						ann["kind"] = "dia" if str(c["type"]) == "diameter" else "rad"
						ann["c"] = Drawing.a2(Drawing.project(ax, f.plane.to_world(f.sketch.points[int(e["c"])])))
						ann["r"] = f.sketch.entity_radius(e)
					_:
						continue
				ann["id"] = Drawing.next_id(sh)
				sh["anns"].append(ann)
				done[key] = true
				n += 1
	return n


# ---------------------------------------------------------------- panel

func _show_drawing_panel() -> void:
	panel.clear()
	var sh := _dw_sheet()
	if sh.is_empty():
		panel.title("Teknik Resim", Icons.get_icon("dw_sheet", 22))
		return
	if _dw_tool != "select":
		panel.info(str(DW_TOOL_HINTS.get(_dw_tool, "")), Color(0.55, 0.85, 1.0))
		if _dw_tool == "model":
			var ors: Array = Drawing.ORIENTS.keys()
			var names: Array = []
			for o in ors:
				names.append(Drawing.ORIENT_NAMES.get(o, o))
			var on_o := func(i: int) -> void: _dw_orient = ors[i]
			panel.option("Yönelim", names, maxi(ors.find(_dw_orient), 0), on_o)
		panel.button("Aracı bırak (Esc)", func(): _dw_set_tool("select"))
		panel.spacer()
	if _dw_sel.get("kind", "") == "view":
		_dw_view_panel(sh, Drawing.find_view(sh, int(_dw_sel["id"])))
	elif _dw_sel.get("kind", "") == "ann":
		_dw_ann_panel(sh, Drawing.find_ann(sh, int(_dw_sel["id"])))
	else:
		_dw_sheet_panel(sh)


func _dw_set(dict: Dictionary, key: String, val: Variant, repanel := false) -> void:
	var setv := func() -> void: dict[key] = val
	_dw_change(setv)
	_dw_request_hlr()
	_dw_render()
	if repanel:
		_refresh_panel()


func _dw_sheet_panel(sh: Dictionary) -> void:
	panel.title(I18n.t("Sayfa: ") + str(sh.get("name", "")), Icons.get_icon("dw_sheet", 22))
	if _dwd().drawings.size() > 1:
		var names: Array = []
		for s in _dwd().drawings:
			names.append(str(s.get("name", "")))
		var on_s := func(i: int) -> void:
			_dw_index = i
			_dw_request_hlr()
			_dw_render()
			_refresh_panel()
		panel.option("Etkin sayfa", names, _dw_index, on_s)
	var add_sheet := func() -> void:
		var ns := func() -> void: _dwd().drawings.append(Drawing.new_sheet("Sayfa%d" % (_dwd().drawings.size() + 1), str(sh.get("size", "A3")), str(sh.get("std", "ISO"))))
		_dw_change(ns)
		_dw_index = _dwd().drawings.size() - 1
		_dw_render()
		_refresh_panel()
	panel.button("Yeni sayfa ekle", add_sheet, Icons.get_icon("new", 16))
	panel.section("Sayfa biçimi")
	var on_size := func(i: int) -> void: _dw_set(sh, "size", Drawing.SIZE_ORDER[i])
	panel.option("Boyut", Drawing.SIZE_ORDER, maxi(Drawing.SIZE_ORDER.find(str(sh.get("size", "A3"))), 0), on_size)
	var on_port := func(b: bool) -> void: _dw_set(sh, "portrait", b)
	panel.check("Dikey", bool(sh.get("portrait", false)), on_port)
	var stds := ["ISO", "ANSI"]
	var on_std := func(i: int) -> void: _dw_set(sh, "std", stds[i])
	panel.option("Standart", stds, maxi(stds.find(str(sh.get("std", "ISO"))), 0), on_std)
	var projs := ["first", "third"]
	var on_proj := func(i: int) -> void:
		var setp := func() -> void:
			sh["proj"] = projs[i]
			# İzdüşüm görünüşlerinin yönelimini yeni açıya göre güncelle
			for v in sh["views"]:
				if v.get("type", "") == "projected":
					var par := Drawing.find_view(sh, int(v["parent"]))
					if not par.is_empty():
						var pa := Drawing.view_axes(sh, par)
						var ax := Drawing.projected_axes(pa["dir"], pa["x"], str(v.get("side", "right")), projs[i])
						v["dir"] = Drawing.a3(ax["dir"])
						v["x"] = Drawing.a3(ax["x"])
		_dw_change(setp)
		_dw_request_hlr()
		_dw_render()
	panel.option("İzdüşüm", ["1. açı (ISO / Avrupa)", "3. açı (ANSI / Amerika)"], maxi(projs.find(str(sh.get("proj", "first"))), 0), on_proj)
	var sc_names: Array = []
	for s2 in Drawing.SCALES:
		sc_names.append(Drawing.scale_text(s2))
	var on_sc := func(i: int) -> void: _dw_set(sh, "scale", Drawing.SCALES[i])
	panel.option("Sayfa ölçeği", sc_names, maxi(Drawing.SCALES.find(float(sh.get("scale", 1.0))), 0), on_sc)
	panel.section("Antet")
	var t: Dictionary = sh.get("title", {})
	for fld in [["company", I18n.t("Firma")], ["title", I18n.t("Başlık (boş: parça adı)")], ["number", I18n.t("Resim no")], ["drawn", I18n.t("Çizen")], ["checked", I18n.t("Kontrol")], ["date", I18n.t("Tarih")], ["material", I18n.t("Malzeme (boş: parça)")]]:
		var key: String = fld[0]
		var on_t := func(txt: String) -> void: _dw_set(t, key, txt)
		panel.text_field(fld[1], str(t.get(key, "")), on_t)
	panel.section("Tablolar")
	var on_bom := func(b: bool) -> void: _dw_set(sh, "bom", b)
	panel.check("Malzeme listesi", bool(sh.get("bom", false)), on_bom)
	var revs: Array = sh.get("revs", [])
	for i in revs.size():
		var r: Dictionary = revs[i]
		var on_rd := func(txt: String) -> void: _dw_set(r, "desc", txt)
		panel.text_field("Rev " + str(r.get("rev", "")), str(r.get("desc", "")), on_rd)
	panel.section("Çıktı")
	panel.button(I18n.t("PDF olarak kaydet"), func(): _dw_cmd("dw_pdf"), Icons.get_icon("dw_pdf", 16))
	panel.button(I18n.t("SVG olarak kaydet"), func(): _dw_cmd("dw_svg"), Icons.get_icon("export", 16))
	panel.button(I18n.t("DXF olarak kaydet"), func(): _dw_cmd("dw_dxf"), Icons.get_icon("export", 16))
	panel.info("DWG için DXF dosyasını AutoCAD veya ücretsiz ODA File Converter ile dönüştürün.", Color(0.55, 0.6, 0.66))


func _dw_view_panel(sh: Dictionary, v: Dictionary) -> void:
	if v.is_empty():
		return
	var tn := {"model": "Model görünüşü", "projected": "İzdüşüm görünüşü", "section": "Kesit görünüşü", "detail": "Detay görünüşü", "aux": "Yardımcı görünüş"}
	panel.title(str(tn.get(str(v.get("type", "")), "Görünüş")), Icons.get_icon("dw_model", 22))
	if v.get("type", "") == "model":
		var ors: Array = Drawing.ORIENTS.keys()
		var names: Array = []
		for o in ors:
			names.append(Drawing.ORIENT_NAMES.get(o, o))
		var on_o := func(i: int) -> void: _dw_set(v, "orient", ors[i])
		panel.option("Yönelim", names, maxi(ors.find(str(v.get("orient", "front"))), 0), on_o)
	if v.get("type", "") == "detail":
		var det: Dictionary = v.get("detail", {})
		var on_f := func(val: float) -> void: _dw_set(det, "factor", val)
		panel.number("Büyütme", float(det.get("factor", 2.0)), on_f, "plain", 0.1, 100.0)
	else:
		var sc_names: Array = ["Sayfa ölçeği"]
		var sc_vals: Array = [0.0]
		for s2 in Drawing.SCALES:
			sc_names.append(Drawing.scale_text(s2))
			sc_vals.append(s2)
		var on_sc := func(i: int) -> void: _dw_set(v, "scale", sc_vals[i])
		panel.option("Ölçek", sc_names, maxi(sc_vals.find(float(v.get("scale", 0.0))), 0), on_sc)
	var hs := ["visible_hidden", "removed"]
	var on_h := func(i: int) -> void: _dw_set(v, "hidden", hs[i])
	panel.option("Gizli çizgiler", ["Görünür (kesikli)", "Kaldırılmış"], maxi(hs.find(str(v.get("hidden", "visible_hidden"))), 0), on_h)
	var ts := ["show", "hide"]
	var on_t := func(i: int) -> void: _dw_set(v, "tangent", ts[i])
	panel.option("Teğet kenarlar", ["Göster", "Gizle"], maxi(ts.find(str(v.get("tangent", "show"))), 0), on_t)
	if v.get("type", "") == "section":
		var sec: Dictionary = v.get("section", {})
		var on_l := func(txt: String) -> void: _dw_set(sec, "label", txt)
		panel.text_field("Kesit harfi", str(sec.get("label", "A")), on_l)
		var flip_sec := func() -> void:
			var par := Drawing.find_view(sh, int(v.get("parent", -1)))
			if par.is_empty():
				return
			var fl := not bool(sec.get("flip", false))
			var sd := Drawing.section_def(Drawing.view_axes(sh, par), Drawing.v2(sec["a"]), Drawing.v2(sec["b"]), fl)
			if sd.is_empty():
				return
			var apply := func() -> void:
				sec["flip"] = fl
				sec["o"] = Drawing.a3(sd["o"])
				sec["n"] = Drawing.a3(sd["n"])
				v["dir"] = Drawing.a3(sd["dir"])
				v["x"] = Drawing.a3(sd["x"])
			_dw_change(apply)
			_dw_request_hlr()
			_dw_render()
		panel.button("Bakış yönünü çevir", flip_sec, Icons.get_icon("dw_section", 16))
	if not (v.get("breaks", []) as Array).is_empty():
		panel.button("Kırıkları kaldır", func(): _dw_set(v, "breaks", []), Icons.get_icon("delete", 16))
	var g: Dictionary = _dw_geo.get(_dw_index, {}).get(int(v["id"]), {})
	if str(g.get("error", "")) != "":
		panel.info(I18n.t("Hata: ") + str(g["error"]), Color(1.0, 0.45, 0.4))
	var cmarks := func() -> void:
		var geo := DrawingRender.view_geometry(sh, v, _dw_geo.get(_dw_index, {}))
		var addc := func() -> void:
			for cc in geo.get("circles", []):
				if bool(cc.get("full", true)):
					sh["anns"].append({"id": Drawing.next_id(sh), "type": "centermark", "view": int(v["id"]), "c": cc["c"], "r": cc["r"]})
		_dw_change(addc)
		_dw_render()
	panel.button("Tüm dairelere merkez işareti", cmarks, Icons.get_icon("dw_cmark", 16))
	panel.button("Görünüşü sil", _dw_delete, Icons.get_icon("delete", 16))


func _dw_ann_panel(sh: Dictionary, a: Dictionary) -> void:
	if a.is_empty():
		return
	var tp := str(a.get("type", ""))
	var titles := {"dim": "Boyut", "note": "Not", "balloon": "Balon", "surface": I18n.t("Yüzey pürüzlülüğü"), "gdt": I18n.t("Geometrik tolerans"),
		"datum": "Datum", "weld": I18n.t("Kaynak sembolü"), "centermark": I18n.t("Merkez işareti"), "centerline": "Merkez çizgisi"}
	panel.title(str(titles.get(tp, tp)), Icons.get_icon("dimension", 22))
	match tp:
		"dim":
			var val := DrawingRender.dim_value(_dwd(), sh, a)
			panel.info(I18n.t("Değer: ") + (Units.format_angle(val) if str(a.get("kind", "")) == "ang" else Units.format_length(val)) + (I18n.t("   (model boyutu — ilişkili)") if a.has("src") else ""), Color(0.55, 0.85, 1.0))
			if str(a.get("kind", "")) in ["h", "v", "a"]:
				var ks := ["h", "v", "a"]
				var on_k := func(i: int) -> void: _dw_set(a, "kind", ks[i])
				panel.option("Yön", ["Yatay", "Dikey", "Hizalı"], maxi(ks.find(str(a.get("kind", "a"))), 0), on_k)
			var on_tx := func(txt: String) -> void: _dw_set(a, "text", txt)
			panel.text_field("Metni geçersiz kıl", str(a.get("text", "")), on_tx, I18n.t("(boş: ölçülen değer)"))
			var tol: Dictionary = a.get("tol", {})
			var tts := ["none", "sym", "dev", "limit", "fit"]
			var on_tt := func(i: int) -> void:
				var t2: Dictionary = a.get("tol", {}).duplicate()
				t2["type"] = tts[i]
				_dw_set(a, "tol", t2, true)
			panel.option("Tolerans", ["Yok", "Simetrik ±", "Sapma +/-", "Sınırlar", "Geçme (H7 vb.)"], maxi(tts.find(str(tol.get("type", "none"))), 0), on_tt)
			var tt := str(tol.get("type", "none"))
			if tt in ["sym", "dev", "limit"]:
				var on_up := func(x: float) -> void:
					var t3: Dictionary = a.get("tol", {}).duplicate()
					t3["up"] = x
					_dw_set(a, "tol", t3)
				panel.number("Üst sapma" if tt != "sym" else "Tolerans", float(tol.get("up", 0.1)), on_up, "length")
			if tt in ["dev", "limit"]:
				var on_lo := func(x: float) -> void:
					var t4: Dictionary = a.get("tol", {}).duplicate()
					t4["lo"] = x
					_dw_set(a, "tol", t4)
				panel.number("Alt sapma", float(tol.get("lo", 0.1)), on_lo, "length")
			if tt == "fit":
				var on_fit := func(txt: String) -> void:
					var t5: Dictionary = a.get("tol", {}).duplicate()
					t5["fit"] = txt
					_dw_set(a, "tol", t5)
				panel.text_field("Geçme", str(tol.get("fit", "H7")), on_fit)
			var on_ref := func(b: bool) -> void: _dw_set(a, "ref", b)
			panel.check("Referans boyut (parantez)", bool(a.get("ref", false)), on_ref)
		"note":
			var on_n := func(txt: String) -> void: _dw_set(a, "text", txt.replace(" | ", "\n").replace("|", "\n"))
			panel.text_field("Metin", str(a.get("text", "")).replace("\n", " | "), on_n)
			panel.info("Satır ayırmak için | kullanın.", Color(0.55, 0.6, 0.66))
			var on_h := func(x: float) -> void: _dw_set(a, "h", x)
			panel.number("Yazı yüksekliği", float(a.get("h", 3.5)), on_h, "plain", 1.0, 50.0)
		"balloon":
			var on_b := func(txt: String) -> void: _dw_set(a, "num", txt)
			panel.text_field("Numara", str(a.get("num", "1")), on_b)
		"surface":
			var on_ra := func(txt: String) -> void: _dw_set(a, "ra", txt)
			panel.text_field("Ra (µm)", str(a.get("ra", "1.6")), on_ra)
			var ms := ["any", "removal", "no_removal"]
			var on_m := func(i: int) -> void: _dw_set(a, "mode", ms[i])
			panel.option("İşlem", ["Herhangi", "Talaş kaldırmalı", "Talaş kaldırmasız"], maxi(ms.find(str(a.get("mode", "removal"))), 0), on_m)
		"gdt":
			var names: Array = []
			for k in DrawingRender.GDT_ORDER:
				names.append(DrawingRender.GDT_NAMES[k])
			var on_s := func(i: int) -> void: _dw_set(a, "sym", DrawingRender.GDT_ORDER[i])
			panel.option("Karakteristik", names, maxi(DrawingRender.GDT_ORDER.find(str(a.get("sym", "position"))), 0), on_s)
			var on_t := func(txt: String) -> void: _dw_set(a, "tol", txt)
			panel.text_field("Tolerans", str(a.get("tol", "0.05")), on_t)
			var on_d := func(b: bool) -> void: _dw_set(a, "dia", b)
			panel.check("Çap bölgesi (Ø)", bool(a.get("dia", false)), on_d)
			var mods := ["", "M", "L"]
			var on_md := func(i: int) -> void: _dw_set(a, "mod", mods[i])
			panel.option("Malzeme koşulu", ["Yok", I18n.t("Ⓜ Maksimum (MMC)"), I18n.t("Ⓛ Minimum (LMC)")], maxi(mods.find(str(a.get("mod", ""))), 0), on_md)
			var on_dt := func(txt: String) -> void:
				var parts: Array = []
				for x in txt.split(","):
					if x.strip_edges() != "":
						parts.append(x.strip_edges().to_upper())
				_dw_set(a, "datums", parts)
			panel.text_field("Datumlar", ",".join(a.get("datums", [])), on_dt, "A,B,C")
		"datum":
			var on_l := func(txt: String) -> void: _dw_set(a, "label", txt.to_upper())
			panel.text_field("Harf", str(a.get("label", "A")), on_l)
		"weld":
			var ks2 := ["fillet", "groove"]
			var on_k2 := func(i: int) -> void: _dw_set(a, "kind", ks2[i])
			panel.option("Tür", ["Köşe kaynağı", "V alın kaynağı"], maxi(ks2.find(str(a.get("kind", "fillet"))), 0), on_k2)
			var on_sz := func(txt: String) -> void: _dw_set(a, "size", txt)
			panel.text_field("Boyut (a)", str(a.get("size", "5")), on_sz)
			var sides := ["arrow", "other", "both"]
			var on_sd := func(i: int) -> void: _dw_set(a, "side", sides[i])
			panel.option("Taraf", ["Ok tarafı", "Karşı taraf", "İki taraf"], maxi(sides.find(str(a.get("side", "arrow"))), 0), on_sd)
			var on_aa := func(b: bool) -> void: _dw_set(a, "all_around", b)
			panel.check("Çepeçevre", bool(a.get("all_around", false)), on_aa)
			var on_nt := func(txt: String) -> void: _dw_set(a, "note", txt)
			panel.text_field("Kuyruk notu", str(a.get("note", "")), on_nt, I18n.t("ör. 111 (elektrik ark)"))
	panel.button("Sil", _dw_delete, Icons.get_icon("delete", 16))


func _dw_commit() -> void:
	_dwd().dirty = true
	_update_title()


## Geri al / yinele vb. belge değişikliğinden sonra resim modunu tazeler.
func _dw_after_doc_change() -> void:
	var sh := _dw_sheet()
	if _dw_sel.get("kind", "") == "view" and Drawing.find_view(sh, int(_dw_sel["id"])).is_empty():
		_dw_sel = {}
	elif _dw_sel.get("kind", "") == "ann" and Drawing.find_ann(sh, int(_dw_sel["id"])).is_empty():
		_dw_sel = {}
	_dw_request_hlr()
	_dw_render()


## Ekran görüntüsü / tanıtım için örnek resim: kesit, detay, boyutlar ve açıklamalar ekler.
func _dw_demo(stage: int) -> void:
	var sh := _dw_sheet()
	if sh.is_empty() or _dw_no_model():
		return
	var front := {}
	var top := {}
	for v in sh["views"]:
		if str(v.get("orient", "")) == "front":
			front = v
		if str(v.get("side", "")) == ("down" if str(sh.get("proj", "first")) == "first" else "up"):
			top = v
	if front.is_empty() or top.is_empty():
		return
	var bb := _dw_aabb()
	if stage == 1:
		# Kesit: üst görünüşte modelin ortasından yatay; detay: ön görünüşün sağ alt köşesi
		_dw_sel = {"kind": "view", "id": int(top["id"])}
		_dw_tool = "section"
		var zc := -(bb.position.z + bb.size.z * 0.5)
		_dw_multi_click(Drawing.view_to_sheet(sh, top, Vector2(bb.position.x - 6.0, zc)))
		_dw_multi_click(Drawing.view_to_sheet(sh, top, Vector2(bb.end.x + 6.0, zc)))
		_dw_sel = {"kind": "view", "id": int(front["id"])}
		_dw_tool = "detail"
		var dc := Vector2(bb.end.x - bb.size.x * 0.15, bb.position.y + bb.size.y * 0.15)
		_dw_multi_click(Drawing.view_to_sheet(sh, front, dc))
		_dw_multi_click(Drawing.view_to_sheet(sh, front, dc + Vector2(bb.size.x * 0.14, 0)))
		_dw_tool = "select"
		return
	var x0 := bb.position.x
	var x1 := bb.end.x
	var y0 := bb.position.y
	var y1 := bb.end.y
	var anns: Array = [
		{"type": "dim", "view": int(front["id"]), "kind": "h", "p1": [x0, y0], "p2": [x1, y0], "off": [(x0 + x1) * 0.5, y0 - 10.0]},
		{"type": "dim", "view": int(front["id"]), "kind": "v", "p1": [x0, y0], "p2": [x0, y1], "off": [x0 - 10.0, (y0 + y1) * 0.5], "tol": {"type": "sym", "up": 0.1}},
		{"type": "note", "pos": [20.0, 40.0], "text": DrawingRender.sheet_t("NOTLAR:\n1. KESKİN KÖŞELERİ KIRIN.\n2. GENEL TOLERANS ISO 2768-m."), "h": 3.0},
		{"type": "surface", "pos": Drawing.a2(Drawing.view_to_sheet(sh, front, Vector2(x0, y0)) + Vector2(-16, -10)), "target": Drawing.a2(Drawing.view_to_sheet(sh, front, Vector2(x0 + bb.size.x * 0.05, y0))), "ra": "3.2", "mode": "removal"},
		{"type": "datum", "pos": Drawing.a2(Drawing.view_to_sheet(sh, front, Vector2(x0 + bb.size.x * 0.75, y0)) + Vector2(0, -14)), "target": Drawing.a2(Drawing.view_to_sheet(sh, front, Vector2(x0 + bb.size.x * 0.75, y0))), "label": "A"},
		{"type": "gdt", "pos": Drawing.a2(Drawing.view_to_sheet(sh, front, Vector2(x1, y1)) + Vector2(8, 6)), "target": Drawing.a2(Drawing.view_to_sheet(sh, front, Vector2(x1, y1 - bb.size.y * 0.2))), "sym": "perpendicularity", "tol": "0.05", "dia": false, "mod": "", "datums": ["A"]},
		{"type": "balloon", "pos": Drawing.a2(Drawing.view_to_sheet(sh, front, Vector2(x0, y1)) + Vector2(-10, 12)), "target": Drawing.a2(Drawing.view_to_sheet(sh, front, Vector2(x0 + bb.size.x * 0.1, y0 + bb.size.y * 0.1))), "num": "1"},
	]
	var geo := DrawingRender.view_geometry(sh, top, _dw_geo.get(_dw_index, {}))
	var best := {}
	for cc in geo.get("circles", []):
		if bool(cc.get("full", true)) and (best.is_empty() or float(cc["r"]) > float(best["r"])):
			best = cc
	if not best.is_empty():
		var c := Drawing.v2(best["c"])
		anns.append({"type": "dim", "view": int(top["id"]), "kind": "dia", "c": Drawing.a2(c), "r": float(best["r"]), "off": Drawing.a2(c + Vector2(0.35, -1).normalized() * (float(best["r"]) + 28.0)), "tol": {"type": "fit", "fit": "H7"}})
	for cc in geo.get("circles", []):
		if bool(cc.get("full", true)):
			anns.append({"type": "centermark", "view": int(top["id"]), "c": cc["c"], "r": cc["r"]})
	for a in anns:
		a["id"] = Drawing.next_id(sh)
		sh["anns"].append(a)
	sh["revs"] = [{"rev": "A", "desc": DrawingRender.sheet_t("İlk yayın"), "date": Time.get_date_string_from_system(), "by": "DIY"}]
	var t: Dictionary = sh["title"]
	t["company"] = "DIY.CAD"
	t["number"] = "DC-0001"
	t["drawn"] = "DIY"
	t["date"] = Time.get_date_string_from_system()
	t["rev"] = "A"
	_dw_render()


## Sayfada dolu bölgeler: görünüşler, antet + malzeme listesi, revizyon tablosu.
func _dw_occupied(sh: Dictionary) -> Array:
	var out: Array = []
	for k in _dw_bboxes:
		out.append((_dw_bboxes[k] as Rect2).grow(6.0))
	var size := Drawing.sheet_size(sh)
	var m := Drawing.MARGIN
	var tw := minf(Drawing.TITLE_W, size.x - 2.0 * m)
	var th := Drawing.TITLE_H + (12.0 if bool(sh.get("bom", false)) else 0.0) + 4.0
	out.append(Rect2(size.x - m - tw - 4.0, m, tw + 4.0, th))
	var nr := (sh.get("revs", []) as Array).size()
	if nr > 0:
		out.append(Rect2(size.x - m - tw - 4.0, size.y - m - 6.0 * (nr + 1) - 4.0, tw + 4.0, 6.0 * (nr + 1) + 4.0))
	return out


## Verilen boyuttaki dikdörtgen için çerçeve içinde boş bir merkez arar (önce verilen yönlerde, sonra tüm sayfada).
func _dw_free_center(sh: Dictionary, size: Vector2, start: Vector2, dirs: Array) -> Vector2:
	var occ := _dw_occupied(sh)
	var ss := Drawing.sheet_size(sh)
	var frame := Rect2(Vector2(Drawing.MARGIN + 3.0, Drawing.MARGIN + 3.0), ss - Vector2(2.0 * Drawing.MARGIN + 6.0, 2.0 * Drawing.MARGIN + 6.0))
	var fits := func(c: Vector2) -> bool:
		var r := Rect2(c - size * 0.5, size)
		if not frame.encloses(r):
			return false
		for o in occ:
			if (o as Rect2).intersects(r):
				return false
		return true
	for d in dirs:
		for k in 80:
			var c: Vector2 = start + (d as Vector2) * 4.0 * k
			if fits.call(c):
				return c
	var best := start
	var bd := INF
	var y := frame.position.y + size.y * 0.5
	while y <= frame.end.y - size.y * 0.5:
		var x := frame.position.x + size.x * 0.5
		while x <= frame.end.x - size.x * 0.5:
			var c2 := Vector2(x, y)
			if c2.distance_to(start) < bd and fits.call(c2):
				bd = c2.distance_to(start)
				best = c2
			x += 5.0
		y += 5.0
	return best


## Kesit / yardımcı görünüş için konum: ebeveynin `dirv` tarafında boş yer; dönüş görünüş orijininin sayfa konumu.
func _dw_place_view(sh: Dictionary, axes: Dictionary, scale: float, par_bb: Rect2, dirv: Vector2) -> Vector2:
	var br := Drawing.box_rect(axes, _dw_aabb())
	var size := br.size * scale + Vector2(4, 14)
	var ext_p := absf(dirv.x) * par_bb.size.x + absf(dirv.y) * par_bb.size.y
	var ext_c := absf(dirv.x) * size.x + absf(dirv.y) * size.y
	var start := par_bb.get_center() + dirv * (ext_p * 0.5 + ext_c * 0.5 + 12.0)
	var c := _dw_free_center(sh, size, start, [dirv])
	return c - br.get_center() * scale + Vector2(0, 5)


# ================================================================ FAZ 7: MONTAJ

## Montaj ekranına geçiş: parça sekmeleri gizlenir, Montaj sekmesi ve araç çubuğu gösterilir.
func enter_assembly_ui() -> void:
	_exit_sketch3d()
	if mode == "sketch":
		_exit_sketch()
	if mode == "feature":
		_cancel_feature()
	_leave_aux_mode()
	if mode == "drawing":
		_exit_drawing()
	mode = "assembly"
	selection = {}
	for i in 3:
		tabs.set_tab_hidden(i, true)
	tabs.set_tab_hidden(3, false)
	tabs.set_tab_hidden(4, false)
	for i in range(5, 10):
		tabs.set_tab_hidden(i, true)
	toolbar_plugins.visible = false
	special.toolbar_sm.visible = false
	special.toolbar_weld.visible = false
	special.toolbar_srf.visible = false
	special.toolbar_an.visible = false
	tabs.set_block_signals(true)
	tabs.current_tab = 4
	tabs.set_block_signals(false)
	toolbar_features.visible = false
	toolbar_sketch.visible = false
	toolbar_eval.visible = false
	toolbar_drawing.visible = false
	asm_mode.toolbar.visible = true
	_set_part_visuals(false)
	def_label.text = ""
	_refresh_panel()


func _set_part_visuals(v: bool) -> void:
	viewport.model_mi.visible = v
	viewport.edges_mi.visible = v and viewport.show_edges
	viewport.sketches_mi.visible = v
	viewport.planes_fill_mi.visible = v
	viewport.planes_line_mi.visible = v
	viewport.sel_edges_mi.visible = v
	if v:
		viewport.clear_face_highlight()


## Montaj ekranından parça ekranına (montaj bellekte kalabilir)
func _leave_assembly_ui() -> void:
	if asm_mode == null:
		return
	asm_mode.leave()
	if mode == "assembly":
		mode = "idle"
	for i in 4:
		tabs.set_tab_hidden(i, false)
	tabs.set_tab_hidden(4, not asm_mode.is_open())
	for i in range(5, 9):
		tabs.set_tab_hidden(i, false)
	tabs.set_tab_hidden(9, toolbar_plugins.get_child_count() == 0)
	asm_mode.toolbar.visible = false
	_set_part_visuals(true)


func _close_assembly_ui() -> void:
	if asm_mode == null or not asm_mode.is_open():
		return
	_leave_assembly_ui()
	asm_mode.close()
	tabs.set_tab_hidden(4, true)


## Montajdaki bir bileşenin parçasını düzenlemek için aç
func open_part_from_assembly(path: String, comp_id := -1) -> void:
	var go := func() -> void:
		_leave_assembly_ui()
		selection = {}
		var err := doc.load_from(path)
		_fit_after_build = true
		_show_toolbar(0)
		if comp_id >= 0:
			asm_mode.show_context(comp_id)
		_set_status((I18n.t("Parça düzenleniyor: %s — bitince 'Montaj' sekmesine tıklayın (parça kaydedilir).") % path.get_file()) if err == OK else (I18n.t("Parça açılamadı: ") + path))
	if doc.dirty:
		_ask_discard(go)
	else:
		go.call()


func _return_to_assembly() -> void:
	var p := doc.file_path
	if doc.dirty and p != "":
		var err := doc.save_to(p)
		_set_status((I18n.t("Parça kaydedildi: ") + p) if err == OK else I18n.t("Parça kaydedilemedi!"))
	asm_mode.enter()
	if p != "":
		asm_mode.reload_part_file(p)


# ---------------------------------------------------------------- montaj teknik resmi

var _dw_in_asm := false


## Resim sayfalarının sahibi: montaj resmi düzenleniyorsa montaj, değilse parça belgesi
func _dwd() -> Object:
	return asm_mode.asm if _dw_in_asm and asm_mode.is_open() else doc


func _dw_no_model() -> bool:
	if _dw_in_asm:
		return asm_mode.asm.comps.is_empty() or asm_mode.view == null or asm_mode.view.world_aabb(asm_mode.asm, asm_mode.parts).size.length() < 1e-6
	return viewport.model.is_empty()


func _dw_aabb() -> AABB:
	if _dw_in_asm:
		return asm_mode.view.world_aabb(asm_mode.asm, asm_mode.parts)
	return viewport.model.aabb


func _dw_mass() -> float:
	if _dw_in_asm:
		return float(asm_mode.mass_totals()["mass"])
	return float(viewport.model.mass_properties(Materials.density_of(doc.material))["mass"])


func _dw_comps() -> Array:
	return asm_mode._occ_comps() if _dw_in_asm else []


func _dw_feature_edges() -> PackedVector3Array:
	if not _dw_in_asm:
		return viewport.model.feature_edges
	var out := PackedVector3Array()
	for c in asm_mode.asm.comps:
		if bool(c.get("hidden", false)) or bool(c.get("suppressed", false)):
			continue
		var m: ModelMesh = asm_mode.parts.get(asm_mode.asm.key_of(c), {}).get("model")
		if m == null:
			continue
		var xf: Transform3D = c["xf"]
		for q in m.feature_edges:
			out.append(xf * q)
	return out


## Montaj resmi malzeme listesi (üst düzey kalemler; balon numaralarıyla aynı)
func _dw_asm_bom() -> Array:
	var keep: bool = asm_mode.bom_flat
	asm_mode.bom_flat = false
	var rows: Array = []
	for r in asm_mode.bom_rows():
		rows.append([str(r["no"]), str(r["name"]), str(r["material"]) if str(r["material"]) != "" else "—", str(r["qty"])])
	asm_mode.bom_flat = keep
	return rows


## Malzeme listesi kalemleri için balonlar: tercihen izometrik görünüşe, bileşen merkezini gösterecek şekilde.
func _dw_auto_balloons(sh: Dictionary) -> int:
	var views: Array = sh.get("views", [])
	var view := {}
	for v in views:
		if str(v.get("orient", "")) in ["iso", "dimetric"]:
			view = v
			break
	if view.is_empty():
		for v in views:
			if str(v.get("type", "")) != "detail":
				view = v
				break
	if view.is_empty():
		return 0
	var keep: Array = []
	for a in sh["anns"]:
		if not (a.get("type", "") == "balloon" and bool(a.get("auto", false))):
			keep.append(a)
	sh["anns"] = keep
	var bb: Rect2 = _dw_bboxes.get(int(view["id"]), Rect2(Drawing.v2(view["pos"]), Vector2(1, 1)))
	var ax := Drawing.view_axes(sh, view)
	var items: Array = []
	if _dw_in_asm:
		var flat: bool = asm_mode.bom_flat
		asm_mode.bom_flat = false
		var chosen: Array = []   # seçilen hedeflerin sayfa konumları (balonları dağıtmak için)
		for r in asm_mode.bom_rows():
			var ids: Array = r.get("comps", [])
			var best_p := Vector3.ZERO
			var best_d := -1.0
			for cid in ids:
				var c: Dictionary = asm_mode.asm.get_comp(int(cid))
				var m: ModelMesh = asm_mode.parts.get(asm_mode.asm.key_of(c), {}).get("model")
				if m == null or m.is_empty():
					continue
				var wp: Vector3 = (c["xf"] as Transform3D) * m.aabb.get_center()
				var spt := Drawing.view_to_sheet(sh, view, Drawing.project(ax, wp))
				var dmin := 1e9
				for q in chosen:
					dmin = minf(dmin, (q as Vector2).distance_to(spt))
				if dmin > best_d:
					best_d = dmin
					best_p = wp
			if best_d < 0.0:
				continue
			chosen.append(Drawing.view_to_sheet(sh, view, Drawing.project(ax, best_p)))
			items.append([str(r["no"]), best_p])
		asm_mode.bom_flat = flat
	elif not viewport.model.is_empty():
		items.append(["1", viewport.model.aabb.get_center()])
	var n := 0
	var center := bb.get_center()
	for it in items:
		var tgt := Drawing.view_to_sheet(sh, view, Drawing.project(ax, it[1]))
		var d := tgt - center
		if d.length() < 1e-3:
			d = Vector2(1, 1)
		d = d.normalized()
		var reach := absf(d.x) * bb.size.x * 0.5 + absf(d.y) * bb.size.y * 0.5
		var pos := center + d * (reach + 12.0)
		var ss := Drawing.sheet_size(sh)
		var mg := Drawing.MARGIN + 7.0
		pos = Vector2(clampf(pos.x, mg, ss.x - mg), clampf(pos.y, mg, ss.y - mg))
		sh["anns"].append({"id": Drawing.next_id(sh), "type": "balloon", "pos": Drawing.a2(pos), "target": Drawing.a2(tgt), "num": str(it[0]), "auto": true})
		n += 1
	return n


# ================================================================ DIŞA AKTAR (tek pencere, tüm formatlar)

const OPEN_FILTERS := ["*.dcad, *.dasm, *.ddrw, *.dcadt, *.dasmt, *.ddrwt, *.dclfp, *.dcftp ; DIY.CAD dosyaları",
	"*.dcad ; DIY.CAD Parça", "*.dasm ; DIY.CAD Montaj", "*.ddrw ; DIY.CAD Teknik Resim",
	"*.dcadt, *.dasmt, *.ddrwt ; DIY.CAD şablonları", "*.dclfp ; DIY.CAD Kütüphane Unsuru Parçası", "*.dcftp ; DIY.CAD Form Verme Aracı"]


func _open_export_dialog() -> void:
	export_dlg.open(_export_reason, str(AppSettings.get_v("export", "last", "")))


func _export_in_asm() -> bool:
	return asm_mode != null and asm_mode.is_open() and (mode == "assembly" or (mode == "drawing" and _dw_in_asm))


func _export_has_mesh() -> bool:
	if not _export_in_asm():
		return not viewport.model.is_empty()
	for c in asm_mode.asm.comps:
		var m: ModelMesh = asm_mode.parts.get(asm_mode.asm.key_of(c), {}).get("model")
		if m != null and not m.is_empty() and not bool(c.get("suppressed", false)):
			return true
	return false


## "" = kullanılabilir; değilse neden
func _export_reason(f: Dictionary) -> String:
	var in_asm := _export_in_asm()
	match str(f["need"]):
		"none":
			return "Bu format desteklenmiyor."
		"native_part":
			return "Montaj açıkken parça dosyası yazılamaz: bileşeni Parçayı Aç ile açın." if in_asm else ""
		"native_drw":
			return "Montaj resmi montaj dosyasının (.dasm) içinde saklanır." if in_asm else ""
		"native_asm":
			return "" if in_asm else "Montaj açık değil."
		"mesh":
			return "" if _export_has_mesh() else "Dışa aktarılacak katı model yok."
		"brep":
			if not (viewport.kernel.is_brep() and viewport.kernel.occ.is_ready()):
				return "OpenCASCADE çekirdeği gerekli (Araçlar → Geometri çekirdeği; kurulum: OCC_Kur.bat)."
			if in_asm:
				return "" if str(f["id"]).begins_with("step") else "Montajda yalnızca STEP yazılabilir."
			return "Dışa aktarılacak katı model yok." if viewport.model.is_empty() else ""
		"sketch":
			return "" if not in_asm and _sketch_for_export() != null else "Önce bir taslak seçin (ağaçtan veya taslak modunda)."
		"drawing":
			return "" if mode == "drawing" and not _dw_sheet().is_empty() else "Teknik Resim sekmesinde kullanılır."
	return ""


func _export_basename() -> String:
	if _export_in_asm():
		return asm_mode.asm.name
	return doc.part_name


func _export_chosen(id: String) -> void:
	var f := ExportFormats.by_id(id)
	if f.is_empty():
		return
	AppSettings.set_v("export", "last", id)
	var base := _export_basename()
	if str(f["need"]) == "sketch":
		var sk := _sketch_for_export()
		if sk:
			base = sk.name
	_file_dialog(true, [ExportFormats.filter_of(f)], I18n.t("Dışa Aktar") + " — " + I18n.t(str(f["label"])), "exp:" + id, base + "." + str(f["ext"][0]))


## Dışa aktarılacak üçgenler: {tris, groups} (montajda bileşen başına grup, montaj konumunda)
func _export_mesh() -> Dictionary:
	var tris := PackedVector3Array()
	var groups: Array = []
	if _export_in_asm():
		for c in asm_mode.asm.comps:
			if bool(c.get("suppressed", false)) or bool(c.get("hidden", false)):
				continue
			var p: Dictionary = asm_mode.parts.get(asm_mode.asm.key_of(c), {})
			var m: ModelMesh = p.get("model")
			if m == null or m.is_empty():
				continue
			var xf: Transform3D = c["xf"]
			var start := tris.size() / 3
			for v in m.ccw_triangles():
				tris.append(xf * v)
			var col: Variant = p.get("color", Materials.color_of(str(p.get("material", ""))))
			groups.append({"name": str(c.get("name", "")), "color": col if col is Color else Color(0.72, 0.75, 0.8),
				"start": start, "count": tris.size() / 3 - start})
	else:
		tris = viewport.model.ccw_triangles()
		groups = ExportFormats.one_group(tris, doc.part_name, Materials.color_of(doc.material))
	return {"tris": tris, "groups": groups}


## Görüntü: teknik resimde sayfa tuvali, diğer modlarda 3B görünüm (ekransız çalışmada null)
func _export_image() -> Image:
	if mode == "drawing":
		var img := get_viewport().get_texture().get_image()
		if img == null or img.is_empty():
			return null
		var vis := get_viewport().get_visible_rect().size
		var k := Vector2(img.get_size()) / vis if vis.x > 0.0 and vis.y > 0.0 else Vector2.ONE
		var gr := drawing_canvas.get_global_rect()
		var r := Rect2i(Vector2i(gr.position * k), Vector2i(gr.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		return img.get_region(r) if r.has_area() else img
	return viewport.screenshot_image()


static func _xml_safe(v: Variant) -> Variant:
	if v is Vector3:
		return {"x": v.x, "y": v.y, "z": v.z}
	return v


## XML veri dışa aktarımı için belge bilgisi
func _export_info() -> Dictionary:
	var d := {"program": APP_NAME, "version": APP_VERSION, "date": Time.get_datetime_string_from_system(false, true), "units": "mm"}
	if _export_in_asm():
		var a: CadAssembly = asm_mode.asm
		d["assembly"] = {"name": a.name, "file": a.file_path, "component_count": a.comps.size(), "mate_count": a.mates.size()}
		var rows: Array = []
		for r in asm_mode.bom_rows():
			rows.append({"no": r["no"], "name": r["name"], "quantity": r["qty"], "material": r["material"], "mass_g": float(r["mass"])})
		d["bill_of_materials"] = rows
		return d
	d["part"] = {"name": doc.part_name, "file": doc.file_path, "material": doc.material}
	var fl: Array = []
	for f in doc.features:
		fl.append({"id": f.id, "name": f.name, "type": f.type, "suppressed": f.suppressed})
	d["features"] = fl
	if not viewport.model.is_empty():
		var mp := viewport.model.mass_properties(Materials.density_of(doc.material))
		d["mass_properties"] = {"volume_mm3": float(mp["volume"]), "area_mm2": float(mp["area"]), "mass_g": float(mp["mass"]),
			"center_of_mass_mm": _xml_safe(mp["center"])}
		var bb: AABB = viewport.model.aabb
		d["bounding_box_mm"] = {"min": _xml_safe(bb.position), "max": _xml_safe(bb.end), "size": _xml_safe(bb.size)}
	return d


func _export_write(id: String, path: String) -> void:
	var f := ExportFormats.by_id(id)
	if f.is_empty():
		return
	path = ExportFormats.with_ext(path, f)
	var err := OK
	match id:
		"dcad":
			_pending_file_action = "save"
			_on_file_selected(path)
			return
		"dcadt", "dclfp", "dcftp", "ddrw", "ddrwt":
			err = doc.write_copy(path)
		"dasm":
			asm_mode.on_file("asm_save", path)
			return
		"dasmt":
			err = asm_mode.asm.write_copy(path, "assembly_template")
		"step214", "step203", "step242":
			if _export_in_asm():
				asm_mode.export_step(path, str(f["schema"]))
			else:
				viewport.kernel.request_export("step", path, {"schema": str(f["schema"])})
				_set_status(I18n.t("Dışa aktarılıyor: ") + path)
			return
		"iges", "brep":
			viewport.kernel.request_export(id, path)
			_set_status(I18n.t("Dışa aktarılıyor: ") + path)
			return
		"stl":
			if not _export_in_asm():
				_pending_file_action = "stl"
				_on_file_selected(path)
				return
			err = Exporters.write_stl(path, _export_mesh()["tris"], asm_mode.asm.name)
		"obj":
			if not _export_in_asm():
				err = Exporters.write_obj(path, viewport.model, doc.part_name)
			else:
				var mo := _export_mesh()
				err = ExportFormats.write_obj_tris(path, mo["tris"], mo["groups"])
		"3mf", "amf", "ply", "off", "fbx", "glb", "gltf", "wrl", "xaml", "ifc", "html":
			var m := _export_mesh()
			err = ExportFormats.write_mesh(id, path, m["tris"], m["groups"], _export_basename())
		"sk_dxf", "sk_svg":
			_pending_file_action = id.substr(3)
			_on_file_selected(path)
			return
		"dw_pdf", "dw_svg", "dw_dxf":
			err = _dw_export(id, path)
		"dw_ai":
			err = _dw_export("dw_pdf", path)
		"png", "jpg", "bmp", "tif", "psd":
			err = ExportFormats.write_image(path, _export_image(), id)
		"xml":
			err = ExportFormats.write_xml(path, "diycad", _export_info())
		"zip":
			err = _export_zip(path)
		_:
			err = ERR_UNAVAILABLE
	_set_status((I18n.t("Dışa aktarıldı: ") + path) if err == OK else (I18n.t("Yazılamadı (hata %d): %s") % [err, path]))


## Paylaşım paketi: DIY.CAD dosyası + STL + HTML görüntüleyici + PNG + XML
func _export_zip(path: String) -> Error:
	var tmp := OS.get_user_data_dir().path_join("export_tmp")
	DirAccess.make_dir_recursive_absolute(tmp)
	var base := _export_basename()
	var safe := base.validate_filename()
	var files: Array = []
	var native := tmp.path_join(safe + (".dasm" if _export_in_asm() else ".dcad"))
	var nerr := asm_mode.asm.write_copy(native) if _export_in_asm() else doc.write_copy(native)
	if nerr == OK:
		files.append({"name": native.get_file(), "path": native})
	if _export_has_mesh():
		var m := _export_mesh()
		var stl := tmp.path_join(safe + ".stl")
		if Exporters.write_stl(stl, m["tris"], base) == OK:
			files.append({"name": stl.get_file(), "path": stl})
		var html := tmp.path_join(safe + ".html")
		if ExportFormats.write_html(html, m["tris"], m["groups"], base) == OK:
			files.append({"name": html.get_file(), "path": html})
	var png := tmp.path_join(safe + ".png")
	if ExportFormats.write_image(png, _export_image(), "png") == OK:
		files.append({"name": png.get_file(), "path": png})
	var xml := tmp.path_join(safe + ".xml")
	if ExportFormats.write_xml(xml, "diycad", _export_info()) == OK:
		files.append({"name": xml.get_file(), "path": xml})
	var err := ExportFormats.write_zip(path, files)
	for fi in files:
		DirAccess.remove_absolute(str(fi["path"]))
	return err
