class_name CadDocument
extends RefCounted
## Parça belgesi: sıralı özellik listesi + geri al/yinele + dosya işlemleri.

signal changed

const FORMAT := "DIY.CAD"
const VERSION := 2
const MAX_UNDO := 100

var part_name := "Parça1"
## Dosya türü (uzantıdan): part | part_template | drawing | drawing_template | library_feature | forming_tool
const KIND_BY_EXT := {"dcad": "part", "dcadt": "part_template", "ddrw": "drawing", "ddrwt": "drawing_template",
	"dclfp": "library_feature", "dcftp": "forming_tool"}
var doc_kind := "part"
var material := ""          # Materials.LIST içindeki ad; boş = belirtilmemiş
var variables: Array = []   # global değişkenler [{name, expr}]
var features: Array = []
var next_id := 1
var counters := {}
var file_path := ""
var dirty := false
## Geri alma çubuğu: >= 0 ise yalnızca ilk `rollback` özellik etkindir (sonrakiler hesaplanmaz)
var rollback := -1
## Teknik resim sayfaları (Faz 6): Drawing.new_sheet() sözlükleri
var drawings: Array = []
## Konfigürasyonlar (Faz 8): [{name, params}], etkin olanın adı
var configs: Array = []
var active_config := ""

var _undo: Array = []
var _redo: Array = []


func new_feature(type: String, name_prefix: String) -> CadFeature:
	var f := CadFeature.new()
	f.id = next_id
	next_id += 1
	f.type = type
	counters[name_prefix] = int(counters.get(name_prefix, 0)) + 1
	f.name = "%s%d" % [name_prefix, counters[name_prefix]]
	return f


func add_feature(f: CadFeature) -> void:
	if rollback >= 0 and rollback < features.size():
		# Geri alma çubuğu varken yeni özellik çubuğun hemen önüne eklenir
		features.insert(rollback, f)
		rollback += 1
	else:
		features.append(f)


## Geri alma çubuğuna göre etkin (hesaplanan) özellikler.
func active_features() -> Array:
	if rollback < 0 or rollback >= features.size():
		return features.duplicate()
	return features.slice(0, rollback)


func is_rolled_back(f: CadFeature) -> bool:
	return rollback >= 0 and index_of(f.id) >= rollback


func set_rollback(index: int) -> void:
	rollback = -1 if index < 0 or index >= features.size() else index


func get_feature(id: int) -> CadFeature:
	for f in features:
		if f.id == id:
			return f
	return null


func index_of(id: int) -> int:
	for i in features.size():
		if features[i].id == id:
			return i
	return -1


func replace_feature(f: CadFeature) -> void:
	var i := index_of(f.id)
	if i >= 0:
		features[i] = f


## Bu taslağı kullanan özellikler.
func consumers_of(sketch_id: int) -> Array:
	var out := []
	for f in features:
		if not f.is_sketch() and sketch_id in f.used_sketch_ids():
			out.append(f)
	return out


static func _scan_refs(v: Variant, ids: Dictionary) -> void:
	if v is Dictionary:
		for k in v:
			_scan_refs(v[k], ids)
	elif v is Array:
		for x in v:
			_scan_refs(x, ids)
	elif v is String:
		var s: String = v
		# Topolojik adlar "F<id>:..." ve referans değerleri "pl:<id>" / "ax:<id>"
		if s.length() > 2 and s[0] == "F" and s.contains(":"):
			var num := s.substr(1, s.find(":") - 1)
			if num.is_valid_int():
				ids[int(num)] = true
		elif s.begins_with("pl:") or s.begins_with("ax:"):
			var n2 := s.substr(3)
			if n2.is_valid_int():
				ids[int(n2)] = true


## Ebeveynler: bu özelliğin dayandığı özellikler (taslaklar, referanslar, adı geçen yüzleri üreten özellikler).
func parents_of(f: CadFeature) -> Array:
	var ids := {}
	for sid in f.used_sketch_ids():
		ids[int(sid)] = true
	for x in f.params.get("features", []):
		ids[int(x)] = true
	for key in ["path", "guide", "curve"]:
		var path = f.params.get(key, {})
		if path is Dictionary and path.has("id"):
			ids[int(path["id"])] = true
	if f.type == "helix" and f.params.has("sketch"):
		ids[int(f.params["sketch"])] = true
	_scan_refs(f.params, ids)
	if f.plane != null:
		if f.plane.ref >= 0:
			ids[f.plane.ref] = true
		_scan_refs(f.plane.support, ids)
	ids.erase(f.id)
	var out: Array = []
	for id in ids:
		if get_feature(int(id)) != null:
			out.append(int(id))
	out.sort_custom(func(a, b): return index_of(a) < index_of(b))
	return out


func children_of(id: int) -> Array:
	var out: Array = []
	for f in features:
		if f.id != id and id in parents_of(f):
			out.append(f.id)
	return out


