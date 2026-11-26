class_name Cam
extends RefCounted
## 2.5 eksen CAM (Faz 8): taslağın kapalı konturlarından dış / iç kontur ve cep frezeleme takım yolları,
## kademeli derinlik pasoları ve G-kod (ISO, G21 mm). X/Y taslak eksenleri; Z0 parçanın üstü ya da taslak düzlemi.

const OPS := {"outside": "Dış kontur", "inside": "İç kontur (delikler)", "pocket": "Cep"}


static func defaults() -> Dictionary:
	return {"op": "outside", "tool": 6.0, "depth": 5.0, "step": 1.5, "stepover": 45.0, "feed": 600.0, "plunge": 200.0, "rpm": 12000.0, "safe": 5.0, "z0": "top"}


static func _loop_poly(L: Dictionary) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for c in L["curves"]:
		match str(c["t"]):
			"line":
				poly.append(Vector2(float(c["a"][0]), float(c["a"][1])))
			"arc":
				# Üç noktalı yayı yoğunlaştır
				var p0 := Vector2(float(c["p"][0][0]), float(c["p"][0][1]))
				var pm := Vector2(float(c["p"][1][0]), float(c["p"][1][1]))
				var p1 := Vector2(float(c["p"][2][0]), float(c["p"][2][1]))
				var d := 2.0 * (p0.x * (pm.y - p1.y) + pm.x * (p1.y - p0.y) + p1.x * (p0.y - pm.y))
				if absf(d) < 1e-12:
					poly.append(p0)
					continue
				var ux := (p0.length_squared() * (pm.y - p1.y) + pm.length_squared() * (p1.y - p0.y) + p1.length_squared() * (p0.y - pm.y)) / d
				var uy := (p0.length_squared() * (p1.x - pm.x) + pm.length_squared() * (p0.x - p1.x) + p1.length_squared() * (pm.x - p0.x)) / d
				var cc := Vector2(ux, uy)
				var r := cc.distance_to(p0)
				var a0 := (p0 - cc).angle()
				var a1 := (p1 - cc).angle()
				var am := (pm - cc).angle()
				var da := wrapf(a1 - a0, -PI, PI)
				var dm := wrapf(am - a0, -PI, PI)
				if signf(dm) != signf(da) or absf(dm) > absf(da):
					da -= signf(da) * TAU
				var n := maxi(4, int(absf(da) * r / 0.5))
				for k in n:
					var a := a0 + da * k / n
					poly.append(cc + Vector2(cos(a), sin(a)) * r)
			"circle":
				var c2 := Vector2(float(c["c"][0]), float(c["c"][1]))
				var r2 := float(c["r"])
				var n2 := maxi(24, int(TAU * r2 / 0.5))
				for k2 in n2:
					var a2 := TAU * k2 / n2
					poly.append(c2 + Vector2(cos(a2), sin(a2)) * r2)
			_:
				for q in c.get("p", []):
					if q is Array:
						poly.append(Vector2(float(q[0]), float(q[1])))
	return poly


