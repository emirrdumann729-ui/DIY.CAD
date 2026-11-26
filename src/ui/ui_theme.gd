class_name UiTheme
extends RefCounted
## Arayüz teması (Faz 9): koyu (varsayılan, Godot teması) veya açık. Açılışta uygulanır (ikonlar ve
## sabit renkli paneller yeniden kurulmalı); arayüz ölçeği anında değişir.

static var light := false

const DARK := {
	"bg": Color(0.12, 0.14, 0.17), "bar": Color(0.09, 0.1, 0.13), "cm": Color(0.15, 0.17, 0.21),
	"panel": Color(0.13, 0.15, 0.18), "section": Color(0.55, 0.75, 1.0), "info": Color(0.75, 0.78, 0.82),
	"title": Color(0.55, 0.62, 0.72), "icon_line": "#dfe7f1",
}
const LIGHT := {
	"bg": Color(0.86, 0.88, 0.91), "bar": Color(0.8, 0.83, 0.87), "cm": Color(0.92, 0.93, 0.95),
	"panel": Color(0.96, 0.965, 0.975), "section": Color(0.1, 0.36, 0.72), "info": Color(0.25, 0.28, 0.32),
	"title": Color(0.3, 0.36, 0.45), "icon_line": "#2f3947",
}


static func c(key: String) -> Variant:
	return (LIGHT if light else DARK)[key]


## Koyu tema için seçilmiş açık metin renklerini açık temada okunur hale getirir
static func adapt(col: Color) -> Color:
	if not light:
		return col
	var lum := 0.2126 * col.r + 0.7152 * col.g + 0.0722 * col.b
	if lum > 0.45:
		return col.darkened(clampf((lum - 0.25) / lum, 0.3, 0.7))
	return col


