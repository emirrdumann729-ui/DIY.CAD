class_name Surfaces
extends RefCounted
## Yüzey modelleme (Faz 8): ekstrüde / döndürülmüş / loft / düzlemsel yüzey, ofset, dikme (knit, isteğe bağlı
## katı), kalınlaştırma ve düzlemle kırpma. Yüzeyler katılarla aynı parçada ayrı (kalınlıksız) gövde olarak tutulur.

const TYPES := ["srf_extrude", "srf_revolve", "srf_loft", "srf_planar", "srf_offset", "srf_knit", "srf_thicken", "srf_trim"]
const LABELS := {"srf_extrude": "Ekstrüde Yüzey", "srf_revolve": "Döndürülmüş Yüzey", "srf_loft": "Loft Yüzey",
	"srf_planar": "Düzlemsel Yüzey", "srf_offset": "Ofset Yüzey", "srf_knit": "Yüzey Dikme", "srf_thicken": "Kalınlaştır",
	"srf_trim": "Yüzey Kırp"}
const SKETCH_TYPES := ["srf_extrude", "srf_revolve", "srf_planar"]


static func defaults(type: String) -> Dictionary:
	match type:
		"srf_extrude":
			return {"depth": 20.0, "reverse": false, "midplane": false}
		"srf_revolve":
			return {"angle": 360.0}
		"srf_loft":
			return {"sketches": [], "ruled": false}
		"srf_planar":
			return {}
		"srf_offset":
			return {"d": 2.0}
		"srf_knit":
			return {"solid": true, "tol": 0.01}
		"srf_thicken":
			return {"t": 2.0, "flip": false, "mid": false, "merge": true}
		"srf_trim":
			return {"plane": "top", "off": 0.0, "flip": false}
	return {}


static func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## Taslağın dönme ekseni: ilk yapı (merkez) çizgisi, yoksa taslak Y ekseni (orijinden)
static func revolve_axis(sk_f: CadFeature) -> Array:
	for e in sk_f.sketch.entities:
		if str(e["type"]) == "line" and bool(e.get("construction", false)):
			var a: Vector3 = sk_f.plane.to_world(sk_f.sketch.points[int(e["a"])])
			var b: Vector3 = sk_f.plane.to_world(sk_f.sketch.points[int(e["b"])])
			if a.distance_to(b) > 1e-9:
				return [a, (b - a).normalized()]
	return [sk_f.plane.origin, sk_f.plane.y_dir]


static func payload(doc: CadDocument, f: CadFeature, d: Dictionary) -> bool:
	match f.type:
		"srf_extrude", "srf_revolve", "srf_planar":
			var sk_f := doc.get_feature(f.sketch_ref())
			if sk_f == null or sk_f.sketch == null:
				f.error = I18n.t("Taslak bulunamadı")
				return false
			d["plane"] = OccKernel._plane_dict(sk_f.plane)
			d["sketch_fid"] = sk_f.id
			if f.type == "srf_planar":
				var prof := sk_f.sketch.extract_profiles()
				if (prof["loops"] as Array).is_empty():
					f.error = I18n.t("Düzlemsel yüzey için kapalı kontur gerekli")
					return false
				var loops: Array = []
				for L in prof["loops"]:
					loops.append({"depth": L["depth"], "parent": L["parent"], "curves": L["curves"]})
				d["loops"] = loops
				return true
			d["chains"] = sk_f.sketch.curve_chains()
			if (d["chains"] as Array).is_empty():
				f.error = I18n.t("Taslakta eğri yok")
				return false
			if f.type == "srf_extrude":
				var n := sk_f.plane.normal() * (-1.0 if bool(f.params.get("reverse", false)) else 1.0)
				var depth := maxf(0.001, float(f.params.get("depth", 20.0)))
				var vec := n * depth
				if bool(f.params.get("midplane", false)):
					var o := sk_f.plane.origin - vec * 0.5
					d["plane"]["o"] = _v3(o)
				d["vec"] = _v3(vec)
			else:
				var ax := revolve_axis(sk_f)
				d["axis_o"] = _v3(ax[0])
				d["axis_d"] = _v3(ax[1])
				d["angle"] = float(f.params.get("angle", 360.0))
			return true
		"srf_loft":
			var secs: Array = []
			for sid in f.params.get("sketches", []):
				var ls := doc.get_feature(int(sid))
				if ls == null or ls.sketch == null:
					continue
				var ch := ls.sketch.curve_chains()
				if ch.is_empty():
					continue
				secs.append({"plane": OccKernel._plane_dict(ls.plane), "curves": ch[0]})
			if secs.size() < 2:
				f.error = I18n.t("En az iki taslak seçin")
				return false
			d["sections"] = secs
			d["ruled"] = bool(f.params.get("ruled", false))
			return true
		"srf_offset":
			d["d"] = float(f.params.get("d", 2.0))
			return true
		"srf_knit":
			d["solid"] = bool(f.params.get("solid", true))
			d["tol"] = float(f.params.get("tol", 0.01))
			return true
		"srf_thicken":
			for k in ["t", "flip", "mid", "merge"]:
				d[k] = f.params.get(k, defaults("srf_thicken")[k])
			return true
		"srf_trim":
			var pl := SketchPlane.standard(str(f.params.get("plane", "top")))
			var n2 := pl.normal() * (-1.0 if bool(f.params.get("flip", false)) else 1.0)
			d["o"] = _v3(pl.normal() * float(f.params.get("off", 0.0)))
			d["n"] = _v3(n2)
			return true
	return false
