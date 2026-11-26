class_name CadFeature
extends RefCounted
## Özellik ağacındaki tek bir öğe.
## type: "sketch" | "sketch3d" | "extrude" | "revolve" | "fillet" | "chamfer" | "shell" | "import"
## params (extrude): sketch, depth, end("blind"|"midplane"|"through"), reverse, cut, regions?
## params (revolve): sketch, angle, axis("x"|"y"|varlık id), reverse, cut, regions?
## params (fillet):  r, edges: [{m: orta nokta [x,y,z], d: teğet [x,y,z]}]   (B-rep çekirdeği)
## params (chamfer): d, edges: [...]
## params (shell):   t, faces: [{p: yüz üzerinde nokta, n: normal}], outward
## params (import):  path (STEP/IGES), scale
## params (draft):   angle, faces: [{p, n, name}], neutral: {p, n, name}, reverse
## params (rib):     sketch, t (kalınlık)
## params (combine): op ("add"|"subtract"|"common"), bodies: [{p, name}] (ilki ana gövde)
## params (move_body): body {p, name}, t [dx,dy,dz], axis ("x"|"y"|"z"), angle, copy
## params (split):   plane ("front"|"top"|"right"), offset, keep ("both"|"pos"|"neg")
## extrude/revolve/fillet/chamfer ek: merge (ayrı gövde için false), r2+variable, mode/d2/angle/flip

var id := 0
var type := ""
var name := ""
var suppressed := false
var params := {}
var plane: SketchPlane = null   # yalnızca taslaklar için
var sketch: Sketch = null       # yalnızca taslaklar için
var sketch3d: Sketch3D = null   # yalnızca 3B taslaklar için
var error := ""                 # rebuild sırasında doldurulur (kaydedilmez)
var runtime := {}               # çekirdekten gelen geçici veriler (ör. projeksiyon eğrisi noktaları; kaydedilmez)


func is_sketch() -> bool:
	return type == "sketch"


func is_cut() -> bool:
	return bool(params.get("cut", false))


func sketch_ref() -> int:
	return int(params.get("sketch", 0))


func type_label() -> String:
	match type:
		"sketch":
			return "Taslak"
		"sketch3d":
			return "3B Taslak"
		"extrude":
			return "Ekstrüzyon Kesme" if is_cut() else "Ekstrüzyon Patron/Taban"
		"revolve":
			return "Döndürerek Kesme" if is_cut() else "Döndürme Patron/Taban"
		"fillet":
			return "Köşe Yuvarlatma"
		"chamfer":
			return "Pah"
		"shell":
			return "Kabuk"
		"import":
			return "İçe Aktarılan Gövde"
		"draft":
			return "Eğim"
		"rib":
			return "Kaburga"
		"combine":
			return "Gövdeleri Birleştir"
		"move_body":
			return "Gövde Taşı/Kopyala"
		"split":
			return "Böl"
		"refplane":
			return "Referans Düzlem"
		"refaxis":
			return "Referans Eksen"
		"refpoint":
			return "Referans Nokta"
		"helix":
			return "Helis"
		"sweep":
			return "Süpürme Kesme" if is_cut() else "Süpürme Patron/Taban"
		"loft":
			return "Loft Kesme" if is_cut() else "Loft Patron/Taban"
		"lpattern":
			return "Doğrusal Çoğaltma"
		"cpattern":
			return "Dairesel Çoğaltma"
		"mirror":
			return "Aynala"
		"tpattern":
			return "Tablo Güdümlü Çoğaltma"
		"hole":
			return "Delik"
		"dome":
			return "Kubbe"
		"refcsys":
			return "Koordinat Sistemi"
		"projcurve":
			return "Projeksiyon Eğrisi"
		"cvpattern":
			return "Eğri Güdümlü Çoğaltma"
		"wrap":
			return "Sarma"
		"emboss":
			return "Kabartma"
		"sm_base":
			return "Taban Flanş"
		"sm_edge":
			return "Kenar Flanş"
		"weld":
			return "Yapısal Üye"
		"srf_extrude", "srf_revolve", "srf_loft", "srf_planar", "srf_offset", "srf_knit", "srf_thicken", "srf_trim":
			return str(Surfaces.LABELS[type])
	return type


## Referans geometri (katı üretmeyen) özellik mi?
func is_reference() -> bool:
	return type in ["refplane", "refaxis", "refpoint", "helix", "refcsys"]


## Bu özelliğin kullandığı taslaklar (ağaçta altında gösterilir).
func used_sketch_ids() -> Array:
	var out: Array = []
	if type == "helix":
		return out
	if params.has("sketch"):
		out.append(int(params["sketch"]))
	for s in params.get("sketches", []):
		out.append(int(s))
	for key in ["path", "guide", "curve"]:
		var path = params.get(key, {})
		if path is Dictionary and str(path.get("kind", "")) in ["sketch", "sketch3d"] and path.has("id"):
			out.append(int(path["id"]))
	return out


## Taslağa dayalı olmayan, doğrudan gövde üzerinde (kenar/yüz/gövde seçerek) çalışan B-rep özelliği mi?
func is_brep_feature() -> bool:
	return type in ["fillet", "chamfer", "shell", "import", "draft", "combine", "move_body", "split", "hole", "dome", "sm_edge"]


func to_dict() -> Dictionary:
	var d := {"id": id, "type": type, "name": name, "suppressed": suppressed, "params": params.duplicate(true)}
	if plane:
		d["plane"] = plane.to_dict()
	if sketch:
		d["sketch"] = sketch.to_dict()
	if sketch3d:
		d["sketch3d"] = sketch3d.to_dict()
	return d


static func from_dict(d: Dictionary) -> CadFeature:
	var f := CadFeature.new()
	f.id = int(d.get("id", 0))
	f.type = str(d.get("type", ""))
	f.name = str(d.get("name", ""))
	f.suppressed = bool(d.get("suppressed", false))
	f.params = (d.get("params", {}) as Dictionary).duplicate(true)
	if f.params.has("sketch"):
		f.params["sketch"] = int(f.params["sketch"])
	if f.params.has("axis") and typeof(f.params["axis"]) == TYPE_FLOAT:
		f.params["axis"] = int(f.params["axis"])
	if d.has("plane"):
		f.plane = SketchPlane.from_dict(d["plane"])
	if d.has("sketch"):
		f.sketch = Sketch.from_dict(d["sketch"])
	if d.has("sketch3d"):
		f.sketch3d = Sketch3D.from_dict(d["sketch3d"])
	return f


func clone() -> CadFeature:
	var c := CadFeature.from_dict(to_dict())
	c.error = error
	return c
