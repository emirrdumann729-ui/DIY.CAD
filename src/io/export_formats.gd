class_name ExportFormats
extends RefCounted
## Tek "Dışa Aktar" penceresinin format listesi ve ağ / görüntü / veri yazıcıları.
## Ağ yazıcıları ortak bir girdi alır: tris (saat yönü tersine üçgen köşeleri, mm) ve gruplar
## [{name, color: Color, start: ilk üçgen, count: üçgen sayısı}] — montajda bileşen başına bir grup.
## Koordinatlar programdaki gibidir (Y yukarı); yalnızca IFC Z-yukarı çerçeveye çevrilir.

## need: native_part | native_asm | native_drw | mesh | brep | sketch | drawing | image | data | none (desteklenmiyor)
const FORMATS := [
	# --- DIY.CAD yerel dosyaları (başka CAD programlarının yerel dosyalarının karşılığı)
	{"id": "dcad", "group": "DIY.CAD", "label": "DIY.CAD Parça", "ext": ["dcad"], "need": "native_part", "desc": "Parametrik parça dosyası (özellik ağacı, taslaklar, teknik resim sayfaları)."},
	{"id": "dasm", "group": "DIY.CAD", "label": "DIY.CAD Montaj", "ext": ["dasm"], "need": "native_asm", "desc": "Montaj dosyası (bileşenler, eşleştirmeler, patlatma, montaj resmi)."},
	{"id": "ddrw", "group": "DIY.CAD", "label": "DIY.CAD Teknik Resim", "ext": ["ddrw"], "need": "native_drw", "desc": "Teknik resim dosyası: parça ve resim sayfaları birlikte; açılınca Teknik Resim sekmesinde açılır."},
	{"id": "dcadt", "group": "DIY.CAD", "label": "DIY.CAD Parça Şablonu", "ext": ["dcadt"], "need": "native_part", "desc": "Parça şablonu: açılınca yeni (adsız) parça olarak başlar; birimler, malzeme, özellikler hazır gelir."},
	{"id": "dasmt", "group": "DIY.CAD", "label": "DIY.CAD Montaj Şablonu", "ext": ["dasmt"], "need": "native_asm", "desc": "Montaj şablonu: açılınca yeni (adsız) montaj olarak başlar."},
	{"id": "ddrwt", "group": "DIY.CAD", "label": "DIY.CAD Teknik Resim Şablonu", "ext": ["ddrwt"], "need": "native_drw", "desc": "Teknik resim şablonu: sayfa boyutu, antet ve görünüş yerleşimi yeni resimde hazır gelir."},
	{"id": "dclfp", "group": "DIY.CAD", "label": "DIY.CAD Kütüphane Unsuru Parçası", "ext": ["dclfp"], "need": "native_part", "desc": "Tekrar kullanılacak unsur (delik, cep, kanal...) için kütüphane parçası."},
	{"id": "dcftp", "group": "DIY.CAD", "label": "DIY.CAD Form Verme Aracı (Sac)", "ext": ["dcftp"], "need": "native_part", "desc": "Sac metalde ezme / kabartma için form verme aracı parçası."},
	# --- 3B katı (B-rep) değişim formatları
	{"id": "step214", "group": "3B katı (B-rep)", "label": "STEP AP214", "ext": ["step", "stp"], "need": "brep", "schema": "AP214IS", "desc": "Evrensel katı model formatı (renk / katman bilgili AP214). Diğer CAD programlarına aktarım için önerilir."},
	{"id": "step203", "group": "3B katı (B-rep)", "label": "STEP AP203", "ext": ["step", "stp"], "need": "brep", "schema": "AP203", "desc": "Evrensel katı model formatı (yapılandırma kontrollü AP203)."},
	{"id": "step242", "group": "3B katı (B-rep)", "label": "STEP AP242", "ext": ["step", "stp"], "need": "brep", "schema": "AP242DIS", "desc": "Evrensel katı model formatının yeni sürümü (AP242)."},
	{"id": "iges", "group": "3B katı (B-rep)", "label": "IGES", "ext": ["igs", "iges"], "need": "brep", "desc": "Yüzey ve tel kafes değişim formatı."},
	{"id": "brep", "group": "3B katı (B-rep)", "label": "OpenCASCADE BREP", "ext": ["brep"], "need": "brep", "desc": "OpenCASCADE'in kendi kesin geometri formatı."},
	{"id": "x_t", "group": "3B katı (B-rep)", "label": "Parasolid (X_T / X_B)", "ext": ["x_t", "x_b"], "need": "none", "desc": "Parasolid ticari, lisanslı bir çekirdeğin formatıdır; açık kaynak yazıcısı yok. Yerine STEP kullanın — Parasolid tabanlı programlar STEP'i sorunsuz açar."},
	{"id": "sat", "group": "3B katı (B-rep)", "label": "ACIS (SAT)", "ext": ["sat"], "need": "none", "desc": "ACIS ticari, lisanslı bir çekirdeğin formatıdır; açık kaynak yazıcısı yok. Yerine STEP kullanın."},
	{"id": "vda", "group": "3B katı (B-rep)", "label": "VDA-FS", "ext": ["vda"], "need": "none", "desc": "Eski otomotiv yüzey formatı; kullanılan OpenCASCADE sürümünde yazıcısı yok. Yerine STEP veya IGES kullanın."},
	{"id": "jt", "group": "3B katı (B-rep)", "label": "JT", "ext": ["jt"], "need": "none", "desc": "JT yazmak için ticari bir geliştirme kiti gerekir. Yerine STEP AP242 veya glTF kullanın."},
	# --- 3B ağ, baskı ve görselleştirme
	{"id": "stl", "group": "3B ağ / baskı / görselleştirme", "label": "STL", "ext": ["stl"], "need": "mesh", "desc": "3B baskı ve hızlı prototipleme ağ formatı (ikili). OpenCASCADE açıksa kalite ayarı Araçlar → Geometri çekirdeği'nden."},
	{"id": "3mf", "group": "3B ağ / baskı / görselleştirme", "label": "3MF", "ext": ["3mf"], "need": "mesh", "desc": "3D Manufacturing Format: birimli, renkli 3B baskı formatı (montajda bileşen başına nesne)."},
	{"id": "amf", "group": "3B ağ / baskı / görselleştirme", "label": "AMF", "ext": ["amf"], "need": "mesh", "desc": "Additive Manufacturing File: eklemeli imalat için XML ağ formatı (renkli)."},
	{"id": "obj", "group": "3B ağ / baskı / görselleştirme", "label": "Wavefront OBJ", "ext": ["obj"], "need": "mesh", "desc": "Genel 3B geometri ve render formatı."},
	{"id": "ply", "group": "3B ağ / baskı / görselleştirme", "label": "PLY", "ext": ["ply"], "need": "mesh", "desc": "Polygon File Format (ikili) — 3B tarayıcı ve ağ işleme programları."},
	{"id": "off", "group": "3B ağ / baskı / görselleştirme", "label": "OFF", "ext": ["off"], "need": "mesh", "desc": "Object File Format (metin)."},
	{"id": "fbx", "group": "3B ağ / baskı / görselleştirme", "label": "FBX", "ext": ["fbx"], "need": "mesh", "desc": "Animasyon ve oyun motoru formatı (ASCII FBX 7.4)."},
	{"id": "glb", "group": "3B ağ / baskı / görselleştirme", "label": "glTF ikili (GLB)", "ext": ["glb"], "need": "mesh", "desc": "Web ve AR / VR için 3B iletim formatı, tek dosya."},
	{"id": "gltf", "group": "3B ağ / baskı / görselleştirme", "label": "glTF (JSON)", "ext": ["gltf"], "need": "mesh", "desc": "Web ve AR / VR için 3B iletim formatı (veriler dosyanın içinde)."},
	{"id": "wrl", "group": "3B ağ / baskı / görselleştirme", "label": "VRML 97 (WRL)", "ext": ["wrl"], "need": "mesh", "desc": "Sanal gerçeklik modelleme dili."},
	{"id": "xaml", "group": "3B ağ / baskı / görselleştirme", "label": "XAML 3B", "ext": ["xaml"], "need": "mesh", "desc": "WPF Viewport3D sahnesi (MeshGeometry3D)."},
	{"id": "ifc", "group": "3B ağ / baskı / görselleştirme", "label": "IFC4 (BIM)", "ext": ["ifc"], "need": "mesh", "desc": "Yapı bilgi modellemesi: bileşenler üçgen yüzlü IfcBuildingElementProxy olarak (Z yukarı)."},
	{"id": "html", "group": "3B ağ / baskı / görselleştirme", "label": "HTML 3B görüntüleyici", "ext": ["html", "htm"], "need": "mesh", "desc": "Tarayıcıda açılan tek dosyalık 3B görüntüleyici (döndür / yakınlaştır). Paylaşım için eDrawings benzeri."},
	{"id": "3dxml", "group": "3B ağ / baskı / görselleştirme", "label": "3DXML / CGR", "ext": ["3dxml", "cgr"], "need": "none", "desc": "Belirli bir üreticinin kapalı formatları; açık yazıcı yok. Görselleştirme için glTF / GLB veya HTML kullanın."},
	{"id": "u3d", "group": "3B ağ / baskı / görselleştirme", "label": "U3D / 3B PDF", "ext": ["u3d"], "need": "none", "desc": "Henüz desteklenmiyor. Paylaşım için HTML görüntüleyici veya GLB kullanın."},
	{"id": "hsf", "group": "3B ağ / baskı / görselleştirme", "label": "HOOPS (HSF / HCG)", "ext": ["hsf", "hcg"], "need": "none", "desc": "Ticari HOOPS kütüphanesinin kapalı formatları; açık yazıcı yok. Yerine glTF / GLB kullanın."},
	{"id": "edrw", "group": "3B ağ / baskı / görselleştirme", "label": "eDrawings (EPRT / EASM / EDRW / EXE)", "ext": ["eprt", "easm", "edrw", "exe"], "need": "none", "desc": "Belirli bir üreticinin kapalı görüntüleyici formatları. Yerine HTML 3B görüntüleyici (tek dosya, her tarayıcıda açılır) veya PDF kullanın."},
	# --- 2B çizim
	{"id": "sk_dxf", "group": "2B çizim", "label": "Taslak DXF (R12)", "ext": ["dxf"], "need": "sketch", "desc": "Seçili / düzenlenen taslak: lazer ve CNC kesim."},
	{"id": "sk_svg", "group": "2B çizim", "label": "Taslak SVG", "ext": ["svg"], "need": "sketch", "desc": "Seçili / düzenlenen taslak, vektörel."},
	{"id": "dw_pdf", "group": "2B çizim", "label": "Teknik resim PDF", "ext": ["pdf"], "need": "drawing", "desc": "Etkin teknik resim sayfası, vektörel PDF."},
	{"id": "dw_dxf", "group": "2B çizim", "label": "Teknik resim DXF", "ext": ["dxf"], "need": "drawing", "desc": "Etkin teknik resim sayfası (katmanlı R12)."},
	{"id": "dw_svg", "group": "2B çizim", "label": "Teknik resim SVG", "ext": ["svg"], "need": "drawing", "desc": "Etkin teknik resim sayfası, vektörel."},
	{"id": "dw_ai", "group": "2B çizim", "label": "Adobe Illustrator (AI)", "ext": ["ai"], "need": "drawing", "desc": "Etkin teknik resim sayfası; PDF uyumlu AI (Illustrator doğrudan açar)."},
	{"id": "dwg", "group": "2B çizim", "label": "DWG", "ext": ["dwg"], "need": "none", "desc": "DWG kapalı bir formattır. DXF olarak kaydedip ücretsiz ODA File Converter veya AutoCAD ile DWG'ye çevirin."},
	# --- Görüntü (3B görünüm ya da teknik resim tuvali)
	{"id": "png", "group": "Görüntü", "label": "PNG", "ext": ["png"], "need": "image", "desc": "Kayıpsız görüntü."},
	{"id": "jpg", "group": "Görüntü", "label": "JPEG", "ext": ["jpg", "jpeg"], "need": "image", "desc": "Sıkıştırılmış görüntü."},
	{"id": "bmp", "group": "Görüntü", "label": "BMP", "ext": ["bmp"], "need": "image", "desc": "Windows bitmap (24 bit)."},
	{"id": "tif", "group": "Görüntü", "label": "TIFF", "ext": ["tif", "tiff"], "need": "image", "desc": "Sıkıştırmasız, yüksek kaliteli görüntü."},
	{"id": "psd", "group": "Görüntü", "label": "Photoshop (PSD)", "ext": ["psd"], "need": "image", "desc": "Tek katmanlı Photoshop belgesi."},
	# --- Veri ve paket
	{"id": "xml", "group": "Veri / paket", "label": "XML veri (özellikler, kütle, malzeme listesi)", "ext": ["xml"], "need": "data", "desc": "Belge bilgisi, özellik ağacı, malzeme ve kütle özellikleri; montajda malzeme listesi."},
	{"id": "zip", "group": "Veri / paket", "label": "ZIP paket", "ext": ["zip"], "need": "data", "desc": "Paylaşım paketi: DIY.CAD dosyası + STL + HTML görüntüleyici + PNG + XML."},
]


