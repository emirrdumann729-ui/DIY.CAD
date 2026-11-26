extends SceneTree
## Faz 7 montaj testleri (çekirdek gerektirmez): eşleştirme çözücüsü, serbestlik analizi, sürükleme,
## mekanik eşleştirmeler, montaj dosyası, malzeme listesi, bağlantı elemanı üretimi.
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/assembly_test.gd

var fails := 0
var passes := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		print("  OK   ", label)
	else:
		fails += 1
		print("  FAIL ", label)


func near(a: float, b: float, tol := 1e-3) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	run_basic()
	run_dof()
	run_more()
	run_advanced()
	run_mechanical()
	run_cam()
	run_drag()
	run_file()
	run_toolbox()
	print("")
	print("MONTAJ SONUÇ: %d başarılı, %d başarısız" % [passes, fails])
	quit(1 if fails > 0 else 0)


# Bileşen: 40 x 10 x 20 kutu (X, Y, Z), yerel orijin alt yüz merkezinde. Referans geometrileri elle verilir.
const BOX := {
	"top": {"t": "plane", "p": [0, 10, 0], "n": [0, 1, 0]}, "bottom": {"t": "plane", "p": [0, 0, 0], "n": [0, -1, 0]},
	"left": {"t": "plane", "p": [-20, 5, 0], "n": [-1, 0, 0]}, "right": {"t": "plane", "p": [20, 5, 0], "n": [1, 0, 0]},
	"front": {"t": "plane", "p": [0, 5, 10], "n": [0, 0, 1]}, "back": {"t": "plane", "p": [0, 5, -10], "n": [0, 0, -1]},
	"hole": {"t": "cyl", "p": [0, 0, 0], "d": [0, 1, 0], "r": 4.0}, "pin": {"t": "cyl", "p": [0, 0, 0], "d": [0, 1, 0], "r": 4.0},
}


func ref(comp: int, face: String) -> Dictionary:
	return {"comp": comp, "kind": "face", "name": face, "fid": -1, "geo": (BOX[face] as Dictionary).duplicate(true)}


func geo_of(r: Dictionary) -> Dictionary:
	return r["geo"]


func info_of(asm: CadAssembly) -> Dictionary:
	var out := {}
	for c in asm.comps:
		out[int(c["id"])] = {"center": Vector3(0, 5, 0), "size": 45.0}
	return out


func solve(asm: CadAssembly, opts := {}) -> Dictionary:
	return MateSolver.solve(asm, geo_of, info_of(asm), opts)


func two_boxes() -> CadAssembly:
	var asm := CadAssembly.new()
	asm.add_component({"path": "a.dcad"}, Transform3D.IDENTITY, "A")
	var xf := Transform3D(Basis(Vector3(0.3, 1, 0.2).normalized(), 0.7), Vector3(13, 27, -9))
	asm.add_component({"path": "b.dcad"}, xf, "B")
	return asm


func wgeo(asm: CadAssembly, comp: int, face: String) -> Dictionary:
	return MateSolver.to_world(BOX[face], asm.get_comp(comp)["xf"])


