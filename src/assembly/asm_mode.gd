class_name AssemblyMode
extends Node
## Montaj modu denetleyicisi (Faz 7): araç çubuğu, özellik ağacı, özellik paneli, 3B seçim ve sürükleme,
## eşleştirme oluşturma, girişim tespiti, patlatılmış görünüm, malzeme listesi, bağlantı elemanları,
## hareket etüdü. Ana uygulama (`app`) montaj modundayken girdileri buraya yönlendirir.

var large_auto := true          # büyük montaj modu otomatik (Faz 9)
var large_mode := false
var app: Node
var asm: CadAssembly = null
var parts := {}            # parça anahtarı -> {doc, name, material, model, mesh, color, ver, ok, brep, error}
var view: AssemblyView
var toolbar: HFlowContainer
var tool := "select"
var sel := {}              # {kind: comp | mate, id}
var sel_comps: Array = []  # patlatma için çoklu seçim
var hover := -1
var mate_type := ""
var mate_refs: Array = []
var mate_opts := {"value": 10.0, "min": 0.0, "max": 20.0, "ratio_a": 1.0, "ratio_b": 1.0}
var last_solve := {}
var interf: Array = []     # [{a, b, volume, center, tris}]
var interf_state := ""     # "" | running | done | error
var explode_t := 0.0
var _explode_goal := 0.0
var ex_dir := 1            # patlatma yönü indeksi (EX_DIRS)
var ex_dist := 30.0
var tb_spec := {"type": "bolt", "size": "M8", "length": 30}
var motion := {"rpm": 30.0, "dur": 4.0, "ref": {}, "t": 0.0, "playing": false}
var _pending := 0
var _fit_after := false
var _drag := {}
var _press := {}
var _hl_tris := PackedVector3Array()
var _connected := false
var _fit_on_explode := false

const EX_DIRS := [["X+", Vector3.RIGHT], ["Y+", Vector3.UP], ["Z+", Vector3.BACK], ["X−", Vector3.LEFT], ["Y−", Vector3.DOWN], ["Z−", Vector3.FORWARD]]
const TOOL_HINTS := {
	"select": "Bileşene tıklayın: seç. Sol tuşla sürükleyin: eşleştirmelere uyarak taşı.",
	"mate": "Eşleştirilecek yüz / kenarlara tıklayın (ağaçtan ana düzlemler de seçilebilir); sonra paneldeki türü seçin.",
	"move": "Bileşeni sürükleyerek taşıyın veya panelden sayısal öteleme girin.",
	"rotate": "Bileşeni sürükleyerek döndürün (eşleştirmeler korunur) veya panelden açı girin.",
	"explode": "Patlatılacak bileşenlere tıklayın, yön ve mesafe seçip 'Adım ekle'.",
	"motion": "Motor: döndürülecek bileşenin silindirik yüzüne tıklayın, hız ve süreyi girip Oynat.",
	"pattern": "Çoğaltılacak bileşenlere tıklayın; yön, sayı ve aralığı panelden seçip Uygula.",
}


# ---------------------------------------------------------------- yaşam döngüsü

func is_open() -> bool:
	return asm != null


func _vp() -> CadViewport:
	return app.viewport


func _ensure() -> void:
	if view == null:
		view = AssemblyView.new()
		view.line_mat = _vp().line_mat
		_vp().world.add_child(view)
	if not _connected:
		_vp().kernel.part_built.connect(_on_part_built)
		_vp().kernel.asm_done.connect(_on_asm_done)
		_connected = true


func new_assembly() -> void:
	_ensure()
	close()
	asm = CadAssembly.new()
	asm.changed.connect(_on_asm_changed)
	enter()
	app._set_status("Yeni montaj. 'Bileşen Ekle' ile parça (.dcad) ekleyin; ilk bileşen sabitlenir.")


func open_file(path: String) -> Error:
	_ensure()
	var a := CadAssembly.new()
	var err := a.load_from(path)
	if err != OK:
		return err
	close()
	asm = a
	asm.changed.connect(_on_asm_changed)
	_fit_after = true
	enter()
	load_parts()
	return OK


## Otomatik kayıttan kurtarılan montajı aç (Faz 9)
func open_recovered(a: CadAssembly) -> void:
	_ensure()
	close()
	asm = a
	asm.dirty = true
	asm.changed.connect(_on_asm_changed)
	_fit_after = true
	enter()
	load_parts()


## Montaj moduna gir (yeni / açılan montaj veya parçadan dönüş)
func enter() -> void:
	_ensure()
	clear_context()
	app.enter_assembly_ui()
	view.visible = true
	tool = "select"
	refresh()
	update_title()


## Montaj ekranından çık (montaj bellekte kalır: parça düzenlemeye gidilirken)
func leave() -> void:
	_stop_motion()
	if view != null:
		view.visible = false
	_vp().clear_face_highlight()


func close() -> void:
	clear_context()
	leave()
	if view != null:
		view.clear()
	asm = null
	parts.clear()
	sel = {}
	interf.clear()
	explode_t = 0.0
	_explode_goal = 0.0


func update_title() -> void:
	if asm != null:
		app.get_window().title = asm.name + (" *" if asm.dirty else "") + I18n.t(" — DIY.CAD (Montaj)")


func _on_asm_changed() -> void:
	update_title()


# ---------------------------------------------------------------- parçalar

func load_parts(force_keys := []) -> void:
	if asm == null:
		return
	for c in asm.comps:
		_request(c.get("src", {}), asm.base_dir(), 0, force_keys)
	if _pending == 0:
		_after_parts_loaded()


## Parçayı (veya alt montajı ve onun parçalarını) yükleme / derleme isteği. Dönüş: parça anahtarı
func _request(src: Dictionary, base_dir: String, depth: int, force_keys: Array) -> String:
	var key := CadAssembly.part_key(src, base_dir)
	if parts.has(key) and not (key in force_keys):
		return key
	var path := CadAssembly.resolve_path(str(src.get("path", "")), base_dir) if not src.has("toolbox") else ""
	if path.get_extension().to_lower() == "dasm":
		_request_sub(key, path, depth, force_keys)
		return key
	var doc := _part_doc_src(src, base_dir)
	var p: Dictionary = parts.get(key, {"ver": 0})
	p["kind"] = "part"
	p["doc"] = doc
	p["ok"] = false
	p["error"] = "" if doc != null else I18n.t("Parça dosyası bulunamadı")
	if doc != null:
		p["name"] = doc.part_name
		p["material"] = doc.material
		if doc.material != "":
			p["color"] = Materials.color_of(doc.material)
		else:
			p.erase("color")
	parts[key] = p
	if doc != null:
		_pending += 1
		_vp().kernel.build_part(doc, key)
	return key


## Alt montaj: rijit grup. Alt bileşenlerin parçaları ayrı ayrı derlenir, sonra tek modelde birleştirilir.
func _request_sub(key: String, path: String, depth: int, force_keys: Array) -> void:
	var p: Dictionary = parts.get(key, {"ver": 0})
	p["kind"] = "asm"
	p["ok"] = false
	p["children"] = []
	p["error"] = ""
	parts[key] = p
	if depth > 6:
		p["error"] = I18n.t("Alt montaj iç içe çok derin (döngü?)")
		return
	var sub := CadAssembly.new()
	if sub.load_from(path) != OK:
		p["error"] = I18n.t("Alt montaj dosyası açılamadı")
		return
	p["name"] = sub.name
	p["sub_path"] = path
	for sc in sub.comps:
		if bool(sc.get("suppressed", false)):
			continue
		var ck := _request(sc.get("src", {}), sub.base_dir(), depth + 1, force_keys)
		p["children"].append({"key": ck, "xf": sc["xf"], "name": str(sc["name"]), "hidden": bool(sc.get("hidden", false))})


## Tüm alt parçaları hazır olan alt montajların birleşik modelini kurar (iç içe olanlar dahil).
func _compose_subs() -> void:
	var changed := true
	var guard := 0
	while changed and guard < 10:
		changed = false
		guard += 1
		for key in parts:
			var p: Dictionary = parts[key]
			if p.get("kind", "") != "asm" or bool(p.get("ok", false)) or str(p.get("error", "")) != "":
				continue
			var ready := true
			for ch in p["children"]:
				var cp: Dictionary = parts.get(ch["key"], {})
				if not bool(cp.get("ok", false)):
					ready = false
					if str(cp.get("error", "")) != "":
						p["error"] = I18n.t("Alt parça yüklenemedi: ") + str(ch["name"])
			if not ready:
				continue
			_merge_sub(key, p)
			changed = true


func _merge_sub(key: String, p: Dictionary) -> void:
	var verts := PackedVector3Array()
	var tri_face := PackedInt32Array()
	var faces: Array = []
	var edges: Array = []
	var all_brep := true
	var ci := 0
	for ch in p["children"]:
		var cp: Dictionary = parts[ch["key"]]
		var m: ModelMesh = cp["model"]
		if m == null or m.is_empty() or bool(ch.get("hidden", false)):
			ci += 1
			continue
		var xf: Transform3D = ch["xf"]
		var foff := faces.size()
		var eoff := edges.size()
		for t in m.tri_count():
			for k in 3:
				verts.append(xf * m.verts[m.tris[t * 3 + k]])
			tri_face.append(m.tri_face[t] + foff if m.has_brep() else -1)
		if m.has_brep():
			for info in m.brep_faces:
				var f: Dictionary = info.duplicate(true)
				f["id"] = int(info["id"]) + foff
				f["name"] = "c%d/%s" % [ci, str(info.get("name", ""))]
				for k2 in ["p", "o"]:
					if f.has(k2):
						f[k2] = MateGeom.a3(xf * MateGeom.v3(f[k2]))
				for k3 in ["n", "axis"]:
					if f.has(k3):
						f[k3] = MateGeom.a3((xf.basis * MateGeom.v3(f[k3])).normalized())
				if f.has("e"):
					var ee: Array = []
					for e in f["e"]:
						ee.append(int(e) + eoff)
					f["e"] = ee
				faces.append(f)
			for e2 in m.brep_edges:
				var ed: Dictionary = e2.duplicate(true)
				ed["id"] = int(e2["id"]) + eoff
				var pts := PackedVector3Array()
				for q in (e2["pts"] as PackedVector3Array):
					pts.append(xf * q)
				ed["pts"] = pts
				var ff: Array = []
				for fi in e2.get("f", []):
					ff.append(int(fi) + foff)
				ed["f"] = ff
				var fn: Array = []
				for nm in e2.get("fn", []):
					fn.append("c%d/%s" % [ci, str(nm)])
				ed["fn"] = fn
				for k4 in ["o", "m"]:
					if ed.has(k4) and ed[k4] is Array and (ed[k4] as Array).size() == 3:
						ed[k4] = MateGeom.a3(xf * MateGeom.v3(ed[k4]))
				for k5 in ["n", "d", "xd"]:
					if ed.has(k5) and ed[k5] is Array and (ed[k5] as Array).size() == 3:
						ed[k5] = MateGeom.a3((xf.basis * MateGeom.v3(ed[k5])).normalized())
				edges.append(ed)
		else:
			all_brep = false
		ci += 1
	var am := ArrayMesh.new()
	if not verts.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var brep := {}
	if all_brep and not faces.is_empty():
		brep = {"tri_face": tri_face, "faces": faces, "edges": edges, "mass": {}, "valid": true}
	var model := ModelMesh.new()
	if not verts.is_empty():
		model.build(am, brep)
	p["model"] = model
	p["mesh"] = AsmLod.with_lods(model.display_mesh())
	p["ok"] = not verts.is_empty()
	p["brep"] = all_brep
	p["ver"] = int(p.get("ver", 0)) + 1
	if view != null:
		view.invalidate_part(key)


func _part_doc_src(src: Dictionary, base_dir: String) -> CadDocument:
	if src.has("toolbox"):
		return Toolbox.make_doc(src["toolbox"])
	var path := CadAssembly.resolve_path(str(src.get("path", "")), base_dir)
	if not FileAccess.file_exists(path):
		return null
	var units := Units.to_dict()
	var d := CadDocument.new()
	var err := d.load_from(path)
	Units.apply_dict(units)
	return d if err == OK else null


func _on_part_built(key: String, mesh: ArrayMesh, brep: Dictionary) -> void:
	if not parts.has(key):
		return
	var p: Dictionary = parts[key]
	var model := ModelMesh.new()
	if mesh != null:
		model.build(mesh, brep)
	p["model"] = model
	p["mesh"] = AsmLod.with_lods(model.display_mesh())
	p["ok"] = mesh != null
	p["brep"] = not brep.is_empty()
	p["ver"] = int(p.get("ver", 0)) + 1
	if mesh == null and str(p.get("error", "")) == "":
		p["error"] = I18n.t("Parça geometrisi boş")
	if view != null:
		view.invalidate_part(key)
	_pending = maxi(0, _pending - 1)
	if _pending == 0:
		_after_parts_loaded()


func _after_parts_loaded() -> void:
	if asm == null:
		return
	_compose_subs()
	# Yeni eklenen bileşenleri mevcut montajın yanına yerleştir
	for c in asm.comps:
		if not bool(c.get("_place", false)):
			continue
		c.erase("_place")
		var others := AABB()
		var first := true
		for o in asm.comps:
			if o == c or bool(o.get("_place", false)):
				continue
			var m: ModelMesh = parts.get(asm.key_of(o), {}).get("model")
			if m == null or m.is_empty():
				continue
			var xf: Transform3D = o["xf"]
			var bb := xf * m.aabb
			others = bb if first else others.merge(bb)
			first = false
		var pm: ModelMesh = parts.get(asm.key_of(c), {}).get("model")
		if not first and pm != null and not pm.is_empty():
			var xf2: Transform3D = c["xf"]
			c["xf"] = Transform3D(xf2.basis, Vector3(others.end.x + 15.0 - pm.aabb.position.x, others.position.y - pm.aabb.position.y, others.get_center().z - pm.aabb.get_center().z))
	solve()
	refresh()
	if _fit_after:
		_fit_after = false
		fit(false)
	if _demo_stage == 1:
		finish_demo()