static func by_id(id: String) -> Dictionary:
	for f in FORMATS:
		if f["id"] == id:
			return f
	return {}


static func filter_of(f: Dictionary) -> String:
	var pats: Array = []
	for e in f["ext"]:
		pats.append("*." + str(e))
	return "%s ; %s" % [", ".join(pats), I18n.t(str(f["label"]))]


## Seçilen yolun uzantısı formatınkilerden değilse ilki eklenir
static func with_ext(path: String, f: Dictionary) -> String:
	var exts: Array = f["ext"]
	if path.get_extension().to_lower() in exts:
		return path
	return path + "." + str(exts[0])


# ---------------------------------------------------------------- ortak yardımcılar

static func _write_text(path: String, text: String) -> Error:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_string(text)
	fa.close()
	return OK


static func _write_bytes(path: String, data: PackedByteArray) -> Error:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_buffer(data)
	fa.close()
	return OK


static func _f(v: float) -> String:
	var s := "%.6f" % v
	s = s.rstrip("0").rstrip(".")
	return "0" if s == "-0" or s == "" else s


static func _xml(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


## Tek grup (tüm üçgenler)
static func one_group(tris: PackedVector3Array, name: String, color := Color(0.72, 0.75, 0.80)) -> Array:
	return [{"name": name, "color": color, "start": 0, "count": tris.size() / 3}]


## Köşe birleştirme: {verts, idx} (idx: üçgen başına 3 indeks, sarım korunur)
static func weld(tris: PackedVector3Array, start := 0, count := -1) -> Dictionary:
	if count < 0:
		count = tris.size() / 3 - start
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	idx.resize(count * 3)
	var map := {}
	for i in count * 3:
		var v := tris[start * 3 + i]
		var id: int = map.get(v, -1)
		if id < 0:
			id = verts.size()
			map[v] = id
			verts.append(v)
		idx[i] = id
	return {"verts": verts, "idx": idx}


static func _tri_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var n := (b - a).cross(c - a)
	return n.normalized() if n.length_squared() > 0.0 else Vector3.UP


# ---------------------------------------------------------------- ağ yazıcıları

## Ağ formatı yazıcısı (format kimliğine göre)
static func write_mesh(id: String, path: String, tris: PackedVector3Array, groups: Array, name := "DIY.CAD") -> Error:
	if tris.is_empty():
		return ERR_INVALID_DATA
	match id:
		"stl":
			return Exporters.write_stl(path, tris, name)
		"obj":
			return write_obj_tris(path, tris, groups)
		"3mf":
			return write_3mf(path, tris, groups)
		"amf":
			return write_amf(path, tris, groups)
		"ply":
			return write_ply(path, tris)
		"off":
			return write_off(path, tris)
		"fbx":
			return write_fbx(path, tris, groups)
		"glb":
			return write_gltf(path, tris, groups, true)
		"gltf":
			return write_gltf(path, tris, groups, false)
		"wrl":
			return write_wrl(path, tris, groups)
		"xaml":
			return write_xaml(path, tris, groups)
		"ifc":
			return write_ifc(path, tris, groups, name)
		"html":
			return write_html(path, tris, groups, name)
	return ERR_INVALID_PARAMETER


## Gruplu OBJ (+ MTL renkleri)
static func write_obj_tris(path: String, tris: PackedVector3Array, groups: Array) -> Error:
	var mtl_path := path.get_basename() + ".mtl"
	var lines := PackedStringArray(["# DIY.CAD OBJ export (birim: mm)", "mtllib " + mtl_path.get_file()])
	var mtl := PackedStringArray(["# DIY.CAD"])
	var off := 1
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var w := weld(tris, int(g["start"]), int(g["count"]))
		var verts: PackedVector3Array = w["verts"]
		var idx: PackedInt32Array = w["idx"]
		var mname := "m%d" % gi
		var col: Color = g["color"]
		mtl.append_array(["newmtl " + mname, "Kd %s %s %s" % [_f(col.r), _f(col.g), _f(col.b)], ""])
		lines.append("o " + _vrml_name(str(g["name"])))
		lines.append("usemtl " + mname)
		for v in verts:
			lines.append("v %s %s %s" % [_f(v.x), _f(v.y), _f(v.z)])
		for t in idx.size() / 3:
			lines.append("f %d %d %d" % [idx[t * 3] + off, idx[t * 3 + 1] + off, idx[t * 3 + 2] + off])
		off += verts.size()
	var err := _write_text(mtl_path, "\n".join(mtl) + "\n")
	if err != OK:
		return err
	return _write_text(path, "\n".join(lines) + "\n")


static func write_ply(path: String, tris: PackedVector3Array) -> Error:
	var w := weld(tris)
	var verts: PackedVector3Array = w["verts"]
	var idx: PackedInt32Array = w["idx"]
	var head := "ply\nformat binary_little_endian 1.0\ncomment DIY.CAD (mm)\nelement vertex %d\nproperty float x\nproperty float y\nproperty float z\nelement face %d\nproperty list uchar int vertex_indices\nend_header\n" % [verts.size(), idx.size() / 3]
	var buf := head.to_ascii_buffer()
	var body := PackedByteArray()
	body.resize(verts.size() * 12 + idx.size() / 3 * 13)
	var o := 0
	for v in verts:
		body.encode_float(o, v.x)
		body.encode_float(o + 4, v.y)
		body.encode_float(o + 8, v.z)
		o += 12
	for t in idx.size() / 3:
		body[o] = 3
		body.encode_s32(o + 1, idx[t * 3])
		body.encode_s32(o + 5, idx[t * 3 + 1])
		body.encode_s32(o + 9, idx[t * 3 + 2])
		o += 13
	buf.append_array(body)
	return _write_bytes(path, buf)


static func write_off(path: String, tris: PackedVector3Array) -> Error:
	var w := weld(tris)
	var verts: PackedVector3Array = w["verts"]
	var idx: PackedInt32Array = w["idx"]
	var lines := PackedStringArray(["OFF", "# DIY.CAD (mm)", "%d %d 0" % [verts.size(), idx.size() / 3]])
	for v in verts:
		lines.append("%s %s %s" % [_f(v.x), _f(v.y), _f(v.z)])
	for t in idx.size() / 3:
		lines.append("3 %d %d %d" % [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]])
	return _write_text(path, "\n".join(lines) + "\n")


