class_name SketchEditor
extends Node
## Taslak düzenleyici: çizim araçları, yakalama, seçim, sürükleme, Akıllı Boyut, ilişkiler.
## Her değişiklik kısıt çözücüden geçer; çözülemeyen (çelişen) değişiklik otomatik geri alınır.
## Değişiklik akışı: before := _begin()  ->  taslağı değiştir  ->  _finish(before, ...)

signal selection_changed
signal tool_changed(tool: String)
signal status(text: String)
signal cursor_moved(local: Vector2)
signal definition_changed(info: Dictionary)

const COL_UNDER := Color(0.08, 0.25, 0.95)
const COL_FULL := Color(0.04, 0.04, 0.07)
const COL_OVER := Color(0.92, 0.08, 0.08)
const COL_SELECTED := Color(0.95, 0.38, 0.0)
const COL_HOVER := Color(0.0, 0.7, 1.0)
const COL_PREVIEW := Color(0.15, 0.5, 1.0)
const COL_SNAP := Color(1.0, 0.55, 0.0)
const COL_ORIGIN := Color(0.85, 0.1, 0.1)
const COL_DIM := Color(0.18, 0.18, 0.24)
const COL_DIM_DRIVEN := Color(0.5, 0.5, 0.56)
const SNAP_PX := 10.0
const ENTITY_SNAP_PX := 6.0
const PICK_PX := 7.0

const TOOL_NAMES := {
	"select": "Seç",
	"line": "Çizgi",
	"centerline": "Merkez Çizgisi",
	"rect": "Köşe Dikdörtgen",
	"crect": "Merkez Dikdörtgen",
	"circle": "Daire",
	"arc": "Merkez Noktalı Yay",
	"dimension": "Akıllı Boyut",
	"polygon": "Çokgen",
	"slot": "Düz Kanal",
	"spline": "Spline",
	"text": "Metin",
	"trim": "Kırp",
	"extend": "Uzat",
	"fillet": "Taslak Köşe Yuvarlatma",
	"chamfer": "Taslak Pahı",
	"ellipse": "Elips",
	"parabola": "Parabol",
	"convert": "Varlıkları Dönüştür",
}

var _press_screen := Vector2.ZERO
var _p3 := Vector2.ZERO            # parabol: başlangıç ucu

# Araç seçenekleri (panelden değiştirilir)
var fillet_radius := 5.0
var chamfer_dist := 2.0
var polygon_sides := 6
var text_default := "DIY.CAD"
var text_height := 10.0
var preview_paths: Array = []      # işlem önizlemesi (ör. ofset) için kesikli çizgiler
var _spline_pts: Array = []        # spline aracında tıklanan noktalar (yakalama bilgisiyle)

const RELATION_NAMES := {
	"horizontal": "Yatay", "vertical": "Dikey", "parallel": "Paralel", "perpendicular": "Dik",
	"collinear": "Eşdoğrusal", "equal": "Eşit", "concentric": "Eş Merkezli", "tangent": "Teğet",
	"coincident": "Çakışık", "merge": "Çakışık", "midpoint": "Orta Nokta", "symmetric": "Simetrik", "fix": "Sabit", "offset": "Ofset",
}

const DIM_NAMES := {
	"distance": "Mesafe", "hdistance": "Yatay mesafe", "vdistance": "Dikey mesafe",
	"pl_distance": "Nokta-çizgi mesafesi", "radius": "Yarıçap", "diameter": "Çap", "angle": "Açı",
}

var viewport: CadViewport
var doc: CadDocument
var feature: CadFeature
var active := false
var tool := "select"
var grid_snap := true
var grid_step := 10.0
var show_relations := true

var selected_entities := {}
var selected_points := {}
var selected_constraints := {}
var analysis := {}

var _stage := 0
var _start_pid := -1
var _start_pos := Vector2.ZERO
var _start_snap := {}
var _chain_first_pid := -1
var _p2 := Vector2.ZERO
var _p2_snap := {}
var _arc_sweep := 0.0
var _arc_last_angle := 0.0
var _cursor := Vector2.ZERO
var _snap_pid := -1
var _snap_eid := -1
var _snap_kind := ""
var _hint := ""
var _hover_entity := -1
var _hover_point := -1
var _has_cursor := false
var _mouse_screen := Vector2.ZERO

var _drag_mode := ""
var _drag_pid := -1
var _drag_eid := -1
var _drag_started := false
var _press_pos := Vector2.ZERO
var _drag_start_local := Vector2.ZERO
var _drag_init := {}
var _drag_before := {}
var _drag_good := {}

var _dim_sel: Array = []
var _labels: Array = []
var _badges: Array = []
var _label_items: Array = []
var _badge_items: Array = []
var _edit_field: NumField = null


func sketch() -> Sketch:
	return feature.sketch


func plane() -> SketchPlane:
	return feature.plane


# ================================================================ oturum

func begin(f: CadFeature, look := true) -> void:
	feature = f
	active = true
	tool = "select"
	_reset_state()
	selected_entities.clear()
	selected_points.clear()
	selected_constraints.clear()
	if look:
		look_at_plane()
	_analyze()
	tool_changed.emit(tool)
	_emit_hint()
	redraw()


func look_at_plane() -> void:
	var p := plane()
	var cam := viewport.camera
	var target := p.to_world(p.to_local(cam.target))
	var sz := cam.view_size
	if not sketch().is_empty():
		var r := sketch().bounds()
		target = p.to_world(r.get_center())
		var vs := cam.viewport_size()
		var aspect := vs.x / maxf(vs.y, 1.0)
		sz = maxf(maxf(r.size.y, r.size.x / aspect) * 1.6, 20.0)
	cam.animate_to(p.basis(), target, sz, true)


func end() -> void:
	_close_editor()
	active = false
	feature = null
	_reset_state()
	selected_entities.clear()
	selected_points.clear()
	selected_constraints.clear()
	(viewport.edit_mi.mesh as ArrayMesh).clear_surfaces()
	(viewport.grid_mi.mesh as ArrayMesh).clear_surfaces()
	viewport.show_cursor_text("", Vector2.ZERO)
	for l in _labels:
		l.visible = false
	for b in _badges:
		b.visible = false
	_label_items.clear()
	_badge_items.clear()


func _reset_state() -> void:
	_stage = 0
	_drag_mode = ""
	_drag_pid = -1
	_drag_eid = -1
	_drag_started = false
	_dim_sel.clear()
	_spline_pts.clear()


## Belge değişince (commit / geri al) çağrılır.
func refresh_feature() -> bool:
	if feature == null:
		return false
	var f := doc.get_feature(feature.id)
	if f == null or not f.is_sketch():
		return false
	if f != feature:
		feature = f
		_reset_state()
	_prune_selection()
	if _start_pid >= 0 and not sketch().points.has(_start_pid):
		_stage = 0
	_analyze()
	redraw()
	return true


func _prune_selection() -> void:
	var sk := sketch()
	for eid in selected_entities.keys():
		if sk.get_entity(eid).is_empty():
			selected_entities.erase(eid)
	for pid in selected_points.keys():
		if not sk.points.has(pid):
			selected_points.erase(pid)
	for cid in selected_constraints.keys():
		if sk.get_constraint(cid).is_empty():
			selected_constraints.erase(cid)


func _analyze() -> void:
	analysis = SketchSolver.analyze_sketch(sketch())
	definition_changed.emit(analysis)


func set_tool(t: String) -> void:
	_close_editor()
	_reset_state()
	tool = t
	if t != "select":
		selected_entities.clear()
		selected_points.clear()
		selected_constraints.clear()
		selection_changed.emit()
	tool_changed.emit(t)
	_emit_hint()
	redraw()


func set_grid_snap(v: bool) -> void:
	grid_snap = v


func set_show_relations(v: bool) -> void:
	show_relations = v
	redraw()


## Esc / sağ tık: önce devam eden işlemi, sonra aracı, sonra seçimi iptal eder.
func cancel() -> void:
	if tool == "spline" and _spline_pts.size() >= 2:
		_finish_spline()
		return
	if _stage > 0 or not _dim_sel.is_empty() or not _spline_pts.is_empty():
		_stage = 0
		_dim_sel.clear()
		_spline_pts.clear()
	elif tool != "select":
		set_tool("select")
		return
	elif has_selection():
		clear_selection()
	_emit_hint()
	redraw()


func has_selection() -> bool:
	return not (selected_entities.is_empty() and selected_points.is_empty() and selected_constraints.is_empty())


func is_busy() -> bool:
	return _stage > 0 or not _dim_sel.is_empty() or _drag_started or not _spline_pts.is_empty()


func clear_selection() -> void:
	selected_entities.clear()
	selected_points.clear()
	selected_constraints.clear()
	selection_changed.emit()
	redraw()


func select_entity(eid: int) -> void:
	selected_entities = {eid: true}
	selected_points.clear()
	selected_constraints.clear()
	selection_changed.emit()


func select_constraint(cid: int) -> void:
	selected_entities.clear()
	selected_points.clear()
	selected_constraints = {cid: true}
	selection_changed.emit()
	redraw()


func _wpp() -> float:
	return viewport.camera.world_per_pixel()


func _emit_hint() -> void:
	var h := ""
	match tool:
		"select":
			h = I18n.t("Öğe seçin, sürükleyin. Birden fazla öğe seçince (Shift/Ctrl) panelden ilişki ekleyebilirsiniz.")
		"line", "centerline":
			h = I18n.t("Başlangıç noktasını tıklayın.") if _stage == 0 else I18n.t("Sonraki noktayı tıklayın. Çift tık / sağ tık / Esc: zinciri bitir.")
		"rect":
			h = I18n.t("İlk köşeyi tıklayın.") if _stage == 0 else I18n.t("Karşı köşeyi tıklayın.")
		"crect":
			h = I18n.t("Dikdörtgenin merkezini tıklayın.") if _stage == 0 else I18n.t("Köşeyi tıklayın.")
		"circle":
			h = I18n.t("Dairenin merkezini tıklayın.") if _stage == 0 else I18n.t("Yarıçapı belirlemek için tıklayın.")
		"arc":
			match _stage:
				0:
					h = I18n.t("Yayın merkezini tıklayın.")
				1:
					h = I18n.t("Yayın başlangıç noktasını tıklayın.")
				_:
					h = I18n.t("Yayın bitiş noktasını tıklayın (fareyi istediğiniz yönde döndürün).")
		"dimension":
			if _dim_sel.is_empty():
				h = I18n.t("Ölçülecek öğeyi seçin (çizgi, daire, yay, nokta). Var olan boyutu düzenlemek için etikete tıklayın.")
			elif _dim_sel.size() == 1:
				h = I18n.t("Boyutu yerleştirmek için boş bir yere tıklayın veya ikinci öğeyi seçin.")
			else:
				h = I18n.t("Boyutu yerleştirmek için boş bir yere tıklayın.")
		"polygon":
			h = (I18n.t("Çokgenin merkezini tıklayın (%d kenar; panelden değiştirin).") % polygon_sides) if _stage == 0 else I18n.t("Bir köşeyi tıklayın.")
		"slot":
			match _stage:
				0:
					h = I18n.t("Kanalın ilk yay merkezini tıklayın.")
				1:
					h = I18n.t("İkinci yay merkezini tıklayın.")
				_:
					h = I18n.t("Kanal genişliğini belirlemek için tıklayın.")
		"spline":
			h = I18n.t("Spline noktalarını tıklayın. İlk noktaya tıklamak kapatır; çift tık / sağ tık / Enter bitirir.")
		"text":
			h = I18n.t("Metnin yerleşeceği noktayı tıklayın (metin ve boyut panelden değişir).")
		"trim":
			h = I18n.t("Silinecek parçaya tıklayın (en yakın kesişimler arasında kırpılır).")
		"extend":
			h = I18n.t("Uzatılacak çizginin ucuna yakın tıklayın.")
		"fillet":
			h = I18n.t("Yuvarlatılacak köşeye tıklayın (R %s; panelden değiştirin).") % Units.format_length(fillet_radius)
		"chamfer":
			h = I18n.t("Pah kırılacak köşeye tıklayın (%s; panelden değiştirin).") % Units.format_length(chamfer_dist)
		"ellipse":
			match _stage:
				0:
					h = I18n.t("Elipsin merkezini tıklayın.")
				1:
					h = I18n.t("Büyük eksenin ucunu tıklayın.")
				_:
					h = I18n.t("Küçük eksen genişliği için tıklayın.")
		"parabola":
			match _stage:
				0:
					h = I18n.t("Parabolün tepe noktasını tıklayın.")
				1:
					h = I18n.t("Odak noktasını tıklayın (eksen yönü ve açıklık).")
				2:
					h = I18n.t("Başlangıç ucunu tıklayın.")
				_:
					h = I18n.t("Bitiş ucunu tıklayın.")
		"convert":
			h = I18n.t("Taslağa alınacak model yüzüne tıklayın; yüzün kenarları çizgi/yay olarak eklenir.")
	status.emit(I18n.t(str(TOOL_NAMES.get(tool, tool))) + ": " + h)


