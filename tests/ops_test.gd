extends SceneTree
## Faz 3 taslak işlemleri testleri. Çalıştırma:
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/ops_test.gd

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
	print("İŞLEM SONUÇ: %d başarılı, %d başarısız" % [passes, fails])
	quit(1 if fails > 0 else 0)


func line(sk: Sketch, a: Vector2, b: Vector2, cons := false) -> int:
	return sk.add_line(sk.add_point(a), sk.add_point(b), cons)


func ends(sk: Sketch, eid: int) -> Array:
	var e := sk.get_entity(eid)
	return [sk.points[e["a"]], sk.points[e["b"]]]


func count_type(sk: Sketch, t: String) -> int:
	var n := 0
	for e in sk.entities:
		if e["type"] == t:
			n += 1
	return n


func rect(sk: Sketch, p0: Vector2, p1: Vector2) -> Array:
	var ids := [sk.add_point(p0), sk.add_point(Vector2(p1.x, p0.y)), sk.add_point(p1), sk.add_point(Vector2(p0.x, p1.y))]
	sk.add_rect(ids)
	return ids


func run_phase3b() -> void:
	print("== Elips")
	var se := Sketch.new()
	var m := se.add_point(Vector2(20, 0))
	var el := se.add_ellipse(Sketch.ORIGIN, m, 10.0)
	var lp: Array = se.extract_profiles()["loops"]
	check(lp.size() == 1 and near(absf(Sketch.polygon_area(lp[0]["poly"])), PI * 200.0, 1.0), "elips kapalı kontur, alan ≈ πab")
	check(int(SketchSolver.analyze_sketch(se)["dof"]) == 3, "orijin merkezli elips: 3 serbestlik")
	var d1 := SketchSolver.make_dimension(se, {"type": "distance", "p1": Sketch.ORIGIN, "p2": m}, Vector2(10, 5))
	d1["value"] = 30.0
	se.add_constraint(d1)
	var d2 := SketchSolver.make_dimension(se, {"type": "radius", "e1": el}, Vector2(0, 15))
	d2["value"] = 12.0
	se.add_constraint(d2)
	se.add_constraint({"type": "horizontal", "p1": Sketch.ORIGIN, "p2": m})
	check(SketchSolver.solve_sketch(se), "elips boyutlarıyla çözüldü")
	var ax := se.ellipse_axes(se.get_entity(el))
	check(near(float(ax["a"]), 30.0) and near(float(ax["b"]), 12.0), "büyük 30, küçük 12")
	check(SketchSolver.analyze_sketch(se)["status"] == "full", "elips tam tanımlı")

	print("== Parabol")
	var sp := Sketch.new()
	var v := sp.add_point(Vector2(0, 0))
	var f := sp.add_point(Vector2(0, 2.5))
	var pa := sp.add_point(Vector2(-10, 10))
	var pb := sp.add_point(Vector2(10, 10))
	sp.add_parabola(v, f, pa, pb)
	sp.add_line(pb, pa)
	var pl: Array = sp.extract_profiles()["loops"]
	check(pl.size() == 1 and near(absf(Sketch.polygon_area(pl[0]["poly"])), 400.0 / 3.0, 0.5), "parabol + çizgi kapalı, alan ≈ 2/3·taban·yükseklik")
	sp.points[pb] = Vector2(12, 10)
	check(SketchSolver.solve_sketch(sp, {"points": {pb: 100000.0}}), "uç sürüklendi")
	var fr := sp.parabola_frame(sp.entities[0])
	var q: Vector2 = (sp.points[pb] as Vector2) - (fr["v"] as Vector2)
	var uu := q.dot(fr["u"])
	var ww := q.dot(fr["w"])
	check(near(ww * ww, 4.0 * float(fr["fl"]) * uu, 1e-3), "uç parabol üzerinde kaldı")
	check(int(SketchSolver.analyze_sketch(sp)["dof"]) == 6, "parabol 6 serbestlik (%d)" % SketchSolver.analyze_sketch(sp)["dof"])

	print("== Bölge seçme")
	var sr := Sketch.new()
	sr.add_circle(sr.add_point(Vector2(-5, 0)), 10.0)
	sr.add_circle(sr.add_point(Vector2(5, 0)), 10.0)
	var fs := SketchRegions.faces(sr)
	check(fs.size() == 3, "kesişen iki daire: 3 bölge (%d)" % fs.size())
	var li := SketchRegions.face_at(fs, Vector2(0, 0))
	var lens := 200.0 * acos(0.5) - 5.0 * sqrt(300.0)
	check(li >= 0 and near(float(fs[li]["net_area"]), lens, 1.5), "mercek bölgesi alanı %.2f ≈ %.2f" % [float(fs[li]["net_area"]) if li >= 0 else 0.0, lens])
	var rl := CsgKernel.region_loops(sr, [[0.0, 0.0]])
	check(rl.size() == 1 and int(rl[0]["region"]) == 0, "örnek noktadan tek bölge konturu")
	var s2 := Sketch.new()
	s2.add_circle(Sketch.ORIGIN, 10.0)
	s2.add_circle(Sketch.ORIGIN, 5.0)
	var f2 := SketchRegions.faces(s2)
	var ring := SketchRegions.face_at(f2, Vector2(7.5, 0))
	check(f2.size() == 2 and ring >= 0 and (f2[ring]["holes"] as Array).size() == 1, "halka: dış + delik, ayrıca iç disk")
	check(near(float(f2[ring]["net_area"]), PI * 75.0, 1.0), "halka alanı π(R²-r²)")
	var s3 := Sketch.new()
	var r3 := rect(s3, Vector2(0, 0), Vector2(20, 10))
	line(s3, Vector2(10, -5), Vector2(10, 15))
	var f3 := SketchRegions.faces(s3)
	check(f3.size() == 2, "çizgiyle bölünen dikdörtgen: 2 bölge (%d)" % f3.size())

	print("== Varlıkları dönüştür")
	var loop := PackedVector2Array()
	for qq in [Vector2(0, 0), Vector2(5, 0), Vector2(10, 0), Vector2(10, 5), Vector2(10, 10), Vector2(0, 10)]:
		loop.append(qq)
	var circ := Sketch.circle_polygon(Vector2(30, 5), 4.0)
	var rr := PackedVector2Array()
	var corner_c := [Vector2(48, 2), Vector2(58, 2), Vector2(58, 8), Vector2(48, 8)]
	var a0 := [PI, -PI * 0.5, 0.0, PI * 0.5]
	for i in 4:
		for k in 33:
			rr.append((corner_c[i] as Vector2) + Vector2.from_angle(float(a0[i]) + PI * 0.5 * k / 32.0) * 2.0)
	var sc := Sketch.new()
	var cr := SketchOps.convert_loops(sc, [loop, circ, rr])
	check(cr["ok"], "dönüştürüldü")
	check(count_type(sc, "circle") == 1 and near(float(sc.entities.filter(func(e): return e["type"] == "circle")[0]["r"]), 4.0, 1e-3), "128-gen daire olarak tanındı")
	check(count_type(sc, "line") == 4 + 4, "kare (eş doğrusal noktalar birleşti) + yuvarlatılmış dikdörtgenin 4 kenarı")
	check(count_type(sc, "arc") == 4, "yuvarlatılmış köşeler yay olarak tanındı")
	check(SketchSolver.analyze_sketch(sc)["status"] == "full", "dönüştürülen öğeler sabitlendi (tam tanımlı)")

	print("== Bloklar")
	var sb := Sketch.new()
	var rb := rect(sb, Vector2(0, 0), Vector2(10, 4))
	var ids: Array = []
	for e in sb.entities:
		ids.append(e["id"])
	var bid := sb.make_block(ids)
	check(bid >= 0 and sb.constraints.is_empty(), "blok oluştu, iç ilişkiler rijitliğe katıldı")
	check(int(SketchSolver.analyze_sketch(sb)["dof"]) == 3, "blok 3 serbestlik (konum + açı)")
	sb.points[rb[2]] = Vector2(15, 12)
	check(SketchSolver.solve_sketch(sb, {"points": {rb[2]: 100000.0}}), "blok köşesi sürüklendi")
	var dd: float = (sb.points[rb[0]] as Vector2).distance_to(sb.points[rb[2]])
	check(near(dd, sqrt(116.0), 1e-3) and (sb.points[rb[2]] as Vector2).distance_to(Vector2(15, 12)) < 0.01, "blok rijit hareket etti (köşegen korunarak)")
	var back := Sketch.from_dict(JSON.parse_string(JSON.stringify(sb.to_dict())))
	check(back.blocks.size() == 1 and int(SketchSolver.analyze_sketch(back)["dof"]) == 3, "blok kaydedilip açıldı")

	print("== Yay uzatma, spline ofseti")
	var sx := Sketch.new()
	var ac := sx.add_arc(Sketch.ORIGIN, sx.add_point(Vector2(10, 0)), sx.add_point(Vector2(0, 10)))
	line(sx, Vector2(-5, -20), Vector2(-5, 20))
	check(SketchOps.extend(sx, ac, Vector2(0.5, 9.5))["ok"], "yay uzatıldı")
	var ae := sx.get_entity(ac)
	check((sx.points[ae["b"]] as Vector2).distance_to(Vector2(-5, sqrt(75.0))) < 1e-3, "yay ucu x=-5 çizgisine ulaştı")
	var so := Sketch.new()
	var spl := so.add_spline([so.add_point(Vector2(0, 0)), so.add_point(Vector2(10, 5)), so.add_point(Vector2(20, 0))])
	var orr := SketchOps.offset(so, [spl], 2.0)
	check(orr["ok"] and count_type(so, "spline") == 2, "spline ofseti oluştu")


