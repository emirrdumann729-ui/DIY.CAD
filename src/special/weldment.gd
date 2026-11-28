class_name Weldment
extends RefCounted
## Kaynaklı konstrüksiyon (Faz 8): taslak / 3B taslak çizgileri boyunca standart profillerden yapısal üyeler.
## Köşelerde gönye (miter) veya alın (butt) birleşim, T birleşimlerinde uç üye diğerine göre kırpılır.
## Her üye ayrı gövdedir; kesim listesi profil + boy + kesim açılarına göre gruplanır.

const TYPES := {"shs": "Kare kutu profil", "rhs": "Dikdörtgen kutu profil", "chs": "Boru", "angle": "Köşebent (L)",
	"upn": "U profil (UPN)", "ipe": "I profil (IPE)", "flat": "Lama"}
## Ölçüler: kutu "HxBxt", boru "Dxt", köşebent "axt", lama "Bxt"; UPN/IPE: [h, b, tw, tf]
const SIZES := {
	"shs": ["20x20x2", "30x30x2", "40x40x3", "50x50x3", "60x60x4", "80x80x4", "100x100x5"],
	"rhs": ["40x20x2", "50x30x3", "60x40x3", "80x40x4", "100x50x4", "120x60x5"],
	"chs": ["21.3x2.3", "26.9x2.3", "33.7x2.6", "42.4x2.6", "48.3x2.9", "60.3x3.2", "76.1x3.2", "88.9x3.6"],
	"angle": ["20x3", "30x3", "40x4", "50x5", "60x6", "80x8"],
	"upn": ["50", "65", "80", "100", "120", "140", "160"],
	"ipe": ["80", "100", "120", "140", "160", "180", "200"],
	"flat": ["20x5", "30x5", "40x8", "50x10", "60x10"],
}
const UPN := {"50": [50, 38, 5, 7], "65": [65, 42, 5.5, 7.5], "80": [80, 45, 6, 8], "100": [100, 50, 6, 8.5],
	"120": [120, 55, 7, 9], "140": [140, 60, 7, 10], "160": [160, 65, 7.5, 10.5]}
const IPE := {"80": [80, 46, 3.8, 5.2], "100": [100, 55, 4.1, 5.7], "120": [120, 64, 4.4, 6.3], "140": [140, 73, 4.7, 6.9],
	"160": [160, 82, 5, 7.4], "180": [180, 91, 5.3, 8], "200": [200, 100, 5.6, 8.5]}
const STEEL_DENSITY := 7.85   # g/cm³


static func label(ptype: String, size: String) -> String:
	match ptype:
		"shs":
			return I18n.t("Kare profil %s") % size
		"rhs":
			return I18n.t("Dikdörtgen profil %s") % size
		"chs":
			return I18n.t("Boru Ø%s") % size
		"angle":
			return I18n.t("Köşebent L%s") % size
		"upn":
			return "UPN %s" % size
		"ipe":
			return "IPE %s" % size
		"flat":
			return I18n.t("Lama %s") % size
	return "%s %s" % [ptype, size]


static func _nums(size: String) -> Array:
	var out: Array = []
	for p in size.split("x"):
		out.append(float(p))
	return out


static func _a2(v: Vector2) -> Array:
	return [v.x, v.y]


static func _poly_loop(pts: Array, k: String, depth := 0, parent := -1) -> Dictionary:
	var curves: Array = []
	for i in pts.size():
		curves.append({"t": "line", "a": _a2(pts[i]), "b": _a2(pts[(i + 1) % pts.size()]), "k": "%s%d" % [k, i]})
	return {"depth": depth, "parent": parent, "curves": curves}


static func _rect(w: float, h: float) -> Array:
	return [Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2), Vector2(w / 2, h / 2), Vector2(-w / 2, h / 2)]


