class_name OccKernel
extends Node
## OpenCASCADE B-rep çekirdeği köprüsü (Faz 4).
## `occ/occ_server.py` betiğini projeye özel Python ortamında (occ_env) yardımcı süreç olarak başlatır,
## stdin/stdout üzerinden satır başına bir JSON mesajla konuşur. Özellik ağacı dünya düzlemi + gerçek
## taslak eğrileri olarak gönderilir; sonuç üçgen ağ + B-rep yüz/kenar bilgisi + kütle özellikleri olarak gelir.

signal ready_changed(ok: bool)
signal built(mesh: ArrayMesh, brep: Dictionary)
signal export_done(result: Dictionary)
signal hlr_done(result: Dictionary)
signal part_built(key: String, mesh: ArrayMesh, brep: Dictionary)
signal asm_done(result: Dictionary)

const STARTUP_TIMEOUT_MS := 45000

var state := "off"          # off | starting | ready | failed
var fail_reason := ""
var version := ""
var last_ms := 0.0

var _io: FileAccess
var _err: FileAccess
var _pid := -1
var _buf := PackedByteArray()
var _errbuf := PackedByteArray()
var _next_id := 1
var _inflight := {}          # id -> {kind, feats?}
var _queued_rebuild := {}    # bekleyen son yeniden oluşturma isteği
var _start_ms := 0
var _alive_check := 0.0
## Son yanıtta bir yüzey taslağının düzlemi kaydırıldı mı (arayüz taslakları yeniden çizer)
var plane_moved := false


static func python_path() -> String:
	return AppSettings.app_dir("occ_env/Scripts/python.exe")


static func server_path() -> String:
	return AppSettings.app_dir("occ/occ_server.py")


static func is_installed() -> bool:
	return FileAccess.file_exists(python_path()) and FileAccess.file_exists(server_path())


func is_ready() -> bool:
	return state == "ready"


func start() -> void:
	if state == "starting" or state == "ready":
		return
	if not is_installed():
		_fail("OpenCASCADE ortamı bulunamadı (occ_env). Kurulum: README → Faz 4")
		return
	var d := OS.execute_with_pipe(python_path(), PackedStringArray(["-u", "-X", "utf8", server_path()]), false)
	if d.is_empty() or not d.has("stdio"):
		_fail("Python süreci başlatılamadı")
		return
	_io = d["stdio"]
	_err = d["stderr"]
	_pid = int(d["pid"])
	_start_ms = Time.get_ticks_msec()
	state = "starting"


func stop() -> void:
	if _pid > 0:
		if _io and state == "ready":
			_io.store_line(JSON.stringify({"id": 0, "cmd": "quit"}))
			_io.flush()
		if OS.is_process_running(_pid):
			OS.kill(_pid)
	_pid = -1
	_io = null
	_err = null
	if state != "failed":
		state = "off"


func _exit_tree() -> void:
	stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop()


func _fail(reason: String) -> void:
	var was_ready := state == "ready"
	state = "failed"
	fail_reason = reason
	push_warning("OCC çekirdeği: " + reason)
	_inflight.clear()
	_queued_rebuild = {}
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	ready_changed.emit(false)
	if was_ready:
		pass


func is_busy() -> bool:
	return state == "starting" or not _inflight.is_empty() or not _queued_rebuild.is_empty()


func has_pending_rebuild() -> bool:
	for id in _inflight:
		if _inflight[id]["kind"] == "rebuild":
			return true
	return not _queued_rebuild.is_empty()


# ---------------------------------------------------------------- istekler

## Engellemesiz boru büyük yazmaları kısmen düşürebildiği için uzun istekler geçici
## dosyaya yazılır ve boruya yalnızca dosya yolu gönderilir (sunucu okuyup siler).
const PIPE_LIMIT := 1024


func _send(req: Dictionary, meta: Dictionary) -> int:
	var id := _next_id
	_next_id += 1
	req["id"] = id
	_inflight[id] = meta
	var line := JSON.stringify(req)
	if line.length() > PIPE_LIMIT:
		var dir := OS.get_user_data_dir().path_join("occ_tmp")
		DirAccess.make_dir_recursive_absolute(dir)
		var path := dir.path_join("req_%d_%d.json" % [OS.get_process_id(), id])
		var fa := FileAccess.open(path, FileAccess.WRITE)
		if fa == null:
			_inflight.erase(id)
			push_warning("OCC isteği yazılamadı: " + path)
			return -1
		fa.store_string(line)
		fa.close()
		line = JSON.stringify({"id": id, "file": path})
	_io.store_line(line)
	_io.flush()
	return id