func run_basic() -> void:
	print("== Standart eşleştirmeler")
	var asm := two_boxes()
	check(bool(asm.comps[0]["fixed"]) and not bool(asm.comps[1]["fixed"]), "ilk bileşen sabit, ikincisi serbest")
	var a := int(asm.comps[0]["id"])
	var b := int(asm.comps[1]["id"])
	asm.add_mate("coincident", [ref(a, "top"), ref(b, "bottom")])
	var r := solve(asm)
	var wb := wgeo(asm, b, "bottom")
	check(bool(r["ok"]) and near(wb["p"].y, 10.0) and (wb["n"] as Vector3).is_equal_approx(Vector3(0, -1, 0)), "çakışık düzlemler: B'nin alt yüzü A'nın üstünde (it %d, artık %s)" % [r["iters"], str(r["residual"])])
	check(int(r["dof"][b]) == 3 and int(r["dof"][a]) == 0, "çakışık düzlem sonrası 3 serbestlik (%d)" % int(r["dof"][b]))
	asm.add_mate("coincident", [ref(a, "right"), ref(b, "right")], {"align": "aligned"})
	asm.add_mate("coincident", [ref(a, "front"), ref(b, "front")], {"align": "aligned"})
	r = solve(asm)
	var xf: Transform3D = asm.get_comp(b)["xf"]
	check(bool(r["ok"]) and xf.origin.distance_to(Vector3(0, 10, 0)) < 1e-3 and (xf.basis.x - Vector3.RIGHT).length() + (xf.basis.y - Vector3.UP).length() < 1e-4, "üç çakışık: B tam üstte hizalı %s" % str(xf.origin))
	check(int(r["dof"][b]) == 0, "tam tanımlı (0 serbestlik)")
	# Çelişkili eşleştirme
	asm.add_mate("distance", [ref(a, "right"), ref(b, "right")], {"value": 5.0, "align": "aligned"})
	r = solve(asm)
	check(not bool(r["ok"]) and not (r["bad"] as Array).is_empty(), "çelişkili eşleştirme algılandı (%d hatalı)" % (r["bad"] as Array).size())


func run_dof() -> void:
	print("== Eş merkezli, serbestlik")
	var asm := two_boxes()
	var a := int(asm.comps[0]["id"])
	var b := int(asm.comps[1]["id"])
	asm.add_mate("concentric", [ref(a, "hole"), ref(b, "pin")])
	var r := solve(asm)
	var wp := wgeo(asm, b, "pin")
	check(bool(r["ok"]) and absf((wp["d"] as Vector3).dot(Vector3.UP)) > 0.9999 and Vector2(wp["p"].x, wp["p"].z).length() < 1e-3, "eş merkezli eksenler")
	check(int(r["dof"][b]) == 2, "eş merkezli: 2 serbestlik (eksen boyunca öteleme + dönme) (%d)" % int(r["dof"][b]))
	asm.add_mate("coincident", [ref(a, "top"), ref(b, "bottom")])
	r = solve(asm)
	check(int(r["dof"][b]) == 1, "eş merkezli + çakışık: 1 serbestlik (dönme) (%d)" % int(r["dof"][b]))


func run_more() -> void:
	print("== Mesafe, açı, paralel, dik, teğet, kilit")
	var asm := two_boxes()
	var a := int(asm.comps[0]["id"])
	var b := int(asm.comps[1]["id"])
	asm.add_mate("distance", [ref(a, "top"), ref(b, "bottom")], {"value": 7.5})
	var r := solve(asm)
	check(bool(r["ok"]) and near(wgeo(asm, b, "bottom")["p"].y, 17.5), "mesafe 7.5: alt yüz y=17.5")
	var asm2 := two_boxes()
	asm2.add_mate("angle", [ref(1, "top"), ref(2, "top")], {"value": 30.0})
	r = solve(asm2)
	var ang := rad_to_deg((wgeo(asm2, 2, "top")["n"] as Vector3).angle_to(Vector3.UP))
	check(bool(r["ok"]) and near(ang, 30.0, 0.01), "açı 30° (%.3f)" % ang)
	var asm3 := two_boxes()
	asm3.add_mate("parallel", [ref(1, "right"), ref(2, "front")])
	asm3.add_mate("perpendicular", [ref(1, "top"), ref(2, "top")])
	r = solve(asm3)
	var n1 := wgeo(asm3, 2, "front")["n"] as Vector3
	var n2 := wgeo(asm3, 2, "top")["n"] as Vector3
	check(bool(r["ok"]) and absf(n1.dot(Vector3.RIGHT)) > 0.9999 and absf(n2.dot(Vector3.UP)) < 1e-4, "paralel + dik")
	var asm4 := two_boxes()
	asm4.add_mate("tangent", [ref(1, "top"), ref(2, "pin")])
	r = solve(asm4)
	var wp := wgeo(asm4, 2, "pin")
	check(bool(r["ok"]) and absf((wp["d"] as Vector3).dot(Vector3.UP)) < 1e-4 and near(absf(wp["p"].y - 10.0), 4.0), "silindir düzleme teğet (eksen düzleme paralel, uzaklık r)")
	var asm5 := two_boxes()
	var rel := (asm5.get_comp(1)["xf"] as Transform3D).affine_inverse() * (asm5.get_comp(2)["xf"] as Transform3D)
	asm5.add_mate("lock", [ref(1, "top"), ref(2, "top")], {"ref_xf": CadAssembly.xf_to_array(rel)})
	asm5.get_comp(1)["fixed"] = false
	asm5.get_comp(2)["fixed"] = true
	asm5.get_comp(2)["xf"] = Transform3D(Basis(Vector3.UP, 0.4), Vector3(50, 0, 0))
	r = solve(asm5)
	var rel2 := (asm5.get_comp(1)["xf"] as Transform3D).affine_inverse() * (asm5.get_comp(2)["xf"] as Transform3D)
	check(bool(r["ok"]) and rel2.origin.is_equal_approx(rel.origin) and rel2.basis.is_equal_approx(rel.basis), "kilit: göreli konum korunur")


