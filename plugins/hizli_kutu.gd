extends RefCounted
## Örnek eklenti: ölçüleri panelden girilen kutu / içi boş kutu (profil) parçası.

const NAME := "Hızlı Kutu"
const DESCRIPTION := "Panelden en / boy / yükseklik / et kalınlığı girip tek tıkla kutu parçası oluşturur."

var api: PluginApi
var p := {"en": 60.0, "boy": 40.0, "yuk": 20.0, "et": 0.0, "radyus": 0.0}


func setup(a: PluginApi) -> void:
	api = a
	api.add_command("plg_hizli_kutu", "Hızlı\nKutu", "Ölçüleri girerek kutu parçası oluştur", "extrude", open)


func open() -> void:
	api.show_panel("Hızlı Kutu", _build)


func _build(panel: PropertyPanel) -> void:
	panel.number("En", float(p["en"]), func(v: float) -> void: p["en"] = v, "length", 0.1)
	panel.number("Boy", float(p["boy"]), func(v: float) -> void: p["boy"] = v, "length", 0.1)
	panel.number("Yükseklik", float(p["yuk"]), func(v: float) -> void: p["yuk"] = v, "length", 0.1)
	panel.number("Et kalınlığı (0: dolu)", float(p["et"]), func(v: float) -> void: p["et"] = v, "length", 0.0)
	panel.button("Oluştur", make, Icons.get_icon("extrude", 16))
	panel.info("Yeni parça açılır; taslak ve ekstrüzyon ağaçta düzenlenebilir.", Color(0.6, 0.65, 0.72))


func make() -> void:
	var m := api.macro
	m.new_part("Kutu")
	var s := m.sketch("top")
	var en := float(p["en"])
	var boy := float(p["boy"])
	var et := float(p["et"])
	s.center_rect(Vector2.ZERO, Vector2(en, boy))
	if et > 0.0 and et * 2.0 < minf(en, boy):
		s.center_rect(Vector2.ZERO, Vector2(en - 2.0 * et, boy - 2.0 * et))
	m.extrude(s, float(p["yuk"]))
	api.app._fit_after_build = true
	m.doc.commit()
	api.status("Hızlı Kutu: %s × %s × %s mm" % [en, boy, p["yuk"]])
