# DIY.CAD — Yol Haritası

Godot 4.7 ile yazılan, **parametrik, özellik tabanlı (feature-based)** bir CAD programı.


---

## Mimari kararlar

| Konu | Karar | Neden |
|---|---|---|
| Motor | Godot 4.7.1 | Hazır 3B görüntüleme, arayüz (UI) sistemi, çapraz platform |
| Dil | Önce GDScript, ağır işler için sonra C++ (GDExtension) | Hızlı ilerleme; performans gereken yer C++'a taşınır |
| Dahili birim | **Milimetre** ve **derece** | Tüm veriler mm saklanır, ekranda seçilen birime çevrilir |
| Geometri çekirdeği | Faz 1–3: Godot CSG (Manifold kütüphanesi). Faz 4: **OpenCASCADE (OCCT)** | CSG hızlı başlangıç sağlar; fillet/shell/STEP için gerçek B-rep çekirdek şart |
| Veri modeli | Özellik ağacı (Feature Tree) → her değişiklikte baştan "rebuild" | Parametrik geçmiş: her özellik öncekilerin sonucuna uygulanır |
| Dosya formatı | `.dcad` (okunabilir JSON) | Hata ayıklaması kolay, sürüm kontrolüne uygun |
| Geri al / Yinele | Belge anlık görüntüleri (snapshot) | Basit ve hatasız; sonra komut tabanlıya geçilebilir |

### Klasör yapısı

```
DIY.CAD/
  project.godot
  scenes/main.tscn          Ana sahne
  src/main.gd               Uygulama: menüler, komutlar, modlar
  src/core/                 Belge, özellik, taslak, düzlem, birimler (motor bağımsız veri)
  src/kernel/               Geometri çekirdeği (CSG) + mesh araçları
  src/view/                 3B görünüm, kamera, taslak editörü, eksen göstergesi
  src/ui/                   Özellik ağacı, özellik paneli, sayı alanı, ikonlar
  src/io/                   Dışa aktarma: STL, OBJ, DXF, SVG
  tests/selftest.gd         Otomatik testler (komut satırından)
```

---

## Faz 0 — Temel iskelet ✅
- [x] Godot projesi, ana sahne, klasör yapısı
- [x] Arayüz yerleşimi: menü, komut çubuğu, özellik ağacı, özellik paneli, 3B görünüm, durum çubuğu
- [x] CAD kamerası: döndür / kaydır / imlece doğru yakınlaştır, standart görünümler, sığdır, perspektif/ortografik
- [x] Orijin ve üç ana düzlem (Ön, Üst, Sağ), XYZ eksen göstergesi
- [x] Belge modeli, JSON kaydet/aç, geri al/yinele

**Bitti sayılır:** Program açılıyor, model alanında gezinilebiliyor, boş parça kaydedilip açılabiliyor.

## Faz 1 — Basit parça çizip çıktı alma (MVP) ✅
- [x] Taslak (Sketch) modu: düzlem veya düzlemsel yüzey üzerine çizim, kamera düzleme dik döner
- [x] Taslak araçları: çizgi (zincirleme), merkez çizgisi, köşe dikdörtgen, merkez dikdörtgen, daire, merkez noktalı yay
- [x] Izgara (grid) ve uç nokta / orijin yakalama, yatay/dikey yakalama
- [x] Ortak noktalar: birleşik çizgiler birlikte hareket eder, nokta sürükleme
- [x] Seçili öğenin ölçülerini panelden sayısal girme (ifade destekli: `25.4*2`, `12,5`, `1in`)
- [x] Kapalı kontur bulma, iç içe konturlar = delik
- [x] Ekstrüzyon Patron/Taban: Kör, Orta Düzlem, Tümünden; yön çevirme
- [x] Ekstrüzyon Kesme
- [x] Döndürme / Döndürerek Kesme (taslak ekseni veya merkez çizgisi etrafında)
- [x] Özellik ağacı: düzenle, taslağı düzenle, bastır (suppress), sil, yeniden adlandır
- [x] Canlı önizleme (özellik paneli açıkken)
- [x] Dışa aktarma: **STL** (3B baskı), **OBJ**, taslağı **DXF** / **SVG** (lazer kesim), ekran görüntüsü PNG

**Bitti sayılır:** Bir plaka çizip delik açıp üstüne silindir ekleyip STL alınabiliyor ve dilimleyicide (Cura vb.) açılıyor.

