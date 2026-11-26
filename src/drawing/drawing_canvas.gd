class_name DrawingCanvas
extends Control
## Teknik resim sayfası görüntüleyici: DrawingRender ilkellerini çizer.
## Tekerlek: imlece doğru yakınlaştır; orta/sağ tuş sürükle: kaydır; sol tık / sürükle: araçlara iletilir.

signal clicked(sheet_pos: Vector2, double: bool, shift: bool)
signal hovered(sheet_pos: Vector2)
signal dragged(from: Vector2, to: Vector2, done: bool)

var prims: Array = []
var overlay: Array = []          # araç önizlemeleri (üstte çizilir)
var sheet_size := Vector2(420, 297)
var zoom := 2.0                  # px / mm
var pan := Vector2(20, 600)      # sayfanın sol alt köşesinin ekran konumu
var font: Font
var _fitted := false
var _pan_drag := false
var _left_down := false
var _down_pos := Vector2.ZERO
var _moved := false


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	resized.connect(func(): if not _fitted: fit())


func fit() -> void:
	if size.x < 10 or size.y < 10:
		return
	zoom = minf((size.x - 40.0) / sheet_size.x, (size.y - 40.0) / sheet_size.y)
	pan = Vector2((size.x - sheet_size.x * zoom) * 0.5, size.y - (size.y - sheet_size.y * zoom) * 0.5)
	_fitted = true
	queue_redraw()


func to_screen(p: Vector2) -> Vector2:
	return Vector2(pan.x + p.x * zoom, pan.y - p.y * zoom)


func to_sheet(s: Vector2) -> Vector2:
	return Vector2((s.x - pan.x) / zoom, (pan.y - s.y) / zoom)


func set_content(p_prims: Array, p_size: Vector2) -> void:
	var resized_sheet := not p_size.is_equal_approx(sheet_size)
	prims = p_prims
	sheet_size = p_size
	if resized_sheet or not _fitted:
		fit()
	queue_redraw()


func _px(w_mm: float) -> float:
	return maxf(1.0, w_mm * zoom * 0.9)


func _dash_pattern(s: String) -> Array:
	var d: Array = DrawingExport.DASH.get(s, [])
	var out: Array = []
	for v in d:
		out.append(maxf(float(v) * zoom, 1.5))
	return out


func _draw_dashed(pts: PackedVector2Array, col: Color, w: float, pattern: Array) -> void:
	var idx := 0
	var left: float = pattern[0]
	var on := true
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		var pos := 0.0
		var guard := 0
		while pos < seg and guard < 10000:
			var step := minf(left, seg - pos)
			if on:
				draw_line(a.lerp(b, pos / seg), a.lerp(b, (pos + step) / seg), col, w)
			pos += step
			left -= step
			if left <= 1e-6:
				idx = (idx + 1) % pattern.size()
				left = pattern[idx]
				on = idx % 2 == 0
			guard += 1


func _draw_prim(p: Dictionary) -> void:
	match str(p["t"]):
		"l", "pl", "circ":
			var col: Color = p.get("col", Color.BLACK) if p["t"] == "circ" else p.get("c", Color.BLACK)
			var w := _px(float(p["w"]))
			var pts := PackedVector2Array()
			if p["t"] == "l":
				pts = PackedVector2Array([to_screen(p["a"]), to_screen(p["b"])])
			elif p["t"] == "pl":
				for q in p["pts"]:
					pts.append(to_screen(q))
				if bool(p.get("closed", false)) and pts.size() > 2:
					pts.append(pts[0])
			else:
				var c: Vector2 = p["c"]
				var r := float(p["r"])
				var n := clampi(int(r * zoom * 0.6), 16, 128)
				for k in n + 1:
					var t := TAU * k / n
					pts.append(to_screen(c + Vector2(cos(t), sin(t)) * r))
			var pat := _dash_pattern(str(p.get("s", "solid")))
			if pat.is_empty():
				draw_polyline(pts, col, w, true)
			else:
				_draw_dashed(pts, col, w, pat)
		"fill":
			var pts2 := PackedVector2Array()
			for q in p["pts"]:
				pts2.append(to_screen(q))
			if pts2.size() >= 3:
				draw_colored_polygon(pts2, p.get("c", Color.BLACK))
		"txt":
			var fs := int(maxf(4.0, float(p["h"]) * 1.38 * zoom))
			if fs < 5:
				return
			var s: String = p["s"]
			var w2 := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var al := str(p.get("al", "l"))
			var dx := 0.0 if al == "l" else (-w2 * 0.5 if al == "c" else -w2)
			var ang := float(p.get("ang", 0.0))
			draw_set_transform(to_screen(p["p"]), -ang, Vector2.ONE)
			draw_string(font, Vector2(dx, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, p.get("c", Color.BLACK))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.36, 0.39, 0.44))
	var tl := to_screen(Vector2(0, sheet_size.y))
	var rect := Rect2(tl, sheet_size * zoom)
	draw_rect(Rect2(rect.position + Vector2(5, 5), rect.size), Color(0, 0, 0, 0.35))
	draw_rect(rect, Color.WHITE)
	for p in prims:
		_draw_prim(p)
	for p in overlay:
		_draw_prim(p)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					var f := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
					var before := to_sheet(mb.position)
					zoom = clampf(zoom * f, 0.2, 80.0)
					var after := to_screen(before)
					pan += mb.position - after
					queue_redraw()
				accept_event()
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_pan_drag = mb.pressed
				accept_event()
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_left_down = true
					_moved = false
					_down_pos = mb.position
					if mb.double_click:
						clicked.emit(to_sheet(mb.position), true, mb.shift_pressed)
						_left_down = false
				else:
					if _left_down:
						if _moved:
							dragged.emit(to_sheet(_down_pos), to_sheet(mb.position), true)
						else:
							clicked.emit(to_sheet(mb.position), false, mb.shift_pressed)
					_left_down = false
				accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pan_drag:
			pan += mm.relative
			queue_redraw()
		elif _left_down and mm.position.distance_to(_down_pos) > 4.0:
			_moved = true
			dragged.emit(to_sheet(_down_pos), to_sheet(mm.position), false)
		hovered.emit(to_sheet(mm.position))