static func write_wrl(path: String, tris: PackedVector3Array, groups: Array) -> Error:
	var out := PackedStringArray(["#VRML V2.0 utf8", "# DIY.CAD (birim: mm)", "WorldInfo { title \"DIY.CAD\" }"])
	for g in groups:
		var w := weld(tris, int(g["start"]), int(g["count"]))
		var verts: PackedVector3Array = w["verts"]
		var idx: PackedInt32Array = w["idx"]
		var col: Color = g["color"]
		var pts := PackedStringArray()
		for v in verts:
			pts.append("%s %s %s" % [_f(v.x), _f(v.y), _f(v.z)])
		var faces := PackedStringArray()
		for t in idx.size() / 3:
			faces.append("%d %d %d -1" % [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]])
		out.append("DEF %s Shape {" % _vrml_name(str(g["name"])))
		out.append("  appearance Appearance { material Material { diffuseColor %s %s %s specularColor 0.3 0.3 0.3 shininess 0.4 } }" % [_f(col.r), _f(col.g), _f(col.b)])
		out.append("  geometry IndexedFaceSet { solid FALSE creaseAngle 0.5")
		out.append("    coord Coordinate { point [ %s ] }" % ", ".join(pts))
		out.append("    coordIndex [ %s ] } }" % ", ".join(faces))
	return _write_text(path, "\n".join(out) + "\n")