func run_advanced() -> void:
	print("== Genişlik, simetrik, sınır")
	var asm := two_boxes()
	asm.add_mate("coincident", [ref(1, "top"), ref(2, "bottom")])
	# B'nin sağ/sol yüzleri A'nın sağ/sol yüzleri arasında ortalansın (genişlik)
	asm.add_mate("width", [ref(2, "left"), ref(2, "right"), ref(1, "left"), ref(1, "right")])
	var r := solve(asm)
	var xb: Transform3D = asm.get_comp(2)["xf"]
	var cx: float = (wgeo(asm, 2, "left")["p"].x + wgeo(asm, 2, "right")["p"].x) * 0.5
	check(bool(r["ok"]) and near(cx, 0.0), "genişlik: B, A'nın genişliğinde ortalandı (%.4f)" % cx)
	var asm2 := CadAssembly.new()
	asm2.add_component({"path": "a"}, Transform3D.IDENTITY, "A")
	asm2.add_component({"path": "b"}, Transform3D(Basis(), Vector3(30, 0, 0)), "B")
	asm2.add_component({"path": "c"}, Transform3D(Basis(Vector3.UP, 0.5), Vector3(-25, 3, 4)), "C")
	var sym := {"comp": 1, "kind": "plane", "name": "right", "geo": {"t": "plane", "p": [0, 0, 0], "n": [1, 0, 0]}}
	asm2.get_comp(2)["fixed"] = true
	asm2.add_mate("symmetric", [ref(2, "right"), ref(3, "left"), sym])
	r = solve(asm2)
	var pr: float = wgeo(asm2, 2, "right")["p"].x
	var pl: float = wgeo(asm2, 3, "left")["p"].x
	check(bool(r["ok"]) and near(pl, -pr), "simetrik: yüzler orta düzleme göre ayna (%.3f / %.3f)" % [pr, pl])
	var asm3 := two_boxes()
	asm3.add_mate("limit_distance", [ref(1, "top"), ref(2, "bottom")], {"min": 2.0, "max": 6.0})
	asm3.get_comp(2)["xf"] = Transform3D(Basis(), Vector3(0, 40, 0))
	r = solve(asm3)
	var y: float = wgeo(asm3, 2, "bottom")["p"].y
	check(bool(r["ok"]) and near(y, 16.0, 1e-2), "mesafe sınırı: aralığın üst sınırına çekildi (y=%.3f)" % y)
	asm3.get_comp(2)["xf"] = Transform3D(Basis(), Vector3(0, 14, 0))
	r = solve(asm3)
	check(near(wgeo(asm3, 2, "bottom")["p"].y, 14.0, 1e-4), "aralık içindeyken bileşen yerinde kalır")


