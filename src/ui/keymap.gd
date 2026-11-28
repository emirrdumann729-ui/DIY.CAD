class_name Keymap
extends RefCounted
## Özelleştirilebilir klavye kısayolları (Faz 9).
## Bağlamlar: "global" (her yerde) ve "sketch" (taslak modunda önce bakılır). Kısayol metni: "Ctrl+Shift+S", "L", "F2".
## Esc, Enter, ok tuşları ve Tab sabittir (özelleştirilmez).

const CONTEXTS := {"global": "Genel", "sketch": "Taslak"}

const DEFAULTS := [
	["global", "Ctrl+Z", "undo"], ["global", "Ctrl+Y", "redo"], ["global", "Ctrl+Shift+Z", "redo"],
	["global", "Ctrl+S", "save"], ["global", "Ctrl+Shift+S", "save_as"], ["global", "Ctrl+O", "open"], ["global", "Ctrl+N", "new"],
	["global", "Ctrl+1", "view_front"], ["global", "Ctrl+2", "view_back"], ["global", "Ctrl+3", "view_left"],
	["global", "Ctrl+4", "view_right"], ["global", "Ctrl+5", "view_top"], ["global", "Ctrl+6", "view_bottom"],
	["global", "Ctrl+7", "view_iso"], ["global", "Ctrl+8", "normal"], ["global", "Ctrl+E", "export_all"],
	["global", "F", "fit"], ["global", "Delete", "delete"], ["global", "F2", "rename"],
	["sketch", "L", "tool:line"], ["sketch", "N", "tool:centerline"], ["sketch", "R", "tool:rect"], ["sketch", "C", "tool:circle"],
	["sketch", "A", "tool:arc"], ["sketch", "S", "tool:select"], ["sketch", "D", "tool:dimension"], ["sketch", "T", "tool:trim"],
	["sketch", "E", "tool:extend"], ["sketch", "P", "tool:polygon"], ["sketch", "G", "grid_toggle"],
]
const FIXED := ["Escape", "Enter", "Kp Enter", "Left", "Right", "Up", "Down", "Tab"]

var bindings: Array = []      # [[ctx, shortcut, cmd], ...]


func _init() -> void:
	reset()


func reset() -> void:
	bindings = []
	for b in DEFAULTS:
		bindings.append((b as Array).duplicate())


## Olaydan kısayol metni (Meta = Ctrl). Yalnız değiştirici tuşa basıldıysa "".
static func shortcut_of(k: InputEventKey) -> String:
	var code := k.keycode
	if code == KEY_NONE:
		code = k.physical_keycode
	if code in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META, KEY_NONE]:
		return ""
	var parts: Array = []
	if k.ctrl_pressed or k.meta_pressed:
		parts.append("Ctrl")
	if k.alt_pressed:
		parts.append("Alt")
	if k.shift_pressed:
		parts.append("Shift")
	parts.append(OS.get_keycode_string(code))
	return "+".join(parts)


## "Ctrl+Shift+S" → tuş olayı (testler ve menü gösterimi için)
static func event_of(sc: String) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	for p in sc.split("+"):
		match p:
			"Ctrl":
				k.ctrl_pressed = true
			"Alt":
				k.alt_pressed = true
			"Shift":
				k.shift_pressed = true
			_:
				k.keycode = OS.find_keycode_from_string(p)
	return k


func find(ctx: String, sc: String) -> String:
	for b in bindings:
		if b[0] == ctx and b[1] == sc:
			return b[2]
	return ""


func shortcuts_for(cmd: String) -> Array:
	var out: Array = []
	for b in bindings:
		if b[2] == cmd:
			out.append(b[1])
	return out


func shortcut_for(cmd: String) -> String:
	var s := shortcuts_for(cmd)
	return s[0] if not s.is_empty() else ""


static func is_fixed(sc: String) -> bool:
	return sc in FIXED


## Komuta kısayol ata (komutun o bağlamdaki eski kısayolları ve aynı kısayolu kullanan başka komut kaldırılır).
## Dönüş: kısayolu kaybeden komut ("" yoksa)
func assign(ctx: String, cmd: String, sc: String) -> String:
	var lost := ""
	for i in range(bindings.size() - 1, -1, -1):
		var b: Array = bindings[i]
		if b[0] == ctx and b[2] == cmd:
			bindings.remove_at(i)
		elif b[0] == ctx and b[1] == sc and sc != "":
			lost = b[2]
			bindings.remove_at(i)
	if sc != "":
		bindings.append([ctx, sc, cmd])
	return lost


func clear_cmd(cmd: String) -> void:
	for i in range(bindings.size() - 1, -1, -1):
		if bindings[i][2] == cmd:
			bindings.remove_at(i)


func load_settings() -> void:
	var v: Variant = AppSettings.get_v("keys", "bindings", null)
	if v is Array and not (v as Array).is_empty():
		bindings = []
		for b in v:
			if b is Array and (b as Array).size() == 3:
				bindings.append([str(b[0]), str(b[1]), str(b[2])])
	else:
		reset()


func save_settings() -> void:
	AppSettings.set_v("keys", "bindings", bindings)


func is_default() -> bool:
	if bindings.size() != DEFAULTS.size():
		return false
	for b in DEFAULTS:
		if find(b[0], b[1]) != b[2]:
			return false
	return true