static func _vrml_name(s: String) -> String:
	var o := ""
	for ch in s:
		o += ch if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_" else "_"
	return ("N_" + o) if o == "" or (o[0] >= "0" and o[0] <= "9") else o


static func _hex(c: Color) -> String:
	return "#%02X%02X%02X" % [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]


static func write_3mf(path: String, tris: PackedVector3Array, groups: Array) -> Error:
	var model := PackedStringArray(['<?xml version="1.0" encoding="UTF-8"?>',
		'<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">',
		'<metadata name="Application">DIY.CAD</metadata>', '<resources>', '<basematerials id="1">'])
	for g in groups:
		model.append('<base name="%s" displaycolor="%s" />' % [_xml(str(g["name"])), _hex(g["color"])])
	model.append("</basematerials>")
	var ids: Array = []
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var oid := gi + 2
		ids.append(oid)
		var w := weld(tris, int(g["start"]), int(g["count"]))
		var verts: PackedVector3Array = w["verts"]
		var idx: PackedInt32Array = w["idx"]
		model.append('<object id="%d" type="model" name="%s" pid="1" pindex="%d"><mesh><vertices>' % [oid, _xml(str(g["name"])), gi])
		for v in verts:
			model.append('<vertex x="%s" y="%s" z="%s" />' % [_f(v.x), _f(v.y), _f(v.z)])
		model.append("</vertices><triangles>")
		for t in idx.size() / 3:
			model.append('<triangle v1="%d" v2="%d" v3="%d" />' % [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]])
		model.append("</triangles></mesh></object>")
	model.append("</resources><build>")
	for oid in ids:
		model.append('<item objectid="%d" />' % oid)
	model.append("</build></model>")
	var files := {
		"[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" /><Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml" /></Types>',
		"_rels/.rels": '<?xml version="1.0" encoding="UTF-8"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" /></Relationships>',
		"3D/3dmodel.model": "\n".join(model)}
	return _zip_texts(path, files)


static func _zip_texts(path: String, files: Dictionary) -> Error:
	var z := ZIPPacker.new()
	var err := z.open(path)
	if err != OK:
		return err
	for name in files:
		z.start_file(str(name))
		var v: Variant = files[name]
		z.write_file(v if v is PackedByteArray else str(v).to_utf8_buffer())
		z.close_file()
	z.close()
	return OK


static func write_amf(path: String, tris: PackedVector3Array, groups: Array) -> Error:
	var out := PackedStringArray(['<?xml version="1.0" encoding="UTF-8"?>', '<amf unit="millimeter" version="1.1">',
		'<metadata type="producer">DIY.CAD</metadata>'])
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		out.append('<material id="%d"><metadata type="name">%s</metadata><color><r>%s</r><g>%s</g><b>%s</b></color></material>' % [
			gi + 1, _xml(str(g["name"])), _f(g["color"].r), _f(g["color"].g), _f(g["color"].b)])
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var w := weld(tris, int(g["start"]), int(g["count"]))
		var verts: PackedVector3Array = w["verts"]
		var idx: PackedInt32Array = w["idx"]
		out.append('<object id="%d"><metadata type="name">%s</metadata><mesh><vertices>' % [gi + 1, _xml(str(g["name"]))])
		for v in verts:
			out.append("<vertex><coordinates><x>%s</x><y>%s</y><z>%s</z></coordinates></vertex>" % [_f(v.x), _f(v.y), _f(v.z)])
		out.append('</vertices><volume materialid="%d">' % (gi + 1))
		for t in idx.size() / 3:
			out.append("<triangle><v1>%d</v1><v2>%d</v2><v3>%d</v3></triangle>" % [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]])
		out.append("</volume></mesh></object>")
	out.append("</amf>")
	return _write_text(path, "\n".join(out) + "\n")


## glTF 2.0 (metre, Y yukarı — program çerçevesiyle aynı). Düz gölgeleme için üçgen başına ayrı köşeler + normaller.
static func write_gltf(path: String, tris: PackedVector3Array, groups: Array, binary: bool) -> Error:
	var bin := PackedByteArray()
	var accessors: Array = []
	var views: Array = []
	var prims: Array = []
	var mats: Array = []
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var n := int(g["count"]) * 3
		if n == 0:
			continue
		var pos := PackedByteArray()
		pos.resize(n * 12)
		var nor := PackedByteArray()
		nor.resize(n * 12)
		var mn := Vector3(INF, INF, INF)
		var mx := -mn
		for t in int(g["count"]):
			var base := (int(g["start"]) + t) * 3
			var a := tris[base] * 0.001
			var b := tris[base + 1] * 0.001
			var c := tris[base + 2] * 0.001
			var nn := _tri_normal(a, b, c)
			for k in 3:
				var p: Vector3 = [a, b, c][k]
				var o := (t * 3 + k) * 12
				pos.encode_float(o, p.x)
				pos.encode_float(o + 4, p.y)
				pos.encode_float(o + 8, p.z)
				nor.encode_float(o, nn.x)
				nor.encode_float(o + 4, nn.y)
				nor.encode_float(o + 8, nn.z)
				mn = mn.min(p)
				mx = mx.max(p)
		views.append({"buffer": 0, "byteOffset": bin.size(), "byteLength": pos.size(), "target": 34962})
		bin.append_array(pos)
		views.append({"buffer": 0, "byteOffset": bin.size(), "byteLength": nor.size(), "target": 34962})
		bin.append_array(nor)
		accessors.append({"bufferView": views.size() - 2, "componentType": 5126, "count": n, "type": "VEC3",
			"min": [mn.x, mn.y, mn.z], "max": [mx.x, mx.y, mx.z]})
		accessors.append({"bufferView": views.size() - 1, "componentType": 5126, "count": n, "type": "VEC3"})
		var col: Color = g["color"]
		mats.append({"name": str(g["name"]), "doubleSided": true,
			"pbrMetallicRoughness": {"baseColorFactor": [col.r, col.g, col.b, 1.0], "metallicFactor": 0.1, "roughnessFactor": 0.6}})
		prims.append({"attributes": {"POSITION": accessors.size() - 2, "NORMAL": accessors.size() - 1}, "material": mats.size() - 1, "mode": 4})
	var doc := {"asset": {"version": "2.0", "generator": "DIY.CAD"}, "scene": 0, "scenes": [{"nodes": [0]}],
		"nodes": [{"mesh": 0, "name": "DIY.CAD"}], "meshes": [{"primitives": prims, "name": "DIY.CAD"}],
		"materials": mats, "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": bin.size()}]}
	if not binary:
		doc["buffers"][0]["uri"] = "data:application/octet-stream;base64," + Marshalls.raw_to_base64(bin)
		return _write_text(path, JSON.stringify(doc))
	var js := JSON.stringify(doc).to_utf8_buffer()
	while js.size() % 4 != 0:
		js.append(0x20)
	while bin.size() % 4 != 0:
		bin.append(0)
	var out := PackedByteArray()
	out.resize(12)
	out.encode_u32(0, 0x46546C67)
	out.encode_u32(4, 2)
	out.encode_u32(8, 12 + 8 + js.size() + 8 + bin.size())
	var ch := PackedByteArray()
	ch.resize(8)
	ch.encode_u32(0, js.size())
	ch.encode_u32(4, 0x4E4F534A)
	out.append_array(ch)
	out.append_array(js)
	ch.encode_u32(0, bin.size())
	ch.encode_u32(4, 0x004E4942)
	out.append_array(ch)
	out.append_array(bin)
	return _write_bytes(path, out)