## Özellik listesini (önizleme dahil) yeniden oluşturur. feats: CadFeature listesi (sırayla).
## display_before >= 0: o kimlikli özellikten önceki gövde gösterilir (kenar/yüz seçimi için),
## ama özellik yine hesaplanır (hata mesajı ve imza güncellemesi gelir).
func rebuild(doc: CadDocument, feats: Array, display_before := -1) -> void:
	var payload := build_payload(doc, feats)
	var req := {"cmd": "rebuild", "features": payload}
	if display_before >= 0:
		req["display_before"] = display_before
	var by_id := {}
	for f in feats:
		by_id[f.id] = f
	var meta := {"kind": "rebuild", "feats": by_id}
	if state != "ready" or has_pending_rebuild():
		_queued_rebuild = {"req": req, "meta": meta}
		return
	_send(req, meta)


func request_export(fmt: String, path: String, opts := {}) -> bool:
	if state != "ready":
		return false
	var req := {"cmd": "export", "format": fmt, "path": path}
	req.merge(opts)
	_send(req, {"kind": "export"})
	return true


## Montaj parçası: ana parçanın durumunu bozmadan ayrı anahtarla derlenir ve sunucuda saklanır.
func build_part(doc: CadDocument, key: String) -> bool:
	if state != "ready":
		return false
	var feats: Array = doc.active_features()
	var by_id := {}
	for f in feats:
		by_id[f.id] = f
	_send({"cmd": "rebuild", "features": build_payload(doc, feats), "store": key}, {"kind": "part", "key": key, "feats": by_id})
	return true


## Montaj komutları (asm_interference, asm_export): yanıt asm_done ile gelir.
func request_asm(cmd: String, data: Dictionary) -> bool:
	if state != "ready":
		return false
	var req := data.duplicate()
	req["cmd"] = cmd
	_send(req, {"kind": "asm", "cmd": cmd})
	return true


## Teknik resim görünüşleri için gizli çizgi hesabı (HLR). views: [{id, dir, x, section?}]
func request_hlr(views: Array, comps := []) -> bool:
	if state != "ready":
		return false
	var req := {"cmd": "hlr", "views": views}
	if not comps.is_empty():
		req["comps"] = comps
	_send(req, {"kind": "hlr"})
	return true


# ---------------------------------------------------------------- yük (payload) hazırlama

static func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _plane_dict(pl: SketchPlane) -> Dictionary:
	return {"o": _v3(pl.origin), "x": _v3(pl.x_dir), "y": _v3(pl.y_dir), "n": _v3(pl.normal())}


## Taslak düzlemi + (varsa) destek yüzü: çekirdek, yüz modelde kayınca düzlemi de kaydırır.
static func _plane_fields(sk_f: CadFeature, d: Dictionary) -> void:
	d["plane"] = _plane_dict(sk_f.plane)
	d["sketch_fid"] = sk_f.id
	if not sk_f.plane.support.is_empty():
		d["support"] = sk_f.plane.support


static func _axis_vec(axis: String) -> Vector3:
	match axis:
		"x":
			return Vector3.RIGHT
		"z":
			return Vector3.BACK
	return Vector3.UP


## Profil: bölge seçimi varsa tüm eğriler + örnek noktalar, yoksa iç içe konturlar.
static func _profile(f: CadFeature, sk_f: CadFeature, d: Dictionary) -> bool:
	_plane_fields(sk_f, d)
	var regions = f.params.get("regions", [])
	if regions is Array and not (regions as Array).is_empty():
		var samples: Array = []
		for s in regions:
			if s is Array:
				samples.append([float(s[0]), float(s[1])])
			elif s is Vector2:
				samples.append([s.x, s.y])
		d["regions"] = {"curves": sk_f.sketch.all_curves(), "samples": samples}
		return true
	var prof := sk_f.sketch.extract_profiles()
	if (prof["loops"] as Array).is_empty():
		f.error = "Taslakta kapalı kontur yok"
		return false
	var loops: Array = []
	for L in prof["loops"]:
		loops.append({"depth": L["depth"], "parent": L["parent"], "curves": L["curves"]})
	d["loops"] = loops
	return true


