class_name Sketch3DEditor
extends Node
## Temel 3B taslak düzenleyici:
## çizgiler etkin düzlem (XY / XZ / YZ) üzerinde çizilir; düzlem son noktadan geçer ve Tab ile değişir.
## Eksen yakalama: imleç son noktadan geçen eksen doğrultusuna yakınsa o eksene kilitlenir.

signal status(text: String)
signal changed_selection

const COL_LINE := Color(0.08, 0.25, 0.95)
const COL_SEL := Color(0.95, 0.38, 0.0)
const COL_PREV := Color(0.15, 0.5, 1.0)
const COL_AXIS := {"x": Color(0.9, 0.2, 0.2), "y": Color(0.2, 0.7, 0.25), "z": Color(0.2, 0.4, 0.95)}
const PLANES := ["XY", "XZ", "YZ"]
const SNAP_PX := 10.0

var viewport: CadViewport
var doc: CadDocument
var feature: CadFeature
var active := false
var plane_name := "XY"
var tool := "line"          # "line" | "select"
var grid_snap := true
var selected_point := -1
var selected_line := -1

var _chain_start := -1      # zincirin son noktası
var _anchor := Vector3.ZERO
var _cursor := Vector3.ZERO
var _snap_pid := -1
var _axis_lock := ""
var _has_cursor := false


func sk() -> Sketch3D:
	return feature.sketch3d


func begin(f: CadFeature) -> void:
	feature = f
	active = true
	_chain_start = -1
	_anchor = Vector3.ZERO
	selected_point = -1
	selected_line = -1
	tool = "line"
	_emit_hint()
	redraw()


func end() -> void:
	active = false
	feature = null
	(viewport.edit_mi.mesh as ArrayMesh).clear_surfaces()
	(viewport.grid_mi.mesh as ArrayMesh).clear_surfaces()
	viewport.show_cursor_text("", Vector2.ZERO)


func refresh() -> bool:
	if feature == null:
		return false
	var f := doc.get_feature(feature.id)
	if f == null or f.sketch3d == null:
		return false
	if f != feature:
		feature = f
		_chain_start = -1
	if not sk().points.has(selected_point):
		selected_point = -1
	if selected_line >= sk().lines.size():
		selected_line = -1
	redraw()
	return true


func plane_normal() -> Vector3:
	match plane_name:
		"XZ":
			return Vector3.UP
		"YZ":
			return Vector3.RIGHT
	return Vector3.BACK


func set_plane(pn: String) -> void:
	plane_name = pn
	_emit_hint()
	redraw()


func cycle_plane() -> void:
	set_plane(PLANES[(PLANES.find(plane_name) + 1) % PLANES.size()])


func set_tool(t: String) -> void:
	tool = t
	_chain_start = -1
	_emit_hint()
	redraw()


func _emit_hint() -> void:
	var t := "3B Taslak — düzlem %s (Tab: değiştir). " % plane_name
	if tool == "line":
		t += "Noktaları tıklayın; sağ tık / Esc zinciri bitirir. Eksene yakın çizim X/Y/Z'ye kilitlenir."
	else:
		t += "Nokta veya çizgi seçin; Delete siler, nokta koordinatları panelden girilir."
	status.emit(t)


func cancel() -> bool:
	if _chain_start >= 0:
		_chain_start = -1
		redraw()
		return true
	if selected_point >= 0 or selected_line >= 0:
		selected_point = -1
		selected_line = -1
		changed_selection.emit()
		redraw()
		return true
	return false


func _wpp() -> float:
	return viewport.camera.world_per_pixel()


func _grid_step() -> float:
	var raw := _wpp() * 13.0
	var e := pow(10.0, floor(log(raw) / log(10.0)))
	for m in [1.0, 2.0, 5.0, 10.0]:
		if m * e >= raw:
			return m * e
	return 10.0 * e


func _update_cursor(screen: Vector2) -> void:
	_snap_pid = -1
	_axis_lock = ""
	var s := sk()
	# Var olan noktalara ekranda yakalama
	var best := SNAP_PX
	for pid in s.points:
		var d := viewport.world_to_screen(s.points[pid]).distance_to(screen)
		if d < best:
			best = d
			_snap_pid = pid
	if _snap_pid >= 0:
		_cursor = s.points[_snap_pid]
		return
	if viewport.world_to_screen(Vector3.ZERO).distance_to(screen) < SNAP_PX:
		_cursor = Vector3.ZERO
		return
	var r := viewport.ray(screen)
	var n := plane_normal()
	var denom := n.dot(r[1])
	if absf(denom) < 1e-9:
		return
	var t := n.dot(_anchor - (r[0] as Vector3)) / denom
	var p: Vector3 = r[0] + r[1] * t
	# Eksen kilidi (son noktadan geçen X/Y/Z doğrultuları)
	if _chain_start >= 0:
		var sa := viewport.world_to_screen(_anchor)
		for ax in [["x", Vector3.RIGHT], ["y", Vector3.UP], ["z", Vector3.BACK]]:
			var dirv: Vector3 = ax[1]
			if absf(dirv.dot(n)) > 0.5:
				continue
			var sb := viewport.world_to_screen(_anchor + dirv * 10.0 * _wpp())
			var sd := (sb - sa)
			if sd.length() < 1e-3:
				continue
			var cp := Geometry2D.get_closest_point_to_segment_uncapped(screen, sa, sb)
			if cp.distance_to(screen) < 8.0:
				var along := (p - _anchor).dot(dirv)
				p = _anchor + dirv * along
				_axis_lock = ax[0]
				break
	if grid_snap:
		var st := _grid_step()
		for i in 3:
			if absf(n[i]) < 0.5:
				p[i] = snappedf(p[i], st)
	_cursor = p


