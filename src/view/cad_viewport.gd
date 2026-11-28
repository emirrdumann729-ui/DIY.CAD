class_name CadViewport
extends Control
## 3B model alanı: SubViewport içinde kamera, ışık, model, kenarlar, düzlemler ve katmanlar.
## Gezinme (döndür/kaydır/yakınlaştır) burada; diğer fare olayları `pointer_input` ile araca iletilir.
##
## Fare:
##   Orta tuş sürükle      : döndür        Ctrl + orta tuş : kaydır     Shift + orta tuş : yakınlaştır
##   Sağ tuş sürükle       : döndür        Ctrl + sağ tuş  : kaydır
##   Tekerlek              : imlece doğru yakınlaştır
##   Sağ tık (sürüklemeden): araca iletilir (ör. çizgi zincirini bitir)

signal pointer_input(event: InputEvent)
signal view_changed
signal gesture_input(phase: String, pos: Vector2)   # Faz 9 fare hareketleri: "begin" | "move" | "end"

const LineShader := preload("res://src/shaders/line.gdshader")
const LineTopShader := preload("res://src/shaders/line_top.gdshader")
const HighlightShader := preload("res://src/shaders/highlight.gdshader")
const AxisTriad := preload("res://src/view/axis_triad.gd")

var container: SubViewportContainer
var subviewport: SubViewport
var world: Node3D
var camera: CadCamera
var kernel: GeoKernel
var model := ModelMesh.new()

var model_mi: MeshInstance3D
var edges_mi: MeshInstance3D
var sel_edges_mi: MeshInstance3D    # seçili B-rep kenarları (yuvarlatma/pah)
var planes_fill_mi: MeshInstance3D
var planes_line_mi: MeshInstance3D
var origin_mi: MeshInstance3D
var highlight_mi: MeshInstance3D
var sketches_mi: MeshInstance3D     # düzenlenmeyen taslaklar
var overlay_mi: MeshInstance3D      # ölçüm / ağırlık merkezi işaretleri (her zaman üstte)
var grid_mi: MeshInstance3D         # taslak ızgarası
var edit_mi: MeshInstance3D         # düzenlenen taslak (her zaman üstte)

var line_mat: ShaderMaterial
var grid_mat: ShaderMaterial
var top_mat: ShaderMaterial
var highlight_mat: ShaderMaterial
var sel_edge_mat: ShaderMaterial
var model_mat: StandardMaterial3D

var triad: Control
var dim_layer: Control          # taslak boyut etiketleri ve ilişki rozetleri
var cursor_label: Label
var overlay_top: HBoxContainer

var show_planes := false      # true: düzlemler her zaman görünür; false: otomatik
var force_planes := false     # taslak için düzlem seçilirken geçici olarak göster
var show_edges := true
var plane_half := 50.0
var selected_plane := ""

var _nav := ""
var _rmb_down := false
var _rmb_moved := false
var _rmb_accum := Vector2.ZERO
var _rmb_press := Vector2.ZERO
## Sağ tuş sürükleme fare hareketi halkası açar (döndürme orta tuşla); false: sağ tuş döndürür
var rmb_gestures := false