## Bir işlem (SketchOps) uygular; başarısızsa geri alır. Dönüş: işlem sonucu.
func apply_op(op: Callable, weights := {}) -> Dictionary:
	var before := _begin()
	var r: Dictionary = op.call()
	if not r.get("ok", false):
		feature.sketch = Sketch.from_dict(before)
		doc.drop_checkpoint()
		_prune_selection()
		redraw()
		status.emit(str(r.get("msg", I18n.t("İşlem uygulanamadı."))))
		return r
	if _finish(before, weights):
		status.emit(str(r.get("msg", "")))
	else:
		r["ok"] = false
	return r


func _sel_entity_ids() -> Array:
	return selected_entities.keys()


func offset_selection(dist: float) -> Dictionary:
	var ids := _sel_entity_ids()
	var r := apply_op(func(): return SketchOps.offset(sketch(), ids, dist))
	preview_paths.clear()
	if r.get("ok", false):
		selected_entities.clear()
		for eid in r.get("ids", []):
			selected_entities[eid] = true
		selection_changed.emit()
	return r


func set_offset_preview(dist: float) -> void:
	preview_paths.clear()
	for ch in SketchOps.offset_geometry(sketch(), _sel_entity_ids(), dist):
		for pc in ch["pieces"]:
			match str(pc["type"]):
				"line":
					preview_paths.append(PackedVector2Array([pc["p0"], pc["p1"]]))
				"circle":
					var cpos: Vector2 = sketch().points[pc["c"]]
					var poly := Sketch.circle_polygon(cpos, pc["r"])
					poly.append(poly[0])
					preview_paths.append(poly)
				"arc":
					var cp: Vector2 = pc["cpos"]
					var a0 := ((pc["p0"] as Vector2) - cp).angle()
					var a1 := ((pc["p1"] as Vector2) - cp).angle()
					var sw := fposmod(a1 - a0, TAU) if pc["fwd"] else -fposmod(a0 - a1, TAU)
					var path := PackedVector2Array()
					for i in 33:
						path.append(cp + Vector2.from_angle(a0 + sw * i / 32.0) * float(pc["r"]))
					preview_paths.append(path)
	redraw()


func clear_preview() -> void:
	preview_paths.clear()
	redraw()


## Seçimdeki tek yapı çizgisi (ayna ekseni) veya -1.
func mirror_axis() -> int:
	var axis := -1
	for eid in selected_entities:
		var e := sketch().get_entity(eid)
		if e.get("type", "") == "line" and e.get("construction", false):
			if axis >= 0:
				return -1
			axis = eid
	return axis


func mirror_selection() -> Dictionary:
	var axis := mirror_axis()
	if axis < 0:
		var r0 := {"ok": false, "msg": I18n.t("Aynalamak için öğelerle birlikte tek bir merkez çizgisi (eksen) seçin.")}
		status.emit(r0["msg"])
		return r0
	var ids := _sel_entity_ids()
	return apply_op(func(): return SketchOps.mirror(sketch(), ids, axis))


## Taşı / kopyala / döndür / ölçekle / çoğalt. kind: move, copy, rotate, scale, linear, circular
func transform_selection(kind: String, a: Vector2, b: float, count: int, copy: bool) -> Dictionary:
	var ids := _sel_entity_ids()
	if ids.is_empty():
		var r0 := {"ok": false, "msg": I18n.t("Önce öğeleri seçin.")}
		status.emit(r0["msg"])
		return r0
	var sk := sketch()
	var xf: Callable
	var scale := 1.0
	match kind:
		"move":
			xf = func(p: Vector2) -> Vector2: return p + a
		"rotate":
			var ang := deg_to_rad(b)
			xf = func(p: Vector2) -> Vector2: return a + (p - a).rotated(ang)
		"scale":
			scale = maxf(b, 1e-4)
			xf = func(p: Vector2) -> Vector2: return a + (p - a) * scale
		"linear":
			return apply_op(func(): return {"ok": true, "msg": I18n.t("Doğrusal çoğaltma: %d kopya.") % count, "ids": SketchOps.linear_pattern(sk, ids, a, count)})
		"circular":
			return apply_op(func(): return {"ok": true, "msg": I18n.t("Dairesel çoğaltma: %d kopya.") % count, "ids": SketchOps.circular_pattern(sk, ids, a, count, b)})
	if copy:
		return apply_op(func(): return {"ok": true, "msg": I18n.t("Kopyalandı."), "ids": SketchOps.copy_entities(sk, ids, xf, scale)})
	var before := _begin()
	var moved := SketchOps.transform_points(sk, ids, xf, scale)
	var ok := _finish(before, _weights_for(moved))
	if ok:
		status.emit(I18n.t("Dönüştürüldü."))
	return {"ok": ok}


# ================================================================ değişiklik yönetimi

func _begin() -> Dictionary:
	doc.checkpoint()
	return sketch().to_dict()


## Çözer; başarılıysa kaydeder, değilse eski hâle döner.
func _finish(before: Dictionary, weights := {}, fail_msg := "", check_cids: Array = []) -> bool:
	var sk := sketch()
	var s := SketchSolver.new(sk, weights)
	var r := s.solve()
	var msg := ""
	if not r["ok"]:
		msg = fail_msg if fail_msg != "" else I18n.t("Bu değişiklik mevcut ilişki ve boyutlarla çelişiyor; geri alındı.")
	else:
		s.apply()
		for cid in check_cids:
			if not sk.get_constraint(cid).is_empty() and not SketchSolver.is_independent(sk, cid):
				msg = I18n.t("Bu ilişki/boyut taslağı aşırı tanımlar (gereksiz veya zaten mevcut); eklenmedi.")
				break
	if msg != "":
		feature.sketch = Sketch.from_dict(before)
		doc.drop_checkpoint()
		_prune_selection()
		_analyze()
		redraw()
		status.emit(msg)
		return false
	doc.commit()
	return true


func _capture() -> Dictionary:
	var radii := {}
	for e in sketch().entities:
		if e["type"] == "circle":
			radii[e["id"]] = e["r"]
	return {"p": sketch().points.duplicate(), "r": radii}


func _restore(cap: Dictionary) -> void:
	var sk := sketch()
	sk.points = (cap["p"] as Dictionary).duplicate()
	var radii: Dictionary = cap["r"]
	for e in sk.entities:
		if radii.has(e["id"]):
			e["r"] = radii[e["id"]]


# ================================================================ girdi

func _local_from_screen(pos: Vector2) -> Variant:
	var r := viewport.ray(pos)
	var hit = plane().intersect_ray(r[0], r[1])
	if hit == null:
		return null
	return plane().to_local(hit)


