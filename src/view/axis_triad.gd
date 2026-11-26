extends Control
## Sol alt köşedeki XYZ eksen göstergesi.

var camera: CadCamera


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if camera == null:
		return
	var b := camera.orient
	var center := Vector2(48, size.y - 48)
	var L := 34.0
	var axes := [
		[Vector3.RIGHT, Color(0.86, 0.2, 0.2), "X"],
		[Vector3.UP, Color(0.2, 0.68, 0.25), "Y"],
		[Vector3.BACK, Color(0.2, 0.4, 0.9), "Z"],
	]
	# Uzaktaki eksen önce çizilsin
	axes.sort_custom(func(p, q): return (p[0] as Vector3).dot(b.z) < (q[0] as Vector3).dot(b.z))
	var font := ThemeDB.fallback_font
	for ax in axes:
		var v: Vector3 = ax[0]
		var d := Vector2(v.dot(b.x), -v.dot(b.y)) * L
		var col: Color = ax[1]
		draw_line(center, center + d, col, 2.5, true)
		draw_circle(center + d, 3.0, col)
		draw_string(font, center + d * 1.3 + Vector2(-4, 5), ax[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	draw_circle(center, 3.0, Color(0.25, 0.25, 0.3))