## Faz 2 — Ölçülendirme ve birimler ✅
- [x] Birim sistemi seçimi: MMGS, CGS, MKS, IPS (inç-pound-saniye), özel; ondalık hassasiyet ayarı (durum çubuğundan tek tıkla)
- [x] Belge özellikleri penceresi (birim sistemi, uzunluk/kütle birimi, ondalık basamak, malzeme) — birimler belgeyle kaydedilir
- [x] **Kısıt çözücü (constraint solver)**: ağırlıklı Levenberg-Marquardt, serbestlik derecesi (DOF) analizi, çelişkili değişikliği otomatik geri alma
- [x] **Akıllı Boyut (Smart Dimension)**: doğrusal (hizalı/yatay/dikey, imleç konumuna göre), yarıçap, çap, açı, nokta-çizgi mesafesi
- [x] Boyutlar sürükleyici (driving) ve güdümlü (driven); ekranda oklu boyut gösterimi, çift tıkla değer kutusu
- [x] Geometrik ilişkiler: çakışık, yatay, dikey, paralel, dik, teğet, eş merkezli, eşit, orta nokta, simetrik, sabit, doğrusal
- [x] Çizerken otomatik ilişkiler: yatay/dikey çıkarımı, uç noktaya/çizgi ortasına/öğe üzerine yakalama, dikdörtgende yatay+dikey
- [x] İlişkileri koruyarak sürükleme (nokta, çizgi taşıma, daire yarıçapı); gereksiz ilişki/boyut uyarısı
- [x] Taslak tanım durumu renkleri: mavi (eksik tanımlı), siyah (tam tanımlı), kırmızı (aşırı tanımlı); ağaçta (-)/(+) öneki
- [x] Ölçüm aracı: mesafe, normal mesafe, açı, alan, çevre, koordinat
- [x] Malzeme kütüphanesi (21 malzeme: metal, 3B baskı plastikleri, ahşap) ve **kütle özellikleri** (hacim, alan, kütle, ağırlık merkezi, atalet tensörü, asal momentler)

**Bitti sayılır:** Dikdörtgen çizip "60 x 40" boyut verince taslak kendini düzeltiyor, birimi inç'e çevirince tüm değerler doğru görünüyor. ✔ (Otomatik testlerle doğrulandı.)

## Faz 3 — Gelişmiş taslak araçları ve parametreler ✅
- [x] **Kırp** (güç kırpma: tıklanan parça en yakın kesişimler arasında silinir; uçlar çakışık ilişkisiyle bağlanır)
- [x] **Uzat** (çizgiyi ilk kesiştiği öğeye kadar)
- [x] **Ofset**: bağlı zincirleri köşeleriyle birlikte; tüm kenarlar tek bir ofset boyutuna bağlı, önizlemeli
- [x] **Aynala**: merkez çizgisine göre, simetrik ilişkilerle (orijinal değişince kopya da değişir)
- [x] **Taslak köşe yuvarlatma / pah**: teğet ilişkileri + yarıçap/mesafe boyutu; eski köşe "sanal köşe" olarak kalır, bağlı boyutlar korunur
- [x] **Çokgen** (yapı çemberi + eşit kenarlar), **düz kanal** (teğet yaylar), **spline** (tüm noktalardan geçen, açık/kapalı), **taslak metni** (yazı tipi konturlarından; kabartma/gravür)
- [x] Doğrusal / dairesel taslak çoğaltma, taşı / kopyala / döndür / ölçekle (iç ilişkiler kopyalanır)
- [x] Yapı geometrisi (construction) değiştirme
- [x] Global değişkenler ve **denklemler** (`"D1@Taslak1" = genislik / 2`): değer kutusuna `=ifade` yazılır, ekstrüzyon derinliği / döndürme açısı da denklemle sürülebilir, Türkçe değişken adları desteklenir
- [x] **Elips** (merkez + büyük eksen ucu + küçük yarı eksen; yarı eksenler boyutlanır, açı/merkez panelden) ve **parabol** (tepe + odak + iki uç; odak uzaklığı boyutlanır, kapalı kontur olarak ekstrüde edilebilir)
- [x] **Varlıkları dönüştür**: seçili model yüzünün sınır kenarları taslağa sabitlenmiş çizgi/yay olarak alınır (OpenCASCADE çekirdeğinde gerçek B-rep kenarlarından; CSG çekirdeğinde ağ tabanlı)
- [x] **Taslak blokları**: seçili öğeler rijit bloğa dönüşür (sürüklenince bütün olarak taşınır/döner), patlatma ve kopyalama
- [x] **Kesişen konturlardan bölge seçme** (Contour Select): kesişen eğrilerin oluşturduğu bölgeler tıklanarak ekstrüzyona/döndürmeye seçilir
- [x] **3B taslak (temel)**: XY/XZ/YZ düzlemlerinde (Tab ile değişir) çizgi zinciri, eksen kilidi, nokta yakalama, koordinat düzenleme

