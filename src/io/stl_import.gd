class_name StlImport
extends RefCounted
## STL içe aktarma (ikili / ASCII) ve gövde dönüşümü. OCC sunucusundaki body_xform / xform_point ile aynı kurallar:
## sıra: kademeli büyütme → bölgesel uzatma (özgün koordinatlarda) → eksen bazlı ölçek (merkez etrafında) → öteleme,
## ardından koruma bölgesi düzeltmesi.
## İçe aktarma parametreleri: path, scale (genel), sx / sy / sz, origin [3], move [3],
## stretch {axis: "x"|"y"|"z", a, b (özgün koordinat aralığı), add (son boyda eklenecek mm)} ya da bu sözlüklerin listesi,
## taper {axis, a, b, grow [2] (b'de kesite eklenecek mm, son ölçü), profile [[x, c1, c2, boy1, boy2], ...], shift [2]}:
## kademeli kesit büyütme — bölge boyunca her kesite doğrusal artan mm eklenir (kesit merkezine göre); önce uygulanır.
## protect {axis, a, b, blend, bands [bant1, bant2], soft [2], offset [2] | anchor [3]}: koruma bölgesi — eksen boyunca
## [a, b] aralığında, eksene dik iki eksendeki bantların içi ölçeklenmeden yalnızca ötelenir (bant = [alt, üst] ya da
## [[konum, alt, üst], ...] profil; null = eksenin tamamı; alt/üst null = sınırsız). bant1 korunan katmanı (ör. üst kısım),
## bant2 bu katmanın içindeki şeridi seçer; katman dışında bant2 etkisizdir (orası normal büyür). Bant kenarında soft mm'lik,
## bölge uçlarında blend mm'lik geçişle normal dönüşüme bağlanır.
## Doğrusal olmayan dönüşümde ağ kırılma düzlemlerinden kesilir ve sapan kenarlar bölünür (refine mm, varsayılan 0.05).

const AXES := {"x": 0, "y": 1, "z": 2}