## Süpürme yolu: taslak zinciri, 3B taslak çizgileri veya helis.
static func _sweep_path(doc: CadDocument, f: CadFeature) -> Dictionary:
	return _curve_ref(doc, f.params.get("path", {}))


## Eğri başvurusu {kind, id} → sunucu yolu: taslak zinciri, 3B taslak, helis/spiral veya projeksiyon eğrisi.
static func _curve_ref(doc: CadDocument, path: Variant) -> Dictionary:
	if not (path is Dictionary) or not (path as Dictionary).has("id"):
		return {"error": "Eğri (yol) seçilmedi"}
	var pf := doc.get_feature(int(path["id"]))
	if pf == null:
		return {"error": "Seçili eğri bulunamadı"}
	if pf.type == "projcurve":
		return {"kind": "projcurve", "id": pf.id}
	match pf.type:
		"sketch":
			var ch := pf.sketch.curve_chains()
			if ch.is_empty():
				return {"error": "Yol taslağında çizgi yok"}
			return {"kind": "sketch", "plane": _plane_dict(pf.plane), "chains": ch}
		"sketch3d":
			if pf.sketch3d == null or pf.sketch3d.lines.is_empty():
				return {"error": "Yol 3B taslağı boş"}
			return {"kind": "sketch3d", "polys": RefGeom.sketch3d_polys(pf.sketch3d)}
		"helix":
			var h := RefGeom.helix_spec(doc, pf)
			if h.has("error"):
				return h
			return {"kind": "helix", "helix": h}
	return {"error": "Yol olarak taslak, 3B taslak veya helis seçin"}


static func _pattern_fields(doc: CadDocument, f: CadFeature, d: Dictionary) -> bool:
	var p := f.params
	match f.type:
		"lpattern":
			var a1 := RefGeom.resolve_axis(doc, p.get("dir1", "x"))
			if a1.is_empty():
				f.error = "Yön 1 geçersiz"
				return false
			d["dir1"] = _v3((a1["d"] as Vector3) * (-1.0 if bool(p.get("rev1", false)) else 1.0))
			d["count1"] = int(p.get("count1", 3))
			d["spacing1"] = float(p.get("spacing1", 10.0))
			d["use2"] = bool(p.get("use2", false))
			if d["use2"]:
				var a2 := RefGeom.resolve_axis(doc, p.get("dir2", "z"))
				if a2.is_empty():
					f.error = "Yön 2 geçersiz"
					return false
				d["dir2"] = _v3((a2["d"] as Vector3) * (-1.0 if bool(p.get("rev2", false)) else 1.0))
				d["count2"] = int(p.get("count2", 2))
				d["spacing2"] = float(p.get("spacing2", 10.0))
		"cpattern":
			var ax := RefGeom.resolve_axis(doc, p.get("axis", "y"))
			if ax.is_empty():
				f.error = "Dönme ekseni geçersiz"
				return false
			d["axis_o"] = _v3(ax["o"])
			d["axis_d"] = _v3((ax["d"] as Vector3) * (-1.0 if bool(p.get("rev", false)) else 1.0))
			d["count"] = int(p.get("count", 4))
			d["angle"] = float(p.get("angle", 360.0))
			d["equal"] = bool(p.get("equal", true))
		"mirror":
			if p.get("plane_face") is Dictionary and not (p["plane_face"] as Dictionary).is_empty():
				d["plane_o"] = p["plane_face"]["o"]
				d["plane_n"] = p["plane_face"]["n"]
			else:
				var mp := RefGeom.resolve_plane(doc, str(p.get("plane", "right")))
				if mp == null:
					f.error = "Aynalama düzlemi geçersiz"
					return false
				d["plane_o"] = _v3(mp.origin)
				d["plane_n"] = _v3(mp.normal())
		"tpattern":
			d["offsets"] = p.get("offsets", [])
		"cvpattern":
			var cr := _curve_ref(doc, p.get("curve", {}))
			if cr.has("error"):
				f.error = cr["error"]
				return false
			d["curve"] = cr
			d["count"] = int(p.get("count", 4))
			d["spacing"] = float(p.get("spacing", 10.0))
			d["equal"] = bool(p.get("equal", true))
			d["align"] = bool(p.get("align", true))
	return true