func _ready() -> void:
	clip_contents = true
	# Arka plan: dikey degrade
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.98, 0.99, 1.0))
	grad.set_color(1, Color(0.70, 0.77, 0.86))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	container = SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	container.focus_mode = Control.FOCUS_CLICK
	add_child(container)
	container.gui_input.connect(_on_gui_input)

	subviewport = SubViewport.new()
	subviewport.transparent_bg = true
	subviewport.msaa_3d = Viewport.MSAA_4X
	subviewport.own_world_3d = true
	container.add_child(subviewport)

	world = Node3D.new()
	subviewport.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	camera = CadCamera.new()
	world.add_child(camera)
	camera.current = true
	camera.view_changed.connect(_on_view_changed)
	var light := DirectionalLight3D.new()
	light.light_energy = 0.85
	light.rotation_degrees = Vector3(-28, -24, 0)
	camera.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.25
	fill.rotation_degrees = Vector3(35, 150, 0)
	camera.add_child(fill)

	kernel = GeoKernel.new()
	world.add_child(kernel)

	line_mat = ShaderMaterial.new()
	line_mat.shader = LineShader
	grid_mat = ShaderMaterial.new()
	grid_mat.shader = LineShader
	top_mat = ShaderMaterial.new()
	top_mat.shader = LineTopShader
	top_mat.render_priority = 10
	highlight_mat = ShaderMaterial.new()
	highlight_mat.shader = HighlightShader
	highlight_mat.render_priority = 5
	sel_edge_mat = ShaderMaterial.new()
	sel_edge_mat.shader = LineShader

	model_mat = StandardMaterial3D.new()
	model_mat.albedo_color = Color(0.72, 0.76, 0.82)
	model_mat.roughness = 0.5
	model_mat.metallic_specular = 0.45

	var plane_mat := StandardMaterial3D.new()
	plane_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plane_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plane_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane_mat.vertex_color_use_as_albedo = true
	plane_mat.vertex_color_is_srgb = true

	model_mi = _mi(model_mat)
	edges_mi = _mi(line_mat)
	sel_edges_mi = _mi(sel_edge_mat)
	planes_fill_mi = _mi(plane_mat)
	planes_line_mi = _mi(line_mat)
	origin_mi = _mi(line_mat)
	highlight_mi = _mi(highlight_mat)
	sketches_mi = _mi(line_mat)
	grid_mi = _mi(grid_mat)
	edit_mi = _mi(top_mat)
	overlay_mi = _mi(top_mat)

	dim_layer = Control.new()
	dim_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim_layer)

	triad = AxisTriad.new()
	triad.camera = camera
	triad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(triad)

	cursor_label = Label.new()
	cursor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_label.add_theme_color_override("font_color", Color(0.05, 0.15, 0.45))
	cursor_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	cursor_label.add_theme_constant_override("outline_size", 4)
	cursor_label.visible = false
	add_child(cursor_label)

	overlay_top = HBoxContainer.new()
	overlay_top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	overlay_top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay_top.position.y = 6
	overlay_top.add_theme_constant_override("separation", 2)
	add_child(overlay_top)

	draw_planes()
	call_deferred("_on_view_changed")