func on_pointer(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		_on_motion((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)


func _update_snap(raw: Vector2, allow_entities := true) -> void:
	var sk := sketch()
	var w := _wpp()
	_snap_pid = -1
	_snap_eid = -1
	_snap_kind = ""
	_hint = ""
	var exclude: Array = []
	if _drag_pid >= 0:
		exclude = [_drag_pid]
	var pid := sk.hit_point(raw, SNAP_PX * w, exclude)
	if pid >= 0:
		_snap_pid = pid
		_snap_kind = "point"
		_cursor = sk.points[pid]
		return
	if allow_entities:
		# Çizgi orta noktası
		for e in sk.entities:
			if e["type"] == "line" and not (_start_pid >= 0 and _start_pid in [e["a"], e["b"]]):
				var mp := sk.line_midpoint(e)
				if raw.distance_to(mp) <= SNAP_PX * w:
					_snap_kind = "midpoint"
					_snap_eid = e["id"]
					_cursor = mp
					return
		# Öğe üzerine (çakışık)
		var best := ENTITY_SNAP_PX * w
		for e in sk.entities:
			if not (e["type"] in ["line", "circle", "arc"]):
				continue
			if _start_pid >= 0 and _start_pid in Sketch.entity_point_ids(e) and e["type"] == "line":
				continue
			var d := sk.entity_distance(e, raw)
			if d <= best:
				best = d
				_snap_eid = e["id"]
		if _snap_eid >= 0:
			_snap_kind = "entity"
			_cursor = sk.closest_on_entity(sk.get_entity(_snap_eid), raw)
			return
	var p := raw
	if _stage >= 1 and (tool == "line" or tool == "centerline"):
		var d2 := raw - _start_pos
		if absf(d2.y) <= SNAP_PX * w and absf(d2.x) > absf(d2.y):
			p.y = _start_pos.y
			_hint = "Yatay"
		elif absf(d2.x) <= SNAP_PX * w and absf(d2.y) > absf(d2.x):
			p.x = _start_pos.x
			_hint = "Dikey"
	if grid_snap:
		if _hint != "Yatay":
			p.y = snappedf(p.y, grid_step)
		if _hint != "Dikey":
			p.x = snappedf(p.x, grid_step)
	_cursor = p


func _snap_info() -> Dictionary:
	return {"kind": _snap_kind, "pid": _snap_pid, "eid": _snap_eid, "pos": _cursor}


## Yakalama bilgisinden nokta üretir; öğe/orta nokta yakalamasında ilgili ilişkiyi bekletir.
func _resolve_point(info: Dictionary, pending: Array) -> int:
	if int(info.get("pid", -1)) >= 0:
		return int(info["pid"])
	var pid := sketch().add_point(info.get("pos", Vector2.ZERO))
	match str(info.get("kind", "")):
		"entity":
			pending.append({"type": "coincident", "p1": pid, "e1": int(info["eid"])})
		"midpoint":
			pending.append({"type": "midpoint", "p1": pid, "e1": int(info["eid"])})
	return pid


func _on_motion(pos: Vector2) -> void:
	_mouse_screen = pos
	var l = _local_from_screen(pos)
	if l == null:
		return
	_has_cursor = true
	var sk := sketch()
	var w := _wpp()
	if tool == "select":
		if _drag_mode != "":
			_drag_motion(l, pos)
		else:
			_hover_point = sk.hit_point(l, PICK_PX * w)
			_hover_entity = -1 if _hover_point >= 0 else sk.hit_entity(l, PICK_PX * w)
			_cursor = l
	elif tool in ["dimension", "trim", "extend", "fillet", "chamfer", "convert"]:
		_cursor = l
		_hover_point = sk.hit_point(l, PICK_PX * w)
		_hover_entity = -1 if _hover_point >= 0 and tool != "trim" and tool != "extend" else sk.hit_entity(l, PICK_PX * w)
		if tool == "trim" or tool == "extend":
			_hover_point = -1
	else:
		_update_snap(l)
		if tool == "arc" and _stage == 2:
			var ang := (_cursor - _start_pos).angle()
			_arc_sweep = clampf(_arc_sweep + wrapf(ang - _arc_last_angle, -PI, PI), -TAU, TAU)
			_arc_last_angle = ang
	cursor_moved.emit(_cursor)
	viewport.show_cursor_text(_readout(), pos)
	redraw()


func _on_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if not mb.pressed:
			cancel()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var l = _local_from_screen(mb.position)
	if l == null:
		return
	if mb.pressed:
		_close_editor()
		_press_screen = mb.position
		match tool:
			"select":
				_select_press(l, mb)
			"dimension":
				_dimension_click(l, mb)
			"trim", "extend", "fillet", "chamfer", "convert":
				_modify_click(l)
			_:
				_update_snap(l)
				if mb.double_click and (tool == "line" or tool == "centerline"):
					_stage = 0
					_emit_hint()
					redraw()
					return
				if mb.double_click and tool == "spline":
					_finish_spline()
					return
				_tool_click()
		_emit_hint()
	else:
		if tool == "select" and _drag_mode != "":
			_drag_release()
	redraw()


# ================================================================ seçim ve sürükleme

func _hit_overlay(screen: Vector2) -> int:
	for it in _label_items:
		if (it["rect"] as Rect2).grow(3.0).has_point(screen):
			return int(it["cid"])
	if show_relations:
		for it in _badge_items:
			if (it["rect"] as Rect2).has_point(screen):
				return int(it["cid"])
	return -1


func _select_press(l: Vector2, mb: InputEventMouseButton) -> void:
	var sk := sketch()
	var w := _wpp()
	var additive := mb.shift_pressed or mb.ctrl_pressed
	var cid := _hit_overlay(mb.position)
	if cid >= 0:
		if additive:
			if selected_constraints.has(cid):
				selected_constraints.erase(cid)
			else:
				selected_constraints[cid] = true
			selection_changed.emit()
		else:
			select_constraint(cid)
		if mb.double_click and Sketch.is_dimension(sk.get_constraint(cid)):
			open_dimension_editor(cid)
		return
	var pid := sk.hit_point(l, PICK_PX * w)
	var eid := -1 if pid >= 0 else sk.hit_entity(l, PICK_PX * w)
	if not additive:
		selected_entities.clear()
		selected_points.clear()
		selected_constraints.clear()
	if pid >= 0:
		if additive and selected_points.has(pid):
			selected_points.erase(pid)
		else:
			selected_points[pid] = true
		if pid != Sketch.ORIGIN:
			_start_drag("point", pid, -1, l, mb.position)
	elif eid >= 0:
		if additive and selected_entities.has(eid):
			selected_entities.erase(eid)
		else:
			selected_entities[eid] = true
		_start_drag(str(sk.get_entity(eid)["type"]), -1, eid, l, mb.position)
	selection_changed.emit()


func _start_drag(mode: String, pid: int, eid: int, l: Vector2, screen: Vector2) -> void:
	_drag_mode = mode
	_drag_pid = pid
	_drag_eid = eid
	_drag_started = false
	_press_pos = screen
	_drag_start_local = l
	_drag_init.clear()
	var sk := sketch()
	if eid >= 0:
		for p in Sketch.entity_point_ids(sk.get_entity(eid)):
			_drag_init[p] = sk.points[p]


func _drag_motion(l: Vector2, screen: Vector2) -> void:
	if not _drag_started:
		if screen.distance_to(_press_pos) <= 3.0:
			return
		_drag_started = true
		_drag_before = _begin()
		_drag_good = _capture()
	var sk := sketch()
	var weights := {"points": {}, "radii": {}}
	match _drag_mode:
		"point":
			_update_snap(l, false)
			sk.points[_drag_pid] = _cursor
			weights["points"][_drag_pid] = 100000.0
		"line", "arc":
			var delta := l - _drag_start_local
			for p in _drag_init:
				if p == Sketch.ORIGIN:
					continue
				sk.points[p] = _drag_init[p] + delta
				weights["points"][p] = 100000.0
		"circle":
			var e := sk.get_entity(_drag_eid)
			e["r"] = maxf(l.distance_to(sk.points[e["c"]]), 1e-3)
			weights["radii"][_drag_eid] = 100000.0
	var s := SketchSolver.new(sk, weights)
	if s.solve(25)["ok"]:
		s.apply()
		_drag_good = _capture()
	else:
		_restore(_drag_good)


func _drag_release() -> void:
	if _drag_started:
		var sk := sketch()
		# Nokta başka bir noktanın üzerine bırakıldıysa birleştir (çakışık)
		if _drag_mode == "point" and _snap_kind == "point" and _snap_pid >= 0 and _snap_pid != _drag_pid:
			var ok_merge := true
			for e in sk.entities:
				var ids := Sketch.entity_point_ids(e)
				if _drag_pid in ids and _snap_pid in ids:
					ok_merge = false
			if ok_merge:
				var keep := _snap_pid
				sk.merge_points(keep, _drag_pid)
				selected_points.clear()
		_finish(_drag_before)
	_drag_mode = ""
	_drag_pid = -1
	_drag_eid = -1
	_drag_started = false


# ================================================================ düzenleme araçları (kırp, uzat, yuvarlat, pah)

func _modify_click(l: Vector2) -> void:
	var sk := sketch()
	var w := _wpp()
	match tool:
		"convert":
			var r := viewport.ray(_press_screen)
			var hit := viewport.model.raycast(r[0], r[1])
			if hit.is_empty():
				status.emit(I18n.t("Model yüzüne tıklayın (taslak düzleminden görünen bir yüz)."))
				return
			var fd := viewport.model.planar_face(int(hit["tri"]))
			if viewport.model.has_brep() and int(fd.get("face", -1)) >= 0:
				# B-rep: yüzün gerçek kenarları (çizgi, daire, yay, elips, spline)
				var fe: Array = []
				for id in (fd["info"] as Dictionary).get("e", []):
					fe.append(viewport.model.brep_edges[int(id)])
				var pl := plane()
				apply_op(func(): return SketchOps.convert_brep_edges(sketch(), pl, fe))
				return
			var loops2: Array = []
			for loop3 in viewport.model.region_boundary_loops(fd["tris"]):
				var l2 := PackedVector2Array()
				for q in loop3:
					l2.append(plane().to_local(q))
				loops2.append(l2)
			apply_op(func(): return SketchOps.convert_loops(sketch(), loops2))
		"trim", "extend":
			var eid := sk.hit_entity(l, PICK_PX * w)
			if eid < 0:
				status.emit(I18n.t("Bir öğeye tıklayın."))
				return
			if tool == "trim":
				apply_op(func(): return SketchOps.trim(sketch(), eid, l))
			else:
				apply_op(func(): return SketchOps.extend(sketch(), eid, l))
		"fillet", "chamfer":
			var pid := sk.hit_point(l, PICK_PX * 1.6 * w, [Sketch.ORIGIN])
			if pid < 0:
				# Çizgiye tıklandıysa yakın ucu köşe say
				var eid2 := sk.hit_entity(l, PICK_PX * w)
				var e := sk.get_entity(eid2)
				if not e.is_empty() and e["type"] == "line":
					pid = e["a"] if l.distance_to(sk.points[e["a"]]) < l.distance_to(sk.points[e["b"]]) else e["b"]
			if pid < 0:
				status.emit(I18n.t("Bir köşe noktasına tıklayın."))
				return
			var r: Dictionary
			if tool == "fillet":
				var rad := fillet_radius
				r = apply_op(func(): return SketchOps.fillet(sketch(), pid, rad))
			else:
				var dd := chamfer_dist
				r = apply_op(func(): return SketchOps.chamfer(sketch(), pid, dd))
			if r.get("ok", false) and r.has("dim"):
				selected_constraints = {r["dim"]: true}
				selection_changed.emit()
	redraw()


func _ellipse_minor() -> float:
	var u := (_p2 - _start_pos)
	if u.length() < 1e-9:
		return 0.0
	return absf(u.normalized().cross(_cursor - _start_pos))


## Noktayı parabole iz düşürür (dik eksen koordinatı korunur).
func _parabola_project(p: Vector2) -> Vector2:
	var d := _p2 - _start_pos
	var fl := maxf(d.length(), 1e-9)
	var fr := {"v": _start_pos, "u": d / fl, "w": Vector2(-d.y, d.x) / fl, "fl": fl}
	return Sketch.parabola_point(fr, (p - _start_pos).dot(fr["w"]))


## Seçimden blok oluşturur.
func make_block_selection() -> Dictionary:
	var ids := _sel_entity_ids()
	if ids.is_empty():
		var r0 := {"ok": false, "msg": I18n.t("Blok için önce öğeleri seçin.")}
		status.emit(r0["msg"])
		return r0
	var op := func() -> Dictionary:
		var bid := sketch().make_block(ids)
		return {"ok": bid >= 0, "msg": I18n.t("Blok oluşturuldu: öğeler artık tek parça (rijit) hareket eder.") if bid >= 0 else I18n.t("Seçili öğeler zaten bir blokta.")}
	return apply_op(op)


func explode_block(bid: int) -> void:
	var op := func() -> Dictionary:
		sketch().explode_block(bid)
		return {"ok": true, "msg": I18n.t("Blok dağıtıldı.")}
	apply_op(op)


func copy_block(bid: int, offset: Vector2) -> void:
	var bl: Dictionary = sketch().blocks.get(bid, {})
	if bl.is_empty():
		return
	var ents: Array = bl.get("entities", []).duplicate()
	var bname := str(bl["name"]) + "-kopya"
	var op := func() -> Dictionary:
		var sk := sketch()
		var xf := func(p: Vector2) -> Vector2: return p + offset
		var ids := SketchOps.copy_entities(sk, ents, xf)
		var nb := sk.make_block(ids, bname)
		return {"ok": nb >= 0, "msg": I18n.t("Blok kopyalandı.")}
	apply_op(op)


func _slot_half_width() -> float:
	var u := (_p2 - _start_pos)
	if u.length() < 1e-9:
		return 0.0
	return absf(u.normalized().cross(_cursor - _start_pos))


func _finish_spline() -> void:
	if _spline_pts.size() < 2:
		_spline_pts.clear()
		return
	var sk := sketch()
	var before := _begin()
	var pending: Array = []
	var ids: Array = []
	for info in _spline_pts:
		var pid: int
		if info.get("closing", false) and not ids.is_empty():
			pid = ids[0]
		else:
			pid = _resolve_point(info, pending)
		if ids.is_empty() or ids[ids.size() - 1] != pid:
			ids.append(pid)
	_spline_pts.clear()
	if ids.size() < 2:
		feature.sketch = Sketch.from_dict(before)
		doc.drop_checkpoint()
		return
	var eid := sk.add_spline(ids)
	for c in pending:
		sk.add_constraint(c)
	if _finish(before):
		select_entity(eid)
		status.emit(I18n.t("Spline oluşturuldu (%d nokta). Noktaları sürükleyerek şeklini değiştirebilirsiniz.") % ids.size())
	_emit_hint()


# ================================================================ çizim araçları

func _tool_click() -> void:
	var sk := sketch()
	match tool:
		"ellipse":
			if _stage == 0:
				_start_snap = _snap_info()
				_start_pos = _cursor
				_start_pid = _snap_pid
				_stage = 1
				return
			if _stage == 1:
				if _cursor.distance_to(_start_pos) < 1e-6:
					return
				_p2 = _cursor
				_p2_snap = _snap_info()
				_stage = 2
				return
			var rb := _ellipse_minor()
			if rb < 1e-6:
				return
			_stage = 0
			var be := _begin()
			var pend: Array = []
			var cpid := _resolve_point(_start_snap, pend)
			var mpid := _resolve_point(_p2_snap, pend)
			if cpid == mpid:
				feature.sketch = Sketch.from_dict(be)
				doc.drop_checkpoint()
				return
			var eid := sk.add_ellipse(cpid, mpid, rb)
			for c in pend:
				sk.add_constraint(c)
			if _finish(be):
				select_entity(eid)
		"parabola":
			if _stage == 0:
				_start_snap = _snap_info()
				_start_pos = _cursor
				_start_pid = _snap_pid
				_stage = 1
				return
			if _stage == 1:
				if _cursor.distance_to(_start_pos) < 1e-6:
					return
				_p2 = _cursor
				_p2_snap = _snap_info()
				_stage = 2
				return
			if _stage == 2:
				_p3 = _parabola_project(_cursor)
				_stage = 3
				return
			var pend2: Array = []
			var a_pos := _p3
			var b_pos := _parabola_project(_cursor)
			if a_pos.distance_to(b_pos) < 1e-6:
				return
			_stage = 0
			var bp := _begin()
			var vpid := _resolve_point(_start_snap, pend2)
			var fpid := _resolve_point(_p2_snap, pend2)
			var apid := sk.add_point(a_pos)
			var bpid := sk.add_point(b_pos)
			var pid := sk.add_parabola(vpid, fpid, apid, bpid)
			for c in pend2:
				sk.add_constraint(c)
			if _finish(bp):
				select_entity(pid)
		"polygon":
			if _stage == 0:
				_start_snap = _snap_info()
				_start_pos = _cursor
				_start_pid = _snap_pid
				_stage = 1
				return
			if _cursor.distance_to(_start_pos) < 1e-6:
				return
			var vtx := _cursor
			var n := polygon_sides
			var csnap := _start_snap
			_stage = 0
			var before_p := _begin()
			var pend: Array = []
			var cpid := _resolve_point(csnap, pend)
			for c in pend:
				sk.add_constraint(c)
			var rp := SketchOps.add_polygon(sk, cpid, vtx, n)
			if rp["ok"] and _finish(before_p):
				status.emit(rp["msg"])
		"slot":
			if _stage == 0:
				_start_snap = _snap_info()
				_start_pos = _cursor
				_start_pid = _snap_pid
				_stage = 1
				return
			if _stage == 1:
				if _cursor.distance_to(_start_pos) < 1e-6:
					return
				_p2 = _cursor
				_p2_snap = _snap_info()
				_stage = 2
				return
			var hw := _slot_half_width()
			if hw < 1e-6:
				return
			_stage = 0
			var before_s := _begin()
			var pend2: Array = []
			var c1 := _resolve_point(_start_snap, pend2)
			var c2 := _resolve_point(_p2_snap, pend2)
			for c in pend2:
				sk.add_constraint(c)
			var rs := SketchOps.add_slot(sk, c1, c2, hw)
			if rs["ok"] and _finish(before_s):
				status.emit(rs["msg"])
			elif not rs["ok"]:
				feature.sketch = Sketch.from_dict(before_s)
				doc.drop_checkpoint()
		"spline":
			var info := _snap_info()
			if _spline_pts.size() >= 2:
				var first: Dictionary = _spline_pts[0]
				if (first["pos"] as Vector2).distance_to(_cursor) <= SNAP_PX * _wpp():
					_spline_pts.append(first.merged({"closing": true}))
					_finish_spline()
					return
			if not _spline_pts.is_empty() and (_spline_pts[_spline_pts.size() - 1]["pos"] as Vector2).distance_to(info["pos"]) < 1e-6:
				return
			_spline_pts.append(info)
			_stage = 1
		"text":
			var before_t := _begin()
			var pend3: Array = []
			var tp := _resolve_point(_snap_info(), pend3)
			for c in pend3:
				sk.add_constraint(c)
			var tid := sk.add_text(tp, text_default, text_height)
			if _finish(before_t):
				select_entity(tid)
				status.emit(I18n.t("Metin eklendi. Yazıyı ve boyutunu soldaki panelden değiştirin."))
		"line", "centerline":
			if _stage == 0:
				_start_snap = _snap_info()
				_start_pid = _snap_pid
				_start_pos = _cursor
				_chain_first_pid = _snap_pid
				_stage = 1
				return
			if _cursor.distance_to(_start_pos) < 1e-6:
				return
			var hint := _hint
			var end_snap := _snap_info()
			var before := _begin()
			var pending: Array = []
			var a := _resolve_point(_start_snap, pending)
			if _chain_first_pid < 0:
				_chain_first_pid = a
			var closing: bool = end_snap["pid"] >= 0 and end_snap["pid"] == _chain_first_pid
			var b := _resolve_point(end_snap, pending)
			if a == b:
				doc.drop_checkpoint()
				feature.sketch = Sketch.from_dict(before)
				return
			var eid := sk.add_line(a, b, tool == "centerline")
			if hint == "Yatay":
				pending.append({"type": "horizontal", "e1": eid})
			elif hint == "Dikey":
				pending.append({"type": "vertical", "e1": eid})
			for c in pending:
				sk.add_constraint(c)
			_start_pid = b
			_start_pos = sk.points[b]
			_start_snap = {"kind": "point", "pid": b, "eid": -1, "pos": _start_pos}
			if closing:
				_stage = 0
			if not _finish(before):
				_stage = 0
		"rect", "crect":
			if _stage == 0:
				_start_snap = _snap_info()
				_start_pid = _snap_pid
				_start_pos = _cursor
				_stage = 1
				return
			var p1 := _start_pos
			var p2 := _cursor
			if tool == "crect":
				p1 = _start_pos * 2.0 - _cursor
			var mn := p1.min(p2)
			var mx := p1.max(p2)
			if mx.x - mn.x < 1e-6 or mx.y - mn.y < 1e-6:
				return
			var end_snap2 := _snap_info()
			var before2 := _begin()
			var pending2: Array = []
			var corners_pos := [Vector2(mn.x, mn.y), Vector2(mx.x, mn.y), Vector2(mx.x, mx.y), Vector2(mn.x, mx.y)]
			var ids: Array = []
			for cp in corners_pos:
				var id := -1
				if tool == "rect" and (cp as Vector2).distance_to(_start_pos) < 1e-6:
					id = _resolve_point(_start_snap, pending2)
				elif (cp as Vector2).distance_to(_cursor) < 1e-6:
					id = _resolve_point(end_snap2, pending2)
				if id < 0:
					id = sk.add_point(cp)
				ids.append(id)
			var gid := sk.add_rect(ids)
			if tool == "crect":
				# Merkez noktası: köşegenler yapı çizgisi, merkez onların orta noktası
				var center_snap := _start_snap.duplicate()
				var cpid := _resolve_point(center_snap, pending2)
				var d1 := sk.add_line(ids[0], ids[2], true)
				sk.add_line(ids[1], ids[3], true)
				pending2.append({"type": "midpoint", "p1": cpid, "e1": d1})
			for c in pending2:
				sk.add_constraint(c)
			_stage = 0
			if _finish(before2):
				for e in sketch().entities:
					if int(e.get("group", 0)) == gid:
						select_entity(e["id"])
						break
		"circle":
			if _stage == 0:
				_start_snap = _snap_info()
				_start_pid = _snap_pid
				_start_pos = _cursor
				_stage = 1
				return
			var r := _cursor.distance_to(_start_pos)
			if r < 1e-6:
				return
			var before3 := _begin()
			var pending3: Array = []
			var c3 := _resolve_point(_start_snap, pending3)
			var eid3 := sk.add_circle(c3, r)
			if _snap_kind == "point" and _snap_pid >= 0 and _snap_pid != c3:
				pending3.append({"type": "coincident", "p1": _snap_pid, "e1": eid3})
			for c in pending3:
				sk.add_constraint(c)
			_stage = 0
			if _finish(before3):
				select_entity(eid3)
		"arc":
			if _stage == 0:
				_start_snap = _snap_info()
				_start_pid = _snap_pid
				_start_pos = _cursor
				_stage = 1
				return
			if _stage == 1:
				if _cursor.distance_to(_start_pos) < 1e-6:
					return
				_p2 = _cursor
				_p2_snap = _snap_info()
				_arc_sweep = 0.0
				_arc_last_angle = (_p2 - _start_pos).angle()
				_stage = 2
				return
			if absf(_arc_sweep) < 1e-3:
				return
			var rad := _p2.distance_to(_start_pos)
			var end_info := _snap_info()
			if end_info["kind"] != "point":
				end_info = {"kind": "", "pid": -1, "eid": -1, "pos": _start_pos + (_cursor - _start_pos).normalized() * rad}
			var before4 := _begin()
			var pending4: Array = []
			var cid := _resolve_point(_start_snap, pending4)
			var aid := _resolve_point(_p2_snap, pending4)
			var bid := _resolve_point(end_info, pending4)
			if bid == aid or bid == cid or aid == cid:
				doc.drop_checkpoint()
				feature.sketch = Sketch.from_dict(before4)
				_stage = 0
				return
			var eid4: int
			if _arc_sweep >= 0.0:
				eid4 = sk.add_arc(cid, aid, bid)
			else:
				eid4 = sk.add_arc(cid, bid, aid)
			for c in pending4:
				sk.add_constraint(c)
			_stage = 0
			if _finish(before4):
				select_entity(eid4)


func _readout() -> String:
	if tool == "dimension" or tool == "select":
		return ""
	var snap_txt := ""
	match _snap_kind:
		"midpoint":
			snap_txt = I18n.t("   [Orta nokta]")
		"entity":
			snap_txt = I18n.t("   [Üzerinde]")
		"point":
			snap_txt = I18n.t("   [Çakışık]")
	if _stage == 0:
		return snap_txt.strip_edges()
	match tool:
		"line", "centerline":
			var d := _cursor - _start_pos
			var s := Units.format_length(d.length()) + "   " + Units.format_angle(fposmod(rad_to_deg(d.angle()), 360.0))
			if _hint != "":
				s += "   [" + _hint + "]"
			return s + snap_txt
		"rect":
			var d2 := (_cursor - _start_pos).abs()
			return Units.format_length(d2.x, false) + " x " + Units.format_length(d2.y)
		"crect":
			var d3 := (_cursor - _start_pos).abs() * 2.0
			return Units.format_length(d3.x, false) + " x " + Units.format_length(d3.y)
		"circle":
			return "Ø " + Units.format_length(_cursor.distance_to(_start_pos) * 2.0)
		"arc":
			if _stage == 1:
				return "R " + Units.format_length(_cursor.distance_to(_start_pos))
			return "R " + Units.format_length(_p2.distance_to(_start_pos)) + "   " + Units.format_angle(absf(rad_to_deg(_arc_sweep)))
		"polygon":
			return I18n.t("%d kenar   R %s") % [polygon_sides, Units.format_length(_cursor.distance_to(_start_pos))]
		"slot":
			if _stage == 1:
				return "L " + Units.format_length(_cursor.distance_to(_start_pos))
			return I18n.t("L %s   genişlik %s") % [Units.format_length(_p2.distance_to(_start_pos), false), Units.format_length(_slot_half_width() * 2.0)]
		"spline":
			return I18n.t("%d nokta%s") % [_spline_pts.size(), snap_txt]
		"ellipse":
			if _stage == 1:
				return "a " + Units.format_length(_cursor.distance_to(_start_pos))
			return "a %s   b %s" % [Units.format_length(_p2.distance_to(_start_pos), false), Units.format_length(_ellipse_minor())]
		"parabola":
			if _stage == 1:
				return "odak uzaklığı " + Units.format_length(_cursor.distance_to(_start_pos))
			return ""
	return ""


# ================================================================ Akıllı Boyut

func _dimension_click(l: Vector2, mb: InputEventMouseButton) -> void:
	var sk := sketch()
	var w := _wpp()
	var cid := _hit_overlay(mb.position)
	if cid >= 0 and _dim_sel.is_empty():
		if Sketch.is_dimension(sk.get_constraint(cid)):
			select_constraint(cid)
			open_dimension_editor(cid)
		return
	var pick := {}
	var pid := sk.hit_point(l, PICK_PX * w)
	if pid >= 0:
		pick = {"kind": "point", "id": pid}
	else:
		var eid := sk.hit_entity(l, PICK_PX * w)
		if eid >= 0:
			pick = {"kind": "entity", "id": eid}
	if not pick.is_empty():
		for q in _dim_sel:
			if q["kind"] == pick["kind"] and q["id"] == pick["id"]:
				return
		if _dim_sel.size() < 2:
			_dim_sel.append(pick)
			return
	if _dim_sel.is_empty():
		return
	var spec := dimension_spec(_dim_sel, l)
	_dim_sel.clear()
	if spec.is_empty():
		status.emit(I18n.t("Bu seçimden boyut oluşturulamadı."))
		return
	add_dimension(spec, l)


func _placed_distance(p1: int, p2: int, place: Vector2) -> Dictionary:
	if p1 == p2:
		return {}
	var sk := sketch()
	var A: Vector2 = sk.points[p1]
	var B: Vector2 = sk.points[p2]
	var mn := A.min(B)
	var mx := A.max(B)
	var eps := 1e-6
	if absf(B.x - A.x) < eps:
		return {"type": "vdistance", "p1": p1, "p2": p2}
	if absf(B.y - A.y) < eps:
		return {"type": "hdistance", "p1": p1, "p2": p2}
	var in_x := place.x > mn.x and place.x < mx.x
	var in_y := place.y > mn.y and place.y < mx.y
	if in_x and not in_y:
		return {"type": "hdistance", "p1": p1, "p2": p2}
	if in_y and not in_x:
		return {"type": "vdistance", "p1": p1, "p2": p2}
	return {"type": "distance", "p1": p1, "p2": p2}


## Seçime ve yerleşime göre boyut türünü belirler (akıllı boyut mantığı).
func dimension_spec(picks: Array, place: Vector2) -> Dictionary:
	var sk := sketch()
	var P: Array = []
	var Ls: Array = []
	var Rs: Array = []
	for q in picks:
		if q["kind"] == "point":
			P.append(int(q["id"]))
		else:
			var e := sk.get_entity(int(q["id"]))
			if e.is_empty():
				continue
			if e["type"] == "line":
				Ls.append(int(q["id"]))
			elif e["type"] in ["circle", "arc", "ellipse"]:
				Rs.append(int(q["id"]))
			else:
				return {}
	if Ls.size() == 1 and P.is_empty() and Rs.is_empty():
		var e1 := sk.get_entity(Ls[0])
		return _placed_distance(e1["a"], e1["b"], place)
	if Rs.size() == 1 and P.is_empty() and Ls.is_empty():
		var e2 := sk.get_entity(Rs[0])
		return {"type": "diameter" if e2["type"] == "circle" else "radius", "e1": Rs[0]}
	if P.size() == 2:
		return _placed_distance(P[0], P[1], place)
	if P.size() == 1 and Ls.size() == 1:
		var e3 := sk.get_entity(Ls[0])
		if P[0] == e3["a"] or P[0] == e3["b"]:
			return _placed_distance(e3["a"], e3["b"], place)
		return {"type": "pl_distance", "p1": P[0], "e1": Ls[0]}
	if Ls.size() == 2:
		var d1 := SketchSolver.line_dir(sk, Ls[0]).normalized()
		var d2 := SketchSolver.line_dir(sk, Ls[1]).normalized()
		if absf(d1.cross(d2)) < 1e-6:
			return {"type": "pl_distance", "p1": sk.get_entity(Ls[1])["a"], "e1": Ls[0]}
		return {"type": "angle", "e1": Ls[0], "e2": Ls[1]}
	if Rs.size() == 1 and P.size() == 1:
		return _placed_distance(sk.get_entity(Rs[0])["c"], P[0], place)
	if Rs.size() == 1 and Ls.size() == 1:
		return {"type": "pl_distance", "p1": sk.get_entity(Rs[0])["c"], "e1": Ls[0]}
	if Rs.size() == 2:
		return _placed_distance(sk.get_entity(Rs[0])["c"], sk.get_entity(Rs[1])["c"], place)
	return {}


func add_dimension(spec: Dictionary, label: Vector2, open_editor := true) -> int:
	var sk := sketch()
	var c := SketchSolver.make_dimension(sk, spec, label)
	doc.checkpoint()
	var cid := sk.add_constraint(c)
	var driven := not SketchSolver.is_independent(sk, cid)
	if driven:
		c["driven"] = true
	doc.commit()
	select_constraint(cid)
	if driven:
		status.emit(I18n.t("Bu boyut taslağı aşırı tanımlardı; güdümlü (referans) boyut olarak eklendi."))
	elif open_editor:
		open_dimension_editor(cid)
	return cid


func set_dimension_value(cid: int, v: float) -> bool:
	var c := sketch().get_constraint(cid)
	if c.is_empty():
		return false
	if c["type"] == "angle":
		v = clampf(v, 0.001, 179.999)
	else:
		v = maxf(v, 1e-4)
	var before := _begin()
	sketch().get_constraint(cid)["value"] = v
	sketch().get_constraint(cid).erase("expr")
	return _finish(before, {}, I18n.t("Bu değer geometrik olarak mümkün değil (diğer ilişki/boyutlarla çelişiyor); geri alındı."))


## Boyuta denklem bağlar (ör. "genislik / 2"). Boş ifade denklemi kaldırır.
func set_dimension_expr(cid: int, expr: String) -> bool:
	var c := sketch().get_constraint(cid)
	if c.is_empty():
		return false
	expr = expr.strip_edges().trim_prefix("=").strip_edges()
	if expr == "":
		var b0 := _begin()
		sketch().get_constraint(cid).erase("expr")
		return _finish(b0)
	var ctx: Dictionary = Equations.variable_values(doc)["ctx"]
	var r = Equations.evaluate(expr, ctx)
	if r == null:
		status.emit(I18n.t("Denklem hesaplanamadı: '%s' (tanımsız değişken veya hatalı ifade).") % expr)
		return false
	var v: float = r if c["type"] == "angle" else Units.from_display(r)
	var before := _begin()
	var cc := sketch().get_constraint(cid)
	cc["expr"] = expr
	cc["value"] = clampf(v, 0.001, 179.999) if c["type"] == "angle" else maxf(v, 1e-4)
	var ok := _finish(before, {}, I18n.t("Denklemin sonucu geometriyle çelişiyor; geri alındı."))
	if ok:
		status.emit(I18n.t("Denklem bağlandı: %s = %s") % [Equations.full_name(cc, feature.name), expr])
	return ok


func set_dimension_driven(cid: int, driven: bool) -> bool:
	var before := _begin()
	var c := sketch().get_constraint(cid)
	c["driven"] = driven
	if not driven:
		c["value"] = SketchSolver.measure(sketch(), c)
		return _finish(before, {}, "", [cid])
	return _finish(before)


func open_dimension_editor(cid: int) -> void:
	_close_editor()
	var c := sketch().get_constraint(cid)
	if c.is_empty() or bool(c.get("driven", false)):
		return
	var f := NumField.new("angle" if c["type"] == "angle" else "length", float(c["value"]))
	f.custom_minimum_size = Vector2(120, 30)
	f.allow_expr = true
	f.tooltip_text = "Değeri yazıp Enter'a basın. '=' ile denklem: =genislik/2  (Esc: vazgeç)"
	viewport.dim_layer.add_child(f)
	if str(c.get("expr", "")) != "":
		f.text = "=" + str(c["expr"])
	f.expr_committed.connect(func(ex): set_dimension_expr(cid, ex))
	var at := viewport.world_to_screen(plane().to_world(SketchSolver.dimension_anchor(sketch(), c) + _dim_off(c)))
	for it in _label_items:
		if it["cid"] == cid:
			at = (it["rect"] as Rect2).get_center()
	f.position = at - Vector2(60, 15)
	f.value_committed.connect(func(v): set_dimension_value(cid, v))
	f.focus_exited.connect(_close_editor, CONNECT_DEFERRED)
	f.gui_input.connect(_on_editor_input)
	_edit_field = f
	f.grab_focus()
	f.select_all()


func _on_editor_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k and k.pressed and k.keycode == KEY_ESCAPE and _edit_field:
		_edit_field.refresh()
		_edit_field.release_focus()


func _close_editor() -> void:
	if _edit_field and is_instance_valid(_edit_field):
		var f := _edit_field
		_edit_field = null
		if f.focus_exited.is_connected(_close_editor):
			f.focus_exited.disconnect(_close_editor)
		f.queue_free()
	_edit_field = null


func is_editing_dimension() -> bool:
	return _edit_field != null and is_instance_valid(_edit_field)


# ================================================================ ilişkiler

func _selection_kinds() -> Dictionary:
	var sk := sketch()
	var L: Array = []
	var R: Array = []
	var P: Array = []
	var O: Array = []
	for eid in selected_entities:
		var e := sk.get_entity(eid)
		if e.is_empty():
			continue
		if e["type"] == "line":
			L.append(eid)
		elif e["type"] == "circle" or e["type"] == "arc":
			R.append(eid)
		else:
			O.append(eid)
	for pid in selected_points:
		P.append(pid)
	return {"L": L, "R": R, "P": P, "O": O}


## Seçime uygulanabilecek ilişkiler: [[tür, etiket], ...]
func available_relations() -> Array:
	var k := _selection_kinds()
	var L: Array = k["L"]
	var R: Array = k["R"]
	var P: Array = k["P"]
	var out: Array = []
	var nl := L.size()
	var nr := R.size()
	var np := P.size()
	if not (k["O"] as Array).is_empty():
		# Spline / metin: yalnızca sabitleme
		return [["fix", RELATION_NAMES["fix"]]] if nl + nr + np == 0 else []
	if nl >= 1 and nr == 0 and np == 0:
		out.append("horizontal")
		out.append("vertical")
		if nl >= 2:
			out.append_array(["parallel", "perpendicular", "equal", "collinear"] if nl == 2 else ["parallel", "equal"])
		out.append("fix")
	elif nl == 1 and nr == 1 and np == 0:
		out.append("tangent")
	elif nr >= 1 and nl == 0 and np == 0:
		if nr == 2:
			out.append_array(["concentric", "equal", "tangent"])
		elif nr > 2:
			out.append("equal")
		out.append("fix")
	elif np == 2 and nl == 0 and nr == 0:
		out.append_array(["horizontal", "vertical", "merge"])
	elif np == 1 and nl == 1 and nr == 0:
		out.append_array(["coincident", "midpoint"])
	elif np == 1 and nr == 1 and nl == 0:
		out.append("coincident")
	elif np == 2 and nl == 1 and nr == 0:
		out.append("symmetric")
	elif np >= 1 and nl == 0 and nr == 0:
		out.append("fix")
	var labeled: Array = []
	for t in out:
		labeled.append([t, RELATION_NAMES.get(t, t)])
	return labeled


func _relation_specs(t: String) -> Array:
	var sk := sketch()
	var k := _selection_kinds()
	var L: Array = k["L"]
	var R: Array = k["R"]
	var P: Array = k["P"]
	var out: Array = []
	match t:
		"horizontal", "vertical":
			if P.size() == 2:
				out.append({"type": t, "p1": P[0], "p2": P[1]})
			else:
				for eid in L:
					out.append({"type": t, "e1": eid})
		"parallel", "equal":
			var ents: Array = L if not L.is_empty() else R
			for i in range(1, ents.size()):
				out.append({"type": t, "e1": ents[0], "e2": ents[i]})
		"perpendicular", "collinear":
			out.append({"type": t, "e1": L[0], "e2": L[1]})
		"concentric":
			out.append({"type": t, "e1": R[0], "e2": R[1]})
		"tangent":
			if L.size() == 1:
				out.append({"type": t, "e1": L[0], "e2": R[0]})
			else:
				var e1 := sk.get_entity(R[0])
				var e2 := sk.get_entity(R[1])
				var d := (sk.points[e1["c"]] as Vector2).distance_to(sk.points[e2["c"]])
				var r1 := sk.entity_radius(e1)
				var r2 := sk.entity_radius(e2)
				out.append({"type": t, "e1": R[0], "e2": R[1], "internal": d < maxf(r1, r2)})
		"merge":
			var keep: int = P[0]
			var drop: int = P[1]
			if drop == Sketch.ORIGIN or (analysis.get("points", {}).get(drop, false) and not analysis.get("points", {}).get(keep, false)):
				keep = P[1]
				drop = P[0]
			for e in sk.entities:
				var ids := Sketch.entity_point_ids(e)
				if keep in ids and drop in ids:
					return []
			out.append({"merge": [keep, drop]})
		"coincident", "midpoint":
			var target: int = L[0] if not L.is_empty() else R[0]
			var te := sk.get_entity(target)
			if P[0] in Sketch.entity_point_ids(te):
				return []
			out.append({"type": t, "p1": P[0], "e1": target})
		"symmetric":
			out.append({"type": t, "p1": P[0], "p2": P[1], "e1": L[0]})
		"fix":
			for pid in P:
				if pid != Sketch.ORIGIN:
					out.append({"type": "fix", "p1": pid})
			for eid in L + R + (k["O"] as Array):
				out.append({"type": "fix", "e1": eid})
	return out


func add_relation(t: String) -> bool:
	var specs := _relation_specs(t)
	if specs.is_empty():
		status.emit(I18n.t("Bu ilişki seçili öğelere uygulanamaz."))
		return false
	var sk := sketch()
	var before := _begin()
	var new_ids: Array = []
	for sp in specs:
		if sp.has("merge"):
			sk.merge_points(sp["merge"][0], sp["merge"][1])
			selected_points.clear()
			continue
		if t == "midpoint":
			for c in sk.constraints.duplicate():
				if c["type"] == "coincident" and c.get("p1", -1) == sp["p1"] and c.get("e1", -1) == sp["e1"]:
					sk.remove_constraint(c["id"])
		new_ids.append(sk.add_constraint(sp))
	if _finish(before, {}, I18n.t("Bu ilişki mevcut geometriyle çelişiyor; eklenmedi."), new_ids):
		status.emit(I18n.t("İlişki eklendi: ") + I18n.t(str(RELATION_NAMES.get(t, t))))
		return true
	return false


func delete_constraint(cid: int) -> void:
	var before := _begin()
	sketch().remove_constraint(cid)
	selected_constraints.erase(cid)
	_finish(before)
	selection_changed.emit()


static func constraint_label(sk: Sketch, c: Dictionary) -> String:
	var t: String = c["type"]
	if Sketch.is_dimension(c):
		var txt := I18n.t(str(DIM_NAMES.get(t, t))) + ": " + dimension_text(c)
		if bool(c.get("driven", false)):
			txt += I18n.t(" (güdümlü)")
		return txt
	return I18n.t(str(RELATION_NAMES.get(t, t)))


static func dimension_text(c: Dictionary) -> String:
	var v := float(c.get("value", 0.0))
	var s := ""
	match str(c["type"]):
		"angle":
			s = Units.format_angle(v)
		"diameter":
			s = "Ø" + Units.fmt(Units.to_display(v))
		"radius":
			s = "R" + Units.fmt(Units.to_display(v))
		_:
			s = Units.fmt(Units.to_display(v))
	if bool(c.get("driven", false)):
		s = "(" + s + ")"
	if str(c.get("expr", "")) != "":
		s = "Σ" + s
	return s


# ================================================================ düzenleme işlemleri (panel)

func delete_selection() -> bool:
	if not has_selection():
		return false
	var sk := sketch()
	var before := _begin()
	for cid in selected_constraints:
		sk.remove_constraint(cid)
	for eid in selected_entities:
		sk.remove_entity(eid)
	for pid in selected_points:
		if sk.points.has(pid):
			sk.remove_point(pid)
	selected_entities.clear()
	selected_points.clear()
	selected_constraints.clear()
	var ok := _finish(before)
	selection_changed.emit()
	return ok


func _weights_for(pids: Array, eids_r: Array = []) -> Dictionary:
	var wp := {}
	for p in pids:
		wp[p] = 100000.0
	var wr := {}
	for e in eids_r:
		wr[e] = 100000.0
	return {"points": wp, "radii": wr}


func _check_reached(ok: bool, reached: bool) -> void:
	if ok and not reached:
		status.emit(I18n.t("Değer, mevcut ilişki/boyutlar nedeniyle tam uygulanamadı. Değiştirmek için ilgili boyutu düzenleyin."))


func edit_point(pid: int, p: Vector2) -> void:
	var before := _begin()
	sketch().points[pid] = p
	var ok := _finish(before, _weights_for([pid]))
	_check_reached(ok, (sketch().points.get(pid, p) as Vector2).distance_to(p) < 1e-4)


## Dairenin/yayın sürükleyici yarıçap/çap boyutu varsa onu döndürür.
func _radius_dimension(eid: int) -> Dictionary:
	for c in sketch().constraints:
		if (c["type"] == "radius" or c["type"] == "diameter") and c.get("e1", -1) == eid and not c.get("driven", false):
			return c
	return {}


func edit_line(eid: int, length: float, angle_deg: float) -> void:
	var sk := sketch()
	var e := sk.get_entity(eid)
	var a: Vector2 = sk.points[e["a"]]
	var target := a + Vector2.from_angle(deg_to_rad(angle_deg)) * maxf(length, 1e-4)
	for c in sk.constraints:
		if c["type"] == "distance" and not c.get("driven", false) and \
				((c["p1"] == e["a"] and c["p2"] == e["b"]) or (c["p1"] == e["b"] and c["p2"] == e["a"])) and \
				absf(fposmod(rad_to_deg((sk.points[e["b"]] - a).angle()), 360.0) - fposmod(angle_deg, 360.0)) < 1e-6:
			set_dimension_value(c["id"], length)
			return
	var before := _begin()
	sk.points[e["b"]] = target
	var ok := _finish(before, _weights_for([e["b"]]))
	_check_reached(ok, (sketch().points[sketch().get_entity(eid)["b"]] as Vector2).distance_to(target) < 1e-4)


func edit_circle(eid: int, center: Vector2, diameter: float) -> void:
	var sk := sketch()
	var e := sk.get_entity(eid)
	var dim := _radius_dimension(eid)
	if not dim.is_empty() and (sk.points[e["c"]] as Vector2).distance_to(center) < 1e-9:
		set_dimension_value(dim["id"], diameter if dim["type"] == "diameter" else diameter * 0.5)
		return
	var before := _begin()
	sk.points[e["c"]] = center
	e["r"] = maxf(diameter * 0.5, 1e-4)
	var ok := _finish(before, _weights_for([e["c"]], [eid]))
	var e2 := sketch().get_entity(eid)
	_check_reached(ok, absf(float(e2["r"]) * 2.0 - diameter) < 1e-4 and (sketch().points[e2["c"]] as Vector2).distance_to(center) < 1e-4)


func edit_arc(eid: int, center: Vector2, radius: float, start_deg: float, end_deg: float) -> void:
	var sk := sketch()
	var e := sk.get_entity(eid)
	radius = maxf(radius, 1e-4)
	var dim := _radius_dimension(eid)
	var d0 := sk.arc_data(e)
	if not dim.is_empty() and (d0["c"] as Vector2).distance_to(center) < 1e-9 and absf(float(d0["r"]) - radius) > 1e-9:
		set_dimension_value(dim["id"], radius if dim["type"] == "radius" else radius * 2.0)
		return
	var before := _begin()
	sk.points[e["c"]] = center
	sk.points[e["a"]] = center + Vector2.from_angle(deg_to_rad(start_deg)) * radius
	sk.points[e["b"]] = center + Vector2.from_angle(deg_to_rad(end_deg)) * radius
	var ok := _finish(before, _weights_for([e["c"], e["a"], e["b"]]))
	_check_reached(ok, absf(sketch().entity_radius(sketch().get_entity(eid)) - radius) < 1e-4)


func edit_ellipse(eid: int, center: Vector2, a: float, b: float, angle_deg: float) -> void:
	var sk := sketch()
	var e := sk.get_entity(eid)
	var before := _begin()
	sk.points[e["c"]] = center
	sk.points[e["m"]] = center + Vector2.from_angle(deg_to_rad(angle_deg)) * maxf(a, 1e-4)
	e["rb"] = maxf(b, 1e-4)
	var ok := _finish(before, _weights_for([e["c"], e["m"]], [eid]))
	var ax := sketch().ellipse_axes(sketch().get_entity(eid))
	_check_reached(ok, absf(float(ax["a"]) - a) < 1e-4 and absf(float(ax["b"]) - b) < 1e-4)


func edit_rect(gid: int, pos: Vector2, size: Vector2) -> void:
	var sk := sketch()
	var pts: Array = sk.groups[gid]["pts"]
	var before := _begin()
	sk.set_rect(gid, pos, Vector2(maxf(size.x, 1e-4), maxf(size.y, 1e-4)))
	var ok := _finish(before, _weights_for(pts))
	if ok and sketch().groups.has(gid):
		var ri := sketch().rect_info(gid)
		_check_reached(true, (ri["pos"] as Vector2).distance_to(pos) < 1e-4 and (ri["size"] as Vector2).distance_to(size) < 1e-4)


func edit_construction(eids: Array, v: bool) -> void:
	var sk := sketch()
	var before := _begin()
	for eid in eids:
		var e := sk.get_entity(eid)
		if not e.is_empty():
			e["construction"] = v
	_finish(before)


# ================================================================ çizim

func _compute_grid_step() -> float:
	var raw := _wpp() * 13.0
	var e := pow(10.0, floor(log(raw) / log(10.0)))
	for m in [1.0, 2.0, 5.0, 10.0]:
		if m * e >= raw:
			return maxf(m * e, 0.001)
	return 10.0 * e


## hw > 0 ise çizgiler o yarı kalınlıkta dolu şerit olarak çizilir.
## colors: {eid: Color} öğe bazlı renk (tanım durumu).
static func draw_sketch(lb: LineBuilder, f: CadFeature, w: float, col: Color, constr_col: Color,
		selected := {}, hover := -1, sel_col := COL_SELECTED, hover_col := COL_HOVER, hw := 0.0, colors := {}) -> void:
	var sk := f.sketch
	var p := f.plane
	var n := p.normal()
	for e in sk.entities:
		var construction: bool = e.get("construction", false)
		var c: Color = colors.get(e["id"], col)
		if construction:
			c = c.lerp(constr_col, 0.5) if colors.has(e["id"]) else constr_col
		var k := 1.0
		if selected.has(e["id"]):
			c = sel_col
			k = 1.6
		elif e["id"] == hover:
			c = hover_col
			k = 1.6
		for pts2 in sk.entity_polylines(e):
			var pts3 := PackedVector3Array()
			for q in pts2:
				pts3.append(p.to_world(q))
			if construction:
				lb.dashed_polyline(pts3, c, 9.0 * w, 5.0 * w)
			elif hw > 0.0 and e["type"] != "text":
				lb.thick_polyline(pts3, c, hw * k, n)
			else:
				lb.polyline(pts3, c)


func _status_color(full: bool) -> Color:
	if analysis.get("status", "") == "over":
		return COL_OVER
	return COL_FULL if full else COL_UNDER


func redraw() -> void:
	if not active or feature == null:
		return
	var lb := LineBuilder.new()
	var gb := LineBuilder.new()
	var p := plane()
	var sk := sketch()
	var w := _wpp()
	grid_step = _compute_grid_step()
	_draw_grid(gb, p)
	# Taslak orijini
	var o := p.to_world(Vector2.ZERO)
	var oc := COL_SELECTED if selected_points.has(Sketch.ORIGIN) else COL_ORIGIN
	lb.line(o, p.to_world(Vector2(26.0 * w, 0)), oc)
	lb.line(o, p.to_world(Vector2(0, 26.0 * w)), oc)
	lb.line(p.to_world(Vector2(26.0 * w, 0)), p.to_world(Vector2(20.0 * w, 3.0 * w)), oc)
	lb.line(p.to_world(Vector2(0, 26.0 * w)), p.to_world(Vector2(3.0 * w, 20.0 * w)), oc)
	# Öğeler (tanım durumuna göre renk)
	var ent_full: Dictionary = analysis.get("entities", {})
	var pt_full: Dictionary = analysis.get("points", {})
	var colors := {}
	for e in sk.entities:
		colors[e["id"]] = _status_color(ent_full.get(e["id"], false))
	var dim_hover := -1
	if tool == "select" or tool == "dimension":
		dim_hover = _hover_entity
	var dsel := selected_entities.duplicate()
	for q in _dim_sel:
		if q["kind"] == "entity":
			dsel[q["id"]] = true
	draw_sketch(lb, feature, w, COL_UNDER, Color(0.45, 0.5, 0.7), dsel, dim_hover, COL_SELECTED, COL_HOVER, 0.85 * w, colors)
	# Noktalar
	for pid in sk.points:
		if pid == Sketch.ORIGIN:
			continue
		var s := 2.5 * w
		var c := _status_color(pt_full.get(pid, false))
		var picked := selected_points.has(pid)
		for q in _dim_sel:
			if q["kind"] == "point" and q["id"] == pid:
				picked = true
		if picked:
			c = COL_SELECTED
			s = 3.5 * w
		elif pid == _hover_point and tool in ["select", "dimension", "fillet", "chamfer"]:
			c = COL_HOVER
			s = 3.5 * w
		if sk.virtual_points.has(pid):
			# Sanal köşe: küçük çarpı işareti
			var wp := p.to_world(sk.points[pid])
			var v := 4.0 * w
			lb.line(wp - (p.x_dir + p.y_dir) * v, wp + (p.x_dir + p.y_dir) * v, c)
			lb.line(wp - (p.x_dir - p.y_dir) * v, wp + (p.x_dir - p.y_dir) * v, c)
			continue
		lb.quad(p.to_world(sk.points[pid]), p.x_dir * s, p.y_dir * s, c)
	# Bloklar: kesikli çerçeve
	for bid in sk.blocks:
		var bl: Dictionary = sk.blocks[bid]
		var br := Rect2()
		var first := true
		for eid in bl.get("entities", []):
			var e := sk.get_entity(eid)
			if e.is_empty():
				continue
			var er := sk.entity_bounds(e)
			br = er if first else br.merge(er)
			first = false
		if first:
			continue
		br = br.grow(4.0 * w)
		var bc := Color(0.15, 0.6, 0.3)
		lb.dashed_polyline(PackedVector3Array([p.to_world(br.position), p.to_world(Vector2(br.end.x, br.position.y)),
			p.to_world(br.end), p.to_world(Vector2(br.position.x, br.end.y)), p.to_world(br.position)]), bc, 6.0 * w, 3.0 * w)
	# İşlem önizlemesi (ör. ofset)
	for path in preview_paths:
		var pp := PackedVector3Array()
		for q in path:
			pp.append(p.to_world(q))
		lb.dashed_polyline(pp, COL_SNAP, 7.0 * w, 4.0 * w)
	# Boyutlar
	_label_items.clear()
	var li := 0
	for c in sk.constraints:
		if Sketch.is_dimension(c):
			_draw_dimension(lb, c, selected_constraints.has(c["id"]), false)
			li = _place_label(li, c, selected_constraints.has(c["id"]))
	# Akıllı Boyut önizlemesi
	if tool == "dimension" and not _dim_sel.is_empty() and _has_cursor:
		var spec := dimension_spec(_dim_sel, _cursor)
		if not spec.is_empty():
			var pc := SketchSolver.make_dimension(sk, spec, _cursor)
			pc["id"] = -1
			_draw_dimension(lb, pc, false, true)
			li = _place_label(li, pc, false, true)
	for k in range(li, _labels.size()):
		_labels[k].visible = false
	_place_badges()
	# Çizim önizlemesi
	if not (tool in ["select", "dimension", "trim", "extend", "fillet", "chamfer", "convert"]) and _has_cursor:
		_draw_preview(lb, p, w)
		if _snap_kind == "point" or _snap_kind == "midpoint" or _snap_kind == "entity":
			var cw := p.to_world(_cursor)
			var s2 := 6.0 * w
			var sc := COL_SNAP
			lb.polyline(PackedVector3Array([
				cw - p.x_dir * s2 - p.y_dir * s2, cw + p.x_dir * s2 - p.y_dir * s2,
				cw + p.x_dir * s2 + p.y_dir * s2, cw - p.x_dir * s2 + p.y_dir * s2]), sc, true)
			if _snap_kind == "midpoint":
				lb.line(cw - p.y_dir * s2 * 1.6, cw + p.y_dir * s2 * 1.6, sc)
		else:
			var cw2 := p.to_world(_cursor)
			lb.line(cw2 - p.x_dir * 5.0 * w, cw2 + p.x_dir * 5.0 * w, COL_PREVIEW)
			lb.line(cw2 - p.y_dir * 5.0 * w, cw2 + p.y_dir * 5.0 * w, COL_PREVIEW)
	lb.commit(viewport.edit_mi.mesh)
	gb.commit(viewport.grid_mi.mesh)


func _dim_off(c: Dictionary) -> Vector2:
	var o = c.get("off", null)
	if o is Vector2:
		return o
	return Vector2(0, 12.0 * _wpp())


## Boyutun çizim geometrisi (taslak koordinatları).
func dim_geometry(c: Dictionary) -> Dictionary:
	var sk := sketch()
	var w := _wpp()
	var segs: Array = []
	var arrows: Array = []
	var arc := PackedVector2Array()
	var anchor := SketchSolver.dimension_anchor(sk, c)
	var L := anchor + _dim_off(c)
	var label := L
	var ext := 4.0 * w
	match str(c["type"]):
		"distance":
			var A: Vector2 = sk.points[int(c["p1"])]
			var B: Vector2 = sk.points[int(c["p2"])]
			var u := (B - A).normalized() if A.distance_to(B) > 1e-9 else Vector2.RIGHT
			var n := Vector2(-u.y, u.x)
			var h := (L - A).dot(n)
			var sgn := signf(h) if absf(h) > 1e-9 else 1.0
			var D1 := A + n * h
			var D2 := B + n * h
			segs.append([A + n * sgn * 2.0 * w, D1 + n * sgn * ext])
			segs.append([B + n * sgn * 2.0 * w, D2 + n * sgn * ext])
			segs.append([D1, D2])
			arrows.append([D1, -u])
			arrows.append([D2, u])
			label = D1 + u * (L - D1).dot(u)
		"hdistance", "vdistance":
			var A2: Vector2 = sk.points[int(c["p1"])]
			var B2: Vector2 = sk.points[int(c["p2"])]
			var D3: Vector2
			var D4: Vector2
			if c["type"] == "hdistance":
				D3 = Vector2(A2.x, L.y)
				D4 = Vector2(B2.x, L.y)
				label = Vector2(L.x, L.y)
			else:
				D3 = Vector2(L.x, A2.y)
				D4 = Vector2(L.x, B2.y)
				label = Vector2(L.x, L.y)
			var e1 := (D3 - A2)
			var e2 := (D4 - B2)
			segs.append([A2 + e1.normalized() * 2.0 * w, D3 + e1.normalized() * ext])
			segs.append([B2 + e2.normalized() * 2.0 * w, D4 + e2.normalized() * ext])
			segs.append([D3, D4])
			var dd := (D4 - D3).normalized() if D3.distance_to(D4) > 1e-9 else Vector2.RIGHT
			arrows.append([D3, -dd])
			arrows.append([D4, dd])
		"pl_distance":
			var P: Vector2 = sk.points[int(c["p1"])]
			var le := sk.get_entity(int(c["e1"]))
			var a: Vector2 = sk.points[le["a"]]
			var b: Vector2 = sk.points[le["b"]]
			var u2 := (b - a).normalized()
			var foot := a + u2 * (P - a).dot(u2)
			segs.append([P, foot])
			if P.distance_to(foot) > 1e-9:
				arrows.append([P, (P - foot).normalized()])
				arrows.append([foot, (foot - P).normalized()])
			var t := (foot - a).dot(u2)
			if t < 0.0 or t > a.distance_to(b):
				segs.append([a if t < 0.0 else b, foot])
		"radius", "diameter":
			var ce := sk.get_entity(int(c["e1"]))
			var C: Vector2 = sk.points[ce["c"]]
			var r := sk.entity_radius(ce)
			var dir := (L - C).normalized() if L.distance_to(C) > 1e-9 else Vector2.RIGHT
			var E := C + dir * r
			if c["type"] == "radius":
				segs.append([C, E])
				arrows.append([E, dir])
			else:
				segs.append([C - dir * r, E])
				arrows.append([E, dir])
				arrows.append([C - dir * r, -dir])
			if L.distance_to(C) > r:
				segs.append([E, L])
		"angle":
			var I := anchor
			var uu := SketchSolver.line_dir(sk, int(c["e1"])).normalized() * float(c.get("su", 1.0))
			var vv := SketchSolver.line_dir(sk, int(c["e2"])).normalized() * float(c.get("sv", 1.0))
			var R := maxf(L.distance_to(I), 12.0 * w)
			var a0 := uu.angle()
			var th := atan2(uu.cross(vv), uu.dot(vv))
			var nseg := maxi(6, int(absf(th) / PI * 48.0))
			for i in nseg + 1:
				arc.append(I + Vector2.from_angle(a0 + th * float(i) / float(nseg)) * R)
			var sg := signf(th) if th != 0.0 else 1.0
			arrows.append([arc[0], Vector2.from_angle(a0 - sg * PI * 0.5)])
			arrows.append([arc[arc.size() - 1], Vector2.from_angle(a0 + th + sg * PI * 0.5)])
			# Kısa çizgiler yayın uçlarına kadar uzatılır
			for pair in [[int(c["e1"]), uu], [int(c["e2"]), vv]]:
				var le2 := sk.get_entity(pair[0])
				var far: Vector2 = sk.points[le2["a"]] if (sk.points[le2["a"]] as Vector2).distance_to(I) > (sk.points[le2["b"]] as Vector2).distance_to(I) else sk.points[le2["b"]]
				if far.distance_to(I) < R:
					segs.append([far, I + (pair[1] as Vector2) * (R + ext)])
	return {"segs": segs, "arrows": arrows, "arc": arc, "label": label}


func _draw_dimension(lb: LineBuilder, c: Dictionary, selected: bool, preview: bool) -> void:
	var p := plane()
	var w := _wpp()
	var g := dim_geometry(c)
	var col := COL_DIM_DRIVEN if bool(c.get("driven", false)) else COL_DIM
	if preview:
		col = COL_PREVIEW
	if selected:
		col = COL_SELECTED
	for sgm in g["segs"]:
		lb.line(p.to_world(sgm[0]), p.to_world(sgm[1]), col)
	var arcp: PackedVector2Array = g["arc"]
	for i in arcp.size() - 1:
		lb.line(p.to_world(arcp[i]), p.to_world(arcp[i + 1]), col)
	var al := 9.0 * w
	var aw := 3.0 * w
	for ar in g["arrows"]:
		var tip: Vector2 = ar[0]
		var d: Vector2 = ar[1]
		var base := tip - d * al
		var nn := Vector2(-d.y, d.x) * aw
		lb.tri(p.to_world(tip), p.to_world(base + nn), p.to_world(base - nn), col)


func _place_label(idx: int, c: Dictionary, selected: bool, preview := false) -> int:
	var lbl: Label
	if idx < _labels.size():
		lbl = _labels[idx]
	else:
		lbl = Label.new()
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_constant_override("outline_size", 5)
		lbl.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.95))
		lbl.add_theme_font_size_override("font_size", 15)
		viewport.dim_layer.add_child(lbl)
		_labels.append(lbl)
	var g := dim_geometry(c)
	lbl.text = dimension_text(c)
	var col := Color(0.05, 0.05, 0.1)
	if bool(c.get("driven", false)):
		col = Color(0.4, 0.4, 0.45)
	if preview:
		col = COL_PREVIEW
	if selected:
		col = COL_SELECTED
	lbl.add_theme_color_override("font_color", col)
	lbl.reset_size()
	var sp := viewport.world_to_screen(plane().to_world(g["label"]))
	lbl.position = sp - lbl.size * 0.5
	lbl.visible = true
	if not preview:
		_label_items.append({"rect": Rect2(lbl.position, lbl.size), "cid": c["id"]})
	return idx + 1


