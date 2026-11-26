class_name Sketch
extends RefCounted
## 2B taslak verisi.
## Noktalar kimlik (id) ile saklanır; varlıklar (çizgi, daire, yay) bu noktalara referans verir.
## Böylece birleşik çizgiler aynı noktayı paylaşır (Faz 2'deki kısıt çözücü için de temel).
##
## Varlık sözlükleri:
##   çizgi : {id, type:"line",   a:pid, b:pid, construction:bool, group:int}
##   daire : {id, type:"circle", c:pid, r:float, construction:bool}
##   yay   : {id, type:"arc",    c:pid, a:pid(başlangıç), b:pid(bitiş), construction:bool}  (saat yönü tersine)
## Gruplar: dikdörtgen gibi bileşik şekiller {type:"rect", pts:[c0,c1,c2,c3]}
##
##   spline: {id, type:"spline", pts:[pid...], construction}  (noktalardan geçen eğri; ilk=son ise kapalı)
##   metin : {id, type:"text", p:pid (taban çizgisi sol), text:String, h:float (yazı boyutu)}
## Sanal köşe noktaları (virtual_points): köşe yuvarlatma/pah sonrası eski köşe, boyutlar bağlı kalsın diye tutulur.
##
## Nokta 0 her zaman taslak orijinidir (sabit, silinemez).
## Kısıtlar (ilişkiler ve boyutlar): {id, type, p1?, p2?, e1?, e2?, value?, driven?, s?, su?, sv?, off?}
##   İlişkiler: horizontal, vertical, parallel, perpendicular, collinear, equal, concentric,
##              tangent, coincident (nokta-eğri), midpoint, symmetric, fix
##   Boyutlar : distance, hdistance, vdistance, pl_distance, radius, diameter, angle

const ORIGIN := 0
const DIM_TYPES := ["distance", "hdistance", "vdistance", "pl_distance", "radius", "diameter", "angle"]

var points := {}        # int -> Vector2
var entities: Array = []
var constraints: Array = []
var groups := {}        # int -> Dictionary
var virtual_points := {}  # pid -> true
var blocks := {}          # bid -> {name, pts:[pid], local:{pid: Vector2}, entities:[eid]}
var next_id := 1

const SPLINE_STEPS := 16


func _init() -> void:
	points[ORIGIN] = Vector2.ZERO


func _new_id() -> int:
	var i := next_id
	next_id += 1
	return i


func is_empty() -> bool:
	return entities.is_empty()


# ---------------------------------------------------------------- oluşturma

func add_point(p: Vector2) -> int:
	var id := _new_id()
	points[id] = p
	return id


func add_line(a: int, b: int, construction := false, group := 0) -> int:
	var id := _new_id()
	entities.append({"id": id, "type": "line", "a": a, "b": b, "construction": construction, "group": group})
	return id


func add_circle(c: int, r: float, construction := false) -> int:
	var id := _new_id()
	entities.append({"id": id, "type": "circle", "c": c, "r": r, "construction": construction})
	return id


func add_arc(c: int, a: int, b: int, construction := false) -> int:
	var id := _new_id()
	entities.append({"id": id, "type": "arc", "c": c, "a": a, "b": b, "construction": construction})
	return id


func add_spline(pids: Array, construction := false) -> int:
	var id := _new_id()
	entities.append({"id": id, "type": "spline", "pts": pids.duplicate(), "construction": construction})
	return id


## Elips: merkez c, büyük eksen ucu m (büyük yarı eksen = |m-c|), küçük yarı eksen rb.
func add_ellipse(c: int, m: int, rb: float, construction := false) -> int:
	var id := _new_id()
	entities.append({"id": id, "type": "ellipse", "c": c, "m": m, "rb": rb, "construction": construction})
	return id


## Parabol: tepe v, odak f, uçlar a ve b (parabol üzerinde).
func add_parabola(v: int, f: int, a: int, b: int, construction := false) -> int:
	var id := _new_id()
	entities.append({"id": id, "type": "parabola", "v": v, "f": f, "a": a, "b": b, "construction": construction})
	return id


func add_text(p: int, text: String, h: float) -> int:
	var id := _new_id()
	entities.append({"id": id, "type": "text", "p": p, "text": text, "h": h, "construction": false})
	return id


## Dört köşe noktasından (c0..c3, sırayla) dikdörtgen grubu oluşturur. Grup id döner.
func add_rect(corners: Array) -> int:
	var g := _new_id()
	groups[g] = {"type": "rect", "pts": corners.duplicate()}
	for i in 4:
		var eid := add_line(corners[i], corners[(i + 1) % 4], false, g)
		# alt/üst kenar yatay, sağ/sol kenar dikey
		add_constraint({"type": "horizontal" if i % 2 == 0 else "vertical", "e1": eid})
	return g


## Dikdörtgen grubunu verilen konum/boyuta göre yeniden yerleştirir.
func set_rect(gid: int, pos: Vector2, size: Vector2) -> void:
	if not groups.has(gid):
		return
	var pts: Array = groups[gid]["pts"]
	points[pts[0]] = pos
	points[pts[1]] = pos + Vector2(size.x, 0)
	points[pts[2]] = pos + size
	points[pts[3]] = pos + Vector2(0, size.y)


