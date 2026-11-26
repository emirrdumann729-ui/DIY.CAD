class_name Autosave
extends Node
## Otomatik kaydetme ve çökme kurtarma (Faz 9).
## Kirli parça / montaj belirli aralıklarla user://autosave/<tür>_<pid>.json dosyasına yazılır; kaydedince,
## yeni / açılan belgede ve düzgün çıkışta silinir. Açılışta sahibi çalışmayan (çökmüş) dosyalar kurtarma için sunulur.

static var DIR := "user://autosave"   # testler geçici klasöre yönlendirir

var app: Node
var enabled := true
var interval_min := 5.0
var _timer: Timer
var last_saved := {}        # tür -> unix zamanı


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.timeout.connect(tick)
	add_child(_timer)
	reload_settings()


func reload_settings() -> void:
	enabled = bool(AppSettings.get_v("autosave", "enabled"))
	interval_min = clampf(float(AppSettings.get_v("autosave", "interval_min")), 0.5, 120.0)
	if _timer == null:
		return
	_timer.stop()
	if enabled:
		_timer.wait_time = interval_min * 60.0
		_timer.start()


static func path_for(kind: String, pid := -1) -> String:
	return DIR.path_join("%s_%d.json" % [kind, OS.get_process_id() if pid < 0 else pid])


## Kirli belgeleri yaz (zamanlayıcı çağırır; testler doğrudan çağırabilir). Dönüş: yazılan dosya sayısı
func tick() -> int:
	var n := 0
	var doc: CadDocument = app.doc
	if doc.dirty and not doc.features.is_empty():
		n += int(_write("part", {"source": doc.file_path, "name": doc.part_name, "data": doc.to_dict()}))
	var am: Node = app.asm_mode
	if am != null and am.is_open() and am.asm.dirty:
		n += int(_write("asm", {"source": am.asm.file_path, "name": am.asm.name, "data": am.asm.to_dict(false)}))
	return n


func _write(kind: String, payload: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	payload["kind"] = kind
	payload["time"] = Time.get_unix_time_from_system()
	payload["pid"] = OS.get_process_id()
	var tmp := path_for(kind) + ".tmp"
	var fa := FileAccess.open(tmp, FileAccess.WRITE)
	if fa == null:
		return false
	fa.store_string(JSON.stringify(payload))
	fa.close()
	# Yarım yazılmış dosya kurtarmayı bozmasın: önce geçici dosya, sonra yeniden adlandır
	var dst := path_for(kind)
	if FileAccess.file_exists(dst):
		DirAccess.remove_absolute(dst)
	DirAccess.rename_absolute(tmp, dst)
	last_saved[kind] = payload["time"]
	return true


func clear(kind: String) -> void:
	var p := path_for(kind)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	last_saved.erase(kind)


func clear_all() -> void:
	clear("part")
	clear("asm")


## Kurtarılabilir kayıtlar: sahibi süreç artık çalışmayan dosyalar (en yenisi önce)
static func pending() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var p := DIR.path_join(f)
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if not (data is Dictionary) or not (data as Dictionary).has("data"):
			continue
		var pid := int(data.get("pid", -1))
		if pid == OS.get_process_id() or (pid > 0 and OS.is_process_running(pid)):
			continue
		data["file"] = p
		out.append(data)
	out.sort_custom(func(a, b): return float(a.get("time", 0)) > float(b.get("time", 0)))
	return out


static func discard(rec: Dictionary) -> void:
	var p := str(rec.get("file", ""))
	if p != "" and FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
