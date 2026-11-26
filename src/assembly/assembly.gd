class_name CadAssembly
extends RefCounted
## Montaj belgesi (Faz 7): bileşenler (parça dosyası veya bağlantı elemanı + dönüşüm), eşleştirmeler,
## patlatma adımları. Dosya: `.dasm` (JSON). Parça yolları montaj dosyasına göre göreli saklanır.
##
## Bileşen: {id, name, src: {path} | {toolbox: spec}, xf: Transform3D, fixed, hidden, suppressed}
## Eşleştirme: {id, name, type, refs: [ref...], value, align, flip, min, max, ratio, suppressed, error, ref_xf}
## Referans: {comp, kind: face|edge|plane|axis|point, name, fid, geo: {t, p, d|n, r}} (geo bileşen yerel koordinatında)

signal changed

const FORMAT := "DIY.CAD-ASM"
const VERSION := 1
const MAX_UNDO := 100

## Eşleştirme türleri: [ad, gereken referans sayısı, değer türü ("" | length | angle | ratio)]
const MATE_TYPES := {
	"coincident": ["Çakışık", 2, ""], "parallel": ["Paralel", 2, ""], "perpendicular": ["Dik", 2, ""],
	"tangent": ["Teğet", 2, ""], "concentric": ["Eş merkezli", 2, ""], "distance": ["Mesafe", 2, "length"],
	"angle": ["Açı", 2, "angle"], "lock": ["Kilit", 2, ""],
	"width": ["Genişlik", 4, ""], "symmetric": ["Simetrik", 3, ""], "limit_distance": ["Mesafe sınırı", 2, "length"],
	"limit_angle": ["Açı sınırı", 2, "angle"], "hinge": ["Menteşe", 4, ""], "gear": ["Dişli", 2, "ratio"],
	"rack": ["Kremayer-pinyon", 2, "length"], "screw": ["Vida", 2, "length"], "slot": ["Kanal", 2, ""],
	"cam": ["Kam", 2, ""],
}
const STANDARD_MATES := ["coincident", "parallel", "perpendicular", "tangent", "concentric", "distance", "angle", "lock"]
const ADVANCED_MATES := ["width", "symmetric", "limit_distance", "limit_angle", "slot"]
const MECHANICAL_MATES := ["hinge", "gear", "rack", "screw", "cam"]

var name := "Montaj1"
var file_path := ""
var dirty := false
var comps: Array = []
var mates: Array = []
var explode: Array = []      # [{id, comps: [id], dir: [x,y,z], dist}]
var exploded := false
var patterns: Array = []     # bileşen çoğaltmaları [{id, name, type, seeds, dir, count, spacing, total, skip}]
var drawings: Array = []     # montaj teknik resim sayfaları (Drawing.new_sheet)
var material := ""           # resim anteti uyumluluğu için (montajın malzemesi yok)
var part_name: String:
	get:
		return name
var next_id := 1
var counters := {}

var _undo: Array = []
var _redo: Array = []


# ---------------------------------------------------------------- bileşenler

func new_id() -> int:
	var id := next_id
	next_id += 1
	return id


func get_comp(id: int) -> Dictionary:
	for c in comps:
		if int(c["id"]) == id:
			return c
	return {}


func get_mate(id: int) -> Dictionary:
	for m in mates:
		if int(m["id"]) == id:
			return m
	return {}


static func part_key(src: Dictionary, base_dir := "") -> String:
	if src.has("toolbox"):
		return "tb:" + JSON.stringify(src["toolbox"], "", true)
	return "file:" + resolve_path(str(src.get("path", "")), base_dir)


static func resolve_path(p: String, base_dir: String) -> String:
	if p == "" or p.is_absolute_path() or base_dir == "":
		return p.simplify_path()
	return base_dir.path_join(p).simplify_path()


func base_dir() -> String:
	return file_path.get_base_dir() if file_path != "" else ""


func key_of(c: Dictionary) -> String:
	return part_key(c.get("src", {}), base_dir())


func add_component(src: Dictionary, xf: Transform3D, display: String) -> Dictionary:
	counters[display] = int(counters.get(display, 0)) + 1
	var c := {"id": new_id(), "name": "%s<%d>" % [display, counters[display]], "src": src, "xf": xf,
		"fixed": comps.is_empty(), "hidden": false, "suppressed": false}
	comps.append(c)
	return c