func on_pointer(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		var pos := (event as InputEventMouseMotion).position
		_has_cursor = true
		_update_cursor(pos)
		var txt := "(%s, %s, %s)" % [Units.format_length(_cursor.x, false), Units.format_length(_cursor.y, false), Units.format_length(_cursor.z, false)]
		if _chain_start >= 0:
			txt = "L " + Units.format_length(_anchor.distance_to(_cursor)) + "   " + txt
		if _axis_lock != "":
			txt += "  [" + _axis_lock.to_upper() + "]"
		viewport.show_cursor_text(txt if tool == "line" else "", pos)
		redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
			cancel()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		_update_cursor(mb.position)
		if tool == "select":
			_select_at(mb.position)
			return
		var s := sk()
		var pid := _snap_pid if _snap_pid >= 0 else -1
		if _chain_start < 0:
			if pid < 0:
				doc.checkpoint()
				pid = s.add_point(_cursor)
				# tek nokta çizgi olmadan temizlenir; zincirin ilk noktası olarak tutulur
				doc.drop_checkpoint()
			_chain_start = pid
			_anchor = _cursor
		else:
			if _cursor.distance_to(_anchor) < 1e-6:
				return
			doc.checkpoint()
			var b := pid if pid >= 0 else s.add_point(_cursor)
			if not s.points.has(_chain_start):
				_chain_start = s.add_point(_anchor)
			s.add_line(_chain_start, b)
			_chain_start = b
			_anchor = _cursor
			doc.commit()
		redraw()


func _select_at(screen: Vector2) -> void:
	var s := sk()
	selected_point = -1
	selected_line = -1
	var best := SNAP_PX
	for pid in s.points:
		var d := viewport.world_to_screen(s.points[pid]).distance_to(screen)
		if d < best:
			best = d
			selected_point = pid
	if selected_point < 0:
		best = 7.0
		for i in s.lines.size():
			var a := viewport.world_to_screen(s.points[s.lines[i][0]])
			var b := viewport.world_to_screen(s.points[s.lines[i][1]])
			var d2 := Geometry2D.get_closest_point_to_segment(screen, a, b).distance_to(screen)
			if d2 < best:
				best = d2
				selected_line = i
	changed_selection.emit()
	redraw()


func delete_selection() -> bool:
	var s := sk()
	if selected_point >= 0:
		doc.checkpoint()
		s.remove_point(selected_point)
	elif selected_line >= 0:
		doc.checkpoint()
		s.remove_line(selected_line)
	else:
		return false
	selected_point = -1
	selected_line = -1
	doc.commit()
	return true


func edit_point(pid: int, p: Vector3) -> void:
	doc.checkpoint()
	sk().points[pid] = p
	doc.commit()


static func draw_lines(lb: LineBuilder, s: Sketch3D, col: Color, sel_line := -1, sel_col := COL_SEL) -> void:
	for i in s.lines.size():
		var l: Array = s.lines[i]
		lb.line(s.points[l[0]], s.points[l[1]], sel_col if i == sel_line else col)


func redraw() -> void:
	if not active or feature == null:
		return
	var lb := LineBuilder.new()
	var gb := LineBuilder.new()
	var s := sk()
	var w := _wpp()
	var cam := viewport.camera.orient
	draw_lines(lb, s, COL_LINE, selected_line)
	for pid in s.points:
		var c := COL_SEL if pid == selected_point else Color(0.05, 0.05, 0.1)
		lb.quad(s.points[pid], cam.x * 3.0 * w, cam.y * 3.0 * w, c)
	# Etkin düzlem ızgarası (çapa noktası çevresinde)
	var n := plane_normal()
	var u := Vector3.RIGHT if absf(n.x) < 0.5 else Vector3.BACK
	var v := n.cross(u).normalized()
	var st := _grid_step()
	var half := 20
	var gc := Color(0.62, 0.68, 0.8)
	var ctr := _anchor
	for i in range(-half, half + 1):
		var cc := gc.darkened(0.15) if i == 0 else gc
		gb.line(ctr + u * i * st - v * half * st, ctr + u * i * st + v * half * st, cc)
		gb.line(ctr + v * i * st - u * half * st, ctr + v * i * st + u * half * st, cc)
	# Önizleme
	if _has_cursor and tool == "line":
		if _chain_start >= 0:
			var pc: Color = COL_AXIS.get(_axis_lock, COL_PREV)
			lb.line(_anchor, _cursor, pc)
		var cs := 5.0 * w
		lb.line(_cursor - cam.x * cs, _cursor + cam.x * cs, COL_PREV)
		lb.line(_cursor - cam.y * cs, _cursor + cam.y * cs, COL_PREV)
	lb.commit(viewport.edit_mi.mesh)
	gb.commit(viewport.grid_mi.mesh)
