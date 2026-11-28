class_name CsgKernel
extends Node3D
## Geometri çekirdeği (Faz 1): özellik ağacını Godot CSG (Manifold) ile katı modele çevirir.
## Faz 4'te aynı arayüzle (rebuild -> built sinyali) OpenCASCADE tabanlı B-rep çekirdeği gelecek.
##
## Not: CSG ağacı bir sonraki karede hesaplandığı için sonuç `built` sinyaliyle gelir.

signal built(mesh: ArrayMesh)

const THROUGH_ALL := 10000.0

var _root: CSGCombiner3D
var _pending := false
var _wait := 0


## Belgeyi yeniden oluşturur. preview: henüz belgeye eklenmemiş (veya düzenlenen) özellik.
func rebuild(doc: CadDocument, preview: CadFeature = null) -> void:
	if _root:
		remove_child(_root)
		_root.free()
	_root = CSGCombiner3D.new()
	_root.visible = false
	add_child(_root)
	var list: Array = doc.active_features()
	if preview != null:
		var idx := doc.index_of(preview.id)
		if idx >= 0 and idx < list.size():
			list[idx] = preview
		else:
			list.append(preview)
	for f in list:
		f.error = ""
		if f.suppressed or f.is_sketch() or f.type == "sketch3d" or f.is_reference():
			continue
		if f.type == "extrude" and (str(f.params.get("end", "blind")) in FeatureGeom.UNTIL_ENDS or float(f.params.get("thin", 0.0)) > 0.0
				or float(f.params.get("draft", 0.0)) != 0.0 or bool(f.params.get("dir2", false))):
			f.error = I18n.t("Bu ekstrüzyon seçenekleri OpenCASCADE (B-rep) çekirdeği gerektirir")
			continue
		if f.type == "import" and StlImport.is_stl(str(f.params.get("path", ""))):
			_add_stl(f)
			continue
		if f.type in GeoKernel.BREP_ONLY:
			f.error = I18n.t("Bu özellik OpenCASCADE (B-rep) çekirdeği gerektirir")
			continue
		var sk_f := doc.get_feature(f.sketch_ref())
		if sk_f == null or sk_f.sketch == null:
			f.error = I18n.t("Taslak bulunamadı")
			continue
		var loops: Array = []
		var regions = f.params.get("regions", [])
		if regions is Array and not (regions as Array).is_empty():
			loops = region_loops(sk_f.sketch, regions)
			if loops.is_empty():
				f.error = I18n.t("Seçili bölgeler bulunamadı (taslak değişmiş olabilir)")
				continue
		else:
			var prof := sk_f.sketch.extract_profiles()
			loops = prof["loops"]
			if loops.is_empty():
				f.error = I18n.t("Taslakta kapalı kontur yok")
				continue
		match f.type:
			"extrude":
				_add_extrude(f, sk_f.plane, loops)
			"revolve":
				_add_revolve(f, sk_f, loops, doc)
	_pending = true
	_wait = 0


func is_busy() -> bool:
	return _pending


func _process(_delta: float) -> void:
	if not _pending:
		return
	_wait += 1
	if _wait < 2:
		return
	_pending = false
	var mesh: ArrayMesh = null
	if _root and _root.get_child_count() > 0:
		mesh = _root.bake_static_mesh()
	built.emit(mesh)


func _make_group(cut: bool) -> CSGCombiner3D:
	var g := CSGCombiner3D.new()
	g.operation = CSGShape3D.OPERATION_SUBTRACTION if cut else CSGShape3D.OPERATION_UNION
	return g