func _relation_anchors(c: Dictionary) -> Array:
	var sk := sketch()
	var out: Array = []
	var w := _wpp()
	for eid in Sketch.constraint_entities(c):
		var e := sk.get_entity(eid)
		if e.is_empty():
			continue
		match e["type"]:
			"line":
				out.append(sk.line_midpoint(e))
			"circle":
				out.append((sk.points[e["c"]] as Vector2) + Vector2.from_angle(PI * 0.25) * float(e["r"]))
			"arc":
				var d := sk.arc_data(e)
				out.append((d["c"] as Vector2) + Vector2.from_angle(float(d["a0"]) + float(d["sweep"]) * 0.5) * float(d["r"]))
		if c["type"] in ["coincident", "midpoint", "symmetric"]:
			break
	if c["type"] in ["coincident", "midpoint", "fix"] and c.has("p1"):
		out = [sk.points[int(c["p1"])]]
	elif c["type"] in ["horizontal", "vertical"] and c.has("p1"):
		out = [((sk.points[int(c["p1"])] as Vector2) + (sk.points[int(c["p2"])] as Vector2)) * 0.5]
	elif c["type"] == "symmetric":
		out = [((sk.points[int(c["p1"])] as Vector2) + (sk.points[int(c["p2"])] as Vector2)) * 0.5]
	if out.is_empty():
		out.append(Vector2.ZERO + Vector2(4, 4) * w)
	return out


