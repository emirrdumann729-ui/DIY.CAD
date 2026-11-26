class_name OptionsDialog
extends AcceptDialog
## Araçlar → Seçenekler (Faz 9): genel (dil, tema, arayüz ölçeği, otomatik kaydetme), klavye kısayolları
## ve fare hareketleri.

const SCALES := [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]

var app: Node
var tabs: TabContainer
var key_tree: Tree
var key_search: LineEdit
var key_info: Label
var capturing := ""           # kısayol beklenen komut
var _g_ctx := "part"
var _g_box: GridContainer


func _init() -> void:
	title = "Seçenekler"
	ok_button_text = "Kapat"
	min_size = Vector2i(720, 540)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(700, 470)
	add_child(tabs)


func open_tab(i := 0) -> void:
	build()
	tabs.current_tab = i
	popup_centered()


func build() -> void:
	for c in tabs.get_children():
		tabs.remove_child(c)
		c.queue_free()
	capturing = ""
	tabs.add_child(_general())
	tabs.add_child(_keys())
	tabs.add_child(_gestures())
	tabs.add_child(_plugins())
	tabs.set_tab_title(3, "Eklentiler")
	tabs.set_tab_title(0, "Genel")
	tabs.set_tab_title(1, "Klavye kısayolları")
	tabs.set_tab_title(2, "Fare hareketleri")


func _row(parent: Control, label: String, ctrl: Control) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 220
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	parent.add_child(h)


func _note(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UiTheme.adapt(Color(0.6, 0.65, 0.72)))
	parent.add_child(l)
	return l


func _header(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UiTheme.c("section"))
	parent.add_child(l)


# ---------------------------------------------------------------- Genel

func _general() -> Control:
	var m := MarginContainer.new()
	m.name = "Genel"
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	_header(v, "Arayüz görünümü")
	var lang := OptionButton.new()
	lang.name = "Lang"
	for L in I18n.LANGS:
		lang.add_item(str(I18n.LANGS[L]))
	lang.selected = maxi(I18n.LANGS.keys().find(I18n.current), 0)
	lang.item_selected.connect(func(i: int) -> void:
		I18n.set_language(str(I18n.LANGS.keys()[i]))
		app._on_language_changed())
	_row(v, "Dil / Language", lang)
	var th := OptionButton.new()
	th.name = "Theme"
	th.add_item("Koyu")
	th.add_item("Açık")
	th.selected = 1 if str(AppSettings.get_v("ui", "theme")) == "light" else 0
	th.item_selected.connect(func(i: int) -> void:
		AppSettings.set_v("ui", "theme", "light" if i == 1 else "dark")
		app._set_status("Tema bir sonraki açılışta uygulanacak."))
	_row(v, "Tema (yeniden başlatınca)", th)
	var sc := OptionButton.new()
	sc.name = "Scale"
	var cur := float(AppSettings.get_v("ui", "scale"))
	var best := 2
	for i in SCALES.size():
		sc.add_item("%%%d" % int(round(SCALES[i] * 100.0)))
		if absf(SCALES[i] - cur) < absf(SCALES[best] - cur):
			best = i
	sc.selected = best
	sc.item_selected.connect(func(i: int) -> void:
		AppSettings.set_v("ui", "scale", SCALES[i])
		UiTheme.set_scale(app.get_tree(), SCALES[i]))
	_row(v, "Arayüz ölçeği", sc)
	v.add_child(HSeparator.new())
	_header(v, "Kaydetme")
	var au := CheckBox.new()
	au.name = "Autosave"
	au.text = "Otomatik kaydet (çökme kurtarma)"
	au.button_pressed = bool(AppSettings.get_v("autosave", "enabled"))
	au.toggled.connect(func(b: bool) -> void:
		AppSettings.set_v("autosave", "enabled", b)
		app.autosave.reload_settings())
	v.add_child(au)
	var iv := SpinBox.new()
	iv.name = "Interval"
	iv.min_value = 0.5
	iv.max_value = 120.0
	iv.step = 0.5
	iv.suffix = "dk"
	iv.value = float(AppSettings.get_v("autosave", "interval_min"))
	iv.value_changed.connect(func(x: float) -> void:
		AppSettings.set_v("autosave", "interval_min", x)
		app.autosave.reload_settings())
	_row(v, "Otomatik kaydetme aralığı", iv)
	var bk := CheckBox.new()
	bk.name = "Backup"
	bk.text = "Kaydederken önceki sürümü yedekle (.bak)"
	bk.button_pressed = bool(AppSettings.get_v("autosave", "backup"))
	bk.toggled.connect(func(b: bool) -> void: AppSettings.set_v("autosave", "backup", b))
	v.add_child(bk)
	var clr := Button.new()
	clr.text = "Son dosyalar listesini temizle"
	clr.pressed.connect(func() -> void:
		AppSettings.clear_recent()
		app._refresh_recent_menu()
		app._set_status("Son dosyalar listesi temizlendi."))
	v.add_child(clr)
	v.add_child(HSeparator.new())
	_note(v, "Ayarlar dosyası: " + ProjectSettings.globalize_path(AppSettings.PATH) + "\nOtomatik kayıtlar: " + ProjectSettings.globalize_path(Autosave.DIR))
	return m