## Üçgen köşeleri (dosya sırası, STL sarımı: dış normal (b-a)x(c-a))
static func read(path: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var data := FileAccess.get_file_as_bytes(path)
	if data.size() >= 84:
		var n := data.decode_u32(80)
		if 84 + n * 50 == data.size():
			out.resize(n * 3)
			for i in n:
				var o := 84 + i * 50 + 12
				for k in 3:
					var q := o + k * 12
					out[i * 3 + k] = Vector3(data.decode_float(q), data.decode_float(q + 4), data.decode_float(q + 8))
			return out
	var txt := data.get_string_from_ascii()
	for line in txt.split("\n"):
		var t := line.strip_edges().split(" ", false)
		if t.size() == 4 and t[0].to_lower() == "vertex":
			out.append(Vector3(float(t[1]), float(t[2]), float(t[3])))
	out.resize(out.size() - out.size() % 3)
	return out


static func is_stl(path: String) -> bool:
	return path.get_extension().to_lower() == "stl"


## Dönüşüm parametreleri: {s, o, t, st: [[eksen, a, b, oran], ...], tp: kademeli, pr: koruma, error}
static func xform_of(p: Dictionary) -> Dictionary:
	var sc := float(p.get("scale", 1.0))
	var s := Vector3(float(p.get("sx", 1.0)), float(p.get("sy", 1.0)), float(p.get("sz", 1.0))) * sc
	var o := _v3(p.get("origin", null))
	var t := _v3(p.get("move", null))
	var x := {"s": s, "o": o, "t": t, "st": [], "tp": {}, "pr": {}, "error": ""}
	var st: Variant = p.get("stretch", {})
	var regs: Array = st if st is Array else [st]
	var sl: Array = []
	for r: Variant in regs:
		if not (r is Dictionary) or absf(float((r as Dictionary).get("add", 0.0))) <= 1e-12:
			continue
		var ax: int = AXES.get(str(r.get("axis", "x")), 0)
		var a := float(r.get("a", 0.0))
		var b := float(r.get("b", 0.0))
		if b - a <= 1e-9:
			x["error"] = "Uzatma bölgesi geçersiz (bitiş > başlangıç olmalı)"
			return x
		sl.append([ax, a, b, 1.0 + float(r["add"]) / s[ax] / (b - a)])
	x["st"] = sl
	var tp: Variant = p.get("taper", {})
	if tp is Dictionary and (tp.get("profile", []) as Array).size() >= 2:
		var tax: int = AXES.get(str(tp.get("axis", "x")), 0)
		var ta := float(tp.get("a", 0.0))
		var tb := float(tp.get("b", 0.0))
		if tb - ta <= 1e-9:
			x["error"] = "Kademeli büyütme bölgesi geçersiz (bitiş > başlangıç olmalı)"
			return x
		var k1 := (tax + 1) % 3
		var k2 := (tax + 2) % 3
		var g: Array = tp.get("grow", [0.0, 0.0])
		var sh: Array = tp.get("shift", [0.0, 0.0])
		var prof: Array = (tp["profile"] as Array).duplicate()
		prof.sort_custom(func(r1, r2): return float(r1[0]) < float(r2[0]))
		var xs := PackedFloat64Array()
		for r in prof:
			xs.append(float(r[0]))
		x["tp"] = {"ax": tax, "a": ta, "b": tb, "g1": float(g[0]) / s[k1], "g2": float(g[1]) / s[k2],
			"sh1": float(sh[0]), "sh2": float(sh[1]), "prof": prof, "xs": xs}
	var pr: Variant = p.get("protect", {})
	if pr is Dictionary and not (pr as Dictionary).is_empty():
		var err := _protect_of(pr, x)
		if err != "":
			x["error"] = err
	return x


## Koruma bölgesi ayrıştırma (OCC sunucusundaki _protect_of ile aynı kurallar)
static func _protect_of(pr: Dictionary, x: Dictionary) -> String:
	var pax: int = AXES.get(str(pr.get("axis", "x")), 0)
	var pa := float(pr.get("a", 0.0))
	var pb := float(pr.get("b", 0.0))
	if pb - pa <= 1e-9:
		return "Koruma bölgesi geçersiz (bitiş > başlangıç olmalı)"
	var raw: Array = pr["bands"] if pr.get("bands") is Array else []
	var bands: Array = []
	for j in 2:
		var bd: Variant = raw[j] if j < raw.size() else null
		if not (bd is Array) or (bd as Array).is_empty():
			bands.append(null)
			continue
		var src_rows: Array = bd if bd[0] is Array else [[pa, bd[0], bd[1]]]
		var rows: Array = []
		for r: Array in src_rows:
			var lo := -INF if typeof(r[1]) == TYPE_NIL else float(r[1])
			var hi := INF if typeof(r[2]) == TYPE_NIL else float(r[2])
			if hi < lo:
				return "Koruma bandı geçersiz (üst sınır alttan küçük)"
			rows.append([float(r[0]), lo, hi])
		rows.sort_custom(func(r1, r2): return float(r1[0]) < float(r2[0]))
		bands.append(rows)
	var sf: Array = pr["soft"] if pr.get("soft") is Array else []
	var soft := [maxf(float(sf[0]) if sf.size() > 0 else 3.0, 1e-6), maxf(float(sf[1]) if sf.size() > 1 else 3.0, 1e-6)]
	var prd := {"ax": pax, "a": pa, "b": pb, "bl": maxf(float(pr.get("blend", 10.0)), 0.0), "bands": bands, "soft": soft, "off": [0.0, 0.0]}
	var k1 := (pax + 1) % 3
	var k2 := (pax + 2) % 3
	if pr.get("offset") is Array and (pr["offset"] as Array).size() >= 2:
		prd["off"] = [float(pr["offset"][0]), float(pr["offset"][1])]
	else:
		var anc := Vector3.ZERO
		if pr.get("anchor") is Array:
			anc = _v3(pr["anchor"])
		else:
			var o: Vector3 = x["o"]
			anc[pax] = 0.5 * (pa + pb)
			for j2 in 2:
				var k := k1 if j2 == 0 else k2
				if bands[j2] == null:
					anc[k] = o[k]
				else:
					var lh := _band_at(bands[j2], anc[pax])
					if is_finite(lh.x) and is_finite(lh.y):
						anc[k] = 0.5 * (lh.x + lh.y)
					elif is_finite(lh.x):
						anc[k] = lh.x
					elif is_finite(lh.y):
						anc[k] = lh.y
					else:
						anc[k] = o[k]
		var q := _regular_point(anc, x)
		prd["off"] = [q[k1] - anc[k1], q[k2] - anc[k2]]
	x["pr"] = prd
	return ""


## Koruma bandı [alt, üst] (eksen konumuna göre doğrusal profil, uçlarda sabit)
static func _band_at(rows: Array, u: float) -> Vector2:
	var r0: Array = rows[0]
	if rows.size() == 1 or u <= float(r0[0]):
		return Vector2(r0[1], r0[2])
	var rl: Array = rows[rows.size() - 1]
	if u >= float(rl[0]):
		return Vector2(rl[1], rl[2])
	for i in range(1, rows.size()):
		var r1: Array = rows[i]
		if u <= float(r1[0]):
			var ra: Array = rows[i - 1]
			var w := (u - float(ra[0])) / maxf(float(r1[0]) - float(ra[0]), 1e-12)
			return Vector2(_lerp_inf(ra[1], r1[1], w), _lerp_inf(ra[2], r1[2], w))
	return Vector2(rl[1], rl[2])


## Doğrusal ara değer; sınırsız (±INF) uçlarda NaN üretmez
static func _lerp_inf(a: float, b: float, w: float) -> float:
	if a == b:
		return a
	if not (is_finite(a) and is_finite(b)):
		return a if w < 0.5 else b
	return lerpf(a, b, w)


static func _taper_point(p: Vector3, tp: Dictionary) -> Vector3:
	var ax: int = tp["ax"]
	var u := p[ax]
	var t := clampf((u - float(tp["a"])) / (float(tp["b"]) - float(tp["a"])), 0.0, 1.0)
	if t <= 0.0:
		return p
	var xs: PackedFloat64Array = tp["xs"]
	var prof: Array = tp["prof"]
	var i := xs.bsearch(u)
	var r: Array
	if i <= 0:
		r = prof[0]
	elif i >= xs.size():
		r = prof[prof.size() - 1]
	else:
		var r0: Array = prof[i - 1]
		var r1: Array = prof[i]
		var w := (u - float(r0[0])) / maxf(float(r1[0]) - float(r0[0]), 1e-12)
		r = []
		for j in 5:
			r.append(float(r0[j]) + (float(r1[j]) - float(r0[j])) * w)
	var k1 := (ax + 1) % 3
	var k2 := (ax + 2) % 3
	var c1 := float(r[1]) - float(tp["sh1"])
	var c2 := float(r[2]) - float(tp["sh2"])
	p[k1] = c1 + (p[k1] - c1) * (1.0 + float(tp["g1"]) * t / maxf(float(r[3]), 1e-6))
	p[k2] = c2 + (p[k2] - c2) * (1.0 + float(tp["g2"]) * t / maxf(float(r[4]), 1e-6))
	return p


static func _v3(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


## Normal dönüşüm: kademeli büyütme → bölgesel uzatma → ölçek → öteleme
static func _regular_point(p: Vector3, x: Dictionary) -> Vector3:
	if not (x.get("tp", {}) as Dictionary).is_empty():
		p = _taper_point(p, x["tp"])
	var sl: Array = x.get("st", [])
	if not sl.is_empty():
		var d := Vector3.ZERO
		for r: Array in sl:
			var ax: int = r[0]
			var u := p[ax]
			if u > float(r[2]):
				d[ax] += (float(r[2]) - float(r[1])) * (float(r[3]) - 1.0)
			elif u > float(r[1]):
				d[ax] += (u - float(r[1])) * (float(r[3]) - 1.0)
		p += d
	var o: Vector3 = x["o"]
	return o + (x["s"] as Vector3) * (p - o) + (x["t"] as Vector3)


static func xform_point(p: Vector3, x: Dictionary) -> Vector3:
	var q := _regular_point(p, x)
	var pr: Dictionary = x.get("pr", {})
	if pr.is_empty():
		return q
	var ax: int = pr["ax"]
	var a: float = pr["a"]
	var b: float = pr["b"]
	var bl: float = pr["bl"]
	var u := p[ax]
	var w := 1.0
	if u < a or u > b:
		w = maxf(0.0, 1.0 - (a - u if u < a else u - b) / bl) if bl > 0.0 else 0.0
	if w <= 0.0:
		return q
	w = w * w * (3.0 - 2.0 * w)
	var out := q
	var bands: Array = pr["bands"]
	var wl := 1.0      # katman ağırlığı (bant1): içinde 1, geçişinde doğrusal azalır, dışında 0
	for j in 2:
		var k := (ax + 1 + j) % 3
		var lo := -INF
		var hi := INF
		if bands[j] != null:
			var lh := _band_at(bands[j], u)
			lo = lh.x
			hi = lh.y
		var m: float = pr["soft"][j]
		var off: float = pr["off"][j]
		var c := p[k]
		var v: float
		var inside := c >= lo and c <= hi
		var outside := (c < lo and c <= lo - m) or (c > hi and c >= hi + m)
		if inside:
			v = c + off
		elif outside:
			v = q[k]
		else:
			var e := lo - m if c < lo else hi + m
			var pe := p
			pe[k] = e
			var r := _regular_point(pe, x)[k]
			var edge := lo if c < lo else hi
			v = r + (edge + off - r) * (c - e) / (edge - e)
		if j == 0:
			if inside:
				wl = 1.0
			elif outside:
				wl = 0.0
			else:
				wl = (c - (lo - m)) / m if c < lo else (hi + m - c) / m
		else:
			v = q[k] + (v - q[k]) * wl      # şerit yalnızca katmanın içinde etkili
		out[k] = q[k] + (v - q[k]) * w
	return out


## Dönüşümün kırılma düzlemleri [k, bağlı eksen | -1, alfa, beta]: p[k] = alfa + beta * p[bağlı eksen]
static func kink_planes(x: Dictionary) -> Array:
	var pl := {}
	for r: Array in x.get("st", []):
		pl[[int(r[0]), -1, float(r[1]), 0.0]] = true
		pl[[int(r[0]), -1, float(r[2]), 0.0]] = true
	var tp: Dictionary = x.get("tp", {})
	if not tp.is_empty():
		var tax: int = tp["ax"]
		pl[[tax, -1, float(tp["a"]), 0.0]] = true
		pl[[tax, -1, float(tp["b"]), 0.0]] = true
		for r2: Array in tp["prof"]:
			if float(r2[0]) > float(tp["a"]) and float(r2[0]) < float(tp["b"]):
				pl[[tax, -1, float(r2[0]), 0.0]] = true
	var pr: Dictionary = x.get("pr", {})
	if not pr.is_empty():
		var ax: int = pr["ax"]
		var a: float = pr["a"]
		var b: float = pr["b"]
		var bl: float = pr["bl"]
		for u in [a - bl, a, b, b + bl]:
			pl[[ax, -1, float(u), 0.0]] = true
		var bands: Array = pr["bands"]
		for j in 2:
			if bands[j] == null:
				continue
			var k := (ax + 1 + j) % 3
			var rows: Array = bands[j]
			var segs: Array = [[rows[0], rows[0]]]
			for i in range(1, rows.size()):
				segs.append([rows[i - 1], rows[i]])
			segs.append([rows[rows.size() - 1], rows[rows.size() - 1]])
			var m: float = pr["soft"][j]
			for sg: Array in segs:
				var r0: Array = sg[0]
				var r1: Array = sg[1]
				if float(r0[0]) > a - bl and float(r0[0]) < b + bl:
					pl[[ax, -1, float(r0[0]), 0.0]] = true
				for cd in [[1, 0.0], [1, -m], [2, 0.0], [2, m]]:
					var v0: float = float(r0[cd[0]]) + float(cd[1])
					var v1: float = float(r1[cd[0]]) + float(cd[1])
					if not (is_finite(v0) and is_finite(v1)):
						continue
					var du := float(r1[0]) - float(r0[0])
					var be := (v1 - v0) / du if du > 1e-9 else 0.0
					pl[[k, ax if absf(be) > 1e-12 else -1, snappedf(v0 - be * float(r0[0]), 1e-9), snappedf(be, 1e-12)]] = true
	return pl.keys()


## Üçgen ağını düzlemlerle keser (kenar kesişimi kenara göre bir kez hesaplanır → ağ kapalı kalır).
## Düzleme snap'ten yakın köşeler düzleme oturtulur. Dönüş: [köşeler, üçgen indisleri]
static func _cut_planes(verts: PackedVector3Array, tri: PackedInt32Array, planes: Array, snap := 0.01) -> Array:
	for pl: Array in planes:
		var k: int = pl[0]
		var ax: int = pl[1]
		var al: float = pl[2]
		var be: float = pl[3]
		var d := PackedFloat64Array()
		d.resize(verts.size())
		for i in verts.size():
			var v := verts[i]
			var dv: float = v[k] - al - (be * v[ax] if ax >= 0 else 0.0)
			if dv != 0.0 and absf(dv) < snap:
				v[k] -= dv
				verts[i] = v
				dv = 0.0
			d[i] = dv
		var emap := {}
		var nt := PackedInt32Array()
		for ti in range(0, tri.size(), 3):
			var t3 := [tri[ti], tri[ti + 1], tri[ti + 2]]
			var da := d[t3[0]]
			var db := d[t3[1]]
			var dc := d[t3[2]]
			if minf(da, minf(db, dc)) >= 0.0 or maxf(da, maxf(db, dc)) <= 0.0:
				nt.append(t3[0])
				nt.append(t3[1])
				nt.append(t3[2])
				continue
			var pos: Array = []
			var neg: Array = []
			for e in 3:
				var i: int = t3[e]
				var j: int = t3[(e + 1) % 3]
				var di := d[i]
				var dj := d[j]
				if di >= 0.0:
					pos.append(i)
				if di <= 0.0:
					neg.append(i)
				if (di > 0.0 and dj < 0.0) or (di < 0.0 and dj > 0.0):
					var i0 := mini(i, j)
					var i1 := maxi(i, j)
					var key := (i0 << 32) | i1
					var mi: int = emap.get(key, -1)
					if mi < 0:
						verts.append(verts[i0].lerp(verts[i1], d[i0] / (d[i0] - d[i1])))
						d.append(0.0)
						mi = verts.size() - 1
						emap[key] = mi
					pos.append(mi)
					neg.append(mi)
			for poly: Array in [pos, neg]:
				for q in range(1, poly.size() - 1):
					nt.append(poly[0])
					nt.append(poly[q])
					nt.append(poly[q + 1])
		tri = nt
	return [verts, tri]


## Dönüştürülmüş üçgenler (STL sarımı korunur; aynalamada sarım düzeltilir). Doğrusal olmayan dönüşümde ağ önce
## kırılma düzlemlerinden kesilir, sonra dönüşümün doğrusal kalmadığı kenarlar bölünür (refine mm, 0 = kapalı).
static func transformed(tris: PackedVector3Array, p: Dictionary) -> PackedVector3Array:
	var x := xform_of(p)
	var s: Vector3 = x["s"]
	var flip := s.x * s.y * s.z < 0.0
	var out := PackedVector3Array()
	var nonlin := not (x["st"] as Array).is_empty() or not (x["tp"] as Dictionary).is_empty() or not (x["pr"] as Dictionary).is_empty()
	if not nonlin:
		out.resize(tris.size())
		for i in range(0, tris.size() - 2, 3):
			var a := xform_point(tris[i], x)
			var b := xform_point(tris[i + 1], x)
			var c := xform_point(tris[i + 2], x)
			out[i] = a
			out[i + 1] = c if flip else b
			out[i + 2] = b if flip else c
		return out
	var verts := PackedVector3Array()
	var tri := PackedInt32Array()
	var idx := {}
	for i in range(0, tris.size() - 2, 3):
		var ids := [0, 0, 0]
		for k in 3:
			var v := tris[i + k]
			var id: int = idx.get(v, -1)
			if id < 0:
				id = verts.size()
				idx[v] = id
				verts.append(v)
			ids[k] = id
		if ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2]:
			tri.append(ids[0])
			tri.append(ids[1])
			tri.append(ids[2])
	var cut := _cut_planes(verts, tri, kink_planes(x))
	verts = cut[0]
	tri = cut[1]
	var img := PackedVector3Array()
	img.resize(verts.size())
	for i in verts.size():
		img[i] = xform_point(verts[i], x)
	var tol := float(p.get("refine", 0.05))
	if tol > 0.0:
		var min2 := 0.25      # en kısa bölünecek kenar 2 × 0.25 mm
		var tol2 := tol * tol
		for _pass in 12:
			var mark := {}
			var hit_any := false
			for ti in range(0, tri.size(), 3):
				for e in 3:
					var i0 := mini(tri[ti + e], tri[ti + (e + 1) % 3])
					var i1 := maxi(tri[ti + e], tri[ti + (e + 1) % 3])
					var key := (i0 << 32) | i1
					if mark.has(key):
						continue
					var pp := verts[i0]
					var qq := verts[i1]
					if pp.distance_squared_to(qq) < min2:
						mark[key] = -1
						continue
					var ip := img[i0]
					var iq := img[i1]
					var hit := false
					for sfr: float in [0.5, 0.25, 0.75]:
						if xform_point(pp.lerp(qq, sfr), x).distance_squared_to(ip.lerp(iq, sfr)) > tol2:
							hit = true
							break
					if not hit:
						mark[key] = -1
						continue
					var mid := pp.lerp(qq, 0.5)
					verts.append(mid)
					img.append(xform_point(mid, x))
					mark[key] = verts.size() - 1
					hit_any = true
			if not hit_any:
				break
			var nt := PackedInt32Array()
			for ti2 in range(0, tri.size(), 3):
				var a: int = tri[ti2]
				var b: int = tri[ti2 + 1]
				var c: int = tri[ti2 + 2]
				var mab: int = mark[(mini(a, b) << 32) | maxi(a, b)]
				var mbc: int = mark[(mini(b, c) << 32) | maxi(b, c)]
				var mca: int = mark[(mini(c, a) << 32) | maxi(c, a)]
				var n := int(mab >= 0) + int(mbc >= 0) + int(mca >= 0)
				if n == 0:
					nt.append_array([a, b, c])
					continue
				# kanonik konum: bölünen kenar a-b (iki kenarda c-a ve a-b) olacak şekilde döndür
				while mab < 0 or (n == 2 and mca < 0):
					var ta := a
					a = b
					b = c
					c = ta
					var tm := mab
					mab = mbc
					mbc = mca
					mca = tm
				if n == 1:
					nt.append_array([a, mab, c, mab, b, c])
				elif n == 2:
					nt.append_array([a, mab, mca, mab, b, c, mab, c, mca])
				else:
					nt.append_array([a, mab, mca, mab, b, mbc, mca, mbc, c, mab, mbc, mca])
			tri = nt
	out.resize(tri.size())
	for ti3 in range(0, tri.size(), 3):
		out[ti3] = img[tri[ti3]]
		out[ti3 + 1] = img[tri[ti3 + 2]] if flip else img[tri[ti3 + 1]]
		out[ti3 + 2] = img[tri[ti3 + 1]] if flip else img[tri[ti3 + 2]]
	return out


## Godot ağı (ön yüz saat yönünde: STL a,b,c → a,c,b)
static func to_mesh(tris: PackedVector3Array) -> ArrayMesh:
	var v := PackedVector3Array()
	v.resize(tris.size())
	for i in range(0, tris.size() - 2, 3):
		v[i] = tris[i]
		v[i + 1] = tris[i + 2]
		v[i + 2] = tris[i + 1]
	var am := ArrayMesh.new()
	if v.is_empty():
		return am
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


static func bounds(tris: PackedVector3Array) -> AABB:
	if tris.is_empty():
		return AABB()
	var bb := AABB(tris[0], Vector3.ZERO)
	for p in tris:
		bb = bb.expand(p)
	return bb
