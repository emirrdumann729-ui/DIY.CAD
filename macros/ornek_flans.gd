extends RefCounted
## Örnek makro: parametrik flanş (göbek + cıvata delikleri).
## Araçlar → Makro çalıştır ile açın. Ölçüleri aşağıdan değiştirip yeniden çalıştırın.

const DIS_CAP := 120.0      # flanş dış çapı
const KALINLIK := 12.0
const GOBEK_CAP := 56.0
const GOBEK_BOY := 20.0
const DELIK_CAP := 30.0     # orta delik
const CIVATA_SAYISI := 6
const CIVATA_CAP := 9.0
const BOLUM_CAP := 92.0     # cıvata bölüm dairesi


func run(m: MacroApi) -> void:
	m.new_part("Flans")
	m.set_material("Düz Karbon Çelik (AISI 1020)")
	# 1) Disk
	var s1 := m.sketch("top")
	s1.circle(Vector2.ZERO, DIS_CAP * 0.5)
	m.extrude(s1, KALINLIK)
	# 2) Göbek: diskin üst yüzünde
	var s2 := m.sketch_at(Vector3(0, KALINLIK, 0), Vector3.UP)
	s2.circle(Vector2.ZERO, GOBEK_CAP * 0.5)
	m.extrude(s2, GOBEK_BOY)
	# 3) Orta delik (tümünden)
	var s3 := m.sketch_at(Vector3(0, KALINLIK + GOBEK_BOY, 0), Vector3.UP)
	s3.circle(Vector2.ZERO, DELIK_CAP * 0.5)
	m.cut_through(s3)
	# 4) Cıvata delikleri: bölüm dairesinde eşit aralıklı
	var s4 := m.sketch_at(Vector3(0, KALINLIK, 0), Vector3.UP)
	for i in CIVATA_SAYISI:
		var a := TAU * i / CIVATA_SAYISI
		s4.circle(Vector2(cos(a), sin(a)) * BOLUM_CAP * 0.5, CIVATA_CAP * 0.5)
	m.cut_through(s4)
	await m.rebuild()
	m.view("iso")
	m.message("Flanş hazır: hacim %.0f mm³" % m.volume())
