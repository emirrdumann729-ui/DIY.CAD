class_name MacroApi
extends RefCounted
## Makro / otomasyon API'si (Faz 9). Makro, `func run(m: MacroApi)` içeren bir GDScript dosyasıdır:
##
##   extends RefCounted
##   func run(m: MacroApi) -> void:
##       m.new_part("Flans")
##       var s := m.sketch("top")
##       s.circle(Vector2.ZERO, 40)
##       m.extrude(s, 10)
##       await m.rebuild()
##       m.message("Hacim: %.1f" % m.volume())
##
## Makrolar tüm uygulamaya erişir (m.app, m.doc); yalnız güvendiğiniz makroları çalıştırın.
## Kayıt: Araçlar → Makro kaydı — kayıt süresince eklenen özellikler `m.add_raw(...)` çağrılarına dönüştürülür.

var app: Node
var doc: CadDocument
var messages: PackedStringArray = []
var running := false
var _rec_ids := {}            # kayıt başındaki özellik kimlikleri
var recording := false


class MacroSketch:
	extends RefCounted
	## Taslak yardımcıları (koordinatlar taslak düzleminde, mm)
	var feature: CadFeature
	var sk: Sketch

	func _init(f: CadFeature) -> void:
		feature = f
		sk = f.sketch

	func point(p: Vector2) -> int:
		return sk.add_point(p)

	func line(a: Vector2, b: Vector2, construction := false) -> int:
		return sk.add_line(sk.add_point(a), sk.add_point(b), construction)

	func polyline(pts: Array, closed := true) -> Array:
		var ids: Array = []
		for p in pts:
			ids.append(sk.add_point(p))
		var out: Array = []
		var n := ids.size()
		for i in (n if closed else n - 1):
			out.append(sk.add_line(ids[i], ids[(i + 1) % n]))
		return out

	func rect(a: Vector2, b: Vector2) -> int:
		return sk.add_rect([sk.add_point(Vector2(a.x, a.y)), sk.add_point(Vector2(b.x, a.y)), sk.add_point(Vector2(b.x, b.y)), sk.add_point(Vector2(a.x, b.y))])

	func center_rect(c: Vector2, size: Vector2) -> int:
		return rect(c - size * 0.5, c + size * 0.5)

	func circle(c: Vector2, r: float) -> int:
		return sk.add_circle(sk.add_point(c), r)

	## Merkez + başlangıç + bitiş noktalı yay (saat yönünün tersine)
	func arc(c: Vector2, a: Vector2, b: Vector2) -> int:
		return sk.add_arc(sk.add_point(c), sk.add_point(a), sk.add_point(b))

	func polygon(c: Vector2, r: float, n: int, angle_deg := 90.0) -> Array:
		var pts: Array = []
		for i in n:
			var a := deg_to_rad(angle_deg) + TAU * i / n
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		return polyline(pts, true)

	func slot(a: Vector2, b: Vector2, width: float) -> void:
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x) * width * 0.5
		var p1 := sk.add_point(a - nrm)
		var p2 := sk.add_point(b - nrm)
		var p3 := sk.add_point(b + nrm)
		var p4 := sk.add_point(a + nrm)
		sk.add_line(p1, p2)
		sk.add_arc(sk.add_point(b), p2, p3)
		sk.add_line(p3, p4)
		sk.add_arc(sk.add_point(a), p4, p1)

	func spline(pts: Array) -> int:
		var ids: Array = []
		for p in pts:
			ids.append(sk.add_point(p))
		return sk.add_spline(ids)


func _init(a: Node) -> void:
	app = a
	doc = a.doc


# ---------------------------------------------------------------- belge

func new_part(part_name := "") -> void:
	app._new_document()
	doc = app.doc
	if part_name != "":
		doc.part_name = part_name


func open(path: String) -> bool:
	app._pending_file_action = "open"
	app._on_file_selected(path)
	return doc.file_path == path


func save(path := "") -> bool:
	var p := path if path != "" else doc.file_path
	if p == "":
		return false
	if p.get_extension().to_lower() != "dcad":
		p += ".dcad"
	var ok := doc.save_to(p) == OK
	if ok:
		app._note_file(p, "part")
	return ok


func set_material(material_name: String) -> void:
	doc.material = material_name


## Global değişken (Denklemler); varsa değeri değişir
func set_variable(var_name: String, expr: Variant) -> void:
	for v in doc.variables:
		if v["name"] == var_name:
			v["expr"] = str(expr)
			return
	doc.variables.append({"name": var_name, "expr": str(expr)})


## Mesaj: durum çubuğu + konsol + sonuç listesi
func message(msg: Variant) -> void:
	var s := str(msg)
	messages.append(s)
	print("[makro] ", s)
	app._set_status(s)


# ---------------------------------------------------------------- taslak ve özellikler

func _add(f: CadFeature) -> CadFeature:
	doc.add_feature(f)
	return f


