extends RefCounted
## Örnek makro: döngüyle delik ızgarası ve kanallar olan plaka (perfore panel).

const EN := 160.0
const BOY := 100.0
const KALINLIK := 4.0
const SATIR := 4
const SUTUN := 7
const DELIK_CAP := 8.0
const KENAR := 18.0


func run(m: MacroApi) -> void:
	m.new_part("DelikliPlaka")
	m.set_material("Alüminyum 6061")
	var s := m.sketch("top")
	s.center_rect(Vector2.ZERO, Vector2(EN, BOY))
	m.extrude(s, KALINLIK)
	var h := m.sketch_at(Vector3(0, KALINLIK, 0), Vector3.UP)
	var dx := (EN - 2.0 * KENAR) / (SUTUN - 1)
	var dy := (BOY - 2.0 * KENAR) / (SATIR - 1)
	for r in SATIR:
		for c in SUTUN:
			h.circle(Vector2(-EN * 0.5 + KENAR + c * dx, -BOY * 0.5 + KENAR + r * dy), DELIK_CAP * 0.5)
	# Uçlarda montaj kanalları
	h.slot(Vector2(-EN * 0.5 + 6.0, -12.0), Vector2(-EN * 0.5 + 6.0, 12.0), 5.0)
	h.slot(Vector2(EN * 0.5 - 6.0, -12.0), Vector2(EN * 0.5 - 6.0, 12.0), 5.0)
	m.cut_through(h)
	await m.rebuild()
	m.view("iso")
	m.message("%d delikli plaka: hacim %.0f mm³" % [SATIR * SUTUN, m.volume()])
