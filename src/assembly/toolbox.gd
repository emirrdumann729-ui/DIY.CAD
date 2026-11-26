class_name Toolbox
extends RefCounted
## Standart bağlantı elemanı kütüphanesi (Toolbox benzeri): parametrik parça belgeleri üretir.
## Eksen +Y; cıvata başı alt yüzü y=0'da, gövde -Y yönünde. Somun / pul / pim / rulman y=0..kalınlık.

const STEEL := "Düz Karbon Çelik (AISI 1020)"
const STAINLESS := "Paslanmaz Çelik (AISI 304)"

## Metrik ölçüler: s (anahtar ağzı), k (baş yüksekliği), m (somun yüksekliği), pul [iç, dış, kalınlık]
const METRIC := {
	"M3": {"d": 3.0, "s": 5.5, "k": 2.0, "m": 2.4, "w": [3.2, 7.0, 0.5], "p": 0.5},
	"M4": {"d": 4.0, "s": 7.0, "k": 2.8, "m": 3.2, "w": [4.3, 9.0, 0.8], "p": 0.7},
	"M5": {"d": 5.0, "s": 8.0, "k": 3.5, "m": 4.7, "w": [5.3, 10.0, 1.0], "p": 0.8},
	"M6": {"d": 6.0, "s": 10.0, "k": 4.0, "m": 5.2, "w": [6.4, 12.0, 1.6], "p": 1.0},
	"M8": {"d": 8.0, "s": 13.0, "k": 5.3, "m": 6.8, "w": [8.4, 16.0, 1.6], "p": 1.25},
	"M10": {"d": 10.0, "s": 16.0, "k": 6.4, "m": 8.4, "w": [10.5, 20.0, 2.0], "p": 1.5},
	"M12": {"d": 12.0, "s": 18.0, "k": 7.5, "m": 10.8, "w": [13.0, 24.0, 2.5], "p": 1.75},
	"M16": {"d": 16.0, "s": 24.0, "k": 10.0, "m": 14.8, "w": [17.0, 30.0, 3.0], "p": 2.0},
	"M20": {"d": 20.0, "s": 30.0, "k": 12.5, "m": 18.0, "w": [21.0, 37.0, 3.0], "p": 2.5},
	"M24": {"d": 24.0, "s": 36.0, "k": 15.0, "m": 21.5, "w": [25.0, 44.0, 4.0], "p": 3.0},
}
const BOLT_LENGTHS := [6, 8, 10, 12, 16, 20, 25, 30, 35, 40, 45, 50, 60, 70, 80, 100, 120]
## Sabit bilyalı rulmanlar: [iç çap d, dış çap D, genişlik B]
const BEARINGS := {
	"608": [8.0, 22.0, 7.0], "6000": [10.0, 26.0, 8.0], "6001": [12.0, 28.0, 8.0], "6002": [15.0, 32.0, 9.0],
	"6003": [17.0, 35.0, 10.0], "6004": [20.0, 42.0, 12.0], "6005": [25.0, 47.0, 12.0], "6200": [10.0, 30.0, 9.0],
	"6201": [12.0, 32.0, 10.0], "6202": [15.0, 35.0, 11.0], "6203": [17.0, 40.0, 12.0], "6204": [20.0, 47.0, 14.0],
}
const TYPES := {"bolt": "Altıgen başlı cıvata (ISO 4017)", "nut": "Altıgen somun (ISO 4032)", "washer": "Düz pul (ISO 7089)",
	"pin": "Silindirik pim (ISO 2338)", "bearing": "Sabit bilyalı rulman (60xx / 62xx)"}


static func designation(spec: Dictionary) -> String:
	var sz := str(spec.get("size", "M8"))
	match str(spec.get("type", "")):
		"bolt":
			return "Cıvata ISO 4017 %sx%d" % [sz, int(spec.get("length", 30))]
		"nut":
			return "Somun ISO 4032 %s" % sz
		"washer":
			return "Pul ISO 7089 %s" % sz
		"pin":
			return "Pim ISO 2338 %sx%d" % [str(spec.get("dia", 6)), int(spec.get("length", 20))]
		"bearing":
			return "Rulman %s" % sz
	return "Bağlantı elemanı"