## Standart düzlemde ("front" | "top" | "right") taslak; offset: düzlem normali boyunca
func sketch(plane := "front", offset := 0.0) -> MacroSketch:
	var pl := SketchPlane.standard(plane)
	if pl == null:
		pl = SketchPlane.standard("front")
	if absf(offset) > 0.0:
		pl = SketchPlane.make(pl.name + " + %s" % str(offset), pl.origin + pl.normal() * offset, pl.x_dir, pl.y_dir)
	var f := doc.new_feature("sketch", "Taslak")
	f.plane = pl
	f.sketch = Sketch.new()
	_add(f)
	return MacroSketch.new(f)


## Uzaydaki bir noktadan ve normalden taslak (ör. bir yüzün üstüne)
func sketch_at(point: Vector3, normal: Vector3) -> MacroSketch:
	var f := doc.new_feature("sketch", "Taslak")
	f.plane = SketchPlane.from_face(point, normal)
	f.sketch = Sketch.new()
	_add(f)
	return MacroSketch.new(f)


func _sid(s: Variant) -> int:
	if s is MacroSketch:
		return (s as MacroSketch).feature.id
	if s is CadFeature:
		return (s as CadFeature).id
	return int(s)


## Ekstrüzyon. opts: end ("blind" | "midplane" | "through"), reverse, ... (özellik parametreleri)
func extrude(s: Variant, depth: float, opts := {}) -> CadFeature:
	var f := doc.new_feature("extrude", "Ekstrüzyon")
	f.params = {"sketch": _sid(s), "depth": depth, "end": "blind", "reverse": false, "cut": false}
	f.params.merge(opts, true)
	return _add(f)


func cut(s: Variant, depth := 10.0, opts := {}) -> CadFeature:
	var f := doc.new_feature("extrude", "Ekstrüzyon-Kesme")
	f.params = {"sketch": _sid(s), "depth": depth, "end": "blind", "reverse": false, "cut": true}
	f.params.merge(opts, true)
	return _add(f)


func cut_through(s: Variant) -> CadFeature:
	return cut(s, 10.0, {"end": "through"})


## Döndürme: eksen "y" / "x" (taslak eksenleri) ya da yapı çizgisi kimliği
func revolve(s: Variant, angle := 360.0, axis: Variant = "y", opts := {}) -> CadFeature:
	var f := doc.new_feature("revolve", "Döndürme")
	f.params = {"sketch": _sid(s), "angle": angle, "axis": axis, "reverse": false, "cut": false}
	f.params.merge(opts, true)
	return _add(f)


## Genel özellik (tür ve parametreler, CadFeature.params biçiminde)
func feature(type: String, params: Dictionary, prefix := "") -> CadFeature:
	var probe := CadFeature.new()
	probe.type = type
	var f := doc.new_feature(type, prefix if prefix != "" else probe.type_label())
	f.params = params.duplicate(true)
	return _add(f)


func find(feature_name: String) -> CadFeature:
	for f in doc.features:
		if f.name == feature_name:
			return f
	return null


func suppress(feature_name: String, on := true) -> void:
	var f := find(feature_name)
	if f != null:
		f.suppressed = on


## Değişiklikleri uygula ve model yeniden oluşturulana kadar bekle (await m.rebuild())
func rebuild() -> void:
	doc.commit()
	var tree: SceneTree = app.get_tree()
	await tree.process_frame
	var t0 := Time.get_ticks_msec()
	while app.viewport.kernel.is_busy() and Time.get_ticks_msec() - t0 < 900000:   # büyük STL içe aktarma dakikalar sürebilir
		await tree.process_frame
	await tree.process_frame


func volume() -> float:
	return app.viewport.model.volume_and_area().x


func area() -> float:
	return app.viewport.model.volume_and_area().y


func cmd(id: String) -> void:
	if not app.run_command(id):
		app._cmd(id)


func view(view_name := "iso") -> void:
	app.viewport.camera.set_standard_view(view_name, false)
	app._fit(false)


## Dışa aktar: uzantıya göre STL / OBJ / STEP / IGES / PNG
func export(path: String) -> void:
	var ext := path.get_extension().to_lower()
	var action: String = {"stl": "stl", "obj": "obj", "step": "step", "stp": "step", "iges": "iges", "igs": "iges", "png": "png"}.get(ext, "")
	if action == "":
		message("Bilinmeyen dışa aktarma uzantısı: " + ext)
		return
	var k: GeoKernel = app.viewport.kernel
	var asyncx: bool = action in ["stl", "step", "iges"] and k.is_brep() and k.occ.is_ready()
	app._pending_file_action = action
	app._on_file_selected(path)
	if asyncx:
		await k.export_done


# ---------------------------------------------------------------- kayıtla gelen özellikler

const _INT_KEYS := ["sketch"]
const _LIST_KEYS := ["sketches", "features", "seeds"]
const _REF_DICT_KEYS := ["path", "guide", "curve"]