static func build_payload(doc: CadDocument, feats: Array) -> Array:
	var out: Array = []
	for f in feats:
		f.error = ""
		if f.suppressed or f.is_sketch() or f.type == "sketch3d" or f.is_reference():
			continue
		var d := {"fid": f.id, "type": f.type}
		match f.type:
			"sm_base", "sm_edge":
				if not SheetMetal.payload(doc, f, d):
					continue
			"weld":
				if not Weldment.payload(doc, f, d):
					continue
			"srf_extrude", "srf_revolve", "srf_loft", "srf_planar", "srf_offset", "srf_knit", "srf_thicken", "srf_trim":
				if not Surfaces.payload(doc, f, d):
					continue
			"extrude", "revolve", "sweep":
				var sk_f := doc.get_feature(f.sketch_ref())
				if sk_f == null or sk_f.sketch == null:
					f.error = "Taslak bulunamadı"
					continue
				var thin := float(f.params.get("thin", 0.0)) if f.type == "extrude" else 0.0
				if thin > 0.0:
					_plane_fields(sk_f, d)
					d["thin"] = thin
					d["thin_side"] = str(f.params.get("thin_side", "mid"))
					d["chains"] = sk_f.sketch.curve_chains()
					if (d["chains"] as Array).is_empty():
						f.error = "Taslakta çizgi yok"
						continue
				elif not _profile(f, sk_f, d):
					continue
				d["cut"] = f.is_cut()
				d["merge"] = bool(f.params.get("merge", true))
				if f.type == "sweep":
					var path := _sweep_path(doc, f)
					if path.has("error"):
						f.error = path["error"]
						continue
					d["path"] = path
					var gd = f.params.get("guide", {})
					if gd is Dictionary and (gd as Dictionary).has("id"):
						var gp := _curve_ref(doc, gd)
						if gp.has("error"):
							f.error = "Kılavuz: " + str(gp["error"])
							continue
						d["guide"] = gp
					d["twist"] = float(f.params.get("twist", 0.0))
				elif f.type == "extrude":
					var g := FeatureGeom.extrude_vectors(f, sk_f.plane)
					if g.has("error"):
						f.error = g["error"]
						continue
					d["vec"] = _v3(g["vec"])
					d["offset"] = _v3(g["offset"])
					var end := str(f.params.get("end", "blind"))
					d["end"] = end
					if end == "face" or end == "face_offset":
						d["face"] = f.params.get("face", {})
						d["face_off"] = float(f.params.get("face_off", 0.0))
					if float(f.params.get("draft", 0.0)) != 0.0:
						d["draft"] = float(f.params.get("draft", 0.0))
						d["draft_out"] = bool(f.params.get("draft_out", false))
					if bool(f.params.get("dir2", false)) and end != "midplane":
						var dv2 := -FeatureGeom.extrude_dir(f, sk_f.plane)
						var end2 := str(f.params.get("end2", "blind"))
						var dep2 := FeatureGeom.THROUGH_ALL if end2 != "blind" else maxf(float(f.params.get("depth2", 10.0)), 0.001)
						d["dir2"] = {"vec": _v3(dv2 * dep2), "end": end2, "face": f.params.get("face2", {})}
				else:
					var r := FeatureGeom.revolve_frame(f, sk_f, [], doc)
					if r.has("error"):
						f.error = r["error"]
						continue
					d["axis_o"] = _v3(r["origin"])
					d["axis_d"] = _v3(r["axis"])
					d["angle"] = r["angle"]
			"fillet":
				d["r"] = float(f.params.get("r", 2.0))
				d["variable"] = bool(f.params.get("variable", false))
				d["r2"] = float(f.params.get("r2", d["r"]))
				d["edges"] = f.params.get("edges", [])
			"chamfer":
				d["d"] = float(f.params.get("d", 1.0))
				d["mode"] = str(f.params.get("mode", "equal"))
				d["d2"] = float(f.params.get("d2", d["d"]))
				d["angle"] = float(f.params.get("angle", 45.0))
				d["flip"] = bool(f.params.get("flip", false))
				d["edges"] = f.params.get("edges", [])
			"draft":
				d["angle"] = float(f.params.get("angle", 3.0))
				d["faces"] = f.params.get("faces", [])
				d["neutral"] = f.params.get("neutral", {})
				d["reverse"] = bool(f.params.get("reverse", false))
			"rib":
				var rs := doc.get_feature(f.sketch_ref())
				if rs == null or rs.sketch == null:
					f.error = "Taslak bulunamadı"
					continue
				_plane_fields(rs, d)
				d["curves"] = rs.sketch.all_curves()
				d["t"] = float(f.params.get("t", 2.0))
			"combine":
				d["op"] = str(f.params.get("op", "add"))
				d["bodies"] = f.params.get("bodies", [])
			"move_body":
				d["body"] = f.params.get("body", {})
				d["t"] = f.params.get("t", [0.0, 0.0, 0.0])
				d["axis_o"] = [0.0, 0.0, 0.0]
				d["axis_d"] = _v3(_axis_vec(str(f.params.get("axis", "y"))))
				d["angle"] = float(f.params.get("angle", 0.0))
				d["copy"] = bool(f.params.get("copy", false))
			"loft":
				var secs: Array = []
				for sid in f.params.get("sketches", []):
					var ls := doc.get_feature(int(sid))
					if ls == null or ls.sketch == null:
						continue
					var lp := ls.sketch.extract_profiles()
					var outer: Array = []
					for L in lp["loops"]:
						if int(L["depth"]) == 0:
							outer = L["curves"]
							break
					if outer.is_empty():
						continue
					secs.append({"plane": _plane_dict(ls.plane), "curves": outer})
				if secs.size() < 2:
					f.error = "En az iki kapalı profilli taslak seçin"
					continue
				d["sections"] = secs
				d["ruled"] = bool(f.params.get("ruled", false))
				var lg = f.params.get("guide", {})
				if lg is Dictionary and (lg as Dictionary).has("id"):
					var lgp := _curve_ref(doc, lg)
					if lgp.has("error"):
						f.error = "Kılavuz: " + str(lgp["error"])
						continue
					d["guide"] = lgp
				d["cut"] = f.is_cut()
				d["merge"] = bool(f.params.get("merge", true))
			"lpattern", "cpattern", "mirror", "tpattern", "cvpattern":
				d["features"] = f.params.get("features", [])
				d["bodies"] = bool(f.params.get("bodies", false))
				if not _pattern_fields(doc, f, d):
					continue
			"hole":
				var dims := HoleTable.dims(str(f.params.get("std", "ISO")), str(f.params.get("htype", "simple")),
					str(f.params.get("size", "M6")), str(f.params.get("fit", "normal")))
				if dims.is_empty():
					f.error = "Bilinmeyen delik ölçüsü"
					continue
				d.merge(dims, true)
				d["htype"] = str(f.params.get("htype", "simple"))
				d["face"] = f.params.get("face", {})
				d["points"] = f.params.get("points", [])
				d["end"] = str(f.params.get("end", "through"))
				d["depth"] = float(f.params.get("depth", 10.0))
				d["point_ang"] = 118.0
			"dome":
				d["face"] = f.params.get("face", {})
				d["height"] = float(f.params.get("height", 5.0))
			"projcurve", "wrap", "emboss":
				var ps := doc.get_feature(f.sketch_ref())
				if ps == null or ps.sketch == null:
					f.error = "Taslak bulunamadı"
					continue
				if f.type == "projcurve":
					f.runtime.erase("poly")
					_plane_fields(ps, d)
					d["chains"] = ps.sketch.curve_chains()
					d["face"] = f.params.get("face", {})
				elif f.type == "wrap":
					_plane_fields(ps, d)
					var wl: Array = []
					for L in ps.sketch.extract_profiles()["loops"]:
						wl.append({"depth": L["depth"], "parent": L["parent"], "curves": L["curves"]})
					if wl.is_empty():
						f.error = "Taslakta kapalı kontur yok"
						continue
					d["loops"] = wl
					d["face"] = f.params.get("face", {})
					d["wtype"] = str(f.params.get("wtype", "emboss"))
					d["depth"] = float(f.params.get("depth", 1.0))
				else:
					if not _profile(f, ps, d):
						continue
					d["depth"] = float(f.params.get("depth", 1.0))
					d["etype"] = str(f.params.get("etype", "emboss"))
					d["reverse"] = bool(f.params.get("reverse", false))
			"split":
				var spl := RefGeom.resolve_plane(doc, str(f.params.get("plane", "front")))
				if spl == null:
					f.error = "Bölme düzlemi geçersiz"
					continue
				var sn := spl.normal()
				d["plane_o"] = _v3(spl.origin + sn * float(f.params.get("offset", 0.0)))
				d["plane_n"] = _v3(sn)
				d["keep"] = str(f.params.get("keep", "both"))
			"shell":
				d["t"] = float(f.params.get("t", 1.0))
				d["faces"] = f.params.get("faces", [])
				d["outward"] = bool(f.params.get("outward", false))
			"import":
				d["path"] = str(f.params.get("path", ""))
				d["scale"] = float(f.params.get("scale", 1.0))
				for k in ["sx", "sy", "sz"]:
					d[k] = float(f.params.get(k, 1.0))
				for k2 in ["origin", "move"]:
					if f.params.get(k2) is Array:
						d[k2] = f.params[k2]
				if f.params.get("stretch") is Dictionary or f.params.get("stretch") is Array:
					d["stretch"] = f.params["stretch"]
				for k3 in ["taper", "protect"]:
					if f.params.get(k3) is Dictionary:
						d[k3] = f.params[k3]
				if f.params.has("refine"):
					d["refine"] = float(f.params["refine"])
			_:
				f.error = "Desteklenmeyen özellik"
				continue
		out.append(d)
	return out