func run_mechanical() -> void:
	print("== Dişli, kremayer, vida, menteşe")
	var asm := CadAssembly.new()
	asm.add_component({"path": "frame"}, Transform3D.IDENTITY, "Gövde")
	asm.add_component({"path": "g1"}, Transform3D.IDENTITY, "Dişli1")
	asm.add_component({"path": "g2"}, Transform3D(Basis(), Vector3(30, 0, 0)), "Dişli2")
	var shaft1 := {"comp": 1, "kind": "axis", "name": "s1", "geo": {"t": "line", "p": [0, 0, 0], "d": [0, 1, 0]}}
	var shaft2 := {"comp": 1, "kind": "axis", "name": "s2", "geo": {"t": "line", "p": [30, 0, 0], "d": [0, 1, 0]}}
	var ax := {"t": "cyl", "p": [0, 0, 0], "d": [0, 1, 0], "r": 10.0}
	var g1 := {"comp": 2, "kind": "face", "name": "h", "geo": ax.duplicate(true)}
	var g2 := {"comp": 3, "kind": "face", "name": "h", "geo": ax.duplicate(true)}
	var base := {"comp": 1, "kind": "plane", "name": "top", "geo": {"t": "plane", "p": [0, 0, 0], "n": [0, 1, 0]}}
	var gb1 := {"comp": 2, "kind": "plane", "name": "top", "geo": {"t": "plane", "p": [0, 0, 0], "n": [0, 1, 0]}}
	var gb2 := {"comp": 3, "kind": "plane", "name": "top", "geo": {"t": "plane", "p": [0, 0, 0], "n": [0, 1, 0]}}
	asm.add_mate("hinge", [shaft1, g1, base, gb1], {"align": "aligned"})
	asm.add_mate("hinge", [shaft2, g2, base, gb2], {"align": "aligned"})
	var r := solve(asm)
	check(bool(r["ok"]) and int(r["dof"][2]) == 1 and int(r["dof"][3]) == 1, "menteşe: her dişli 1 serbestlik (dönme)")
	var ref_xf := {"2": CadAssembly.xf_to_array(asm.get_comp(2)["xf"]), "3": CadAssembly.xf_to_array(asm.get_comp(3)["xf"])}
	asm.add_mate("gear", [g1, g2], {"ratio_a": 10.0, "ratio_b": 20.0, "ref_xf": ref_xf})
	# Dişli 1'i 60° döndür ve sabitle → dişli 2 ters yönde 30° dönmeli
	var x1: Transform3D = asm.get_comp(2)["xf"]
	asm.get_comp(2)["xf"] = Transform3D(Basis(Vector3.UP, deg_to_rad(60.0)) * x1.basis, x1.origin)
	r = solve(asm, {"pinned": [2]})
	var th2 := rad_to_deg(MateSolver.axis_angle(asm.get_comp(3)["xf"], CadAssembly.xf_from_array(ref_xf["3"]), Vector3.UP))
	check(bool(r["ok"]) and near(th2, -30.0, 0.05), "dişli 1:2 — 60° → %.2f°" % th2)
	# Çok tur: 4 adımda toplam 400° (sürekli açı)
	for k in 4:
		var xk: Transform3D = asm.get_comp(2)["xf"]
		asm.get_comp(2)["xf"] = Transform3D(Basis(Vector3.UP, deg_to_rad(85.0)) * xk.basis, xk.origin)
		solve(asm, {"pinned": [2]})
	var m: Dictionary = asm.mates[asm.mates.size() - 1]
	var tb: float = rad_to_deg(float(m["_rt"]["b"][1]))
	check(near(tb, -200.0, 0.2), "dişli: 400° döndürmede sürekli açı korunur (%.1f°)" % tb)
	# Kremayer-pinyon
	var asm2 := CadAssembly.new()
	asm2.add_component({"path": "f"}, Transform3D.IDENTITY, "Gövde")
	asm2.add_component({"path": "p"}, Transform3D.IDENTITY, "Pinyon")
	asm2.add_component({"path": "r"}, Transform3D(Basis(), Vector3(0, -12, 0)), "Kremayer")
	var pin_ax := {"comp": 2, "kind": "face", "name": "p", "geo": {"t": "cyl", "p": [0, 0, 0], "d": [0, 0, 1], "r": 12.0}}
	var rack_line := {"comp": 3, "kind": "edge", "name": "r", "geo": {"t": "line", "p": [0, 0, 0], "e": [100, 0, 0], "d": [1, 0, 0]}}
	var fr_ax := {"comp": 1, "kind": "axis", "name": "z", "geo": {"t": "line", "p": [0, 0, 0], "d": [0, 0, 1]}}
	var fr_rail := {"comp": 1, "kind": "axis", "name": "x", "geo": {"t": "line", "p": [0, -12, 0], "d": [1, 0, 0]}}
	var pz := {"comp": 2, "kind": "plane", "name": "f", "geo": {"t": "plane", "p": [0, 0, 0], "n": [0, 0, 1]}}
	var fz := {"comp": 1, "kind": "plane", "name": "f", "geo": {"t": "plane", "p": [0, 0, 0], "n": [0, 0, 1]}}
	var rz := {"comp": 3, "kind": "plane", "name": "f", "geo": {"t": "plane", "p": [0, 0, 0], "n": [0, 0, 1]}}
	var ry := {"comp": 3, "kind": "plane", "name": "t", "geo": {"t": "plane", "p": [0, 0, 0], "n": [0, 1, 0]}}
	var fy := {"comp": 1, "kind": "plane", "name": "t", "geo": {"t": "plane", "p": [0, -12, 0], "n": [0, 1, 0]}}
	asm2.add_mate("hinge", [fr_ax, pin_ax, fz, pz], {"align": "aligned"})
	asm2.add_mate("coincident", [fy, ry], {"align": "aligned"})
	asm2.add_mate("coincident", [fz, rz], {"align": "aligned"})
	asm2.add_mate("parallel", [fr_rail, rack_line])
	solve(asm2)
	var rx := {"2": CadAssembly.xf_to_array(asm2.get_comp(2)["xf"]), "3": CadAssembly.xf_to_array(asm2.get_comp(3)["xf"])}
	asm2.add_mate("rack", [rack_line, pin_ax], {"value": 12.0, "ref_xf": {"3": rx["3"], "2": rx["2"]}})
	var xp: Transform3D = asm2.get_comp(2)["xf"]
	asm2.get_comp(2)["xf"] = Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(90.0)) * xp.basis, xp.origin)
	r = solve(asm2, {"pinned": [2]})
	var dx: float = (asm2.get_comp(3)["xf"] as Transform3D).origin.x
	check(bool(r["ok"]) and near(absf(dx), 12.0 * PI * 0.5, 0.02), "kremayer: 90° pinyon dönüşü → %.3f mm (π/2 × 12)" % dx)
	# Vida: 2 mm hatve, 360° → 2 mm ilerleme
	var asm3 := CadAssembly.new()
	asm3.add_component({"path": "s"}, Transform3D.IDENTITY, "Mil")
	asm3.add_component({"path": "n"}, Transform3D.IDENTITY, "Somun")
	var sa := {"comp": 1, "kind": "axis", "name": "a", "geo": {"t": "line", "p": [0, 0, 0], "d": [0, 1, 0]}}
	var na := {"comp": 2, "kind": "face", "name": "h", "geo": {"t": "cyl", "p": [0, 0, 0], "d": [0, 1, 0], "r": 4.0}}
	var rs := {"1": CadAssembly.xf_to_array(Transform3D.IDENTITY), "2": CadAssembly.xf_to_array(Transform3D.IDENTITY)}
	asm3.add_mate("screw", [sa, na], {"value": 2.0, "ref_xf": rs})
	# Motor (sürücü) somunu eksen etrafında döndürür; vida eşleştirmesi ilerlemeyi üretir
	var drv := asm3.add_mate("drive", [na], {"value": 0.0, "ref_xf": {"2": rs["2"]}})
	for k in 4:
		drv["value"] = deg_to_rad(90.0 * (k + 1))
		r = solve(asm3)
	var yn: float = (asm3.get_comp(2)["xf"] as Transform3D).origin.y
	check(near(absf(yn), 2.0, 0.01), "vida: tam tur → 2 mm ilerleme (%.4f)" % yn)