func on_backend_changed() -> void:
	if asm != null and _pending == 0:
		load_parts(parts.keys())


## Parça düzenlemesinden dönüldü: bu dosyanın parçasını yeniden yükle
func reload_part_file(path: String) -> void:
	if asm == null:
		return
	var key := "file:" + path.simplify_path()
	if parts.has(key):
		var force: Array = [key]
		# Bu parçayı içeren alt montajlar yeniden birleştirilir
		for k in parts:
			if parts[k].get("kind", "") == "asm":
				for ch in parts[k].get("children", []):
					if ch["key"] == key:
						force.append(k)
		load_parts(force)


# ---------------------------------------------------------------- çözüm

func _info() -> Dictionary:
	var out := {}
	for c in asm.comps:
		var m: ModelMesh = parts.get(asm.key_of(c), {}).get("model")
		if m != null and not m.is_empty():
			out[int(c["id"])] = {"center": m.aabb.get_center(), "size": m.aabb.size.length()}
		else:
			out[int(c["id"])] = {"center": Vector3.ZERO, "size": 50.0}
	return out


func _local_geo(ref: Dictionary) -> Dictionary:
	var c := asm.get_comp(int(ref.get("comp", -1)))
	var m: ModelMesh = parts.get(asm.key_of(c), {}).get("model") if not c.is_empty() else null
	return MateGeom.resolve(ref, m)


func solve(opts := {}) -> Dictionary:
	if asm == null:
		return {}
	var o := {"tol": 1e-4}
	o.merge(opts, true)
	var inst: Array = []
	for c in asm.comps:
		if c.has("pattern"):
			inst.append(int(c["id"]))
	if not inst.is_empty():
		var pin: Array = o.get("pinned", []).duplicate()
		pin.append_array(inst)
		o["pinned"] = pin
		update_patterns()
	last_solve = MateSolver.solve(asm, _local_geo, _info(), o)
	if not inst.is_empty():
		update_patterns()
		var uses := false
		for m in asm.mates:
			for r in m["refs"]:
				if int(r.get("comp", -1)) in inst:
					uses = true
		if uses:
			last_solve = MateSolver.solve(asm, _local_geo, _info(), o)
	return last_solve


## Çoğaltma örneklerinin dönüşümleri: çekirdek bileşenin dönüşümüne öteleme / dönme uygulanır.
func update_patterns() -> void:
	for p in asm.patterns:
		var d := Vector3.UP
		var origin := Vector3.ZERO
		var dirv: Dictionary = p.get("dir", {"axis": "x"})
		if dirv.has("axis"):
			d = {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}.get(str(dirv["axis"]), Vector3.RIGHT)
		elif dirv.has("ref"):
			var c := asm.get_comp(int(dirv["ref"].get("comp", -1)))
			if not c.is_empty():
				var w := _world_ref(dirv["ref"])
				d = MateSolver.dir(w)
				origin = MateSolver.pt(w)
		if bool(p.get("reverse", false)):
			d = -d
		var count := maxi(2, int(p.get("count", 2)))
		var total := float(p.get("total", 360.0))
		var step := deg_to_rad(total / count if total >= 359.99 else total / maxf(1.0, count - 1))
		for c2 in asm.pattern_instances(int(p["id"])):
			var si := int(c2["pidx"][0])
			var k := int(c2["pidx"][1])
			if si >= (p["seeds"] as Array).size():
				continue
			var seed := asm.get_comp(int(p["seeds"][si]))
			if seed.is_empty():
				continue
			var sx: Transform3D = seed["xf"]
			if str(p.get("type", "linear")) == "circular":
				var rb := Basis(d.normalized(), step * k)
				c2["xf"] = Transform3D(rb * sx.basis, rb * (sx.origin - origin) + origin)
			else:
				c2["xf"] = Transform3D(sx.basis, sx.origin + d.normalized() * float(p.get("spacing", 20.0)) * k)


var pat_opts := {"type": "linear", "axis": 0, "count": 3, "spacing": 30.0, "total": 360.0, "ref": {}, "pick_dir": false, "reverse": false}


func create_pattern() -> Dictionary:
	if sel_comps.is_empty():
		app._set_status("Önce çoğaltılacak bileşen(ler)e tıklayın.")
		return {}
	var dirv := {}
	if int(pat_opts["axis"]) < 3:
		dirv = {"axis": ["x", "y", "z"][int(pat_opts["axis"])]}
	else:
		if (pat_opts["ref"] as Dictionary).is_empty():
			app._set_status("Yön için modelden kenar / eksen / yüz seçin.")
			return {}
		dirv = {"ref": (pat_opts["ref"] as Dictionary).duplicate(true)}
	asm.checkpoint()
	var label := "Dairesel Çoğaltma" if pat_opts["type"] == "circular" else "Doğrusal Çoğaltma"
	asm.counters[label] = int(asm.counters.get(label, 0)) + 1
	var p := {"id": asm.new_id(), "name": "%s%d" % [label, asm.counters[label]], "type": pat_opts["type"], "seeds": sel_comps.duplicate(),
		"dir": dirv, "count": int(pat_opts["count"]), "spacing": float(pat_opts["spacing"]), "total": float(pat_opts["total"]),
		"reverse": bool(pat_opts["reverse"]), "skip": []}
	asm.patterns.append(p)
	_regen_instances(p)
	asm.commit()
	sel_comps.clear()
	sel = {"kind": "pattern", "id": int(p["id"])}
	tool = "select"
	solve()
	refresh()
	app._set_status(I18n.t("%s: %d örnek") % [p["name"], asm.pattern_instances(int(p["id"])).size()])
	return p


## Örnek bileşenlerini yeniden oluştur (sayı değişince); atlanan örnekler oluşturulmaz.
func _regen_instances(p: Dictionary) -> void:
	var have := {}
	for c in asm.pattern_instances(int(p["id"])):
		have["%d:%d" % [int(c["pidx"][0]), int(c["pidx"][1])]] = c
	var want := {}
	for si in (p["seeds"] as Array).size():
		for k in range(1, maxi(2, int(p["count"]))):
			var skip := false
			for sk in p.get("skip", []):
				if int(sk[0]) == si and int(sk[1]) == k:
					skip = true
			if not skip:
				want["%d:%d" % [si, k]] = [si, k]
	for key in have:
		if not want.has(key):
			asm.comps.erase(have[key])
	for key in want:
		if have.has(key):
			continue
		var seed := asm.get_comp(int(p["seeds"][want[key][0]]))
		if seed.is_empty():
			continue
		var c := asm.add_component(seed["src"].duplicate(true), seed["xf"], str(seed["name"]).get_slice("<", 0))
		c["fixed"] = false
		c["pattern"] = int(p["id"])
		c["pidx"] = want[key]
	update_patterns()


func dof_of(id: int) -> int:
	return int(last_solve.get("dof", {}).get(id, 0 if bool(asm.get_comp(id).get("fixed", false)) else 6))


# ---------------------------------------------------------------- görünüm

func _offsets() -> Dictionary:
	var out := {}
	if explode_t <= 0.0 or asm == null:
		return out
	for st in asm.explode:
		var d := MateSolver.v3(st.get("dir", [0, 1, 0])) * float(st.get("dist", 0.0)) * explode_t
		for id in st.get("comps", []):
			out[int(id)] = (out.get(int(id), Vector3.ZERO) as Vector3) + d
	return out


func refresh() -> void:
	if asm == null or view == null:
		return
	if app.mode != "assembly" and not (app.mode == "drawing" and app._dw_in_asm):
		# Parça bağlamda düzenlenirken yalnızca hayalet görünüm güncellenir
		if context_active():
			view.sync(asm, parts, {}, [], -1)
		return
	refresh_view()
	rebuild_tree()
	app._refresh_panel()
	update_title()


func refresh_view() -> void:
	if asm == null or view == null:
		return
	var selected: Array = []
	if sel.get("kind", "") == "comp":
		selected.append(int(sel["id"]))
	if tool == "explode" or tool == "pattern":
		selected.append_array(sel_comps)
	var offs := _offsets()
	view.large = large_mode if not large_auto else AsmLod.is_big(asm, parts)
	view.sync(asm, parts, offs, selected, hover)
	view.set_edges_visible(_vp().show_edges)
	# Patlatma çizgileri
	var segs: Array = []
	if explode_t > 0.0:
		for c in asm.comps:
			var id := int(c["id"])
			if offs.has(id):
				var m: ModelMesh = parts.get(asm.key_of(c), {}).get("model")
				if m != null and not m.is_empty():
					var a: Vector3 = (c["xf"] as Transform3D) * m.aabb.get_center()
					segs.append([a, a + (offs[id] as Vector3)])
	view.set_lines(segs)
	_update_highlight()


func _update_highlight() -> void:
	var pts := PackedVector3Array()
	var refs: Array = []
	if tool == "mate":
		refs = mate_refs
	elif tool == "motion" and not (motion["ref"] as Dictionary).is_empty():
		refs = [motion["ref"]]
	elif tool == "pattern" and not (pat_opts["ref"] as Dictionary).is_empty() and int(pat_opts["axis"]) == 3:
		refs = [pat_opts["ref"]]
	elif sel.get("kind", "") == "mate":
		var m := asm.get_mate(int(sel["id"]))
		if not m.is_empty():
			refs = m["refs"]
	for r in refs:
		pts.append_array(_ref_tris(r))
	var offs := _offsets()
	var tri_sets: Array = []
	for it in interf:
		tri_sets.append(it["tris"])
	view.set_interference(tri_sets)
	_vp().set_face_highlight(pts)