## Faz 4 — B-rep çekirdeğine geçiş (OpenCASCADE) ✅
CSG yalnızca üçgen ağ (mesh) üretir; köşe yuvarlatma, kabuk, STEP gibi işler için **gerçek yüzey/kenar topolojisi** gerekir.
- [x] OpenCASCADE bağlantısı: C++ derleyici gerektirmeyen **Python yardımcı süreç** (`occ/occ_server.py`, OCP / OCCT 8.0, projeye özel `occ_env`, kurulum: `OCC_Kur.bat`). Godot ile stdin/stdout üzerinden JSON; büyük istekler geçici dosyayla. (GDExtension yerine bu yol seçildi; ileride aynı protokolle C++ modülüne geçilebilir.)
- [x] Aynı çekirdek arayüzü (`GeoKernel`): Faz 1–3 özellikleri (ekstrüzyon, döndürme, kesme, bölge seçimi, elips/parabol/spline/metin profilleri) OCC'de **gerçek eğrilerle** çalışır; OCC yoksa/çökerse otomatik CSG yedeği. Araçlar → Geometri çekirdeği: Otomatik / OpenCASCADE / CSG
- [x] Çift hassasiyet geometri, kesin hacim/alan/atalet (GProp)
- [x] **Topolojik adlandırma**: her yüz, onu üreten özellik + taslak öğesinden kalıcı bir ad alır (ör. `F3:s:12`, `F3:b:10`); adlar her işlemde OCCT geçmişiyle (Modified/Generated/Deleted) taşınır. Kenarlar komşu yüz adlarıyla, yüzler/gövdeler adlarıyla başvurulur; ad bulunamazsa geometrik imzaya düşülür. Yüzeye çizilen taslak, destek yüzüne bağlıdır: model değişince taslak düzlemi yüzle birlikte kayar
- [x] **Köşe yuvarlatma** (sabit yarıçap), **Pah** (eşit mesafe), **Kabuk** (seçili yüzler açık; yüz seçilmezse içi boş gövde; içe/dışa) — kenara/yüze tıklayarak seçim, seçim sırasında özellikten önceki gövde gösterilir
- [x] **STEP / IGES dışa aktarma**, **STEP / IGES içe aktarma** (yüzey tabanlı IGES dikilerek katıya çevrilir, ölçek), yüksek kaliteli STL (sapma/açı ön ayarları, ikili/ASCII)
- [x] Varlıkları dönüştür B-rep kenarlarından: çizgi, daire, yay, elips gerçek öğe olarak gelir
- [x] **Değişken yarıçaplı yuvarlatma** (kenar boyunca doğrusal), **iki mesafeli** ve **açı-mesafe pah** (yön çevirme)
- [x] **Eğim (Draft)**: yüzlere tarafsız yüze göre kalıp çıkma eğimi, çekme yönü çevrilebilir
- [x] **Kaburga (Rib)**: açık taslak çizgisinden, iki yana eşit kalınlıkta; uçlar gövdeye değene kadar otomatik uzar, malzeme tarafı çevrilebilir
- [x] **Çoklu gövde**: ekstrüzyon/döndürmede "Sonucu birleştir" kapatılınca ayrı gövde; **Gövdeleri Birleştir** (ekle / çıkar / kesiştir), **Gövde Taşı/Kopyala** (öteleme + eksen etrafında dönme), **Böl** (ana düzlem + ofset, korunacak taraf); yuvarlatma/pah/kabuk/eğim yalnızca ilgili gövdeye uygulanır