static func _ccw(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate()
	if Sketch.polygon_area(q) < 0.0:
		q.reverse()
	return q


## Seçili bölgelerden (örnek noktalar) kontur listesi: {poly, depth (0 dış / 1 delik), region}
static func region_loops(sk: Sketch, samples: Array) -> Array:
	var fs := SketchRegions.faces(sk)
	var chosen: Array = []
	for s in samples:
		var p := Vector2(float(s[0]), float(s[1])) if s is Array else (s as Vector2)
		var fi := SketchRegions.face_at(fs, p)
		if fi >= 0 and not (fi in chosen):
			chosen.append(fi)
	var out: Array = []
	for ri in chosen.size():
		var face: Dictionary = fs[chosen[ri]]
		out.append({"poly": _ccw(face["outer"]), "depth": 0, "region": ri})
		for h in face["holes"]:
			out.append({"poly": _ccw(h), "depth": 1, "region": ri})
	return out


## Konturları gruba ekler. Bölge modunda her bölge kendi alt birleştiricisinde (dış - delikler).
func _fill_group(group: CSGCombiner3D, loops: Array, make_poly: Callable) -> void:
	var subs := {}
	for L in loops:
		var poly: CSGPolygon3D = make_poly.call(L)
		poly.operation = CSGShape3D.OPERATION_UNION if int(L["depth"]) % 2 == 0 else CSGShape3D.OPERATION_SUBTRACTION
		if L.has("region"):
			var ri: int = L["region"]
			if not subs.has(ri):
				var sub := CSGCombiner3D.new()
				sub.operation = CSGShape3D.OPERATION_UNION
				group.add_child(sub)
				subs[ri] = sub
			(subs[ri] as CSGCombiner3D).add_child(poly)
		else:
			group.add_child(poly)


## STL ağ gövdesi (Faz 9+): dönüştürülüp birleşime eklenir
var _stl_cache := {}

func _add_stl(f: CadFeature) -> void:
	var path := str(f.params.get("path", ""))
	if not FileAccess.file_exists(path):
		f.error = "Dosya bulunamadı: " + path
		return
	var x := StlImport.xform_of(f.params)
	if str(x["error"]) != "":
		f.error = str(x["error"])
		return
	var key := path + "|" + str(FileAccess.get_modified_time(path))
	if not _stl_cache.has(key):
		_stl_cache.clear()
		_stl_cache[key] = StlImport.read(path)
	var tris: PackedVector3Array = _stl_cache[key]
	if tris.is_empty():
		f.error = I18n.t("STL okunamadı (üçgen yok)")
		return
	var cm := CSGMesh3D.new()
	cm.mesh = StlImport.to_mesh(StlImport.transformed(tris, f.params))
	cm.operation = CSGShape3D.OPERATION_UNION
	_root.add_child(cm)


func _add_extrude(f: CadFeature, plane: SketchPlane, loops: Array) -> void:
	var cut := f.is_cut()
	# Ortak kurallar (FeatureGeom): CSG çokgeni yerel -Z (= -normal) yönünde uzatır
	var g := FeatureGeom.extrude_vectors(f, plane)
	if g.has("error"):
		f.error = g["error"]
		return
	var vec: Vector3 = g["vec"]
	var depth := vec.length()
	var n := plane.normal()
	var o: Vector3 = plane.origin + (g["offset"] as Vector3)
	if vec.dot(n) > 0.0:
		o += vec
	var xf := Transform3D(plane.basis(), o)
	var group := _make_group(cut)
	var make := func(L: Dictionary) -> CSGPolygon3D:
		var poly := CSGPolygon3D.new()
		poly.polygon = L["poly"]
		poly.mode = CSGPolygon3D.MODE_DEPTH
		poly.depth = depth
		poly.transform = xf
		return poly
	_fill_group(group, loops, make)
	_root.add_child(group)


## Döndürme ekseni (taslak koordinatlarında iki nokta). Bulunamazsa boş dizi.
## axis: "x" | "y" | taslak çizgisi kimliği | "ax:<referans eksen>" (taslak düzleminde olmalı)
static func revolve_axis(sk_f: CadFeature, axis: Variant, doc: CadDocument = null) -> Array:
	if typeof(axis) == TYPE_STRING:
		if str(axis).begins_with("ax:"):
			if doc == null:
				return []
			var ra := RefGeom.resolve_axis(doc, axis)
			if ra.is_empty():
				return []
			var pl := sk_f.plane
			var o3: Vector3 = ra["o"]
			var d3: Vector3 = ra["d"]
			if absf(d3.dot(pl.normal())) > 1e-6 or absf((o3 - pl.origin).dot(pl.normal())) > 1e-4:
				return []
			return [pl.to_local(o3), pl.to_local(o3 + d3)]
		if axis == "x":
			return [Vector2.ZERO, Vector2.RIGHT]
		return [Vector2.ZERO, Vector2.UP]
	var e := sk_f.sketch.get_entity(int(axis))
	if e.is_empty() or e["type"] != "line":
		return []
	return [sk_f.sketch.points[e["a"]], sk_f.sketch.points[e["b"]]]


func _add_revolve(f: CadFeature, sk_f: CadFeature, loops: Array, doc: CadDocument = null) -> void:
	var p := f.params
	var ax := revolve_axis(sk_f, p.get("axis", "y"), doc)
	if ax.is_empty():
		f.error = I18n.t("Döndürme ekseni bulunamadı")
		return
	var a2: Vector2 = ax[0]
	var ad: Vector2 = (ax[1] - ax[0])
	if ad.length() < 1e-9:
		f.error = I18n.t("Döndürme ekseni geçersiz")
		return
	ad = ad.normalized()
	if bool(p.get("reverse", false)):
		ad = -ad
	var perp := Vector2(-ad.y, ad.x)
	var side := 0.0
	for L in loops:
		for q in L["poly"]:
			side += (q - a2).dot(perp)
	if side < 0.0:
		perp = -perp
	# Profil eksenin iki tarafına geçmemeli
	for L in loops:
		for q in L["poly"]:
			if (q - a2).dot(perp) < -1e-4:
				f.error = I18n.t("Profil döndürme ekseninin iki tarafında olamaz")
				return
	var plane := sk_f.plane
	var X3 := plane.dir_to_world(perp)
	var Y3 := plane.dir_to_world(ad)
	var Z3 := X3.cross(Y3)
	var xf := Transform3D(Basis(X3, Y3, Z3), plane.to_world(a2))
	var angle := clampf(float(p.get("angle", 360.0)), 0.1, 360.0)
	var rmax := 0.0
	for L in loops:
		for q in L["poly"]:
			rmax = maxf(rmax, (q - a2).dot(perp))
	var sides := maxi(3, int(ceil(Sketch.full_segments(rmax) * angle / 360.0 - 1e-6)))
	var group := _make_group(f.is_cut())
	var make := func(L: Dictionary) -> CSGPolygon3D:
		var local := PackedVector2Array()
		for q in L["poly"]:
			var d: Vector2 = q - a2
			local.append(Vector2(maxf(d.dot(perp), 0.0), d.dot(ad)))
		if Sketch.polygon_area(local) < 0.0:
			local.reverse()
		var poly := CSGPolygon3D.new()
		poly.polygon = local
		poly.mode = CSGPolygon3D.MODE_SPIN
		poly.spin_degrees = angle
		poly.spin_sides = sides
		poly.transform = xf
		return poly
	_fill_group(group, loops, make)
	_root.add_child(group)