# ---------------------------------------------------------------- yanıtlar

func _process(delta: float) -> void:
	if _io == null or state == "off" or state == "failed":
		return
	var chunk := _io.get_buffer(1 << 22)
	if chunk.size() > 0:
		_buf.append_array(chunk)
	if _err:
		var ec := _err.get_buffer(1 << 16)
		if ec.size() > 0:
			_errbuf.append_array(ec)
			var nl := _errbuf.rfind(10)
			if nl >= 0:
				var txt := _errbuf.slice(0, nl).get_string_from_utf8()
				_errbuf = _errbuf.slice(nl + 1)
				for ln in txt.split("\n"):
					if ln.strip_edges() != "":
						# OCCT'nin bilgi mesajları (STEP/IGES); hatalar JSON yanıtında gelir
						print_verbose("[occ] ", ln)
	while true:
		var nl2 := _buf.find(10)
		if nl2 < 0:
			break
		var line := _buf.slice(0, nl2).get_string_from_utf8()
		_buf = _buf.slice(nl2 + 1)
		if line.strip_edges() == "":
			continue
		var msg = JSON.parse_string(line)
		if msg is Dictionary:
			_handle(msg)
	if state == "starting" and Time.get_ticks_msec() - _start_ms > STARTUP_TIMEOUT_MS:
		_fail("OpenCASCADE sunucusu zamanında başlamadı")
		return
	_alive_check += delta
	if _alive_check > 1.0:
		_alive_check = 0.0
		if _pid > 0 and not OS.is_process_running(_pid):
			_fail("OpenCASCADE sunucusu beklenmedik şekilde kapandı")