func _place_badges() -> void:
	_badge_items.clear()
	var bi := 0
	if show_relations:
		var sk := sketch()
		var stack := {}
		for c in sk.constraints:
			if Sketch.is_dimension(c):
				continue
			for anchor in _relation_anchors(c):
				var sp := viewport.world_to_screen(plane().to_world(anchor))
				var key := Vector2i(roundi(sp.x / 6.0), roundi(sp.y / 6.0))
				var n: int = stack.get(key, 0)
				stack[key] = n + 1
				var tr: TextureRect
				if bi < _badges.size():
					tr = _badges[bi]
				else:
					tr = TextureRect.new()
					tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
					tr.custom_minimum_size = Vector2(16, 16)
					tr.size = Vector2(16, 16)
					viewport.dim_layer.add_child(tr)
					_badges.append(tr)
				tr.texture = Icons.get_icon("rel_" + str(c["type"]), 16)
				tr.position = sp + Vector2(7 + 17 * n, -22)
				tr.modulate = Color(1.0, 0.75, 0.4) if selected_constraints.has(c["id"]) else Color.WHITE
				tr.visible = true
				_badge_items.append({"rect": Rect2(tr.position, Vector2(16, 16)), "cid": c["id"]})
				bi += 1
	for k in range(bi, _badges.size()):
		_badges[k].visible = false