func add_mate(type: String, refs: Array, extra := {}) -> Dictionary:
	var label: String = MATE_TYPES.get(type, [type])[0]
	counters["mate:" + type] = int(counters.get("mate:" + type, 0)) + 1
	var m := {"id": new_id(), "name": "%s%d" % [label, counters["mate:" + type]], "type": type, "refs": refs,
		"value": 0.0, "align": "", "flip": false, "suppressed": false, "error": ""}
	m.merge(extra, true)
	mates.append(m)
	return m


## Bileşenin eşleştirmeleri
func mates_of(comp_id: int) -> Array:
	var out: Array = []
	for m in mates:
		for r in m["refs"]:
			if int(r.get("comp", -1)) == comp_id:
				out.append(m)
				break
	return out


func remove_component(id: int) -> void:
	# Çoğaltma: çekirdek silinirse çoğaltma ve örnekleri, örnek silinirse atlanır
	var c0 := get_comp(id)
	if c0.has("pattern"):
		var pt := get_pattern(int(c0["pattern"]))
		if not pt.is_empty():
			(pt["skip"] as Array).append(c0["pidx"])
	for pt2 in patterns.duplicate():
		if id in pt2["seeds"]:
			remove_pattern(int(pt2["id"]))
	var keep: Array = []
	for c in comps:
		if int(c["id"]) != id:
			keep.append(c)
	comps = keep
	var km: Array = []
	for m in mates:
		var uses := false
		for r in m["refs"]:
			if int(r.get("comp", -1)) == id:
				uses = true
		if not uses:
			km.append(m)
	mates = km
	for st in explode:
		(st["comps"] as Array).erase(id)


func get_pattern(id: int) -> Dictionary:
	for p in patterns:
		if int(p["id"]) == id:
			return p
	return {}


func pattern_instances(pid: int) -> Array:
	var out: Array = []
	for c in comps:
		if int(c.get("pattern", -1)) == pid:
			out.append(c)
	return out


func remove_pattern(pid: int) -> void:
	var keep: Array = []
	var gone: Array = []
	for c in comps:
		if int(c.get("pattern", -1)) == pid:
			gone.append(int(c["id"]))
		else:
			keep.append(c)
	comps = keep
	var kp: Array = []
	for p in patterns:
		if int(p["id"]) != pid:
			kp.append(p)
	patterns = kp
	var km: Array = []
	for m in mates:
		var uses := false
		for r in m["refs"]:
			if int(r.get("comp", -1)) in gone:
				uses = true
		if not uses:
			km.append(m)
	mates = km


func remove_mate(id: int) -> void:
	var keep: Array = []
	for m in mates:
		if int(m["id"]) != id:
			keep.append(m)
	mates = keep


## Montaj malzeme listesi: aynı parça (anahtar) gruplanır. Dönüş: [{key, name, qty, comps: [id]}]
func bom() -> Array:
	var rows: Array = []
	var by := {}
	for c in comps:
		if bool(c.get("suppressed", false)):
			continue
		var k := key_of(c)
		if not by.has(k):
			by[k] = {"key": k, "name": str(c["name"]).get_slice("<", 0), "qty": 0, "comps": []}
			rows.append(by[k])
		by[k]["qty"] += 1
		by[k]["comps"].append(int(c["id"]))
	return rows


# ---------------------------------------------------------------- geri al / yinele

func checkpoint() -> void:
	_undo.append(to_dict())
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func commit() -> void:
	dirty = true
	changed.emit()


func drop_checkpoint() -> void:
	if not _undo.is_empty():
		_undo.pop_back()


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

static func xf_to_array(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t.origin.x, t.origin.y, t.origin.z]


static func xf_from_array(a: Variant) -> Transform3D:
	if a is Transform3D:
		return a
	if not (a is Array) or (a as Array).size() < 12:
		return Transform3D.IDENTITY
	var b := Basis(Vector3(float(a[0]), float(a[1]), float(a[2])), Vector3(float(a[3]), float(a[4]), float(a[5])), Vector3(float(a[6]), float(a[7]), float(a[8])))
	return Transform3D(b.orthonormalized(), Vector3(float(a[9]), float(a[10]), float(a[11])))


