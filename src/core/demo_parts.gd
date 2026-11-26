class_name DemoParts
extends RefCounted
## Örnek parça (tanıtım ve otomatik testler için).
## Delikli taban plakası + silindir + döndürülmüş yaka + kanal + eksenel delik.


static func _sketch(doc: CadDocument, plane: SketchPlane) -> CadFeature:
	var s := doc.new_feature("sketch", "Taslak")
	s.plane = plane
	s.sketch = Sketch.new()
	doc.add_feature(s)
	return s


static func _extrude(doc: CadDocument, sk: CadFeature, depth: float, end := "blind", cut := false) -> CadFeature:
	var e := doc.new_feature("extrude", "Ekstrüzyon-Kesme" if cut else "Ekstrüzyon")
	e.params = {"sketch": sk.id, "depth": depth, "end": end, "reverse": false, "cut": cut}
	doc.add_feature(e)
	return e


static func build_bracket(doc: CadDocument) -> void:
	doc.load_dict({})
	doc.part_name = "OrnekParca"
	# 1) Taban plakası: 80 x 50 x 8, dört delik — tam tanımlı taslak (boyutlar + ilişkiler)
	var s1 := _sketch(doc, SketchPlane.standard("top"))
	var sk := s1.sketch
	var c := [sk.add_point(Vector2(-40, -25)), sk.add_point(Vector2(40, -25)),
		sk.add_point(Vector2(40, 25)), sk.add_point(Vector2(-40, 25))]
	sk.add_rect(c)
	var diag := sk.add_line(c[0], c[2], true)
	sk.add_constraint({"type": "midpoint", "p1": Sketch.ORIGIN, "e1": diag})
	_dim(sk, {"type": "hdistance", "p1": c[3], "p2": c[2]}, 80.0, Vector2(0, 33))
	_dim(sk, {"type": "vdistance", "p1": c[0], "p2": c[3]}, 50.0, Vector2(-49, 0))
	var holes: Array = []
	var hc: Array = []
	for pos in [Vector2(-30, -15), Vector2(30, -15), Vector2(30, 15), Vector2(-30, 15)]:
		var pid := sk.add_point(pos)
		hc.append(pid)
		holes.append(sk.add_circle(pid, 3.5))
	_dim(sk, {"type": "diameter", "e1": holes[0]}, 7.0, Vector2(-36, -6))
	for i in range(1, 4):
		sk.add_constraint({"type": "equal", "e1": holes[0], "e2": holes[i]})
	_dim(sk, {"type": "hdistance", "p1": c[0], "p2": hc[0]}, 10.0, Vector2(-35, -31))
	_dim(sk, {"type": "vdistance", "p1": c[0], "p2": hc[0]}, 10.0, Vector2(-45, -20))
	_dim(sk, {"type": "hdistance", "p1": hc[0], "p2": hc[1]}, 60.0, Vector2(0, -31))
	sk.add_constraint({"type": "horizontal", "p1": hc[0], "p2": hc[1]})
	_dim(sk, {"type": "vdistance", "p1": hc[1], "p2": hc[2]}, 30.0, Vector2(47, 0))
	sk.add_constraint({"type": "vertical", "p1": hc[1], "p2": hc[2]})
	sk.add_constraint({"type": "horizontal", "p1": hc[2], "p2": hc[3]})
	sk.add_constraint({"type": "vertical", "p1": hc[0], "p2": hc[3]})
	_extrude(doc, s1, 8.0)
	# 2) Silindir: plakanın üst yüzeyinde, orijin merkezli Ø28 x 22
	var s2 := _sketch(doc, SketchPlane.from_face(Vector3(0, 8, 0), Vector3.UP))
	var cyl := s2.sketch.add_circle(Sketch.ORIGIN, 14.0)
	_dim(s2.sketch, {"type": "diameter", "e1": cyl}, 28.0, Vector2(18, 14))
	_extrude(doc, s2, 22.0)
	# 3) Yaka: Ön düzlemde profil, dikey eksen etrafında 360°
	var s3 := _sketch(doc, SketchPlane.standard("front"))
	var k3 := s3.sketch
	var q := [k3.add_point(Vector2(14, 24)), k3.add_point(Vector2(19, 24)),
		k3.add_point(Vector2(19, 30)), k3.add_point(Vector2(14, 30))]
	k3.add_rect(q)
	_dim(k3, {"type": "hdistance", "p1": q[3], "p2": q[2]}, 5.0, Vector2(16.5, 34))
	_dim(k3, {"type": "vdistance", "p1": q[1], "p2": q[2]}, 6.0, Vector2(23, 27))
	_dim(k3, {"type": "hdistance", "p1": Sketch.ORIGIN, "p2": q[0]}, 14.0, Vector2(7, 20))
	_dim(k3, {"type": "vdistance", "p1": Sketch.ORIGIN, "p2": q[0]}, 24.0, Vector2(10, 12))
	var r := doc.new_feature("revolve", "Döndürme")
	r.params = {"sketch": s3.id, "angle": 360.0, "axis": "y", "reverse": false, "cut": false}
	doc.add_feature(r)
	# 4) Kanal: plaka üst yüzeyinde yay + çizgilerden oluşan oval, tümünden kesme
	var s4 := _sketch(doc, SketchPlane.from_face(Vector3(0, 8, 0), Vector3.UP))
	var k4 := s4.sketch
	var c_r := k4.add_point(Vector2(8, 19))
	var c_l := k4.add_point(Vector2(-8, 19))
	var p1 := k4.add_point(Vector2(8, 16.5))
	var p2 := k4.add_point(Vector2(8, 21.5))
	var p3 := k4.add_point(Vector2(-8, 21.5))
	var p4 := k4.add_point(Vector2(-8, 16.5))
	k4.add_arc(c_r, p1, p2)
	k4.add_line(p2, p3)
	k4.add_arc(c_l, p3, p4)
	k4.add_line(p4, p1)
	_extrude(doc, s4, 10.0, "through", true)
	# 5) Eksenel delik: silindirin üstünden Ø14, tümünden kesme
	var s5 := _sketch(doc, SketchPlane.from_face(Vector3(0, 30, 0), Vector3.UP))
	var hole := s5.sketch.add_circle(Sketch.ORIGIN, 7.0)
	_dim(s5.sketch, {"type": "diameter", "e1": hole}, 14.0, Vector2(10, 8))
	_extrude(doc, s5, 10.0, "through", true)
	doc.material = "Alüminyum 6061"
	doc.dirty = false