## Profil kesiti: {loops (u: genişlik, v: yükseklik, merkez sınır kutusu ortası), w, h, area}
static func profile(ptype: String, size: String) -> Dictionary:
	var n := _nums(size)
	match ptype:
		"shs", "rhs":
			var h: float = n[0]
			var b: float = n[1] if n.size() > 2 else n[0]
			var t: float = n[n.size() - 1]
			return {"loops": [_poly_loop(_rect(b, h), "o"), _poly_loop(_rect(b - 2 * t, h - 2 * t), "i", 1, 0)], "w": b, "h": h, "area": b * h - (b - 2 * t) * (h - 2 * t)}
		"chs":
			var D: float = n[0]
			var t2: float = n[1]
			return {"loops": [{"depth": 0, "parent": -1, "curves": [{"t": "circle", "c": [0, 0], "r": D / 2, "k": "o"}]},
				{"depth": 1, "parent": 0, "curves": [{"t": "circle", "c": [0, 0], "r": D / 2 - t2, "k": "i"}]}],
				"w": D, "h": D, "area": PI * (D * D - (D - 2 * t2) * (D - 2 * t2)) / 4.0}
		"angle":
			var a: float = n[0]
			var t3: float = n[1]
			var pts := [Vector2(0, 0), Vector2(a, 0), Vector2(a, t3), Vector2(t3, t3), Vector2(t3, a), Vector2(0, a)]
			var sh: Array = []
			for q in pts:
				sh.append((q as Vector2) - Vector2(a / 2, a / 2))
			return {"loops": [_poly_loop(sh, "o")], "w": a, "h": a, "area": t3 * (2 * a - t3)}
		"upn", "ipe":
			var d: Array = UPN.get(size, [100, 50, 6, 8.5]) if ptype == "upn" else IPE.get(size, [100, 55, 4.1, 5.7])
			var h2 := float(d[0])
			var b2 := float(d[1])
			var tw := float(d[2])
			var tf := float(d[3])
			var pts2: Array = []
			if ptype == "upn":
				pts2 = [Vector2(0, 0), Vector2(b2, 0), Vector2(b2, tf), Vector2(tw, tf), Vector2(tw, h2 - tf), Vector2(b2, h2 - tf), Vector2(b2, h2), Vector2(0, h2)]
			else:
				var x0 := (b2 - tw) / 2
				pts2 = [Vector2(0, 0), Vector2(b2, 0), Vector2(b2, tf), Vector2(x0 + tw, tf), Vector2(x0 + tw, h2 - tf), Vector2(b2, h2 - tf),
					Vector2(b2, h2), Vector2(0, h2), Vector2(0, h2 - tf), Vector2(x0, h2 - tf), Vector2(x0, tf), Vector2(0, tf)]
			var sh2: Array = []
			for q2 in pts2:
				sh2.append((q2 as Vector2) - Vector2(b2 / 2, h2 / 2))
			return {"loops": [_poly_loop(sh2, "o")], "w": b2, "h": h2, "area": 2 * b2 * tf + (h2 - 2 * tf) * tw}
		"flat":
			var b3: float = n[0]
			var t4: float = n[1]
			return {"loops": [_poly_loop(_rect(b3, t4), "o")], "w": b3, "h": t4, "area": b3 * t4}
	return profile("shs", "40x40x3")


## Üye çizgileri (dünya). [{a, b, pn (taslak düzlemi normali veya sıfır)}]
static func segments(doc: CadDocument, f: CadFeature) -> Array:
	var out: Array = []
	var src := doc.get_feature(int(f.params.get("sketch", 0)))
	if src == null:
		return out
	if src.type == "sketch3d" and src.sketch3d != null:
		for ln in src.sketch3d.lines:
			out.append({"a": src.sketch3d.points[int(ln[0])], "b": src.sketch3d.points[int(ln[1])], "pn": Vector3.ZERO})
	elif src.sketch != null:
		for e in src.sketch.entities:
			if str(e["type"]) == "line" and not bool(e.get("construction", false)):
				out.append({"a": src.plane.to_world(src.sketch.points[int(e["a"])]), "b": src.plane.to_world(src.sketch.points[int(e["b"])]), "pn": src.plane.normal()})
	return out


