class_name ExportDialog
extends ConfirmationDialog
## Tek "Dışa Aktar" penceresi: tüm formatlar gruplu listede. Şu an kullanılamayanlar (OpenCASCADE yok,
## teknik resim açık değil, kapalı format...) gri görünür; seçilince nedeni ve önerilen seçenek altta yazar.

signal chosen(id: String)

var tree: Tree
var info: Label
var _reasons := {}   # id -> "" (uygun) ya da neden


func _init() -> void:
	title = "Dışa Aktar"
	ok_button_text = "Dışa aktar..."
	cancel_button_text = "Kapat"
	min_size = Vector2i(760, 560)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := Label.new()
	head.text = "Format seçin (çift tıklama da olur). Gri olanlar şu an kullanılamaz — nedeni seçince aşağıda yazar."
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	tree = Tree.new()
	tree.name = "ExportTree"
	tree.columns = 2
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size = Vector2(0, 360)
	tree.set_column_expand(0, true)
	tree.set_column_expand(1, true)
	tree.set_column_custom_minimum_width(1, 180)
	tree.item_selected.connect(_on_selected)
	tree.item_activated.connect(_on_activated)
	box.add_child(tree)
	info = Label.new()
	info.name = "ExportInfo"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(0, 64)
	box.add_child(info)
	confirmed.connect(_on_confirmed)


## reason_of(format) -> "" (uygun) ya da neden; last: önceki seçim
func open(reason_of: Callable, last := "") -> void:
	tree.clear()
	_reasons.clear()
	var root := tree.create_item()
	var groups := {}
	var first_ok: TreeItem = null
	var last_item: TreeItem = null
	var dim := Color(0.55, 0.57, 0.6)
	for f in ExportFormats.FORMATS:
		var g := str(f["group"])
		if not groups.has(g):
			var gi := tree.create_item(root)
			gi.set_text(0, I18n.t(g))
			gi.set_selectable(0, false)
			gi.set_selectable(1, false)
			gi.set_custom_color(0, Color(0.45, 0.7, 1.0))
			groups[g] = gi
		var it := tree.create_item(groups[g])
		var r := str(reason_of.call(f))
		_reasons[f["id"]] = r
		it.set_text(0, I18n.t(str(f["label"])))
		var exts: Array = []
		for e in f["ext"]:
			exts.append("." + str(e))
		it.set_text(1, " ".join(exts))
		it.set_metadata(0, f["id"])
		if r != "":
			it.set_custom_color(0, dim)
			it.set_custom_color(1, dim)
			it.set_tooltip_text(0, r)
		elif first_ok == null:
			first_ok = it
		if f["id"] == last and r == "":
			last_item = it
	var sel := last_item if last_item else first_ok
	if sel:
		sel.select(0)
		tree.scroll_to_item(sel)
		_on_selected()
	else:
		info.text = ""
		get_ok_button().disabled = true
	popup_centered(min_size)


func selected_id() -> String:
	var it := tree.get_selected()
	return str(it.get_metadata(0)) if it and it.get_metadata(0) != null else ""


func _on_selected() -> void:
	var id := selected_id()
	if id == "":
		return
	var f := ExportFormats.by_id(id)
	var r: String = _reasons.get(id, "")
	info.text = I18n.t(str(f.get("desc", ""))) + (("\n⚠ " + I18n.t(r)) if r != "" else "")
	get_ok_button().disabled = r != ""


func _on_activated() -> void:
	var id := selected_id()
	if id != "" and _reasons.get(id, "x") == "":
		hide()
		chosen.emit(id)


func _on_confirmed() -> void:
	var id := selected_id()
	if id != "" and _reasons.get(id, "x") == "":
		chosen.emit(id)