func run_cam() -> void:
	print("== Kam")
	var circle: Array = []
	for k in 256:
		var a := TAU * k / 256.0
		circle.append([5.0 + 20.0 * cos(a), 20.0 * sin(a)])
	check(near(MateSolver.signed_dist_poly(Vector2(5, 0), circle), -20.0, 0.01) and near(MateSolver.signed_dist_poly(Vector2(35, 0), circle), 10.0, 0.01), "çokgene işaretli uzaklık (içeride negatif)")
	var asm := CadAssembly.new()
	asm.add_component({"path": "frame"}, Transform3D.IDENTITY, "Gövde")
	asm.add_component({"path": "cam"}, Transform3D.IDENTITY, "Kam")
	asm.add_component({"path": "fol"}, Transform3D(Basis(), Vector3(0, 30, 0)), "İzleyici")
	var fz_ax := {"comp": 1, "kind": "axis", "name": "z", "geo": {"t": "line", "p": [0, 0, 0], "d": [0, 0, 1]}}
	var fz := {"comp": 1, "kind": "plane", "name": "f", "geo": {"t": "plane", "p": [0, 0, 0], "n": [0, 0, 1]}}
	var fx := {"comp": 1, "kind": "plane", "name": "r", "geo": {"t": "plane", "p": [0, 0, 0], "n": [1, 0, 0]}}
	var cam_ax := {"comp": 2, "kind": "axis", "name": "z", "geo": {"t": "line", "p": [0, 0, 0], "d": [0, 0, 1]}}
	var cz := {"comp": 2, "kind": "plane", "name": "f", "geo": {"t": "plane", "p": [0, 0, 0], "n": [0, 0, 1]}}
	var ox := {"comp": 3, "kind": "plane", "name": "r", "geo": {"t": "plane", "p": [0, 0, 0], "n": [1, 0, 0]}}
	var oz := {"comp": 3, "kind": "plane", "name": "f", "geo": {"t": "plane", "p": [0, 0, 0], "n": [0, 0, 1]}}
	var tip := {"comp": 3, "kind": "point", "name": "o", "geo": {"t": "point", "p": [0, 0, 0]}}
	asm.add_mate("hinge", [fz_ax, cam_ax, fz, cz], {"align": "aligned"})
	asm.add_mate("coincident", [fx, ox], {"align": "aligned"})
	asm.add_mate("coincident", [fz, oz], {"align": "aligned"})
	asm.add_mate("cam", [tip, cz], {"frame": {"o": [0, 0, 0], "u": [1, 0, 0], "v": [0, 1, 0], "d": [0, 0, 1]}, "profile": circle})
	var drv := asm.add_mate("drive", [cam_ax], {"value": 0.0, "ref_xf": {"2": CadAssembly.xf_to_array(Transform3D.IDENTITY)}})
	var ok := true
	var worst := 0.0
	for deg in [0.0, 60.0, 135.0, 200.0, 270.0, 330.0]:
		drv["value"] = deg_to_rad(deg)
		var r := solve(asm)
		var th := deg_to_rad(deg)
		var want := 5.0 * sin(th) + sqrt(400.0 - 25.0 * cos(th) * cos(th))
		var y: float = (asm.get_comp(3)["xf"] as Transform3D).origin.y
		worst = maxf(worst, absf(y - want))
		if not bool(r["ok"]) or absf(y - want) > 0.03:
			ok = false
			print("     %.0f°: y=%.4f beklenen %.4f" % [deg, y, want])
	check(ok, "eksantrik kam: izleyici yüksekliği analitik eğriyi izler (en büyük hata %.4f mm)" % worst)
	check(int(solve(asm)["dof"][3]) == 0, "izleyici kamla tam tanımlı")