## ASCII FBX 7.4 (birim: mm — UnitScaleFactor 0.1 santimetre tabanına göre)
static func write_fbx(path: String, tris: PackedVector3Array, groups: Array) -> Error:
	var o := PackedStringArray(["; FBX 7.4.0 project file", "; DIY.CAD", "FBXHeaderExtension:  {", "\tFBXHeaderVersion: 1003", "\tFBXVersion: 7400",
		"\tCreator: \"DIY.CAD\"", "}", "GlobalSettings:  {", "\tVersion: 1000", "\tProperties70:  {",
		"\t\tP: \"UpAxis\", \"int\", \"Integer\", \"\",1", "\t\tP: \"UpAxisSign\", \"int\", \"Integer\", \"\",1",
		"\t\tP: \"FrontAxis\", \"int\", \"Integer\", \"\",2", "\t\tP: \"FrontAxisSign\", \"int\", \"Integer\", \"\",1",
		"\t\tP: \"CoordAxis\", \"int\", \"Integer\", \"\",0", "\t\tP: \"CoordAxisSign\", \"int\", \"Integer\", \"\",1",
		"\t\tP: \"UnitScaleFactor\", \"double\", \"Number\", \"\",0.1", "\t}", "}"])
	var n := groups.size()
	o.append_array(["Definitions:  {", "\tVersion: 100", "\tCount: %d" % (1 + n * 3),
		"\tObjectType: \"GlobalSettings\" {", "\t\tCount: 1", "\t}",
		"\tObjectType: \"Model\" {", "\t\tCount: %d" % n, "\t}", "\tObjectType: \"Geometry\" {", "\t\tCount: %d" % n, "\t}",
		"\tObjectType: \"Material\" {", "\t\tCount: %d" % n, "\t}", "}", "Objects:  {"])
	var conns := PackedStringArray()
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var w := weld(tris, int(g["start"]), int(g["count"]))
		var verts: PackedVector3Array = w["verts"]
		var idx: PackedInt32Array = w["idx"]
		var gid := 100000 + gi * 10
		var mid := gid + 1
		var matid := gid + 2
		var vs := PackedStringArray()
		for v in verts:
			vs.append("%s,%s,%s" % [_f(v.x), _f(v.y), _f(v.z)])
		var pv := PackedStringArray()
		var ns := PackedStringArray()
		for t in idx.size() / 3:
			pv.append("%d,%d,%d" % [idx[t * 3], idx[t * 3 + 1], -idx[t * 3 + 2] - 1])
			var nn := _tri_normal(verts[idx[t * 3]], verts[idx[t * 3 + 1]], verts[idx[t * 3 + 2]])
			var s := "%s,%s,%s" % [_f(nn.x), _f(nn.y), _f(nn.z)]
			ns.append("%s,%s,%s" % [s, s, s])
		var nm := str(g["name"]).replace("\"", "'")
		o.append_array(["\tGeometry: %d, \"Geometry::%s\", \"Mesh\" {" % [gid, nm],
			"\t\tVertices: *%d {" % (verts.size() * 3), "\t\t\ta: " + ",".join(vs), "\t\t}",
			"\t\tPolygonVertexIndex: *%d {" % idx.size(), "\t\t\ta: " + ",".join(pv), "\t\t}",
			"\t\tGeometryVersion: 124",
			"\t\tLayerElementNormal: 0 {", "\t\t\tVersion: 101", "\t\t\tName: \"\"",
			"\t\t\tMappingInformationType: \"ByPolygonVertex\"", "\t\t\tReferenceInformationType: \"Direct\"",
			"\t\t\tNormals: *%d {" % (idx.size() * 3), "\t\t\t\ta: " + ",".join(ns), "\t\t\t}", "\t\t}",
			"\t\tLayerElementMaterial: 0 {", "\t\t\tVersion: 101", "\t\t\tName: \"\"",
			"\t\t\tMappingInformationType: \"AllSame\"", "\t\t\tReferenceInformationType: \"IndexToDirect\"",
			"\t\t\tMaterials: *1 {", "\t\t\t\ta: 0", "\t\t\t}", "\t\t}",
			"\t\tLayer: 0 {", "\t\t\tVersion: 100",
			"\t\t\tLayerElement:  {", "\t\t\t\tType: \"LayerElementNormal\"", "\t\t\t\tTypedIndex: 0", "\t\t\t}",
			"\t\t\tLayerElement:  {", "\t\t\t\tType: \"LayerElementMaterial\"", "\t\t\t\tTypedIndex: 0", "\t\t\t}", "\t\t}", "\t}",
			"\tModel: %d, \"Model::%s\", \"Mesh\" {" % [mid, nm], "\t\tVersion: 232", "\t\tCulling: \"CullingOff\"", "\t}"])
		var col: Color = g["color"]
		o.append_array(["\tMaterial: %d, \"Material::%s\", \"\" {" % [matid, nm], "\t\tVersion: 102", "\t\tShadingModel: \"phong\"",
			"\t\tProperties70:  {", "\t\t\tP: \"DiffuseColor\", \"Color\", \"\", \"A\",%s,%s,%s" % [_f(col.r), _f(col.g), _f(col.b)], "\t\t}", "\t}"])
		conns.append_array(["\tC: \"OO\",%d,0" % mid, "\tC: \"OO\",%d,%d" % [gid, mid], "\tC: \"OO\",%d,%d" % [matid, mid]])
	o.append("}")
	o.append("Connections:  {")
	o.append_array(conns)
	o.append("}")
	return _write_text(path, "\n".join(o) + "\n")