# ---------------------------------------------------------------- Kısayollar

func _keys() -> Control:
	var v := VBoxContainer.new()
	v.name = "Kisayollar"
	key_search = LineEdit.new()
	key_search.placeholder_text = "Komut, grup veya kısayol ara..."
	key_search.text_changed.connect(func(_t: String) -> void: _fill_keys())
	v.add_child(key_search)
	key_tree = Tree.new()
	key_tree.name = "KeyTree"
	key_tree.columns = 4
	key_tree.column_titles_visible = true
	key_tree.hide_root = true
	key_tree.set_column_title(0, "Komut")
	key_tree.set_column_title(1, "Grup")
	key_tree.set_column_title(2, "Bağlam")
	key_tree.set_column_title(3, "Kısayol")
	key_tree.set_column_expand_ratio(0, 3)
	key_tree.set_column_expand_ratio(1, 2)
	key_tree.set_column_expand_ratio(2, 1)
	key_tree.set_column_expand_ratio(3, 2)
	key_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	key_tree.item_activated.connect(func() -> void: _start_capture())
	v.add_child(key_tree)
	var h := HBoxContainer.new()
	var b1 := Button.new()
	b1.text = "Kısayol ata..."
	b1.pressed.connect(_start_capture)
	h.add_child(b1)
	var b2 := Button.new()
	b2.text = "Kısayolu kaldır"
	b2.pressed.connect(func() -> void:
		var id := _selected_cmd()
		if id != "":
			app.keymap.clear_cmd(id)
			_keys_changed("Kısayol kaldırıldı: " + app.command_label(id)))
	h.add_child(b2)
	var b3 := Button.new()
	b3.text = "Varsayılanlara dön"
	b3.pressed.connect(func() -> void:
		app.keymap.reset()
		_keys_changed("Varsayılan kısayollar geri yüklendi."))
	h.add_child(b3)
	v.add_child(h)
	key_info = _note(v, "Satıra çift tıklayın veya 'Kısayol ata' deyip tuş kombinasyonuna basın. Esc, Enter, ok tuşları ve Tab sabittir.")
	_fill_keys()
	return v


func command_ids() -> Array:
	var ids: Array = app._commands.keys()
	ids.sort_custom(func(a, b):
		var ca: Dictionary = app._commands[a]
		var cb: Dictionary = app._commands[b]
		if str(ca["group"]) != str(cb["group"]):
			return str(ca["group"]) < str(cb["group"])
		return str(ca["label"]) < str(cb["label"]))
	return ids