func _ref_tris(r: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var c := asm.get_comp(int(r.get("comp", -1)))
	if c.is_empty():
		return out
	var m: ModelMesh = parts.get(asm.key_of(c), {}).get("model")
	if m == null or m.is_empty():
		return out
	var xf := AssemblyView.comp_world(c, _offsets())
	if str(r.get("kind", "")) == "face":
		var tris := PackedInt32Array()
		var g: Dictionary = MateGeom.resolve(r, m)
		if m.has_brep():
			for info in m.brep_faces:
				if str(r.get("name", "")) != "" and str(info.get("name", "")) == str(r["name"]):
					var gi := MateGeom.geo_from_face_info(info)
					if not gi.is_empty() and gi["t"] == g.get("t", "") and MateGeom.v3(gi["p"]).distance_to(MateGeom.v3(g.get("p", [0, 0, 0]))) < 1e-4:
						tris = m.brep_face_region(int(info["id"]))["tris"]
						break
			if tris.is_empty() and int(r.get("fid", -1)) >= 0 and int(r["fid"]) < m.brep_faces.size():
				tris = m.brep_face_region(int(r["fid"]))["tris"]
		else:
			# CSG: geometriye uyan üçgenler
			var t := str(g.get("t", ""))
			for ti in m.tri_count():
				var c3 := (m.verts[m.tris[ti * 3]] + m.verts[m.tris[ti * 3 + 1]] + m.verts[m.tris[ti * 3 + 2]]) / 3.0
				if t == "plane":
					if absf((c3 - MateGeom.v3(g["p"])).dot(MateGeom.v3(g["n"]))) < 1e-3 and m.normals[ti].dot(MateGeom.v3(g["n"])) > 0.99:
						tris.append(ti)
				elif t == "cyl":
					var d := MateGeom.v3(g["d"])
					var q := c3 - MateGeom.v3(g["p"])
					if absf((q - d * q.dot(d)).length() - float(g["r"])) < float(g["r"]) * 0.05 + 0.05 and absf(m.normals[ti].dot(d)) < 0.3:
						tris.append(ti)
		for ti in tris:
			for k in 3:
				out.append(xf * m.verts[m.tris[ti * 3 + k]])
	else:
		# Kenar / eksen / nokta: küçük bir vurgu şeridi
		var g2 := MateGeom.resolve(r, m)
		var w := MateSolver.to_world(g2, xf)
		var size := maxf(2.0, m.aabb.size.length() * 0.02)
		var p0: Vector3 = w.get("p", Vector3.ZERO)
		var dirv: Vector3 = w.get("d", w.get("n", Vector3.UP))
		var e: Vector3 = w.get("e", p0 + dirv * size * 10.0)
		if str(g2.get("t", "")) == "circle":
			var u := dirv.cross(Vector3.RIGHT if absf(dirv.x) < 0.9 else Vector3.UP).normalized()
			var v := dirv.cross(u)
			var rr := float(g2.get("r", 1.0))
			for k in 32:
				var a1 := TAU * k / 32.0
				var a2 := TAU * (k + 1) / 32.0
				var q1 := p0 + (u * cos(a1) + v * sin(a1)) * rr
				var q2 := p0 + (u * cos(a2) + v * sin(a2)) * rr
				out.append_array(_ribbon(q1, q2, size * 0.25))
		elif str(g2.get("t", "")) == "plane":
			var u2 := dirv.cross(Vector3.RIGHT if absf(dirv.x) < 0.9 else Vector3.UP).normalized() * size * 6.0
			var v2 := dirv.cross(u2.normalized()) * size * 6.0
			out.append_array([p0 - u2 - v2, p0 + u2 - v2, p0 + u2 + v2, p0 - u2 - v2, p0 + u2 + v2, p0 - u2 + v2])
		elif str(g2.get("t", "")) == "point":
			out.append_array(_ribbon(p0 - Vector3.RIGHT * size, p0 + Vector3.RIGHT * size, size * 0.5))
			out.append_array(_ribbon(p0 - Vector3.UP * size, p0 + Vector3.UP * size, size * 0.5))
		else:
			out.append_array(_ribbon(p0, e, size * 0.3))
	return out


static func _ribbon(a: Vector3, b: Vector3, w: float) -> PackedVector3Array:
	var d := (b - a).normalized()
	var u := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized() * w
	var v := d.cross(u.normalized()) * w
	var out := PackedVector3Array()
	for s in [u, v]:
		out.append_array([a - s, b - s, b + s, a - s, b + s, a + s])
	return out


func fit(animate: bool) -> void:
	if asm == null or view == null:
		return
	var box := view.world_aabb(asm, parts, _offsets())
	if box.size.length() < 1e-6:
		box = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	_vp().camera.fit(box, animate)


func _process(delta: float) -> void:
	if asm == null:
		return
	if absf(explode_t - _explode_goal) > 1e-4:
		explode_t = move_toward(explode_t, _explode_goal, delta * 2.5)
		refresh_view()
		if absf(explode_t - _explode_goal) <= 1e-4 and _fit_on_explode:
			_fit_on_explode = false
			fit(true)
	if bool(motion.get("playing", false)):
		_motion_step(delta)


# ---------------------------------------------------------------- araç çubuğu

func build_toolbar(cm: Control) -> void:
	toolbar = HFlowContainer.new()
	toolbar.set_meta("group", "Montaj")
	toolbar.visible = false
	cm.add_child(toolbar)
	var items := [
		["Bileşen\nEkle", "asm_insert", "Parça dosyası (.dcad) ekle", "asm_insert"],
		["Bağlantı\nElemanları", "asm_toolbox", "Cıvata, somun, pul, pim, rulman (Toolbox)", "asm_toolbox"],
		["Yeni\nParça", "asm_newpart", "Montaj içinde yeni parça oluştur ve diğer bileşenleri görerek modelle", "asm_newpart"], [],
		["Eşleştir", "asm_mate", "Standart, gelişmiş ve mekanik eşleştirmeler", "asm_mate"],
		["Bileşeni\nTaşı", "asm_move", "Bileşeni sürükle veya sayısal ötele", "asm_move"],
		["Bileşeni\nDöndür", "asm_rotate", "Bileşeni sürükleyerek veya açıyla döndür", "asm_rotate"],
		["Sabitle /\nSerbest", "asm_fix", "Seçili bileşeni sabitle veya serbest bırak", "asm_fix"],
		["Gizle /\nGöster", "asm_hide", "Seçili bileşeni gizle veya göster", "asm_hide"], [],
		["Girişim\nTespiti", "asm_interf", "Bileşenler arası çakışan hacimleri bul (OpenCASCADE)", "asm_interf"],
		["Patlatılmış\nGörünüm", "asm_explode", "Patlatma adımları oluştur", "asm_explode"],
		["Patlat /\nTopla", "asm_explode_toggle", "Patlatılmış görünümü aç / kapat", "asm_explode_toggle"],
		["Hareket\nEtüdü", "asm_motion", "Motorla döndür, eşleştirmeler hareketi taşır", "asm_motion"],
		["Bileşen\nÇoğaltma", "asm_pattern", "Bileşenleri doğrusal veya dairesel çoğalt", "asm_pattern"], [],
		["Malzeme\nListesi", "asm_bom", "Montaj malzeme listesi (BOM), CSV", "asm_bom"],
		["Kütle\nÖzellikleri", "asm_mass", "Toplam kütle ve ağırlık merkezi", "asm_mass"],
		["Parçayı\nAç", "asm_open", "Seçili bileşenin parçasını düzenlemek için aç", "asm_open"],
		["Dışa\nAktar", "export", "Montajı dışa aktar: STEP, STL, 3MF, glTF, görüntü, XML... (Ctrl+E)", "asm_export_all"],
	]
	for it in items:
		if it.is_empty():
			toolbar.add_child(VSeparator.new())
			continue
		app._tb(toolbar, it[0], it[1], it[2], cmd.bind(it[3]), false, 66)


func set_tool(t: String) -> void:
	_stop_motion()
	tool = t
	mate_refs.clear()
	_drag = {}
	app._set_status(str(TOOL_HINTS.get(t, "")))
	refresh()


## Montaj modunda komutları işler. true: komut işlendi.
func handle_cmd(c: String) -> bool:
	match c:
		"save":
			save()
		"save_as":
			app._file_dialog(true, ["*.dasm ; DIY.CAD Montaj"], I18n.t("Montajı Farklı Kaydet"), "asm_save", asm.name + ".dasm")
		"undo", "redo":
			_stop_motion()
			var ok := asm.undo() if c == "undo" else asm.redo()
			if not ok:
				app._set_status(I18n.t("Geri alınacak işlem yok.") if c == "undo" else I18n.t("Yinelenecek işlem yok."))
			else:
				_validate_sel()
				load_parts()
				solve({"dof": true})
				refresh()
		"delete":
			delete_selected()
		"fit":
			fit(true)
		"rename":
			pass
		_:
			if c.begins_with("asm_"):
				cmd(c)
			else:
				return false
	return true


func cmd(c: String) -> void:
	if asm == null:
		return
	match c:
		"asm_export_all":
			app._cmd("export_all")
		"asm_insert":
			app._file_dialog(false, [I18n.t("*.dcad, *.dasm ; Parça veya alt montaj"), I18n.t("*.dcad ; DIY.CAD Parça"), "*.dasm ; DIY.CAD Montaj (alt montaj)"], "Bileşen Ekle", "asm_insert")
		"asm_toolbox":
			set_tool("toolbox")
		"asm_newpart":
			if asm.file_path == "":
				app._set_status("Yeni parça için önce montajı kaydedin (parça montajın yanına kaydedilir).")
				return
			app._file_dialog(true, [I18n.t("*.dcad ; DIY.CAD Parça")], I18n.t("Yeni parça (montaj içinde)"), "asm_newpart", "YeniParca.dcad")
		"asm_mate":
			mate_type = ""
			set_tool("mate")
		"asm_move", "asm_rotate":
			set_tool(c.substr(4))
		"asm_fix", "asm_hide":
			if sel.get("kind", "") != "comp":
				app._set_status("Önce bir bileşen seçin.")
				return
			var comp := asm.get_comp(int(sel["id"]))
			asm.checkpoint()
			if c == "asm_fix":
				comp["fixed"] = not bool(comp.get("fixed", false))
			else:
				comp["hidden"] = not bool(comp.get("hidden", false))
			asm.commit()
			solve()
			refresh()
		"asm_interf":
			set_tool("interf")
			run_interference()
		"asm_explode":
			sel_comps.clear()
			if sel.get("kind", "") == "comp":
				sel_comps.append(int(sel["id"]))
			set_tool("explode")
		"asm_explode_toggle":
			if asm.explode.is_empty():
				auto_explode()
			_explode_goal = 0.0 if _explode_goal > 0.5 else 1.0
			_fit_on_explode = true
			change(func() -> void: asm.exploded = _explode_goal > 0.5)
			app._set_status("Patlatılmış görünüm" if _explode_goal > 0.5 else "Toplanmış görünüm")
		"asm_motion":
			set_tool("motion")
		"asm_pattern":
			sel_comps.clear()
			if sel.get("kind", "") == "comp":
				sel_comps.append(int(sel["id"]))
			set_tool("pattern")
			pat_opts["pick_dir"] = false
		"asm_bom":
			set_tool("bom")
		"asm_mass":
			set_tool("mass")
		"asm_open":
			open_selected_part()
		"asm_step":
			app._file_dialog(true, ["*.step ; STEP", "*.stp ; STEP"], "Montajı STEP olarak dışa aktar", "asm_step", asm.name + ".step")
		"asm_bom_csv":
			app._file_dialog(true, ["*.csv ; CSV"], "Malzeme listesini kaydet", "asm_bom_csv", asm.name + "_BOM.csv")


func change(fn: Callable) -> void:
	asm.checkpoint()
	fn.call()
	asm.commit()


func save() -> void:
	if asm.file_path == "":
		app._file_dialog(true, ["*.dasm ; DIY.CAD Montaj"], I18n.t("Montajı Kaydet"), "asm_save", asm.name + ".dasm")
		return
	var err := asm.save_to(asm.file_path)
	app._set_status((I18n.t("Montaj kaydedildi: ") + asm.file_path) if err == OK else (I18n.t("Montaj kaydedilemedi (hata %d)") % err))
	if err == OK:
		app._note_file(asm.file_path, "asm")
	refresh()


## Dosya iletişim kutusu sonuçları
func on_file(action: String, path: String) -> void:
	match action:
		"asm_newpart":
			if path.get_extension().to_lower() != "dcad":
				path += ".dcad"
			new_part_in_context(path)
		"asm_insert":
			if path.get_extension().to_lower() == "dasm" and path.simplify_path() == asm.file_path.simplify_path():
				app._set_status("Montaj kendi içine alt montaj olarak eklenemez.")
				return
			insert_file(path)
		"asm_save":
			if path.get_extension().to_lower() != "dasm":
				path += ".dasm"
			var err := asm.save_to(path)
			app._set_status((I18n.t("Montaj kaydedildi: ") + path) if err == OK else (I18n.t("Montaj kaydedilemedi (hata %d)") % err))
			if err == OK:
				app._note_file(path, "asm")
			refresh()
		"asm_step":
			if not (path.get_extension().to_lower() in ["step", "stp"]):
				path += ".step"
			export_step(path)
		"asm_bom_csv":
			if path.get_extension().to_lower() != "csv":
				path += ".csv"
			var err2 := write_bom_csv(path)
			app._set_status((I18n.t("Malzeme listesi kaydedildi: ") + path) if err2 == OK else I18n.t("CSV yazılamadı"))


func insert_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		app._set_status(I18n.t("Dosya bulunamadı: ") + path)
		return {}
	asm.checkpoint()
	var c := asm.add_component({"path": path.simplify_path()}, Transform3D.IDENTITY, path.get_file().get_basename())
	if asm.comps.size() > 1:
		c["_place"] = true
	asm.commit()
	sel = {"kind": "comp", "id": int(c["id"])}
	load_parts()
	refresh()
	app._set_status(I18n.t("Bileşen eklendi: %s%s") % [c["name"], I18n.t(" (sabit)") if bool(c["fixed"]) else I18n.t(" — eşleştirmelerle konumlandırın")])
	return c


func insert_toolbox(spec: Dictionary) -> Dictionary:
	asm.checkpoint()
	var c := asm.add_component({"toolbox": spec.duplicate()}, Transform3D.IDENTITY, Toolbox.designation(spec))
	if asm.comps.size() > 1:
		c["_place"] = true
	asm.commit()
	sel = {"kind": "comp", "id": int(c["id"])}
	load_parts()
	refresh()
	return c


func open_selected_part() -> void:
	if sel.get("kind", "") != "comp":
		app._set_status("Önce bir bileşen seçin.")
		return
	var c := asm.get_comp(int(sel["id"]))
	if c["src"].has("toolbox"):
		app._set_status("Bağlantı elemanları kütüphaneden üretilir; ölçüsünü panelden değiştirin.")
		return
	var path := CadAssembly.resolve_path(str(c["src"]["path"]), asm.base_dir())
	if path.get_extension().to_lower() == "dasm":
		# Alt montajı aç: üst montaj kaydedilir (yolu varsa), alt montaj açılır
		if asm.dirty:
			if asm.file_path == "":
				app._set_status("Önce montajı kaydedin, sonra alt montajı açın.")
				return
			asm.save_to(asm.file_path)
		var err := open_file(path)
		app._set_status((I18n.t("Alt montaj açıldı: ") + path.get_file()) if err == OK else I18n.t("Alt montaj açılamadı."))
		return
	app.open_part_from_assembly(path, int(c["id"]))


func delete_selected() -> void:
	if sel.is_empty():
		return
	var s := sel.duplicate()
	asm.checkpoint()
	if s["kind"] == "comp":
		asm.remove_component(int(s["id"]))
	elif s["kind"] == "mate":
		asm.remove_mate(int(s["id"]))
	elif s["kind"] == "pattern":
		asm.remove_pattern(int(s["id"]))
	asm.commit()
	sel = {}
	solve()
	refresh()


func _validate_sel() -> void:
	if sel.get("kind", "") == "comp" and asm.get_comp(int(sel["id"])).is_empty():
		sel = {}
	elif sel.get("kind", "") == "mate" and asm.get_mate(int(sel["id"])).is_empty():
		sel = {}
	elif sel.get("kind", "") == "pattern" and asm.get_pattern(int(sel["id"])).is_empty():
		sel = {}


func escape() -> void:
	if tool == "mate" and not mate_refs.is_empty():
		mate_refs.clear()
		refresh()
	elif tool != "select":
		set_tool("select")
	else:
		sel = {}
		refresh()


# ---------------------------------------------------------------- girdi

func _ray(pos: Vector2) -> Array:
	return _vp().ray(pos)


func pick(pos: Vector2) -> Dictionary:
	var r := _ray(pos)
	return view.pick(asm, parts, r[0], r[1], _offsets())


## Eşleştirme referansı seçimi: önce yakın kenar, sonra yüz
func pick_ref(pos: Vector2) -> Dictionary:
	var hit := pick(pos)
	var offs := _offsets()
	var best_e := {}
	for c in asm.comps:
		if bool(c.get("hidden", false)) or bool(c.get("suppressed", false)):
			continue
		var m: ModelMesh = parts.get(asm.key_of(c), {}).get("model")
		if m == null or not m.has_brep():
			continue
		var xf := AssemblyView.comp_world(c, offs)
		var to_s := func(p: Vector3) -> Vector2: return _vp().world_to_screen(xf * p)
		var e := m.pick_edge(pos, to_s, 6.0)
		if not e.is_empty() and (best_e.is_empty() or float(e["dist_px"]) < float(best_e["dist_px"])):
			e["comp"] = int(c["id"])
			best_e = e
	if not best_e.is_empty() and (hit.is_empty() or int(hit["comp"]) == int(best_e["comp"])):
		var m2: ModelMesh = parts[asm.key_of(asm.get_comp(int(best_e["comp"])))]["model"]
		var er := MateGeom.edge_ref(m2, int(best_e["edge"]))
		if not er.is_empty():
			er["comp"] = int(best_e["comp"])
			return er
	if hit.is_empty():
		return {}
	var m3: ModelMesh = parts[asm.key_of(asm.get_comp(int(hit["comp"])))]["model"]
	var fr := MateGeom.face_ref(m3, int(hit["tri"]), hit["local"])
	if not fr.is_empty():
		fr["comp"] = int(hit["comp"])
	return fr


func on_pointer(ev: InputEvent) -> void:
	if asm == null:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press = {"pos": mb.position, "hit": pick(mb.position)}
			if tool in ["select", "move", "rotate"] and not (_press["hit"] as Dictionary).is_empty():
				_begin_drag(_press["hit"], mb.position)
		else:
			if not _drag.is_empty() and bool(_drag.get("moved", false)):
				_end_drag()
			else:
				_drag = {}
				_click(mb.position, mb.shift_pressed or mb.ctrl_pressed)
			_press = {}
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if not _drag.is_empty():
			if not bool(_drag.get("moved", false)) and mm.position.distance_to(_drag["start"]) < 4.0:
				return
			_drag["moved"] = true
			_drag_to(mm.position)
			return
		var h := pick(mm.position)
		var nh: int = int(h["comp"]) if not h.is_empty() else -1
		if nh != hover:
			hover = nh
			refresh_view()
		if not h.is_empty():
			var p: Vector3 = h["world"]
			app.coord_label.text = "%s   X %s  Y %s  Z %s" % [asm.get_comp(nh).get("name", ""), Units.format_length(p.x, false), Units.format_length(p.y, false), Units.format_length(p.z, false)]
		else:
			app.coord_label.text = ""


func _click(pos: Vector2, multi: bool) -> void:
	match tool:
		"mate":
			var r := pick_ref(pos)
			if r.is_empty():
				return
			add_mate_ref(r)
		"motion":
			var r2 := pick_ref(pos)
			if r2.is_empty() or not (str(r2["geo"]["t"]) in ["cyl", "circle", "line", "cone"]):
				app._set_status("Silindirik yüz, dairesel veya doğrusal kenar seçin (dönme ekseni).")
				return
			motion["ref"] = r2
			refresh()
		"pattern":
			if bool(pat_opts["pick_dir"]):
				var rr := pick_ref(pos)
				if not rr.is_empty():
					pat_opts["ref"] = rr
					pat_opts["pick_dir"] = false
					refresh()
				return
			var hp := pick(pos)
			if hp.is_empty():
				return
			var pid := int(hp["comp"])
			if pid in sel_comps:
				sel_comps.erase(pid)
			else:
				sel_comps.append(pid)
			refresh()
		"explode":
			var h := pick(pos)
			if h.is_empty():
				return
			var id := int(h["comp"])
			if id in sel_comps:
				sel_comps.erase(id)
			else:
				sel_comps.append(id)
			refresh()
		_:
			var h2 := pick(pos)
			sel = {"kind": "comp", "id": int(h2["comp"])} if not h2.is_empty() else {}
			refresh()


func add_mate_ref(r: Dictionary) -> void:
	var need := _refs_needed()
	if mate_refs.size() >= need:
		mate_refs.clear()
	mate_refs.append(r)
	if mate_type != "" and mate_refs.size() >= _refs_needed():
		apply_mate(mate_type)
	else:
		refresh()


func _refs_needed() -> int:
	if mate_type == "":
		return 2
	return int(CadAssembly.MATE_TYPES[mate_type][1])


# ---------------------------------------------------------------- sürükleme

func _begin_drag(hit: Dictionary, pos: Vector2) -> void:
	if explode_t > 0.0:
		return
	var c := asm.get_comp(int(hit["comp"]))
	if c.is_empty():
		return
	var cam := _vp().camera
	_drag = {"comp": int(hit["comp"]), "local": hit["local"], "plane_p": hit["world"], "plane_n": -cam.global_transform.basis.z,
		"start": pos, "moved": false, "xf0": c["xf"], "fixed": bool(c.get("fixed", false))}
	_coll_good = _xfs()
	_coll_start = _coll_good.duplicate()
	_coll_hit = false


func _drag_to(pos: Vector2) -> void:
	var c := asm.get_comp(int(_drag["comp"]))
	if bool(_drag["fixed"]):
		app._set_status("Sabit bileşen taşınamaz (Sabitle / Serbest ile serbest bırakın).")
		return
	if not _drag.has("snap"):
		_drag["snap"] = asm.to_dict()
	if tool == "rotate":
		var cam := _vp().camera
		var d: Vector2 = pos - (_drag["start"] as Vector2)
		var m: ModelMesh = parts.get(asm.key_of(c), {}).get("model")
		var x0: Transform3D = _drag["xf0"]
		var ctr: Vector3 = x0 * (m.aabb.get_center() if m != null else Vector3.ZERO)
		var rb := Basis(cam.global_transform.basis.y, d.x * 0.01) * Basis(cam.global_transform.basis.x, d.y * 0.01)
		c["xf"] = Transform3D((rb * x0.basis).orthonormalized(), rb * (x0.origin - ctr) + ctr)
		solve({"dof": false, "pinned": [int(_drag["comp"])] if asm.mates_of(int(_drag["comp"])).is_empty() else []})
	else:
		var r := _ray(pos)
		var n: Vector3 = _drag["plane_n"]
		var den := (r[1] as Vector3).dot(n)
		if absf(den) < 1e-9:
			return
		var t := ((_drag["plane_p"] as Vector3) - (r[0] as Vector3)).dot(n) / den
		var target: Vector3 = r[0] + r[1] * t
		solve({"dof": false, "drag": {"comp": int(_drag["comp"]), "local": _drag["local"], "target": target, "w": 0.05}})
	if collide_on:
		if _coll_busy:
			_coll_dirty = true
		else:
			_send_collide()
	refresh_view()


func _end_drag() -> void:
	var snap: Dictionary = _drag.get("snap", {})
	_drag = {}
	if snap.is_empty():
		return
	if collide_on and _coll_busy:
		# Son çarpışma yanıtı gelince işlenir
		_coll_end_snap = snap
		return
	_commit_drag(snap)


func _commit_drag(snap: Dictionary) -> void:
	# Geri al için sürükleme öncesi durum
	var after := asm.to_dict()
	asm.load_dict(snap, false)
	asm.checkpoint()
	asm.load_dict(after, false)
	asm.commit()
	solve()
	refresh()


# ---------------------------------------------------------------- çarpışma algılama (sürüklerken)

var collide_on := false
var _coll_busy := false
var _coll_dirty := false
var _coll_hit := false
var _coll_good := {}       # son çarpışmasız dönüşümler
var _coll_start := {}
var _coll_pending := {}
var _coll_end_snap := {}
var _coll_ids: Array = []


func _xfs() -> Dictionary:
	var out := {}
	for c in asm.comps:
		out[int(c["id"])] = c["xf"]
	return out


func _send_collide() -> void:
	if not _vp().kernel.is_brep():
		return
	var moving := {}
	for c in asm.comps:
		var id := int(c["id"])
		var x0: Transform3D = _coll_start.get(id, c["xf"])
		var x1: Transform3D = c["xf"]
		if not x0.is_equal_approx(x1):
			moving[id] = true
	if moving.is_empty():
		_coll_good = _xfs()
		return
	var ml: Array = []
	var ol: Array = []
	for c in asm.comps:
		if bool(c.get("suppressed", false)) or bool(c.get("hidden", false)):
			continue
		_occ_expand(asm.key_of(c), c["xf"], int(c["id"]), ml if moving.has(int(c["id"])) else ol, 0)
	if ml.is_empty() or ol.is_empty():
		_coll_good = _xfs()
		return
	_coll_ids = []
	for e in ml:
		_coll_ids.append(e["id"])
	for e in ol:
		_coll_ids.append(e["id"])
	_coll_pending = _xfs()
	_coll_busy = true
	_vp().kernel.request_asm("asm_collide", {"moving": ml, "others": ol})


func _on_collide(res: Dictionary) -> void:
	_coll_busy = false
	if bool(res.get("hit", false)):
		_coll_hit = true
		for c in asm.comps:
			var id := int(c["id"])
			if _coll_good.has(id):
				c["xf"] = _coll_good[id]
		var pr: Array = res.get("pairs", [[0, 0]])[0]
		var nm := func(i: int) -> String: return str(asm.get_comp(int(_coll_ids[i])).get("name", "?")) if i < _coll_ids.size() else "?"
		app._set_status(I18n.t("Çarpışma: %s ↔ %s — bileşen son çarpışmasız konumda durdu.") % [nm.call(int(pr[0])), nm.call(int(pr[1]) + int(res.get("n_moving", 0)))])
		refresh_view()
		_coll_dirty = false
	else:
		_coll_hit = false
		_coll_good = _coll_pending
		if _coll_dirty:
			# Yanıt beklenirken bileşen yine hareket etti: güncel konumu da denetle
			_coll_dirty = false
			_send_collide()
			if _coll_busy:
				return
	if not _coll_end_snap.is_empty():
		var snap := _coll_end_snap
		_coll_end_snap = {}
		_commit_drag(snap)


# ---------------------------------------------------------------- eşleştirme oluşturma

func _world_ref(r: Dictionary) -> Dictionary:
	var c := asm.get_comp(int(r["comp"]))
	return MateSolver.to_world(_local_geo(r), c["xf"])


func apply_mate(type: String) -> Dictionary:
	var need := int(CadAssembly.MATE_TYPES[type][1])
	if mate_refs.size() < need:
		mate_type = type
		app._set_status(I18n.t("%s için %d referans gerekli (%d seçili).") % [I18n.t(str(CadAssembly.MATE_TYPES[type][0])), need, mate_refs.size()])
		refresh()
		return {}
	var refs: Array = mate_refs.slice(0, need)
	var comps_in := {}
	for r in refs:
		comps_in[int(r["comp"])] = true
	if comps_in.size() < 2 and type != "symmetric":
		app._set_status("Eşleştirme iki farklı bileşen arasında olmalı.")
		mate_refs.clear()
		refresh()
		return {}
	var extra := {}
	var wa := _world_ref(refs[0])
	var wb := _world_ref(refs[1])
	# Hizalama ve yön: mevcut duruma en yakın seçenek
	if type in ["coincident", "distance", "limit_distance", "hinge"]:
		var pa := wa if type != "hinge" else _world_ref(refs[2])
		var pb := wb if type != "hinge" else _world_ref(refs[3])
		if MateSolver.is_plane(pa) and MateSolver.is_plane(pb):
			extra["align"] = "aligned" if (pa["n"] as Vector3).dot(pb["n"]) > 0.0 else "anti"
	match type:
		"distance":
			extra["value"] = absf(float(mate_opts["value"]))
			var dv := MateSolver.distance_value(wa, wb)
			extra["flip"] = dv < 0.0 and (MateSolver.is_plane(wa) or MateSolver.is_plane(wb))
		"angle":
			extra["value"] = float(mate_opts["value"]) if mate_opts.has("value") else 45.0
		"tangent":
			var pl := wa if MateSolver.is_plane(wa) else wb
			var ot := wb if MateSolver.is_plane(wa) else wa
			if MateSolver.is_plane(pl):
				extra["flip"] = (MateSolver.pt(ot) - MateSolver.pt(pl)).dot(pl["n"]) < 0.0
		"limit_distance", "limit_angle":
			extra["min"] = float(mate_opts["min"])
			extra["max"] = float(mate_opts["max"])
		"lock":
			var xa: Transform3D = asm.get_comp(int(refs[0]["comp"]))["xf"]
			var xb: Transform3D = asm.get_comp(int(refs[1]["comp"]))["xf"]
			extra["ref_xf"] = CadAssembly.xf_to_array(xa.affine_inverse() * xb)
		"gear", "rack", "screw":
			var rx := {}
			for r in refs:
				rx[str(int(r["comp"]))] = CadAssembly.xf_to_array(asm.get_comp(int(r["comp"]))["xf"])
			extra["ref_xf"] = rx
			if type == "gear":
				extra["ratio_a"] = float(wa.get("r", mate_opts["ratio_a"]))
				extra["ratio_b"] = float(wb.get("r", mate_opts["ratio_b"]))
			elif type == "rack":
				extra["value"] = float(wb.get("r", mate_opts["value"]))
			else:
				extra["value"] = float(mate_opts.get("pitch", 1.25))
		"cam":
			var cr: Dictionary = refs[1]
			var cc := asm.get_comp(int(cr["comp"]))
			var cm: ModelMesh = parts.get(asm.key_of(cc), {}).get("model")
			var tri := int(cr.get("tri", -1))
			if tri < 0 and cm != null and int(cr.get("fid", -1)) >= 0:
				var reg: PackedInt32Array = cm.brep_face_region(int(cr["fid"]))["tris"]
				tri = reg[0] if not reg.is_empty() else -1
			var prof := MateGeom.cam_profile(cm, tri) if cm != null else {}
			if prof.is_empty():
				app._set_status("Kam profili çıkarılamadı: 2. seçim kamın yan (ekstrüzyon) yüzü olmalı.")
				mate_refs.clear()
				refresh()
				return {}
			extra["frame"] = prof["frame"]
			extra["profile"] = prof["profile"]
	var snap := asm.to_dict()
	asm.checkpoint()
	var m := asm.add_mate(type, refs.duplicate(true), extra)
	var r2 := solve()
	if int(m["id"]) in r2.get("bad", []):
		# Sağlanamayan eşleştirme: konumları geri al, eşleştirmeyi hatalı olarak bırak
		var keep_err := str(m.get("error", ""))
		var mates_now := asm.mates.duplicate(true)
		asm.load_dict(snap, false)
		asm.mates = mates_now
		asm.get_mate(int(m["id"]))["error"] = keep_err
		app._set_status(I18n.t("%s eşleştirmesi sağlanamadı: hizalamayı çevirin veya silin.") % m["name"])
	else:
		app._set_status(I18n.t("%s eklendi.") % m["name"])
	asm.commit()
	mate_refs.clear()
	sel = {"kind": "mate", "id": int(m["id"])}
	tool = "select" if mate_type == "" else tool
	solve()
	refresh()
	return m


# ---------------------------------------------------------------- girişim, patlatma, hareket, çıktı

static func _m34(xf: Transform3D) -> Array:
	var b := xf.basis.orthonormalized()
	return [b.x.x, b.y.x, b.z.x, xf.origin.x, b.x.y, b.y.y, b.z.y, xf.origin.y, b.x.z, b.y.z, b.z.z, xf.origin.z]


func _occ_comps() -> Array:
	var out: Array = []
	for c in asm.comps:
		if bool(c.get("suppressed", false)) or bool(c.get("hidden", false)):
			continue
		_occ_expand(asm.key_of(c), c["xf"], int(c["id"]), out, 0)
	return out


func _occ_expand(key: String, xf: Transform3D, id: int, out: Array, depth: int) -> void:
	var p: Dictionary = parts.get(key, {})
	if p.get("kind", "") == "asm":
		if depth > 6:
			return
		for ch in p.get("children", []):
			if not bool(ch.get("hidden", false)):
				_occ_expand(ch["key"], xf * (ch["xf"] as Transform3D), id, out, depth + 1)
		return
	if bool(p.get("brep", false)):
		out.append({"key": key, "m": _m34(xf), "id": id})


func run_interference() -> void:
	interf.clear()
	if not _vp().kernel.is_brep():
		interf_state = "error"
		app._set_status("Girişim tespiti OpenCASCADE çekirdeği gerektirir.")
		refresh()
		return
	var cl := _occ_comps()
	interf_state = "running"
	interf_ids = []
	for c in cl:
		interf_ids.append(c["id"])
	_vp().kernel.request_asm("asm_interference", {"comps": cl})
	refresh()


var interf_ids: Array = []


func export_step(path: String, schema := "AP214IS") -> void:
	if not _vp().kernel.is_brep():
		app._set_status("Montaj STEP çıktısı OpenCASCADE çekirdeği gerektirir.")
		return
	_vp().kernel.request_asm("asm_export", {"comps": _occ_comps(), "path": path, "format": "step", "schema": schema})
	app._set_status(I18n.t("Montaj dışa aktarılıyor: ") + path)


func _on_asm_done(res: Dictionary) -> void:
	match str(res.get("cmd", "")):
		"asm_collide":
			_on_collide(res)
		"asm_interference":
			interf.clear()
			if not bool(res.get("ok", false)):
				interf_state = "error"
				app._set_status(I18n.t("Girişim hesaplanamadı: ") + str(res.get("error", "")))
			else:
				interf_state = "done"
				for p in res.get("pairs", []):
					if int(interf_ids[int(p["a"])]) == int(interf_ids[int(p["b"])]):
						continue
					var fl := Marshalls.base64_to_raw(str(p["tris"])).to_float32_array()
					var tris := PackedVector3Array()
					for i in range(0, fl.size() - 8, 9):
						tris.append(Vector3(fl[i], fl[i + 1], fl[i + 2]))
						tris.append(Vector3(fl[i + 6], fl[i + 7], fl[i + 8]))
						tris.append(Vector3(fl[i + 3], fl[i + 4], fl[i + 5]))
					interf.append({"a": int(interf_ids[int(p["a"])]), "b": int(interf_ids[int(p["b"])]), "volume": float(p["volume"]),
						"center": MateSolver.v3(p["center"]), "tris": tris})
				app._set_status(I18n.t("Girişim: %d çakışma") % interf.size() if not interf.is_empty() else I18n.t("Girişim yok."))
			refresh()
		"asm_export":
			if bool(res.get("ok", false)):
				app._set_status(I18n.t("Montaj kaydedildi: %s (%d bayt)") % [str(res.get("path", "")), int(res.get("bytes", 0))])
			else:
				app._set_status(I18n.t("Montaj dışa aktarılamadı: ") + str(res.get("error", "")))


## Otomatik patlatma: düzlemsel çakışık / mesafe eşleştirmelerinden yön (bileşenin yüzünün tersine) ve
## sabit bileşenden uzaklığa göre kademeli mesafe; eşleştirmesi olmayanlar merkezden dışa doğru.
func auto_explode() -> void:
	var box := view.world_aabb(asm, parts)
	var center := box.get_center()
	var base := maxf(box.size.length() * 0.18, 10.0)
	var depth := {}
	var dirs := {}
	for c in asm.comps:
		if bool(c.get("fixed", false)):
			depth[int(c["id"])] = 0
	var changed := true
	var guard := 0
	while changed and guard < 50:
		changed = false
		guard += 1
		for m in asm.mates:
			if not (str(m["type"]) in ["coincident", "distance"]) or bool(m.get("suppressed", false)):
				continue
			var r0: Dictionary = m["refs"][0]
			var r1: Dictionary = m["refs"][1]
			for pair in [[r0, r1], [r1, r0]]:
				var known: Dictionary = pair[0]
				var other: Dictionary = pair[1]
				var ko := int(known["comp"])
				var oo := int(other["comp"])
				if depth.has(ko) and not depth.has(oo):
					var w := _world_ref(other)
					if MateSolver.is_plane(w):
						depth[oo] = int(depth[ko]) + 1
						dirs[oo] = -(w["n"] as Vector3)
						changed = true
	var steps: Array = []
	for c in asm.comps:
		var id := int(c["id"])
		if bool(c.get("fixed", false)) or bool(c.get("suppressed", false)):
			continue
		var m2: ModelMesh = parts.get(asm.key_of(c), {}).get("model")
		if m2 == null or m2.is_empty():
			continue
		var d := Vector3.ZERO
		var dist := base
		if dirs.has(id):
			d = dirs[id]
			dist = base * int(depth[id])
		else:
			var cc: Vector3 = (c["xf"] as Transform3D) * m2.aabb.get_center()
			var v := cc - center
			if v.length() < 1e-3:
				v = Vector3.UP
			var k := 0
			for i2 in 3:
				if absf(v[i2]) > absf(v[k]):
					k = i2
			d[k] = signf(v[k]) if v[k] != 0.0 else 1.0
			dist = maxf(base * 1.5, m2.aabb.size.length() * 1.2)
		steps.append({"id": asm.new_id(), "comps": [id], "dir": [d.x, d.y, d.z], "dist": dist})
	change(func() -> void: asm.explode = steps)


func add_explode_step() -> void:
	if sel_comps.is_empty():
		app._set_status("Önce patlatılacak bileşenlere tıklayın.")
		return
	var d: Vector3 = EX_DIRS[ex_dir][1]
	var ids := sel_comps.duplicate()
	change(func() -> void: asm.explode.append({"id": asm.new_id(), "comps": ids, "dir": [d.x, d.y, d.z], "dist": ex_dist}))
	_explode_goal = 1.0
	sel_comps.clear()
	refresh()


func _stop_motion() -> void:
	if not bool(motion.get("playing", false)):
		return
	motion["playing"] = false
	if asm != null:
		var keep: Array = []
		for m in asm.mates:
			if not bool(m.get("_temp", false)):
				keep.append(m)
		asm.mates = keep


func start_motion() -> void:
	var r: Dictionary = motion["ref"]
	if r.is_empty():
		app._set_status("Önce motor eksenini seçin (silindirik yüz).")
		return
	var c := asm.get_comp(int(r["comp"]))
	if bool(c.get("fixed", false)):
		app._set_status("Sabit bileşen döndürülemez: başka bir bileşen seçin.")
		return
	motion["snap"] = asm.to_dict()
	var drv := {"id": -999, "name": "Motor", "type": "drive", "refs": [r.duplicate(true)], "value": 0.0, "_temp": true,
		"ref_xf": {str(int(r["comp"])): CadAssembly.xf_to_array(c["xf"])}, "suppressed": false, "error": ""}
	asm.mates.append(drv)
	motion["drive"] = drv
	motion["t"] = 0.0
	motion["playing"] = true
	app._set_status("Hareket etüdü oynatılıyor...")


func _motion_step(delta: float) -> void:
	motion["t"] = float(motion["t"]) + delta
	var drv: Dictionary = motion["drive"]
	drv["value"] = float(motion["rpm"]) * TAU / 60.0 * float(motion["t"])
	var r := solve({"dof": false})
	refresh_view()
	if not bool(r.get("ok", true)):
		_stop_motion()
		app._set_status("Hareket durdu: eşleştirmeler bu konumda sağlanamıyor (kilitlenme).")
		app._refresh_panel()
		return
	if float(motion["t"]) >= float(motion["dur"]):
		_stop_motion()
		app._set_status(I18n.t("Hareket etüdü bitti (%.0f°).") % rad_to_deg(float(drv["value"])))
		app._refresh_panel()


func reset_motion() -> void:
	_stop_motion()
	if motion.has("snap"):
		asm.load_dict(motion["snap"], false)
		motion.erase("snap")
		for m in asm.mates:
			m.erase("_rt")
		solve()
		refresh()


var bom_flat := true   # true: yalnızca parçalar (alt montajlar açılır), false: üst düzey


func bom_rows() -> Array:
	var counts := {}
	var order: Array = []
	var comps_of := {}
	for c in asm.comps:
		if bool(c.get("suppressed", false)):
			continue
		_bom_add(asm.key_of(c), 1, counts, order, 0)
		var top := asm.key_of(c) if not bom_flat or parts.get(asm.key_of(c), {}).get("kind", "") != "asm" else ""
		if top != "":
			if not comps_of.has(top):
				comps_of[top] = []
			comps_of[top].append(int(c["id"]))
	var rows: Array = []
	var no := 1
	for key in order:
		var p: Dictionary = parts.get(key, {})
		var mass := 0.0
		var m: ModelMesh = p.get("model")
		if m != null and not m.is_empty() and p.get("kind", "") != "asm":
			mass = float(m.mass_properties(Materials.density_of(str(p.get("material", ""))))["mass"])
		elif p.get("kind", "") == "asm":
			var acc := {"mass": 0.0, "volume": 0.0, "mc": Vector3.ZERO}
			_mass_add(key, Transform3D.IDENTITY, acc, 0)
			mass = float(acc["mass"])
		rows.append({"no": no, "name": str(p.get("name", key.get_file())) + (I18n.t(" (alt montaj)") if p.get("kind", "") == "asm" else ""),
			"qty": int(counts[key]), "material": str(p.get("material", "")), "mass": mass, "key": key, "comps": comps_of.get(key, [])})
		no += 1
	return rows


func _bom_add(key: String, qty: int, counts: Dictionary, order: Array, depth: int) -> void:
	var p: Dictionary = parts.get(key, {})
	if bom_flat and p.get("kind", "") == "asm" and depth < 7:
		for ch in p.get("children", []):
			_bom_add(ch["key"], qty, counts, order, depth + 1)
		return
	if not counts.has(key):
		counts[key] = 0
		order.append(key)
	counts[key] += qty


func write_bom_csv(path: String) -> Error:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
	fa.store_line(I18n.t("No;Parça;Adet;Malzeme;Birim kütle (g);Toplam kütle (g)"))
	for r in bom_rows():
		fa.store_line("%d;%s;%d;%s;%.3f;%.3f" % [r["no"], str(r["name"]).replace(";", ","), r["qty"], r["material"], r["mass"], float(r["mass"]) * int(r["qty"])])
	fa.close()
	return OK


func mass_totals() -> Dictionary:
	var acc := {"mass": 0.0, "volume": 0.0, "mc": Vector3.ZERO}
	for c in asm.comps:
		if bool(c.get("suppressed", false)):
			continue
		_mass_add(asm.key_of(c), c["xf"], acc, 0)
	var total: float = acc["mass"]
	return {"mass": total, "volume": acc["volume"], "center": (acc["mc"] as Vector3) / total if total > 0.0 else Vector3.ZERO}


func _mass_add(key: String, xf: Transform3D, acc: Dictionary, depth: int) -> void:
	var p: Dictionary = parts.get(key, {})
	if p.get("kind", "") == "asm":
		if depth < 7:
			for ch in p.get("children", []):
				_mass_add(ch["key"], xf * (ch["xf"] as Transform3D), acc, depth + 1)
		return
	var m: ModelMesh = p.get("model")
	if m == null or m.is_empty():
		return
	var mp := m.mass_properties(Materials.density_of(str(p.get("material", ""))))
	acc["mass"] = float(acc["mass"]) + float(mp["mass"])
	acc["volume"] = float(acc["volume"]) + float(mp["volume"])
	acc["mc"] = (acc["mc"] as Vector3) + (xf * (mp["center"] as Vector3)) * float(mp["mass"])


# ---------------------------------------------------------------- ağaç

func rebuild_tree() -> void:
	var t: Tree = app.tree
	app._syncing_tree = true
	t.clear()
	var root := t.create_item()
	root.set_text(0, asm.name + (" *" if asm.dirty else ""))
	root.set_icon(0, Icons.get_icon("assembly", 18))
	root.set_metadata(0, {"kind": "asm"})
	var mf := t.create_item(root)
	mf.set_text(0, I18n.t("Eşleştirmeler (%d)") % asm.mates.size())
	mf.set_icon(0, Icons.get_icon("asm_mate", 18))
	mf.set_metadata(0, {"kind": "mates"})
	for m in asm.mates:
		if bool(m.get("_temp", false)):
			continue
		var it := t.create_item(mf)
		var err := str(m.get("error", "")) != ""
		it.set_text(0, str(m["name"]) + ("  ⚠" if err else ""))
		it.set_icon(0, Icons.get_icon("asm_mate", 16))
		it.set_metadata(0, {"kind": "mate", "id": int(m["id"])})
		var names: Array = []
		for r in m["refs"]:
			names.append(MateGeom.describe(r, str(asm.get_comp(int(r["comp"])).get("name", "?"))))
		it.set_tooltip_text(0, CadAssembly.MATE_TYPES.get(str(m["type"]), [m["type"]])[0] + ": " + " ↔ ".join(names) + (("\n" + str(m["error"])) if err else ""))
		if err:
			it.set_custom_color(0, Color(1.0, 0.45, 0.4))
		elif bool(m.get("suppressed", false)):
			it.set_custom_color(0, Color(0.5, 0.5, 0.55))
		if sel.get("kind", "") == "mate" and int(sel["id"]) == int(m["id"]):
			it.select(0)
	mf.collapsed = asm.mates.size() > 12
	var pat_items := {}
	for p in asm.patterns:
		var pi := t.create_item(root)
		pi.set_text(0, "%s (%d)" % [p["name"], asm.pattern_instances(int(p["id"])).size()])
		pi.set_icon(0, Icons.get_icon("asm_pattern", 16))
		pi.set_metadata(0, {"kind": "pattern", "id": int(p["id"])})
		pi.collapsed = true
		pat_items[int(p["id"])] = pi
		if sel.get("kind", "") == "pattern" and int(sel["id"]) == int(p["id"]):
			pi.select(0)
	for c in asm.comps:
		var id := int(c["id"])
		var parent_it: TreeItem = pat_items.get(int(c.get("pattern", -1)), root)
		var it2 := t.create_item(parent_it)
		var pre := "(f) " if bool(c.get("fixed", false)) else ("" if c.has("pattern") else ("(-) " if dof_of(id) > 0 else ""))
		var p: Dictionary = parts.get(asm.key_of(c), {})
		it2.set_text(0, pre + str(c["name"]) + ("  ⚠" if str(p.get("error", "")) != "" else ""))
		var is_sub: bool = p.get("kind", "") == "asm"
		it2.set_icon(0, Icons.get_icon("asm_toolbox" if c["src"].has("toolbox") else ("assembly" if is_sub else "part"), 16))
		it2.set_metadata(0, {"kind": "comp", "id": id})
		var tip := "Sabit" if bool(c.get("fixed", false)) else (I18n.t("Serbestlik derecesi: %d") % dof_of(id))
		if str(p.get("error", "")) != "":
			tip += "\n" + str(p["error"])
		it2.set_tooltip_text(0, tip)
		if bool(c.get("hidden", false)) or bool(c.get("suppressed", false)):
			it2.set_custom_color(0, Color(0.5, 0.5, 0.55))
		if is_sub:
			for ch in p.get("children", []):
				var si := t.create_item(it2)
				si.set_text(0, str(ch["name"]))
				si.set_icon(0, Icons.get_icon("assembly" if parts.get(ch["key"], {}).get("kind", "") == "asm" else "part", 14))
				si.set_metadata(0, {"kind": "subpart", "comp": id})
				si.set_custom_color(0, Color(0.62, 0.66, 0.72))
		for oid in ["front", "top", "right", "origin"]:
			var sub := t.create_item(it2)
			sub.set_text(0, MateGeom.ORIGIN_REFS[oid][0])
			sub.set_icon(0, Icons.get_icon("plane" if oid != "origin" else "origin", 14))
			sub.set_metadata(0, {"kind": "cref", "comp": id, "id": oid})
		it2.collapsed = true
		if sel.get("kind", "") == "comp" and int(sel["id"]) == id:
			it2.select(0)
	app._syncing_tree = false


func on_tree_picked(meta: Dictionary) -> void:
	match str(meta.get("kind", "")):
		"pattern":
			sel = {"kind": "pattern", "id": int(meta["id"])}
			tool = "select"
			refresh_view()
			app._refresh_panel()
		"comp", "mate":
			if (tool == "explode" or tool == "pattern") and meta["kind"] == "comp":
				var id := int(meta["id"])
				if id in sel_comps:
					sel_comps.erase(id)
				else:
					sel_comps.append(id)
			else:
				if tool == "mate" and meta["kind"] == "comp":
					return
				sel = {"kind": meta["kind"], "id": int(meta["id"])}
				if tool != "select" and tool != "explode":
					tool = "select"
			refresh_view()
			app._refresh_panel()
		"cref":
			if tool == "mate":
				var r := MateGeom.origin_ref(str(meta["id"]))
				r["comp"] = int(meta["comp"])
				add_mate_ref(r)
			else:
				sel = {"kind": "comp", "id": int(meta["comp"])}
				refresh_view()
				app._refresh_panel()
		"asm":
			sel = {}
			refresh_view()
			app._refresh_panel()


func on_tree_activated(meta: Dictionary) -> void:
	if str(meta.get("kind", "")) == "comp":
		sel = {"kind": "comp", "id": int(meta["id"])}
		open_selected_part()


# ---------------------------------------------------------------- panel

func show_panel() -> void:
	var panel: PropertyPanel = app.panel
	panel.clear()
	if asm == null:
		return
	match tool:
		"mate":
			_panel_mate(panel)
		"move", "rotate":
			_panel_move(panel)
		"explode":
			_panel_explode(panel)
		"interf":
			_panel_interf(panel)
		"bom":
			_panel_bom(panel)
		"toolbox":
			_panel_toolbox(panel)
		"motion":
			_panel_motion(panel)
		"pattern":
			_panel_pattern(panel)
		"mass":
			_panel_mass(panel)
		_:
			if sel.get("kind", "") == "comp":
				_panel_comp(panel, asm.get_comp(int(sel["id"])))
			elif sel.get("kind", "") == "mate":
				_panel_mate_edit(panel, asm.get_mate(int(sel["id"])))
			elif sel.get("kind", "") == "pattern":
				_panel_pattern_edit(panel, asm.get_pattern(int(sel["id"])))
			else:
				_panel_asm(panel)
	if tool != "select":
		panel.spacer()
		panel.button("Kapat (Esc)", func(): set_tool("select"), Icons.get_icon("exit_sketch", 16))


func _panel_asm(panel: PropertyPanel) -> void:
	panel.title(asm.name, Icons.get_icon("assembly", 22))
	var nf := 0
	var under := 0
	for c in asm.comps:
		if bool(c.get("fixed", false)):
			nf += 1
		elif dof_of(int(c["id"])) > 0:
			under += 1
	panel.info(I18n.t("Bileşen: %d   (sabit: %d, eksik tanımlı: %d)\nEşleştirme: %d") % [asm.comps.size(), nf, under, asm.mates.size()])
	var bad: Array = last_solve.get("bad", [])
	if not bad.is_empty():
		panel.info(I18n.t("%d eşleştirme sağlanamıyor (ağaçta ⚠).") % bad.size(), Color(1.0, 0.45, 0.4))
	if _pending > 0:
		panel.info(I18n.t("Parçalar yükleniyor (%d)...") % _pending, Color(0.55, 0.85, 1.0))
	var lods := 0
	var tris := 0
	for k in parts:
		var pm: Mesh = parts[k].get("mesh", null)
		if pm != null:
			lods += int(int(pm.get_meta("lods", 0)) > 0)
	for c in asm.comps:
		var pm2: Mesh = parts.get(asm.key_of(c), {}).get("mesh", null)
		if pm2 != null:
			tris += int(pm2.get_meta("tris", 0))
	var big := view != null and view.large
	panel.info(I18n.t("Üçgen: %d   LOD'lu parça: %d%s") % [tris, lods, I18n.t("\nBüyük montaj modu: kenarlar yalnız seçili bileşende") if big else ""], Color(0.6, 0.66, 0.74))
	var on_big := func(i: int) -> void:
		large_auto = i == 0
		large_mode = i == 2
		refresh()
	panel.option("Büyük montaj modu", ["Otomatik", "Kapalı", "Her zaman"], 0 if large_auto else (2 if large_mode else 1), on_big)
	panel.button("Bileşen Ekle", func(): cmd("asm_insert"), Icons.get_icon("asm_insert", 16))
	panel.button("Bağlantı Elemanı Ekle", func(): cmd("asm_toolbox"), Icons.get_icon("asm_toolbox", 16))
	panel.button("Eşleştir", func(): cmd("asm_mate"), Icons.get_icon("asm_mate", 16))
	var on_coll := func(b: bool) -> void: collide_on = b
	panel.check("Sürüklerken çarpışmada dur", collide_on, on_coll)
	panel.info("İpucu: bileşeni sol tuşla sürükleyin; eşleştirmeler korunarak hareket eder. (f) sabit, (-) eksik tanımlı.", Color(0.55, 0.6, 0.66))


func _panel_comp(panel: PropertyPanel, c: Dictionary) -> void:
	if c.is_empty():
		return
	var id := int(c["id"])
	panel.title(str(c["name"]), Icons.get_icon("part", 22))
	var p: Dictionary = parts.get(asm.key_of(c), {})
	if c["src"].has("toolbox"):
		panel.info(I18n.t("Bağlantı elemanı: ") + Toolbox.designation(c["src"]["toolbox"]))
	else:
		panel.info(I18n.t("Parça: ") + str(c["src"].get("path", "")).get_file())
	if str(p.get("material", "")) != "":
		panel.info(I18n.t("Malzeme: ") + I18n.t(str(p["material"])))
	if str(p.get("error", "")) != "":
		panel.info(I18n.t("Hata: ") + str(p["error"]), Color(1.0, 0.45, 0.4))
	panel.info("Sabit" if bool(c.get("fixed", false)) else (I18n.t("Serbestlik derecesi: %d%s") % [dof_of(id), I18n.t("  (tam tanımlı)") if dof_of(id) == 0 else ""]),
		Color(0.55, 0.85, 1.0))
	var set_flag := func(b: bool, key: String) -> void:
		asm.checkpoint()
		c[key] = b
		asm.commit()
		solve()
		refresh()
	panel.check("Sabit", bool(c.get("fixed", false)), set_flag.bind("fixed"))
	panel.check("Gizli", bool(c.get("hidden", false)), set_flag.bind("hidden"))
	panel.check("Bastırılmış", bool(c.get("suppressed", false)), set_flag.bind("suppressed"))
	panel.section("Konum")
	var xf: Transform3D = c["xf"]
	var set_pos := func(v: float, axis: int) -> void:
		asm.checkpoint()
		var x2: Transform3D = c["xf"]
		var o := x2.origin
		o[axis] = v
		c["xf"] = Transform3D(x2.basis, o)
		asm.commit()
		solve()
		refresh()
	for k in 3:
		panel.number(["X", "Y", "Z"][k], xf.origin[k], set_pos.bind(k), "length")
	var mates := asm.mates_of(id)
	if not mates.is_empty():
		panel.section("Eşleştirmeler")
		var del_mate := func(mid: int) -> void:
			sel = {"kind": "mate", "id": mid}
			delete_selected()
		for m in mates:
			panel.item_row(str(m["name"]), Icons.get_icon("asm_mate", 16), del_mate.bind(int(m["id"])))
	panel.spacer()
	if not c["src"].has("toolbox"):
		panel.button("Parçayı Aç", open_selected_part, Icons.get_icon("asm_open", 16))
	else:
		_panel_toolbox_edit(panel, c)
	panel.button("Bileşeni Sil", delete_selected, Icons.get_icon("delete", 16))


func _panel_toolbox_edit(panel: PropertyPanel, c: Dictionary) -> void:
	var spec: Dictionary = c["src"]["toolbox"]
	var sizes := Toolbox.sizes_for(str(spec["type"]))
	var key := "dia" if str(spec["type"]) == "pin" else "size"
	var set_spec := func(v: Variant, k: String) -> void:
		asm.checkpoint()
		var s2: Dictionary = spec.duplicate()
		s2[k] = v
		c["src"] = {"toolbox": s2}
		asm.commit()
		load_parts()
		refresh()
	var on_size := func(i: int) -> void: set_spec.call(sizes[i], key)
	panel.option("Ölçü", sizes, maxi(sizes.find(str(spec.get(key, sizes[0]))), 0), on_size)
	if str(spec["type"]) in ["bolt", "pin"]:
		panel.number("Uzunluk", float(spec.get("length", 30)), set_spec.bind("length"), "length", 2.0, 500.0)


func _ref_desc(r: Dictionary) -> String:
	return MateGeom.describe(r, str(asm.get_comp(int(r["comp"])).get("name", "?")))


func _panel_mate(panel: PropertyPanel) -> void:
	panel.title("Eşleştir", Icons.get_icon("asm_mate", 22))
	if mate_type != "":
		var mt: Array = CadAssembly.MATE_TYPES[mate_type]
		panel.info(I18n.t("Tür: %s — %d referans") % [I18n.t(str(mt[0])), mt[1]], Color(0.55, 0.85, 1.0))
		var order := {"width": I18n.t("1-2: genişlik yüzleri (yerleşen bileşen), 3-4: kanal yüzleri"),
			"symmetric": I18n.t("1-2: simetrik yüz/eksenler, 3: simetri düzlemi"), "hinge": I18n.t("1-2: eksenler (silindirik yüzler), 3-4: çakışacak düzlemler"),
			"gear": I18n.t("1: dişli 1 silindirik yüzü, 2: dişli 2 silindirik yüzü (oran yarıçaplardan)"), "rack": I18n.t("1: kremayerin doğrusal kenarı, 2: pinyonun silindirik yüzü"),
			"screw": I18n.t("1-2: vida ve somun eksenleri"), "slot": I18n.t("1: pim (silindir veya nokta), 2: kanal orta çizgisi (doğrusal kenar)")}
		if order.has(mate_type):
			panel.info(order[mate_type], Color(0.6, 0.66, 0.72))
	panel.section(I18n.t("Seçimler (%d)") % mate_refs.size())
	if mate_refs.is_empty():
		panel.info("Modelde yüz veya kenara tıklayın.", Color(0.6, 0.66, 0.72))
	var rm_ref := func(k: int) -> void:
		mate_refs.remove_at(k)
		refresh()
	for i in mate_refs.size():
		panel.item_row("%d. %s" % [i + 1, _ref_desc(mate_refs[i])], Icons.get_icon("select", 14), rm_ref.bind(i))
	panel.section("Değer")
	panel.number("Mesafe / açı", float(mate_opts["value"]), func(v: float) -> void: mate_opts["value"] = v, "plain")
	panel.number("Sınır: en az", float(mate_opts["min"]), func(v: float) -> void: mate_opts["min"] = v, "plain")
	panel.number("Sınır: en çok", float(mate_opts["max"]), func(v: float) -> void: mate_opts["max"] = v, "plain")
	panel.number("Vida hatvesi", float(mate_opts.get("pitch", 1.25)), func(v: float) -> void: mate_opts["pitch"] = v, "length", 0.01, 100.0)
	var sugg: Array = []
	if mate_refs.size() >= 2:
		sugg = MateGeom.suggest_mates(mate_refs[0]["geo"], mate_refs[1]["geo"])
	var choose := func(tt: String) -> void:
		mate_type = tt
		apply_mate(tt)
	for grp in [["Standart", CadAssembly.STANDARD_MATES], [I18n.t("Gelişmiş"), CadAssembly.ADVANCED_MATES], [I18n.t("Mekanik"), CadAssembly.MECHANICAL_MATES]]:
		panel.section(grp[0])
		for t in grp[1]:
			var label: String = I18n.t(str(CadAssembly.MATE_TYPES[t][0])) + ("  ★" if t in sugg else "")
			panel.button(label, choose.bind(t), Icons.get_icon("asm_mate", 14))


func _panel_mate_edit(panel: PropertyPanel, m: Dictionary) -> void:
	if m.is_empty():
		return
	panel.title(str(m["name"]), Icons.get_icon("asm_mate", 22))
	var type := str(m["type"])
	panel.info(I18n.t("Tür: ") + CadAssembly.MATE_TYPES.get(type, [type])[0])
	for r in m["refs"]:
		panel.info("• " + _ref_desc(r), Color(0.7, 0.74, 0.8))
	if str(m.get("error", "")) != "":
		panel.info(str(m["error"]), Color(1.0, 0.45, 0.4))
	var upd := func(key: String, v: Variant) -> void:
		asm.checkpoint()
		m[key] = v
		asm.commit()
		solve()
		refresh()
	match type:
		"distance":
			panel.number("Mesafe", float(m.get("value", 0.0)), func(v: float) -> void: upd.call("value", v), "length", 0.0)
		"angle":
			panel.number("Açı", float(m.get("value", 0.0)), func(v: float) -> void: upd.call("value", v), "angle")
		"limit_distance":
			panel.number("En az", float(m.get("min", 0.0)), func(v: float) -> void: upd.call("min", v), "length")
			panel.number("En çok", float(m.get("max", 0.0)), func(v: float) -> void: upd.call("max", v), "length")
		"limit_angle":
			panel.number("En az", float(m.get("min", 0.0)), func(v: float) -> void: upd.call("min", v), "angle")
			panel.number("En çok", float(m.get("max", 90.0)), func(v: float) -> void: upd.call("max", v), "angle")
		"gear":
			panel.number("Oran A (yarıçap/diş)", float(m.get("ratio_a", 1.0)), func(v: float) -> void: upd.call("ratio_a", v), "plain", 0.001)
			panel.number("Oran B (yarıçap/diş)", float(m.get("ratio_b", 1.0)), func(v: float) -> void: upd.call("ratio_b", v), "plain", 0.001)
		"rack":
			panel.number("Pinyon hatve yarıçapı", float(m.get("value", 10.0)), func(v: float) -> void: upd.call("value", v), "length", 0.001)
		"screw":
			panel.number("Hatve (tur başına)", float(m.get("value", 1.0)), func(v: float) -> void: upd.call("value", v), "length", 0.001)
	if type in ["coincident", "distance", "limit_distance", "hinge"] and str(m.get("align", "")) != "":
		var flip_align := func() -> void: upd.call("align", "anti" if m["align"] == "aligned" else "aligned")
		panel.button(I18n.t("Hizalamayı çevir (%s)") % (I18n.t("aynı yön") if m["align"] == "aligned" else I18n.t("ters yön")), flip_align, Icons.get_icon("refresh", 16))
	if type in ["distance", "tangent", "angle", "gear", "rack", "screw", "limit_angle"]:
		panel.check("Yönü çevir", bool(m.get("flip", false)), func(b: bool) -> void: upd.call("flip", b))
	panel.check("Bastırılmış", bool(m.get("suppressed", false)), func(b: bool) -> void: upd.call("suppressed", b))
	panel.button("Eşleştirmeyi Sil", delete_selected, Icons.get_icon("delete", 16))


func _panel_move(panel: PropertyPanel) -> void:
	panel.title("Bileşeni Taşı" if tool == "move" else I18n.t("Bileşeni Döndür"), Icons.get_icon("asm_" + tool, 22))
	panel.info(str(TOOL_HINTS.get(tool, "")), Color(0.6, 0.66, 0.72))
	var on_coll := func(b: bool) -> void:
		collide_on = b
		if b and not _vp().kernel.is_brep():
			app._set_status("Çarpışma algılama OpenCASCADE çekirdeği gerektirir.")
	panel.check("Çarpışmada dur (OpenCASCADE)", collide_on, on_coll)
	if sel.get("kind", "") != "comp":
		panel.info("Sayısal giriş için bir bileşen seçin.")
		return
	var c := asm.get_comp(int(sel["id"]))
	panel.info(I18n.t("Seçili: ") + str(c["name"]))
	if not mate_opts.has("dx"):
		mate_opts.merge({"dx": 10.0, "dy": 0.0, "dz": 0.0, "ang": 90.0, "axis": 1})
	if tool == "move":
		for k in ["dx", "dy", "dz"]:
			var kk: String = k
			panel.number(kk.substr(1).to_upper(), float(mate_opts[kk]), func(v: float) -> void: mate_opts[kk] = v, "length")
		var do_move := func() -> void:
			asm.checkpoint()
			var xf: Transform3D = c["xf"]
			c["xf"] = Transform3D(xf.basis, xf.origin + Vector3(mate_opts["dx"], mate_opts["dy"], mate_opts["dz"]))
			asm.commit()
			solve()
			refresh()
		panel.button("Ötele", do_move, Icons.get_icon("asm_move", 16))
	else:
		panel.option("Eksen", ["X", "Y", "Z"], int(mate_opts["axis"]), func(i: int) -> void: mate_opts["axis"] = i)
		panel.number("Açı", float(mate_opts["ang"]), func(v: float) -> void: mate_opts["ang"] = v, "angle")
		var do_rot := func() -> void:
			var ax: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][int(mate_opts["axis"])]
			var m: ModelMesh = parts.get(asm.key_of(c), {}).get("model")
			asm.checkpoint()
			var xf: Transform3D = c["xf"]
			var ctr: Vector3 = xf * (m.aabb.get_center() if m != null else Vector3.ZERO)
			var rb := Basis(ax, deg_to_rad(float(mate_opts["ang"])))
			c["xf"] = Transform3D(rb * xf.basis, rb * (xf.origin - ctr) + ctr)
			asm.commit()
			solve()
			refresh()
		panel.button("Döndür", do_rot, Icons.get_icon("asm_rotate", 16))


