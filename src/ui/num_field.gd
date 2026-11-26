class_name NumField
extends LineEdit
## Sayısal giriş alanı. Matematik ifadesi kabul eder ("25.4*2", "12,5", "1in").
## kind: "length" (mm saklanır, birimle gösterilir) | "angle" (derece) | "plain"

signal value_committed(v: float)
signal expr_committed(expr: String)   # allow_expr açıkken "=..." yazılırsa

var kind := "length"
var allow_expr := false
var _last_expr := ""
var value := 0.0
var min_value := -INF
var max_value := INF


func _init(p_kind := "length", p_value := 0.0) -> void:
	kind = p_kind
	value = p_value


func _ready() -> void:
	select_all_on_focus = true
	custom_minimum_size.x = 90
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_submitted.connect(_on_submitted)
	focus_exited.connect(_commit)
	refresh()


func _on_submitted(_t: String) -> void:
	_commit()
	release_focus()


func set_value(v: float) -> void:
	value = v
	refresh()


func refresh() -> void:
	match kind:
		"length":
			text = Units.fmt(Units.to_display(value))
		"angle":
			text = Units.fmt(value)
		_:
			text = Units.fmt(value)
	remove_theme_color_override("font_color")


func _commit() -> void:
	if allow_expr and text.strip_edges().begins_with("="):
		var ex := text.strip_edges().substr(1).strip_edges()
		if ex != "" and ex != _last_expr:
			_last_expr = ex
			expr_committed.emit(ex)
		return
	_last_expr = ""
	var v = null
	if kind == "length":
		v = Units.parse_length(text)
	else:
		v = Units.evaluate(text)
	if v == null:
		add_theme_color_override("font_color", Color(1, 0.4, 0.35))
		return
	var fv := clampf(float(v), min_value, max_value)
	if absf(fv - value) > 1e-9:
		value = fv
		refresh()
		value_committed.emit(fv)
	else:
		refresh()