func rect_info(gid: int) -> Dictionary:
	var pts: Array = groups[gid]["pts"]
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for pid in pts:
		var p: Vector2 = points[pid]
		mn = mn.min(p)
		mx = mx.max(p)
	return {"pos": mn, "size": mx - mn}


# ---------------------------------------------------------------- sorgular

func get_entity(id: int) -> Dictionary:
	for e in entities:
		if e["id"] == id:
			return e
	return {}


static func entity_point_ids(e: Dictionary) -> Array:
	match e.get("type", ""):
		"line":
			return [e["a"], e["b"]]
		"circle":
			return [e["c"]]
		"arc":
			return [e["c"], e["a"], e["b"]]
		"spline":
			var out: Array = []
			for pid in e["pts"]:
				if not (pid in out):
					out.append(pid)
			return out
		"text":
			return [e["p"]]
		"ellipse":
			return [e["c"], e["m"]]
		"parabola":
			return [e["v"], e["f"], e["a"], e["b"]]
	return []


## Profil kenarı olabilen (iki uçlu) öğe mi? Uçlar: edge_ends().
static func is_edge(e: Dictionary) -> bool:
	return e["type"] in ["line", "arc", "spline", "parabola"]


static func edge_ends(e: Dictionary) -> Array:
	if e["type"] == "spline":
		return [e["pts"][0], e["pts"][e["pts"].size() - 1]]
	return [e["a"], e["b"]]


## Bir noktaya bağlı varlık sayısı.
func point_users(pid: int) -> Array:
	var out := []
	for e in entities:
		if pid in entity_point_ids(e):
			out.append(e["id"])
	return out


func remove_entity(id: int) -> void:
	for i in entities.size():
		if entities[i]["id"] == id:
			entities.remove_at(i)
			break
	_cleanup()


func remove_point(pid: int) -> void:
	if pid == ORIGIN:
		return
	var ids := point_users(pid)
	for id in ids:
		for i in entities.size():
			if entities[i]["id"] == id:
				entities.remove_at(i)
				break
	_cleanup()


func _cleanup() -> void:
	for _pass in 2:
		# Geçersiz referanslı kısıtları sil
		var keep: Array = []
		for c in constraints:
			if _constraint_valid(c):
				keep.append(c)
		constraints = keep
		var used := {}
		for e in entities:
			for pid in entity_point_ids(e):
				used[pid] = true
		used[ORIGIN] = true
		# Sanal köşe noktası, ona bağlı bir öğe kısıtı (çakışık) kaldıkça yaşar
		for vp in virtual_points.keys():
			var alive := false
			for c in constraints:
				if c["type"] == "coincident" and int(c.get("p1", -1)) == vp:
					alive = true
			if alive:
				used[vp] = true
			else:
				virtual_points.erase(vp)
		for pid in points.keys():
			if not used.has(pid):
				points.erase(pid)
	if not points.has(ORIGIN):
		points[ORIGIN] = Vector2.ZERO
	var keep2: Array = []
	for c in constraints:
		if _constraint_valid(c):
			keep2.append(c)
	constraints = keep2
	# Eksik çizgisi olan veya köşesi değişmiş grupları çöz
	for gid in groups.keys():
		var count := 0
		for e in entities:
			if int(e.get("group", 0)) == gid:
				count += 1
		var pts_ok := true
		for pid in groups[gid]["pts"]:
			if not points.has(pid) or virtual_points.has(pid):
				pts_ok = false
		if count != 4 or not pts_ok:
			groups.erase(gid)
			for e in entities:
				if int(e.get("group", 0)) == gid:
					e["group"] = 0
	# Silinen noktaları bloklardan çıkar; boş blokları sil
	for bid in blocks.keys():
		var bl: Dictionary = blocks[bid]
		var bp: Array = bl["pts"]
		for pid in bp.duplicate():
			if not points.has(pid):
				bp.erase(pid)
				(bl["local"] as Dictionary).erase(pid)
		var be: Array = bl.get("entities", [])
		for eid in be.duplicate():
			if get_entity(eid).is_empty():
				be.erase(eid)
		if bp.is_empty():
			blocks.erase(bid)


# ---------------------------------------------------------------- bloklar

## Seçili öğelerden rijit blok oluşturur. Bloğun iç ilişkileri rijitliğe katılır (silinir).
func make_block(eids: Array, block_name := "") -> int:
	var pts: Array = []
	for eid in eids:
		for pid in entity_point_ids(get_entity(eid)):
			if pid != ORIGIN and not (pid in pts) and block_of_point(pid) < 0:
				pts.append(pid)
	if pts.is_empty():
		return -1
	var cen := Vector2.ZERO
	for pid in pts:
		cen += points[pid]
	cen /= pts.size()
	var local := {}
	for pid in pts:
		local[pid] = (points[pid] as Vector2) - cen
	var bid := _new_id()
	if block_name == "":
		block_name = "Blok%d" % (blocks.size() + 1)
	blocks[bid] = {"name": block_name, "pts": pts, "local": local, "entities": eids.duplicate()}
	# İç ilişkiler (tüm referansları blokta) gereksiz hâle gelir
	var keep: Array = []
	for c in constraints:
		var inside := not (constraint_points(c).is_empty() and constraint_entities(c).is_empty())
		for pid in constraint_points(c):
			if not (pid in pts):
				inside = false
		for eid in constraint_entities(c):
			if not (eid in eids):
				inside = false
		if not inside:
			keep.append(c)
	constraints = keep
	return bid