func _panel_explode(panel: PropertyPanel) -> void:
	panel.title("Patlatılmış Görünüm", Icons.get_icon("asm_explode", 22))
	panel.info(I18n.t("Seçili bileşen: %d") % sel_comps.size())
	var names: Array = []
	for d in EX_DIRS:
		names.append(d[0])
	panel.option("Yön", names, ex_dir, func(i: int) -> void: ex_dir = i)
	panel.number("Mesafe", ex_dist, func(v: float) -> void: ex_dist = v, "length")
	panel.button("Adım ekle", add_explode_step, Icons.get_icon("new", 16))
	var do_auto := func() -> void:
		auto_explode()
		_explode_goal = 1.0
		refresh()
	panel.button("Otomatik patlat", do_auto, Icons.get_icon("asm_explode", 16))
	panel.button("Patlat / Topla", func(): cmd("asm_explode_toggle"), Icons.get_icon("asm_explode_toggle", 16))
	if not asm.explode.is_empty():
		panel.section("Adımlar")
		var rm_step := func(k: int) -> void:
			asm.checkpoint()
			asm.explode.remove_at(k)
			asm.commit()
			refresh()
		for i in asm.explode.size():
			var st: Dictionary = asm.explode[i]
			var cn: Array = []
			for id in st["comps"]:
				cn.append(str(asm.get_comp(int(id)).get("name", "?")))
			panel.item_row("%d. %s  (%s)" % [i + 1, ", ".join(cn), Units.format_length(float(st["dist"]))], Icons.get_icon("asm_explode", 14), rm_step.bind(i))


