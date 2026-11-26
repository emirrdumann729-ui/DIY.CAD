extends RefCounted
## Örnek makro: açık parçayı STL, STEP ve PNG olarak dışa aktarır (parça dosyasının yanına, yoksa Belgeler).


func run(m: MacroApi) -> void:
	if m.doc.features.is_empty():
		m.message("Önce bir parça açın.")
		return
	var dir := m.doc.file_path.get_base_dir() if m.doc.file_path != "" else OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var base := dir.path_join(m.doc.part_name)
	m.view("iso")
	await m.rebuild()
	await m.export(base + ".stl")
	if m.app.viewport.kernel.is_brep():
		await m.export(base + ".step")
	await m.export(base + ".png")
	m.message("Dışa aktarıldı: %s.stl / .step / .png" % base)
