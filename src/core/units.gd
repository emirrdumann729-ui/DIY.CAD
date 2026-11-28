class_name Units
extends RefCounted
## Birim sistemi (belgeye özeldir: Belge Özellikleri > Birimler).
## Dahili birimler her zaman: uzunluk = milimetre, kütle = gram, açı = derece.
## Ekranda seçilen birime çevrilir; kullanıcı girdisi seçilen birimde yorumlanır.

const LENGTH := {
	"mm": 1.0,
	"cm": 10.0,
	"m": 1000.0,
	"in": 25.4,
	"ft": 304.8,
}
const LENGTH_ORDER := ["mm", "cm", "m", "in", "ft"]

const MASS := {
	"g": 1.0,
	"kg": 1000.0,
	"lb": 453.59237,
}
const MASS_ORDER := ["g", "kg", "lb"]

const SYSTEMS := {
	"MMGS": {"length": "mm", "mass": "g", "decimals": 2, "label": "MMGS (milimetre, gram, saniye)"},
	"CGS": {"length": "cm", "mass": "g", "decimals": 3, "label": "CGS (santimetre, gram, saniye)"},
	"MKS": {"length": "m", "mass": "kg", "decimals": 4, "label": "MKS (metre, kilogram, saniye)"},
	"IPS": {"length": "in", "mass": "lb", "decimals": 3, "label": "IPS (inç, pound, saniye)"},
}
const SYSTEM_ORDER := ["MMGS", "CGS", "MKS", "IPS"]

static var system := "MMGS"
static var length_unit := "mm"
static var mass_unit := "g"
static var decimals := 2
static var angle_decimals := 2

static var _int_re: RegEx
static var _unit_re: RegEx


# ---------------------------------------------------------------- sistem

static func reset() -> void:
	set_system("MMGS")
	angle_decimals = 2


static func set_system(name: String) -> void:
	if not SYSTEMS.has(name):
		system = "custom"
		return
	var s: Dictionary = SYSTEMS[name]
	system = name
	length_unit = s["length"]
	mass_unit = s["mass"]
	decimals = int(s["decimals"])


## Uzunluk/kütle birimi elle seçildiğinde sistemi günceller (eşleşen yoksa "Özel").
static func set_custom(p_length: String, p_mass: String) -> void:
	length_unit = p_length if LENGTH.has(p_length) else "mm"
	mass_unit = p_mass if MASS.has(p_mass) else "g"
	system = "custom"
	for k in SYSTEMS:
		if SYSTEMS[k]["length"] == length_unit and SYSTEMS[k]["mass"] == mass_unit:
			system = k


static func system_short() -> String:
	if system == "custom":
		return I18n.t("Özel (%s, %s)") % [length_unit, mass_unit]
	return system


static func to_dict() -> Dictionary:
	return {"system": system, "length": length_unit, "mass": mass_unit,
		"decimals": decimals, "angle_decimals": angle_decimals}


static func apply_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	var sname := str(d.get("system", "MMGS"))
	if SYSTEMS.has(sname):
		set_system(sname)
	else:
		set_custom(str(d.get("length", "mm")), str(d.get("mass", "g")))
	decimals = clampi(int(d.get("decimals", decimals)), 0, 8)
	angle_decimals = clampi(int(d.get("angle_decimals", angle_decimals)), 0, 6)


# ---------------------------------------------------------------- çeviri

static func factor() -> float:
	return float(LENGTH.get(length_unit, 1.0))


static func mass_factor() -> float:
	return float(MASS.get(mass_unit, 1.0))


static func to_display(mm: float) -> float:
	return mm / factor()


static func from_display(v: float) -> float:
	return v * factor()


static func fmt(v: float, dec: int = -1) -> String:
	if dec < 0:
		dec = decimals
	var s: String = ("%." + str(dec) + "f") % v
	if s.begins_with("-") and s.trim_prefix("-").replace("0", "").replace(".", "") == "":
		s = s.trim_prefix("-")
	return s


