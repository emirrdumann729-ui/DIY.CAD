extends RefCounted
## Örnek eklenti: parça özeti (özellik türleri, boyut kutusu, hacim, kütle, üçgen sayısı); model
## değiştikçe panel kendini günceller.

const NAME := "Parça Bilgisi"
const DESCRIPTION := "Özellik sayıları, boyut kutusu, hacim / alan / kütle ve ağ bilgisini gösteren canlı panel."

var api: PluginApi


func setup(a: PluginApi) -> void:
	api = a
	api.add_command("plg_parca_bilgisi", "Parça\nBilgisi", "Parça özeti (canlı güncellenir)", "mass", open)
	api.on_built(_on_built)


func open() -> void:
	api.show_panel("Parça Bilgisi", _build)


func _on_built() -> void:
	api.refresh_panel()


## Özet sözlüğü (testler de kullanır)
func summary() -> Dictionary:
	var d: CadDocument = api.doc()
	var counts := {}
	for f in d.features:
		var lbl: String = f.type_label()
		counts[lbl] = int(counts.get(lbl, 0)) + 1
	var mm: ModelMesh = api.model()
	var va := mm.volume_and_area() if not mm.is_empty() else Vector2.ZERO
	var dens := Materials.density_of(d.material) if d.material != "" else 1.0
	return {"features": d.features.size(), "counts": counts, "size": mm.aabb.size if not mm.is_empty() else Vector3.ZERO,
		"volume": va.x, "area": va.y, "mass_g": va.x * dens / 1000.0, "tris": mm.tri_count()}


func _build(panel: PropertyPanel) -> void:
	var s := summary()
	var d: CadDocument = api.doc()
	panel.info("%s%s" % [d.part_name, ("  (" + d.file_path.get_file() + ")") if d.file_path != "" else ""])
	panel.section("Özellikler (%d)" % int(s["features"]))
	var lines: PackedStringArray = []
	for k in s["counts"]:
		lines.append("%s: %d" % [k, s["counts"][k]])
	panel.info("\n".join(lines) if not lines.is_empty() else "—")
	panel.section("Geometri")
	var sz: Vector3 = s["size"]
	panel.info("Boyut kutusu: %s × %s × %s\nHacim: %.1f mm³\nYüzey alanı: %.1f mm²\nKütle: %.2f g (%s)\nÜçgen: %d" % [
		Units.format_length(sz.x), Units.format_length(sz.y), Units.format_length(sz.z), float(s["volume"]), float(s["area"]),
		float(s["mass_g"]), d.material if d.material != "" else "malzeme yok, 1 g/cm³", int(s["tris"])], Color(0.55, 0.85, 1.0))
	panel.info("Model her yeniden oluşturulduğunda güncellenir.", Color(0.6, 0.65, 0.72))