func _panel_interf(panel: PropertyPanel) -> void:
	panel.title("Girişim Tespiti", Icons.get_icon("asm_interf", 22))
	panel.button("Yeniden hesapla", run_interference, Icons.get_icon("refresh", 16))
	match interf_state:
		"running":
			panel.info("Hesaplanıyor...", Color(0.55, 0.85, 1.0))
		"error":
			panel.info("Girişim tespiti OpenCASCADE çekirdeği gerektirir.", Color(1.0, 0.45, 0.4))
		"done":
			if interf.is_empty():
				panel.info("Girişim yok ✓", Color(0.5, 0.9, 0.55))
			else:
				panel.info(I18n.t("%d girişim (kırmızı hacimler):") % interf.size(), Color(1.0, 0.6, 0.45))
				for it in interf:
					panel.info("• %s ↔ %s : %s³" % [asm.get_comp(int(it["a"])).get("name", "?"), asm.get_comp(int(it["b"])).get("name", "?"),
						Units.format_length(float(it["volume"]))], Color(0.85, 0.75, 0.7))


func _panel_bom(panel: PropertyPanel) -> void:
	panel.title("Malzeme Listesi", Icons.get_icon("asm_bom", 22))
	var total := 0
	for r in bom_rows():
		panel.info("%d.  %s   × %d\n     %s   %s" % [r["no"], r["name"], r["qty"], r["material"] if r["material"] != "" else "—",
			Units.format_mass(float(r["mass"]))], Color(0.8, 0.83, 0.88))
		total += int(r["qty"])
	panel.info(I18n.t("Toplam parça adedi: %d") % total, Color(0.55, 0.85, 1.0))
	panel.button(I18n.t("CSV olarak kaydet"), func(): cmd("asm_bom_csv"), Icons.get_icon("export", 16))