static func write_xaml(path: String, tris: PackedVector3Array, groups: Array) -> Error:
	var bb := AABB()
	if tris.size() > 0:
		bb = AABB(tris[0], Vector3.ZERO)
		for v in tris:
			bb = bb.expand(v)
	var c := bb.get_center()
	var r := maxf(bb.size.length(), 1.0)
	var cam := c + Vector3(1, 0.8, 1.2).normalized() * r * 1.6
	var out := PackedStringArray(['<Viewport3D xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">',
		'  <!-- DIY.CAD (birim: mm) -->',
		'  <Viewport3D.Camera><PerspectiveCamera Position="%s,%s,%s" LookDirection="%s,%s,%s" UpDirection="0,1,0" FieldOfView="40" /></Viewport3D.Camera>' % [
			_f(cam.x), _f(cam.y), _f(cam.z), _f(c.x - cam.x), _f(c.y - cam.y), _f(c.z - cam.z)],
		'  <ModelVisual3D><ModelVisual3D.Content><Model3DGroup>',
		'    <AmbientLight Color="#404040" /><DirectionalLight Color="#C0C0C0" Direction="-1,-1,-1" />'])
	for g in groups:
		var w := weld(tris, int(g["start"]), int(g["count"]))
		var verts: PackedVector3Array = w["verts"]
		var idx: PackedInt32Array = w["idx"]
		var ps := PackedStringArray()
		for v in verts:
			ps.append("%s,%s,%s" % [_f(v.x), _f(v.y), _f(v.z)])
		var ti := PackedStringArray()
		for i in idx:
			ti.append(str(i))
		out.append('    <GeometryModel3D x:Name="%s">' % _vrml_name(str(g["name"])))
		out.append('      <GeometryModel3D.Geometry><MeshGeometry3D Positions="%s" TriangleIndices="%s" /></GeometryModel3D.Geometry>' % [" ".join(ps), " ".join(ti)])
		out.append('      <GeometryModel3D.Material><DiffuseMaterial Brush="%s" /></GeometryModel3D.Material>' % _hex(g["color"]))
		out.append('      <GeometryModel3D.BackMaterial><DiffuseMaterial Brush="%s" /></GeometryModel3D.BackMaterial>' % _hex(g["color"]))
		out.append("    </GeometryModel3D>")
	out.append("  </Model3DGroup></ModelVisual3D.Content></ModelVisual3D>")
	out.append("</Viewport3D>")
	return _write_text(path, "\n".join(out) + "\n")


## IFC GlobalId: 22 karakter (IFC base64 alfabesi, ilk karakter 0–3)
static func _ifc_guid() -> String:
	const A := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$"
	var s := A[randi() % 4]
	for i in 21:
		s += A[randi() % 64]
	return s


static func _ifc_str(s: String) -> String:
	# IFC (ISO 10303-21) dizgisi: ASCII dışı karakterler \X2\ kodlamasıyla
	var o := ""
	for ch in s:
		var u := ch.unicode_at(0)
		if ch == "'":
			o += "''"
		elif ch == "\\":
			o += "\\\\"
		elif u < 128:
			o += ch
		else:
			o += "\\X2\\%04X\\X0\\" % u
	return "'" + o + "'"


static func write_ifc(path: String, tris: PackedVector3Array, groups: Array, project := "DIY.CAD") -> Error:
	var d := PackedStringArray()
	var t := Time.get_datetime_string_from_system(false, false)
	d.append_array(["ISO-10303-21;", "HEADER;", "FILE_DESCRIPTION(('ViewDefinition [ReferenceView]'),'2;1');",
		"FILE_NAME(%s,'%s',(''),(''),'DIY.CAD','DIY.CAD','');" % [_ifc_str(path.get_file()), t], "FILE_SCHEMA(('IFC4'));", "ENDSEC;", "DATA;",
		"#1=IFCCARTESIANPOINT((0.,0.,0.));", "#2=IFCDIRECTION((0.,0.,1.));", "#3=IFCDIRECTION((1.,0.,0.));",
		"#4=IFCAXIS2PLACEMENT3D(#1,#2,#3);", "#5=IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#4,$);",
		"#6=IFCGEOMETRICREPRESENTATIONSUBCONTEXT('Body','Model',*,*,*,*,#5,$,.MODEL_VIEW.,$);",
		"#7=IFCSIUNIT(*,.LENGTHUNIT.,.MILLI.,.METRE.);", "#8=IFCUNITASSIGNMENT((#7));",
		"#9=IFCPROJECT('%s',$,%s,$,$,$,$,(#5),#8);" % [_ifc_guid(), _ifc_str(project)],
		"#10=IFCLOCALPLACEMENT($,#4);",
		"#11=IFCSITE('%s',$,'Site',$,$,#10,$,$,.ELEMENT.,$,$,$,$,$);" % _ifc_guid(),
		"#12=IFCRELAGGREGATES('%s',$,$,$,#9,(#11));" % _ifc_guid()])
	var nid := 20
	var elems: Array = []
	for g in groups:
		var w := weld(tris, int(g["start"]), int(g["count"]))
		var verts: PackedVector3Array = w["verts"]
		var idx: PackedInt32Array = w["idx"]
		if idx.is_empty():
			continue
		var pts := PackedStringArray()
		for v in verts:
			# program Y yukarı → IFC Z yukarı: (x, y, z) → (x, -z, y)
			pts.append("(%s,%s,%s)" % [_ifc_num(v.x), _ifc_num(-v.z), _ifc_num(v.y)])
		var fs := PackedStringArray()
		for k in idx.size() / 3:
			fs.append("(%d,%d,%d)" % [idx[k * 3] + 1, idx[k * 3 + 1] + 1, idx[k * 3 + 2] + 1])
		var col: Color = g["color"]
		d.append("#%d=IFCCARTESIANPOINTLIST3D((%s));" % [nid, ",".join(pts)])
		d.append("#%d=IFCTRIANGULATEDFACESET(#%d,$,$,(%s),$);" % [nid + 1, nid, ",".join(fs)])
		d.append("#%d=IFCSHAPEREPRESENTATION(#6,'Body','Tessellation',(#%d));" % [nid + 2, nid + 1])
		d.append("#%d=IFCPRODUCTDEFINITIONSHAPE($,$,(#%d));" % [nid + 3, nid + 2])
		d.append("#%d=IFCBUILDINGELEMENTPROXY('%s',$,%s,$,$,#10,#%d,$,$);" % [nid + 4, _ifc_guid(), _ifc_str(str(g["name"])), nid + 3])
		d.append("#%d=IFCCOLOURRGB($,%s,%s,%s);" % [nid + 5, _ifc_num(col.r), _ifc_num(col.g), _ifc_num(col.b)])
		d.append("#%d=IFCSURFACESTYLESHADING(#%d,$);" % [nid + 6, nid + 5])
		d.append("#%d=IFCSURFACESTYLE($,.BOTH.,(#%d));" % [nid + 7, nid + 6])
		d.append("#%d=IFCSTYLEDITEM(#%d,(#%d),$);" % [nid + 8, nid + 1, nid + 7])
		elems.append("#%d" % (nid + 4))
		nid += 10
	d.append("#%d=IFCRELCONTAINEDINSPATIALSTRUCTURE('%s',$,$,$,(%s),#11);" % [nid, _ifc_guid(), ",".join(elems)])
	d.append_array(["ENDSEC;", "END-ISO-10303-21;"])
	return _write_text(path, "\n".join(d) + "\n")


static func _ifc_num(v: float) -> String:
	var s := _f(v)
	return s if "." in s or "e" in s else s + "."


