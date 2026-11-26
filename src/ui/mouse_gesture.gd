class_name MouseGesture
extends Control
## Fare hareketleri (Faz 9): sağ tuşla sürüklerken imlecin çevresinde
## 8 yönlü komut halkası açılır; bir yöne çekip bırakınca o komut çalışır. Bağlama göre (parça / taslak / montaj)
## atamalar Seçenekler → Fare hareketleri'nden değiştirilir.

const DIRS := ["Yukarı", "Sağ üst", "Sağ", "Sağ alt", "Aşağı", "Sol alt", "Sol", "Sol üst"]
const CONTEXTS := {"part": "Parça", "sketch": "Taslak", "assembly": "Montaj"}
const DEFAULTS := {
	"part": ["view_top", "view_iso", "view_right", "fit", "view_bottom", "view_front", "view_left", "normal"],
	"sketch": ["tool:line", "tool:rect", "tool:circle", "tool:arc", "tool:dimension", "tool:trim", "tool:centerline", "tool:select"],
	"assembly": ["view_top", "view_iso", "view_right", "fit", "view_bottom", "view_front", "view_left", "normal"],
}
const RADIUS := 100.0
const DEAD := 26.0

var slots: Array = []        # [{cmd, label, icon}] × 8
var center := Vector2.ZERO
var current := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func mapping(ctx: String) -> Array:
	var v: Variant = AppSettings.get_v("gestures", ctx, null)
	var out: Array = (DEFAULTS.get(ctx, DEFAULTS["part"]) as Array).duplicate()
	if v is Array and (v as Array).size() == 8:
		out = []
		for x in v:
			out.append(str(x))
	return out


static func save_mapping(ctx: String, arr: Array) -> void:
	AppSettings.set_v("gestures", ctx, arr)


## Yön indeksi (0 = yukarı, saat yönünde); ölü bölgedeyse -1
static func dir_index(v: Vector2) -> int:
	if v.length() < DEAD:
		return -1
	var a := atan2(v.x, -v.y)          # yukarı = 0, sağ = +90°
	return int(round(fposmod(a, TAU) / (TAU / 8.0))) % 8


func begin(at: Vector2, slot_list: Array) -> void:
	center = at
	slots = slot_list
	current = -1
	visible = true
	queue_redraw()


func update(at: Vector2) -> void:
	var i := dir_index(at - center)
	if i >= 0 and (i >= slots.size() or str(slots[i].get("cmd", "")) == ""):
		i = -1
	if i != current:
		current = i
		queue_redraw()


## Bitir: seçilen komut ("" yoksa)
func finish(at: Vector2) -> String:
	update(at)
	visible = false
	var cmd := ""
	if current >= 0:
		cmd = str(slots[current].get("cmd", ""))
	current = -1
	return cmd


func cancel() -> void:
	visible = false
	current = -1


func _draw() -> void:
	if not visible:
		return
	draw_circle(center, RADIUS + 40.0, Color(0.1, 0.12, 0.16, 0.28))
	draw_arc(center, DEAD, 0, TAU, 32, Color(1, 1, 1, 0.5), 1.5, true)
	var font := get_theme_default_font()
	for i in mini(8, slots.size()):
		var sl: Dictionary = slots[i]
		if str(sl.get("cmd", "")) == "":
			continue
		var ang := i * TAU / 8.0
		var p := center + Vector2(sin(ang), -cos(ang)) * RADIUS
		var hot := i == current
		var r := 21.0 if hot else 18.0
		draw_circle(p, r, Color(0.27, 0.55, 0.95, 0.95) if hot else Color(0.16, 0.19, 0.24, 0.92))
		draw_arc(p, r, 0, TAU, 28, Color(1, 1, 1, 0.8 if hot else 0.35), 1.5, true)
		var ic: Texture2D = sl.get("icon", null)
		if ic != null:
			draw_texture_rect(ic, Rect2(p - Vector2(12, 12), Vector2(24, 24)), false)
		var txt := str(sl.get("label", ""))
		var fs := 12
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := p + Vector2(-w * 0.5, r + 14.0)
		draw_rect(Rect2(tp + Vector2(-4, -12), Vector2(w + 8, 16)), Color(0.08, 0.09, 0.12, 0.8 if hot else 0.6))
		draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1) if hot else Color(0.85, 0.88, 0.92))