func run_drag() -> void:
	print("== Sürükleme")
	var asm := two_boxes()
	asm.add_mate("coincident", [ref(1, "top"), ref(2, "bottom")])
	solve(asm)
	var xf: Transform3D = asm.get_comp(2)["xf"]
	var grab := Vector3(0, 5, 0)
	var start: Vector3 = xf * grab
	var target := start + Vector3(25, 30, -10)
	var r := solve(asm, {"drag": {"comp": 2, "local": grab, "target": target}})
	var now: Vector3 = (asm.get_comp(2)["xf"] as Transform3D) * grab
	check(bool(r["ok"]) and near(wgeo(asm, 2, "bottom")["p"].y, 10.0) and near(now.x, target.x, 0.5) and near(now.z, target.z, 0.5), "sürükleme düzlemde kayar, eşleştirme korunur (%s)" % str(now))
	var asm2 := two_boxes()
	var r2 := solve(asm2, {"drag": {"comp": 2, "local": grab, "target": Vector3(100, 0, 0)}})
	var now2: Vector3 = (asm2.get_comp(2)["xf"] as Transform3D) * grab
	check(now2.distance_to(Vector3(100, 0, 0)) < 0.5, "eşleştirmesiz bileşen serbestçe sürüklenir")
	var asm3 := two_boxes()
	var x0: Transform3D = asm3.get_comp(1)["xf"]
	solve(asm3, {"drag": {"comp": 1, "local": grab, "target": Vector3(100, 0, 0)}})
	check((asm3.get_comp(1)["xf"] as Transform3D).is_equal_approx(x0), "sabit bileşen sürüklenmez")