static func _flat(bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 3, margin := 4.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin + 2
	s.content_margin_right = margin + 2
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s


## Açık tema nesnesi (koyu temada null: Godot varsayılanı)
static func build_theme() -> Theme:
	if not light:
		return null
	var t := Theme.new()
	var fg := Color(0.13, 0.15, 0.19)
	var fg_dis := Color(0.55, 0.57, 0.6)
	var sel := Color(0.72, 0.83, 0.97)
	var border := Color(0.7, 0.73, 0.78)
	var accent := Color(0.2, 0.47, 0.85)
	for ty in ["Label", "Button", "MenuButton", "OptionButton", "CheckBox", "CheckButton", "LineEdit", "TextEdit", "Tree",
			"ItemList", "PopupMenu", "TabBar", "TabContainer", "LinkButton", "AcceptDialog", "ConfirmationDialog", "TooltipLabel", "RichTextLabel"]:
		t.set_color("font_color", ty, fg)
		t.set_color("font_hover_color", ty, fg)
		t.set_color("font_pressed_color", ty, accent.darkened(0.2))
		t.set_color("font_hover_pressed_color", ty, accent.darkened(0.2))
		t.set_color("font_focus_color", ty, fg)
		t.set_color("font_disabled_color", ty, fg_dis)
		t.set_color("font_selected_color", ty, fg)
		t.set_color("font_outline_color", ty, Color(1, 1, 1, 0))
	t.set_color("default_color", "RichTextLabel", fg)
	t.set_color("font_unselected_color", "TabBar", Color(0.35, 0.38, 0.43))
	t.set_color("font_unselected_color", "TabContainer", Color(0.35, 0.38, 0.43))
	t.set_color("font_placeholder_color", "LineEdit", fg_dis)
	t.set_color("font_uneditable_color", "LineEdit", fg_dis)
	t.set_color("caret_color", "LineEdit", fg)
	t.set_color("selection_color", "LineEdit", sel)
	t.set_color("font_separator_color", "PopupMenu", Color(0.4, 0.43, 0.48))
	t.set_color("font_accelerator_color", "PopupMenu", Color(0.4, 0.43, 0.48))
	t.set_color("guide_color", "Tree", Color(0, 0, 0, 0.08))
	t.set_color("relationship_line_color", "Tree", Color(0.6, 0.63, 0.68))
	t.set_color("parent_hl_line_color", "Tree", Color(0.5, 0.53, 0.58))
	t.set_color("children_hl_line_color", "Tree", Color(0.6, 0.63, 0.68))
	t.set_color("drop_position_color", "Tree", accent)
	for st in ["icon_normal_color", "icon_hover_color", "icon_focus_color"]:
		t.set_color(st, "Button", Color(1, 1, 1))
	var btn_n := _flat(Color(0.88, 0.9, 0.93), border, 1)
	var btn_h := _flat(Color(0.82, 0.86, 0.92), border, 1)
	var btn_p := _flat(sel, accent, 1)
	var btn_d := _flat(Color(0.9, 0.91, 0.92), Color(0.82, 0.84, 0.86), 1)
	var empty := StyleBoxEmpty.new()
	var empty_m := StyleBoxEmpty.new()
	empty_m.content_margin_left = 6
	empty_m.content_margin_right = 6
	empty_m.content_margin_top = 4
	empty_m.content_margin_bottom = 4
	for ty2 in ["Button", "MenuButton", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", ty2, btn_n if ty2 in ["Button", "OptionButton"] else empty_m)
		t.set_stylebox("hover", ty2, btn_h)
		var chk: bool = ty2 in ["CheckBox", "CheckButton"]
		t.set_stylebox("pressed", ty2, empty_m if chk else btn_p)
		t.set_stylebox("hover_pressed", ty2, btn_h if chk else btn_p)
		t.set_stylebox("disabled", ty2, btn_d if ty2 in ["Button", "OptionButton"] else empty_m)
		t.set_stylebox("focus", ty2, empty)
	t.set_stylebox("normal", "LineEdit", _flat(Color(1, 1, 1), border, 1))
	t.set_stylebox("focus", "LineEdit", _flat(Color(0, 0, 0, 0), accent, 1))
	t.set_stylebox("read_only", "LineEdit", _flat(Color(0.93, 0.94, 0.95), border, 1))
	t.set_stylebox("normal", "TextEdit", _flat(Color(1, 1, 1), border, 1))
	t.set_stylebox("focus", "TextEdit", _flat(Color(0, 0, 0, 0), accent, 1))
	t.set_stylebox("panel", "PanelContainer", _flat(Color(0.95, 0.96, 0.97), Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("panel", "Panel", _flat(Color(0.95, 0.96, 0.97), Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("panel", "PopupMenu", _flat(Color(0.99, 0.99, 1.0), border, 1, 3, 4))
	t.set_stylebox("hover", "PopupMenu", _flat(sel, Color(0, 0, 0, 0), 0, 2))
	var sep_line := StyleBoxLine.new()
	sep_line.color = Color(0.78, 0.8, 0.84)
	t.set_stylebox("separator", "PopupMenu", sep_line)
	t.set_stylebox("separator", "HSeparator", sep_line)
	var vsep := StyleBoxLine.new()
	vsep.color = Color(0.74, 0.77, 0.81)
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	t.set_stylebox("panel", "Tree", _flat(Color(1, 1, 1), border, 1, 2))
	t.set_stylebox("focus", "Tree", empty)
	t.set_stylebox("selected", "Tree", _flat(sel, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("selected_focus", "Tree", _flat(sel, accent, 1, 2))
	t.set_stylebox("cursor", "Tree", empty)
	t.set_stylebox("cursor_unfocused", "Tree", empty)
	t.set_stylebox("hovered", "Tree", _flat(Color(0.9, 0.93, 0.98), Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("title_button_normal", "Tree", _flat(Color(0.9, 0.91, 0.93), border, 1, 0))
	t.set_stylebox("panel", "ItemList", _flat(Color(1, 1, 1), border, 1, 2))
	t.set_stylebox("selected", "ItemList", _flat(sel, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("selected_focus", "ItemList", _flat(sel, accent, 1, 2))
	t.set_stylebox("tab_selected", "TabBar", _flat(Color(1, 1, 1), accent, 0, 3, 5))
	(t.get_stylebox("tab_selected", "TabBar") as StyleBoxFlat).border_width_top = 2
	t.set_stylebox("tab_unselected", "TabBar", _flat(Color(0.86, 0.88, 0.91), Color(0, 0, 0, 0), 0, 3, 5))
	t.set_stylebox("tab_hovered", "TabBar", _flat(Color(0.93, 0.94, 0.96), Color(0, 0, 0, 0), 0, 3, 5))
	t.set_stylebox("tab_selected", "TabContainer", t.get_stylebox("tab_selected", "TabBar"))
	t.set_stylebox("tab_unselected", "TabContainer", t.get_stylebox("tab_unselected", "TabBar"))
	t.set_stylebox("tab_hovered", "TabContainer", t.get_stylebox("tab_hovered", "TabBar"))
	t.set_stylebox("panel", "TabContainer", _flat(Color(0.97, 0.975, 0.98), border, 1, 2))
	t.set_stylebox("panel", "AcceptDialog", _flat(Color(0.96, 0.965, 0.975), Color(0, 0, 0, 0), 0, 0, 8))
	t.set_stylebox("embedded_border", "Window", _flat(Color(0.96, 0.965, 0.975), border, 1, 4, 0))
	t.set_color("title_color", "Window", fg)
	t.set_stylebox("panel", "TooltipPanel", _flat(Color(1.0, 1.0, 0.94), border, 1, 3, 4))
	t.set_color("font_color", "TooltipLabel", fg)
	for sb_ty in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_ty, _flat(Color(0.9, 0.91, 0.93), Color(0, 0, 0, 0), 0, 4, 0))
		t.set_stylebox("grabber", sb_ty, _flat(Color(0.7, 0.73, 0.78), Color(0, 0, 0, 0), 0, 4, 0))
		t.set_stylebox("grabber_highlight", sb_ty, _flat(Color(0.6, 0.64, 0.7), Color(0, 0, 0, 0), 0, 4, 0))
		t.set_stylebox("grabber_pressed", sb_ty, _flat(accent, Color(0, 0, 0, 0), 0, 4, 0))
	return t


## Ayarlardan: tema (açılışta) ve arayüz ölçeği
static func apply_settings(tree: SceneTree, override := "") -> void:
	light = (override if override != "" else str(AppSettings.get_v("ui", "theme"))) == "light"
	Icons.L = str(c("icon_line"))
	Icons.clear_cache()
	var th := build_theme()
	tree.root.theme = th
	set_scale(tree, float(AppSettings.get_v("ui", "scale")))


static func set_scale(tree: SceneTree, s: float) -> void:
	tree.root.content_scale_factor = clampf(s, 0.75, 2.5)