## Anlamlı basamakla biçimlendirme (alan, hacim, atalet gibi geniş aralıklı değerler için).
static func fmt_sig(v: float, sig := 6) -> String:
	if v == 0.0 or is_nan(v):
		return "0"
	var a := absf(v)
	var e := int(floor(log(a) / log(10.0)))
	if a >= 1e-3 and a < 1e9:
		var digits := clampi(sig - 1 - e, 0, 10)
		var s: String = ("%." + str(digits) + "f") % v
		if s.contains("."):
			s = s.rstrip("0").rstrip(".")
		return s
	var m := v / pow(10.0, e)
	return ("%." + str(sig - 1) + "f") % m + "e" + str(e)


static func format_length(mm: float, with_unit := true) -> String:
	var s := fmt(to_display(mm))
	return s + (" " + length_unit if with_unit else "")


static func format_angle(deg: float) -> String:
	return fmt(deg, angle_decimals) + "°"


static func format_area(mm2: float) -> String:
	return fmt_sig(mm2 / pow(factor(), 2)) + " " + length_unit + "²"


static func format_volume(mm3: float) -> String:
	return fmt_sig(mm3 / pow(factor(), 3)) + " " + length_unit + "³"


static func format_mass(g: float) -> String:
	return fmt_sig(g / mass_factor()) + " " + mass_unit


## Yoğunluk g/cm³ olarak saklanır; seçilen birimle gösterilir.
static func format_density(g_cm3: float) -> String:
	var per_mm3 := g_cm3 / 1000.0
	var v := per_mm3 / mass_factor() * pow(factor(), 3)
	return fmt_sig(v) + " " + mass_unit + "/" + length_unit + "³"


## Atalet: g·mm² -> seçilen kütle·uzunluk²
static func format_inertia(g_mm2: float) -> String:
	return fmt_sig(g_mm2 / mass_factor() / pow(factor(), 2)) + " " + mass_unit + "·" + length_unit + "²"


# ---------------------------------------------------------------- girdi

## "10*2+5", "12,5", "1in + 3mm" gibi ifadeleri hesaplar.
## Birim eki olan sayılar görüntü birimine çevrilir. Hata durumunda null döner.
static func evaluate(text: String) -> Variant:
	var t := text.strip_edges().to_lower()
	if t.is_empty():
		return null
	t = t.replace(",", ".").replace("°", "").replace("deg", "")
	# Boyut etiketinden kopyalanan "Ø12" / "R 5" önekleri
	t = t.trim_prefix("ø").trim_prefix("r ").strip_edges()
	if _unit_re == null:
		_unit_re = RegEx.new()
		_unit_re.compile("(\\d+(?:\\.\\d+)?|\\.\\d+)\\s*(mm|cm|in|ft|m|\")(?![a-z])")
		_int_re = RegEx.new()
		_int_re.compile("(?<![\\d.])(\\d+)(?![\\d.])")
	# Birim eklerini çöz: "1in" -> "(1*25.4/faktör)"
	var out := ""
	var last := 0
	for m in _unit_re.search_all(t):
		var u: String = m.get_string(2)
		if u == "\"":
			u = "in"
		var f: float = float(LENGTH[u]) / factor()
		out += t.substr(last, m.get_start() - last) + "(" + m.get_string(1) + "*" + str(f) + ")"
		last = m.get_end()
	out += t.substr(last)
	# Tamsayı bölmesini engelle: 10/4 = 2.5 olsun
	out = _int_re.sub(out, "$1.0", true)
	var expr := Expression.new()
	if expr.parse(out) != OK:
		return null
	var r = expr.execute([], null, false)
	if expr.has_execute_failed():
		return null
	if typeof(r) == TYPE_INT or typeof(r) == TYPE_FLOAT:
		var v := float(r)
		if is_nan(v) or is_inf(v):
			return null
		return v
	return null


## Görüntü biriminde yazılmış uzunluğu mm'ye çevirir.
static func parse_length(text: String) -> Variant:
	var v = evaluate(text)
	if v == null:
		return null
	return from_display(float(v))
