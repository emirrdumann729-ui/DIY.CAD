extends SceneTree
## Kısıt çözücü testleri. Çalıştırma:
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/solver_test.gd

var fails := 0
var passes := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		print("  OK   ", label)
	else:
		fails += 1
		print("  FAIL ", label)


func near(a: float, b: float, tol := 1e-4) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	run_all()
	print("")
	print("ÇÖZÜCÜ SONUÇ: %d başarılı, %d başarısız" % [passes, fails])
	quit(1 if fails > 0 else 0)


func rect(sk: Sketch, p0: Vector2, p1: Vector2) -> Array:
	var ids := [sk.add_point(p0), sk.add_point(Vector2(p1.x, p0.y)), sk.add_point(p1), sk.add_point(Vector2(p0.x, p1.y))]
	sk.add_rect(ids)
	return ids


func line_of(sk: Sketch, a: int, b: int) -> int:
	for e in sk.entities:
		if e["type"] == "line" and ((e["a"] == a and e["b"] == b) or (e["a"] == b and e["b"] == a)):
			return e["id"]
	return -1


func add_dim(sk: Sketch, spec: Dictionary, value: float) -> int:
	var c := SketchSolver.make_dimension(sk, spec, Vector2(0, 0))
	c["value"] = value
	return sk.add_constraint(c)


