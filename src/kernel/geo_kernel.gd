class_name GeoKernel
extends Node3D
## Geometri çekirdeği seçici: OpenCASCADE (B-rep, Faz 4) varsa onu, yoksa Godot CSG'yi kullanır.
## Arayüz CSG çekirdeğiyle aynıdır: rebuild(doc, preview) -> built(mesh) sinyali; ek olarak
## son sonucun B-rep bilgisi `brep` içinde tutulur (CSG'de boş sözlük).
##
## mode: "auto" (OCC hazırsa OCC, hazırlanırken CSG), "occ" (OCC'yi bekle), "csg" (yalnızca CSG).

signal built(mesh: ArrayMesh)
signal backend_changed(backend: String)
signal export_done(result: Dictionary)
signal hlr_done(result: Dictionary)
signal part_built(key: String, mesh: ArrayMesh, brep: Dictionary)
signal asm_done(result: Dictionary)

const SETTINGS_PATH := "user://diycad.cfg"
const BREP_ONLY := ["fillet", "chamfer", "shell", "import", "draft", "rib", "combine", "move_body", "split",
	"sweep", "loft", "lpattern", "cpattern", "mirror", "tpattern", "hole", "dome", "cvpattern", "projcurve", "wrap", "emboss",
	"sm_base", "sm_edge", "weld", "srf_extrude", "srf_revolve", "srf_loft", "srf_planar", "srf_offset", "srf_knit", "srf_thicken", "srf_trim"]

var mode := "auto"
var csg: CsgKernel
var occ: OccKernel
var brep := {}

var _last_doc: CadDocument = null
var _last_preview: CadFeature = null
var _last_before := false
var _active := "csg"      # son isteğin gittiği çekirdek
var _part_csg: CsgKernel = null   # montaj parçaları için ayrı CSG çekirdeği (ana modeli bozmaz)
var _part_queue: Array = []       # [[doc, key]] CSG ile sırayla derlenecek parçalar
var _part_busy := ""
## Faz 9: ağ işleme arka planda (WorkerThreadPool). Hazır model `prepared` ile görünüme verilir.
var threaded := true
var prepared := {}                # {mesh, model, display}
var last_post_ms := 0.0
var _job: MeshJob = null
var _job_id := -1
var _job_mesh: ArrayMesh = null
var _job_brep := {}
var _queued: Array = []           # iş sürerken gelen en yeni sonuç [mesh, brep]


func _ready() -> void:
	csg = CsgKernel.new()
	add_child(csg)
	occ = OccKernel.new()
	add_child(occ)
	csg.built.connect(_on_csg_built)
	occ.built.connect(_on_occ_built)
	occ.ready_changed.connect(_on_occ_ready)
	occ.export_done.connect(func(r: Dictionary) -> void: export_done.emit(r))
	occ.hlr_done.connect(func(r: Dictionary) -> void: hlr_done.emit(r))
	occ.part_built.connect(func(k: String, m: ArrayMesh, b: Dictionary) -> void: part_built.emit(k, m, b))
	occ.asm_done.connect(func(r: Dictionary) -> void: asm_done.emit(r))
	mode = load_mode()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kernel="):
			mode = a.substr(9)
	if mode != "csg":
		occ.start()


static func load_mode() -> String:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		return str(cf.get_value("kernel", "mode", "auto"))
	return "auto"


func set_mode(m: String) -> void:
	mode = m
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("kernel", "mode", m)
	cf.save(SETTINGS_PATH)
	if m != "csg" and (occ.state == "off" or occ.state == "failed"):
		occ.state = "off"
		occ.start()
	backend_changed.emit(backend())
	_rerun()


## Etkin çekirdek: "occ" | "csg"
func backend() -> String:
	if mode == "csg":
		return "csg"
	if occ.is_ready():
		return "occ"
	if mode == "occ" and occ.state == "starting":
		return "occ"
	return "csg"


func backend_label() -> String:
	match backend():
		"occ":
			return "OpenCASCADE" + ("" if occ.is_ready() else " (başlatılıyor...)")
	return "CSG"


func status_text() -> String:
	var t := "Çekirdek: " + backend_label()
	if mode != "csg" and occ.state == "failed":
		t += " — OCC kullanılamıyor: " + occ.fail_reason
	elif mode == "auto" and occ.state == "starting":
		t += " — OpenCASCADE başlatılıyor"
	return t


func is_brep() -> bool:
	return backend() == "occ"


