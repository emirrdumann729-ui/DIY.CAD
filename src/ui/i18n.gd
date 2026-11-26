class_name I18n
extends RefCounted
## Dil desteği (Faz 9): arayüz metinleri Türkçe yazılır; İngilizce için res://i18n/en.txt sözlüğü
## ("türkçe<TAB>english", \n kaçışlı) Godot'nun otomatik çevirisine (TranslationServer) yüklenir.
## Düğme, etiket, menü, sekme ve ipucu metinleri dil değişince kendiliğinden güncellenir.

const LANGS := {"tr": "Türkçe", "en": "English"}
const DICT_PATH := "res://i18n/%s.txt"

static var current := "tr"
static var _loaded := {}


static func _unescape(s: String) -> String:
	return s.replace("\\n", "\n").replace("\\t", "\t")


## Sözlüğü yükle: {türkçe: çeviri}
static func load_dict(lang: String) -> Dictionary:
	var out := {}
	var p := DICT_PATH % lang
	if not FileAccess.file_exists(p):
		return out
	var f := FileAccess.open(p, FileAccess.READ)
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "" or line.begins_with("#"):
			continue
		var i := line.find("\t")
		if i <= 0:
			continue
		out[_unescape(line.substr(0, i))] = _unescape(line.substr(i + 1))
	return out


static func set_language(lang: String, save := true) -> void:
	if not LANGS.has(lang):
		lang = "tr"
	current = lang
	if lang != "tr" and not _loaded.has(lang):
		var t := Translation.new()
		t.locale = lang
		var d := load_dict(lang)
		for k in d:
			t.add_message(k, d[k])
		TranslationServer.add_translation(t)
		_loaded[lang] = t
	TranslationServer.set_locale(lang)
	if save:
		AppSettings.set_v("ui", "lang", lang)


## Koddan çeviri (otomatik çevrilmeyen biçimli metinler için)
static func t(s: String) -> String:
	if current == "tr":
		return s
	return TranslationServer.translate(s)