func block_of_point(pid: int) -> int:
	for bid in blocks:
		if pid in blocks[bid]["pts"]:
			return bid
	return -1


func block_of_entity(eid: int) -> int:
	for bid in blocks:
		if eid in blocks[bid].get("entities", []):
			return bid
	return -1


func explode_block(bid: int) -> void:
	blocks.erase(bid)


# ---------------------------------------------------------------- kısıtlar

static func is_dimension(c: Dictionary) -> bool:
	return str(c.get("type", "")) in DIM_TYPES


func add_constraint(c: Dictionary) -> int:
	var id := _new_id()
	c["id"] = id
	if is_dimension(c) and not c.has("num"):
		var mx := 0
		for o in constraints:
			mx = maxi(mx, int(o.get("num", 0)))
		c["num"] = mx + 1
	constraints.append(c)
	return id


func get_constraint(id: int) -> Dictionary:
	for c in constraints:
		if c["id"] == id:
			return c
	return {}


func remove_constraint(id: int) -> void:
	for i in constraints.size():
		if constraints[i]["id"] == id:
			constraints.remove_at(i)
			return


static func constraint_points(c: Dictionary) -> Array:
	var out: Array = []
	for k in ["p1", "p2"]:
		if c.has(k):
			out.append(int(c[k]))
	return out


static func constraint_entities(c: Dictionary) -> Array:
	var out: Array = []
	for k in ["e1", "e2"]:
		if c.has(k):
			out.append(int(c[k]))
	return out


func _constraint_valid(c: Dictionary) -> bool:
	for pid in constraint_points(c):
		if not points.has(pid):
			return false
	for eid in constraint_entities(c):
		if get_entity(eid).is_empty():
			return false
	return true


## Verilen öğelere/noktalara dokunan kısıtlar.
func constraints_touching(eids: Array, pids: Array) -> Array:
	var out: Array = []
	for c in constraints:
		var hit := false
		for eid in constraint_entities(c):
			if eid in eids:
				hit = true
		for pid in constraint_points(c):
			if pid in pids:
				hit = true
		if hit:
			out.append(c)
	return out


## İki noktayı birleştirir (çakışık ilişkisi). drop noktasının tüm referansları keep'e taşınır.
func merge_points(keep: int, drop: int) -> void:
	if keep == drop:
		return
	if drop == ORIGIN:
		var t := keep
		keep = drop
		drop = t
	for e in entities:
		for k in ["a", "b", "c", "p", "m", "v", "f"]:
			if e.has(k) and int(e[k]) == drop:
				e[k] = keep
		if e["type"] == "spline":
			var sp: Array = e["pts"]
			for i in sp.size():
				if int(sp[i]) == drop:
					sp[i] = keep
			# ardışık tekrarları sil
			var clean: Array = []
			for pid in sp:
				if clean.is_empty() or clean[clean.size() - 1] != pid:
					clean.append(pid)
			e["pts"] = clean
	if virtual_points.has(drop):
		virtual_points.erase(drop)
	for bl in blocks.values():
		var bp: Array = bl["pts"]
		if drop in bp:
			bp.erase(drop)
			(bl["local"] as Dictionary).erase(drop)
	for c in constraints:
		for k in ["p1", "p2"]:
			if c.has(k) and int(c[k]) == drop:
				c[k] = keep
	for g in groups.values():
		var pts: Array = g["pts"]
		for i in pts.size():
			if int(pts[i]) == drop:
				pts[i] = keep
	points.erase(drop)
	# Dejenere öğeleri at (iki ucu aynı nokta olan çizgi vb.)
	var keep_e: Array = []
	for e in entities:
		var ok := true
		match e["type"]:
			"line":
				ok = int(e["a"]) != int(e["b"])
			"arc":
				ok = int(e["a"]) != int(e["b"]) and int(e["c"]) != int(e["a"]) and int(e["c"]) != int(e["b"])
			"spline":
				ok = entity_point_ids(e).size() >= 2
			"ellipse":
				ok = int(e["c"]) != int(e["m"])
			"parabola":
				ok = int(e["a"]) != int(e["b"]) and int(e["v"]) != int(e["f"])
		if ok:
			keep_e.append(e)
	entities = keep_e
	_cleanup()


func line_midpoint(e: Dictionary) -> Vector2:
	return (points[e["a"]] + points[e["b"]]) * 0.5


func entity_radius(e: Dictionary) -> float:
	if e["type"] == "circle":
		return float(e["r"])
	if e["type"] == "arc":
		return (points[e["a"]] as Vector2).distance_to(points[e["c"]])
	if e["type"] == "ellipse":
		return float(e["rb"])
	return 0.0


# ---------------------------------------------------------------- elips ve parabol

func ellipse_axes(e: Dictionary) -> Dictionary:
	var c: Vector2 = points[e["c"]]
	var mv: Vector2 = (points[e["m"]] as Vector2) - c
	return {"c": c, "a": mv.length(), "b": float(e["rb"]), "phi": mv.angle()}