func _panel_toolbox(panel: PropertyPanel) -> void:
	panel.title("Bağlantı Elemanları", Icons.get_icon("asm_toolbox", 22))
	var types: Array = Toolbox.TYPES.keys()
	var tn: Array = []
	for t in types:
		tn.append(Toolbox.TYPES[t])
	var on_type := func(i: int) -> void:
		tb_spec = {"type": types[i], "size": Toolbox.sizes_for(types[i])[0], "length": 20}
		if types[i] == "pin":
			tb_spec = {"type": "pin", "dia": "6", "length": 20}
		elif types[i] == "bolt":
			tb_spec["size"] = "M8"
			tb_spec["length"] = 30
		app._refresh_panel()
	panel.option("Tür", tn, maxi(types.find(str(tb_spec["type"])), 0), on_type)
	var sizes := Toolbox.sizes_for(str(tb_spec["type"]))
	var key := "dia" if tb_spec["type"] == "pin" else "size"
	var on_size := func(i: int) -> void:
		tb_spec[key] = sizes[i]
		app._refresh_panel()
	panel.option("Ölçü", sizes, maxi(sizes.find(str(tb_spec.get(key, ""))), 0), on_size)
	if str(tb_spec["type"]) in ["bolt", "pin"]:
		var on_len := func(v: float) -> void:
			tb_spec["length"] = v
			app._refresh_panel()
		panel.number("Uzunluk", float(tb_spec.get("length", 30)), on_len, "length", 2.0, 500.0)
	panel.info(Toolbox.designation(tb_spec), Color(0.55, 0.85, 1.0))
	var do_add := func() -> void:
		var c := insert_toolbox(tb_spec)
		app._set_status(I18n.t("%s eklendi — eşleştirmelerle konumlandırın (örn. eş merkezli + çakışık).") % c["name"])
	panel.button("Montaja ekle", do_add, Icons.get_icon("new", 16))


