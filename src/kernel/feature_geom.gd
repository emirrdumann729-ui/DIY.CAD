class_name FeatureGeom
extends RefCounted
## Çekirdekten bağımsız özellik geometrisi: ekstrüzyon yönü/başlangıcı ve döndürme ekseni.
## CSG ve OpenCASCADE çekirdekleri aynı kuralları kullanır (aynı parametre → aynı katı).

const THROUGH_ALL := 10000.0
## Döndürme yönü: CSGPolygon3D'nin dönüş yönüyle eşleşecek şekilde (OCC ekseni bu işaretle çevrilir).
const OCC_SPIN_SIGN := 1.0


const UNTIL_ENDS := ["next", "face", "face_offset"]


static func extrude_depth(f: CadFeature) -> float:
	var end := str(f.params.get("end", "blind"))
	if end == "through" or end in UNTIL_ENDS:
		return THROUGH_ALL
	return maxf(float(f.params.get("depth", 10.0)), 0.001)


## Ekstrüzyon yönü (birim, dünya): patron normal yönünde, kesme tersine; "reverse" çevirir.
static func extrude_dir(f: CadFeature, plane: SketchPlane) -> Vector3:
	return plane.normal() * (1.0 if extrude_toward_normal(f) else -1.0)


## Patron varsayılan olarak normal yönünde, kesme normalin tersine (malzemeye doğru) gider.
static func extrude_toward_normal(f: CadFeature) -> bool:
	var toward := not f.is_cut()
	if bool(f.params.get("reverse", false)):
		toward = not toward
	return toward


## Dönüş: {offset: profilin taşınacağı vektör, vec: ekstrüzyon vektörü} (dünya koordinatları).
static func extrude_vectors(f: CadFeature, plane: SketchPlane) -> Dictionary:
	var depth := extrude_depth(f)
	var n := plane.normal()
	var end := str(f.params.get("end", "blind"))
	if end == "vertex":
		# Köşeye Kadar: derinlik, seçilen noktanın taslak düzlemine uzaklığı
		var v = f.params.get("vertex")
		if not (v is Array) or (v as Array).size() < 3:
			return {"error": I18n.t("Köşe seçilmedi")}
		var dv := extrude_dir(f, plane)
		var dd := (Vector3(float(v[0]), float(v[1]), float(v[2])) - plane.origin).dot(dv)
		if dd <= 1e-6:
			return {"error": I18n.t("Seçilen köşe ekstrüzyon yönünde değil (yönü ters çevirin)")}
		return {"offset": Vector3.ZERO, "vec": dv * dd}
	if end == "midplane":
		return {"offset": -n * depth * 0.5, "vec": n * depth}
	if extrude_toward_normal(f):
		return {"offset": Vector3.ZERO, "vec": n * depth}
	return {"offset": Vector3.ZERO, "vec": -n * depth}


## Profil konturları (çokgen): bölge seçimi varsa seçili bölgeler, yoksa kapalı konturlar.
static func profile_polys(f: CadFeature, sk_f: CadFeature) -> Array:
	var regions = f.params.get("regions", [])
	if regions is Array and not (regions as Array).is_empty():
		return CsgKernel.region_loops(sk_f.sketch, regions)
	return sk_f.sketch.extract_profiles()["loops"]


## Döndürme çerçevesi. Dönüş: {origin, axis (dünya), a2, ad, perp (taslak), angle} veya {error}.
static func revolve_frame(f: CadFeature, sk_f: CadFeature, loops: Array = [], doc: CadDocument = null) -> Dictionary:
	var p := f.params
	var ax := CsgKernel.revolve_axis(sk_f, p.get("axis", "y"), doc)
	if ax.is_empty():
		return {"error": I18n.t("Döndürme ekseni bulunamadı")}
	var a2: Vector2 = ax[0]
	var ad: Vector2 = (ax[1] - ax[0])
	if ad.length() < 1e-9:
		return {"error": I18n.t("Döndürme ekseni geçersiz")}
	ad = ad.normalized()
	if bool(p.get("reverse", false)):
		ad = -ad
	if loops.is_empty():
		loops = profile_polys(f, sk_f)
	var perp := Vector2(-ad.y, ad.x)
	var side := 0.0
	for L in loops:
		for q in L["poly"]:
			side += (q - a2).dot(perp)
	if side < 0.0:
		perp = -perp
	for L in loops:
		for q in L["poly"]:
			if (q - a2).dot(perp) < -1e-4:
				return {"error": I18n.t("Profil döndürme ekseninin iki tarafında olamaz")}
	var plane := sk_f.plane
	var X3 := plane.dir_to_world(perp)
	var Y3 := plane.dir_to_world(ad)
	# CSG: yerel Y ekseni etrafında dönüş; OCC'de eksen yönü dönüş yönünü belirler (sağ el kuralı)
	return {"origin": plane.to_world(a2), "axis": Y3 * OCC_SPIN_SIGN, "a2": a2, "ad": ad, "perp": perp,
		"x3": X3, "y3": Y3, "angle": clampf(float(p.get("angle", 360.0)), 0.1, 360.0)}
