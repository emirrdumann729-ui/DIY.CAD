class_name Materials
extends RefCounted
## Malzeme kütüphanesi. Yoğunluk g/cm³ cinsindendir.
## Renk, modelin ekrandaki görünümü için kullanılır.

const DEFAULT_COLOR := Color(0.72, 0.76, 0.82)
const DEFAULT_DENSITY := 1.0  # malzeme yoksa (su) varsayılır

const LIST := [
	{"name": "Düz Karbon Çelik (AISI 1020)", "density": 7.87, "color": Color(0.60, 0.62, 0.66), "group": "Metal"},
	{"name": "Paslanmaz Çelik (AISI 304)", "density": 8.00, "color": Color(0.74, 0.76, 0.78), "group": "Metal"},
	{"name": "Dökme Demir (Gri)", "density": 7.20, "color": Color(0.42, 0.43, 0.45), "group": "Metal"},
	{"name": "Alüminyum 6061", "density": 2.70, "color": Color(0.80, 0.82, 0.85), "group": "Metal"},
	{"name": "Alüminyum 7075", "density": 2.81, "color": Color(0.78, 0.80, 0.84), "group": "Metal"},
	{"name": "Pirinç", "density": 8.50, "color": Color(0.83, 0.68, 0.32), "group": "Metal"},
	{"name": "Bakır", "density": 8.96, "color": Color(0.80, 0.48, 0.32), "group": "Metal"},
	{"name": "Bronz", "density": 8.80, "color": Color(0.70, 0.50, 0.28), "group": "Metal"},
	{"name": "Titanyum (Ti-6Al-4V)", "density": 4.43, "color": Color(0.62, 0.62, 0.65), "group": "Metal"},
	{"name": "PLA", "density": 1.24, "color": Color(0.95, 0.55, 0.20), "group": "Plastik (3B baskı)"},
	{"name": "ABS", "density": 1.04, "color": Color(0.90, 0.90, 0.86), "group": "Plastik (3B baskı)"},
	{"name": "PETG", "density": 1.27, "color": Color(0.35, 0.65, 0.85), "group": "Plastik (3B baskı)"},
	{"name": "TPU (esnek)", "density": 1.21, "color": Color(0.25, 0.25, 0.28), "group": "Plastik (3B baskı)"},
	{"name": "Naylon (PA12)", "density": 1.01, "color": Color(0.92, 0.92, 0.90), "group": "Plastik"},
	{"name": "Akrilik (PMMA)", "density": 1.18, "color": Color(0.80, 0.90, 0.95), "group": "Plastik"},
	{"name": "Polikarbonat (PC)", "density": 1.20, "color": Color(0.85, 0.88, 0.92), "group": "Plastik"},
	{"name": "POM (Delrin)", "density": 1.41, "color": Color(0.95, 0.95, 0.93), "group": "Plastik"},
	{"name": "Meşe", "density": 0.75, "color": Color(0.70, 0.52, 0.32), "group": "Ahşap"},
	{"name": "Çam", "density": 0.50, "color": Color(0.86, 0.72, 0.50), "group": "Ahşap"},
	{"name": "Kontrplak (Huş)", "density": 0.68, "color": Color(0.88, 0.78, 0.60), "group": "Ahşap"},
	{"name": "MDF", "density": 0.75, "color": Color(0.66, 0.54, 0.40), "group": "Ahşap"},
]


static func find(material_name: String) -> Dictionary:
	for m in LIST:
		if m["name"] == material_name:
			return m
	return {}


static func names() -> Array:
	var out: Array = []
	for m in LIST:
		out.append(m["name"])
	return out


static func density_of(material_name: String) -> float:
	var m := find(material_name)
	return float(m["density"]) if not m.is_empty() else DEFAULT_DENSITY


static func color_of(material_name: String) -> Color:
	var m := find(material_name)
	return m["color"] if not m.is_empty() else DEFAULT_COLOR