## Özellik new_index konumuna taşınabilir mi (ebeveynlerinden önceye, çocuklarından sonraya geçemez).
func can_move(id: int, new_index: int) -> bool:
	var f := get_feature(id)
	if f == null or new_index < 0 or new_index >= features.size():
		return false
	var old := index_of(id)
	if new_index == old:
		return false
	var order: Array = features.duplicate()
	order.remove_at(old)
	order.insert(new_index, f)
	for i in order.size():
		var g: CadFeature = order[i]
		for pid in parents_of(g):
			var j := -1
			for k in order.size():
				if order[k].id == pid:
					j = k
					break
			if j > i:
				return false
	return true


func move_feature(id: int, new_index: int) -> bool:
	if not can_move(id, new_index):
		return false
	var f := get_feature(id)
	features.erase(f)
	features.insert(new_index, f)
	return true


func sketches() -> Array:
	var out := []
	for f in features:
		if f.is_sketch():
			out.append(f)
	return out


## Özelliği siler. Taslak silinirse onu kullanan özellikler de silinir.
func remove_feature(id: int) -> void:
	var f := get_feature(id)
	if f == null:
		return
	if f.is_sketch():
		for c in consumers_of(id):
			features.erase(c)
	features.erase(f)


# ---------------------------------------------------------------- geri al / yinele

## Bir değişiklikten ÖNCE çağrılır.
func checkpoint() -> void:
	_undo.append(to_dict())
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


## Bir değişiklikten SONRA çağrılır.
func commit() -> void:
	dirty = true
	changed.emit()


## Son checkpoint'i iptal eder (değişiklik vazgeçildiyse).
func drop_checkpoint() -> void:
	if not _undo.is_empty():
		_undo.pop_back()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(to_dict())
	load_dict(_undo.pop_back(), false)
	dirty = true
	changed.emit()
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(to_dict())
	load_dict(_redo.pop_back(), false)
	dirty = true
	changed.emit()
	return true


# ---------------------------------------------------------------- serileştirme

func to_dict() -> Dictionary:
	var fl := []
	for f in features:
		fl.append(f.to_dict())
	return {
		"format": FORMAT,
		"version": VERSION,
		"part_name": part_name,
		"units": Units.to_dict(),
		"material": material,
		"variables": variables.duplicate(true),
		"next_id": next_id,
		"counters": counters.duplicate(),
		"rollback": rollback,
		"features": fl,
		"drawings": drawings.duplicate(true),
		"configs": configs.duplicate(true),
		"active_config": active_config,
	}


func load_dict(d: Dictionary, reset_history := true) -> void:
	features.clear()
	for fd in d.get("features", []):
		features.append(CadFeature.from_dict(fd))
	next_id = int(d.get("next_id", 1))
	rollback = int(d.get("rollback", -1))
	counters = {}
	var c: Dictionary = d.get("counters", {})
	for k in c:
		counters[k] = int(c[k])
	part_name = str(d.get("part_name", "Parça1"))
	material = str(d.get("material", ""))
	variables = []
	for v in d.get("variables", []):
		variables.append({"name": str(v.get("name", "")), "expr": str(v.get("expr", ""))})
	drawings = (d.get("drawings", []) as Array).duplicate(true) if d.get("drawings", []) is Array else []
	configs = (d.get("configs", []) as Array).duplicate(true) if d.get("configs", []) is Array else []
	active_config = str(d.get("active_config", ""))
	var u = d.get("units", {})
	Units.apply_dict(u if u is Dictionary else {})
	if reset_history:
		_undo.clear()
		_redo.clear()


func clear() -> void:
	load_dict({})
	file_path = ""
	dirty = false
	changed.emit()


func save_to(path: String) -> Error:
	var err := write_copy(path)
	if err != OK:
		return err
	doc_kind = str(KIND_BY_EXT.get(path.get_extension().to_lower(), "part"))
	file_path = path
	part_name = path.get_file().get_basename()
	dirty = false
	changed.emit()
	return OK


## Belgenin bir kopyasını yazar (belge durumu değişmez); dosya türü uzantıdan: .dcad / .dcadt / .ddrw / .ddrwt / .dclfp / .dcftp
func write_copy(path: String) -> Error:
	var d := to_dict()
	d["doc_kind"] = str(KIND_BY_EXT.get(path.get_extension().to_lower(), "part"))
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_string(JSON.stringify(d, "\t"))
	fa.close()
	return OK


func load_from(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or data.get("format", "") != FORMAT:
		return ERR_FILE_CORRUPT
	load_dict(data)
	doc_kind = str(data.get("doc_kind", KIND_BY_EXT.get(path.get_extension().to_lower(), "part")))
	file_path = path
	part_name = path.get_file().get_basename()
	dirty = false
	changed.emit()
	return OK