func run_all() -> void:
	print("== Dikdörtgen + boyutlar = tam tanımlı")
	var sk := Sketch.new()
	var r := rect(sk, Vector2(-17, -9), Vector2(23, 12))
	var a0 := SketchSolver.analyze_sketch(sk)
	check(a0["dof"] == 4 and a0["status"] == "under", "H/V'li dikdörtgen DOF=4 (%d)" % a0["dof"])
	add_dim(sk, {"type": "hdistance", "p1": r[0], "p2": r[1]}, 60.0)
	add_dim(sk, {"type": "vdistance", "p1": r[0], "p2": r[3]}, 40.0)
	check(SketchSolver.solve_sketch(sk), "60x40 boyutlarıyla çözüldü")
	var w: float = sk.points[r[1]].x - sk.points[r[0]].x
	var h: float = sk.points[r[3]].y - sk.points[r[0]].y
	check(near(w, 60.0) and near(h, 40.0), "genişlik %.4f, yükseklik %.4f" % [w, h])
	check(near(sk.points[r[2]].x - sk.points[r[3]].x, 60.0), "üst kenar da 60 (yatay ilişkiler korunuyor)")
	add_dim(sk, {"type": "hdistance", "p1": Sketch.ORIGIN, "p2": r[0]}, 30.0)
	add_dim(sk, {"type": "vdistance", "p1": Sketch.ORIGIN, "p2": r[0]}, 20.0)
	check(SketchSolver.solve_sketch(sk), "orijine konumlandırıldı")
	var a1 := SketchSolver.analyze_sketch(sk)
	check(a1["dof"] == 0 and a1["status"] == "full", "tam tanımlı (DOF %d, %s)" % [a1["dof"], a1["status"]])
	check(sk.points[r[0]].is_equal_approx(Vector2(-30, -20)), "sol alt köşe (-30,-20): %s" % sk.points[r[0]])
	var all_full := true
	for e in sk.entities:
		if not a1["entities"][e["id"]]:
			all_full = false
	check(all_full, "tüm öğeler tam tanımlı (siyah)")

	print("== Fazlalık ve çelişki")
	var cid := sk.add_constraint({"type": "horizontal", "e1": line_of(sk, r[0], r[1])})
	check(not SketchSolver.is_independent(sk, cid), "ikinci yatay ilişki gereksiz algılandı")
	sk.remove_constraint(cid)
	var diag := add_dim(sk, {"type": "distance", "p1": r[0], "p2": r[2]}, 10.0)
	var snap := sk.to_dict()
	check(not SketchSolver.solve_sketch(sk), "çelişen köşegen boyutu (10) çözülemez")
	sk = Sketch.from_dict(snap)
	sk.remove_constraint(diag)
	check(SketchSolver.solve_sketch(sk), "çelişen boyut kaldırılınca tekrar çözülüyor")

	print("== Boyut değiştirme")
	for c in sk.constraints:
		if c["type"] == "hdistance" and c["p1"] == r[0]:
			c["value"] = 75.0
	check(SketchSolver.solve_sketch(sk), "genişlik 75 yapıldı")
	check(near(sk.points[r[1]].x - sk.points[r[0]].x, 75.0) and sk.points[r[0]].is_equal_approx(Vector2(-30, -20)), "köşe sabit kaldı, genişlik 75")

	print("== Teğet, eş merkezli, eşit")
	var s2 := Sketch.new()
	var la := s2.add_point(Vector2(-20, 1))
	var lb := s2.add_point(Vector2(20, -1))
	var L := s2.add_line(la, lb)
	var cc := s2.add_point(Vector2(3, 9))
	var C := s2.add_circle(cc, 5.0)
	s2.add_constraint({"type": "horizontal", "e1": L})
	s2.add_constraint({"type": "tangent", "e1": L, "e2": C})
	check(SketchSolver.solve_sketch(s2), "çizgi-daire teğetliği çözüldü")
	var dist := absf(SketchSolver.signed_line_dist(s2, L, s2.points[cc]))
	check(near(dist, float(s2.get_entity(C)["r"])), "merkez-çizgi mesafesi = yarıçap (%.4f)" % dist)
	var c2p := s2.add_point(Vector2(4, 8))
	var C2 := s2.add_circle(c2p, 2.0)
	s2.add_constraint({"type": "concentric", "e1": C, "e2": C2})
	check(SketchSolver.solve_sketch(s2) and s2.points[cc].is_equal_approx(s2.points[c2p]), "eş merkezli")
	s2.add_constraint({"type": "equal", "e1": C, "e2": C2})
	check(SketchSolver.solve_sketch(s2) and near(float(s2.get_entity(C)["r"]), float(s2.get_entity(C2)["r"])), "eşit yarıçap")

	print("== Açı, dik, paralel, orta nokta, simetrik, nokta-eğri")
	var s3 := Sketch.new()
	var o := Sketch.ORIGIN
	var p1 := s3.add_point(Vector2(30, 2))
	var p2 := s3.add_point(Vector2(25, 15))
	var L1 := s3.add_line(o, p1)
	var L2 := s3.add_line(o, p2)
	s3.add_constraint({"type": "horizontal", "e1": L1})
	var ang := SketchSolver.make_dimension(s3, {"type": "angle", "e1": L1, "e2": L2}, Vector2(10, 3))
	ang["value"] = 30.0
	s3.add_constraint(ang)
	check(SketchSolver.solve_sketch(s3), "30° açı çözüldü")
	var u := SketchSolver.line_dir(s3, L1).normalized()
	var v := SketchSolver.line_dir(s3, L2).normalized()
	check(near(rad_to_deg(u.angle_to(v)), 30.0, 1e-3), "açı = %.4f°" % rad_to_deg(u.angle_to(v)))
	var p3 := s3.add_point(Vector2(5, 20))
	var p4 := s3.add_point(Vector2(9, 40))
	var L3 := s3.add_line(p3, p4)
	s3.add_constraint({"type": "perpendicular", "e1": L1, "e2": L3})
	check(SketchSolver.solve_sketch(s3) and absf(SketchSolver.line_dir(s3, L3).normalized().dot(Vector2.RIGHT)) < 1e-6, "dik")
	var m := s3.add_point(Vector2(12, 1))
	var p5 := s3.add_point(Vector2(12, -8))
	s3.add_line(m, p5)
	s3.add_constraint({"type": "midpoint", "p1": m, "e1": L1})
	check(SketchSolver.solve_sketch(s3) and s3.points[m].is_equal_approx(s3.line_midpoint(s3.get_entity(L1))), "orta nokta")
	var q1 := s3.add_point(Vector2(-10, 6))
	var q2 := s3.add_point(Vector2(-12, -9))
	s3.add_line(q1, q2, true)
	s3.add_constraint({"type": "symmetric", "p1": q1, "p2": q2, "e1": L1})
	check(SketchSolver.solve_sketch(s3) and near(s3.points[q1].y, -s3.points[q2].y) and near(s3.points[q1].x, s3.points[q2].x), "simetrik (x ekseni)")
	var cp := s3.add_point(Vector2(-30, -30))
	var Cc := s3.add_circle(cp, 6.0)
	var on := s3.add_point(Vector2(-20, -31))
	s3.add_line(on, s3.add_point(Vector2(-10, -40)))
	s3.add_constraint({"type": "coincident", "p1": on, "e1": Cc})
	check(SketchSolver.solve_sketch(s3) and near(s3.points[on].distance_to(s3.points[cp]), float(s3.get_entity(Cc)["r"])), "nokta daire üzerinde")

	print("== Yay örtük kısıtı ve sabitleme")
	var s4 := Sketch.new()
	var ac := s4.add_point(Vector2(0, 0))
	var aa := s4.add_point(Vector2(10, 0))
	var ab := s4.add_point(Vector2(0, 12))
	var A := s4.add_arc(ac, aa, ab)
	check(SketchSolver.solve_sketch(s4) and near(s4.points[ab].distance_to(s4.points[ac]), s4.points[aa].distance_to(s4.points[ac])), "yay uçları aynı çemberde")
	var rid := s4.add_constraint(SketchSolver.make_dimension(s4, {"type": "radius", "e1": A}, Vector2(5, 5)))
	s4.get_constraint(rid)["value"] = 20.0
	check(SketchSolver.solve_sketch(s4) and near(s4.entity_radius(s4.get_entity(A)), 20.0), "yay yarıçapı 20")
	var fid := s4.add_constraint({"type": "fix", "p1": ac})
	check(SketchSolver.is_independent(s4, fid), "merkez sabitleme bağımsız")
	var before: Vector2 = s4.points[ac]
	s4.points[aa] = Vector2(40, 3)
	check(SketchSolver.solve_sketch(s4, {"points": {aa: 1000.0}}) and s4.points[ac].is_equal_approx(before), "sürüklemede sabit merkez yerinde kaldı")

	print("== Sürükleme ağırlığı")
	var s5 := Sketch.new()
	var e0 := s5.add_point(Vector2(0, 5))
	var e1 := s5.add_point(Vector2(20, 5))
	var LL := s5.add_line(e0, e1)
	s5.add_constraint({"type": "horizontal", "e1": LL})
	s5.points[e1] = Vector2(25, 15)
	check(SketchSolver.solve_sketch(s5, {"points": {e1: 1000.0}}), "yatay çizginin ucu sürüklendi")
	check(near(s5.points[e1].y, 15.0, 0.05) and near(s5.points[e0].y, s5.points[e1].y), "çizgi fareyi takip etti (y≈15)")

	print("== Nokta birleştirme")
	var s6 := Sketch.new()
	var n1 := s6.add_point(Vector2(0, 0.5))
	var n2 := s6.add_point(Vector2(10, 0))
	var n3 := s6.add_point(Vector2(10, 0.2))
	var n4 := s6.add_point(Vector2(20, 5))
	s6.add_line(n1, n2)
	s6.add_line(n3, n4)
	s6.merge_points(n2, n3)
	check(not s6.points.has(n3) and s6.point_users(n2).size() == 2, "iki uç birleşti")
	s6.merge_points(Sketch.ORIGIN, n1)
	check(s6.points.has(Sketch.ORIGIN) and not s6.points.has(n1), "orijinle birleşme orijini korur")

	print("== Serileştirme")
	var back := Sketch.from_dict(sk.to_dict())
	check(back.constraints.size() == sk.constraints.size(), "kısıtlar kaydedildi")
	check(JSON.stringify(back.to_dict()) == JSON.stringify(sk.to_dict()), "kaydet/aç sonrası aynı")
	var json_back := Sketch.from_dict(JSON.parse_string(JSON.stringify(sk.to_dict())))
	check(SketchSolver.analyze_sketch(json_back)["status"] == "full", "JSON'dan açılan taslak hâlâ tam tanımlı")
