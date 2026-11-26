class_name AppSettings
extends RefCounted
## Uygulama ayarları (Faz 9): user://diycad.cfg içindeki bölümler — ui, autosave, recent, keys, gestures, mouse.
## Çekirdek ayarları (GeoKernel) ve dışa aktarma ayarları da aynı dosyadadır.

static var PATH := "user://diycad.cfg"   # testler geçici dosyaya yönlendirir
const MAX_RECENT := 10

const DEFAULTS := {
	"ui": {"theme": "dark", "scale": 1.0, "lang": "tr"},
	"autosave": {"enabled": true, "interval_min": 5.0, "backup": false},
	"mouse": {"rmb": "rotate"},
}


static func get_v(section: String, key: String, default: Variant = null) -> Variant:
	var cf := ConfigFile.new()
	var def: Variant = default
	if def == null and DEFAULTS.has(section):
		def = (DEFAULTS[section] as Dictionary).get(key, null)
	if cf.load(PATH) != OK or not cf.has_section_key(section, key):
		return def
	return cf.get_value(section, key)


static func set_v(section: String, key: String, value: Variant) -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)
	cf.set_value(section, key, value)
	cf.save(PATH)


static func erase_section(section: String) -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK or not cf.has_section(section):
		return
	cf.erase_section(section)
	cf.save(PATH)


## Kullanıcı veri klasöründeki (testler, otomatik kayıt) dosyalar son dosyalara girmez.
static func is_internal_path(path: String) -> bool:
	var ud := OS.get_user_data_dir().replace("\\", "/").to_lower()
	var p := path.replace("\\", "/").to_lower()
	return p.begins_with("user://") or (ud != "" and p.begins_with(ud))


static func recent() -> Array:
	var out: Array = []
	var v: Variant = get_v("recent", "files", [])
	if v is Array:
		for p in v:
			out.append(str(p))
	return out


static func add_recent(path: String) -> void:
	if path == "" or is_internal_path(path):
		return
	var lst := recent()
	var norm := path.replace("\\", "/")
	for i in range(lst.size() - 1, -1, -1):
		if str(lst[i]).replace("\\", "/").to_lower() == norm.to_lower():
			lst.remove_at(i)
	lst.insert(0, norm)
	if lst.size() > MAX_RECENT:
		lst.resize(MAX_RECENT)
	set_v("recent", "files", lst)


static func remove_recent(path: String) -> void:
	var lst := recent()
	lst.erase(path)
	set_v("recent", "files", lst)


static func clear_recent() -> void:
	set_v("recent", "files", [])


## Program klasöründeki alt klasör (geliştirmede proje klasörü, kurulu sürümde .exe'nin yanı)
static func app_dir(sub := "") -> String:
	var base := OS.get_executable_path().get_base_dir() if OS.has_feature("template") else ProjectSettings.globalize_path("res://")
	return base.path_join(sub) if sub != "" else base