func _handle(msg: Dictionary) -> void:
	var id := int(msg.get("id", 0))
	if id == 0 and msg.has("ready"):
		if bool(msg["ready"]):
			state = "ready"
			version = str(msg.get("version", ""))
			ready_changed.emit(true)
			_flush_queue()
		else:
			_fail(str(msg.get("error", "OCP yüklenemedi")))
		return
	if not _inflight.has(id):
		return
	var meta: Dictionary = _inflight[id]
	_inflight.erase(id)
	last_ms = float(msg.get("ms", 0.0))
	match meta["kind"]:
		"rebuild":
			if not _queued_rebuild.is_empty():
				# Bu sonuç eskidi: sıradaki isteği gönder, bunu gösterme
				_flush_queue()
				return
			_on_rebuilt(msg, meta)
		"export":
			export_done.emit(msg)
		"hlr":
			hlr_done.emit(msg)
		"part":
			_on_rebuilt(msg, meta)
		"asm":
			msg["cmd"] = meta["cmd"]
			asm_done.emit(msg)


func _flush_queue() -> void:
	if _queued_rebuild.is_empty() or state != "ready" or has_inflight_rebuild():
		return
	var q := _queued_rebuild
	_queued_rebuild = {}
	_send(q["req"], q["meta"])


func has_inflight_rebuild() -> bool:
	for id in _inflight:
		if _inflight[id]["kind"] == "rebuild":
			return true
	return false


static func _f32(b64: String) -> PackedFloat32Array:
	return Marshalls.base64_to_raw(b64).to_float32_array()


static func _i32(b64: String) -> PackedInt32Array:
	return Marshalls.base64_to_raw(b64).to_int32_array()


