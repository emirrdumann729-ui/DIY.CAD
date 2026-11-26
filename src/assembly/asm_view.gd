class_name AssemblyView
extends Node3D
## Montaj 3B görünümü: her bileşen için parça ağı + kenar çizgileri (dönüşümüyle), seçim/vurgu,
## girişim hacimleri (kırmızı) ve patlatma çizgileri. Işınla seçim bileşen yerel uzayında yapılır.

const PALETTE := [Color(0.72, 0.76, 0.82), Color(0.85, 0.72, 0.48), Color(0.55, 0.72, 0.86), Color(0.70, 0.82, 0.62),
	Color(0.86, 0.62, 0.62), Color(0.75, 0.66, 0.86), Color(0.86, 0.80, 0.55), Color(0.60, 0.80, 0.78)]

var line_mat: Material
var nodes := {}          # comp id -> {root: Node3D, mi: MeshInstance3D, edges: MeshInstance3D, mat: StandardMaterial3D, key}
var interf_mi: MeshInstance3D
var lines_mi: MeshInstance3D
var interf_mat: StandardMaterial3D
var _edge_meshes := {}   # part key -> ArrayMesh
var ghost := false       # bağlam görünümü: yarı saydam, kenarsız
var skip_id := -1        # gösterilmeyen bileşen (düzenlenen parça)
var large := false       # büyük montaj modu: kenarlar yalnız seçili / üzerine gelinen bileşende (Faz 9)
var _sel: Array = []
var _hover := -1


func _ready() -> void:
	interf_mat = StandardMaterial3D.new()
	interf_mat.albedo_color = Color(1.0, 0.15, 0.1, 0.75)
	interf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	interf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	interf_mat.no_depth_test = true
	interf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	interf_mi = MeshInstance3D.new()
	interf_mi.mesh = ArrayMesh.new()
	interf_mi.material_override = interf_mat
	add_child(interf_mi)
	lines_mi = MeshInstance3D.new()
	lines_mi.mesh = ArrayMesh.new()
	lines_mi.material_override = line_mat
	add_child(lines_mi)


func clear() -> void:
	for id in nodes:
		(nodes[id]["root"] as Node3D).queue_free()
	nodes.clear()
	_edge_meshes.clear()
	set_interference([])
	set_lines([])


func _edges_mesh(key: String, part: Dictionary) -> ArrayMesh:
	if _edge_meshes.has(key):
		return _edge_meshes[key]
	var am := ArrayMesh.new()
	var model: ModelMesh = part.get("model")
	if model != null and not model.is_empty():
		var lb := LineBuilder.new()
		var col := Color(0.05, 0.05, 0.08)
		for i in range(0, model.feature_edges.size() - 1, 2):
			lb.line(model.feature_edges[i], model.feature_edges[i + 1], col)
		lb.commit(am)
	_edge_meshes[key] = am
	return am


func invalidate_part(key: String) -> void:
	_edge_meshes.erase(key)


## asm: CadAssembly; parts: key -> {model, mesh (görüntü), color}; offsets: comp id -> Vector3 (patlatma)
func sync(asm: CadAssembly, parts: Dictionary, offsets := {}, sel := [], hover := -1) -> void:
	_sel = sel
	_hover = hover
	var seen := {}
	var idx := 0
	for c in asm.comps:
		var id := int(c["id"])
		seen[id] = true
		var key := asm.key_of(c)
		var part: Dictionary = parts.get(key, {})
		var n: Dictionary = nodes.get(id, {})
		if n.is_empty() or n["key"] != key or n.get("mesh_ver", -1) != int(part.get("ver", 0)):
			if not n.is_empty():
				(n["root"] as Node3D).queue_free()
			n = _make_node(key, part)
			n["mesh_ver"] = int(part.get("ver", 0))
			nodes[id] = n
		var root: Node3D = n["root"]
		var xf: Transform3D = c["xf"]
		root.transform = Transform3D(xf.basis, xf.origin + (offsets.get(id, Vector3.ZERO) as Vector3))
		root.visible = not bool(c.get("hidden", false)) and not bool(c.get("suppressed", false)) and id != skip_id
		var base: Color = part.get("color", PALETTE[idx % PALETTE.size()])
		var mat: StandardMaterial3D = n["mat"]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if ghost else BaseMaterial3D.TRANSPARENCY_DISABLED
		(n["edges"] as MeshInstance3D).visible = not ghost and (not large or id in sel or id == hover)
		if ghost:
			mat.albedo_color = Color(base.r, base.g, base.b, 0.3)
			idx += 1
			continue
		if id in sel:
			mat.albedo_color = Color(0.35, 0.62, 1.0)
		elif id == hover:
			mat.albedo_color = base.lerp(Color(0.45, 0.7, 1.0), 0.35)
		else:
			mat.albedo_color = base
		idx += 1
	for id in nodes.keys():
		if not seen.has(id):
			(nodes[id]["root"] as Node3D).queue_free()
			nodes.erase(id)


