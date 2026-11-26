class_name Exporters
extends RefCounted
## Dışa aktarma: STL (ikili), OBJ, taslak için DXF (R12) ve SVG.
## Tüm koordinatlar milimetredir.


## İkili STL. tris: saat yönü tersine (dış normale göre) üçgen köşeleri.
static func write_stl(path: String, tris: PackedVector3Array, solid_name := "DIY.CAD") -> Error:
	var count := tris.size() / 3
	var buf := PackedByteArray()
	buf.resize(84 + count * 50)
	buf.fill(0)
	var header := ("DIY.CAD binary STL - " + solid_name).to_utf8_buffer()
	for i in mini(header.size(), 80):
		buf[i] = header[i]
	buf.encode_u32(80, count)
	var off := 84
	for t in count:
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() > 0.0:
			n = n.normalized()
		var vals := [n, a, b, c]
		for v in vals:
			buf.encode_float(off, v.x)
			buf.encode_float(off + 4, v.y)
			buf.encode_float(off + 8, v.z)
			off += 12
		off += 2
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(buf)
	f.close()
	return OK


static func write_obj(path: String, model: ModelMesh, obj_name := "DIYCAD_Part") -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var lines := PackedStringArray()
	lines.append("# DIY.CAD OBJ export (birim: mm)")
	lines.append("o " + obj_name)
	for v in model.verts:
		lines.append("v %.6f %.6f %.6f" % [v.x, v.y, v.z])
	for ti in model.tri_count():
		# OBJ: saat yönü tersine
		lines.append("f %d %d %d" % [model.tris[ti * 3] + 1, model.tris[ti * 3 + 2] + 1, model.tris[ti * 3 + 1] + 1])
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return OK


static func _dxf_pair(out: PackedStringArray, code: int, value: Variant) -> void:
	out.append(str(code))
	if typeof(value) == TYPE_FLOAT:
		out.append("%.6f" % value)
	else:
		out.append(str(value))


## Taslağı DXF (R12, ASCII) olarak yazar. Yapı (construction) çizgileri atlanır.
static func write_dxf(path: String, sk: Sketch) -> Error:
	var o := PackedStringArray()
	_dxf_pair(o, 0, "SECTION")
	_dxf_pair(o, 2, "HEADER")
	_dxf_pair(o, 9, "$INSUNITS")
	_dxf_pair(o, 70, 4)
	_dxf_pair(o, 0, "ENDSEC")
	_dxf_pair(o, 0, "SECTION")
	_dxf_pair(o, 2, "ENTITIES")
	for e in sk.entities:
		if e.get("construction", false):
			continue
		match e["type"]:
			"line":
				var a: Vector2 = sk.points[e["a"]]
				var b: Vector2 = sk.points[e["b"]]
				_dxf_pair(o, 0, "LINE")
				_dxf_pair(o, 8, "0")
				_dxf_pair(o, 10, a.x)
				_dxf_pair(o, 20, a.y)
				_dxf_pair(o, 30, 0.0)
				_dxf_pair(o, 11, b.x)
				_dxf_pair(o, 21, b.y)
				_dxf_pair(o, 31, 0.0)
			"circle":
				var c: Vector2 = sk.points[e["c"]]
				_dxf_pair(o, 0, "CIRCLE")
				_dxf_pair(o, 8, "0")
				_dxf_pair(o, 10, c.x)
				_dxf_pair(o, 20, c.y)
				_dxf_pair(o, 30, 0.0)
				_dxf_pair(o, 40, float(e["r"]))
			"arc":
				var d := sk.arc_data(e)
				var c2: Vector2 = d["c"]
				var a0 := rad_to_deg(float(d["a0"]))
				var a1 := a0 + rad_to_deg(float(d["sweep"]))
				_dxf_pair(o, 0, "ARC")
				_dxf_pair(o, 8, "0")
				_dxf_pair(o, 10, c2.x)
				_dxf_pair(o, 20, c2.y)
				_dxf_pair(o, 30, 0.0)
				_dxf_pair(o, 40, float(d["r"]))
				_dxf_pair(o, 50, fposmod(a0, 360.0))
				_dxf_pair(o, 51, fposmod(a1, 360.0))
			_:
				# Spline ve metin: çizgi parçalarına bölünür (R12'de SPLINE yok)
				for poly in sk.entity_polylines(e):
					for i in (poly as PackedVector2Array).size() - 1:
						var p0: Vector2 = poly[i]
						var p1: Vector2 = poly[i + 1]
						_dxf_pair(o, 0, "LINE")
						_dxf_pair(o, 8, "0")
						_dxf_pair(o, 10, p0.x)
						_dxf_pair(o, 20, p0.y)
						_dxf_pair(o, 30, 0.0)
						_dxf_pair(o, 11, p1.x)
						_dxf_pair(o, 21, p1.y)
						_dxf_pair(o, 31, 0.0)
	_dxf_pair(o, 0, "ENDSEC")
	_dxf_pair(o, 0, "EOF")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string("\n".join(o) + "\n")
	f.close()
	return OK


## Taslağı gerçek ölçülü (mm) SVG olarak yazar.
static func write_svg(path: String, sk: Sketch) -> Error:
	var r := sk.bounds().grow(2.0)
	var body := PackedStringArray()
	for e in sk.entities:
		if e.get("construction", false):
			continue
		match e["type"]:
			"line":
				var a: Vector2 = sk.points[e["a"]]
				var b: Vector2 = sk.points[e["b"]]
				body.append('<line x1="%.4f" y1="%.4f" x2="%.4f" y2="%.4f"/>' % [a.x, a.y, b.x, b.y])
			"circle":
				var c: Vector2 = sk.points[e["c"]]
				body.append('<circle cx="%.4f" cy="%.4f" r="%.4f"/>' % [c.x, c.y, float(e["r"])])
			"arc":
				var d := sk.arc_data(e)
				var pa: Vector2 = d["pa"]
				var c2: Vector2 = d["c"]
				var rad: float = d["r"]
				var a1: float = float(d["a0"]) + float(d["sweep"])
				var pb := c2 + Vector2(cos(a1), sin(a1)) * rad
				var large := 1 if float(d["sweep"]) > PI else 0
				body.append('<path d="M %.4f %.4f A %.4f %.4f 0 %d 1 %.4f %.4f"/>' % [pa.x, pa.y, rad, rad, large, pb.x, pb.y])
			_:
				for poly in sk.entity_polylines(e):
					var parts := PackedStringArray()
					for q in poly:
						parts.append("%.4f,%.4f" % [q.x, q.y])
					if parts.size() >= 2:
						body.append('<polyline points="%s"/>' % " ".join(parts))
	var svg := '<?xml version="1.0" encoding="UTF-8"?>\n'
	svg += '<svg xmlns="http://www.w3.org/2000/svg" width="%.3fmm" height="%.3fmm" viewBox="0 0 %.4f %.4f">\n' % [r.size.x, r.size.y, r.size.x, r.size.y]
	svg += '<g transform="translate(%.4f %.4f) scale(1 -1)" fill="none" stroke="#000" stroke-width="0.2">\n' % [-r.position.x, r.position.y + r.size.y]
	svg += "\n".join(body) + "\n</g>\n</svg>\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(svg)
	f.close()
	return OK
