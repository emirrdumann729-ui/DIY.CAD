# DIY.CAD — Sürüm notları

Ayrıntılı özellik listesi: [ROADMAP.md](ROADMAP.md). Kullanım: [README.md](README.md).

## 0.9.3
- STL içe aktarmada **koruma bölgesi**: bir eksen boyunca seçilen aralıkta, kesitteki korunan katmanın (ör. üst kısım) ve onun içindeki şeridin (ör. orta ±h) içi ölçeklenmeden yalnızca taşınır; katman altında / şerit kenarında ve bölge uçlarında geçişle normal büyütmeye bağlanır (katman dışında şerit etkisiz — dönüşüm katlanmaz). Delik, yuva, geçme gibi başka parçaya takılan ayrıntılar özgün ölçüde kalırken gövde etrafında büyür. Katman ve şerit sınırları eksen boyunca profil olarak değişebilir.
- **Çok bölgeli uzatma**: `stretch` artık bölge listesi de alır (her bölgeye ayrı + / − mm).
- Doğrusal olmayan dönüşümlerde (uzatma, kademeli büyütme, koruma) ağ önce dönüşümün kırılma düzlemlerinden kesilir, sonra dönüşümün kenar boyunca doğrusal kalmadığı yerlerde uyumlu (T-birleşimsiz) inceltilir (`refine`, varsayılan 0,05 mm) — ağ kapalı kalır, büyük üçgenler bükülmez.
- İçe aktarma paneli: koruma bölgesi aç / kapa, eksen, aralık, geçiş boyu; özet satırında uzatma bölgeleri, kademeli büyütme ve koruma bölgesi.
- Makro `rebuild()` uzun içe aktarmalarda 15 dakikaya kadar bekler (önceden 2 dakika sonra beklemeyi bırakıyordu).
- Gerçek parça denemesi: RC uçak gövdesi 800 mm'ye büyütülürken kanadın oturduğu kısım (yuva, delikler, oturma yüzeyleri) özgün ölçüde korundu.

## 0.9.2
- **STL içe aktarma** (ikili / ASCII): OpenCASCADE'de üçgenler dikilerek katıya çevrilir (sonraki özellikler, bölme, STEP çıktısı çalışır), CSG çekirdeğinde ağ gövdesi olarak birleşir.
- İçe aktarma dönüşümü: **eksen bazlı ölçek** (X/Y/Z), ölçek merkezi, öteleme ve STL için **bölgesel uzatma** (bir eksen boyunca seçilen aralık orantılı uzar, sonrası kayar; son boyda eklenecek mm olarak girilir). STEP / IGES'te eksen bazlı ölçek de çalışır.
- STL için **kademeli kesit büyütme**: bir eksen boyunca seçilen bölgede her kesite doğrusal artan mm eklenir (kesit merkezine göre; referans profil uçlardan), düz daralmalar düz kalır — iki parçayı farklı kesitlerde buluşturmak için.
- Makro API: `await m.export(...)` OpenCASCADE dışa aktarmasının bitmesini bekler.
- Komut satırı `--` sonrasında verilen `.dcad` / `.dasm` yolları da açılır.
- Gerçek parça denemesi: 6 parçalı RC uçak gövdesi (STL) 800 mm boya, 120 × 120 mm buruna yeniden boyutlandırıldı.

## 0.9.1 — Faz 9 (tamamlandı)
- **Arka planda ağ işleme**: çekirdekten gelen modelin işlenmesi (köşe birleştirme, komşuluk, kenarlar, yumuşatılmış normaller) WorkerThreadPool iş parçacığında; 120 bin üçgenlik modelde en uzun arayüz donması 1072 ms → 234 ms. Gösterim normalleri sıkıştırılmış komşuluk listesiyle hızlandı. OpenCASCADE zaten ayrı süreçte çalışır.
- **Büyük montajlar**: bileşen ağlarına otomatik ayrıntı seviyesi (LOD, `ImporterMesh.generate_lods`); büyük montaj modu (otomatik / kapalı / açık): kenarlar yalnızca seçili / üzerine gelinen bileşende.
- **Eklentiler**: `plugins/` ve kullanıcı klasöründeki `setup(api: PluginApi)` betikleri; "Eklentiler" sekmesinde komut düğmeleri (kısayol / fare hareketi atanabilir), özel paneller, model / belge olayları; Seçenekler → Eklentiler'den aç / kapat. Örnekler: Hızlı Kutu, Parça Bilgisi.
- **Çeviri**: biçimli durum / panel mesajları ve Yardım metni İngilizce (sözlük ~1170 metin).
- **Paketleme**: Windows dışa aktarma ayarı (`export_presets.cfg`, simge `icon.ico`), `Paketle.bat` (taşınabilir sürüm + Inno Setup 6 kurulum dosyası), `installer/DIYCAD.iss` (kullanıcı klasörüne kurulum, .dcad / .dasm ilişkilendirme, isteğe bağlı OpenCASCADE kurulumu). Kurulu sürüm OpenCASCADE, makro ve eklenti klasörlerini .exe'nin yanında arar.
- `.dasm` dosyası komut satırından (dosya ilişkilendirme) açılır.