func _draw_preview(lb: LineBuilder, p: SketchPlane, w: float) -> void:
	if _stage == 0:
		return
	var c := COL_PREVIEW
	match tool:
		"line":
			lb.line(p.to_world(_start_pos), p.to_world(_cursor), c)
		"centerline":
			lb.dashed(p.to_world(_start_pos), p.to_world(_cursor), c, 9.0 * w, 5.0 * w)
		"rect", "crect":
			var p1 := _start_pos if tool == "rect" else _start_pos * 2.0 - _cursor
			var p2 := _cursor
			lb.polyline(PackedVector3Array([
				p.to_world(p1), p.to_world(Vector2(p2.x, p1.y)), p.to_world(p2), p.to_world(Vector2(p1.x, p2.y))]), c, true)
			if tool == "crect":
				lb.dashed(p.to_world(p1), p.to_world(p2), c, 6.0 * w, 4.0 * w)
		"circle":
			var poly := Sketch.circle_polygon(_start_pos, maxf(_cursor.distance_to(_start_pos), 1e-6))
			var pts := PackedVector3Array()
			for q in poly:
				pts.append(p.to_world(q))
			lb.polyline(pts, c, true)
			lb.dashed(p.to_world(_start_pos), p.to_world(_cursor), c, 6.0 * w, 4.0 * w)
		"arc":
			if _stage == 1:
				lb.dashed(p.to_world(_start_pos), p.to_world(_cursor), c, 6.0 * w, 4.0 * w)
			else:
				var rad := _p2.distance_to(_start_pos)
				var a0 := (_p2 - _start_pos).angle()
				var n := maxi(4, int(absf(_arc_sweep) / TAU * 96.0))
				var pts2 := PackedVector3Array()
				for i in n + 1:
					var a := a0 + _arc_sweep * float(i) / float(n)
					pts2.append(p.to_world(_start_pos + Vector2.from_angle(a) * rad))
				lb.polyline(pts2, c)
				lb.dashed(p.to_world(_start_pos), p.to_world(_p2), c, 6.0 * w, 4.0 * w)
				lb.dashed(p.to_world(_start_pos), pts2[pts2.size() - 1], c, 6.0 * w, 4.0 * w)
		"polygon":
			var r := _cursor.distance_to(_start_pos)
			var a0p := (_cursor - _start_pos).angle()
			var pp := PackedVector3Array()
			for k in polygon_sides:
				pp.append(p.to_world(_start_pos + Vector2.from_angle(a0p + TAU * k / polygon_sides) * r))
			lb.polyline(pp, c, true)
			var circ := Sketch.circle_polygon(_start_pos, maxf(r, 1e-6))
			var cp := PackedVector3Array()
			for q in circ:
				cp.append(p.to_world(q))
			lb.dashed_polyline(cp, c, 5.0 * w, 4.0 * w)
		"slot":
			if _stage == 1:
				lb.dashed(p.to_world(_start_pos), p.to_world(_cursor), c, 6.0 * w, 4.0 * w)
			else:
				var hw := _slot_half_width()
				var u := (_p2 - _start_pos).normalized()
				var nn := Vector2(-u.y, u.x) * hw
				lb.line(p.to_world(_start_pos + nn), p.to_world(_p2 + nn), c)
				lb.line(p.to_world(_start_pos - nn), p.to_world(_p2 - nn), c)
				for end_c in [[_p2, u], [_start_pos, -u]]:
					var cc: Vector2 = end_c[0]
					var base := (end_c[1] as Vector2).angle()
					var ap := PackedVector3Array()
					for i in 25:
						ap.append(p.to_world(cc + Vector2.from_angle(base - PI * 0.5 + PI * i / 24.0) * hw))
					lb.polyline(ap, c)
				lb.dashed(p.to_world(_start_pos), p.to_world(_p2), c, 6.0 * w, 4.0 * w)
		"spline":
			var P: Array = []
			for info in _spline_pts:
				P.append(info["pos"])
			P.append(_cursor)
			var sp := Sketch.spline_through(P, false)
			var s3 := PackedVector3Array()
			for q in sp:
				s3.append(p.to_world(q))
			lb.polyline(s3, c)
			var s := 3.0 * w
			for q in P:
				lb.polyline(PackedVector3Array([
					p.to_world(q + Vector2(-s, -s)), p.to_world(q + Vector2(s, -s)),
					p.to_world(q + Vector2(s, s)), p.to_world(q + Vector2(-s, s))]), c, true)
		"ellipse":
			if _stage == 1:
				lb.dashed(p.to_world(_start_pos), p.to_world(_cursor), c, 6.0 * w, 4.0 * w)
			else:
				var a := _p2.distance_to(_start_pos)
				var phi := (_p2 - _start_pos).angle()
				var poly := Sketch.ellipse_polygon(_start_pos, a, maxf(_ellipse_minor(), 1e-6), phi)
				var e3 := PackedVector3Array()
				for q in poly:
					e3.append(p.to_world(q))
				lb.polyline(e3, c, true)
				lb.dashed(p.to_world(_start_pos), p.to_world(_p2), c, 6.0 * w, 4.0 * w)
		"parabola":
			if _stage == 1:
				lb.dashed(p.to_world(_start_pos), p.to_world(_cursor), c, 6.0 * w, 4.0 * w)
			else:
				var d := _p2 - _start_pos
				var fl := maxf(d.length(), 1e-9)
				var fr := {"v": _start_pos, "u": d / fl, "w": Vector2(-d.y, d.x) / fl, "fl": fl}
				var w0 := (_p3 - _start_pos).dot(fr["w"]) if _stage == 3 else -(_cursor - _start_pos).dot(fr["w"])
				var w1 := (_cursor - _start_pos).dot(fr["w"])
				var pp := PackedVector3Array()
				for i in 49:
					pp.append(p.to_world(Sketch.parabola_point(fr, lerpf(w0, w1, i / 48.0))))
				lb.polyline(pp, c)
				lb.dashed(p.to_world(_start_pos), p.to_world(_p2), c, 4.0 * w, 4.0 * w)


func _draw_grid(gb: LineBuilder, p: SketchPlane) -> void:
	var vs := viewport.camera.viewport_size()
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for c in [Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y)]:
		var r := viewport.ray(c)
		var hit = p.intersect_ray(r[0], r[1])
		if hit == null:
			return
		var l := p.to_local(hit)
		mn = mn.min(l)
		mx = mx.max(l)
	var step := grid_step
	if (mx.x - mn.x) / step > 400.0 or (mx.y - mn.y) / step > 400.0:
		return
	var minor := Color(0.66, 0.72, 0.82)
	var major := Color(0.5, 0.58, 0.72)
	var i := int(floor(mn.x / step))
	while i * step <= mx.x:
		var x := i * step
		gb.line(p.to_world(Vector2(x, mn.y)), p.to_world(Vector2(x, mx.y)), major if i % 5 == 0 else minor)
		i += 1
	var j := int(floor(mn.y / step))
	while j * step <= mx.y:
		var y := j * step
		gb.line(p.to_world(Vector2(mn.x, y)), p.to_world(Vector2(mx.x, y)), major if j % 5 == 0 else minor)
		j += 1