func _panel_motion(panel: PropertyPanel) -> void:
	panel.title("Hareket Etüdü", Icons.get_icon("asm_motion", 22))
	panel.info(str(TOOL_HINTS["motion"]), Color(0.6, 0.66, 0.72))
	var r: Dictionary = motion["ref"]
	panel.info(I18n.t("Motor ekseni: ") + (_ref_desc(r) if not r.is_empty() else I18n.t("<seçilmedi>")))
	panel.number("Hız (dev/dk)", float(motion["rpm"]), func(v: float) -> void: motion["rpm"] = v, "plain", -1000.0, 1000.0)
	panel.number("Süre (sn)", float(motion["dur"]), func(v: float) -> void: motion["dur"] = v, "plain", 0.1, 600.0)
	var do_stop := func() -> void:
		_stop_motion()
		app._refresh_panel()
	var do_play := func() -> void:
		start_motion()
		app._refresh_panel()
	if bool(motion.get("playing", false)):
		panel.button("Durdur", do_stop, Icons.get_icon("delete", 16))
	else:
		panel.button("Oynat", do_play, Icons.get_icon("asm_motion", 16))
	panel.button("Başa dön", reset_motion, Icons.get_icon("refresh", 16))


func _panel_pattern(panel: PropertyPanel) -> void:
	panel.title("Bileşen Çoğaltma", Icons.get_icon("asm_pattern", 22))
	panel.info(str(TOOL_HINTS["pattern"]), Color(0.6, 0.66, 0.72))
	var names: Array = []
	for id in sel_comps:
		names.append(str(asm.get_comp(int(id)).get("name", "?")))
	panel.info(I18n.t("Çoğaltılacak: ") + (", ".join(names) if not names.is_empty() else I18n.t("<seçilmedi>")))
	var types := ["linear", "circular"]
	var on_t := func(i: int) -> void:
		pat_opts["type"] = types[i]
		app._refresh_panel()
	panel.option("Tür", [I18n.t("Doğrusal"), I18n.t("Dairesel")], types.find(str(pat_opts["type"])), on_t)
	var on_ax := func(i: int) -> void:
		pat_opts["axis"] = i
		pat_opts["pick_dir"] = i == 3
		refresh()
	panel.option("Yön / eksen", ["X", "Y", "Z", I18n.t("Modelden seç (kenar, eksen, yüz)")], int(pat_opts["axis"]), on_ax)
	if int(pat_opts["axis"]) == 3:
		var rr: Dictionary = pat_opts["ref"]
		panel.info((I18n.t("Yön: ") + _ref_desc(rr)) if not rr.is_empty() else I18n.t("Modelde kenar / silindirik yüz / düzlemsel yüze tıklayın."), Color(0.55, 0.85, 1.0))
		var again := func() -> void: pat_opts["pick_dir"] = true
		panel.button("Yönü yeniden seç", again, Icons.get_icon("select", 16))
	var on_c := func(v: float) -> void: pat_opts["count"] = int(v)
	panel.number("Örnek sayısı", float(pat_opts["count"]), on_c, "plain", 2.0, 500.0)
	if pat_opts["type"] == "circular":
		var on_tot := func(v: float) -> void: pat_opts["total"] = v
		panel.number("Toplam açı (360: eşit aralık)", float(pat_opts["total"]), on_tot, "angle", 1.0, 360.0)
	else:
		var on_sp := func(v: float) -> void: pat_opts["spacing"] = v
		panel.number("Aralık", float(pat_opts["spacing"]), on_sp, "length")
	var on_rev := func(b: bool) -> void: pat_opts["reverse"] = b
	panel.check("Yönü ters çevir", bool(pat_opts["reverse"]), on_rev)
	panel.button("Uygula", create_pattern, Icons.get_icon("asm_pattern", 16))


