class_name Equations
extends RefCounted
## Global değişkenler ve denklemler (denklem yöneticisi).
##
##   Global değişken : doc.variables = [{name: "genislik", expr: "80"}]
##   Boyut denklemi  : boyut kısıtında "expr" alanı, ör. "genislik / 2" veya "\"D1@Taslak1\" * 2"
##   Özellik denklemi: feature.params["depth_expr"] (ekstrüzyon derinliği) / ["angle_expr"] (döndürme açısı)
##
## Boyut adları: taslak boyutları "D<n>@<taslak adı>", özellik boyutu "D1@<özellik adı>".
## Uzunluklar ekrandaki birimle, açılar derece ile yorumlanır.

const NAME_CHARS := "A-Za-z0-9_ğüşıöçĞÜŞİÖÇ"

static var _int_re: RegEx


static func dim_name(c: Dictionary) -> String:
	return "D%d" % int(c.get("num", 0))


static func full_name(c: Dictionary, sketch_name: String) -> String:
	return dim_name(c) + "@" + sketch_name


static func valid_var_name(n: String) -> bool:
	var re := RegEx.new()
	re.compile("^[A-Za-zğüşıöçĞÜŞİÖÇ_][" + NAME_CHARS + "]*$")
	return re.search(n) != null


static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		if ch in "\\.^$|?*+()[]{}-/":
			out += "\\" + ch
		else:
			out += ch
	return out


## Belgedeki boyut değerleri (görüntü biriminde).
static func dimension_values(doc: CadDocument) -> Dictionary:
	var ctx := {}
	for f in doc.sketches():
		for c in f.sketch.constraints:
			if Sketch.is_dimension(c):
				var v := float(c.get("value", 0.0))
				ctx[full_name(c, f.name)] = v if c["type"] == "angle" else Units.to_display(v)
	for f in doc.features:
		if f.type == "extrude":
			ctx["D1@" + f.name] = Units.to_display(float(f.params.get("depth", 0.0)))
		elif f.type == "revolve":
			ctx["D1@" + f.name] = float(f.params.get("angle", 360.0))
	return ctx


## İfadeyi verilen adlarla hesaplar. Hata: null.
static func evaluate(expr: String, names: Dictionary) -> Variant:
	var t := expr.strip_edges()
	if t.begins_with("="):
		t = t.substr(1)
	if t.is_empty():
		return null
	if not t.contains("("):
		t = t.replace(",", ".")
	var keys: Array = names.keys()
	keys.sort_custom(func(a, b): return str(a).length() > str(b).length())
	var in_names := PackedStringArray()
	var in_vals: Array = []
	for i in keys.size():
		var k := str(keys[i])
		var ident := "_v%d" % i
		var before := t
		t = t.replace("\"" + k + "\"", ident)
		var re := RegEx.new()
		re.compile("(?<![" + NAME_CHARS + "@])" + _escape(k) + "(?![" + NAME_CHARS + "@])")
		t = re.sub(t, ident, true)
		if t != before:
			in_names.append(ident)
			in_vals.append(float(names[keys[i]]))
	if _int_re == null:
		_int_re = RegEx.new()
		_int_re.compile("(?<![\\d.\\w])(\\d+)(?![\\d.\\w])")
	t = _int_re.sub(t, "$1.0", true)
	var e := Expression.new()
	if e.parse(t, in_names) != OK:
		return null
	var r = e.execute(in_vals, null, false)
	if e.has_execute_failed() or not (typeof(r) == TYPE_FLOAT or typeof(r) == TYPE_INT):
		return null
	var fv := float(r)
	if is_nan(fv) or is_inf(fv):
		return null
	return fv


## Global değişkenleri sırayla hesaplar. Dönüş: {values: {ad: değer}, errors: []}
static func variable_values(doc: CadDocument) -> Dictionary:
	var ctx := dimension_values(doc)
	var vals := {}
	var errors: Array = []
	for v in doc.variables:
		var n := str(v.get("name", ""))
		var r = evaluate(str(v.get("expr", "")), ctx)
		if r == null:
			errors.append(I18n.t("Değişken '%s' hesaplanamadı.") % n)
			continue
		vals[n] = r
		ctx[n] = r
	return {"values": vals, "errors": errors, "ctx": ctx}


## Tüm denklemleri uygular; değişen taslakları çözer. Dönüş: {errors: [], changed: bool}
static func apply(doc: CadDocument) -> Dictionary:
	var errors: Array = []
	var any_changed := false
	for _pass in 2:
		var vv := variable_values(doc)
		if _pass == 0:
			errors.append_array(vv["errors"])
		var ctx: Dictionary = vv["ctx"]
		for f in doc.sketches():
			var changed := false
			for c in f.sketch.constraints:
				var ex := str(c.get("expr", ""))
				if ex == "" or not Sketch.is_dimension(c) or bool(c.get("driven", false)):
					continue
				var r = evaluate(ex, ctx)
				if r == null:
					if _pass == 0:
						errors.append(I18n.t("%s: '%s' hesaplanamadı.") % [full_name(c, f.name), ex])
					continue
				var mm: float = r if c["type"] == "angle" else Units.from_display(r)
				if c["type"] == "angle":
					mm = clampf(mm, 0.001, 179.999)
				else:
					mm = maxf(mm, 1e-4)
				if absf(mm - float(c["value"])) > 1e-9:
					c["value"] = mm
					changed = true
				ctx[full_name(c, f.name)] = r
			if changed:
				any_changed = true
				if not SketchSolver.solve_sketch(f.sketch) and _pass == 1:
					errors.append(I18n.t("%s: denklem değerleri taslağın geometrisiyle çelişiyor.") % f.name)
		for f in doc.features:
			for key in ["depth", "angle"]:
				var ex2 := str(f.params.get(key + "_expr", ""))
				if ex2 == "":
					continue
				var r2 = evaluate(ex2, ctx)
				if r2 == null:
					if _pass == 0:
						errors.append(I18n.t("D1@%s: '%s' hesaplanamadı.") % [f.name, ex2])
					continue
				var val: float = Units.from_display(r2) if key == "depth" else clampf(r2, 0.1, 360.0)
				if absf(val - float(f.params.get(key, 0.0))) > 1e-9:
					f.params[key] = maxf(val, 0.001)
					any_changed = true
	return {"errors": errors, "changed": any_changed}