static func _sketch(doc: CadDocument) -> CadFeature:
	var s := doc.new_feature("sketch", "Taslak")
	s.plane = SketchPlane.standard("top")
	s.sketch = Sketch.new()
	doc.add_feature(s)
	return s


static func _extrude(doc: CadDocument, sk: CadFeature, depth: float, reverse := false) -> void:
	var e := doc.new_feature("extrude", "Ekstrüzyon")
	e.params = {"sketch": sk.id, "depth": depth, "end": "blind", "reverse": reverse, "cut": false}
	doc.add_feature(e)


static func _hexagon(sk: Sketch, s: float) -> void:
	var R := s / sqrt(3.0)
	var ids: Array = []
	for k in 6:
		var a := deg_to_rad(30.0 + 60.0 * k)
		ids.append(sk.add_point(Vector2(cos(a), sin(a)) * R))
	for k in 6:
		sk.add_line(ids[k], ids[(k + 1) % 6])


static func make_doc(spec: Dictionary) -> CadDocument:
	var doc := CadDocument.new()
	doc.load_dict({})
	doc.part_name = designation(spec)
	doc.material = STEEL
	var t := str(spec.get("type", "bolt"))
	var m: Dictionary = METRIC.get(str(spec.get("size", "M8")), METRIC["M8"])
	match t:
		"bolt":
			var head := _sketch(doc)
			_hexagon(head.sketch, float(m["s"]))
			_extrude(doc, head, float(m["k"]))
			var shank := _sketch(doc)
			shank.sketch.add_circle(Sketch.ORIGIN, float(m["d"]) * 0.5)
			_extrude(doc, shank, float(spec.get("length", 30)), true)
		"nut":
			var n := _sketch(doc)
			_hexagon(n.sketch, float(m["s"]))
			n.sketch.add_circle(Sketch.ORIGIN, float(m["d"]) * 0.5)
			_extrude(doc, n, float(m["m"]))
		"washer":
			var w: Array = m["w"]
			var ws := _sketch(doc)
			ws.sketch.add_circle(Sketch.ORIGIN, float(w[1]) * 0.5)
			ws.sketch.add_circle(Sketch.ORIGIN, float(w[0]) * 0.5)
			_extrude(doc, ws, float(w[2]))
		"pin":
			var ps := _sketch(doc)
			ps.sketch.add_circle(Sketch.ORIGIN, float(spec.get("dia", 6)) * 0.5)
			_extrude(doc, ps, float(spec.get("length", 20)))
		"bearing":
			doc.material = STAINLESS
			var b: Array = BEARINGS.get(str(spec.get("size", "6000")), BEARINGS["6000"])
			var d := float(b[0])
			var D := float(b[1])
			var wall := (D - d) * 0.5
			var bs := _sketch(doc)
			# İç bilezik [d, d + 0.7 wall], dış bilezik [D - 0.7 wall, D] (bilyeler gösterilmez)
			bs.sketch.add_circle(Sketch.ORIGIN, D * 0.5)
			bs.sketch.add_circle(Sketch.ORIGIN, D * 0.5 - wall * 0.35)
			bs.sketch.add_circle(Sketch.ORIGIN, d * 0.5 + wall * 0.35)
			bs.sketch.add_circle(Sketch.ORIGIN, d * 0.5)
			_extrude(doc, bs, float(b[2]))
	doc.dirty = false
	return doc


## Panel için ölçü listeleri
static func sizes_for(t: String) -> Array:
	if t == "bearing":
		return BEARINGS.keys()
	if t == "pin":
		return ["2", "3", "4", "5", "6", "8", "10", "12", "16", "20"]
	return METRIC.keys()
