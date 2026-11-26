class_name Plugins
extends RefCounted
## Eklenti yöneticisi (Faz 9): plugins/ klasörlerindeki eklentileri bulur, yükler, açar / kapatır.
## Klasörler: program klasörü (geliştirmede res://plugins, kurulu sürümde .exe yanındaki plugins/) ve
## kullanıcı klasörü (user://plugins). Etkinlik ayarı user://diycad.cfg [plugins] disabled listesinde.

var app: Node
var items: Array = []        # {id, name, desc, path, enabled, ok, error}
var _objs: Array = []        # yüklü eklenti nesneleri (yaşam süresi)


func _init(a: Node) -> void:
	app = a


static func program_dir() -> String:
	return AppSettings.app_dir("plugins")


static func dirs() -> Array:
	return [program_dir(), ProjectSettings.globalize_path("user://plugins")]


static func discover() -> Array:
	var paths: Array = []
	for d in dirs():
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if f.get_extension() == "gd" and not f.begins_with("_"):
				paths.append(d.path_join(f))
		for sub in da.get_directories():
			var p: String = str(d).path_join(sub).path_join("plugin.gd")
			if FileAccess.file_exists(p):
				paths.append(p)
	return paths


static func id_of(path: String) -> String:
	return path.get_base_dir().get_file() if path.get_file() == "plugin.gd" else path.get_file().get_basename()


static func _const_str(src: String, cname: String) -> String:
	var re := RegEx.new()
	re.compile("const\\s+" + cname + "\\s*:?=\\s*\"([^\"]*)\"")
	var m := re.search(src)
	return m.get_string(1) if m != null else ""


static func disabled() -> Array:
	var v: Variant = AppSettings.get_v("plugins", "disabled", [])
	return v if v is Array else []


static func set_enabled(id: String, on: bool) -> void:
	var lst := disabled()
	lst.erase(id)
	if not on:
		lst.append(id)
	AppSettings.set_v("plugins", "disabled", lst)


func load_all() -> void:
	items = []
	var off := disabled()
	for path in discover():
		var src := FileAccess.get_file_as_string(path)
		var id := id_of(path)
		var it := {"id": id, "path": path, "name": _const_str(src, "NAME"), "desc": _const_str(src, "DESCRIPTION"),
			"enabled": not off.has(id), "ok": false, "error": ""}
		if str(it["name"]) == "":
			it["name"] = id
		items.append(it)
		if not it["enabled"]:
			continue
		var s := GDScript.new()
		s.source_code = src
		if s.reload() != OK:
			it["error"] = "derlenemedi (sözdizimi hatası)"
			continue
		var obj: Object = s.new()
		if obj == null or not obj.has_method("setup"):
			it["error"] = "setup(api) yok"
			continue
		var api := PluginApi.new(app, id, str(it["name"]))
		obj.setup(api)
		_objs.append([obj, api])
		it["ok"] = true


func loaded_count() -> int:
	var n := 0
	for it in items:
		n += int(bool(it["ok"]))
	return n