func _fill_keys() -> void:
	key_tree.clear()
	var root := key_tree.create_item()
	var q := key_search.text.strip_edges().to_lower() if key_search else ""
	for id in command_ids():
		var c: Dictionary = app._commands[id]
		var sc := ", ".join(app.keymap.shortcuts_for(id))
		var ctx_s := str(Keymap.CONTEXTS.get(str(c["ctx"]), c["ctx"]))
		var shown: String = app.command_label(id)
		if q != "" and not (shown.to_lower().contains(q) or str(c["label"]).to_lower().contains(q) or str(c["group"]).to_lower().contains(q) or sc.to_lower().contains(q) or str(id).contains(q)):
			continue
		var it := key_tree.create_item(root)
		it.set_text(0, app.command_label(id))
		it.set_tooltip_text(0, str(c["tip"]) if str(c["tip"]) != "" else str(id))
		it.set_text(1, I18n.t(str(c["group"])))
		it.set_text(2, ctx_s)
		it.set_text(3, sc)
		it.set_metadata(0, id)
		if id == capturing:
			it.set_text(3, "… tuşa basın")
			it.select(0)


func _selected_cmd() -> String:
	var it := key_tree.get_selected()
	return str(it.get_metadata(0)) if it != null else ""


func _start_capture() -> void:
	var id := _selected_cmd()
	if id == "":
		key_info.text = "Önce listeden bir komut seçin."
		return
	capturing = id
	key_info.text = "'%s' için bir tuş kombinasyonuna basın (Esc: vazgeç)." % app.command_label(id)
	_fill_keys()


## Kısayol yakalama: tuşu doğrudan pencere girişinden al
func _input(event: InputEvent) -> void:
	if capturing == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var k := event as InputEventKey
	if k.keycode == KEY_ESCAPE:
		capturing = ""
		key_info.text = "Vazgeçildi."
		_fill_keys()
		return
	var sc := Keymap.shortcut_of(k)
	if sc == "":
		return
	assign_capture(sc)


## Yakalanan kısayolu ata (testler doğrudan çağırabilir)
func assign_capture(sc: String) -> void:
	var id := capturing
	capturing = ""
	if id == "":
		return
	if Keymap.is_fixed(sc):
		key_info.text = "%s sabit bir tuştur, atanamaz." % sc
		_fill_keys()
		return
	var ctx := str(app._commands[id]["ctx"]) if app._commands.has(id) else "global"
	var lost: String = app.keymap.assign(ctx, id, sc)
	var msg := "%s → %s" % [sc, app.command_label(id)]
	if lost != "" and lost != id:
		msg += "  (önceki atama kaldırıldı: %s)" % app.command_label(lost)
	_keys_changed(msg)


func _keys_changed(msg: String) -> void:
	app.keymap.save_settings()
	app._refresh_shortcut_labels()
	key_info.text = msg
	_fill_keys()


# ---------------------------------------------------------------- Fare hareketleri

func _gestures() -> Control:
	var m := MarginContainer.new()
	m.name = "Fare"
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	var rmb := OptionButton.new()
	rmb.name = "Rmb"
	rmb.add_item("Görünümü döndür")
	rmb.add_item("Fare hareketleri (döndürme: orta tuş)")
	rmb.selected = 1 if str(AppSettings.get_v("mouse", "rmb")) == "gesture" else 0
	rmb.item_selected.connect(func(i: int) -> void:
		AppSettings.set_v("mouse", "rmb", "gesture" if i == 1 else "rotate")
		app.viewport.rmb_gestures = i == 1)
	_row(v, "Sağ tuşla sürükleme", rmb)
	var ctx := OptionButton.new()
	ctx.name = "GestureCtx"
	for k in MouseGesture.CONTEXTS:
		ctx.add_item(str(MouseGesture.CONTEXTS[k]))
	ctx.selected = MouseGesture.CONTEXTS.keys().find(_g_ctx)
	ctx.item_selected.connect(func(i: int) -> void:
		_g_ctx = str(MouseGesture.CONTEXTS.keys()[i])
		_fill_gestures())
	_row(v, "Bağlam", ctx)
	_g_box = GridContainer.new()
	_g_box.columns = 2
	v.add_child(_g_box)
	var rst := Button.new()
	rst.text = "Bu bağlamı varsayılana döndür"
	rst.pressed.connect(func() -> void:
		MouseGesture.save_mapping(_g_ctx, (MouseGesture.DEFAULTS[_g_ctx] as Array).duplicate())
		_fill_gestures())
	v.add_child(rst)
	_note(v, "Sağ tuşu basılı tutup bir yöne çekin; halkada vurgulanan komut bırakınca çalışır. Ctrl + sağ tuş her zaman kaydırır.")
	_fill_gestures()
	return m