## 0.9.0 — Faz 9 (1. kısım)
- Otomatik kaydetme, çökme kurtarma, son dosyalar, kaydederken .bak yedeği.
- Özelleştirilebilir klavye kısayolları (170+ komut), fare hareketleri (8 yönlü halka), koyu / açık tema, arayüz ölçeği, Türkçe / İngilizce arayüz.
- GDScript makroları: çalıştırma, kayıt, parçadan makro, `--macro=` komut satırı.

## 0.8.1 — Faz 8 (tamamlandı)
- Yüzey modelleme (ekstrüde / döndürülmüş / loft / düzlemsel / ofset yüzey, dikme, kalınlaştırma, kırpma), doğrusal statik analiz (FEA, von Mises / yer değiştirme haritası), eğim analizi ve ayırma çizgisi, 2.5 eksen CAM G-kod, görselleştirme (HDRI, gölge, PBR, çıkartma), kıvırma.

## 0.8.0 — Faz 8 (1. kısım)
- Sac metal (taban / kenar flanş, K-faktörü, açınım ve DXF), kaynaklı konstrüksiyon (profil kütüphanesi, gönye / alın / T birleşimi, kesim listesi), konfigürasyonlar ve tasarım tablosu (CSV).

## 0.7.1 — Faz 7 (tamamlandı)
- Alt montajlar, kam eşleştirmesi, bileşen çoğaltma, sürüklerken çarpışma algılama, montaj teknik resmi ve otomatik balon, montaj içinde yeni parça.

## 0.7.0 — Faz 7
- Montaj belgesi (.dasm), standart / gelişmiş / mekanik eşleştirmeler, rijit cisim çözücü, girişim tespiti, patlatılmış görünüm, montaj malzeme listesi, bağlantı elemanı kütüphanesi, hareket etüdü, montaj STEP çıktısı.

## 0.6.0 — Faz 6
- Teknik resim: sayfa ve antet, standart / izdüşüm / kesit / detay / yardımcı / kırık görünüşler, gizli çizgi kaldırma (HLR), akıllı boyut ve model boyutları, toleranslar, GD&T, yüzey pürüzlülüğü, kaynak sembolü, BOM, revizyon tablosu; PDF / SVG / DXF çıktısı.

## 0.5.x — Faz 5
- Referans geometri, ekstrüzyon bitiş koşulları ve ince özellik, süpürme ve loft (kılavuz eğrili), çoğaltmalar ve aynalama, delik sihirbazı, kubbe, helis / spiral, geri alma çubuğu ve özellik sıralama, projeksiyon eğrisi, sarma, kabartma, koordinat sistemi.

## 0.4.x — Faz 4
- OpenCASCADE (B-rep) çekirdeği (Python yardımcı süreç), topolojik adlandırma, köşe yuvarlatma / pah / kabuk / eğim / kaburga, çoklu gövde, STEP / IGES içe ve dışa aktarma.

## 0.3.x — Faz 3
- Kırp / uzat / ofset / aynala, taslak köşe yuvarlatma / pah, çokgen, kanal, spline, metin, elips, parabol, taslak çoğaltma, bloklar, bölge seçme, global değişkenler ve denklemler, 3B taslak.

## 0.2.x — Faz 2
- Birim sistemleri, kısıt çözücü, akıllı boyut, geometrik ilişkiler, tanım durumu renkleri, ölçüm, malzeme kütüphanesi ve kütle özellikleri.

## 0.1.x — Faz 0–1
- Arayüz iskeleti, CAD kamerası, belge modeli; taslak modu ve temel araçlar, ekstrüzyon / döndürme / kesme, özellik ağacı, STL / OBJ / DXF / SVG çıktısı.