static func ellipse_polygon(c: Vector2, a: float, b: float, phi: float) -> PackedVector2Array:
	var n := full_segments(maxf(a, b))
	var out := PackedVector2Array()
	for i in n:
		var t := TAU * float(i) / float(n)
		out.append(c + Vector2(a * cos(t), b * sin(t)).rotated(phi))
	return out


func ellipse_points(e: Dictionary) -> PackedVector2Array:
	var ax := ellipse_axes(e)
	return ellipse_polygon(ax["c"], ax["a"], ax["b"], ax["phi"])


## Parabol yerel çerçevesi: u = odağa doğru eksen, w = dik eksen, fl = odak uzaklığı.
func parabola_frame(e: Dictionary) -> Dictionary:
	var v: Vector2 = points[e["v"]]
	var d: Vector2 = (points[e["f"]] as Vector2) - v
	var fl := maxf(d.length(), 1e-9)
	var u := d / fl
	return {"v": v, "u": u, "w": Vector2(-u.y, u.x), "fl": fl}


static func parabola_point(fr: Dictionary, w: float) -> Vector2:
	var fl: float = fr["fl"]
	return (fr["v"] as Vector2) + (fr["u"] as Vector2) * (w * w / (4.0 * fl)) + (fr["w"] as Vector2) * w


func parabola_points(e: Dictionary, reverse := false) -> PackedVector2Array:
	var fr := parabola_frame(e)
	var pa: Vector2 = points[e["a"]]
	var pb: Vector2 = points[e["b"]]
	var wa := (pa - (fr["v"] as Vector2)).dot(fr["w"])
	var wb := (pb - (fr["v"] as Vector2)).dot(fr["w"])
	var out := PackedVector2Array()
	out.append(pa)
	var n := 64
	for i in range(1, n):
		out.append(parabola_point(fr, lerpf(wa, wb, float(i) / n)))
	out.append(pb)
	if reverse:
		out.reverse()
	return out


## Öğe üzerindeki en yakın nokta.
func closest_on_entity(e: Dictionary, pos: Vector2) -> Vector2:
	match e["type"]:
		"line":
			return Geometry2D.get_closest_point_to_segment(pos, points[e["a"]], points[e["b"]])
		"circle":
			var c: Vector2 = points[e["c"]]
			var d := pos - c
			if d.length() < 1e-9:
				d = Vector2.RIGHT
			return c + d.normalized() * float(e["r"])
		"arc":
			var ad := arc_data(e)
			var c2: Vector2 = ad["c"]
			var ang := fposmod((pos - c2).angle() - float(ad["a0"]), TAU)
			if ang <= float(ad["sweep"]):
				return c2 + (pos - c2).normalized() * float(ad["r"])
			var pa: Vector2 = ad["pa"]
			var pb: Vector2 = ad["pb"]
			return pa if pos.distance_to(pa) < pos.distance_to(pb) else pb
		"spline", "ellipse", "parabola":
			var poly := entity_polyline(e)
			var best := pos
			var bd := INF
			for i in poly.size() - 1:
				var q := Geometry2D.get_closest_point_to_segment(pos, poly[i], poly[i + 1])
				if q.distance_to(pos) < bd:
					bd = q.distance_to(pos)
					best = q
			return best
	return pos


# ---------------------------------------------------------------- spline ve metin

## Merkezcil Catmull-Rom (eğri tüm noktalardan geçer).
static func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t0 := 0.0
	var t1 := t0 + maxf(pow(p0.distance_to(p1), 0.5), 1e-6)
	var t2 := t1 + maxf(pow(p1.distance_to(p2), 0.5), 1e-6)
	var t3 := t2 + maxf(pow(p2.distance_to(p3), 0.5), 1e-6)
	var tt := lerpf(t1, t2, t)
	var A1 := p0 * (t1 - tt) / (t1 - t0) + p1 * (tt - t0) / (t1 - t0)
	var A2 := p1 * (t2 - tt) / (t2 - t1) + p2 * (tt - t1) / (t2 - t1)
	var A3 := p2 * (t3 - tt) / (t3 - t2) + p3 * (tt - t2) / (t3 - t2)
	var B1 := A1 * (t2 - tt) / (t2 - t0) + A2 * (tt - t0) / (t2 - t0)
	var B2 := A2 * (t3 - tt) / (t3 - t1) + A3 * (tt - t1) / (t3 - t1)
	return B1 * (t2 - tt) / (t2 - t1) + B2 * (tt - t1) / (t2 - t1)