func run_file() -> void:
	print("== Montaj dosyası ve malzeme listesi")
	var tmp := OS.get_user_data_dir().path_join("asm_test")
	DirAccess.make_dir_recursive_absolute(tmp.path_join("parcalar"))
	var asm := CadAssembly.new()
	var pa := tmp.path_join("parcalar/plaka.dcad")
	asm.add_component({"path": pa}, Transform3D.IDENTITY, "Plaka")
	asm.add_component({"toolbox": {"type": "bolt", "size": "M8", "length": 30}}, Transform3D(Basis(), Vector3(10, 0, 0)), "Cıvata")
	asm.add_component({"toolbox": {"type": "bolt", "size": "M8", "length": 30}}, Transform3D(Basis(), Vector3(-10, 0, 0)), "Cıvata")
	asm.add_mate("coincident", [ref(1, "top"), ref(2, "bottom")])
	var bom := asm.bom()
	check(bom.size() == 2 and int(bom[1]["qty"]) == 2, "malzeme listesi: aynı cıvata 2 adet gruplandı")
	check(asm.get_comp(3)["name"] == "Cıvata<2>", "bileşen adları örnek numaralı")
	var path := tmp.path_join("montaj.dasm")
	check(asm.save_to(path) == OK, "montaj kaydedildi")
	var txt := FileAccess.get_file_as_string(path)
	check(txt.contains('"parcalar/plaka.dcad"'), "parça yolu montaja göre göreli saklandı")
	var b := CadAssembly.new()
	check(b.load_from(path) == OK and b.comps.size() == 3 and b.mates.size() == 1, "montaj yüklendi")
	check(b.key_of(b.comps[0]) == "file:" + pa.simplify_path(), "göreli yol yüklenince çözüldü")
	check((b.get_comp(2)["xf"] as Transform3D).origin.is_equal_approx(Vector3(10, 0, 0)), "dönüşüm korunur")
	b.checkpoint()
	b.remove_component(2)
	b.commit()
	check(b.comps.size() == 2 and b.mates.is_empty(), "bileşen silinince eşleştirmeleri de silinir")
	b.undo()
	check(b.comps.size() == 3 and b.mates.size() == 1, "geri al")


func run_toolbox() -> void:
	print("== Bağlantı elemanları")
	var bolt := Toolbox.make_doc({"type": "bolt", "size": "M10", "length": 40})
	check(bolt.part_name == "Cıvata ISO 4017 M10x40" and bolt.features.size() == 4, "cıvata belgesi: baş + gövde (%d özellik)" % bolt.features.size())
	var ext: CadFeature = bolt.features[3]
	check(bool(ext.params["reverse"]) and near(float(ext.params["depth"]), 40.0), "gövde baş altına (−Y) uzanır")
	var nut := Toolbox.make_doc({"type": "nut", "size": "M10"})
	var prof := (nut.features[0] as CadFeature).sketch.extract_profiles()
	check((prof["loops"] as Array).size() == 2, "somun profili: altıgen + delik")
	check(Toolbox.make_doc({"type": "bearing", "size": "6204"}).material.begins_with("Paslanmaz"), "rulman malzemesi")
	check(Toolbox.designation({"type": "washer", "size": "M6"}) == "Pul ISO 7089 M6", "pul adı")
