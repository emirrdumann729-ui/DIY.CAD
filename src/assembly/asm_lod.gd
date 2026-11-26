class_name AsmLod
extends RefCounted
## Büyük montajlar için ayrıntı seviyesi (Faz 9). Bileşen ağlarına Godot'nun otomatik LOD'u eklenir
## (ImporterMesh.generate_lods: kenar birleştirerek sadeleştirilmiş ağlar); kamera uzaklaştıkça ekranda
## küçülen bileşenler daha az üçgenle çizilir. Büyük montaj modunda kenar çizgileri yalnızca seçili /
## üzerine gelinen bileşende gösterilir.

const MIN_TRIS := 4000          # bundan küçük ağlara LOD eklenmez
const BIG_TRIS := 400000        # toplam üçgen bunu aşarsa büyük montaj modu (otomatik)
const BIG_COMPS := 80           # veya bileşen sayısı bunu aşarsa


static func tri_count(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var arr := mesh.surface_get_arrays(0)
	var idx = arr[Mesh.ARRAY_INDEX]
	if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
		return (idx as PackedInt32Array).size() / 3
	return (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


## Gösterim ağına LOD ekle (küçükse olduğu gibi döner). Meta: "lods" = LOD sayısı, "tris" = üçgen sayısı
static func with_lods(mesh: ArrayMesh) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var n := tri_count(mesh)
	mesh.set_meta("tris", n)
	if n < MIN_TRIS:
		mesh.set_meta("lods", 0)
		return mesh
	var st := SurfaceTool.new()
	st.create_from_arrays(mesh.surface_get_arrays(0))
	st.index()
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	im.generate_lods(25.0, 60.0, [])
	var out := im.get_mesh()
	out.set_meta("lods", im.get_surface_lod_count(0))
	out.set_meta("tris", n)
	return out


## Montaj büyük mü (otomatik büyük montaj modu için)
static func is_big(asm: CadAssembly, parts: Dictionary) -> bool:
	if asm.comps.size() > BIG_COMPS:
		return true
	var total := 0
	for c in asm.comps:
		var p: Dictionary = parts.get(asm.key_of(c), {})
		var m: Mesh = p.get("mesh", null)
		if m != null:
			total += int(m.get_meta("tris", 0))
	return total > BIG_TRIS