## Bileşen yolunu montaj dosyasına göre göreli yapar (aynı sürücüdeyse).
func _rel_path(p: String) -> String:
	var bd := base_dir()
	if bd == "" or p == "" or not p.is_absolute_path():
		return p
	var a := p.simplify_path().replace("\\", "/")
	var b := bd.simplify_path().replace("\\", "/")
	if a.get_slice("/", 0).to_lower() != b.get_slice("/", 0).to_lower():
		return p
	var pa := a.split("/")
	var pb := b.split("/")
	var i := 0
	while i < pa.size() and i < pb.size() and pa[i].to_lower() == pb[i].to_lower():
		i += 1
	var parts: Array = []
	for _k in range(i, pb.size()):
		parts.append("..")
	for k in range(i, pa.size()):
		parts.append(pa[k])
	return "/".join(parts)


func to_dict(for_file := false) -> Dictionary:
	var cl: Array = []
	for c in comps:
		var d: Dictionary = c.duplicate(true)
		d["xf"] = xf_to_array(c["xf"])
		if for_file and d["src"].has("path"):
			d["src"] = {"path": _rel_path(resolve_path(str(d["src"]["path"]), base_dir()))}
		cl.append(d)
	var ml: Array = []
	for m in mates:
		var d2: Dictionary = m.duplicate(true)
		d2.erase("_rt")
		ml.append(d2)
	return {"format": FORMAT, "version": VERSION, "name": name, "comps": cl, "mates": ml,
		"explode": explode.duplicate(true), "exploded": exploded, "next_id": next_id, "counters": counters.duplicate(),
		"patterns": patterns.duplicate(true), "drawings": drawings.duplicate(true)}


func load_dict(d: Dictionary, reset_history := true) -> void:
	name = str(d.get("name", "Montaj1"))
	comps = []
	for cd in d.get("comps", []):
		var c: Dictionary = (cd as Dictionary).duplicate(true)
		c["id"] = int(c.get("id", 0))
		c["xf"] = xf_from_array(c.get("xf", []))
		c["fixed"] = bool(c.get("fixed", false))
		c["hidden"] = bool(c.get("hidden", false))
		c["suppressed"] = bool(c.get("suppressed", false))
		if c.has("pattern"):
			c["pattern"] = int(c["pattern"])
			c["pidx"] = [int(c["pidx"][0]), int(c["pidx"][1])]
		comps.append(c)
	mates = []
	for md in d.get("mates", []):
		var m: Dictionary = (md as Dictionary).duplicate(true)
		m["id"] = int(m.get("id", 0))
		for r in m.get("refs", []):
			r["comp"] = int(r.get("comp", -1))
		mates.append(m)
	explode = (d.get("explode", []) as Array).duplicate(true)
	patterns = (d.get("patterns", []) as Array).duplicate(true)
	for p in patterns:
		p["id"] = int(p["id"])
		var sd: Array = []
		for x in p.get("seeds", []):
			sd.append(int(x))
		p["seeds"] = sd
		if not p.has("skip"):
			p["skip"] = []
	drawings = (d.get("drawings", []) as Array).duplicate(true) if d.get("drawings", []) is Array else []
	exploded = bool(d.get("exploded", false))
	next_id = int(d.get("next_id", 1))
	counters = {}
	var cc: Dictionary = d.get("counters", {})
	for k in cc:
		counters[k] = int(cc[k])
	if reset_history:
		_undo.clear()
		_redo.clear()


func save_to(path: String) -> Error:
	var old := file_path
	file_path = path
	if old != "" and old.get_base_dir() != path.get_base_dir():
		# Göreli yollar yeni konuma göre yeniden yazılır: önce mutlak yap
		for c in comps:
			if c["src"].has("path"):
				c["src"]["path"] = resolve_path(str(c["src"]["path"]), old.get_base_dir())
	var old_name := name
	if name == "" or (name.begins_with("Montaj") and name.substr(6).is_valid_int()):
		name = path.get_file().get_basename()
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		file_path = old
		name = old_name
		return FileAccess.get_open_error()
	fa.store_string(JSON.stringify(to_dict(true), "  "))
	fa.close()
	dirty = false
	return OK


func load_from(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or str(data.get("format", "")) != FORMAT:
		return ERR_FILE_UNRECOGNIZED
	load_dict(data)
	file_path = path
	dirty = false
	changed.emit()
	return OK
