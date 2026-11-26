class_name Icons
extends RefCounted
## SVG'den üretilen arayüz ikonları (harici dosya gerektirmez).

static var L := "#dfe7f1"   # çizgi rengi (açık temada koyu; UiTheme ayarlar)
const A := "#4f9dff"   # vurgu
const R := "#ff7a6b"   # kesme
const G := "#5cc46a"   # onay

static var _cache := {}


static func clear_cache() -> void:
	_cache.clear()

static func _svg(body: String) -> String:
	return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round">' + body + '</svg>'


## Taslak ilişki rozetleri (yeşil kutucuklar).
static func _rel_body(t: String) -> String:
	var bg := '<rect x="1" y="1" width="22" height="22" rx="4" fill="#47b356" stroke="#1d5a26" stroke-width="1"/>'
	var k := "#0b250f"
	var sym := ""
	match t:
		"horizontal":
			sym = '<path d="M5 12 L19 12" stroke="%s" stroke-width="3"/>' % k
		"vertical":
			sym = '<path d="M12 5 L12 19" stroke="%s" stroke-width="3"/>' % k
		"parallel":
			sym = '<path d="M6 18 L12 6 M12 18 L18 6" stroke="%s" stroke-width="2.4"/>' % k
		"perpendicular":
			sym = '<path d="M12 5 L12 18 M5 18 L19 18" stroke="%s" stroke-width="2.4"/>' % k
		"collinear":
			sym = '<path d="M4 12 L20 12" stroke="%s" stroke-width="1.6"/><circle cx="7" cy="12" r="2.2" fill="%s"/><circle cx="17" cy="12" r="2.2" fill="%s"/>' % [k, k, k]
		"equal":
			sym = '<path d="M6 9 L18 9 M6 15 L18 15" stroke="%s" stroke-width="2.6"/>' % k
		"concentric":
			sym = '<circle cx="12" cy="12" r="7" stroke="%s" stroke-width="2"/><circle cx="12" cy="12" r="3" stroke="%s" stroke-width="2"/>' % [k, k]
		"tangent":
			sym = '<circle cx="12" cy="10" r="5.5" stroke="%s" stroke-width="2"/><path d="M4 18.5 L20 18.5" stroke="%s" stroke-width="2.2"/>' % [k, k]
		"coincident", "merge":
			sym = '<path d="M5 18 L19 6 M5 6 L19 18" stroke="%s" stroke-width="1.4"/><circle cx="12" cy="12" r="3.6" fill="%s"/>' % [k, k]
		"midpoint":
			sym = '<path d="M4 16 L20 16 M4 13 L4 19 M20 13 L20 19" stroke="%s" stroke-width="1.8"/><circle cx="12" cy="16" r="2.6" fill="%s"/><path d="M12 5 L12 11" stroke="%s" stroke-width="1.6"/>' % [k, k, k]
		"symmetric":
			sym = '<path d="M12 4 L12 20" stroke="%s" stroke-width="1.4" stroke-dasharray="2 2"/><path d="M9 7 L4 12 L9 17 Z M15 7 L20 12 L15 17 Z" fill="%s"/>' % [k, k]
		"offset":
			sym = '<path d="M5 18 L5 10 A 5 5 0 0 1 10 5 L19 5" stroke="%s" stroke-width="2"/><path d="M10 19 L10 13 A 3 3 0 0 1 13 10 L19 10" stroke="%s" stroke-width="2"/>' % [k, k]
		"fix":
			sym = '<path d="M8 4 L16 4 L14 10 L17 14 L7 14 L10 10 Z" fill="%s"/><path d="M12 14 L12 21" stroke="%s" stroke-width="2.2"/>' % [k, k]
	return bg + sym