static func spline_through(P: Array, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := P.size()
	if n < 2:
		return out
	if n == 2 and not closed:
		return PackedVector2Array([P[0], P[1]])
	var segs := n if closed else n - 1
	for i in segs:
		var p1: Vector2 = P[i]
		var p2: Vector2 = P[(i + 1) % n]
		var p0: Vector2
		var p3: Vector2
		if closed:
			p0 = P[(i - 1 + n) % n]
			p3 = P[(i + 2) % n]
		else:
			p0 = P[i - 1] if i > 0 else p1 * 2.0 - p2
			p3 = P[i + 2] if i + 2 < n else p2 * 2.0 - p1
		for k in SPLINE_STEPS:
			out.append(_cr(p0, p1, p2, p3, float(k) / SPLINE_STEPS))
	out.append(P[0] if closed else P[n - 1])
	return out


func spline_points(e: Dictionary, reverse := false) -> PackedVector2Array:
	var ids: Array = e["pts"]
	var closed: bool = ids.size() > 2 and ids[0] == ids[ids.size() - 1]
	var P: Array = []
	for i in ids.size():
		if closed and i == ids.size() - 1:
			break
		P.append(points[ids[i]])
	var out := spline_through(P, closed)
	if reverse:
		out.reverse()
	return out


## Metnin kapalı konturları (taslak koordinatlarında).
func text_loops(e: Dictionary) -> Array:
	var base: Vector2 = points[e["p"]]
	var out: Array = []
	for loop in TextOutline.loops(str(e.get("text", "")), float(e.get("h", 10.0))):
		var moved := PackedVector2Array()
		for q in loop:
			moved.append(q + base)
		out.append(moved)
	return out


## Çizim için öğenin tüm nokta listeleri (metin birden çok kontur içerir).
func entity_polylines(e: Dictionary) -> Array:
	if e["type"] == "text":
		var out: Array = []
		for loop in text_loops(e):
			var closed_loop: PackedVector2Array = loop.duplicate()
			if not closed_loop.is_empty():
				closed_loop.append(closed_loop[0])
			out.append(closed_loop)
		return out
	return [entity_polyline(e)]


func arc_data(e: Dictionary) -> Dictionary:
	var c: Vector2 = points[e["c"]]
	var pa: Vector2 = points[e["a"]]
	var pb: Vector2 = points[e["b"]]
	var r := c.distance_to(pa)
	var a0 := (pa - c).angle()
	var a1 := (pb - c).angle()
	var sweep := fposmod(a1 - a0, TAU)
	if sweep < 1e-9:
		sweep = TAU
	return {"c": c, "r": r, "a0": a0, "sweep": sweep, "pa": pa, "pb": pb}


## Tam daire bölme sayısı. Tüm daireler ve döndürmeler aynı sayıyı (ve 0° başlangıcını)
## kullanır; böylece aynı yarıçaplı eş eksenli yüzeyler birebir örtüşür, CSG'de mikro yarık oluşmaz.
static func full_segments(r: float) -> int:
	return 128 if r < 250.0 else 256


static func segment_count(r: float, sweep: float) -> int:
	return maxi(2, int(ceil(full_segments(r) * sweep / TAU - 1e-6)))


static func circle_polygon(c: Vector2, r: float) -> PackedVector2Array:
	var n := segment_count(r, TAU)
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


## Yayı nokta listesine çevirir (uçlar dahil). reverse=true ise bitişten başlangıca.
func arc_points(e: Dictionary, reverse := false) -> PackedVector2Array:
	var d := arc_data(e)
	var n := segment_count(d["r"], d["sweep"])
	var out := PackedVector2Array()
	out.append(d["pa"])
	for i in range(1, n):
		var a: float = d["a0"] + d["sweep"] * float(i) / float(n)
		out.append(d["c"] + Vector2(cos(a), sin(a)) * float(d["r"]))
	out.append(d["pb"])
	if reverse:
		out.reverse()
	return out


## Çizim için varlığın nokta listesi (daire kapalı: ilk nokta sonda tekrar eder).
func entity_polyline(e: Dictionary) -> PackedVector2Array:
	match e["type"]:
		"line":
			return PackedVector2Array([points[e["a"]], points[e["b"]]])
		"circle":
			var poly := circle_polygon(points[e["c"]], float(e["r"]))
			poly.append(poly[0])
			return poly
		"arc":
			return arc_points(e)
		"spline":
			return spline_points(e)
		"ellipse":
			var ep := ellipse_points(e)
			ep.append(ep[0])
			return ep
		"parabola":
			return parabola_points(e)
	return PackedVector2Array()


func _edge_points(e: Dictionary, forward: bool) -> PackedVector2Array:
	if e["type"] == "line":
		var pa: Vector2 = points[e["a"]]
		var pb: Vector2 = points[e["b"]]
		return PackedVector2Array([pa, pb]) if forward else PackedVector2Array([pb, pa])
	if e["type"] == "spline":
		return spline_points(e, not forward)
	if e["type"] == "parabola":
		return parabola_points(e, not forward)
	return arc_points(e, not forward)


static func polygon_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _v2a(p: Vector2) -> Array:
	return [p.x, p.y]


static func _poly_arr(poly: PackedVector2Array) -> Array:
	var out: Array = []
	for q in poly:
		out.append([q.x, q.y])
	return out


## B-rep çekirdeği için öğenin gerçek eğri tanımı (taslak koordinatlarında).
## forward=false ise çizgi ve yay ters yönde verilir. Metin birden çok kapalı çokgen döndürür.
## Her eğri "k" anahtarı taşır (taslak öğe kimliği): çekirdek yüzleri bu anahtarla adlandırır.
func entity_curves(e: Dictionary, forward := true) -> Array:
	var out := _entity_curves_raw(e, forward)
	for i in out.size():
		out[i]["k"] = str(e["id"]) if out.size() == 1 and e["type"] != "text" else "%d.%d" % [int(e["id"]), i]
	return out


func _entity_curves_raw(e: Dictionary, forward: bool) -> Array:
	match e["type"]:
		"line":
			var pa: Vector2 = points[e["a"]]
			var pb: Vector2 = points[e["b"]]
			if not forward:
				var t := pa
				pa = pb
				pb = t
			return [{"t": "line", "a": _v2a(pa), "b": _v2a(pb)}]
		"arc":
			var d := arc_data(e)
			var am: float = float(d["a0"]) + float(d["sweep"]) * 0.5
			var mid: Vector2 = (d["c"] as Vector2) + Vector2(cos(am), sin(am)) * float(d["r"])
			var p0: Vector2 = d["pa"]
			var p1: Vector2 = d["pb"]
			if not forward:
				var t2 := p0
				p0 = p1
				p1 = t2
			return [{"t": "arc", "p": [_v2a(p0), _v2a(mid), _v2a(p1)]}]
		"circle":
			return [{"t": "circle", "c": _v2a(points[e["c"]]), "r": float(e["r"])}]
		"ellipse":
			var ax := ellipse_axes(e)
			return [{"t": "ellipse", "c": _v2a(ax["c"]), "a": ax["a"], "b": ax["b"], "phi": ax["phi"]}]
		"parabola":
			var fr := parabola_frame(e)
			var v: Vector2 = fr["v"]
			var w: Vector2 = fr["w"]
			return [{"t": "parabola", "v": _v2a(v), "u": _v2a(fr["u"]), "fl": fr["fl"],
				"w0": ((points[e["a"]] as Vector2) - v).dot(w), "w1": ((points[e["b"]] as Vector2) - v).dot(w)}]
		"spline":
			var ids: Array = e["pts"]
			var closed: bool = ids.size() > 2 and ids[0] == ids[ids.size() - 1]
			return [{"t": "bspline", "p": _poly_arr(spline_points(e, not forward)), "closed": closed}]
		"text":
			var out: Array = []
			for tl in text_loops(e):
				if (tl as PackedVector2Array).size() >= 3:
					out.append({"t": "poly", "p": _poly_arr(tl)})
			return out
	return []


## Yapı geometrisi olmayan kenarların bağlı zincirleri: her zincir sıralı eğri listesi
## (ince özellik, süpürme yolu, kaburga için). Daire/elips ve kapalı spline tek başına bir zincirdir.
func curve_chains() -> Array:
	var edges: Array = []
	var adj := {}
	var out: Array = []
	for e in entities:
		if e.get("construction", false):
			continue
		match e["type"]:
			"circle", "ellipse":
				out.append(entity_curves(e))
			"line", "arc", "spline", "parabola":
				var ends := edge_ends(e)
				if ends[0] == ends[1]:
					out.append(entity_curves(e))
					continue
				var idx := edges.size()
				edges.append({"e": e, "a": ends[0], "b": ends[1]})
				for pid in ends:
					if not adj.has(pid):
						adj[pid] = []
					adj[pid].append(idx)
	var used := {}
	for i in edges.size():
		if used.has(i):
			continue
		var cur := i
		var pt: int = edges[i]["a"]
		var guard := 0
		while (adj[pt] as Array).size() == 2 and guard < 100000:
			var other: int = adj[pt][0] if adj[pt][0] != cur else adj[pt][1]
			if other == i:
				break
			cur = other
			pt = edges[cur]["a"] if edges[cur]["b"] == pt else edges[cur]["b"]
			guard += 1
		var curves: Array = []
		var start := cur
		guard = 0
		while guard < 100000:
			used[cur] = true
			var fwd: bool = edges[cur]["a"] == pt
			curves.append_array(entity_curves(edges[cur]["e"], fwd))
			pt = edges[cur]["b"] if fwd else edges[cur]["a"]
			var nb: Array = adj[pt]
			if nb.size() != 2:
				break
			var nxt: int = nb[0] if nb[0] != cur else nb[1]
			if nxt == start or used.has(nxt):
				break
			cur = nxt
			guard += 1
		out.append(curves)
	return out


## Yapı geometrisi olmayan tüm eğriler (bölge seçimi için).
func all_curves() -> Array:
	var out: Array = []
	for e in entities:
		if e.get("construction", false) or not (e["type"] in ["line", "arc", "circle", "ellipse", "parabola", "spline", "text"]):
			continue
		out.append_array(entity_curves(e))
	return out


## Kapalı konturları bulur.
## Dönüş: {loops: [{poly: PackedVector2Array (CCW), depth: int, parent: int, curves: Array}], open: int}
## depth: kaç konturun içinde olduğu (çift = dolu, tek = delik); parent: bir üst konturun indeksi.
## curves: B-rep çekirdeği için konturun gerçek eğrileri (sırayla).
func extract_profiles() -> Dictionary:
	var loops: Array = []
	var loop_curves: Array = []
	var edges: Array = []
	var adj := {}
	for e in entities:
		if e.get("construction", false):
			continue
		match e["type"]:
			"circle":
				if float(e["r"]) > 1e-6:
					loops.append(circle_polygon(points[e["c"]], float(e["r"])))
					loop_curves.append(entity_curves(e))
			"ellipse":
				var ax := ellipse_axes(e)
				if float(ax["a"]) > 1e-6 and float(ax["b"]) > 1e-6:
					loops.append(ellipse_points(e))
					loop_curves.append(entity_curves(e))
			"line", "arc", "spline", "parabola":
				var ends := edge_ends(e)
				var idx := edges.size()
				edges.append({"e": e, "a": ends[0], "b": ends[1]})
				for pid in ends:
					if not adj.has(pid):
						adj[pid] = []
					adj[pid].append(idx)
			"text":
				var tls := text_loops(e)
				for ti in tls.size():
					var tl: PackedVector2Array = tls[ti]
					if tl.size() >= 3:
						loops.append(tl)
						loop_curves.append([{"t": "poly", "p": _poly_arr(tl), "k": "%d.%d" % [int(e["id"]), ti]}])
	var open_count := 0
	var used := {}
	for start in edges.size():
		if used.has(start):
			continue
		var comp_edges: Array = []
		var comp_pts := {}
		var stack: Array = [start]
		used[start] = true
		while not stack.is_empty():
			var ei: int = stack.pop_back()
			comp_edges.append(ei)
			var ce: Dictionary = edges[ei]
			for pid in [ce["a"], ce["b"]]:
				comp_pts[pid] = true
				for nb in adj[pid]:
					if not used.has(nb):
						used[nb] = true
						stack.append(nb)
		var closed := true
		for pid in comp_pts:
			if (adj[pid] as Array).size() != 2:
				closed = false
				break
		if not closed:
			open_count += 1
			continue
		var poly := PackedVector2Array()
		var curves: Array = []
		var first_edge: int = comp_edges[0]
		var cur_edge := first_edge
		var cur_pt: int = edges[cur_edge]["a"]
		var guard := 0
		while true:
			var e: Dictionary = edges[cur_edge]
			var forward: bool = e["a"] == cur_pt
			var pts := _edge_points(e["e"], forward)
			curves.append_array(entity_curves(e["e"], forward))
			for i in pts.size() - 1:
				poly.append(pts[i])
			cur_pt = e["b"] if forward else e["a"]
			var nbrs: Array = adj[cur_pt]
			cur_edge = nbrs[0] if nbrs[0] != cur_edge else nbrs[1]
			guard += 1
			if cur_edge == first_edge or guard > 100000:
				break
		if poly.size() >= 3 and absf(polygon_area(poly)) > 1e-8:
			loops.append(poly)
			loop_curves.append(curves)
	var result: Array = []
	for i in loops.size():
		var poly: PackedVector2Array = loops[i]
		if polygon_area(poly) < 0.0:
			poly.reverse()
		var depth := 0
		var inside: Array = []
		for j in loops.size():
			if i != j and Geometry2D.is_point_in_polygon(poly[0], loops[j]):
				depth += 1
				inside.append(j)
		result.append({"poly": poly, "depth": depth, "curves": loop_curves[i], "_src": i, "_in": inside})
	result.sort_custom(func(x, y): return x["depth"] < y["depth"])
	# Bir üst kontur: içinde bulunulan ve derinliği bir eksik olan kontur
	var pos_of := {}
	for k in result.size():
		pos_of[result[k]["_src"]] = k
	for L in result:
		var parent := -1
		for j in L["_in"]:
			var pj: int = pos_of[j]
			if int(result[pj]["depth"]) == int(L["depth"]) - 1:
				parent = pj
				break
		L["parent"] = parent
		L.erase("_src")
		L.erase("_in")
	return {"loops": result, "open": open_count}


# ---------------------------------------------------------------- seçim / isabet testi

func hit_point(pos: Vector2, tol: float, exclude: Array = []) -> int:
	var best := -1
	var best_d := tol
	for pid in points:
		if pid in exclude:
			continue
		var d := pos.distance_to(points[pid])
		if d <= best_d:
			best_d = d
			best = pid
	return best


func entity_distance(e: Dictionary, pos: Vector2) -> float:
	match e["type"]:
		"line":
			var a: Vector2 = points[e["a"]]
			var b: Vector2 = points[e["b"]]
			return Geometry2D.get_closest_point_to_segment(pos, a, b).distance_to(pos)
		"circle":
			return absf(pos.distance_to(points[e["c"]]) - float(e["r"]))
		"arc":
			var d := arc_data(e)
			var ang := fposmod((pos - d["c"]).angle() - float(d["a0"]), TAU)
			if ang <= float(d["sweep"]):
				return absf(pos.distance_to(d["c"]) - float(d["r"]))
			return minf(pos.distance_to(d["pa"]), pos.distance_to(d["pb"]))
		"spline", "ellipse", "parabola":
			return closest_on_entity(e, pos).distance_to(pos)
		"text":
			var r := entity_bounds(e)
			if r.has_point(pos):
				return 0.0
			var cx := clampf(pos.x, r.position.x, r.end.x)
			var cy := clampf(pos.y, r.position.y, r.end.y)
			return pos.distance_to(Vector2(cx, cy))
	return INF


func entity_bounds(e: Dictionary) -> Rect2:
	match e["type"]:
		"line":
			return Rect2(points[e["a"]], Vector2.ZERO).expand(points[e["b"]])
		"circle", "arc":
			var c: Vector2 = points[e["c"]]
			var rad: float = entity_radius(e)
			return Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0)
	var r := Rect2()
	var first := true
	for poly in entity_polylines(e):
		for q in poly:
			if first:
				r = Rect2(q, Vector2.ZERO)
				first = false
			else:
				r = r.expand(q)
	if first and e["type"] == "text":
		r = Rect2(points[e["p"]], Vector2.ZERO)
	return r