## Faz 3 örneği: köşeleri yuvarlatılmış isim plakası; altıgen, kanal, spline ve metin kesikleri,
## genişlik/yükseklik global değişkenlere bağlı.
static func build_nameplate(doc: CadDocument) -> void:
	doc.load_dict({})
	doc.part_name = "IsimPlakasi"
	doc.variables = [{"name": "genislik", "expr": "100"}, {"name": "yukseklik", "expr": "genislik * 0.6"}, {"name": "kalinlik", "expr": "4"}]
	var s := _sketch(doc, SketchPlane.standard("front"))
	var sk := s.sketch
	var c := [sk.add_point(Vector2(-50, -30)), sk.add_point(Vector2(50, -30)),
		sk.add_point(Vector2(50, 30)), sk.add_point(Vector2(-50, 30))]
	sk.add_rect(c)
	var diag := sk.add_line(c[0], c[2], true)
	sk.add_constraint({"type": "midpoint", "p1": Sketch.ORIGIN, "e1": diag})
	var wd := _dim(sk, {"type": "hdistance", "p1": c[3], "p2": c[2]}, 100.0, Vector2(0, 40))
	sk.get_constraint(wd)["expr"] = "genislik"
	var hd := _dim(sk, {"type": "vdistance", "p1": c[0], "p2": c[3]}, 60.0, Vector2(-60, 0))
	sk.get_constraint(hd)["expr"] = "yukseklik"
	for i in 4:
		SketchOps.fillet(sk, c[i], 8.0)
	SketchOps.add_polygon(sk, sk.add_point(Vector2(-32, -8)), Vector2(-22, -8), 6)
	SketchOps.add_slot(sk, sk.add_point(Vector2(5, -17)), sk.add_point(Vector2(35, -17)), 4.0)
	var sp: Array = []
	for q in [Vector2(28, 2), Vector2(38, 10), Vector2(36, 20), Vector2(26, 14)]:
		sp.append(sk.add_point(q))
	sp.append(sp[0])
	sk.add_spline(sp)
	sk.add_text(sk.add_point(Vector2(-38, 12)), "DIY.CAD", 13.0)
	SketchSolver.solve_sketch(sk)
	var e := _extrude(doc, s, 4.0)
	e.params["depth_expr"] = "kalinlik"
	doc.material = "PLA"
	Equations.apply(doc)
	doc.dirty = false


## Boyut ekler (değer geometriyle uyumlu verilir; çözücü gerekmez).
static func _dim(sk: Sketch, spec: Dictionary, value: float, label: Vector2) -> int:
	var c := SketchSolver.make_dimension(sk, spec, label)
	c["value"] = value
	return sk.add_constraint(c)