static func _body(icon_name: String) -> String:
	if icon_name.begins_with("rel_"):
		return _rel_body(icon_name.substr(4))
	match icon_name:
		"select":
			return '<path d="M6 3 L6 19 L10 15 L13 21 L15.5 20 L12.5 14 L18 14 Z" fill="%s" stroke="%s" stroke-width="1.2"/>' % [A, L]
		"sketch":
			return '<rect x="3" y="9" width="12" height="11" stroke="%s" stroke-width="1.6"/><path d="M12 14 L20 4 L22 6 L14 16 L11.5 16.5 Z" fill="%s" stroke="%s" stroke-width="1.2"/>' % [L, A, L]
		"exit_sketch":
			return '<rect x="3" y="7" width="12" height="12" stroke="%s" stroke-width="1.6"/><path d="M12 13 L16 17 L22 7" stroke="%s" stroke-width="2.4"/>' % [L, G]
		"line":
			return '<path d="M4 19 L20 5" stroke="%s" stroke-width="2"/><circle cx="4" cy="19" r="2" fill="%s"/><circle cx="20" cy="5" r="2" fill="%s"/>' % [A, L, L]
		"centerline":
			return '<path d="M3 20 L21 4" stroke="%s" stroke-width="1.8" stroke-dasharray="5 2 1 2"/>' % [A]
		"rect":
			return '<rect x="4" y="6" width="16" height="12" stroke="%s" stroke-width="2"/><circle cx="4" cy="18" r="2" fill="%s"/><circle cx="20" cy="6" r="2" fill="%s"/>' % [A, L, L]
		"crect":
			return '<rect x="4" y="6" width="16" height="12" stroke="%s" stroke-width="2"/><path d="M4 18 L20 6" stroke="%s" stroke-width="1" stroke-dasharray="2 2"/><circle cx="12" cy="12" r="2" fill="%s"/>' % [A, L, L]
		"circle":
			return '<circle cx="12" cy="12" r="8" stroke="%s" stroke-width="2"/><circle cx="12" cy="12" r="1.8" fill="%s"/>' % [A, L]
		"arc":
			return '<path d="M5 17 A 9 9 0 0 1 19 9" stroke="%s" stroke-width="2"/><circle cx="12" cy="17" r="1.8" fill="%s"/><path d="M12 17 L5 17 M12 17 L19 9" stroke="%s" stroke-width="0.8" stroke-dasharray="2 2"/>' % [A, L, L]
		"extrude":
			return '<path d="M4 15 L12 19 L20 15 L20 11 L12 15 L4 11 Z" fill="%s" stroke="%s" stroke-width="1.2"/><path d="M4 11 L12 7 L20 11" stroke="%s" stroke-width="1.2"/><path d="M12 13 L12 2 M9 5 L12 2 L15 5" stroke="%s" stroke-width="1.8"/>' % [A, L, L, G]
		"cut":
			return '<path d="M3 12 L12 16 L21 12 L21 17 L12 21 L3 17 Z" fill="%s" stroke="%s" stroke-width="1.2"/><path d="M3 12 L12 8 L21 12" stroke="%s" stroke-width="1.2"/><ellipse cx="12" cy="12" rx="4" ry="2" fill="#1a2230" stroke="%s" stroke-width="1.4"/><path d="M12 9 L12 1 M9.5 6.5 L12 9 L14.5 6.5" stroke="%s" stroke-width="1.8"/>' % [A, L, L, R, R]
		"revolve":
			return '<path d="M12 2 L12 22" stroke="%s" stroke-width="1" stroke-dasharray="3 2"/><path d="M12 5 L17 5 L18 12 L16 19 L12 19" fill="%s" stroke="%s" stroke-width="1.2"/><path d="M4 14 A 8 3 0 0 0 20 14" stroke="%s" stroke-width="1.6"/><path d="M18 12 L20 14 L22 12" stroke="%s" stroke-width="1.6"/>' % [L, A, L, G, G]
		"revcut":
			return '<path d="M12 2 L12 22" stroke="%s" stroke-width="1" stroke-dasharray="3 2"/><path d="M12 5 L17 5 L18 12 L16 19 L12 19" fill="%s" stroke="%s" stroke-width="1.2"/><path d="M4 14 A 8 3 0 0 0 20 14" stroke="%s" stroke-width="1.6"/><path d="M18 12 L20 14 L22 12" stroke="%s" stroke-width="1.6"/>' % [L, R, L, R, R]
		"grid":
			return '<path d="M3 8 L21 8 M3 13 L21 13 M3 18 L21 18 M8 3 L8 21 M13 3 L13 21 M18 3 L18 21" stroke="%s" stroke-width="1"/><circle cx="13" cy="13" r="2.2" fill="%s"/>' % [L, A]
		"delete":
			return '<path d="M6 6 L18 18 M18 6 L6 18" stroke="%s" stroke-width="2.4"/>' % [R]
		"fit":
			return '<rect x="7" y="7" width="10" height="10" fill="%s" stroke="%s" stroke-width="1"/><path d="M3 8 L3 3 L8 3 M16 3 L21 3 L21 8 M21 16 L21 21 L16 21 M8 21 L3 21 L3 16" stroke="%s" stroke-width="1.8"/>' % [A, L, L]
		"plugin":
			return '<path d="M4 9 L9 9 L9 7 A2.2 2.2 0 1 1 13 7 L13 9 L18 9 L18 13 L16 13 A2.2 2.2 0 1 0 16 17 L18 17 L18 21 L4 21 Z" fill="%s" fill-opacity="0.35" stroke="%s" stroke-width="1.5"/>' % [A, L]
		"views":
			return '<path d="M12 3 L20 7.5 L20 16.5 L12 21 L4 16.5 L4 7.5 Z" stroke="%s" stroke-width="1.4"/><path d="M4 7.5 L12 12 L20 7.5 M12 12 L12 21" stroke="%s" stroke-width="1.4"/><path d="M12 12 L20 7.5 L20 16.5 L12 21 Z" fill="%s"/>' % [L, L, A]
		"normal":
			return '<rect x="5" y="5" width="14" height="14" stroke="%s" stroke-width="1.6"/><circle cx="12" cy="12" r="2.5" fill="%s"/><path d="M12 12 L12 12" stroke="%s"/>' % [L, A, L]
		"persp":
			return '<path d="M8 6 L16 6 L21 19 L3 19 Z" stroke="%s" stroke-width="1.6" fill="%s" fill-opacity="0.35"/>' % [L, A]
		"edges":
			return '<path d="M4 16 L12 20 L20 16 L20 8 L12 4 L4 8 Z M4 8 L12 12 L20 8 M12 12 L12 20" stroke="%s" stroke-width="1.8"/>' % [L]
		"planes":
			return '<path d="M3 15 L9 9 L21 9 L15 15 Z" fill="%s" fill-opacity="0.4" stroke="%s" stroke-width="1.4"/>' % [A, L]
		"new":
			return '<path d="M6 3 L14 3 L19 8 L19 21 L6 21 Z" stroke="%s" stroke-width="1.6"/><path d="M14 3 L14 8 L19 8" stroke="%s" stroke-width="1.4"/><path d="M12 11 L12 18 M8.5 14.5 L15.5 14.5" stroke="%s" stroke-width="1.8"/>' % [L, L, A]
		"open":
			return '<path d="M3 6 L9 6 L11 8 L20 8 L20 19 L3 19 Z" stroke="%s" stroke-width="1.6"/><path d="M3 19 L6 11 L22 11 L20 19" fill="%s" fill-opacity="0.5" stroke="%s" stroke-width="1.4"/>' % [L, A, L]
		"save":
			return '<path d="M4 4 L17 4 L20 7 L20 20 L4 20 Z" stroke="%s" stroke-width="1.6"/><rect x="7" y="4" width="9" height="5" fill="%s"/><rect x="7" y="13" width="10" height="7" stroke="%s" stroke-width="1.4"/>' % [L, A, L]
		"undo":
			return '<path d="M9 7 L4 11 L9 15" stroke="%s" stroke-width="1.8"/><path d="M4 11 L14 11 A 6 6 0 0 1 14 23" stroke="%s" stroke-width="1.8"/>' % [A, L]
		"redo":
			return '<path d="M15 7 L20 11 L15 15" stroke="%s" stroke-width="1.8"/><path d="M20 11 L10 11 A 6 6 0 0 0 10 23" stroke="%s" stroke-width="1.8"/>' % [A, L]
		"export":
			return '<path d="M5 14 L5 20 L19 20 L19 14" stroke="%s" stroke-width="1.6"/><path d="M12 15 L12 3 M8 7 L12 3 L16 7" stroke="%s" stroke-width="1.8"/>' % [L, A]
		"plane":
			return '<path d="M3 16 L8 8 L21 8 L16 16 Z" fill="%s" fill-opacity="0.35" stroke="%s" stroke-width="1.4"/>' % [A, L]
		"origin":
			return '<path d="M12 4 L12 20 M4 12 L20 12" stroke="%s" stroke-width="1.6"/><circle cx="12" cy="12" r="3" stroke="%s" stroke-width="1.6"/>' % [A, L]
		"part":
			return '<path d="M4 7.5 L12 3 L20 7.5 L20 16.5 L12 21 L4 16.5 Z" fill="%s" stroke="%s" stroke-width="1.2"/><path d="M4 7.5 L12 12 L20 7.5 M12 12 L12 21" stroke="%s" stroke-width="1.2"/>' % [A, L, L]
		"dimension":
			return '<path d="M4 18 L20 18 M4 14 L4 22 M20 14 L20 22" stroke="%s" stroke-width="1.6"/><path d="M4 18 L8 16 L8 20 Z M20 18 L16 16 L16 20 Z" fill="%s"/><path d="M6 10 L10 3 L13 3 L17 10" stroke="%s" stroke-width="1.6"/><path d="M8.5 7.5 L14.5 7.5" stroke="%s" stroke-width="1.4"/>' % [L, L, A, A]
		"relation":
			return '<rect x="2" y="2" width="20" height="20" rx="4" fill="#3fa34d"/><path d="M6 9 L18 9 M6 15 L18 15" stroke="#0d2b12" stroke-width="2.4"/>'
		"relations_show":
			return '<rect x="2" y="2" width="9" height="9" rx="2" fill="#3fa34d"/><rect x="13" y="13" width="9" height="9" rx="2" fill="#3fa34d"/><path d="M4 6.5 L9 6.5 M17.5 15 L17.5 20" stroke="#0d2b12" stroke-width="1.8"/><path d="M11 6 L18 6 L18 11" stroke="%s" stroke-width="1.2" stroke-dasharray="2 1.5"/>' % [L]
		"measure":
			return '<path d="M3 17 L17 3 L21 7 L7 21 Z" fill="%s" stroke="%s" stroke-width="1.2"/><path d="M7 13 L9 15 M10 10 L12.5 12.5 M13 7 L15 9 M16 4 L18.5 6.5" stroke="#1a2230" stroke-width="1.4"/>' % [A, L]
		"mass":
			return '<path d="M7 9 L17 9 L21 21 L3 21 Z" fill="%s" stroke="%s" stroke-width="1.2"/><circle cx="12" cy="5.5" r="2.8" stroke="%s" stroke-width="1.6"/><path d="M9 13 L9 18 M9 15.5 L12 13 M10 15 L12 18 M17 13.5 A 2.5 2.5 0 1 0 17 17.5 L17 15.5 L15.5 15.5" stroke="#1a2230" stroke-width="1.2"/>' % [A, L, L]
		"material":
			return '<path d="M3 8 L12 3 L21 8 L12 13 Z" fill="#d4a24a" stroke="%s" stroke-width="1"/><path d="M3 12 L12 17 L21 12" stroke="%s" stroke-width="1.6"/><path d="M3 16 L12 21 L21 16" stroke="%s" stroke-width="1.6"/>' % [L, L, A]
		"units":
			return '<path d="M2 15 L22 15 L22 20 L2 20 Z" fill="%s" stroke="%s" stroke-width="1"/><path d="M6 15 L6 18 M10 15 L10 17 M14 15 L14 18 M18 15 L18 17" stroke="#1a2230" stroke-width="1.2"/><path d="M4 4 L4 11 M20 4 L20 11 M4 7.5 L20 7.5 M4 7.5 L7 6 M4 7.5 L7 9 M20 7.5 L17 6 M20 7.5 L17 9" stroke="%s" stroke-width="1.4"/>' % [A, L, L]
		"trim":
			return '<path d="M3 12 L10 12" stroke="%s" stroke-width="2"/><path d="M10 12 L21 12" stroke="%s" stroke-width="2" stroke-dasharray="2 2"/><path d="M10 3 L10 21" stroke="%s" stroke-width="1.6"/><path d="M15 6 L19 10 M19 6 L15 10" stroke="%s" stroke-width="1.8"/>' % [A, R, L, R]
		"extend":
			return '<path d="M3 12 L12 12" stroke="%s" stroke-width="2"/><path d="M12 12 L19 12" stroke="%s" stroke-width="2" stroke-dasharray="2 2"/><path d="M20 3 L20 21" stroke="%s" stroke-width="1.6"/><path d="M15 9 L18 12 L15 15" stroke="%s" stroke-width="1.6"/>' % [A, G, L, G]
		"offset":
			return '<path d="M4 20 L4 9 A 5 5 0 0 1 9 4 L20 4" stroke="%s" stroke-width="1.8"/><path d="M9 20 L9 11 A 2 2 0 0 1 11 9 L20 9" stroke="%s" stroke-width="1.8" stroke-dasharray="3 2"/>' % [L, A]
		"mirror":
			return '<path d="M12 2 L12 22" stroke="%s" stroke-width="1.2" stroke-dasharray="3 2"/><path d="M9 6 L3 12 L9 18 Z" fill="%s"/><path d="M15 6 L21 12 L15 18 Z" stroke="%s" stroke-width="1.4"/>' % [L, A, A]
		"fillet":
			return '<path d="M4 20 L4 12 A 8 8 0 0 1 12 4 L20 4" stroke="%s" stroke-width="2"/><path d="M4 4 L4 9 M4 4 L9 4" stroke="%s" stroke-width="1" stroke-dasharray="1.5 1.5"/>' % [A, L]
		"chamfer":
			return '<path d="M4 20 L4 11 L11 4 L20 4" stroke="%s" stroke-width="2"/><path d="M4 4 L4 9 M4 4 L9 4" stroke="%s" stroke-width="1" stroke-dasharray="1.5 1.5"/>' % [A, L]
		"polygon":
			return '<path d="M12 3 L20 7.5 L20 16.5 L12 21 L4 16.5 L4 7.5 Z" stroke="%s" stroke-width="2"/><circle cx="12" cy="12" r="9" stroke="%s" stroke-width="0.8" stroke-dasharray="2 2"/>' % [A, L]
		"slot":
			return '<path d="M7 7 L17 7 A 5 5 0 0 1 17 17 L7 17 A 5 5 0 0 1 7 7 Z" stroke="%s" stroke-width="2"/><path d="M7 12 L17 12" stroke="%s" stroke-width="0.8" stroke-dasharray="2 2"/>' % [A, L]
		"spline":
			return '<path d="M3 18 C 7 2, 12 22, 21 6" stroke="%s" stroke-width="2"/><circle cx="3" cy="18" r="1.6" fill="%s"/><circle cx="12" cy="12.5" r="1.6" fill="%s"/><circle cx="21" cy="6" r="1.6" fill="%s"/>' % [A, L, L, L]
		"text":
			return '<path d="M5 5 L19 5 M12 5 L12 20 M9 20 L15 20" stroke="%s" stroke-width="2.4"/>' % [A]
		"ellipse":
			return '<ellipse cx="12" cy="12" rx="9" ry="5.5" stroke="%s" stroke-width="2"/><circle cx="12" cy="12" r="1.6" fill="%s"/><path d="M12 12 L21 12" stroke="%s" stroke-width="0.8" stroke-dasharray="2 1.5"/>' % [A, L, L]
		"parabola":
			return '<path d="M4 4 Q 12 28 20 4" stroke="%s" stroke-width="2"/><circle cx="12" cy="10" r="1.6" fill="%s"/><circle cx="12" cy="16" r="1.4" fill="%s"/>' % [A, L, L]
		"convert":
			return '<path d="M3 15 L9 9 L21 9 L15 15 Z" fill="%s" fill-opacity="0.35" stroke="%s" stroke-width="1.2"/><path d="M5 21 L11 15 L21 15" stroke="%s" stroke-width="2"/><path d="M12 10 L12 14 M10 12.5 L12 14.5 L14 12.5" stroke="%s" stroke-width="1.4"/>' % [L, L, A, G]
		"block":
			return '<rect x="3" y="3" width="18" height="18" stroke="%s" stroke-width="1.2" stroke-dasharray="3 2"/><rect x="7" y="9" width="10" height="6" stroke="%s" stroke-width="2"/><circle cx="12" cy="12" r="1.2" fill="%s"/>' % [G, A, L]
		"sketch3d":
			return '<path d="M4 18 L11 14 L11 5 M11 14 L20 18" stroke="%s" stroke-width="1" stroke-dasharray="2 1.5"/><path d="M5 16 L10 9 L16 12 L19 5" stroke="%s" stroke-width="2"/><circle cx="10" cy="9" r="1.5" fill="%s"/><circle cx="16" cy="12" r="1.5" fill="%s"/>' % [L, A, L, L]
		"fillet3d":
			return '<path d="M3 9 L13 9 L13 21 L3 21 Z" stroke="%s" stroke-width="1.4"/><path d="M3 9 L9 3 L21 3 L21 15 L13 21 M13 9 L21 3" stroke="%s" stroke-width="1.4"/><path d="M13 13 A 4 4 0 0 1 17 9 M13 9 L13 13" stroke="%s" stroke-width="2.4"/>' % [L, L, A]
		"chamfer3d":
			return '<path d="M3 9 L13 9 L13 21 L3 21 Z" stroke="%s" stroke-width="1.4"/><path d="M3 9 L9 3 L21 3 L21 15 L13 21 M13 9 L21 3" stroke="%s" stroke-width="1.4"/><path d="M13 13.5 L17.5 9" stroke="%s" stroke-width="2.6"/>' % [L, L, A]
		"shell":
			return '<path d="M3 8 L12 3 L21 8 L21 17 L12 22 L3 17 Z" stroke="%s" stroke-width="1.6"/><path d="M6 9.5 L12 6.3 L18 9.5 L18 15.5 L12 18.8 L6 15.5 Z" stroke="%s" stroke-width="1.6"/><path d="M12 6.3 L12 3" stroke="%s" stroke-width="1"/>' % [L, A, L]
		"import":
			return '<path d="M4 15 L4 20 L20 20 L20 15" stroke="%s" stroke-width="2"/><path d="M12 3 L12 15 M7 10 L12 15 L17 10" stroke="%s" stroke-width="2.2"/>' % [L, A]
		"step":
			return '<path d="M4 4 L14 4 L20 10 L20 20 L4 20 Z" stroke="%s" stroke-width="1.6"/><path d="M14 4 L14 10 L20 10" stroke="%s" stroke-width="1.4"/><path d="M8 16 L11 13 L13 15 L16 12" stroke="%s" stroke-width="2"/>' % [L, L, A]
		"draft":
			return '<path d="M4 20 L20 20 L17 6 L7 6 Z" stroke="%s" stroke-width="1.8"/><path d="M7 6 L7 20 M17 6 L17 20" stroke="%s" stroke-width="1" stroke-dasharray="1.5 1.5"/><path d="M12 3 L12 9 M10 5 L12 3 L14 5" stroke="%s" stroke-width="1.6"/>' % [A, L, L]
		"rib":
			return '<path d="M3 21 L21 21 L21 17 L7 17 L7 3 L3 3 Z" stroke="%s" stroke-width="1.6"/><path d="M7 7 L17 17 L7 17 Z" fill="%s" stroke="%s" stroke-width="1"/>' % [L, A, A]
		"combine":
			return '<rect x="3" y="7" width="11" height="11" stroke="%s" stroke-width="1.6"/><circle cx="15" cy="10" r="6" stroke="%s" stroke-width="1.6"/><path d="M14 7 L14 15" stroke="%s" stroke-width="1"/>' % [L, A, A]
		"move_body":
			return '<rect x="3" y="11" width="9" height="9" stroke="%s" stroke-width="1.4" stroke-dasharray="2 1.5"/><rect x="11" y="4" width="9" height="9" stroke="%s" stroke-width="1.8"/><path d="M8 11 L13 8" stroke="%s" stroke-width="1.2"/>' % [L, A, L]
		"split":
			return '<path d="M3 8 L11 8 L11 20 L3 20 Z M13 8 L21 8 L21 20 L13 20 Z" stroke="%s" stroke-width="1.6"/><path d="M12 3 L12 22" stroke="%s" stroke-width="1.8" stroke-dasharray="3 2"/>' % [L, A]
		"sweep":
			return '<path d="M4 18 C 8 18, 10 6, 20 6" stroke="%s" stroke-width="1" stroke-dasharray="2 1.5"/><ellipse cx="5" cy="17" rx="2.5" ry="4" stroke="%s" stroke-width="1.8"/><ellipse cx="19" cy="6" rx="2" ry="3.2" stroke="%s" stroke-width="1.6"/><path d="M5 13 C 9 13, 11 3, 19 3 M5 21 C 10 21, 12 9, 19 9" stroke="%s" stroke-width="1.4"/>' % [L, A, A, A]
		"sweepcut":
			return '<path d="M4 18 C 8 18, 10 6, 20 6" stroke="%s" stroke-width="1" stroke-dasharray="2 1.5"/><ellipse cx="5" cy="17" rx="2.5" ry="4" stroke="%s" stroke-width="1.8"/><path d="M5 13 C 9 13, 11 3, 19 3 M5 21 C 10 21, 12 9, 19 9" stroke="%s" stroke-width="1.4"/>' % [L, R, R]
		"loft":
			return '<rect x="3" y="15" width="12" height="6" stroke="%s" stroke-width="1.6"/><circle cx="15" cy="6" r="3.5" stroke="%s" stroke-width="1.6"/><path d="M3 15 L11.5 6 M15 15 L18.5 6" stroke="%s" stroke-width="1.2"/>' % [A, A, L]
		"loftcut":
			return '<rect x="3" y="15" width="12" height="6" stroke="%s" stroke-width="1.6"/><circle cx="15" cy="6" r="3.5" stroke="%s" stroke-width="1.6"/><path d="M3 15 L11.5 6 M15 15 L18.5 6" stroke="%s" stroke-width="1.2"/>' % [R, R, L]
		"refplane":
			return '<path d="M3 16 L9 6 L21 6 L15 16 Z" stroke="%s" stroke-width="1.8"/><path d="M5 20 L11 10" stroke="%s" stroke-width="1" stroke-dasharray="1.5 1.5"/>' % [A, L]
		"refaxis":
			return '<path d="M4 20 L20 4" stroke="%s" stroke-width="1.8" stroke-dasharray="5 2 1 2"/>' % A
		"refpoint":
			return '<path d="M12 4 L12 20 M4 12 L20 12" stroke="%s" stroke-width="1" /><circle cx="12" cy="12" r="3" fill="%s"/>' % [L, A]
		"helix":
			return '<path d="M6 20 C 18 19, 18 16, 6 15 C 18 14, 18 11, 6 10 C 18 9, 18 6, 6 5" stroke="%s" stroke-width="1.8"/>' % A
		"lpattern":
			return '<rect x="3" y="9" width="5" height="6" stroke="%s" stroke-width="1.8"/><rect x="10" y="9" width="5" height="6" stroke="%s" stroke-width="1.3" stroke-dasharray="2 1"/><rect x="17" y="9" width="5" height="6" stroke="%s" stroke-width="1.3" stroke-dasharray="2 1"/>' % [A, L, L]
		"cpattern":
			return '<circle cx="12" cy="12" r="7" stroke="%s" stroke-width="0.9" stroke-dasharray="2 1.5"/><circle cx="12" cy="5" r="2.2" fill="%s"/><circle cx="19" cy="12" r="2" stroke="%s" stroke-width="1.2"/><circle cx="12" cy="19" r="2" stroke="%s" stroke-width="1.2"/><circle cx="5" cy="12" r="2" stroke="%s" stroke-width="1.2"/>' % [L, A, L, L, L]
		"mirror3d":
			return '<path d="M12 3 L12 21" stroke="%s" stroke-width="1.2" stroke-dasharray="3 2"/><path d="M10 6 L4 9 L4 17 L10 19 Z" fill="%s" stroke="%s" stroke-width="1.2"/><path d="M14 6 L20 9 L20 17 L14 19 Z" stroke="%s" stroke-width="1.2" stroke-dasharray="2 1"/>' % [L, A, A, L]
		"tpattern":
			return '<path d="M3 4 L21 4 M3 9 L21 9 M3 14 L21 14 M3 19 L21 19 M9 4 L9 19" stroke="%s" stroke-width="1"/><circle cx="15" cy="11.5" r="2.4" fill="%s"/>' % [L, A]
		"hole":
			return '<path d="M3 8 L21 8 L21 20 L3 20 Z" stroke="%s" stroke-width="1.4"/><path d="M8 8 L8 11 L10 11 L10 20 M16 8 L16 11 L14 11 L14 20" stroke="%s" stroke-width="1.8"/>' % [L, A]
		"dome":
			return '<path d="M3 19 L21 19" stroke="%s" stroke-width="1.6"/><path d="M4 19 C 4 9, 20 9, 20 19" stroke="%s" stroke-width="1.8"/>' % [L, A]
		"refcsys":
			return '<path d="M5 19 L19 19" stroke="#ff6b6b" stroke-width="2"/><path d="M5 19 L5 5" stroke="#5cc46a" stroke-width="2"/><path d="M5 19 L13 11" stroke="%s" stroke-width="2"/><circle cx="5" cy="19" r="1.8" fill="%s"/>' % [A, L]
		"projcurve":
			return '<path d="M3 6 L21 6" stroke="%s" stroke-width="1.2" stroke-dasharray="2 1.5"/><path d="M8 6 L8 13 M16 6 L16 13" stroke="%s" stroke-width="0.9"/><path d="M3 18 C 8 12, 16 12, 21 18" stroke="%s" stroke-width="2"/>' % [L, L, A]
		"cvpattern":
			return '<path d="M3 18 C 8 4, 16 4, 21 18" stroke="%s" stroke-width="1" stroke-dasharray="2 1.5"/><circle cx="4.5" cy="15" r="2.2" fill="%s"/><circle cx="9" cy="8.5" r="2" stroke="%s" stroke-width="1.2"/><circle cx="15" cy="8.5" r="2" stroke="%s" stroke-width="1.2"/><circle cx="19.5" cy="15" r="2" stroke="%s" stroke-width="1.2"/>' % [L, A, L, L, L]
		"wrap":
			return '<ellipse cx="12" cy="5" rx="7" ry="2.5" stroke="%s" stroke-width="1.4"/><path d="M5 5 L5 19 M19 5 L19 19" stroke="%s" stroke-width="1.4"/><path d="M5 19 A 7 2.5 0 0 0 19 19" stroke="%s" stroke-width="1.4"/><path d="M9 9 L13 9 L13 15 L9 15 Z" fill="%s"/>' % [L, L, L, A]
		"emboss":
			return '<path d="M3 17 L21 17" stroke="%s" stroke-width="1.6"/><path d="M7 17 L7 11 L11 11 L11 13 L13 13 L13 11 L17 11 L17 17" stroke="%s" stroke-width="2"/>' % [L, A]
		"kernel":
			return '<path d="M12 2 L21 7 L21 17 L12 22 L3 17 L3 7 Z" stroke="%s" stroke-width="1.6"/><path d="M3 7 L12 12 L21 7 M12 12 L12 22" stroke="%s" stroke-width="1.6"/>' % [L, A]
		"region":
			return '<circle cx="9" cy="12" r="6.5" stroke="%s" stroke-width="1.4"/><circle cx="15" cy="12" r="6.5" stroke="%s" stroke-width="1.4"/><path d="M12 6.8 A 6.5 6.5 0 0 1 12 17.2 A 6.5 6.5 0 0 1 12 6.8 Z" fill="%s"/>' % [L, L, A]
		"pattern":
			return '<rect x="3" y="3" width="6" height="6" stroke="%s" stroke-width="1.6"/><rect x="15" y="3" width="6" height="6" stroke="%s" stroke-width="1.4" stroke-dasharray="2 1"/><rect x="3" y="15" width="6" height="6" stroke="%s" stroke-width="1.4" stroke-dasharray="2 1"/><rect x="15" y="15" width="6" height="6" stroke="%s" stroke-width="1.4" stroke-dasharray="2 1"/>' % [A, L, L, L]
		"equations":
			return '<path d="M18 6 L18 4 L6 4 L13 12 L6 20 L18 20 L18 18" stroke="%s" stroke-width="2.4"/>' % [A]
		"warning":
			return '<path d="M12 3 L22 20 L2 20 Z" fill="#e5a400" stroke="#1a1a1a" stroke-width="1"/><path d="M12 9 L12 14 M12 16.5 L12 17" stroke="#1a1a1a" stroke-width="2"/>'
		# --- Teknik resim (Faz 6)
		"dw_sheet":
			return '<rect x="2" y="4" width="20" height="16" stroke="%s" stroke-width="1.5"/><rect x="12" y="15" width="9" height="4" stroke="%s" stroke-width="1.2"/><path d="M5 7 L9 7 L9 11 L5 11 Z" stroke="%s" stroke-width="1.2"/>' % [L, A, L]
		"dw_std3":
			return '<rect x="3" y="12" width="7" height="8" stroke="%s" stroke-width="1.6"/><rect x="3" y="3" width="7" height="6" stroke="%s" stroke-width="1.2"/><rect x="13" y="12" width="6" height="8" stroke="%s" stroke-width="1.2"/><path d="M14 3 L19 3 L21 5 L21 9 L16 9 L14 7 Z" stroke="%s" stroke-width="1.2"/>' % [A, L, L, L]
		"dw_model":
			return '<path d="M12 3 L20 7 L20 16 L12 20 L4 16 L4 7 Z" stroke="%s" stroke-width="1.5"/><path d="M4 7 L12 11 L20 7 M12 11 L12 20" stroke="%s" stroke-width="1.5"/>' % [L, A]
		"dw_proj":
			return '<rect x="3" y="8" width="8" height="10" stroke="%s" stroke-width="1.6"/><rect x="15" y="8" width="6" height="10" stroke="%s" stroke-width="1.2" stroke-dasharray="2 1"/><path d="M11 13 L15 13" stroke="%s" stroke-width="1.2"/>' % [A, L, L]
		"dw_section":
			return '<rect x="5" y="5" width="14" height="14" stroke="%s" stroke-width="1.5"/><path d="M5 11 L11 5 M5 17 L17 5 M9 19 L19 9 M15 19 L19 15" stroke="%s" stroke-width="1"/><path d="M2 12 L22 12" stroke="#ff7a6b" stroke-width="1.6" stroke-dasharray="4 1.5 1 1.5"/>' % [L, A]
		"dw_detail":
			return '<circle cx="9" cy="10" r="6" stroke="%s" stroke-width="1.5" stroke-dasharray="3 1.5"/><circle cx="17" cy="16" r="5" stroke="%s" stroke-width="1.8"/><path d="M13.5 13 L14.5 13.5" stroke="%s" stroke-width="1"/>' % [L, A, L]
		"dw_aux":
			return '<path d="M3 18 L11 18 L11 10 Z" stroke="%s" stroke-width="1.5"/><path d="M13 9 L18 4 L22 8 L17 13 Z" stroke="%s" stroke-width="1.6"/><path d="M8 13 L14 8" stroke="%s" stroke-width="1" stroke-dasharray="2 1"/>' % [L, A, L]
		"dw_break":
			return '<path d="M2 8 L9 8 M2 16 L9 16 M15 8 L22 8 M15 16 L22 16" stroke="%s" stroke-width="1.6"/><path d="M9 5 L10 10 L8 14 L9 19 M15 5 L16 10 L14 14 L15 19" stroke="%s" stroke-width="1.4"/>' % [L, A]
		"dw_modeldims":
			return '<path d="M4 8 L4 20 M20 8 L20 20" stroke="%s" stroke-width="1"/><path d="M4 12 L20 12" stroke="%s" stroke-width="1.4"/><path d="M4 12 L7 10.5 L7 13.5 Z M20 12 L17 10.5 L17 13.5 Z" fill="%s"/><path d="M9 3 L15 3 L12 7 Z" fill="%s"/>' % [L, A, A, G]
		"dw_cmark":
			return '<circle cx="12" cy="12" r="7" stroke="%s" stroke-width="1.5"/><path d="M12 2 L12 9 M12 11 L12 13 M12 15 L12 22 M2 12 L9 12 M11 12 L13 12 M15 12 L22 12" stroke="%s" stroke-width="1.2"/>' % [L, A]
		"dw_balloon":
			return '<circle cx="15" cy="9" r="6" stroke="%s" stroke-width="1.6"/><path d="M10.5 13 L4 20" stroke="%s" stroke-width="1.3"/><circle cx="4" cy="20" r="1.3" fill="%s"/><path d="M14 6.5 L15.5 5.5 L15.5 12.5" stroke="%s" stroke-width="1.4"/>' % [A, L, L, L]
		"dw_surface":
			return '<path d="M3 13 L7 20 L15 4 L22 4" stroke="%s" stroke-width="1.6"/><path d="M5 13 L10 13" stroke="%s" stroke-width="1.6"/><path d="M15 8 L21 8" stroke="%s" stroke-width="1"/>' % [A, A, L]
		"dw_gdt":
			return '<rect x="2" y="7" width="20" height="10" stroke="%s" stroke-width="1.4"/><path d="M9 7 L9 17 M16 7 L16 17" stroke="%s" stroke-width="1.2"/><circle cx="5.5" cy="12" r="2.3" stroke="%s" stroke-width="1.2"/><path d="M5.5 9 L5.5 15 M2.5 12 L8.5 12" stroke="%s" stroke-width="0.9"/>' % [L, L, A, A]
		"dw_datum":
			return '<rect x="7" y="3" width="10" height="9" stroke="%s" stroke-width="1.4"/><path d="M12 12 L12 16" stroke="%s" stroke-width="1.3"/><path d="M8 21 L12 16 L16 21 Z" fill="%s"/><path d="M10 10 L12 5 L14 10 M10.8 8 L13.2 8" stroke="%s" stroke-width="1.1"/>' % [L, L, A, A]
		"dw_weld":
			return '<path d="M3 20 L9 14 L21 14" stroke="%s" stroke-width="1.4"/><path d="M3 20 L4.5 16.5 L6.5 18.5 Z" fill="%s"/><path d="M13 14 L13 8 L19 14" stroke="%s" stroke-width="1.6"/>' % [L, L, A]
		"dw_bom":
			return '<rect x="3" y="4" width="18" height="16" stroke="%s" stroke-width="1.4"/><path d="M3 8 L21 8 M3 12 L21 12 M3 16 L21 16 M8 4 L8 20" stroke="%s" stroke-width="1"/><path d="M3 4 L21 4 L21 8 L3 8 Z" fill="%s"/>' % [L, L, A]
		"dw_rev":
			return '<rect x="3" y="4" width="18" height="12" stroke="%s" stroke-width="1.4"/><path d="M3 10 L21 10 M8 4 L8 16" stroke="%s" stroke-width="1"/><path d="M12 18 L12 22 M10 20 L14 20" stroke="%s" stroke-width="1.8"/>' % [L, L, G]
		"dw_pdf", "dw_svg", "dw_dxf":
			var tag: String = {"dw_pdf": "PDF", "dw_svg": "SVG", "dw_dxf": "DXF"}[icon_name]
			return '<path d="M5 2 L15 2 L20 7 L20 22 L5 22 Z" stroke="%s" stroke-width="1.4"/><path d="M15 2 L15 7 L20 7" stroke="%s" stroke-width="1.2"/><rect x="2" y="11" width="17" height="7" rx="1" fill="%s"/><text x="10.5" y="16.6" font-size="5.6" font-family="sans-serif" font-weight="bold" text-anchor="middle" fill="#ffffff">%s</text>' % [L, L, A, tag]
		# --- Montaj (Faz 7)
		"assembly":
			return '<path d="M3 9 L9 6 L15 9 L9 12 Z" stroke="%s" stroke-width="1.3"/><path d="M3 9 L3 15 L9 18 L9 12 M15 9 L15 15 L9 18" stroke="%s" stroke-width="1.3"/><path d="M13 13 L18 10.5 L22 12.5 L22 18 L17 20.5 L13 18.5 Z" fill="%s" stroke="%s" stroke-width="1"/>' % [L, L, A, L]
		"asm_insert":
			return '<path d="M4 9 L10 6 L16 9 L10 12 Z M4 9 L4 15 L10 18 L10 12 M16 9 L16 15 L10 18" stroke="%s" stroke-width="1.3"/><path d="M18 3 L18 11 M14 7 L22 7" stroke="%s" stroke-width="2.2"/>' % [L, G]
		"asm_mate":
			return '<rect x="3" y="13" width="12" height="7" stroke="%s" stroke-width="1.4"/><rect x="9" y="4" width="12" height="7" fill="%s" stroke="%s" stroke-width="1"/><path d="M9 13 L15 11" stroke="%s" stroke-width="1.6" stroke-dasharray="2 1.5"/>' % [L, A, L, G]
		"asm_move":
			return '<path d="M12 2 L12 22 M2 12 L22 12" stroke="%s" stroke-width="1.6"/><path d="M12 2 L9 5 M12 2 L15 5 M12 22 L9 19 M12 22 L15 19 M2 12 L5 9 M2 12 L5 15 M22 12 L19 9 M22 12 L19 15" stroke="%s" stroke-width="1.6"/><rect x="9" y="9" width="6" height="6" fill="%s"/>' % [L, L, A]
		"asm_rotate":
			return '<path d="M19 12 A 7 7 0 1 1 15.5 6" stroke="%s" stroke-width="1.8"/><path d="M15 2.5 L16 6.5 L12 7.5" stroke="%s" stroke-width="1.8"/><rect x="9.5" y="9.5" width="5" height="5" fill="%s"/>' % [L, L, A]
		"asm_fix":
			return '<path d="M8 3 L16 3 L14 10 L17 14 L7 14 L10 10 Z" fill="%s" stroke="%s" stroke-width="1"/><path d="M12 14 L12 21" stroke="%s" stroke-width="2"/>' % [A, L, L]
		"asm_hide":
			return '<path d="M2 12 C 6 5, 18 5, 22 12 C 18 19, 6 19, 2 12 Z" stroke="%s" stroke-width="1.5"/><circle cx="12" cy="12" r="3" fill="%s"/><path d="M4 20 L20 4" stroke="%s" stroke-width="1.6"/>' % [L, A, R]
		"asm_interf":
			return '<rect x="3" y="7" width="11" height="11" stroke="%s" stroke-width="1.4"/><rect x="10" y="3" width="11" height="11" stroke="%s" stroke-width="1.4"/><rect x="10" y="7" width="4" height="7" fill="%s"/>' % [L, L, R]
		"asm_explode":
			return '<rect x="8" y="9" width="8" height="6" fill="%s"/><rect x="8" y="2" width="8" height="3" stroke="%s" stroke-width="1.2"/><rect x="8" y="19" width="8" height="3" stroke="%s" stroke-width="1.2"/><path d="M12 5 L12 9 M12 15 L12 19" stroke="%s" stroke-width="1" stroke-dasharray="1.5 1"/>' % [A, L, L, "#ffb24a"]
		"asm_explode_toggle":
			return '<path d="M4 12 L9 12 M15 12 L20 12" stroke="%s" stroke-width="1.6"/><path d="M4 12 L7 9 M4 12 L7 15 M20 12 L17 9 M20 12 L17 15" stroke="%s" stroke-width="1.6"/><rect x="9" y="8" width="6" height="8" fill="%s"/>' % [L, L, A]
		"asm_motion":
			return '<circle cx="9" cy="12" r="6" stroke="%s" stroke-width="1.5"/><circle cx="18" cy="12" r="3.5" stroke="%s" stroke-width="1.5"/><path d="M7 9.5 L12 12 L7 14.5 Z" fill="%s"/>' % [L, L, G]
		"asm_bom":
			return '<rect x="3" y="3" width="18" height="18" stroke="%s" stroke-width="1.4"/><path d="M3 8 L21 8 M3 13 L21 13 M3 18 L21 18 M8 3 L8 21 M17 3 L17 21" stroke="%s" stroke-width="1"/><path d="M3 3 L21 3 L21 8 L3 8 Z" fill="%s"/>' % [L, L, A]
		"asm_mass":
			return '<path d="M6 9 L18 9 L21 21 L3 21 Z" stroke="%s" stroke-width="1.5"/><circle cx="12" cy="6" r="2.5" stroke="%s" stroke-width="1.5"/><path d="M9 16 L15 16" stroke="%s" stroke-width="2"/>' % [L, L, A]
		"asm_open":
			return '<path d="M3 7 L10 4 L17 7 L10 10 Z M3 7 L3 15 L10 18 L10 10 M17 7 L17 10" stroke="%s" stroke-width="1.3"/><path d="M13 21 L20 14 M16 14 L20 14 L20 18" stroke="%s" stroke-width="1.8"/>' % [L, A]
		"asm_toolbox":
			return '<path d="M9 3 L15 3 L17 6.5 L15 10 L9 10 L7 6.5 Z" fill="%s" stroke="%s" stroke-width="1"/><path d="M10 10 L10 21 M14 10 L14 21 M10 13 L14 12 M10 16 L14 15 M10 19 L14 18" stroke="%s" stroke-width="1.2"/>' % [A, L, L]
		"asm_pattern":
			return '<rect x="2" y="9" width="6" height="6" fill="%s"/><rect x="9" y="9" width="6" height="6" stroke="%s" stroke-width="1.3" stroke-dasharray="2 1"/><rect x="16" y="9" width="6" height="6" stroke="%s" stroke-width="1.3" stroke-dasharray="2 1"/><path d="M5 5 L19 5 M16 3 L19 5 L16 7" stroke="%s" stroke-width="1.2"/>' % [A, L, L, L]
		"asm_newpart":
			return '<path d="M3 8 L10 5 L17 8 L10 11 Z M3 8 L3 15 L10 18 L10 11 M17 8 L17 12" stroke="%s" stroke-width="1.3" stroke-dasharray="2 1"/><path d="M18 13 L18 21 M14 17 L22 17" stroke="%s" stroke-width="2.2"/>' % [L, G]
		"dw_autoballoon":
			return '<circle cx="7" cy="7" r="4" stroke="%s" stroke-width="1.4"/><circle cx="17" cy="9" r="4" stroke="%s" stroke-width="1.4"/><circle cx="10" cy="18" r="4" fill="%s"/><path d="M6 6 L7 5.5 L7 9" stroke="%s" stroke-width="1"/>' % [L, L, A, L]
		# --- Faz 8
		"sm_base":
			return '<path d="M3 15 L13 9 L21 13 L11 19 Z" fill="%s" stroke="%s" stroke-width="1"/><path d="M3 15 L3 17 L11 21 L21 15 L21 13" stroke="%s" stroke-width="1.2"/>' % [A, L, L]
		"sm_edge":
			return '<path d="M3 17 L13 12 L21 15 L11 20 Z" stroke="%s" stroke-width="1.2"/><path d="M13 12 C 15 11, 16 9, 16 7 L16 3 L19 4 L19 8 C 19 11, 20 13, 21 15" fill="%s" stroke="%s" stroke-width="1"/>' % [L, A, L]
		"sm_flat":
			return '<path d="M2 15 L12 10 L22 14 L12 19 Z" stroke="%s" stroke-width="1.3"/><path d="M7 12.5 L17 16.5" stroke="%s" stroke-width="1.2" stroke-dasharray="2 1.5"/><path d="M12 3 L12 8 M10 6 L12 8 L14 6" stroke="%s" stroke-width="1.4"/>' % [L, A, G]
		"sm_dxf":
			return '<path d="M3 6 L21 6 L21 18 L3 18 Z" stroke="%s" stroke-width="1.3"/><path d="M9 6 L9 18 M15 6 L15 18" stroke="%s" stroke-width="1.1" stroke-dasharray="2 1.5"/><rect x="5" y="14" width="14" height="6" rx="1" fill="%s"/>' % [L, A, A]
		"weld":
			return '<rect x="3" y="3" width="5" height="18" stroke="%s" stroke-width="1.4"/><rect x="8" y="3" width="13" height="5" fill="%s" stroke="%s" stroke-width="1"/><path d="M8 8 L11 11" stroke="#ffb24a" stroke-width="2"/>' % [L, A, L]
		"weld_cutlist":
			return '<rect x="3" y="3" width="18" height="18" stroke="%s" stroke-width="1.3"/><path d="M6 8 L18 8 M6 12 L18 12 M6 16 L14 16" stroke="%s" stroke-width="1.5"/><path d="M15 15 L19 19 M19 15 L15 19" stroke="%s" stroke-width="1.2"/>' % [L, A, L]
		"configs":
			return '<rect x="3" y="4" width="8" height="7" stroke="%s" stroke-width="1.3"/><rect x="13" y="4" width="8" height="7" fill="%s"/><rect x="3" y="13" width="8" height="7" fill="%s"/><rect x="13" y="13" width="8" height="7" stroke="%s" stroke-width="1.3"/>' % [L, A, A, L]
		"srf_extrude":
			return '<path d="M4 16 C 8 12, 12 18, 16 14 L20 10 L20 4 C 16 8, 12 2, 8 6 L4 10 Z" fill="%s" fill-opacity="0.5" stroke="%s" stroke-width="1.2"/>' % [A, L]
		"srf_revolve":
			return '<path d="M5 6 C 5 3, 19 3, 19 6 L17 18 C 17 21, 7 21, 7 18 Z" fill="%s" fill-opacity="0.45" stroke="%s" stroke-width="1.2"/><path d="M12 2 L12 22" stroke="%s" stroke-width="1" stroke-dasharray="3 1.5"/>' % [A, L, L]
		"srf_loft":
			return '<path d="M4 18 L10 20 L10 8 L4 6 Z M14 16 C 17 15, 20 13, 20 10 C 20 7, 17 5, 14 4" stroke="%s" stroke-width="1.3"/><path d="M10 8 C 12 6, 13 5, 14 4 M10 20 C 12 18, 13 17, 14 16" stroke="%s" stroke-width="1.3"/>' % [L, A]
		"srf_planar":
			return '<path d="M3 15 L12 9 L21 13 L12 19 Z" fill="%s" fill-opacity="0.55" stroke="%s" stroke-width="1.2"/>' % [A, L]
		"srf_offset":
			return '<path d="M3 17 C 8 12, 14 20, 21 14" stroke="%s" stroke-width="1.4"/><path d="M3 11 C 8 6, 14 14, 21 8" stroke="%s" stroke-width="1.6"/>' % [L, A]
		"srf_knit":
			return '<path d="M3 15 L11 11 L11 19 Z" fill="%s" fill-opacity="0.5" stroke="%s" stroke-width="1"/><path d="M13 11 L21 7 L21 15 L13 19 Z" fill="%s" fill-opacity="0.5" stroke="%s" stroke-width="1"/><path d="M11.5 12 L12.5 13 M11.5 15 L12.5 16" stroke="%s" stroke-width="1.6"/>' % [A, L, A, L, G]
		"srf_thicken":
			return '<path d="M3 12 L12 7 L21 11 L12 16 Z" fill="%s" fill-opacity="0.55" stroke="%s" stroke-width="1"/><path d="M3 12 L3 16 L12 20 L21 15 L21 11 M12 16 L12 20" stroke="%s" stroke-width="1.2"/>' % [A, L, L]
		"srf_trim":
			return '<path d="M3 15 C 8 10, 14 18, 21 12" stroke="%s" stroke-width="1.6"/><path d="M14 3 L14 21" stroke="%s" stroke-width="1.3" stroke-dasharray="2 1.5"/><path d="M17 14 L21 18 M21 14 L17 18" stroke="%s" stroke-width="1.3"/>' % [A, L, R]
		"sm_hem":
			return '<path d="M3 17 L15 17 C 19 17, 19 11, 15 11 L8 11" stroke="%s" stroke-width="2.2"/>' % [A]
		"fea":
			return '<path d="M3 18 L21 18 L21 14 L3 6 Z" fill="%s" fill-opacity="0.35" stroke="%s" stroke-width="1.2"/><path d="M5 18 L5 14 M9 18 L9 13 M13 18 L13 12 M17 18 L17 11" stroke="%s" stroke-width="0.8"/><path d="M19 3 L19 10 M17 8 L19 10 L21 8" stroke="#ff7a6b" stroke-width="1.6"/>' % [A, L, L]
		"draft_an":
			return '<path d="M5 20 L8 6 L16 6 L19 20 Z" stroke="%s" stroke-width="1.3"/><path d="M5 20 L8 6" stroke="#5cc46a" stroke-width="2"/><path d="M19 20 L16 6" stroke="#ff7a6b" stroke-width="2"/><path d="M12 2 L12 9 M10 4 L12 2 L14 4" stroke="%s" stroke-width="1.4"/>' % [L, A]
		"cam":
			return '<rect x="9" y="2" width="6" height="9" stroke="%s" stroke-width="1.3"/><path d="M10 11 L12 15 L14 11" fill="%s"/><path d="M3 19 L7 17 L11 19 L15 17 L21 19" stroke="#ffb24a" stroke-width="1.6"/>' % [L, A]
		"render":
			return '<circle cx="12" cy="12" r="7" fill="%s"/><circle cx="9.5" cy="9.5" r="2.2" fill="#ffffff" fill-opacity="0.8"/><path d="M4 21 L20 21" stroke="%s" stroke-width="1.2"/>' % [A, L]
		"arrow_down":
			return '<path d="M12 3 L12 19 M7 14 L12 19 L17 14" stroke="%s" stroke-width="2"/>' % [R]
		"refresh":
			return '<path d="M19 12 A 7 7 0 1 1 16 6.3" stroke="%s" stroke-width="1.8"/><path d="M16 2.5 L16.5 6.8 L12.2 7.2" stroke="%s" stroke-width="1.8"/>' % [A, A]
		"dw_print":
			return '<rect x="6" y="3" width="12" height="6" stroke="%s" stroke-width="1.4"/><rect x="3" y="9" width="18" height="8" rx="1.5" stroke="%s" stroke-width="1.5"/><rect x="7" y="14" width="10" height="7" fill="%s" stroke="%s" stroke-width="1"/>' % [L, L, A, L]
	return '<rect x="4" y="4" width="16" height="16" stroke="%s"/>' % [L]


static func get_icon(icon_name: String, px := 20) -> Texture2D:
	var key := "%s@%d" % [icon_name, px]
	if _cache.has(key):
		return _cache[key]
	var img := Image.new()
	var err := img.load_svg_from_string(_svg(_body(icon_name)), float(px) / 24.0)
	if err != OK:
		img = Image.create(px, px, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