func _make_node(key: String, part: Dictionary) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var mi := MeshInstance3D.new()
	mi.mesh = part.get("mesh", null)
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.55
	mat.metallic = 0.15
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var em := MeshInstance3D.new()
	em.mesh = _edges_mesh(key, part)
	em.material_override = line_mat
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(em)
	return {"root": root, "mi": mi, "edges": em, "mat": mat, "key": key}


func set_edges_visible(v: bool) -> void:
	for id in nodes:
		(nodes[id]["edges"] as MeshInstance3D).visible = v and not ghost and (not large or id in _sel or id == _hover)


## Girişim hacimleri: [PackedVector3Array üçgen köşeleri (Godot sarımı)]
func set_interference(tri_sets: Array) -> void:
	var am: ArrayMesh = interf_mi.mesh
	am.clear_surfaces()
	var all := PackedVector3Array()
	for t in tri_sets:
		all.append_array(t)
	if all.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = all
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


## Patlatma çizgileri vb.: [[a, b], ...]
func set_lines(segs: Array, col := Color(0.95, 0.55, 0.1)) -> void:
	var lb := LineBuilder.new()
	for s in segs:
		lb.line(s[0], s[1], col)
	lb.commit(lines_mi.mesh)


## Işın ile bileşen seçimi. Dönüş: {comp, tri, local, world, dist} veya {}
func pick(asm: CadAssembly, parts: Dictionary, from: Vector3, dir: Vector3, offsets := {}, skip := -1) -> Dictionary:
	var best := {}
	var bd := INF
	for c in asm.comps:
		if bool(c.get("hidden", false)) or bool(c.get("suppressed", false)) or int(c["id"]) == skip:
			continue
		var part: Dictionary = parts.get(asm.key_of(c), {})
		var model: ModelMesh = part.get("model")
		if model == null or model.is_empty():
			continue
		var xf := comp_world(c, offsets)
		var inv := xf.affine_inverse()
		var hit := model.raycast(inv * from, (inv.basis * dir).normalized())
		if hit.is_empty():
			continue
		var d := float(hit["dist"])
		if d < bd:
			bd = d
			best = {"comp": int(c["id"]), "tri": int(hit["tri"]), "local": hit["point"], "world": xf * (hit["point"] as Vector3), "dist": d}
	return best


static func comp_world(c: Dictionary, offsets: Dictionary) -> Transform3D:
	var xf: Transform3D = c["xf"]
	return Transform3D(xf.basis, xf.origin + (offsets.get(int(c["id"]), Vector3.ZERO) as Vector3))


## Montajın dünya sınır kutusu
func world_aabb(asm: CadAssembly, parts: Dictionary, offsets := {}) -> AABB:
	var box := AABB()
	var first := true
	for c in asm.comps:
		if bool(c.get("hidden", false)) or bool(c.get("suppressed", false)):
			continue
		var model: ModelMesh = parts.get(asm.key_of(c), {}).get("model")
		if model == null or model.is_empty():
			continue
		var xf := comp_world(c, offsets)
		var a := model.aabb
		for i in 8:
			var p := xf * (a.position + Vector3(a.size.x * (i & 1), a.size.y * ((i >> 1) & 1), a.size.z * ((i >> 2) & 1)))
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box
