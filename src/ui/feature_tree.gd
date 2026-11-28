class_name FeatureTree
extends Tree
## Özellik (tasarım) ağacı. Öğe meta verisi: {kind: "part"|"plane"|"origin"|"feature", id}

signal picked(meta: Dictionary)
signal activated(meta: Dictionary)
signal context_requested(meta: Dictionary, at: Vector2)
signal feature_renamed(feature_id: int, new_name: String)
## Sürükle-bırak: data = {kind: "feature"|"rollback", id}, hedef özelliğin önüne/arkasına
signal move_requested(data: Dictionary, target_id: int, after: bool)


func _ready() -> void:
	hide_root = false
	allow_rmb_select = true
	select_mode = Tree.SELECT_SINGLE
	item_selected.connect(_on_selected)
	item_activated.connect(_on_activated)
	item_mouse_selected.connect(_on_mouse_selected)
	item_edited.connect(_on_edited)
	empty_clicked.connect(_on_empty_clicked)


func _on_empty_clicked(_pos: Vector2, _button: int) -> void:
	deselect_all()
	picked.emit({})


func _feature_icon(f: CadFeature) -> Texture2D:
	if f.error != "":
		return Icons.get_icon("warning", 18)
	match f.type:
		"sketch":
			return Icons.get_icon("sketch", 18)
		"sketch3d":
			return Icons.get_icon("sketch3d", 18)
		"extrude":
			return Icons.get_icon("cut" if f.is_cut() else "extrude", 18)
		"revolve":
			return Icons.get_icon("revcut" if f.is_cut() else "revolve", 18)
		"fillet":
			return Icons.get_icon("fillet3d", 18)
		"chamfer":
			return Icons.get_icon("chamfer3d", 18)
		"shell":
			return Icons.get_icon("shell", 18)
		"import":
			return Icons.get_icon("import", 18)
		"draft":
			return Icons.get_icon("draft", 18)
		"rib":
			return Icons.get_icon("rib", 18)
		"combine":
			return Icons.get_icon("combine", 18)
		"move_body":
			return Icons.get_icon("move_body", 18)
		"split":
			return Icons.get_icon("split", 18)
		"sweep":
			return Icons.get_icon("sweepcut" if f.is_cut() else "sweep", 18)
		"loft":
			return Icons.get_icon("loftcut" if f.is_cut() else "loft", 18)
		"lpattern", "cpattern", "tpattern", "refplane", "refaxis", "refpoint", "helix", "hole", "dome", "refcsys", "projcurve", "cvpattern", "wrap", "emboss":
			return Icons.get_icon(f.type, 18)
		"mirror":
			return Icons.get_icon("mirror3d", 18)
		"sm_base", "sm_edge", "weld", "srf_extrude", "srf_revolve", "srf_loft", "srf_planar", "srf_offset", "srf_knit", "srf_thicken", "srf_trim":
			return Icons.get_icon(f.type, 18)
	return Icons.get_icon("part", 18)


func _add_feature_item(parent: TreeItem, f: CadFeature, selected: Dictionary) -> TreeItem:
	var it := create_item(parent)
	var prefix := ""
	if f.is_sketch() and not f.sketch.is_empty():
		match str(SketchSolver.analyze_sketch(f.sketch)["status"]):
			"under":
				prefix = "(-) "
			"over":
				prefix = "(+) "
	it.set_text(0, prefix + f.name)
	it.set_icon(0, _feature_icon(f))
	it.set_metadata(0, {"kind": "feature", "id": f.id})
	var tip := f.type_label()
	if prefix == "(-) ":
		tip += "\nEksik tanımlı taslak (boyut/ilişki ekleyerek tam tanımlayın)"
	elif prefix == "(+) ":
		tip += "\nAşırı tanımlı taslak"
	if f.error != "":
		tip += "\nHata: " + f.error
		it.set_custom_color(0, UiTheme.adapt(Color(1.0, 0.45, 0.35)))
	if f.suppressed:
		it.set_custom_color(0, UiTheme.adapt(Color(0.55, 0.55, 0.6)))
		tip += "\n(Bastırılmış)"
	if _doc and _doc.is_rolled_back(f):
		it.set_custom_color(0, UiTheme.adapt(Color(0.45, 0.45, 0.5)))
		tip += "\n(Geri alma çubuğunun altında: hesaplanmıyor)"
	it.set_tooltip_text(0, tip)
	if selected.get("kind", "") == "feature" and selected.get("id", -1) == f.id:
		it.select(0)
	return it


var _doc: CadDocument = null