## Tek dosyalık WebGL görüntüleyici (dış kütüphane yok)
static func write_html(path: String, tris: PackedVector3Array, groups: Array, title := "DIY.CAD") -> Error:
	var pos := PackedByteArray()
	var col := PackedByteArray()
	var n := tris.size()
	pos.resize(n * 12)
	col.resize(n * 3)
	var tri_group := PackedInt32Array()
	tri_group.resize(n / 3)
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		for t in int(g["count"]):
			tri_group[int(g["start"]) + t] = gi
	for i in n:
		var v := tris[i]
		pos.encode_float(i * 12, v.x)
		pos.encode_float(i * 12 + 4, v.y)
		pos.encode_float(i * 12 + 8, v.z)
		var c: Color = groups[tri_group[i / 3]]["color"] if not groups.is_empty() else Color(0.72, 0.75, 0.8)
		col[i * 3] = int(c.r * 255.0)
		col[i * 3 + 1] = int(c.g * 255.0)
		col[i * 3 + 2] = int(c.b * 255.0)
	var html := """<!DOCTYPE html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>html,body{margin:0;height:100%;overflow:hidden;font-family:system-ui,sans-serif;background:linear-gradient(#fafcff,#b3c4db)}
canvas{width:100%;height:100%;display:block;touch-action:none}#i{position:fixed;left:12px;top:10px;color:#223;font-size:14px;background:#fffc;padding:6px 10px;border-radius:6px}</style>
</head><body><canvas id="c"></canvas><div id="i"><b>__TITLE__</b> — DIY.CAD · drag: rotate · right-drag / shift: pan · wheel: zoom · double-click: fit</div>
<script>
const P=Uint8Array.from(atob("__POS__"),c=>c.charCodeAt(0)), C=Uint8Array.from(atob("__COL__"),c=>c.charCodeAt(0));
const pos=new Float32Array(P.buffer), n=pos.length/3, nor=new Float32Array(pos.length), col=new Float32Array(pos.length);
let mn=[1e30,1e30,1e30], mx=[-1e30,-1e30,-1e30];
for(let t=0;t<n;t+=3){const a=t*3,b=a+3,c=a+6;const u=[pos[b]-pos[a],pos[b+1]-pos[a+1],pos[b+2]-pos[a+2]],v=[pos[c]-pos[a],pos[c+1]-pos[a+1],pos[c+2]-pos[a+2]];
let q=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];const l=Math.hypot(...q)||1;q=q.map(x=>x/l);for(let k=0;k<9;k++)nor[a+k]=q[k%3];}
for(let i=0;i<n;i++){for(let k=0;k<3;k++){const x=pos[i*3+k];mn[k]=Math.min(mn[k],x);mx[k]=Math.max(mx[k],x);col[i*3+k]=C[i*3+k]/255;}}
const cen=mn.map((v,k)=>(v+mx[k])/2), rad=Math.max(Math.hypot(mx[0]-mn[0],mx[1]-mn[1],mx[2]-mn[2])/2,1);
const cv=document.getElementById('c'), gl=cv.getContext('webgl',{antialias:true});
function sh(t,s){const o=gl.createShader(t);gl.shaderSource(o,s);gl.compileShader(o);return o;}
const pr=gl.createProgram();
gl.attachShader(pr,sh(gl.VERTEX_SHADER,'attribute vec3 p,n,c;uniform mat4 M,V;varying vec3 vn,vc;void main(){vn=mat3(V)*n;vc=c;gl_Position=M*V*vec4(p,1.);}'));
gl.attachShader(pr,sh(gl.FRAGMENT_SHADER,'precision mediump float;varying vec3 vn,vc;void main(){vec3 N=normalize(vn);if(!gl_FrontFacing)N=-N;float d=max(dot(N,normalize(vec3(.4,.6,1.))),0.);float s=pow(max(N.z,0.),24.)*.25;gl_FragColor=vec4(vc*(.35+.7*d)+s,1.);}'));
gl.linkProgram(pr);gl.useProgram(pr);
function buf(a,name){const b=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,b);gl.bufferData(gl.ARRAY_BUFFER,a,gl.STATIC_DRAW);const l=gl.getAttribLocation(pr,name);gl.enableVertexAttribArray(l);gl.vertexAttribPointer(l,3,gl.FLOAT,false,0,0);}
buf(pos,'p');buf(nor,'n');buf(col,'c');gl.enable(gl.DEPTH_TEST);
let yaw=0.7,pit=0.45,dist=rad*2.6,pan=[0,0];
function mul(a,b){const r=new Float32Array(16);for(let i=0;i<4;i++)for(let j=0;j<4;j++){let s=0;for(let k=0;k<4;k++)s+=a[k*4+j]*b[i*4+k];r[i*4+j]=s;}return r;}
function draw(){const w=cv.clientWidth*devicePixelRatio,h=cv.clientHeight*devicePixelRatio;if(cv.width!=w||cv.height!=h){cv.width=w;cv.height=h;}gl.viewport(0,0,w,h);
gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
const cy=Math.cos(yaw),sy=Math.sin(yaw),cp=Math.cos(pit),sp=Math.sin(pit);
const R=new Float32Array([cy,sy*sp,-sy*cp,0, 0,cp,sp,0, sy,-cy*sp,cy*cp,0, 0,0,0,1]);
const T=new Float32Array([1,0,0,0,0,1,0,0,0,0,1,0,-cen[0],-cen[1],-cen[2],1]);
let V=mul(R,T);V[12]+=pan[0];V[13]+=pan[1];V[14]-=dist;
const f=1/Math.tan(0.35),a=w/h,nr=dist/100,fr=dist*10;
const M=new Float32Array([f/a,0,0,0,0,f,0,0,0,0,(fr+nr)/(nr-fr),-1,0,0,2*fr*nr/(nr-fr),0]);
gl.uniformMatrix4fv(gl.getUniformLocation(pr,'M'),false,M);gl.uniformMatrix4fv(gl.getUniformLocation(pr,'V'),false,V);gl.drawArrays(gl.TRIANGLES,0,n);}
let drag=null;cv.oncontextmenu=e=>e.preventDefault();
cv.onpointerdown=e=>{drag={x:e.clientX,y:e.clientY,b:(e.button==2||e.shiftKey)};cv.setPointerCapture(e.pointerId);};
cv.onpointermove=e=>{if(!drag)return;const dx=e.clientX-drag.x,dy=e.clientY-drag.y;drag.x=e.clientX;drag.y=e.clientY;
if(drag.b){const k=dist/cv.clientHeight*0.75;pan[0]+=dx*k;pan[1]-=dy*k;}else{yaw+=dx*0.01;pit=Math.max(-1.55,Math.min(1.55,pit+dy*0.01));}draw();};
cv.onpointerup=()=>drag=null;cv.onwheel=e=>{e.preventDefault();dist*=Math.exp(e.deltaY*0.001);draw();};
cv.ondblclick=()=>{dist=rad*2.6;pan=[0,0];draw();};window.onresize=draw;draw();
</script></body></html>
"""
	html = html.replace("__TITLE__", _xml(title)).replace("__POS__", Marshalls.raw_to_base64(pos)).replace("__COL__", Marshalls.raw_to_base64(col))
	return _write_text(path, html)