## Faz 5 — Gelişmiş 3B özellikler ✅
- [x] **Referans geometri**: düzlem (ofset, açılı, 3 nokta; taban ana düzlem / referans düzlem / model yüzü), eksen (ana eksen, iki nokta, kenar veya silindir ekseni, iki düzlem kesişimi), nokta. Taslaklar referans düzleme bağlanır, düzlem değişince taşınır; döndürme ve çoğaltma referans eksen kullanabilir
- [x] **Ekstrüzyon bitiş koşulları**: Sonrakine Kadar, Köşeye Kadar, Yüzeye Kadar, Yüzeyden Ofset, İki Yönlü (Yön 2: kör / tümünden / sonrakine), eğim açısı (içe/dışa), **ince özellik** (açık veya kapalı taslak; orta / bir yön / diğer yön)
- [x] **Süpürme** (patron / kesme; yol: taslak zinciri, 3B taslak veya helis) ve **Loft** (patron / kesme, düz veya yumuşak geçiş)
- [x] **Doğrusal** (iki yön), **dairesel**, **tablo güdümlü** çoğaltma ve **aynalama** — özellikleri (ekstrüzyon, döndürme, süpürme, loft, delik) veya tüm gövdeleri
- [x] **Delik Sihirbazı**: düz, havşa başlı (silindirik), konik havşa, kılavuz; ISO (M2–M24, ISO 273 geçme sınıfları) ve ANSI (#4–1/2 UNC); tümünden / kör (118° matkap ucu); kılavuz deliklerde kozmetik diş (kesikli daire)
- [x] **Kubbe**, **helis** (adım/tur/yükseklik, saat yönü, başlangıç açısı)
- [x] **Geri alma çubuğu** (sürüklenebilir; yeni özellikler çubuğun önüne eklenir), özellik sırasını **sürükleyerek** veya Yukarı/Aşağı taşı ile değiştirme (ebeveyn/çocuk sırası korunur), **Ebeveyn / Çocuk** penceresi
- [x] **Yüzeye teğet referans düzlem** (silindir/koni/küre/düzlem üzerinde seçilen noktada) ve **koordinat sistemi** (başlangıç + X/Y eksenleri; kütle özellikleri bu sisteme göre raporlanır)
- [x] Süpürmede **kılavuz eğrisi** (profil kılavuza değecek şekilde ölçeklenir) ve **bükme açısı**; loftta **kılavuz eğrisi**
- [x] **Eğri güdümlü çoğaltma** (taslak zinciri, 3B taslak, helis veya projeksiyon eğrisi boyunca; eşit aralık veya sabit aralık; eğriyi izleyerek döndürme)
- [x] **Spiral** (düzlemsel) ve **konik helis**, **projeksiyon eğrisi** (taslak eğrisini yüze izdüşürür; yol/kılavuz/çoğaltma eğrisi olur), **sarma** (silindire kabartma / oyma / çizgi, yay uzunluğu korunur), **kabartma / gravür** (yüzeyi izleyen sabit kalınlık)

## Faz 6 — Teknik resim (Drawing) ✅
- [x] **Teknik Resim** sekmesi: resim sayfaları parça dosyasında (`drawings`) saklanır, geri al/yinele ile çalışır; birden çok sayfa
- [x] Sayfa boyutları **A4–A0** ve **ANSI A–E**, yatay/dikey, **ISO / ANSI** standardı; çerçeve, merkezleme işaretleri ve **antet** (firma, başlık, resim no, çizen, kontrol, tarih, malzeme, ölçek, ağırlık — malzeme ve kütle modelden otomatik)
- [x] **Standart 3 görünüş + izometrik** (ölçek ve yerleşim otomatik), **1. açı (ISO) / 3. açı (ANSI)** izdüşüm sembolüyle; açı değişince izdüşüm görünüşleri yeniden yönlenir
- [x] Model görünüşü (ön, arka, üst, alt, sağ, sol, izometrik, dimetrik), **izdüşüm görünüşü** (tıklanan tarafa), **kesit** (iki tıkla kesit çizgisi; tarama, A-A etiketi, oklar, bakış yönü çevrilebilir), **detay** (daire, büyütme oranı), **yardımcı** (kenara dik bakış), **kırık görünüş** (birden çok kırık, zikzak sınır)
- [x] **Gizli çizgi kaldırma (HLR)**: OpenCASCADE HLRBRep ile görünür / gizli / teğet kenarlar; görünür çizgiyle çakışan gizli çizgiler bastırılır. Görünüş başına gizli çizgiler (kesikli / kaldırılmış) ve teğet kenarlar (göster / gizle); OCC yoksa ağ kenarlarından yaklaşık görünüş
- [x] **Akıllı boyut** (köşe, daire merkezi, daire, kenar yakalama; yatay / dikey / hizalı, çap, açı), **model boyutlarını aktarma** (taslak boyutları paralel görünüşe; ilişkili — taslak değişince resim güncellenir), **referans boyut**, **toleranslar** (simetrik, sapma, sınır, geçme H7 vb.), metin geçersiz kılma
- [x] **GD&T** kontrol çerçevesi (14 karakteristik, Ø bölgesi, MMC/LMC, datumlar), **datum** sembolü, **yüzey pürüzlülüğü** (Ra; talaşlı / talaşsız / herhangi), **kaynak sembolü** (köşe / V alın; ok tarafı / karşı taraf / iki taraf, çepeçevre, kuyruk notu)
- [x] **Merkez işareti** (tek / görünüşteki tüm daireler), **merkez çizgisi**, **notlar** (çok satır, oklu), **balonlar**, **malzeme listesi (BOM)**, **revizyon tablosu**
- [x] Görünüş ve açıklamaları sürükleyerek taşıma (izdüşüm çocukları hizalı kalır), otomatik yerleşimde boş yer arama, Delete / Esc
- [x] Çıktı: **PDF** (vektörel, çok sayfa, TrueType alt kümesi gömülü — Türkçe karakterler tüm görüntüleyicilerde), **SVG**, **DXF** (R12, katmanlar GORUNUR / GIZLI / EKSEN / OLCU / TARAMA / METIN, çizgi tipleri, cp1254), **DWG** (DXF'i AutoCAD veya ücretsiz ODA File Converter ile), **yazdırma** (PDF varsayılan uygulamada açılır)

## Faz 7 — Montaj (Assembly) ✅
- [x] **Montaj belgesi** `.dasm` (JSON; parça yolları montaja göre göreli), Dosya → Yeni Montaj / Aç, kendi geri al / yinele geçmişi; **Montaj** sekmesi ve araç çubuğu
- [x] **Bileşen ekleme** (parça dosyası; aynı parça bir kez derlenir, örnekler `Ad<1>`, `Ad<2>`), ilk bileşen **sabit** (f), sabitle / serbest bırak, gizle, bastır, sayısal konum; eksik tanımlılar ağaçta (-)
- [x] Parçalar ana parçadan bağımsız derlenir (OCC sunucusunda anahtarla saklanır; CSG'de ayrı çekirdek); **Parçayı Aç** ile düzenle, Montaj sekmesiyle dön (parça kaydedilir ve montajda yenilenir)
- [x] **Standart eşleştirmeler**: çakışık, paralel, dik, teğet, eş merkezli, mesafe, açı, kilit — yüz / kenar / ana düzlem / orijin referansları, seçime göre önerilen türler (★), hizalamayı / yönü çevirme
- [x] **Gelişmiş**: genişlik, simetrik, mesafe sınırı, açı sınırı, kanal; **mekanik**: menteşe, dişli (oran yarıçaplardan), kremayer-pinyon, vida (hatve)
- [x] **Rijit cisim çözücü**: bileşen başına 6 serbestlik, Levenberg-Marquardt, bileşen başına **serbestlik analizi**, çelişkili / sağlanamayan eşleştirme uyarısı (⚠); mekanik eşleştirmelerde sürekli (çok turlu) açı
- [x] Bileşeni **sürükleyerek taşıma / döndürme** (eşleştirmelere uyarak), sayısal öteleme ve döndürme
- [x] **Girişim tespiti** (OpenCASCADE ortak hacim; kırmızı hacimler ve hacim listesi), **patlatılmış görünüm** (adımlar, eşleştirmelerden yön çıkaran otomatik patlatma, animasyon, patlatma çizgileri), **montaj malzeme listesi** (adet, malzeme, kütle; CSV), **kütle özellikleri**, montajı **STEP** olarak dışa aktarma
- [x] **Bağlantı elemanı kütüphanesi** (Toolbox benzeri): altıgen başlı cıvata ISO 4017, somun ISO 4032, pul ISO 7089 (M3–M24), silindirik pim, sabit bilyalı rulman (60xx / 62xx) — ölçüsü panelden değiştirilebilir
- [x] **Hareket etüdü** (motor): seçilen eksen etrafında dev/dk ile döndürme, eşleştirmeler (dişli, vida, kremayer...) hareketi aktarır, kilitlenmede durur
- [x] **Alt montajlar**: `.dasm` bileşen olarak eklenir, rijit grup (alt parçalar tek modelde birleşir; yüzleri eşleştirilebilir), iç içe alt montaj, BOM'da "yalnızca parçalar" / "üst düzey", alt montajı açma
- [x] **Kam eşleştirmesi**: izleyici (nokta, küre, makara/silindir) kam profiline değer; profil kamın yan yüzünün teğet bölgesinden otomatik çıkarılır, hareket etüdüyle çalışır
- [x] **Bileşen çoğaltma**: doğrusal (X/Y/Z veya modelden kenar/eksen/yüz yönü, aralık) ve dairesel (eksen, toplam açı); örnekler çekirdeği izler, sayı değiştirilebilir, silinen örnek atlanır
- [x] **Sürüklerken çarpışma algılama** (OpenCASCADE): bileşen çarpıştığı anda son çarpışmasız konumda durur; değen yüzler çarpışma sayılmaz
- [x] **Montaj teknik resmi**: montajda Teknik Resim sekmesi; görünüşler montaj bileşiğinden (HLR, kesit, detay...), antette montaj adı/kütlesi, malzeme listesi tablosu montaj kalemleriyle, **otomatik balon** (kalem başına, hedefler dağıtılarak); resim `.dasm` içinde saklanır
- [x] **Montaj içinde yeni parça**: parça dosyası oluşturulup montaj orijinine yerleşir; parça düzenlenirken diğer bileşenler parçanın koordinatlarında yarı saydam görünür ve düzlemsel yüzlerine taslak açılabilir (bağlamda tasarım)

## Faz 8 — Özel modüller ✅
- [x] **Sac metal**: **Taban flanş** (kapalı profil → plaka; açık çizgi zinciri → büküm yarıçaplı bükümlü sac, malzeme tarafı, orta düzlem), **kenar flanş** (taban kenarlarına tıklayarak, çoklu kenar, açı, boy, büküm yarıçapı, yön, uç boşlukları; kenar topolojik addan taban taslağına bağlı), **K-faktörü** ve büküm payı BA = A·(R + K·T), **açınım** (düz sac gösterimi) ve **açınım DXF**'i (büküm çizgileri EKSEN katmanında, YUKARI/AŞAĞI açı notları)
- [x] **Kıvırma (hem)**: 180° kenar flanşı hazır ayarı (R = T/2, boy 8 mm), kenara tıklayarak
- [ ] Sac metal devamı (sonraya): gönye flanş, taslakla büküm, kenar flanşına flanş, köşe kabartma / boşaltma
- [x] **Kaynaklı konstrüksiyon**: profil kütüphanesi (kare / dikdörtgen kutu, boru, köşebent, UPN, IPE, lama), taslak veya 3B taslak çizgilerinden **yapısal üye** (her üye ayrı gövde, profil dönüşü), köşede **gönye** veya **alın** birleşim, üçlü köşelerde dikey üye sürer, **T birleşiminde kırpma**, **kesim listesi** (profil, boy, kesim açıları, adet, kütle; CSV)
- [x] **Yüzey modelleme**: ekstrüde / döndürülmüş / loft / düzlemsel yüzey, ofset yüzey, **dikme** (knit; kapalıysa katıya çevirir), **kalınlaştırma** (tek yön / orta, katıyla birleştirme), düzlemle **kırpma**; yüzeyler katılarla aynı parçada kalınlıksız gövde olarak tutulur, sonraki katı özellikleri onları korur
- [ ] Yüzey devamı (sonraya): süpürülmüş yüzey, sınır yüzeyi, doldurma, yüzeyle kırpma, uzatma
- [x] **Konfigürasyonlar** (boyut değerleri, özellik derinlik/açıları ve bastırma durumları; etkin konfigürasyon ağaç kökünde) ve **tasarım tablosu** (CSV içe / dışa aktarma; Excel CSV'yi açar)
- [x] **Simülasyon (FEA)**: doğrusal statik analiz (sunucuda numpy + scipy; vokselli altı yüzlü, uyumsuz modlu elemanlar, seyrek doğrudan çözücü), yüze tıklayarak **sabit yüz** ve **kuvvet** (yüze dik / eksen yönlü), malzemeden E / ν / akma, **von Mises** ve **yer değiştirme** renk haritası, şekil değiştirme büyütmesi, güvenlik katsayısı, mesnet tepkisi (konsol kiriş FL³/3EI ile %0.2 içinde doğrulandı)
- [ ] FEA devamı (sonraya): tetrahedral ağ, basınç / yerçekimi yükleri, montaj analizi, modal / termal analiz
- [x] **Görselleştirme**: stüdyo / gün ışığı / gece ortamları ve **HDRI** panorama yükleme, gölgeli güneş + gölge yakalayıcı zemin, SSAO / SSR / glow, malzemeden **PBR** yüzey (metal / mat / parlak), pozlama, **çıkartmalar** (decal: görüntü seç, yüze tıkla), 2× çözünürlükte **render PNG**
- [x] **Kalıp araçları**: eğim (çekme açısı) analizi — pozitif / negatif / eğim gerektiren yüzler renkli, alan oranları, olası **ayırma çizgisi**
- [x] **CAM (2.5 eksen)**: taslak konturlarından dış kontur / iç kontur / cep takım yolları (takım yarıçapı ofseti, yan adım, adalar), kademeli pasolar, Z0 parça üstü ya da taslak düzlemi, **G-kod** (ISO, G21) ve süre tahmini
- [ ] Kalıp / CAM devamı (sonraya): çekirdek-boşluk ayırma, büzülme payı, 3 eksen yüzey frezeleme, takım kütüphanesi

## Faz 9 — Profesyonelleşme ✅
- [x] **Otomatik kaydetme** (aralık ayarlı, parça + montaj, süreç kimlikli kayıtlar), **çökme kurtarma** penceresi, **son dosyalar** (menü + boş parça paneli), kaydederken **.bak yedeği**
- [x] **Klavye kısayolları** özelleştirme (170+ komut otomatik kaydedilir: menüler, araç çubukları, taslak araçları; bağlamlar Genel / Taslak; çakışma çözümü; menüler canlı kısayol gösterir), **fare hareketleri** (sağ tuş + yön → 8 yönlü halka; parça / taslak / montaj bağlamına göre atanabilir), **koyu / açık tema**, **arayüz ölçeği**, **Türkçe / İngilizce** arayüz (Godot otomatik çevirisi, `i18n/en.txt`, ~1050 metin)
- [x] **Makro API'si** (GDScript: `func run(m: MacroApi)`; taslak / özellik / dışa aktarma yardımcıları, `await m.rebuild()`), **makro kaydı** (eklenen özellikler → `m.add_raw`, kimlik eşleme), **parçadan makro**, örnek makrolar (`macros/`), komut satırı `--macro=`
- [x] Birim testleri: 10 test grubu (çözücü, taslak işlemleri, teknik resim, montaj, özel modüller, Faz 9, B-rep, uçtan uca arayüz × 2 çekirdek)
- [x] **Performans**: çekirdek sonucunun işlenmesi (köşe birleştirme, komşuluk, kenarlar, yumuşatılmış normaller) **arka plan iş parçacığında** (WorkerThreadPool; en uzun donma 1072 → 234 ms), sıkıştırılmış komşuluk listesiyle hızlı normaller; **büyük montajlar için LOD** (ImporterMesh.generate_lods) ve büyük montaj modu
- [x] **Sürüm notları** (CHANGELOG.md), **Windows paketleme**: dışa aktarma ayarı + simge, `Paketle.bat`, Inno Setup kurulum betiği (kullanıcı klasörüne, dosya ilişkilendirme, isteğe bağlı OpenCASCADE kurulumu); kurulu sürüm `occ_env` / `occ` / `macros` / `plugins` klasörlerini .exe yanında arar
- [x] **Dil desteği devamı**: biçimli durum / panel mesajları ve Yardım metni İngilizce (~1170 metin, biçim belirteçleri testle doğrulanır); **eklenti arayüzü** (PluginApi: komut + düğme, özel panel, olaylar, makro API; Seçenekler'den aç / kapat; 2 örnek eklenti)

---

## Özellikler → Faz eşlemesi

| Özellik | DIY.CAD Fazı |
|---|---|
| Sketch, Line, Rectangle, Circle, Arc, Centerline | 1 ✅ |
| Extruded Boss/Base, Extruded Cut, Revolved Boss/Cut | 1 ✅ |
| STL/OBJ çıktı, DXF taslak çıktısı | 1 ✅ |
| Smart Dimension, Relations, Units, Mass Properties, Measure | 2 ✅ |
| Trim/Extend/Offset/Mirror, Sketch Fillet/Chamfer, Spline, Polygon, Slot, Text, Patterns, Equations | 3 ✅ |
| Ellipse, Convert Entities, Blocks, Contour Select, 3D Sketch | 3 (kalan) |
| Fillet, Chamfer, Shell, Draft, Rib, STEP/IGES, Multi-body | 4 |
| Sweep, Loft, Patterns, Mirror, Delik sihirbazı, Reference Geometry | 5 |
| Drawings, Section/Detail Views, BOM, GD&T | 6 ✅ |
| Assemblies, Mates, Exploded View, Interference, standart parça kütüphanesi | 7 ✅ |
| Sheet Metal, Weldments, Configurations | 8 ✅ |
| Surfaces, statik analiz, görselleştirme, eğim analizi, CAM | 8 ✅ (temel) |
| Options, Customize, Macros, Add-ins, Auto-recover, Large Assembly Mode | 9 ✅ |

## Bilinen sınırlamalar
- Faz 5 özelliklerinin hepsi OpenCASCADE çekirdeği gerektirir (referans geometri ve geri alma çubuğu CSG'de de çalışır). Çoğaltılan kılavuz deliklerde kozmetik diş yalnızca ilk delikte çizilir.
- Sarma yalnızca silindirik yüzlere yapılır ve taslak düzlemi silindir eksenine paralel olmalıdır; kılavuzlu süpürmede tek kılavuz eğrisi desteklenir, profilin delikleri yok sayılır.
- Bükmeli süpürme ara kesitlerden yumuşak loft olarak kurulur (yaklaşık yüzey); kabartma/gravür gövdenin tamamının ofsetini kullandığı için çok karmaşık gövdelerde başarısız olabilir.
- Süpürmede profil yolun başında ve yola dik olmalıdır; köşeli 3B taslak yollarında süpürme başarısız olabilir.
- CSG çekirdeğinde geometri üçgen ağ (mesh) tabanlıdır; daireler 128 parçaya bölünür. OpenCASCADE çekirdeğinde geometri kesindir, yalnızca ekran görüntüsü üçgenlenir.
- OpenCASCADE çekirdeği Python 3.11–3.13 ve `occ_env` (~240 MB, statik analiz için numpy + scipy dahil) gerektirir; ilk açılışta ~1 sn içinde başlar, bu sürede model CSG ile gösterilir.
- Topolojik adlar taslak öğe kimliklerine dayanır: taslaktaki bir öğe silinip yeniden çizilirse ondan türeyen yüzlerin adı değişir ve başvurular geometrik eşleşmeye düşer. Bir yüz ikiye bölünürse parçalar aynı adı taşır, aralarında en yakın olan seçilir.
- Yüzey taslağı yalnızca destek yüzü kendi normali boyunca kayınca izler (yüz döner/eğilirse düzlem yerinde kalır).
- Kaburga OCCT LinearForm ile yapılır: profil gövdenin dışında başlayıp gövdeye ulaşmalıdır; çok karmaşık profillerde başarısız olabilir.
- CSG çekirdeğinde yüzeye çizilen taslak yüzün **düzlemini** kopyalar; alttaki parça değişirse taslak yerinde kalır (OpenCASCADE çekirdeğinde destek yüzüyle birlikte kayar).
- Boyutlar 3B modelde yalnızca taslak düzenlenirken görünür (modele bağlı 3B boyutlar yok); teknik resimde model boyutları aktarılabilir.
- Sac metal ve kaynaklı konstrüksiyon OpenCASCADE gerektirir. Kenar flanşı yalnızca düz (kapalı profilli) taban flanşın üst / alt kenarlarına eklenir; büküm "dışa doğru" yapılır (taban boyu değişmez). Açınım gösterilirken taban flanştan sonraki kesme/delik özellikleri açınıma taşınmaz. Açık profilli taban flanş yalnızca doğru çizgilerden oluşmalıdır.
- Kaynaklı konstrüksiyonda üyeler düz çizgilerdir (yaylı yol yok); köşe yuvarlatmaları ve kaynak dikişleri modellenmez; kesim listesinde gönye üyelerin boyu merkez çizgisi boyudur.
- Konfigürasyonlar boyut / derinlik / açı değerlerini ve bastırma durumlarını kapsar (malzeme, renk, özellik türü değişiklikleri kapsanmaz).
- Yüzey özellikleri ve statik analiz OpenCASCADE gerektirir; FEA ayrıca `occ_env` içinde numpy + scipy ister (`OCC_Kur.bat` kurar). Ağ vokselli olduğu için eğri yüzeyler basamaklı yaklaşılır: gerilme yığılmaları (delik kenarı, iç köşe) ağ yoğunluğuna bağlıdır, sonuçlar ön boyutlandırma içindir. Yükler yüze eşit yayılmış kuvvettir (basınç / moment yok); yalnızca tek parça (montaj analizi yok).
- Yüzey kırpma yalnızca standart düzlemlere (ofsetli) göredir; dikme yalnızca kenarları çakışan (tolerans içinde) yüzeyleri birleştirir.
- CAM 2.5 eksendir: yalnız taslak konturları (düzlemsel) işlenir, takım yolu takım merkezidir, giriş/çıkış rampası ve takım telafisi (G41/G42) yoktur; G-kodu tezgâhta çalıştırmadan önce bir simülatörde kontrol edin.
- Görselleştirme gerçek zamanlıdır (Godot Forward+): ışın izleme yoktur; HDRI panorama ortam ışığı ve yansıma olarak kullanılır, çıkartmalar kaydedilmez (oturumluk).
- İngilizce arayüzde menüler, sekmeler, araç çubukları, ipuçları, panel etiketleri, durum mesajları ve Yardım çevrilir; özellik adları (Ekstrüzyon1...), malzeme adları ve bazı nadir hata iletileri Türkçe kalır. Tema değişikliği yeniden başlatınca uygulanır.
- Makrolar uygulamanın tamamına erişen GDScript kodudur: yalnızca güvendiğiniz makroları çalıştırın. Makro kaydı yalnız **eklenen** özellikleri kaydeder (düzenleme / silme kaydedilmez).
- Otomatik kayıt, kayıt aralığı içindeki son değişiklikleri kaybedebilir; teknik resim düzenlemeleri parça kaydının içindedir.
- CSG çekirdeğinde Boolean işlemleri Godot'nun CSG düğümleriyle ana iş parçacığında hesaplanır (CSG sahne ağacı dışında çalışmıyor); çok delikli parçalarda kısa donma olabilir — OpenCASCADE çekirdeği ayrı süreçte çalıştığı için etkilenmez. LOD, perspektif ve ortografik görünümde Godot'nun ekran boyutu ölçütüyle seçilir.
- Kurulum paketi için Godot dışa aktarma şablonları ve Inno Setup 6 gerekir (geliştirme makinesinde kurulu değilse `Paketle.bat` yol gösterir). OpenCASCADE kurulu sürümde de Python + `OCC_Kur.bat` ile kurulur; Python paketle gelmez.
- Eklentiler ve makrolar tüm uygulamaya erişir; yalnız güvendiğiniz eklentileri `plugins/` klasörüne koyun.
- Montaj: girişim tespiti ve montaj STEP çıktısı OpenCASCADE gerektirir. CSG çekirdeğinde eşleştirme referansları düzlemsel yüzler ve uydurulan silindirlerle sınırlıdır (kenar seçimi yok). Dişli / vida / kremayer açıları eşleştirme oluşturulduğu andaki konuma göre ölçülür; dişli geometrisi modellenmez (Toolbox rulmanı bilyesiz, cıvata dişsiz basitleştirilmiş katıdır). Alt montajlar rijittir (esnek alt montaj yok); alt montaj içindeki eşleştirmeler üst montajda çözülmez. Bağlamda düzenlemede diğer bileşenlerin yüzleri yalnızca taslak düzlemi olarak kullanılabilir (kenar dönüştürme / ilişkili referans yok). Çarpışma algılama asenkron çalışır: hızlı sürüklemede bileşen bir önceki çarpışmasız konuma geri döner.
- Teknik resim: kesit görünüşü OpenCASCADE çekirdeği gerektirir; kesitte yalnızca tam (düz) kesit var (kademeli/yarım/kırık kesit yok). Model boyutu aktarımı taslak boyutlarıyla sınırlı (özellik derinlikleri aktarılmaz). Yazdırma doğrudan değil, PDF üzerinden yapılır. DWG doğrudan yazılmaz.
- Teknik resimde metin genişliği yazı tipi ölçümüne değil tahmine dayanır (PDF'te gerçek glif genişlikleri kullanılır); çok uzun notlarda hizalama birkaç mm kayabilir.
- Ölçüm aracı yüz ve köşe seçer; ölçüm aracına B-rep kenar seçimi ve silindir yarıçapı ölçümü henüz bağlanmadı (çekirdek bu bilgiyi veriyor).
- Teğet yay aracı henüz yok (yay + teğet ilişkisiyle yapılabilir).
- Uzat çizgi ve yaylarda; kırp çizgi/daire/yayda çalışır (spline, elips, parabol kesici olarak kullanılabilir ama kendileri kırpılmaz).
- Ofset metni desteklemez; çoğaltılan kopyaların konumu serbesttir (eksik tanımlı).
- 3B taslak şimdilik yalnızca düz çizgilerden oluşur ve henüz bir özellik (süpürme vb.) tarafından kullanılmaz — Faz 5'te süpürme yolu olarak bağlanacak; 3B ilişki/boyut yok.
- Varlıkları dönüştür ile alınan öğeler sabittir; parça değişince taslak güncellenmez (CSG çekirdeğinde eğriler kısa çizgilere bölünür).
- Metin, programın varsayılan yazı tipiyle çizilir; yazı tipi seçimi sonraki sürümlerde.
- CSG çekirdeğinde tam çakışan iki eğri yüzey birleşince nadiren saç teli inceliğinde bir iz kalabilir (OpenCASCADE çekirdeğinde oluşmaz).
- Çizgiler ekranda 1–2 piksel kalınlığındadır; kenar kalınlığı ayarı Faz 9'da.
