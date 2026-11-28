class_name Configs
extends RefCounted
## Konfigürasyonlar ve tasarım tablosu (Faz 8).
## doc.configs = [{name, params: {parametre adı: değer}}], doc.active_config = etkin konfigürasyonun adı.
## Parametreler: taslak boyutları "D<n>@<Taslak>", özellik boyutları "D1@<Özellik>" (ekstrüzyon derinliği,
## döndürme açısı), bastırma "$BASTIR@<Özellik>" (1 = bastırılmış). Değerler iç birimde (mm / derece) saklanır;
## tasarım tablosu (CSV) ekrandaki birimle yazılır / okunur.

const SUP := "$BASTIR@"


static func capture(doc: CadDocument) -> Dictionary:
	var p := {}
	for f in doc.sketches():
		for c in f.sketch.constraints:
			if Sketch.is_dimension(c) and not bool(c.get("driven", false)):
				p[Equations.full_name(c, f.name)] = float(c.get("value", 0.0))
	for f in doc.features:
		if f.type == "extrude":
			p["D1@" + f.name] = float(f.params.get("depth", 0.0))
		elif f.type == "revolve":
			p["D1@" + f.name] = float(f.params.get("angle", 360.0))
		if not f.is_sketch() and not f.is_reference() and f.type != "sketch3d":
			p[SUP + f.name] = 1.0 if f.suppressed else 0.0
	return p


static func is_angle(doc: CadDocument, name: String) -> bool:
	if name.begins_with(SUP):
		return true   # birimsiz
	var at := name.get_slice("@", 1)
	var dn := name.get_slice("@", 0)
	for f in doc.features:
		if f.name != at:
			continue
		if f.is_sketch():
			for c in f.sketch.constraints:
				if Sketch.is_dimension(c) and Equations.dim_name(c) == dn:
					return str(c["type"]) == "angle"
		return f.type == "revolve"
	return false


## Parametreleri belgeye uygular, değişen taslakları çözer. Dönüş: uygulanan parametre sayısı
static func apply(doc: CadDocument, params: Dictionary) -> int:
	var n := 0
	var dirty := {}
	for name in params:
		var val := float(params[name])
		var at := str(name).get_slice("@", 1)
		var dn := str(name).get_slice("@", 0)
		for f in doc.features:
			if f.name != at:
				continue
			if str(name).begins_with(SUP):
				var s := val > 0.5
				if f.suppressed != s:
					f.suppressed = s
				n += 1
			elif f.is_sketch():
				for c in f.sketch.constraints:
					if Sketch.is_dimension(c) and Equations.dim_name(c) == dn:
						if absf(float(c.get("value", 0.0)) - val) > 1e-9:
							c["value"] = val
							dirty[f.id] = f
						n += 1
			elif dn == "D1" and f.type == "extrude":
				f.params["depth"] = val
				n += 1
			elif dn == "D1" and f.type == "revolve":
				f.params["angle"] = val
				n += 1
			break
	for id in dirty:
		SketchSolver.solve_sketch((dirty[id] as CadFeature).sketch)
	return n


static func find(doc: CadDocument, name: String) -> Dictionary:
	for c in doc.configs:
		if str(c["name"]) == name:
			return c
	return {}


## İlk kullanımda "Varsayılan" konfigürasyonu oluşturur
static func ensure_default(doc: CadDocument) -> void:
	if doc.configs.is_empty():
		doc.configs.append({"name": "Varsayılan", "params": capture(doc)})
		doc.active_config = "Varsayılan"


## Etkin konfigürasyonun güncel değerleri saklanır, hedef konfigürasyon uygulanır.
static func activate(doc: CadDocument, name: String) -> bool:
	ensure_default(doc)
	var tgt := find(doc, name)
	if tgt.is_empty():
		return false
	var cur := find(doc, doc.active_config)
	if not cur.is_empty():
		cur["params"] = capture(doc)
	apply(doc, tgt["params"])
	doc.active_config = name
	return true


static func add(doc: CadDocument, name: String) -> bool:
	ensure_default(doc)
	if name.strip_edges() == "" or not find(doc, name).is_empty():
		return false
	var cur := find(doc, doc.active_config)
	if not cur.is_empty():
		cur["params"] = capture(doc)
	doc.configs.append({"name": name, "params": capture(doc)})
	doc.active_config = name
	return true


static func remove(doc: CadDocument, name: String) -> bool:
	if doc.configs.size() <= 1 or name == doc.active_config:
		return false
	var keep: Array = []
	for c in doc.configs:
		if str(c["name"]) != name:
			keep.append(c)
	doc.configs = keep
	return true


static func _fmt(doc: CadDocument, name: String, v: float) -> String:
	if name.begins_with(SUP):
		return "1" if v > 0.5 else "0"
	return str(snappedf(v if is_angle(doc, name) else Units.to_display(v), 0.000001))


## Tasarım tablosu (CSV, ';' ayırıcı). İlk sütun konfigürasyon adı.
static func write_csv(doc: CadDocument, path: String) -> Error:
	ensure_default(doc)
	var cur := find(doc, doc.active_config)
	if not cur.is_empty():
		cur["params"] = capture(doc)
	var names: Array = []
	for c in doc.configs:
		for k in c["params"]:
			if not (k in names):
				names.append(k)
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
	fa.store_line("Konfigürasyon;" + ";".join(names))
	for c in doc.configs:
		var row: Array = [str(c["name"])]
		for k in names:
			row.append(_fmt(doc, k, float(c["params"][k])) if (c["params"] as Dictionary).has(k) else "")
		fa.store_line(";".join(row))
	fa.close()
	return OK


## Tasarım tablosunu okur: konfigürasyonları oluşturur / günceller. Dönüş: {configs, params} veya {error}
static func read_csv(doc: CadDocument, path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": I18n.t("Dosya bulunamadı")}
	var text := FileAccess.get_file_as_string(path).trim_prefix("﻿")
	var lines := text.replace("\r", "").split("\n", false)
	if lines.size() < 2:
		return {"error": I18n.t("Tabloda satır yok")}
	var sep := ";" if lines[0].contains(";") else ","
	var head := lines[0].split(sep)
	ensure_default(doc)
	var cur := find(doc, doc.active_config)
	if not cur.is_empty():
		cur["params"] = capture(doc)
	var known := capture(doc)
	var ncfg := 0
	for li in range(1, lines.size()):
		var cells := lines[li].split(sep)
		if cells.size() < 1 or cells[0].strip_edges() == "":
			continue
		var name := cells[0].strip_edges()
		var cfg := find(doc, name)
		if cfg.is_empty():
			cfg = {"name": name, "params": capture(doc)}
			doc.configs.append(cfg)
		for j in range(1, mini(head.size(), cells.size())):
			var key := head[j].strip_edges()
			var t := cells[j].strip_edges().replace(",", ".")
			if key == "" or t == "" or not known.has(key) or not t.is_valid_float():
				continue
			var v := t.to_float()
			if not key.begins_with(SUP) and not is_angle(doc, key):
				v = Units.from_display(v)
			cfg["params"][key] = v
		ncfg += 1
	var act := find(doc, doc.active_config)
	if not act.is_empty():
		apply(doc, act["params"])
	return {"configs": ncfg, "params": head.size() - 1}