## Takım yolları (2B kapalı çoklu çizgiler, taslak düzleminde). Dönüş: {paths: [PackedVector2Array], error}
static func toolpaths(sk: Sketch, p: Dictionary) -> Dictionary:
	var prof := sk.extract_profiles()
	var loops: Array = prof["loops"]
	if loops.is_empty():
		return {"error": "Taslakta kapalı kontur yok"}
	var r := float(p.get("tool", 6.0)) * 0.5
	var paths: Array = []
	var op := str(p.get("op", "outside"))
	for i in loops.size():
		var L: Dictionary = loops[i]
		var poly := _loop_poly(L)
		if poly.size() < 3:
			continue
		var outer := int(L["depth"]) % 2 == 0
		match op:
			"outside":
				if outer and int(L["depth"]) == 0:
					paths.append_array(Geometry2D.offset_polygon(poly, r, Geometry2D.JOIN_ROUND))
			"inside":
				if not outer:
					paths.append_array(Geometry2D.offset_polygon(poly, -r, Geometry2D.JOIN_ROUND))
			"pocket":
				if not outer:
					continue
				var islands: Array = []
				for j in loops.size():
					if int(loops[j].get("parent", -1)) == i and int(loops[j]["depth"]) % 2 == 1:
						var ip := _loop_poly(loops[j])
						if ip.size() >= 3:
							islands.append_array(Geometry2D.offset_polygon(ip, r, Geometry2D.JOIN_ROUND))
				var step := maxf(0.05, float(p.get("tool", 6.0)) * float(p.get("stepover", 45.0)) / 100.0)
				var off := -r
				var guard := 0
				while guard < 500:
					guard += 1
					var rings := Geometry2D.offset_polygon(poly, off, Geometry2D.JOIN_ROUND)
					if rings.is_empty():
						break
					var any := false
					for ring in rings:
						if Geometry2D.is_polygon_clockwise(ring):
							continue
						var pieces: Array = [ring]
						for isl in islands:
							var nxt: Array = []
							for pc in pieces:
								nxt.append_array(Geometry2D.clip_polygons(pc, isl))
							pieces = nxt
						for pc2 in pieces:
							if not Geometry2D.is_polygon_clockwise(pc2) and pc2.size() >= 3:
								paths.append(pc2)
								any = true
					if not any:
						break
					off -= step
	if paths.is_empty():
		return {"error": "Takım yolu oluşmadı (takım çapı / işlem türü uygun değil)"}
	return {"paths": paths}


static func _f(x: float) -> String:
	return "%.3f" % x


## G-kod ve istatistik: {gcode, length, time_min, passes}
static func gcode(paths: Array, p: Dictionary, name: String) -> Dictionary:
	var depth := absf(float(p.get("depth", 5.0)))
	var stepd := maxf(0.01, absf(float(p.get("step", 1.5))))
	var safe := float(p.get("safe", 5.0))
	var feed := float(p.get("feed", 600.0))
	var plunge := float(p.get("plunge", 200.0))
	var lines: PackedStringArray = []
	lines.append("(DIY.CAD CAM - %s)" % name)
	lines.append("(Takim: D%s  Islem: %s  Derinlik: %s)" % [_f(float(p.get("tool", 6.0))), str(p.get("op", "")), _f(depth)])
	lines.append("(Z0: %s)" % ("parca ustu" if str(p.get("z0", "top")) == "top" else "taslak duzlemi"))
	lines.append("G21 G90 G17 G94")
	lines.append("M3 S%d" % int(p.get("rpm", 12000.0)))
	lines.append("G0 Z%s" % _f(safe))
	var zs: Array = []
	var z := 0.0
	while z > -depth + 1e-9:
		z = maxf(z - stepd, -depth)
		zs.append(z)
	var cut_len := 0.0
	var rapid := 0.0
	var plunge_len := 0.0
	for zz in zs:
		for path in paths:
			var pts: PackedVector2Array = path
			if pts.size() < 2:
				continue
			lines.append("G0 X%s Y%s" % [_f(pts[0].x), _f(pts[0].y)])
			lines.append("G1 Z%s F%d" % [_f(zz), int(plunge)])
			plunge_len += safe - float(zz)
			lines.append("G1 X%s Y%s F%d" % [_f(pts[0].x), _f(pts[0].y), int(feed)])
			for k in range(1, pts.size()):
				lines.append("G1 X%s Y%s" % [_f(pts[k].x), _f(pts[k].y)])
				cut_len += pts[k - 1].distance_to(pts[k])
			lines.append("G1 X%s Y%s" % [_f(pts[0].x), _f(pts[0].y)])
			cut_len += pts[pts.size() - 1].distance_to(pts[0])
			lines.append("G0 Z%s" % _f(safe))
			rapid += safe - float(zz)
	lines.append("M5")
	lines.append("G0 Z%s" % _f(safe + 10.0))
	lines.append("M30")
	var t := cut_len / maxf(feed, 1.0) + plunge_len / maxf(plunge, 1.0)
	return {"gcode": "\n".join(lines) + "\n", "length": cut_len, "time_min": t, "passes": zs.size()}