func _mi(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ArrayMesh.new()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	return mi


# ---------------------------------------------------------------- model

func set_model_mesh(mesh: ArrayMesh, brep := {}) -> void:
	var pre: Dictionary = kernel.prepared if kernel != null else {}
	if not pre.is_empty() and pre["mesh"] == mesh:
		# Arka planda hazırlanmış model (Faz 9): yalnızca veriyi al, gösterim ağını kur
		model.copy_from(pre["model"])
		model.source = mesh
		model_mi.mesh = ModelMesh.mesh_from_arrays(pre["display"])
		kernel.prepared = {}
	else:
		model.build(mesh, brep)
		model_mi.mesh = model.display_mesh()
	# Açık yüzey gövdeleri (Faz 8) iki taraftan da görünmeli
	var has_srf := false
	for f in model.brep_faces:
		if int(f.get("body", 0)) < 0:
			has_srf = true
			break
	model_mat.cull_mode = BaseMaterial3D.CULL_DISABLED if has_srf else BaseMaterial3D.CULL_BACK
	var lb := LineBuilder.new()
	if show_edges:
		var col := Color(0.05, 0.05, 0.08)
		for i in range(0, model.feature_edges.size(), 2):
			lb.line(model.feature_edges[i], model.feature_edges[i + 1], col)
	lb.commit(edges_mi.mesh)
	# Düzlem boyutunu modele göre ayarla
	var half := 50.0
	if not model.is_empty():
		var a := model.aabb
		for v in [a.position, a.end]:
			half = maxf(half, maxf(absf(v.x), maxf(absf(v.y), absf(v.z))) * 1.15)
	plane_half = half
	draw_planes()


func set_edges_visible(v: bool) -> void:
	show_edges = v
	edges_mi.visible = v
	if v:
		set_model_mesh(model.source, model.brep_src)


func model_aabb() -> AABB:
	if model.is_empty():
		return AABB(Vector3(-plane_half, -plane_half, -plane_half), Vector3.ONE * plane_half * 2.0)
	return model.aabb


# ---------------------------------------------------------------- düzlemler

func draw_planes() -> void:
	var fill := LineBuilder.new()
	var lines := LineBuilder.new()
	for id in visible_plane_ids():
		if true:
			var p := SketchPlane.standard(id)
			var sel: bool = id == selected_plane
			var fc := Color(0.2, 0.55, 1.0, 0.30) if sel else Color(0.35, 0.6, 0.95, 0.08)
			var lc := Color(0.05, 0.35, 1.0) if sel else Color(0.45, 0.58, 0.78)
			var u := p.x_dir * plane_half
			var v := p.y_dir * plane_half
			fill.quad(p.origin, u, v, fc)
			lines.polyline(PackedVector3Array([
				p.origin - u - v, p.origin + u - v, p.origin + u + v, p.origin - u + v]), lc, true)
	fill.commit(planes_fill_mi.mesh)
	lines.commit(planes_line_mi.mesh)


## Model varken düzlemler gizlenir, yalnızca seçili düzlem görünür.
func visible_plane_ids() -> Array:
	if show_planes or force_planes or model.is_empty():
		return SketchPlane.STANDARD_IDS
	if selected_plane != "":
		return [selected_plane]
	return []


func set_planes_visible(v: bool) -> void:
	show_planes = v
	draw_planes()


## Standart düzlemlerden ışınla en yakın olanı. Dönüş: {id, dist} veya {}.
func pick_plane(from: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	for id in visible_plane_ids():
		var p := SketchPlane.standard(id)
		var hit = p.intersect_ray(from, dir)
		if hit == null:
			continue
		var l := p.to_local(hit)
		if absf(l.x) <= plane_half and absf(l.y) <= plane_half:
			var d: float = (hit - from).dot(dir)
			if best.is_empty() or d < float(best["dist"]):
				best = {"id": id, "dist": d}
	return best


# ---------------------------------------------------------------- vurgular

func set_face_highlight(tri_points: PackedVector3Array) -> void:
	var am: ArrayMesh = highlight_mi.mesh
	am.clear_surfaces()
	if tri_points.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = tri_points
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


func clear_face_highlight() -> void:
	set_face_highlight(PackedVector3Array())


var _hl_ids: Array = []
var _hl_hover := -1


## B-rep kenarlarını vurgular. ids: kenar kimlikleri; hover: imleç altındaki kenar (-1 yok).
## Çizgiler ekranda ~3 piksel kalınlığında görünsün diye kameraya dik küçük kaydırmalarla tekrarlanır.
func set_edge_highlight(ids: Array, hover := -1) -> void:
	_hl_ids = ids.duplicate()
	_hl_hover = hover
	var lb := LineBuilder.new()
	if not ids.is_empty() or hover >= 0:
		var w := camera.world_per_pixel()
		var bx := camera.global_transform.basis.x * w
		var by := camera.global_transform.basis.y * w
		var offs := [Vector3.ZERO, bx, -bx, by, -by]
		for e in model.brep_edges:
			var id := int(e["id"])
			var col := Color(0.15, 0.55, 1.0)
			if id in ids:
				col = Color(0.95, 0.38, 0.0)
			elif id != hover:
				continue
			var pts: PackedVector3Array = e["pts"]
			for o in offs:
				for i in pts.size() - 1:
					lb.line(pts[i] + o, pts[i + 1] + o, col)
	lb.commit(sel_edges_mi.mesh)


## Ekran noktasındaki görünür B-rep kenarı. Dönüş: {edge, point, dist_px} veya {}.
func pick_edge(screen: Vector2, tol_px := 8.0) -> Dictionary:
	if not model.has_brep():
		return {}
	var hit := model.pick_edge(screen, world_to_screen, tol_px)
	if hit.is_empty():
		return {}
	# Model tarafından örtülen kenarları ele: kameradan kenar noktasına ışın
	var p: Vector3 = hit["point"]
	var from := camera.project_ray_origin(world_to_screen(p))
	var dir := (p - from).normalized()
	var rc := model.raycast(from, dir)
	if not rc.is_empty() and float(rc["dist"]) < from.distance_to(p) - maxf(0.02, camera.world_per_pixel() * 3.0):
		return {}
	return hit


# ---------------------------------------------------------------- yardımcılar

func ray(pos: Vector2) -> Array:
	return [camera.project_ray_origin(pos), camera.project_ray_normal(pos)]


func world_to_screen(p: Vector3) -> Vector2:
	return camera.unproject_position(p)


func mouse_pos() -> Vector2:
	return container.get_local_mouse_position()


func show_cursor_text(text: String, pos: Vector2) -> void:
	if text.is_empty():
		cursor_label.visible = false
		return
	cursor_label.text = text
	cursor_label.position = pos + Vector2(18, 14)
	cursor_label.visible = true


func screenshot(path: String) -> Error:
	var img := screenshot_image()
	return img.save_png(path) if img else ERR_UNAVAILABLE


## Görünümün görüntüsü (saydam arka plan degradeyle birleştirilmiş)
func screenshot_image() -> Image:
	var img := subviewport.get_texture().get_image()
	if img == null or img.is_empty():
		return null      # ekransız (headless) çalışma
	# Arka plan saydam olduğundan degrade ile birleştir
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for y in out.get_height():
		var t := float(y) / maxf(out.get_height() - 1, 1)
		var c := Color(0.98, 0.99, 1.0).lerp(Color(0.70, 0.77, 0.86), t)
		out.fill_rect(Rect2i(0, y, out.get_width(), 1), c)
	img.convert(Image.FORMAT_RGBA8)
	out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	return out


func _on_view_changed() -> void:
	if camera == null:
		return
	var bias := camera.depth_bias()
	line_mat.set_shader_parameter("depth_bias", bias)
	grid_mat.set_shader_parameter("depth_bias", bias * 0.3)
	highlight_mat.set_shader_parameter("depth_bias", bias * 0.5)
	sel_edge_mat.set_shader_parameter("depth_bias", bias * 1.6)
	if not _hl_ids.is_empty() or _hl_hover >= 0:
		set_edge_highlight(_hl_ids, _hl_hover)
	# Orijin işareti (sabit piksel boyutunda)
	var w := camera.world_per_pixel()
	var L := 28.0 * w
	var lb := LineBuilder.new()
	lb.line(Vector3.ZERO, Vector3(L, 0, 0), Color(0.85, 0.15, 0.15))
	lb.line(Vector3.ZERO, Vector3(0, L, 0), Color(0.15, 0.6, 0.2))
	lb.line(Vector3.ZERO, Vector3(0, 0, L), Color(0.15, 0.35, 0.9))
	lb.commit(origin_mi.mesh)
	triad.queue_redraw()
	view_changed.emit()


# ---------------------------------------------------------------- girdi

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					camera.zoom_at(1.0 / (1.0 + 0.15 * maxf(mb.factor, 1.0)), mb.position)
				accept_event()
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					camera.zoom_at(1.0 + 0.15 * maxf(mb.factor, 1.0), mb.position)
				accept_event()
				return
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_nav = "pan" if mb.ctrl_pressed else ("zoom" if mb.shift_pressed else "rotate")
				else:
					_nav = ""
				accept_event()
				return
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_rmb_down = true
					_rmb_moved = false
					_rmb_accum = Vector2.ZERO
					_rmb_press = mb.position
				else:
					_rmb_down = false
					if not _rmb_moved:
						pointer_input.emit(event)
					elif rmb_gestures and not mb.ctrl_pressed:
						gesture_input.emit("end", mb.position)
				accept_event()
				return
		pointer_input.emit(event)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		match _nav:
			"rotate":
				camera.orbit(mm.relative.x, mm.relative.y)
				return
			"pan":
				camera.pan(mm.relative.x, mm.relative.y)
				return
			"zoom":
				camera.zoom_at(pow(1.01, mm.relative.y), container.size * 0.5)
				return
		if _rmb_down:
			_rmb_accum += mm.relative
			if not _rmb_moved and _rmb_accum.length() > 4.0:
				_rmb_moved = true
				if rmb_gestures and not mm.ctrl_pressed:
					gesture_input.emit("begin", _rmb_press)
			if _rmb_moved:
				if rmb_gestures and not mm.ctrl_pressed:
					gesture_input.emit("move", mm.position)
				elif mm.ctrl_pressed:
					camera.pan(mm.relative.x, mm.relative.y)
				else:
					camera.orbit(mm.relative.x, mm.relative.y)
			return
		pointer_input.emit(event)
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		camera.zoom_at(1.0 / maxf(mg.factor, 0.01), mg.position)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		camera.pan(-pg.delta.x * 8.0, -pg.delta.y * 8.0)