# ---------------------------------------------------------------- görüntü yazıcıları

static func _rgba(img: Image) -> Image:
	var im := img.duplicate() as Image
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	return im


## 24 bit BMP (alt satırdan üste, BGR, 4 bayt hizalı satır)
static func write_bmp(path: String, img: Image) -> Error:
	var im := _rgba(img)
	var w := im.get_width()
	var h := im.get_height()
	var row := (w * 3 + 3) & ~3
	var data := PackedByteArray()
	data.resize(54 + row * h)
	data.fill(0)
	data[0] = 0x42
	data[1] = 0x4D
	data.encode_u32(2, data.size())
	data.encode_u32(10, 54)
	data.encode_u32(14, 40)
	data.encode_s32(18, w)
	data.encode_s32(22, h)
	data.encode_u16(26, 1)
	data.encode_u16(28, 24)
	data.encode_u32(34, row * h)
	data.encode_s32(38, 2835)
	data.encode_s32(42, 2835)
	var px := im.get_data()
	for y in h:
		var o := 54 + (h - 1 - y) * row
		for x in w:
			var s := (y * w + x) * 4
			data[o + x * 3] = px[s + 2]
			data[o + x * 3 + 1] = px[s + 1]
			data[o + x * 3 + 2] = px[s]
	return _write_bytes(path, data)


## Sıkıştırmasız taban TIFF (RGBA, little-endian, tek şerit)
static func write_tiff(path: String, img: Image) -> Error:
	var im := _rgba(img)
	var w := im.get_width()
	var h := im.get_height()
	var px := im.get_data()
	var entries := [[256, 4, 1, w], [257, 4, 1, h], [258, 3, 4, 0], [259, 3, 1, 1], [262, 3, 1, 2],
		[273, 4, 1, 0], [277, 3, 1, 4], [278, 4, 1, h], [279, 4, 1, px.size()], [284, 3, 1, 1], [338, 3, 1, 2]]
	var ifd_off := 8
	var ifd_size := 2 + entries.size() * 12 + 4
	var bps_off := ifd_off + ifd_size
	var data_off := bps_off + 8
	var out := PackedByteArray()
	out.resize(data_off)
	out.fill(0)
	out[0] = 0x49
	out[1] = 0x49
	out.encode_u16(2, 42)
	out.encode_u32(4, ifd_off)
	out.encode_u16(ifd_off, entries.size())
	for i in entries.size():
		var e: Array = entries[i]
		var o := ifd_off + 2 + i * 12
		out.encode_u16(o, e[0])
		out.encode_u16(o + 2, e[1])
		out.encode_u32(o + 4, e[2])
		var val: int = e[3]
		if e[0] == 258:
			val = bps_off
		elif e[0] == 273:
			val = data_off
		if e[1] == 3 and e[2] == 1:
			out.encode_u16(o + 8, val)
		else:
			out.encode_u32(o + 8, val)
	for k in 4:
		out.encode_u16(bps_off + k * 2, 8)
	out.append_array(px)
	return _write_bytes(path, out)


## Tek katmanlı Photoshop belgesi (yalnız birleşik görüntü, RGB 8 bit, ham veri)
static func write_psd(path: String, img: Image) -> Error:
	var im := _rgba(img)
	var w := im.get_width()
	var h := im.get_height()
	var px := im.get_data()
	var out := PackedByteArray()
	out.append_array("8BPS".to_ascii_buffer())
	var hdr := PackedByteArray()
	hdr.resize(22)
	hdr.fill(0)
	hdr[1] = 1                   # sürüm 1 (büyük uçlu)
	hdr[9] = 3                   # kanal sayısı (RGB)
	_be32(hdr, 10, h)
	_be32(hdr, 14, w)
	hdr[19] = 8                  # bit derinliği
	hdr[21] = 3                  # RGB
	out.append_array(hdr.slice(0, 22))
	for k in 3:                  # renk modu verisi, görüntü kaynakları, katman bilgisi: boş
		out.append_array(PackedByteArray([0, 0, 0, 0]))
	out.append_array(PackedByteArray([0, 0]))   # sıkıştırma: ham
	var plane := PackedByteArray()
	plane.resize(w * h)
	for ch in 3:
		for i in w * h:
			plane[i] = px[i * 4 + ch]
		out.append_array(plane)
	return _write_bytes(path, out)


static func _be32(b: PackedByteArray, o: int, v: int) -> void:
	b[o] = (v >> 24) & 0xFF
	b[o + 1] = (v >> 16) & 0xFF
	b[o + 2] = (v >> 8) & 0xFF
	b[o + 3] = v & 0xFF


static func write_image(path: String, img: Image, id: String) -> Error:
	if img == null or img.is_empty():
		return ERR_UNAVAILABLE
	match id:
		"png":
			return _rgba(img).save_png(path)
		"jpg":
			var im := _rgba(img)
			im.convert(Image.FORMAT_RGB8)
			return im.save_jpg(path, 0.92)
		"bmp":
			return write_bmp(path, img)
		"tif":
			return write_tiff(path, img)
		"psd":
			return write_psd(path, img)
	return ERR_INVALID_PARAMETER


# ---------------------------------------------------------------- veri

## Basit sözlük / dizi → XML (anahtarlar öğe adı olur)
static func write_xml(path: String, root_name: String, data: Dictionary) -> Error:
	var out := PackedStringArray(['<?xml version="1.0" encoding="UTF-8"?>'])
	_xml_node(out, root_name, data, 0)
	return _write_text(path, "\n".join(out) + "\n")


static func _xml_node(out: PackedStringArray, name: String, v: Variant, depth: int) -> void:
	var pad := "  ".repeat(depth)
	if v is Dictionary:
		out.append("%s<%s>" % [pad, name])
		for k in v:
			_xml_node(out, str(k), v[k], depth + 1)
		out.append("%s</%s>" % [pad, name])
	elif v is Array:
		out.append("%s<%s>" % [pad, name])
		var item := name.trim_suffix("s") if name.ends_with("s") else "item"
		for e in v:
			_xml_node(out, item, e, depth + 1)
		out.append("%s</%s>" % [pad, name])
	else:
		var s := (_f(v) if v is float else str(v))
		out.append("%s<%s>%s</%s>" % [pad, name, _xml(s), name])


## Dosyaları ZIP'e koy: [{name (zip içindeki ad), path (diskteki dosya)}]
static func write_zip(path: String, files: Array) -> Error:
	var z := ZIPPacker.new()
	var err := z.open(path)
	if err != OK:
		return err
	for f in files:
		if not FileAccess.file_exists(str(f["path"])):
			continue
		z.start_file(str(f["name"]))
		z.write_file(FileAccess.get_file_as_bytes(str(f["path"])))
		z.close_file()
	z.close()
	return OK