static func _remap_str(s: String, ids: Dictionary) -> String:
	if s.length() > 2 and s[0] == "F" and s.contains(":"):
		var num := s.substr(1, s.find(":") - 1)
		if num.is_valid_int() and ids.has(int(num)):
			return "F%d%s" % [ids[int(num)], s.substr(s.find(":"))]
	elif s.begins_with("pl:") or s.begins_with("ax:"):
		var n2 := s.substr(3)
		if n2.is_valid_int() and ids.has(int(n2)):
			return s.substr(0, 3) + str(ids[int(n2)])
	return s


static func _remap(v: Variant, ids: Dictionary, key := "") -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _remap(v[k], ids, str(k))
		if key in _REF_DICT_KEYS and out.has("id") and ids.has(int(out["id"])):
			out["id"] = ids[int(out["id"])]
		return out
	if v is Array:
		var arr: Array = []
		for x in v:
			if key in _LIST_KEYS and (x is int or x is float) and ids.has(int(x)):
				arr.append(ids[int(x)])
			else:
				arr.append(_remap(x, ids, key))
		return arr
	if v is String:
		return _remap_str(v, ids)
	if key in _INT_KEYS and (v is int or v is float) and ids.has(int(v)):
		return ids[int(v)]
	return v


## Kaydedilmiş özellik sözlüğünü ekle. Kimlik doluysa yeni kimlik verilir ve sonraki başvurular `ids` ile eşlenir.
func add_raw(d: Dictionary, ids := {}) -> CadFeature:
	var dd: Dictionary = d.duplicate(true)
	var old := int(dd.get("id", 0))
	if old <= 0 or doc.get_feature(old) != null or ids.has(old):
		ids[old] = doc.next_id
		doc.next_id += 1
	if not ids.is_empty():
		dd["params"] = _remap(dd.get("params", {}), ids)
		if dd.get("plane") is Dictionary:
			dd["plane"] = _remap(dd["plane"], ids)
			if int(dd["plane"].get("ref", -1)) >= 0 and ids.has(int(dd["plane"]["ref"])):
				dd["plane"]["ref"] = ids[int(dd["plane"]["ref"])]
	var f := CadFeature.from_dict(dd)
	if ids.has(old):
		f.id = int(ids[old])
	doc.next_id = maxi(doc.next_id, f.id + 1)
	return _add(f)


# ---------------------------------------------------------------- çalıştırma ve kayıt

## Makro kaynağını çalıştır. Dönüş: {ok, error, messages}
func run_source(src: String, label := "makro") -> Dictionary:
	if running:
		return {"ok": false, "error": "Bir makro zaten çalışıyor"}
	var s := GDScript.new()
	s.source_code = src
	if s.reload() != OK:
		return {"ok": false, "error": "Makro derlenemedi (sözdizimi hatası, konsol çıktısına bakın): " + label}
	var obj: Object = s.new()
	if obj == null or not obj.has_method("run"):
		return {"ok": false, "error": "Makroda 'func run(m: MacroApi)' yok: " + label}
	messages = []
	running = true
	doc = app.doc
	doc.checkpoint()
	await obj.run(self)
	doc = app.doc
	doc.commit()
	running = false
	return {"ok": true, "error": "", "messages": messages}


func run_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Makro dosyası bulunamadı: " + path}
	return await run_source(FileAccess.get_file_as_string(path), path.get_file())


func start_recording() -> void:
	_rec_ids = {}
	for f in app.doc.features:
		_rec_ids[f.id] = true
	recording = true


## Kaydı bitir; eklenen özelliklerden makro kaynağı üret ("" hiçbir şey eklenmediyse)
func stop_recording() -> String:
	recording = false
	var added: Array = []
	for f in app.doc.features:
		if not _rec_ids.has(f.id):
			added.append(f)
	if added.is_empty():
		return ""
	return _source_for(added, false)


## Tüm parçayı yeniden kuran makro
func part_macro() -> String:
	return _source_for(app.doc.features, true)


func _source_for(feats: Array, whole: bool) -> String:
	var d: CadDocument = app.doc
	var lines: PackedStringArray = []
	lines.append("extends RefCounted")
	lines.append("## DIY.CAD makrosu — %s (%s)" % ["parça: " + d.part_name if whole else "kayıt", Time.get_datetime_string_from_system(false, true)])
	lines.append("## Araçlar → Makro çalıştır ile oynatın. API: src/core/macro_api.gd")
	lines.append("")
	lines.append("")
	lines.append("func run(m: MacroApi) -> void:")
	if whole:
		lines.append("\tm.new_part(%s)" % JSON.stringify(d.part_name))
		if d.material != "":
			lines.append("\tm.set_material(%s)" % JSON.stringify(d.material))
		for v in d.variables:
			lines.append("\tm.set_variable(%s, %s)" % [JSON.stringify(str(v["name"])), JSON.stringify(str(v["expr"]))])
	lines.append("\tvar ids := {}")
	for f in feats:
		lines.append("\tm.add_raw(%s, ids)" % JSON.stringify((f as CadFeature).to_dict()))
	lines.append("\tawait m.rebuild()")
	lines.append("\tm.message(\"Makro tamamlandı: %d özellik\")" % feats.size())
	return "\n".join(lines) + "\n"
