class_name PropertyPanel
extends PanelContainer
## Özellik paneli. İçerik koddan kurulur.

var _scroll: ScrollContainer
var _box: VBoxContainer


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.c("panel")
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(_box)


func clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()


func title(text: String, icon: Texture2D = null) -> void:
	var h := HBoxContainer.new()
	if icon:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		h.add_child(tr)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	h.add_child(l)
	_box.add_child(h)
	_box.add_child(HSeparator.new())


func section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UiTheme.c("section"))
	_box.add_child(l)


func info(text: String, color := Color(0.75, 0.78, 0.82)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UiTheme.adapt(color))
	l.custom_minimum_size.x = 120
	_box.add_child(l)
	return l


func _row(label: String, ctrl: Control, suffix := "") -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 92
	h.add_child(l)
	h.add_child(ctrl)
	if suffix != "":
		var s := Label.new()
		s.text = suffix
		s.custom_minimum_size.x = 26
		h.add_child(s)
	_box.add_child(h)


func number(label: String, value: float, on_commit: Callable, kind := "length", min_v := -INF, max_v := INF) -> NumField:
	var f := NumField.new(kind, value)
	f.min_value = min_v
	f.max_value = max_v
	f.value_committed.connect(on_commit)
	var suffix := Units.length_unit if kind == "length" else ("°" if kind == "angle" else "")
	_row(label, f, suffix)
	return f


## Etiketli satıra hazır bir denetim ekler.
func add_control(label: String, ctrl: Control) -> void:
	_row(label, ctrl)


## Etiketli metin alanı; Enter veya odak kaybında on_commit(text) çağrılır.
func text_field(label: String, value: String, on_commit: Callable, placeholder := "") -> LineEdit:
	var le := LineEdit.new()
	le.text = value
	le.placeholder_text = placeholder
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.custom_minimum_size.x = 90
	var last := [value]
	var fire := func(t: String) -> void:
		if t != last[0]:
			last[0] = t
			on_commit.call(t)
	le.text_submitted.connect(fire)
	le.focus_exited.connect(func(): fire.call(le.text))
	_row(label, le)
	return le


func check(label: String, value: bool, on_toggle: Callable) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = value
	cb.toggled.connect(on_toggle)
	_box.add_child(cb)
	return cb


func option(label: String, items: Array, selected: int, on_select: Callable) -> OptionButton:
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(str(it))
	ob.selected = clampi(selected, 0, maxi(items.size() - 1, 0))
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.item_selected.connect(on_select)
	_row(label, ob)
	return ob


func button(text: String, on_press: Callable, icon: Texture2D = null) -> Button:
	var b := Button.new()
	b.text = text
	if icon:
		b.icon = icon
	b.pressed.connect(on_press)
	_box.add_child(b)
	return b


## Simge + metin + sil düğmesi satırı (ör. mevcut ilişkiler listesi).
func item_row(text: String, icon: Texture2D, on_delete: Callable) -> void:
	var h := HBoxContainer.new()
	if icon:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		h.add_child(tr)
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.tooltip_text = text
	h.add_child(l)
	var b := Button.new()
	b.icon = Icons.get_icon("delete", 14)
	b.flat = true
	b.tooltip_text = "Sil"
	b.pressed.connect(on_delete)
	h.add_child(b)
	_box.add_child(h)


func ok_cancel(on_ok: Callable, on_cancel: Callable) -> void:
	var h := HBoxContainer.new()
	var ok := Button.new()
	ok.text = "  Tamam  "
	ok.icon = Icons.get_icon("exit_sketch", 18)
	ok.pressed.connect(on_ok)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cancel := Button.new()
	cancel.text = "  İptal  "
	cancel.icon = Icons.get_icon("delete", 18)
	cancel.pressed.connect(on_cancel)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ok)
	h.add_child(cancel)
	_box.add_child(h)
	_box.add_child(HSeparator.new())


func spacer(h := 6) -> void:
	var c := Control.new()
	c.custom_minimum_size.y = h
	_box.add_child(c)
