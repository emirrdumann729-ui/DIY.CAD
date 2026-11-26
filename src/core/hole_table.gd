class_name HoleTable
extends RefCounted
## Delik Sihirbazı ölçü tabloları (mm).
## ISO: geçiş deliği ISO 273 (sıkı / normal / gevşek), havşa başlı (silindirik havşa) ISO 4762 / DIN 974,
## konik havşa 90° ISO 15065, kılavuz matkabı ISO 261 kaba diş.
## ANSI: inç ölçüler (UNC), havşa 82°.

const ISO := {
	"M2": {"fit": [2.2, 2.4, 2.6], "cb": [4.3, 2.3], "cs": 4.4, "tap": 1.6, "pitch": 0.4},
	"M2.5": {"fit": [2.7, 2.9, 3.1], "cb": [5.0, 2.8], "cs": 5.5, "tap": 2.05, "pitch": 0.45},
	"M3": {"fit": [3.2, 3.4, 3.6], "cb": [6.5, 3.4], "cs": 6.3, "tap": 2.5, "pitch": 0.5},
	"M4": {"fit": [4.3, 4.5, 4.8], "cb": [8.0, 4.4], "cs": 8.4, "tap": 3.3, "pitch": 0.7},
	"M5": {"fit": [5.3, 5.5, 5.8], "cb": [10.0, 5.4], "cs": 10.4, "tap": 4.2, "pitch": 0.8},
	"M6": {"fit": [6.4, 6.6, 7.0], "cb": [11.0, 6.4], "cs": 12.4, "tap": 5.0, "pitch": 1.0},
	"M8": {"fit": [8.4, 9.0, 10.0], "cb": [15.0, 8.6], "cs": 16.4, "tap": 6.8, "pitch": 1.25},
	"M10": {"fit": [10.5, 11.0, 12.0], "cb": [18.0, 10.6], "cs": 20.4, "tap": 8.5, "pitch": 1.5},
	"M12": {"fit": [13.0, 13.5, 14.5], "cb": [20.0, 12.6], "cs": 24.4, "tap": 10.2, "pitch": 1.75},
	"M16": {"fit": [17.0, 17.5, 18.5], "cb": [26.0, 16.6], "cs": 32.4, "tap": 14.0, "pitch": 2.0},
	"M20": {"fit": [21.0, 22.0, 24.0], "cb": [33.0, 20.6], "cs": 40.4, "tap": 17.5, "pitch": 2.5},
	"M24": {"fit": [25.0, 26.0, 28.0], "cb": [40.0, 24.6], "cs": 48.4, "tap": 21.0, "pitch": 3.0},
}
const ISO_ORDER := ["M2", "M2.5", "M3", "M4", "M5", "M6", "M8", "M10", "M12", "M16", "M20", "M24"]

const IN := 25.4
## inç değerler: geçiş [sıkı, normal, gevşek], havşa başlı [çap, derinlik], havşa çapı, kılavuz matkabı, diş/inç
const ANSI := {
	"#4-40": {"fit": [0.1160, 0.1285, 0.1360], "cb": [0.1875, 0.112], "cs": 0.225, "tap": 0.0890, "tpi": 40},
	"#6-32": {"fit": [0.1440, 0.1495, 0.1610], "cb": [0.2190, 0.138], "cs": 0.262, "tap": 0.1065, "tpi": 32},
	"#8-32": {"fit": [0.1695, 0.1770, 0.1910], "cb": [0.2810, 0.164], "cs": 0.312, "tap": 0.1360, "tpi": 32},
	"#10-24": {"fit": [0.1960, 0.2010, 0.2130], "cb": [0.3125, 0.190], "cs": 0.362, "tap": 0.1495, "tpi": 24},
	"1/4-20": {"fit": [0.2570, 0.2660, 0.2810], "cb": [0.3750, 0.250], "cs": 0.477, "tap": 0.2010, "tpi": 20},
	"5/16-18": {"fit": [0.3230, 0.3320, 0.3480], "cb": [0.4375, 0.312], "cs": 0.597, "tap": 0.2570, "tpi": 18},
	"3/8-16": {"fit": [0.3860, 0.3970, 0.4130], "cb": [0.5625, 0.375], "cs": 0.717, "tap": 0.3125, "tpi": 16},
	"1/2-13": {"fit": [0.5156, 0.5312, 0.5625], "cb": [0.7500, 0.500], "cs": 0.957, "tap": 0.4219, "tpi": 13},
}
const ANSI_ORDER := ["#4-40", "#6-32", "#8-32", "#10-24", "1/4-20", "5/16-18", "3/8-16", "1/2-13"]

const TYPES := ["simple", "cbore", "csink", "tap"]
const TYPE_NAMES := ["Düz delik", "Havşa başlı (silindirik havşa)", "Havşa (konik)", "Kılavuz (diş)"]
const FITS := ["close", "normal", "loose"]
const FIT_NAMES := ["Sıkı", "Normal", "Gevşek"]


static func sizes(std: String) -> Array:
	return ANSI_ORDER if std == "ANSI" else ISO_ORDER


## Delik ölçüleri (mm): {d, cb_d, cb_h, cs_d, cs_ang, major, pitch, thread} veya {} (bilinmeyen ölçü).
static func dims(std: String, htype: String, size: String, fit: String) -> Dictionary:
	var fi := maxi(FITS.find(fit), 0)
	if std == "ANSI":
		if not ANSI.has(size):
			return {}
		var a: Dictionary = ANSI[size]
		var major := _ansi_major(size)
		var out := {"d": float(a["fit"][fi]) * IN, "cb_d": float(a["cb"][0]) * IN, "cb_h": float(a["cb"][1]) * IN,
			"cs_d": float(a["cs"]) * IN, "cs_ang": 82.0, "major": major, "pitch": IN / float(a["tpi"]),
			"thread": "%s UNC" % size}
		if htype == "tap":
			out["d"] = float(a["tap"]) * IN
		return out
	if not ISO.has(size):
		return {}
	var m: Dictionary = ISO[size]
	var o := {"d": float(m["fit"][fi]), "cb_d": float(m["cb"][0]), "cb_h": float(m["cb"][1]), "cs_d": float(m["cs"]),
		"cs_ang": 90.0, "major": float(size.substr(1)), "pitch": float(m["pitch"]),
		"thread": "%sx%s" % [size, str(m["pitch"])]}
	if htype == "tap":
		o["d"] = float(m["tap"])
	return o


static func _ansi_major(size: String) -> float:
	var num := size.split("-")[0]
	if num.begins_with("#"):
		return (0.060 + 0.013 * float(num.substr(1))) * IN
	var frac := num.split("/")
	return float(frac[0]) / float(frac[1]) * IN