static func _sig_changed(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return true
	for i in a.size():
		var x: Dictionary = a[i]
		var y: Dictionary = b[i]
		for k in y:
			if not x.has(k):
				return true
			var xv = x[k]
			var yv = y[k]
			if xv is Array and yv is Array:
				if (xv as Array).size() != (yv as Array).size():
					return true
				for j in (xv as Array).size():
					var p = xv[j]
					var q = yv[j]
					if (p is float or p is int) and (q is float or q is int):
						if absf(float(p) - float(q)) > 1e-6:
							return true
					elif str(p) != str(q):
						return true
			elif str(xv) != str(yv):
				return true
	return false


func _on_rebuilt(msg: Dictionary, meta: Dictionary) -> void:
	var feats: Dictionary = meta["feats"]
	if not bool(msg.get("ok", false)):
		var err := str(msg.get("error", "Çekirdek hatası"))
		push_warning("OCC rebuild: " + err + "\n" + str(msg.get("trace", "")))
		for fid in feats:
			var f0: CadFeature = feats[fid]
			if not f0.is_sketch() and f0.type != "sketch3d" and not f0.suppressed:
				f0.error = err
				break
		_emit_built(meta, null, {})
		return
	var errors: Dictionary = msg.get("errors", {})
	for k in errors:
		var f: CadFeature = feats.get(int(k))
		if f:
			f.error = str(errors[k])
	# Kenar/yüz başvurularının güncel imzaları (model değişince seçim kaymasın)
	var updates: Dictionary = msg.get("updates", {})
	plane_moved = false
	for k in updates:
		var f2: CadFeature = feats.get(int(k))
		if f2 == null:
			continue
		var u: Dictionary = updates[k]
		for key in ["edges", "faces", "bodies"]:
			if u.has(key) and _sig_changed(f2.params.get(key, []), u[key]):
				f2.params[key] = u[key]
		for key1 in ["neutral", "body"]:
			if u.has(key1) and _sig_changed([f2.params.get(key1, {})], [u[key1]]):
				f2.params[key1] = u[key1]
		# Yüzeye çizilen taslak: destek yüzü kaydıysa taslak düzlemi de kayar
		if u.has("plane_o") and f2.plane != null:
			var no := Vector3(float(u["plane_o"][0]), float(u["plane_o"][1]), float(u["plane_o"][2]))
			if no.distance_to(f2.plane.origin) > 1e-7:
				f2.plane.origin = no
				plane_moved = true
		if u.has("poly"):
			f2.runtime["poly"] = u["poly"]
		if u.has("warn") and f2.error == "":
			f2.error = ""
	if bool(msg.get("empty", false)) or not msg.has("mesh"):
		_emit_built(meta, null, {})
		return
	var mesh_d: Dictionary = msg["mesh"]
	var pos := _f32(mesh_d["pos"])
	var fids := _i32(mesh_d["face"])
	var nt := fids.size()
	var verts := PackedVector3Array()
	verts.resize(nt * 3)
	for t in nt:
		var o := t * 9
		# Sunucu: dış normale göre saat yönü tersi (a, b, c). Godot: saat yönü (a, c, b).
		verts[t * 3] = Vector3(pos[o], pos[o + 1], pos[o + 2])
		verts[t * 3 + 1] = Vector3(pos[o + 6], pos[o + 7], pos[o + 8])
		verts[t * 3 + 2] = Vector3(pos[o + 3], pos[o + 4], pos[o + 5])
	var am := ArrayMesh.new()
	if nt > 0:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var edges: Array = []
	for e in msg.get("edges", []):
		var pts := PackedVector3Array()
		var fl := _f32(e["pts"])
		for i in range(0, fl.size() - 2, 3):
			pts.append(Vector3(fl[i], fl[i + 1], fl[i + 2]))
		var ed: Dictionary = e.duplicate()
		ed["pts"] = pts
		edges.append(ed)
	var mass = msg.get("mass", {})
	var brep := {"tri_face": fids, "faces": msg.get("faces", []), "edges": edges,
		"mass": mass if mass is Dictionary else {}, "valid": msg.get("valid", true), "ms": last_ms,
		"before": bool(msg.get("before", false))}
	_emit_built(meta, am if nt > 0 else null, brep)


func _emit_built(meta: Dictionary, mesh: ArrayMesh, brep: Dictionary) -> void:
	if meta.get("kind", "") == "part":
		part_built.emit(str(meta["key"]), mesh, brep)
	else:
		built.emit(mesh, brep)