func hit_entity(pos: Vector2, tol: float) -> int:
	var best := -1
	var best_d := tol
	for e in entities:
		var d := entity_distance(e, pos)
		if d <= best_d:
			best_d = d
			best = e["id"]
	return best


func bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for e in entities:
		var rr := entity_bounds(e)
		if first:
			r = rr
			first = false
		else:
			r = r.merge(rr)
	return r


# ---------------------------------------------------------------- serileştirme

func to_dict() -> Dictionary:
	var pts := {}
	for pid in points:
		var p: Vector2 = points[pid]
		pts[str(pid)] = [p.x, p.y]
	var grps := {}
	for gid in groups:
		grps[str(gid)] = groups[gid].duplicate(true)
	var cons: Array = []
	for c in constraints:
		var cc: Dictionary = c.duplicate(true)
		if cc.has("off"):
			var o: Vector2 = cc["off"]
			cc["off"] = [o.x, o.y]
		cons.append(cc)
	return {"points": pts, "entities": entities.duplicate(true), "constraints": cons, "groups": grps,
		"virtual": virtual_points.keys(), "blocks": _blocks_to_dict(), "next_id": next_id}


func _blocks_to_dict() -> Dictionary:
	var out := {}
	for bid in blocks:
		var bl: Dictionary = blocks[bid]
		var loc := {}
		for pid in bl["local"]:
			var v: Vector2 = bl["local"][pid]
			loc[str(pid)] = [v.x, v.y]
		out[str(bid)] = {"name": bl["name"], "pts": (bl["pts"] as Array).duplicate(), "local": loc,
			"entities": (bl.get("entities", []) as Array).duplicate()}
	return out