func _panel_pattern_edit(panel: PropertyPanel, p: Dictionary) -> void:
	if p.is_empty():
		return
	panel.title(str(p["name"]), Icons.get_icon("asm_pattern", 22))
	var names: Array = []
	for id in p["seeds"]:
		names.append(str(asm.get_comp(int(id)).get("name", "?")))
	panel.info(I18n.t("Çekirdek: ") + ", ".join(names))
	var dirv: Dictionary = p.get("dir", {})
	panel.info(I18n.t("Yön: ") + (str(dirv["axis"]).to_upper() + I18n.t(" ekseni") if dirv.has("axis") else _ref_desc(dirv.get("ref", {}))))
	if not (p.get("skip", []) as Array).is_empty():
		panel.info(I18n.t("Atlanan örnek: %d") % (p["skip"] as Array).size(), Color(0.6, 0.66, 0.72))
	var upd := func(v: Variant, key: String) -> void:
		asm.checkpoint()
		p[key] = v
		_regen_instances(p)
		asm.commit()
		solve()
		refresh()
	panel.number("Örnek sayısı", float(p["count"]), func(v: float) -> void: upd.call(int(v), "count"), "plain", 2.0, 500.0)
	if str(p["type"]) == "circular":
		panel.number("Toplam açı", float(p.get("total", 360.0)), upd.bind("total"), "angle", 1.0, 360.0)
	else:
		panel.number("Aralık", float(p.get("spacing", 30.0)), upd.bind("spacing"), "length")
	panel.check("Yönü ters çevir", bool(p.get("reverse", false)), upd.bind("reverse"))
	var clear_skip := func() -> void:
		asm.checkpoint()
		p["skip"] = []
		_regen_instances(p)
		asm.commit()
		solve()
		refresh()
	if not (p.get("skip", []) as Array).is_empty():
		panel.button("Atlanan örnekleri geri getir", clear_skip, Icons.get_icon("refresh", 16))
	panel.button("Çoğaltmayı Sil", delete_selected, Icons.get_icon("delete", 16))


func _panel_mass(panel: PropertyPanel) -> void:
	panel.title("Montaj Kütle Özellikleri", Icons.get_icon("asm_mass", 22))
	var t := mass_totals()
	var c: Vector3 = t["center"]
	panel.info(I18n.t("Kütle: %s\nHacim: %s³\nAğırlık merkezi:\n  X %s  Y %s  Z %s") % [Units.format_mass(float(t["mass"])), Units.format_length(float(t["volume"])),
		Units.format_length(c.x), Units.format_length(c.y), Units.format_length(c.z)], Color(0.8, 0.85, 0.9))
	panel.info("Malzemesi belirtilmeyen parçalarda varsayılan yoğunluk kullanılır.", Color(0.55, 0.6, 0.66))


# ---------------------------------------------------------------- örnek montaj (tanıtım / ekran görüntüsü)

## Örnek parçayı geçici dosyaya kaydedip üzerine 4 cıvata + pul + somun ve rulman ekler; eşleştirmeler kurulur.
func build_demo() -> void:
	var dir := OS.get_user_data_dir().path_join("ornek_montaj")
	DirAccess.make_dir_recursive_absolute(dir)
	var pd := CadDocument.new()
	DemoParts.build_bracket(pd)
	var ppath := dir.path_join("OrnekParca.dcad")
	pd.save_to(ppath)
	new_assembly()
	asm.name = "OrnekMontaj"
	_demo_stage = 1
	insert_file(ppath)
	for i in 4:
		insert_toolbox({"type": "bolt", "size": "M6", "length": 20})
	for i in 4:
		insert_toolbox({"type": "washer", "size": "M6"})
	for i in 4:
		insert_toolbox({"type": "nut", "size": "M6"})


var _demo_stage := 0


## Parçalar yüklendikten sonra örnek eşleştirmeleri kurar. Referanslar bilinen ölçülerden üretilir
## (B-rep varsa eşleşen yüzün adı da eklenir; CSG çekirdeğinde de çalışır).
func finish_demo() -> bool:
	if _demo_stage != 1 or _pending > 0:
		return false
	_demo_stage = 2
	var mk := func(comp: Dictionary, g: Dictionary) -> Dictionary:
		var r := {"comp": int(comp["id"]), "kind": "face", "name": "", "fid": -1, "geo": g, "label": MateGeom.TYPE_NAMES.get(g["t"], "Yüz")}
		var m: ModelMesh = parts.get(asm.key_of(comp), {}).get("model")
		if m != null and m.has_brep():
			for info in m.brep_faces:
				var gi := MateGeom.geo_from_face_info(info)
				if gi.is_empty() or gi["t"] != g["t"]:
					continue
				var same := false
				if g["t"] == "plane":
					same = MateGeom.v3(gi["n"]).dot(MateGeom.v3(g["n"])) > 0.9999 and absf((MateGeom.v3(gi["p"]) - MateGeom.v3(g["p"])).dot(MateGeom.v3(g["n"]))) < 1e-4
				else:
					var d := MateGeom.v3(g["d"])
					var q := MateGeom.v3(gi["p"]) - MateGeom.v3(g["p"])
					same = absf(float(gi["r"]) - float(g["r"])) < 1e-4 and (q - d * q.dot(d)).length() < 1e-4
				if same:
					r["name"] = str(info.get("name", ""))
					r["fid"] = int(info["id"])
					r["geo"] = gi
					break
		return r
	var base: Dictionary = asm.comps[0]
	var M: Dictionary = Toolbox.METRIC["M6"]
	var w: Array = M["w"]
	var top := {"t": "plane", "p": [0, 8, 0], "n": [0, 1, 0]}
	var bottom := {"t": "plane", "p": [0, 0, 0], "n": [0, -1, 0]}
	var hole_pos := [Vector3(-30, 0, 15), Vector3(30, 0, 15), Vector3(30, 0, -15), Vector3(-30, 0, -15)]
	for i in 4:
		var bolt: Dictionary = asm.comps[1 + i]
		var washer: Dictionary = asm.comps[5 + i]
		var nut: Dictionary = asm.comps[9 + i]
		var hp: Vector3 = hole_pos[i]
		var hole: Dictionary = mk.call(base, {"t": "cyl", "p": [hp.x, 0, hp.z], "d": [0, 1, 0], "r": 3.5})
		# Pul plakanın üstünde, cıvata başı pulun üstünde, somun plakanın altında
		mate_refs = [hole, mk.call(washer, {"t": "cyl", "p": [0, 0, 0], "d": [0, 1, 0], "r": float(w[0]) * 0.5})]
		apply_mate("concentric")
		mate_refs = [mk.call(base, top), mk.call(washer, {"t": "plane", "p": [0, 0, 0], "n": [0, -1, 0]})]
		apply_mate("coincident")
		mate_refs = [hole, mk.call(bolt, {"t": "cyl", "p": [0, 0, 0], "d": [0, 1, 0], "r": float(M["d"]) * 0.5})]
		apply_mate("concentric")
		mate_refs = [mk.call(washer, {"t": "plane", "p": [0, float(w[2]), 0], "n": [0, 1, 0]}), mk.call(bolt, {"t": "plane", "p": [0, 0, 0], "n": [0, -1, 0]})]
		apply_mate("coincident")
		mate_refs = [hole, mk.call(nut, {"t": "cyl", "p": [0, 0, 0], "d": [0, 1, 0], "r": float(M["d"]) * 0.5})]
		apply_mate("concentric")
		mate_refs = [mk.call(base, bottom), mk.call(nut, {"t": "plane", "p": [0, float(M["m"]), 0], "n": [0, 1, 0]})]
		apply_mate("coincident")
	sel = {}
	asm.dirty = false
	solve()
	refresh()
	fit(false)
	return true


# ---------------------------------------------------------------- montaj bağlamında parça düzenleme

var context_id := -1


func context_active() -> bool:
	return asm != null and context_id >= 0 and view != null and view.visible


## Parça düzenlenirken diğer bileşenleri parçanın koordinat sisteminde yarı saydam göster.
func show_context(comp_id: int) -> void:
	if asm == null or view == null:
		return
	var c := asm.get_comp(comp_id)
	if c.is_empty():
		return
	context_id = comp_id
	view.transform = (c["xf"] as Transform3D).affine_inverse()
	view.ghost = true
	view.skip_id = comp_id
	view.visible = true
	view.sync(asm, parts, {}, [], -1)
	view.set_interference([])
	view.set_lines([])


func clear_context() -> void:
	context_id = -1
	if view != null:
		view.transform = Transform3D.IDENTITY
		view.ghost = false
		view.skip_id = -1


## Bağlamdaki yüz seçimi (parça koordinatlarında ışın). Dönüş: {planar, point, normal, dist, pts} veya {}
func context_pick(from: Vector3, dir: Vector3) -> Dictionary:
	if not context_active():
		return {}
	var ec := asm.get_comp(context_id)
	var exf: Transform3D = ec["xf"]
	var hit := view.pick(asm, parts, exf * from, (exf.basis * dir).normalized(), {}, context_id)
	if hit.is_empty():
		return {}
	var c := asm.get_comp(int(hit["comp"]))
	var m: ModelMesh = parts.get(asm.key_of(c), {}).get("model")
	var r := MateGeom.face_ref(m, int(hit["tri"]), hit["local"])
	if r.is_empty():
		return {}
	r["comp"] = int(hit["comp"])
	var inv := exf.affine_inverse()
	var w := MateSolver.to_world(r["geo"], c["xf"])
	var pts := PackedVector3Array()
	for q in _ref_tris(r):
		pts.append(inv * q)
	var out := {"planar": str(r["geo"]["t"]) == "plane", "dist": float(hit["dist"]), "pts": pts, "point": inv * (hit["world"] as Vector3)}
	if out["planar"]:
		out["normal"] = (inv.basis * (w["n"] as Vector3)).normalized()
		out["point"] = inv * (w["p"] as Vector3)
	else:
		out["normal"] = (inv.basis * m.normals[int(hit["tri"])]).normalized()
	return out


## Montaj içinde yeni (boş) parça: dosyası oluşturulur, montaj orijininde sabit bileşen olarak eklenir ve
## diğer bileşenler bağlam olarak görünürken düzenlemeye açılır.
func new_part_in_context(path: String) -> void:
	var d := CadDocument.new()
	d.load_dict({})
	d.part_name = path.get_file().get_basename()
	if d.save_to(path) != OK:
		app._set_status(I18n.t("Parça dosyası oluşturulamadı: ") + path)
		return
	asm.checkpoint()
	var c := asm.add_component({"path": path.simplify_path()}, Transform3D.IDENTITY, d.part_name)
	c["fixed"] = true
	asm.commit()
	if asm.file_path != "":
		asm.save_to(asm.file_path)
	sel = {"kind": "comp", "id": int(c["id"])}
	load_parts()
	app.open_part_from_assembly(path, int(c["id"]))
	app._set_status(I18n.t("Yeni parça '%s' montaj bağlamında açıldı: diğer bileşenlerin düzlemsel yüzlerine tıklayıp taslak açabilirsiniz. Bitince 'Montaj' sekmesi.") % d.part_name)