static func _frame(d: Vector3, pn: Vector3, rot_deg: float) -> Array:
	var v0 := pn
	if v0.length() < 1e-6 or absf(v0.normalized().dot(d)) > 0.99:
		v0 = Vector3.UP if absf(d.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var v := (v0 - d * d.dot(v0)).normalized()
	var u := d.cross(v).normalized()
	if absf(rot_deg) > 1e-9:
		var rb := Basis(d, deg_to_rad(rot_deg))
		u = rb * u
		v = rb * v
	return [u, v]


## Profilin d yönündeki yarı genişliği (üye çerçevesine göre)
static func _half_extent(prof: Dictionary, u: Vector3, v: Vector3, d: Vector3) -> float:
	return absf(d.dot(u)) * float(prof["w"]) * 0.5 + absf(d.dot(v)) * float(prof["h"]) * 0.5


## Üyeler, birleşimler ve kesim listesi bilgisi. Dönüş: {members: [...], cutlist: [...]} veya {error}
static func build(doc: CadDocument, f: CadFeature) -> Dictionary:
	var segs := segments(doc, f)
	if segs.is_empty():
		return {"error": I18n.t("Taslakta çizgi yok (2B taslak veya 3B taslak seçin)")}
	var ptype := str(f.params.get("ptype", "shs"))
	var psize := str(f.params.get("psize", "40x40x3"))
	var prof := profile(ptype, psize)
	var rot := float(f.params.get("rot", 0.0))
	var corner := str(f.params.get("corner", "miter"))
	var tol := 1e-3
	var M: Array = []
	for s in segs:
		var a: Vector3 = s["a"]
		var b: Vector3 = s["b"]
		var L := a.distance_to(b)
		if L < tol:
			continue
		var d := (b - a) / L
		var fr := _frame(d, s["pn"], rot)
		M.append({"a": a, "b": b, "d": d, "L": L, "u": fr[0], "v": fr[1], "ext": [0.0, 0.0], "cuts": [], "trim": [], "ang": [0.0, 0.0], "adj": [0.0, 0.0]})
	var big := sqrt(float(prof["w"]) * float(prof["w"]) + float(prof["h"]) * float(prof["h"]))
	# Köşe birleşimleri: ortak uç noktası
	for i in M.size():
		for ei in 2:
			var P: Vector3 = M[i]["a"] if ei == 0 else M[i]["b"]
			var mates: Array = []
			for j in M.size():
				if j == i:
					continue
				for ej in 2:
					var Q: Vector3 = M[j]["a"] if ej == 0 else M[j]["b"]
					if Q.distance_to(P) < tol:
						mates.append([j, ej])
			if mates.size() == 1:
				var j: int = mates[0][0]
				var ej: int = mates[0][1]
				if j < i:
					continue   # çift bir kez işlenir
				var ai: Vector3 = M[i]["d"] * (1.0 if ei == 0 else -1.0)   # P'den uzağa
				var aj: Vector3 = M[j]["d"] * (1.0 if ej == 0 else -1.0)
				var cosang := ai.dot(aj)
				if cosang < -0.9999:
					continue   # doğrusal: birleşim yok
				var corner_ang := acos(clampf(cosang, -1.0, 1.0))
				if corner == "miter":
					var nb := (ai - aj).normalized()
					M[i]["ext"][ei] = big
					M[j]["ext"][ej] = big
					M[i]["cuts"].append({"o": _v(P), "n": _v(-nb)})
					M[j]["cuts"].append({"o": _v(P), "n": _v(nb)})
					var cut_deg := 90.0 - rad_to_deg(corner_ang) * 0.5
					M[i]["ang"][ei] = cut_deg
					M[j]["ang"][ej] = cut_deg
				else:
					# Alın: i devam eder (dış yüze kadar uzar), j kırpılır
					var hj := _half_extent(prof, M[j]["u"], M[j]["v"], ai)
					var hi := _half_extent(prof, M[i]["u"], M[i]["v"], aj)
					M[i]["ext"][ei] = hj
					M[i]["adj"][ei] = hj
					M[j]["trim"].append(i)
					M[j]["adj"][ej] = -hi
	# Üç veya daha fazla üyenin buluştuğu köşe: en dikey üye sürer (diğerlerinin dış yüzüne kadar uzar),
	# diğerleri ona göre kırpılır
	var done := {}
	for i in M.size():
		for ei in 2:
			var P3: Vector3 = M[i]["a"] if ei == 0 else M[i]["b"]
			var key := "%d,%d,%d" % [roundi(P3.x / tol), roundi(P3.y / tol), roundi(P3.z / tol)]
			if done.has(key):
				continue
			var group: Array = [[i, ei]]
			for j in M.size():
				if j == i:
					continue
				for ej in 2:
					var Q3: Vector3 = M[j]["a"] if ej == 0 else M[j]["b"]
					if Q3.distance_to(P3) < tol:
						group.append([j, ej])
			if group.size() < 3:
				continue
			done[key] = true
			var main: Array = group[0]
			for g in group:
				if absf((M[g[0]]["d"] as Vector3).dot(Vector3.UP)) > absf((M[main[0]]["d"] as Vector3).dot(Vector3.UP)) + 1e-6:
					main = g
			var mi: int = main[0]
			var away_m: Vector3 = M[mi]["d"] * (1.0 if main[1] == 0 else -1.0)
			var ext := 0.0
			for g2 in group:
				if g2[0] == mi:
					continue
				var oj: int = g2[0]
				ext = maxf(ext, _half_extent(prof, M[oj]["u"], M[oj]["v"], away_m))
				var away_o: Vector3 = M[oj]["d"] * (1.0 if g2[1] == 0 else -1.0)
				if not (mi in M[oj]["trim"]):
					M[oj]["trim"].append(mi)
				M[oj]["adj"][g2[1]] = -_half_extent(prof, M[mi]["u"], M[mi]["v"], away_o)
				M[oj]["ext"][g2[1]] = 0.0
				M[oj]["cuts"] = (M[oj]["cuts"] as Array).filter(func(c: Dictionary) -> bool: return Vector3(c["o"][0], c["o"][1], c["o"][2]).distance_to(P3) > tol)
				M[oj]["ang"][g2[1]] = 0.0
			M[mi]["ext"][main[1]] = ext
			M[mi]["adj"][main[1]] = ext
			M[mi]["cuts"] = (M[mi]["cuts"] as Array).filter(func(c: Dictionary) -> bool: return Vector3(c["o"][0], c["o"][1], c["o"][2]).distance_to(P3) > tol)
			M[mi]["ang"][main[1]] = 0.0
	# T birleşimleri: uç diğer üyenin ara noktasında
	for j in M.size():
		for ej in 2:
			var P2: Vector3 = M[j]["a"] if ej == 0 else M[j]["b"]
			for i in M.size():
				if i == j:
					continue
				var a2: Vector3 = M[i]["a"]
				var t := (P2 - a2).dot(M[i]["d"])
				if t <= tol or t >= float(M[i]["L"]) - tol:
					continue
				if (a2 + M[i]["d"] * t).distance_to(P2) < tol:
					if not (i in M[j]["trim"]):
						M[j]["trim"].append(i)
					var away: Vector3 = M[j]["d"] * (1.0 if ej == 0 else -1.0)
					M[j]["adj"][ej] = -_half_extent(prof, M[i]["u"], M[i]["v"], away)
	var members: Array = []
	var env_loops: Array = []
	for L0 in prof["loops"]:
		if int(L0["depth"]) == 0:
			env_loops.append(L0)
	for m in M:
		var ea: float = m["ext"][0]
		var eb: float = m["ext"][1]
		var o: Vector3 = (m["a"] as Vector3) - (m["d"] as Vector3) * ea
		var u: Vector3 = m["u"]
		var v: Vector3 = m["v"]
		var n := u.cross(v).normalized()
		members.append({"plane": {"o": _v(o), "x": _v(u), "y": _v(v), "n": _v(n)}, "loops": prof["loops"], "env": env_loops,
			"vec": _v((m["d"] as Vector3) * (float(m["L"]) + ea + eb)), "cuts": m["cuts"], "trim_by": m["trim"]})
	# Kesim listesi
	var name := label(ptype, psize)
	var groups := {}
	var order: Array = []
	for m2 in M:
		var length: float = float(m2["L"]) + float(m2["adj"][0]) + float(m2["adj"][1])
		var angs := [snappedf(float(m2["ang"][0]), 0.1), snappedf(float(m2["ang"][1]), 0.1)]
		angs.sort()
		var key := "%.1f|%s" % [length, str(angs)]
		if not groups.has(key):
			groups[key] = {"profile": name, "length": length, "angles": angs, "qty": 0}
			order.append(key)
		groups[key]["qty"] += 1
	var cut: Array = []
	var total := 0.0
	for k in order:
		var g: Dictionary = groups[k]
		g["mass"] = float(prof["area"]) * float(g["length"]) * STEEL_DENSITY / 1000.0   # g (mm³·g/cm³ / 1000)
		total += float(g["length"]) * int(g["qty"])
		cut.append(g)
	return {"members": members, "cutlist": cut, "total_length": total, "profile": prof}


static func _v(p: Vector3) -> Array:
	return [p.x, p.y, p.z]


static func payload(doc: CadDocument, f: CadFeature, d: Dictionary) -> bool:
	var r := build(doc, f)
	if r.has("error"):
		f.error = r["error"]
		return false
	d["type"] = "weldment"
	d["members"] = r["members"]
	return true


## Belgedeki tüm yapısal üye özelliklerinin birleşik kesim listesi
static func doc_cutlist(doc: CadDocument) -> Array:
	var out: Array = []
	var by := {}
	for f in doc.features:
		if f.type != "weld" or f.suppressed or doc.is_rolled_back(f):
			continue
		var r := build(doc, f)
		if r.has("error"):
			continue
		for g in r["cutlist"]:
			var key := "%s|%.1f|%s" % [g["profile"], float(g["length"]), str(g["angles"])]
			if by.has(key):
				by[key]["qty"] += int(g["qty"])
			else:
				by[key] = (g as Dictionary).duplicate()
				out.append(by[key])
	return out


static func write_cutlist_csv(path: String, rows: Array) -> Error:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return FileAccess.get_open_error()
	fa.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
	fa.store_line(I18n.t("No;Profil;Boy (mm);Kesim açıları;Adet;Birim kütle (g);Toplam kütle (g)"))
	var i := 1
	for r in rows:
		fa.store_line("%d;%s;%.1f;%s;%d;%.1f;%.1f" % [i, r["profile"], float(r["length"]), "%s° / %s°" % [str(r["angles"][0]), str(r["angles"][1])],
			int(r["qty"]), float(r["mass"]), float(r["mass"]) * int(r["qty"])])
		i += 1
	fa.close()
	return OK