## show_before: önizleme özelliğinden önceki gövdeyi göster (yuvarlatma/pah/kabuk seçimi için).
func rebuild(doc: CadDocument, preview: CadFeature = null, show_before := false) -> void:
	_last_doc = doc
	_last_preview = preview
	_last_before = show_before
	if backend() == "occ":
		_active = "occ"
		var list: Array = doc.active_features()
		if preview != null:
			var idx := doc.index_of(preview.id)
			if idx >= 0 and idx < list.size():
				list[idx] = preview
			else:
				list.append(preview)
		occ.rebuild(doc, list, preview.id if (show_before and preview != null) else -1)
	else:
		_active = "csg"
		csg.rebuild(doc, preview)


func _rerun() -> void:
	if _last_doc != null:
		rebuild(_last_doc, _last_preview, _last_before)


func is_busy() -> bool:
	if _job_id >= 0 or not _queued.is_empty():
		return true
	if _active == "occ":
		return occ.is_busy()
	return csg.is_busy()


func request_export(fmt: String, path: String, opts := {}) -> bool:
	if not occ.is_ready():
		return false
	return occ.request_export(fmt, path, opts)


func request_hlr(views: Array, comps := []) -> bool:
	if not occ.is_ready():
		return false
	return occ.request_hlr(views, comps)


func _on_csg_built(mesh: ArrayMesh) -> void:
	if _active != "csg":
		return
	_post(mesh, {})


func _on_occ_built(mesh: ArrayMesh, b: Dictionary) -> void:
	if _active != "occ":
		return
	_post(mesh, b)


## Sonucu arka planda işle; bitince `built` yayılır (is_busy bu sürede true)
func _post(mesh: ArrayMesh, b: Dictionary) -> void:
	if mesh == null or not threaded:
		prepared = {}
		brep = b
		built.emit(mesh)
		return
	if _job_id >= 0:
		_queued = [mesh, b]
		return
	_start_job(mesh, b)


func _start_job(mesh: ArrayMesh, b: Dictionary) -> void:
	_job = MeshJob.new()
	_job.surfs = ModelMesh.surfaces_of(mesh)
	_job.aabb = mesh.get_aabb()
	_job.brep = b
	_job_mesh = mesh
	_job_brep = b
	_job_id = WorkerThreadPool.add_task(_job.run, false, "DIY.CAD ağ işleme")


func _process(_delta: float) -> void:
	if _job_id < 0 or not WorkerThreadPool.is_task_completed(_job_id):
		return
	WorkerThreadPool.wait_for_task_completion(_job_id)
	_job_id = -1
	if not _queued.is_empty():
		# Bu sürede daha yeni bir sonuç geldi: eskisini at, yenisini işle
		var q: Array = _queued
		_queued = []
		_start_job(q[0], q[1])
		return
	last_post_ms = _job.ms
	prepared = {"mesh": _job_mesh, "model": _job.model, "display": _job.display}
	brep = _job_brep
	var m := _job_mesh
	_job = null
	_job_mesh = null
	built.emit(m)


func _exit_tree() -> void:
	if _job_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_job_id)
		_job_id = -1


func _on_occ_ready(ok: bool) -> void:
	backend_changed.emit(backend())
	if mode == "csg":
		return
	if ok or _active == "occ":
		# OCC hazır oldu (CSG sonucunu değiştir) ya da çöktü (CSG'ye dön)
		_rerun()


## Montaj parçasını derler (sonuç part_built ile gelir). OCC varsa sunucuda anahtarla saklanır.
func build_part(doc: CadDocument, key: String) -> void:
	if backend() == "occ" and occ.is_ready():
		occ.build_part(doc, key)
		return
	if _part_csg == null:
		_part_csg = CsgKernel.new()
		add_child(_part_csg)
		_part_csg.built.connect(_on_part_csg_built)
	_part_queue.append([doc, key])
	_next_part_csg()


func _next_part_csg() -> void:
	if _part_busy != "" or _part_queue.is_empty():
		return
	var it: Array = _part_queue.pop_front()
	_part_busy = it[1]
	_part_csg.rebuild(it[0])


func _on_part_csg_built(mesh: ArrayMesh) -> void:
	var k := _part_busy
	_part_busy = ""
	part_built.emit(k, mesh, {})
	_next_part_csg()


func request_asm(cmd: String, data: Dictionary) -> bool:
	if not occ.is_ready():
		return false
	return occ.request_asm(cmd, data)