func run_all() -> void:
	print("== Kırp")
	var s1 := Sketch.new()
	var h := line(s1, Vector2(-10, 0), Vector2(10, 0))
	var v := line(s1, Vector2(0, -10), Vector2(0, 10))
	check(SketchOps.trim(s1, h, Vector2(5, 0))["ok"], "kesişen çizgiden kırpıldı")
	var hb := ends(s1, h)
	check((hb[0] as Vector2).is_equal_approx(Vector2(-10, 0)) and (hb[1] as Vector2).is_equal_approx(Vector2(0, 0)), "sağ parça silindi: %s" % str(hb))
	var has_coinc := false
	for c in s1.constraints:
		if c["type"] == "coincident" and c["e1"] == v:
			has_coinc = true
	check(has_coinc and SketchSolver.solve_sketch(s1), "kırpılan uç dikey çizgiye çakışık bağlandı")
	var s2 := Sketch.new()
	var h2 := line(s2, Vector2(-10, 0), Vector2(10, 0))
	line(s2, Vector2(-5, -5), Vector2(-5, 5))
	line(s2, Vector2(5, -5), Vector2(5, 5))
	SketchOps.trim(s2, h2, Vector2(0, 0))
	check(count_type(s2, "line") == 4, "ortadan kırpma çizgiyi ikiye böldü")
	var col := false
	for c in s2.constraints:
		if c["type"] == "collinear":
			col = true
	check(col and SketchSolver.solve_sketch(s2), "iki parça doğrusal ilişkisiyle bağlı")
	var s3 := Sketch.new()
	var ci := s3.add_circle(s3.add_point(Vector2.ZERO), 5.0)
	line(s3, Vector2(-10, 0), Vector2(10, 0))
	SketchOps.trim(s3, ci, Vector2(0, 5))
	check(count_type(s3, "circle") == 0 and count_type(s3, "arc") == 1, "daire kırpılınca yay kaldı")
	var arc := {}
	for e in s3.entities:
		if e["type"] == "arc":
			arc = e
	check(not arc.is_empty() and s3.points[arc["a"]].y < 1e-4 and near(float(s3.arc_data(arc)["sweep"]), PI, 1e-4), "alt yarım daire (180°) kaldı")
	var lone := Sketch.new()
	var l1 := line(lone, Vector2(0, 0), Vector2(5, 5))
	SketchOps.trim(lone, l1, Vector2(2, 2))
	check(lone.entities.is_empty(), "kesişimsiz öğe tamamen silindi")

	print("== Uzat")
	var s4 := Sketch.new()
	var e4 := line(s4, Vector2(0, 0), Vector2(5, 0))
	line(s4, Vector2(10, -5), Vector2(10, 5))
	check(SketchOps.extend(s4, e4, Vector2(4.5, 0))["ok"], "uzatıldı")
	check((ends(s4, e4)[1] as Vector2).is_equal_approx(Vector2(10, 0)), "uç x=10 sınırına ulaştı")
	check(SketchSolver.solve_sketch(s4), "uzatma sonrası çözüm tamam")

	print("== Ofset")
	var s5 := Sketch.new()
	var r5 := rect(s5, Vector2(0, 0), Vector2(20, 10))
	var rl: Array = []
	for e in s5.entities:
		rl.append(e["id"])
	var dof0: int = SketchSolver.analyze_sketch(s5)["dof"]
	var off := SketchOps.offset(s5, rl, 2.0)
	check(off["ok"] and (off["ids"] as Array).size() == 4, "dikdörtgen dışa 2 mm ofsetlendi")
	check(SketchSolver.solve_sketch(s5), "ofset çözüldü")
	var bb := Rect2()
	var first := true
	for eid in off["ids"]:
		for q in ends(s5, eid):
			if first:
				bb = Rect2(q, Vector2.ZERO)
				first = false
			else:
				bb = bb.expand(q)
	check(bb.size.is_equal_approx(Vector2(24, 14)) and bb.position.is_equal_approx(Vector2(-2, -2)), "ofset kutusu 24x14: %s" % bb)
	check(int(SketchSolver.analyze_sketch(s5)["dof"]) == dof0, "ofset geometri tam bağlı (DOF değişmedi: %d)" % dof0)
	s5.get_constraint(off["master"])["value"] = 3.0
	SketchSolver.solve_sketch(s5)
	var all3 := true
	for i in 4:
		var ne := s5.get_entity(off["ids"][i])
		for c in s5.constraints:
			if c["type"] in ["offset", "pl_distance"] and int(c.get("e1", -1)) in [off["ids"][i], rl[i]]:
				pass
		# Yeni kenarın her iki ucu, karşılık gelen orijinal kenara 3 mm uzaklıkta olmalı
		var best := INF
		for oid in rl:
			var d1 := absf(SketchSolver.signed_line_dist(s5, oid, s5.points[ne["a"]]))
			var d2 := absf(SketchSolver.signed_line_dist(s5, oid, s5.points[ne["b"]]))
			if absf(d1 - d2) < 1e-4:
				best = minf(best, d1)
		all3 = all3 and near(best, 3.0, 1e-3)
	check(all3, "ana ofset boyutu 3 yapılınca tüm kenarlar izledi")
	var s6 := Sketch.new()
	var c6 := s6.add_circle(Sketch.ORIGIN, 5.0)
	var o6 := SketchOps.offset(s6, [c6], 2.0)
	check(o6["ok"] and SketchSolver.solve_sketch(s6) and near(float(s6.get_entity(o6["ids"][0])["r"]), 7.0), "daire ofseti R7")
	var s6b := Sketch.new()
	var r6 := rect(s6b, Vector2(0, 0), Vector2(20, 10))
	var rl6: Array = []
	for e in s6b.entities:
		rl6.append(e["id"])
	var o6b := SketchOps.offset(s6b, rl6, -2.0)
	check(o6b["ok"] and SketchSolver.solve_sketch(s6b), "içe ofset")
	var pr := s6b.extract_profiles()
	check((pr["loops"] as Array).size() == 2 and int(pr["loops"][1]["depth"]) == 1, "iç ofset delik konturu oluşturdu")

	print("== Aynala")
	var s7 := Sketch.new()
	var ax := line(s7, Vector2(0, -10), Vector2(0, 10), true)
	var m7 := line(s7, Vector2(2, 1), Vector2(5, 4))
	var mr := SketchOps.mirror(s7, [m7, ax], ax)
	check(mr["ok"] and (mr["ids"] as Array).size() == 1, "çizgi aynalandı")
	var me := ends(s7, mr["ids"][0])
	check((me[0] as Vector2).is_equal_approx(Vector2(-2, 1)) and (me[1] as Vector2).is_equal_approx(Vector2(-5, 4)), "ayna görüntüsü doğru: %s" % str(me))
	var nsym := 0
	for c in s7.constraints:
		if c["type"] == "symmetric":
			nsym += 1
	check(nsym == 2, "iki simetrik ilişki eklendi")
	s7.add_constraint({"type": "fix", "e1": ax})
	s7.points[s7.get_entity(m7)["b"]] = Vector2(8, 6)
	check(SketchSolver.solve_sketch(s7, {"points": {s7.get_entity(m7)["b"]: 1000.0}}), "orijinal değişince çözüldü")
	check((s7.points[s7.get_entity(mr["ids"][0])["b"]] as Vector2).distance_to(Vector2(-8, 6)) < 0.01, "ayna kopyası izledi")

	print("== Köşe yuvarlatma ve pah")
	var s8 := Sketch.new()
	var pa := s8.add_point(Vector2(0, 0))
	var pc := s8.add_point(Vector2(10, 0))
	var pb := s8.add_point(Vector2(10, 10))
	s8.add_line(pa, pc)
	s8.add_line(pc, pb)
	var d_before: int = SketchSolver.analyze_sketch(s8)["dof"]
	var fr := SketchOps.fillet(s8, pc, 3.0)
	check(fr["ok"], "köşe yuvarlatıldı")
	check(SketchSolver.solve_sketch(s8), "yuvarlatma çözüldü")
	var fa := s8.get_entity(fr["arc"])
	check(near(s8.entity_radius(fa), 3.0) and near(float(s8.arc_data(fa)["sweep"]), PI * 0.5, 1e-4), "R3, 90° yay")
	check(int(SketchSolver.analyze_sketch(s8)["dof"]) == d_before, "serbestlik derecesi korundu (%d)" % d_before)
	check(s8.virtual_points.has(pc) and s8.points.has(pc), "eski köşe sanal köşe olarak kaldı")
	var s9 := Sketch.new()
	var r9 := rect(s9, Vector2(-20, -10), Vector2(20, 10))
	var diag := s9.add_line(r9[0], r9[2], true)
	s9.add_constraint({"type": "midpoint", "p1": Sketch.ORIGIN, "e1": diag})
	var dw := SketchSolver.make_dimension(s9, {"type": "hdistance", "p1": r9[3], "p2": r9[2]}, Vector2(0, 15))
	s9.add_constraint(dw)
	s9.add_constraint(SketchSolver.make_dimension(s9, {"type": "vdistance", "p1": r9[1], "p2": r9[2]}, Vector2(25, 0)))
	check(SketchSolver.analyze_sketch(s9)["status"] == "full", "tam tanımlı dikdörtgen")
	var f9 := SketchOps.fillet(s9, r9[2], 4.0)
	check(f9["ok"] and SketchSolver.solve_sketch(s9), "köşegenli köşe de yuvarlatıldı (yapı çizgisi yok sayılır)")
	var f9b := SketchOps.fillet(s9, r9[1], 3.0)
	check(f9b["ok"] and SketchSolver.solve_sketch(s9), "ikinci köşe yuvarlatıldı")
	check(SketchSolver.analyze_sketch(s9)["status"] == "full", "yuvarlatmadan sonra hâlâ tam tanımlı (boyutlar sanal köşeye bağlı)")
	dw["value"] = 50.0
	check(SketchSolver.solve_sketch(s9), "genişlik 50 yapıldı")
	check(near(s9.entity_radius(s9.get_entity(f9["arc"])), 4.0), "yay yarıçapı korunarak geometri güncellendi")
	var s10 := Sketch.new()
	var qa := s10.add_point(Vector2(0, 0))
	var qc := s10.add_point(Vector2(10, 0))
	var qb := s10.add_point(Vector2(10, 10))
	s10.add_line(qa, qc)
	s10.add_line(qc, qb)
	var ch := SketchOps.chamfer(s10, qc, 2.0)
	check(ch["ok"] and SketchSolver.solve_sketch(s10), "pah kırıldı")
	var cl := ends(s10, ch["line"])
	check(near((cl[0] as Vector2).distance_to(cl[1]), 2.0 * sqrt(2.0)), "pah çizgisi 2√2")

	print("== Çokgen ve kanal")
	var s11 := Sketch.new()
	var pg := SketchOps.add_polygon(s11, Sketch.ORIGIN, Vector2(10, 0), 6)
	check(pg["ok"] and (pg["ids"] as Array).size() == 6, "altıgen")
	var a11 := SketchSolver.analyze_sketch(s11)
	check(a11["dof"] == 2, "merkezi orijinde altıgen: 2 serbestlik (yarıçap, dönüş) — %d" % a11["dof"])
	check((s11.extract_profiles()["loops"] as Array).size() == 1, "altıgen kapalı kontur")
	var s12 := Sketch.new()
	var sl := SketchOps.add_slot(s12, s12.add_point(Vector2(-10, 0)), s12.add_point(Vector2(10, 0)), 3.0)
	check(sl["ok"] and SketchSolver.solve_sketch(s12), "kanal")
	check(int(SketchSolver.analyze_sketch(s12)["dof"]) == 5, "kanal 5 serbestlik (iki merkez + genişlik)")
	var sp := s12.extract_profiles()
	check((sp["loops"] as Array).size() == 1, "kanal kapalı kontur")
	var area := absf(Sketch.polygon_area(sp["loops"][0]["poly"]))
	check(near(area, 20.0 * 6.0 + PI * 9.0, 0.1), "kanal alanı %.2f" % area)

	print("== Kopyala / çoğalt")
	var s13 := Sketch.new()
	var r13 := rect(s13, Vector2(0, 0), Vector2(4, 2))
	var ids13: Array = []
	for e in s13.entities:
		ids13.append(e["id"])
	SketchOps.linear_pattern(s13, ids13, Vector2(10, 0), 3)
	check(count_type(s13, "line") == 12, "doğrusal çoğaltma 3 kopya")
	var nh := 0
	for c in s13.constraints:
		if c["type"] == "horizontal":
			nh += 1
	check(nh == 6, "iç ilişkiler (yatay) kopyalandı")
	var s14 := Sketch.new()
	var c14 := s14.add_circle(s14.add_point(Vector2(10, 0)), 1.0)
	SketchOps.circular_pattern(s14, [c14], Vector2.ZERO, 4, 360.0)
	var ok14 := count_type(s14, "circle") == 4
	for e in s14.entities:
		ok14 = ok14 and near((s14.points[e["c"]] as Vector2).length(), 10.0)
	check(ok14, "dairesel çoğaltma: 4 daire çember üzerinde")
	var s15 := Sketch.new()
	var l15 := line(s15, Vector2(1, 0), Vector2(3, 0))
	SketchOps.transform_points(s15, [l15], func(p: Vector2) -> Vector2: return p.rotated(PI * 0.5))
	check((ends(s15, l15)[1] as Vector2).is_equal_approx(Vector2(0, 3)), "döndürme 90°")

	print("== Spline ve metin")
	var s16 := Sketch.new()
	var sp_pts: Array = []
	for q in [Vector2(0, 0), Vector2(5, 4), Vector2(10, 0), Vector2(5, -6)]:
		sp_pts.append(s16.add_point(q))
	var spl := s16.add_spline(sp_pts)
	check(int(s16.extract_profiles()["open"]) == 1, "açık spline kontur değil")
	s16.get_entity(spl)["pts"].append(sp_pts[0])
	check((s16.extract_profiles()["loops"] as Array).size() == 1, "kapanan spline kontur oldu")
	var poly := s16.spline_points(s16.get_entity(spl))
	var passes_all := true
	for pid in sp_pts:
		var hit := false
		for q in poly:
			if (q as Vector2).distance_to(s16.points[pid]) < 1e-4:
				hit = true
		passes_all = passes_all and hit
	check(passes_all, "spline tüm noktalardan geçiyor")
	var s17 := Sketch.new()
	s17.add_text(s17.add_point(Vector2(0, 0)), "DIY", 10.0)
	var tl: Array = s17.extract_profiles()["loops"]
	check(tl.size() >= 4, "metin 'DIY' konturları: %d" % tl.size())
	var tb := s17.bounds()
	check(tb.position.y > -0.5 and tb.end.y > 6.0 and tb.size.x > 15.0, "metin taban çizgisinin üstünde: %s" % tb)

	run_phase3b()

	print("== Denklemler")
	var doc := CadDocument.new()
	var sf := doc.new_feature("sketch", "Taslak")
	sf.plane = SketchPlane.standard("front")
	sf.sketch = Sketch.new()
	var rq := rect(sf.sketch, Vector2(0, 0), Vector2(30, 20))
	doc.add_feature(sf)
	var wd := SketchSolver.make_dimension(sf.sketch, {"type": "hdistance", "p1": rq[0], "p2": rq[1]}, Vector2(15, -5))
	sf.sketch.add_constraint(wd)
	var hd := SketchSolver.make_dimension(sf.sketch, {"type": "vdistance", "p1": rq[0], "p2": rq[3]}, Vector2(-5, 10))
	sf.sketch.add_constraint(hd)
	check(Equations.full_name(wd, sf.name) == "D1@Taslak1" and Equations.full_name(hd, sf.name) == "D2@Taslak1", "boyut adları D1@Taslak1, D2@Taslak1")
	doc.variables = [{"name": "genislik", "expr": "80"}, {"name": "kalınlık", "expr": "genislik / 10"}]
	wd["expr"] = "genislik"
	hd["expr"] = "\"D1@Taslak1\" / 2"
	var ex := doc.new_feature("extrude", "Ekstrüzyon")
	ex.params = {"sketch": sf.id, "depth": 5.0, "end": "blind", "reverse": false, "cut": false, "depth_expr": "kalınlık * 2"}
	doc.add_feature(ex)
	var res := Equations.apply(doc)
	check((res["errors"] as Array).is_empty(), "denklemler hatasız: %s" % str(res["errors"]))
	check(near(float(wd["value"]), 80.0) and near(float(hd["value"]), 40.0), "genişlik 80, yükseklik D1/2 = 40")
	check(near(float(ex.params["depth"]), 16.0), "derinlik = kalınlık*2 = 16 (Türkçe değişken adı)")
	check(near((sf.sketch.points[rq[1]] as Vector2).x - (sf.sketch.points[rq[0]] as Vector2).x, 80.0), "taslak geometrisi güncellendi")
	doc.variables[0]["expr"] = "100"
	Equations.apply(doc)
	check(near(float(hd["value"]), 50.0) and near(float(ex.params["depth"]), 20.0), "değişken 100 olunca zincir güncellendi")
	check(Equations.evaluate("2*(3+4)", {}) == 14.0 and Equations.evaluate("pow(2, 3)", {}) == 8.0, "ifade hesaplama (fonksiyonlar dahil)")
	check(Equations.evaluate("tanimsiz + 1", {}) == null, "tanımsız ad hata verir")
	check(Equations.valid_var_name("kalınlık") and not Equations.valid_var_name("2x"), "değişken adı doğrulama")
	var back := CadDocument.new()
	back.load_dict(doc.to_dict())
	check(back.variables.size() == 2 and str(back.sketches()[0].sketch.constraints[-1].get("expr", "")) != "", "değişkenler ve denklemler kaydediliyor")