func rebuild(doc: CadDocument, selected: Dictionary) -> void:
	_doc = doc
	clear()
	var root := create_item()
	root.set_text(0, doc.part_name + ((" [" + doc.active_config + "]") if doc.active_config != "" else "") + (" *" if doc.dirty else ""))
	root.set_icon(0, Icons.get_icon("part", 18))
	root.set_metadata(0, {"kind": "part"})
	var mat := create_item(root)
	mat.set_text(0, (I18n.t("Malzeme: ") + doc.material) if doc.material != "" else I18n.t("Malzeme") + " " + I18n.t("<belirtilmemiş>"))
	mat.set_icon(0, Icons.get_icon("material", 18))
	mat.set_metadata(0, {"kind": "material"})
	mat.set_tooltip_text(0, "Çift tıklayın veya sağ tıklayın: malzemeyi düzenle")
	for id in SketchPlane.STANDARD_IDS:
		var p := SketchPlane.standard(id)
		var it := create_item(root)
		it.set_text(0, p.name)
		it.set_icon(0, Icons.get_icon("plane", 18))
		it.set_metadata(0, {"kind": "plane", "id": id})
		if selected.get("kind", "") == "plane" and selected.get("id", "") == id:
			it.select(0)
	var o := create_item(root)
	o.set_text(0, "Orijin")
	o.set_icon(0, Icons.get_icon("origin", 18))
	o.set_metadata(0, {"kind": "origin"})
	for fi in doc.features.size():
		var f: CadFeature = doc.features[fi]
		if doc.rollback >= 0 and fi == doc.rollback:
			_add_rollback_item(root)
		if f.is_sketch() and not doc.consumers_of(f.id).is_empty():
			continue  # özelliğin altında gösterilir
		var it := _add_feature_item(root, f, selected)
		if not f.is_sketch() and not f.is_brep_feature():
			for sid in f.used_sketch_ids():
				var sk := doc.get_feature(int(sid))
				if sk:
					_add_feature_item(it, sk, selected)
					it.collapsed = true
					if selected.get("kind", "") == "feature" and selected.get("id", -1) == sk.id:
						it.collapsed = false


func _add_rollback_item(root: TreeItem) -> void:
	var rb := create_item(root)
	rb.set_text(0, "━━━ Geri alma çubuğu ━━━")
	rb.set_custom_color(0, UiTheme.adapt(Color(0.95, 0.75, 0.3)))
	rb.set_metadata(0, {"kind": "rollback"})
	rb.set_tooltip_text(0, "Altındaki özellikler hesaplanmaz. Sürükleyerek taşıyın; sağ tık: kaldır.")


# ---------------------------------------------------------------- sürükle-bırak (özellik sırası, geri alma çubuğu)

func _top_item(it: TreeItem) -> TreeItem:
	var root := get_root()
	while it != null and it.get_parent() != null and it.get_parent() != root:
		it = it.get_parent()
	return it


func _get_drag_data(at_position: Vector2) -> Variant:
	var it := get_item_at_position(at_position)
	if it == null:
		return null
	var m := _meta(it)
	if m.get("kind", "") == "feature" and it.get_parent() != get_root():
		it = _top_item(it)
		m = _meta(it)
	if not (m.get("kind", "") in ["feature", "rollback"]):
		return null
	var lbl := Label.new()
	lbl.text = it.get_text(0)
	set_drag_preview(lbl)
	drop_mode_flags = Tree.DROP_MODE_INBETWEEN
	return m


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or not (str((data as Dictionary).get("kind", "")) in ["feature", "rollback"]):
		return false
	var it := get_item_at_position(at_position)
	if it == null:
		return true
	return str(_meta(_top_item(it)).get("kind", "")) in ["feature", "rollback"]


func _drop_data(at_position: Vector2, data: Variant) -> void:
	drop_mode_flags = Tree.DROP_MODE_DISABLED
	var it := get_item_at_position(at_position)
	if it == null:
		move_requested.emit(data, -1, true)
		return
	var top := _top_item(it)
	var m := _meta(top)
	var after := get_drop_section_at_position(at_position) > 0
	if m.get("kind", "") == "rollback":
		return
	move_requested.emit(data, int(m.get("id", -1)), after)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		drop_mode_flags = Tree.DROP_MODE_DISABLED


func _meta(it: TreeItem) -> Dictionary:
	if it == null:
		return {}
	var m = it.get_metadata(0)
	return m if m is Dictionary else {}


func _on_selected() -> void:
	picked.emit(_meta(get_selected()))


func _on_activated() -> void:
	activated.emit(_meta(get_selected()))


func _on_mouse_selected(pos: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		context_requested.emit(_meta(get_selected()), get_global_transform() * pos)


## Seçili özelliği yerinde yeniden adlandırmaya başlar.
func begin_rename() -> void:
	var it := get_selected()
	if it == null or _meta(it).get("kind", "") != "feature":
		return
	it.set_editable(0, true)
	edit_selected(true)


func _on_edited() -> void:
	var it := get_edited()
	if it == null:
		return
	it.set_editable(0, false)
	var m := _meta(it)
	if m.get("kind", "") == "feature":
		feature_renamed.emit(int(m["id"]), it.get_text(0).strip_edges())