static func from_dict(d: Dictionary) -> Sketch:
	var s := Sketch.new()
	var pts: Dictionary = d.get("points", {})
	for k in pts:
		var v: Array = pts[k]
		s.points[int(k)] = Vector2(float(v[0]), float(v[1]))
	for e in d.get("entities", []):
		var ne: Dictionary = (e as Dictionary).duplicate(true)
		for key in ["id", "a", "b", "c", "group", "p", "m", "v", "f"]:
			if ne.has(key):
				ne[key] = int(ne[key])
		if ne.has("rb"):
			ne["rb"] = float(ne["rb"])
		if ne.has("r"):
			ne["r"] = float(ne["r"])
		if ne.has("h"):
			ne["h"] = float(ne["h"])
		if ne.has("pts"):
			var ip: Array = []
			for q in ne["pts"]:
				ip.append(int(q))
			ne["pts"] = ip
		ne["construction"] = bool(ne.get("construction", false))
		s.entities.append(ne)
	var grps: Dictionary = d.get("groups", {})
	for k in grps:
		var g: Dictionary = (grps[k] as Dictionary).duplicate(true)
		var ints: Array = []
		for p in g.get("pts", []):
			ints.append(int(p))
		g["pts"] = ints
		s.groups[int(k)] = g
	for c in d.get("constraints", []):
		var nc: Dictionary = (c as Dictionary).duplicate(true)
		for key in ["id", "p1", "p2", "e1", "e2", "num"]:
			if nc.has(key):
				nc[key] = int(nc[key])
		for key in ["value", "s", "su", "sv"]:
			if nc.has(key):
				nc[key] = float(nc[key])
		if nc.has("driven"):
			nc["driven"] = bool(nc["driven"])
		if nc.has("internal"):
			nc["internal"] = bool(nc["internal"])
		if nc.has("off"):
			var o = nc["off"]
			if o is Array and o.size() >= 2:
				nc["off"] = Vector2(float(o[0]), float(o[1]))
			elif not (o is Vector2):
				nc.erase("off")
		s.constraints.append(nc)
	for vp in d.get("virtual", []):
		s.virtual_points[int(vp)] = true
	var bls: Dictionary = d.get("blocks", {})
	for k in bls:
		var b: Dictionary = bls[k]
		var bp: Array = []
		for q in b.get("pts", []):
			bp.append(int(q))
		var loc := {}
		var ld: Dictionary = b.get("local", {})
		for lk in ld:
			var lv = ld[lk]
			loc[int(lk)] = lv if lv is Vector2 else Vector2(float(lv[0]), float(lv[1]))
		var be: Array = []
		for q in b.get("entities", []):
			be.append(int(q))
		s.blocks[int(k)] = {"name": str(b.get("name", "Blok")), "pts": bp, "local": loc, "entities": be}
	s.next_id = int(d.get("next_id", 1))
	if not s.points.has(ORIGIN):
		s.points[ORIGIN] = Vector2.ZERO
	return s


func clone() -> Sketch:
	return Sketch.from_dict(to_dict())