func gesture_choices(ctx: String) -> Array:
	var out: Array = [""]
	for id in command_ids():
		var c: Dictionary = app._commands[id]
		if str(c["ctx"]) == "sketch" and ctx != "sketch":
			continue
		out.append(id)
	if ctx == "sketch":
		for t in app.tool_buttons:
			if not out.has("tool:" + str(t)):
				out.append("tool:" + str(t))
	return out


func _fill_gestures() -> void:
	for c in _g_box.get_children():
		_g_box.remove_child(c)
		c.queue_free()
	var mp := MouseGesture.mapping(_g_ctx)
	var choices := gesture_choices(_g_ctx)
	for i in 8:
		var l := Label.new()
		l.text = str(MouseGesture.DIRS[i])
		l.custom_minimum_size.x = 120
		_g_box.add_child(l)
		var ob := OptionButton.new()
		ob.custom_minimum_size.x = 380
		ob.fit_to_longest_item = false
		for id in choices:
			ob.add_item("—" if id == "" else ("%s  (%s)" % [app.command_label(id), I18n.t(str(app._commands[id]["group"]))] if app._commands.has(id) else id))
		ob.selected = maxi(choices.find(mp[i]), 0)
		ob.item_selected.connect(func(j: int) -> void:
			var arr := MouseGesture.mapping(_g_ctx)
			arr[i] = choices[j]
			MouseGesture.save_mapping(_g_ctx, arr))
		_g_box.add_child(ob)


# ---------------------------------------------------------------- Eklentiler

func _plugins() -> Control:
	var m := MarginContainer.new()
	m.name = "Eklentiler"
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	var pl: Plugins = app.plugins
	if pl == null or pl.items.is_empty():
		_note(v, "Eklenti bulunamadı.")
	else:
		for it in pl.items:
			var cb := CheckBox.new()
			cb.text = str(it["name"])
			cb.button_pressed = bool(it["enabled"])
			var pid := str(it["id"])
			cb.toggled.connect(func(b: bool) -> void:
				Plugins.set_enabled(pid, b)
				app._set_status("Eklenti değişikliği yeniden başlatınca uygulanır."))
			v.add_child(cb)
			var st := "yüklendi" if bool(it["ok"]) else ("kapalı" if not bool(it["enabled"]) else "hata: " + str(it["error"]))
			_note(v, "    %s\n    %s  —  %s" % [str(it["desc"]), it["path"], st])
	v.add_child(HSeparator.new())
	var h := HBoxContainer.new()
	for d in Plugins.dirs():
		var b := Button.new()
		b.text = "Klasörü aç: " + str(d).get_file()
		b.tooltip_text = str(d)
		var dd := str(d)
		b.pressed.connect(func() -> void:
			DirAccess.make_dir_recursive_absolute(dd)
			OS.shell_open(dd))
		h.add_child(b)
	v.add_child(h)
	_note(v, "Eklenti: setup(api: PluginApi) içeren .gd dosyası (src/core/plugin_api.gd). Açma / kapama yeniden başlatınca uygulanır.")
	return m
