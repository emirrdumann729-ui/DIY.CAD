# DIY.CAD

Godot 4.7 ile yazılmış, **parametrik ve özellik tabanlı** bir CAD programı.
Hedef ve aşamalar için: [ROADMAP.md](ROADMAP.md)

**Şu anki sürüm: 0.9.3 — STL içe aktarma (eksen bazlı ölçek, bölgesel uzatma, kademeli büyütme, koruma bölgesi) + Faz 9 (tamamlandı): arka planda ağ işleme, büyük montajlar için LOD, eklentiler, İngilizce arayüz, Windows paketleme, otomatik kaydetme, kısayollar, fare hareketleri, makrolar** (önceki: Faz 8). Sürüm notları: [CHANGELOG.md](CHANGELOG.md)

## Çalıştırma

| Dosya | Ne yapar |
|---|---|
| `DIY.CAD.bat` | Programı açar |
| `Editor.bat` | Projeyi Godot editöründe açar (kodu değiştirmek için) |
| `Test.bat` | Otomatik testleri çalıştırır (birim, kısıt çözücü, taslak işlemleri, uçtan uca arayüz; OCC kuruluysa B-rep testleri de) |
| `OCC_Kur.bat` | OpenCASCADE (B-rep) çekirdeğini kurar (bir kez) |
| `Paketle.bat` | Windows paketi: `build\DIY.CAD.exe` (taşınabilir) ve Inno Setup 6 kuruluysa `build\installer\DIY.CAD-<sürüm>-kurulum.exe`. Godot 4.7.1 dışa aktarma şablonları gerekir (editör: Editor → Manage Export Templates) |

Godot, bir üst klasördeki `Godot\Godot_v4.7.1-stable_win64.exe` olarak beklenir.

Komut satırı seçenekleri (`--` işaretinden sonra):
- `--demo` örnek parçayla, `--demo2` isim plakası örneğiyle açılır
- `--open=yol\parca.dcad` dosya açar
- `--uitest` uçtan uca arayüz testini çalıştırır
- `--kernel=auto|occ|csg` geometri çekirdeğini seçer (kayıtlı ayarı geçersiz kılar)
- `--macro=dosya.gd` açılışta makro çalıştırır; `--lang=en|tr`, `--theme=light|dark` ayarı o oturum için geçersiz kılar; `--no-plugins` eklentileri yüklemez
- Komut satırında `.dcad` / `.dasm` dosya yolu verilirse (dosya ilişkilendirme) açılır

## İlk parçanı yap

1. Soldaki ağaçta **Üst Düzlem**'e tıkla, üstteki **Taslak** düğmesine bas.
2. **Köşe Dikdörtgen** (R) aracıyla iki tıkla bir dikdörtgen çiz. Kenarlar otomatik olarak yatay/dikey ilişki alır.
3. **Akıllı Boyut** (D): üst kenara tıkla, yukarıya yerleştir, açılan kutuya `60` yaz, Enter. Sol kenar için `40`.
4. Taslak hâlâ **mavi** ise eksik tanımlıdır: köşeden orijine boyut ver ya da köşegen merkez çizgisi çizip
   orijinle birlikte seçerek **Orta Nokta** ilişkisi ekle. Her şey **siyah** olunca durum çubuğunda *Tam Tanımlı* yazar.
5. **Daire** (C) çiz, Akıllı Boyut ile çapını ver.
6. **Ekstrüzyon** düğmesine bas, derinliği gir, **Tamam**.
7. **Değerlendir → Malzeme** ile malzeme seç, **Kütle Özellikleri** ile ağırlığı gör.
8. **Dosya → STL olarak dışa aktar** ile 3B yazıcıya hazır dosyayı al.

Bir yüzeye tıklayıp tekrar **Taslak** dersen o yüzeyin üzerine çizersin (patron/kesme eklemek için).

## Taslak ipuçları

- **Renkler:** mavi = eksik tanımlı, siyah = tam tanımlı, kırmızı = aşırı tanımlı.
- **Boyut değiştirme:** etikete çift tıkla. Taslak tüm ilişkileri koruyarak kendini günceller.
- **İlişki ekleme:** öğeleri Shift/Ctrl ile seç; soldaki panelde uygun ilişkiler (paralel, dik, teğet, eşit...) listelenir.
- **İlişki silme:** yeşil simgeye tıklayıp Delete'e bas veya paneldeki "Mevcut ilişkiler" listesinden sil.
- **Çelişki:** imkânsız bir boyut ya da ilişki girersen işlem otomatik geri alınır ve durum çubuğunda uyarı çıkar.
  Fazladan (gereksiz) bir boyut eklersen güdümlü (referans, parantez içinde) boyut olur.

## Faz 3 araçları

| Araç | Kullanım |
|---|---|
| Kırp (T) | Silinecek parçaya tıkla; en yakın kesişimler arası silinir |
| Uzat (E) | Çizginin ucuna yakın tıkla; ilk kesiştiği öğeye uzar |
| Köşe Yuvarlat / Pah | Aracı seç, yarıçapı panelden ver, köşeye tıkla |
| Ofset | Öğeleri seç → Ofset → mesafe + yön → Tamam (önizlemeli) |
| Aynala | Öğeleri ve bir merkez çizgisini birlikte seç → Aynala |
| Taşı / Çoğalt | Öğeleri seç → taşı, döndür, ölçekle, doğrusal veya dairesel çoğalt |
| Çokgen (P), Kanal, Spline, Metin | Taslak çubuğundan; metnin yazısı ve boyutu panelden |
| Elips | Merkez → büyük eksen ucu → küçük eksen genişliği; yarı eksenler Akıllı Boyut ile ölçülendirilir |
| Parabol | Tepe → odak → başlangıç ucu → bitiş ucu; uçları bir çizgiyle birleştirirsen kapalı kontur olur |
| Varlıkları Dönüştür | Taslaktayken model yüzüne tıkla; yüzün kenarları sabit çizgi/yay olarak taslağa gelir |
| Blok | Öğeleri seç → Blok: rijit bütün olur (sürükleyince birlikte taşınır/döner); panelden patlat veya kopyala |
| Bölge seç | Ekstrüzyon/döndürme panelinde "Bölge seç" → kesişen eğrilerin oluşturduğu alanlara tıkla |
| 3B Taslak | Özellikler → 3B Taslak: noktaları tıkla, **Tab** ile çizim düzlemini (XY/XZ/YZ) değiştir; eksene yakın çizim X/Y/Z'ye kilitlenir |

**Denklemler:** Özellikler → Denklemler panelinden global değişken ekle (ör. `genislik = 100`).
Bir boyutun değer kutusuna `=genislik/2` yaz; boyut Σ ile işaretlenir ve değişken değişince her şey güncellenir.
Başka boyuta `"D1@Taslak1" * 2` şeklinde başvurulabilir; ekstrüzyon derinliğine de `=kalinlik` yazılabilir.
Örnek için **Dosya → Örnek: isim plakası**.

## Faz 4: OpenCASCADE (B-rep) çekirdeği

Gerçek yüzey/kenar topolojisi için program, projeye özel bir Python ortamında çalışan OpenCASCADE
sunucusunu (`occ/occ_server.py`) arka planda başlatır. Kurulum (bir kez, ~240 MB):

1. Python 3.11–3.13 kurulu olmalı (`python --version`).
2. `OCC_Kur.bat` dosyasını çalıştır (`occ_env` klasörünü oluşturur, `cadquery-ocp-novtk` ile statik analiz için `numpy` + `scipy` paketlerini kurar; eski kurulumlarda bir kez daha çalıştırmak yeterli).

Kurulu değilse program otomatik olarak CSG çekirdeğiyle çalışır. Sağ alttaki çekirdek düğmesi veya
**Araçlar → Geometri çekirdeği** ile Otomatik / OpenCASCADE / CSG seçilir; STL kalitesi de buradan ayarlanır.

| Komut | Kullanım |
|---|---|
| Köşe Yuvarlatma | Kenarlara tıkla (yüze tıklamak tüm kenarlarını ekler, tekrar tıklamak kaldırır), yarıçapı gir; "Değişken yarıçap" ile başlangıç/bitiş yarıçapı |
| Pah | Aynı seçim; eşit mesafe, iki mesafe veya açı-mesafe |
| Kabuk | Açık kalacak yüzlere tıkla, kalınlığı gir (yüz seçmezsen içi boş kapalı gövde) |
| Eğim | "Tarafsız yüzü seç" ile düzlemsel yüzü, sonra eğim verilecek yüzleri tıkla; açıyı gir |
| Kaburga | Taslağa açık bir çizgi çiz (gövdeye değmesi gerekmez, uçlar uzatılır) → Kaburga → kalınlık |
| Sonucu birleştir | Ekstrüzyon/döndürme panelinde kapatılırsa yeni gövde oluşur |
| Gövdeleri Birleştir | Gövdelere tıkla (ilki ana gövde), işlemi seç: ekle / çıkar / kesiştir |
| Gövde Taşı/Kopyala | Gövdeye tıkla, ΔX/ΔY/ΔZ ve dönme eksen/açısını gir; "Kopyala" orijinali korur |
| Böl | Ana düzlem + ofset seç; her iki taraf ayrı gövde olur ya da yalnızca bir taraf kalır |
| STEP / IGES çıktısı | Dosya menüsü veya STEP düğmesi — diğer CAD programlarına aktarım |
| İçe aktar | STEP/IGES dosyasını gövde olarak ekler; üzerine taslak çizip kesme/ekstrüzyon yapılabilir |

Seçim sırasında model, düzenlenen özellikten önceki hâliyle gösterilir; "Sonucu önizle" kutusu sonucu gösterir.
Kütle özellikleri ve ölçülen hacimler B-rep'ten kesin olarak hesaplanır.

**Topolojik adlandırma:** yüzler onları üreten özellik ve taslak öğesinden kalıcı ad alır; seçtiğin kenarlar/yüzler
bu adlarla saklanır. Parçanın ölçüleri büyük ölçüde değişse de yuvarlatma doğru kenarda kalır, yüzeye çizilen
taslak da destek yüzüyle birlikte kayar (ör. taban yüksekliği artınca üstteki çıkıntı yeni üst yüze taşınır).

## Faz 5 araçları

| Araç | Kullanım |
|---|---|
| Referans Geometri ▾ | Düzlem (ofset / açılı / 3 nokta / yüzeye teğet), Eksen, Nokta, Koordinat Sistemi, Helis / Spiral (konik de olabilir), Projeksiyon Eğrisi. Düzlem kenarına tıklayıp "Taslak" ile üzerine çiz |
| Ekstrüzyon bitişleri | Sonrakine Kadar, Köşeye Kadar, Yüzeye Kadar, Yüzeyden Ofset ("Hedef yüzü seç" ile modele tıkla); İki yön, Eğim açısı, İnce özellik |
| Süpürme / Süpürme Kesme | Profil taslağı + yol (taslak zinciri, 3B taslak, helis veya projeksiyon eğrisi); isteğe bağlı kılavuz eğrisi veya bükme açısı |
| Loft / Loft Kesme | Kapalı profilli taslakları işaretle; isteğe bağlı kılavuz eğrisi |
| Çoğaltma ▾ | Doğrusal (2 yön), Dairesel, Aynala, Tablo, Eğri Güdümlü; ağaçtan seçili özellik otomatik eklenir, yön/eksen modelden seçilebilir |
| Sarma | Silindire teğet bir düzleme taslak (ör. metin) çiz → Sarma → silindirik yüzü seç → kabartma / oyma / çizgi |
| Kabartma | Taslak profilini gövdenin yüzeyine (eğri de olabilir) sabit kalınlıkta kabart veya oy |
| Kütle özellikleri | Koordinat sistemi varsa sonuçlar ona göre raporlanabilir |
| Delik Sihirbazı | Standart (ISO/ANSI), tür, ölçü, geçme seç; düzlemsel yüzde her tıklama bir delik |
| Kubbe | Düzlemsel yüze tıkla, yüksekliği gir |
| Geri alma çubuğu | Ağaçta sürükle veya özelliğe sağ tık → "Geri alma çubuğunu bunun altına taşı" |
| Sıralama | Özelliği ağaçta sürükle-bırak veya sağ tık → Yukarı/Aşağı taşı; sağ tık → Ebeveyn / Çocuk |

## Faz 6: Teknik resim

Üstteki **Teknik Resim** sekmesine geçince parçanın A3 sayfası (ISO, 1. açı) standart 3 görünüş ve
izometrik görünüşle otomatik oluşur; resim parça dosyasıyla birlikte kaydedilir. Görünüşler OpenCASCADE'in
gizli çizgi kaldırma (HLR) algoritmasıyla hesaplanır ve model değişince kendiliğinden güncellenir.

| Araç | Kullanım |
|---|---|
| Seç | Görünüşe / açıklamaya tıkla → sol panelde özellikleri (ölçek, gizli çizgi, teğet kenar, tolerans...). Sürükleyerek taşı; izdüşüm görünüşleri hizalı kalır |
| Sayfa | Boyut (A4–A0, ANSI A–E), dikey/yatay, ISO/ANSI, 1./3. açı, sayfa ölçeği, antet alanları, yeni sayfa |
| Standart 3 Görünüş / Model Görünüşü | Ön-üst-yan-izometrik; ya da panelden yönelim seçip sayfaya tıkla |
| İzdüşüm Görünüşü | Bir görünüş seç → sağına/soluna/üstüne/altına tıkla |
| Kesit Görünüşü | Görünüş seç → kesit çizgisinin iki ucuna tıkla (taramalı A-A görünüşü; panelden bakış yönü çevrilir) |
| Detay Görünüşü | Görünüş seç → merkeze, sonra daire kenarına tıkla (büyütme panelden) |
| Yardımcı / Kırık Görünüş | Kenara tıkla (ona dik bakış) / kaldırılacak bölgenin iki sınırına tıkla |
| Akıllı Boyut | İki köşe (yerleşime göre yatay/dikey/hizalı), daire (çap), kenar (uzunluk), iki kenar (açı); toleranslar panelden |
| Model Boyutları | Taslak boyutlarını, taslak düzlemine paralel görünüşlere ilişkili olarak aktarır |
| Merkez İşareti / Çizgisi, Not, Balon | Daireye tıkla / iki nokta / yere tıkla / hedef + balon yeri |
| Yüzey Pürüzlülüğü, Geometrik Tolerans, Datum, Kaynak Sembolü | Sembolü yerleştir (gerekirse önce hedef noktası), değerleri panelden düzenle |
| Malzeme Listesi, Revizyon Ekle | BOM tablosunu aç/kapat, revizyon tablosuna satır ekle |
| PDF / SVG / DXF / Yazdır | Vektörel çıktı; PDF'e Türkçe karakterler için yazı tipi gömülür. DWG için DXF'i AutoCAD veya ücretsiz ODA File Converter ile dönüştürün |

Tuvalde tekerlek yakınlaştırır, sağ/orta tuş kaydırır, **F** sayfayı sığdırır, **Delete** seçileni siler, **Esc** aracı bırakır.

## Faz 7: Montaj

**Dosya → Yeni Montaj** (veya *Örnek montajı aç*) ile montaj moduna geçilir; montaj `.dasm` dosyasına kaydedilir,
parça dosyalarına göreli yolla başvurur. Üstte yalnızca **Montaj** sekmesi görünür.

| Araç | Kullanım |
|---|---|
| Bileşen Ekle | Parça dosyası (.dcad) seç; ilk bileşen sabittir (f), sonrakiler yanına yerleşir |
| Bağlantı Elemanları | Cıvata (ISO 4017), somun (ISO 4032), pul (ISO 7089), pim, rulman — ölçü ve uzunluk seçip ekle |
| Eşleştir | Yüzlere / kenarlara tıkla (ağaçtan bileşenin ana düzlemleri de seçilebilir) → türü seç; ★ önerilenler. Standart: çakışık, paralel, dik, teğet, eş merkezli, mesafe, açı, kilit. Gelişmiş: genişlik, simetrik, mesafe/açı sınırı, kanal. Mekanik: menteşe, dişli, kremayer-pinyon, vida |
| Sürükleme | Bileşeni sol tuşla sürükle: eşleştirmelere uyarak hareket eder. Taşı / Döndür araçlarında sayısal giriş |
| Sabitle / Serbest, Gizle / Göster | Seçili bileşen için; ağaçta (-) eksik tanımlı, ⚠ sağlanamayan eşleştirme |
| Girişim Tespiti | Çakışan hacimler kırmızı gösterilir, hacimleri listelenir (OpenCASCADE) |
| Patlatılmış Görünüm, Patlat / Topla | Adım ekle (bileşen + yön + mesafe) veya otomatik patlat; animasyonlu aç/kapat |
| Hareket Etüdü | Döndürülecek bileşenin silindirik yüzüne tıkla, dev/dk ve süre gir → Oynat; dişli/vida eşleştirmeleri hareketi aktarır |
| Malzeme Listesi, Kütle Özellikleri | Adet / malzeme / kütle tablosu (CSV), toplam kütle ve ağırlık merkezi |
| Parçayı Aç | Bileşenin parçasını düzenle; **Montaj** sekmesine tıklayınca parça kaydedilip montaja dönülür |
| STEP Çıktısı | Tüm montajı tek STEP dosyası olarak dışa aktar |
| Yeni Parça | Montaj içinde yeni parça: diğer bileşenler yarı saydam görünür, düzlemsel yüzlerine tıklayıp taslak açılır; bitince Montaj sekmesi |
| Bileşen Çoğaltma | Bileşenlere tıkla → doğrusal (yön + aralık) veya dairesel (eksen + toplam açı); örnekler çekirdeği izler |
| Alt montaj | Bileşen Ekle ile `.dasm` seç: rijit grup olarak eklenir; BOM'da alt montajlar açılabilir |
| Kam (mekanik eşleştirme) | 1: izleyici (silindir / nokta), 2: kamın yan yüzü — profil otomatik çıkarılır |
| Çarpışmada dur | Montaj panelinde veya Taşı aracında işaretle: sürüklenen bileşen çarpışmadan önce durur (OpenCASCADE) |
| Teknik Resim (montajda) | Montajın resmi: görünüşler, malzeme listesi tablosu, **Otomatik Balon** |

## Faz 8: Sac metal, kaynaklı konstrüksiyon, konfigürasyonlar

| Araç (sekme) | Kullanım |
|---|---|
| Taban Flanş (Sac Metal) | Kapalı profilli taslak → sac plaka; açık çizgi zinciri → bükümlü sac (L, U, Z...). Kalınlık, büküm yarıçapı, K-faktörü panelden |
| Kenar Flanş (Sac Metal) | Taban plakanın üst veya alt kenarlarına tıkla (birden çok); boy, açı, yarıçap, yön ve uç boşlukları |
| Açınım / Açınım DXF | Düz sac görünümünü aç/kapat; açınımı büküm çizgileri ve "YUKARI 90° R2" notlarıyla DXF'e kaydet (lazer, abkant) |
| Yapısal Üye (Kaynaklar) | Taslak veya 3B taslak çizgileri + profil (kare/dikdörtgen kutu, boru, köşebent, UPN, IPE, lama); köşe birleşimi gönye veya alın; T birleşimleri otomatik kırpılır |
| Kesim Listesi (Kaynaklar) | Profil, boy, kesim açıları, adet ve kütle tablosu; CSV |
| Konfigürasyon (Değerlendir) | Boyut / derinlik değerleri ve bastırma durumlarından oluşan konfigürasyonlar; tasarım tablosu CSV içe / dışa aktarma (`D1@Taslak1`, `D1@Ekstrüzyon1`, `$BASTIR@Özellik`) |

### Faz 8 (devam): yüzeyler, analiz, CAM, görselleştirme

| Araç (sekme) | Kullanım |
|---|---|
| Ekstrüde / Döndürülmüş / Loft Yüzey (Yüzeyler) | Açık ya da kapalı taslak eğrilerinden kalınlıksız yüzey; döndürmede ilk merkez çizgisi eksendir; loft son iki taslağı birleştirir |
| Düzlemsel Yüzey (Yüzeyler) | Kapalı konturlu taslaktan düz yüzey (iç konturlar delik olur) |
| Ofset Yüzey / Yüzey Dikme (Yüzeyler) | Yüzeyi ofsetle; çakışan kenarlı yüzeyleri dik — kapalıysa katıya çevrilir |
| Kalınlaştır / Yüzey Kırp (Yüzeyler) | Yüzeyden kalınlıklı katı (tek yön / orta, katıyla birleştir); standart düzlem (+ofset) ile kırp |
| Kıvırma (Sac Metal) | 180° kenar flanşı (hem): taban kenarına tıkla |
| Statik Analiz (Analiz) | "Tıklama: Sabit yüz" ile yüzlere tıkla, sonra "Yük yüzü" ile yük yüzlerine; kuvvet ve yönü panelden; Çalıştır → von Mises / yer değiştirme haritası, şekil değiştirme, güvenlik katsayısı |
| Eğim Analizi (Analiz) | Çekme yönü ve en az eğim açısı: yeşil pozitif, kırmızı negatif, sarı eğim gerekli; mavi çizgi olası ayırma çizgisi |
| CAM G-kod (Analiz) | Taslak + işlem (dış / iç kontur, cep), takım çapı, derinlik, paso, ilerleme, Z0 referansı → turuncu takım yolları ve `.nc` G-kod |
| Görselleştirme (Analiz) | Ortam (stüdyo / gün / gece / HDRI dosyası), gölge, zemin, SSAO, yüzey (PBR), pozlama, çıkartma ekle (görüntü seç → yüze tıkla), Render kaydet (2×) |

## Faz 9: Profesyonelleşme

| Özellik | Kullanım |
|---|---|
| Otomatik kaydetme | Kirli parça / montaj her 5 dakikada (Seçenekler'den değişir) kullanıcı klasörüne yazılır; kaydedince, yeni belgede ve düzgün çıkışta silinir |
| Çökme kurtarma | Program beklenmedik kapanırsa sonraki açılışta "Belge kurtarma" penceresi: Kurtar (kirli olarak açılır) veya Kaydı sil |
| Son dosyalar | Dosya → Son Dosyalar (en çok 10, parça ve montaj); boş parçada sol panelde de listelenir |
| Yedek | Seçenekler → "Kaydederken önceki sürümü yedekle": üzerine yazmadan önce `dosya.dcad.bak` |
| Klavye kısayolları | Araçlar → Seçenekler → Klavye kısayolları: 170'ten fazla komut (menüler, tüm araç çubukları, taslak araçları); satıra çift tıkla, tuşa bas. Taslak bağlamı (L, C, R...) ayrıdır; menüler yeni kısayolu gösterir |
| Fare hareketleri | Seçenekler → Fare hareketleri → "Sağ tuşla sürükleme: Fare hareketleri": sağ tuşu basılı tutup bir yöne çek → 8 yönlü halkada komut (parça: görünümler, taslak: çizim araçları, montaj); her yön atanabilir. Döndürme orta tuşa geçer, Ctrl + sağ tuş kaydırır |
| Tema / ölçek | Koyu veya açık tema (yeniden başlatınca), arayüz ölçeği %75–%200 (anında) |
| Dil | Türkçe / English (anında): menüler, sekmeler, araç çubukları, ipuçları, panel etiketleri, seçenekler; sözlük `i18n/en.txt` (`türkçe<TAB>english`) |
| Makro çalıştır | Araçlar → Makro çalıştır: `func run(m: MacroApi)` içeren `.gd` dosyası. Örnekler `macros/` klasöründe (parametrik flanş, delikli plaka, toplu çıktı). Komut satırı: `DIY.CAD.bat -- --macro=dosya.gd` |
| Makro kaydı | Araçlar → Makro kaydını başlat / durdur: aradaki özellikler makroya dönüşür (dolu parçaya oynatılırsa kimlikler eşlenir). "Parçayı makro olarak kaydet" tüm parçayı yeniden kuran makro üretir |
| STL içe aktarma | Özellikler → İçe Aktar: `.stl` (ikili / ASCII) gövde olur (OpenCASCADE: dikilmiş katı; CSG: ağ gövdesi). Panelde **Ölçek X / Y / Z**, ölçek merkezi, öteleme ve **bölgesel uzatma** (eksen, bölge başı / sonu özgün koordinatta, eklenecek boy mm): bölgedeki geometri orantılı uzar, dışı bozulmaz. **Koruma bölgesi**: seçilen aralık (ve makrodan verilen kesit bantları) ölçeklenmeden yalnızca taşınır — delik / yuva / geçme gibi ayrıntılar özgün ölçüde kalır, çevresi büyür. Makrodan **kademeli kesit büyütme** (`taper`: bölge boyunca kesite doğrusal artan mm), çok bölgeli uzatma (`stretch` listesi) ve koruma bantları (`protect.bands`) da verilebilir. Sonra Dosya → STL ile dışa aktar — mevcut STL'leri yeniden boyutlandırmak için |
| Eklentiler | `plugins/` (program klasörü) veya kullanıcı klasöründeki `plugins/` içine `setup(api: PluginApi)` içeren `.gd` dosyası: komutlar **Eklentiler** sekmesinde düğme olur (kısayol / fare hareketi atanabilir), özel panel açabilir, model / belge değişince haber alır. Seçenekler → Eklentiler: aç / kapat, klasörü aç. Örnekler: **Hızlı Kutu** (ölçülerle kutu / profil), **Parça Bilgisi** (canlı parça özeti) |
| Arka planda ağ işleme | Çekirdekten gelen modelin işlenmesi (komşuluk, kenarlar, yumuşatılmış normaller) iş parçacığında yapılır; büyük modellerde arayüz donmaz (120 bin üçgende en uzun donma 1,07 sn → 0,23 sn) |
| Büyük montajlar | Bileşen ağlarına otomatik ayrıntı seviyesi (LOD): uzaktaki / küçük görünen bileşenler sadeleştirilmiş ağla çizilir. Montaj panelinde **Büyük montaj modu** (otomatik: 400 bin üçgen veya 80 bileşen üstü): kenarlar yalnız seçili bileşende |

Makro API'si (`src/core/macro_api.gd`): `new_part`, `sketch("front"|"top"|"right", ofset)`, `sketch_at(nokta, normal)`,
taslakta `line / polyline / rect / center_rect / circle / arc / polygon / slot / spline`, `extrude`, `cut`, `cut_through`,
`revolve`, `feature(tür, parametreler)`, `set_material`, `set_variable`, `suppress`, `await rebuild()`, `volume()`, `area()`,
`view()`, `cmd(komut)`, `export(yol)` (STL / OBJ / STEP / IGES / PNG), `save()`, `message()`; tüm uygulamaya `m.app`, `m.doc` ile erişilir.

```gdscript
extends RefCounted
func run(m: MacroApi) -> void:
	m.new_part("Pul")
	var s := m.sketch("top")
	s.circle(Vector2.ZERO, 12)
	s.circle(Vector2.ZERO, 6.5)
	m.extrude(s, 2)
	await m.rebuild()
	m.message("Hacim: %.1f mm³" % m.volume())
```

Eklenti örneği:

```gdscript
extends RefCounted
const NAME := "Selam"
const DESCRIPTION := "Durum çubuğuna parça adını yazar"

func setup(api: PluginApi) -> void:
	api.add_command("selam", "Selam", "Parça adını göster", "part", func(): api.status("Parça: " + api.doc().part_name))
```

## Birimler

Sağ alttaki birim düğmesinden **MMGS / CGS / MKS / IPS** seçilir; **Araçlar → Belge Özellikleri** ile
uzunluk/kütle birimi ve ondalık basamak ayrı ayrı ayarlanır. Birimler parça dosyasıyla birlikte kaydedilir.
Sayı alanlarına ifade ve birim yazılabilir: `25.4*2`, `12,5`, `1in + 3mm`, `100/3`.

## Fare ve klavye

| | |
|---|---|
| Orta tuş veya sağ tuş sürükle | Döndür |
| Ctrl + orta/sağ tuş sürükle | Kaydır |
| Tekerlek | İmlece doğru yakınlaştır |
| Sol tık / çift tık | Seç / düzenle |
| F | Ekrana sığdır |
| Ctrl+1…7 | Ön, Arka, Sol, Sağ, Üst, Alt, İzometrik |
| Ctrl+8 | Düzleme dik görünüm |
| Ctrl+Z / Ctrl+Y | Geri al / Yinele |
| Delete, F2, Esc, Enter | Sil, Yeniden adlandır, İptal, Tamam |
| Taslakta: L, N, R, C, A, P, D, T, E, S, G | Çizgi, Merkez çizgisi, Dikdörtgen, Daire, Yay, Çokgen, Akıllı Boyut, Kırp, Uzat, Seç, Izgara |

## Kod yapısı

```
src/core/     Belge, özellik, taslak, düzlem, birimler, malzemeler, kısıt çözücü, taslak işlemleri, denklemler, metin konturları, ayarlar (AppSettings), otomatik kayıt (Autosave), makro API (MacroApi)
src/kernel/   Çekirdek seçici (GeoKernel), OpenCASCADE köprüsü (OccKernel), CSG yedeği, mesh araçları, kütle özellikleri, arka plan ağ işleme (MeshJob)
occ/          OpenCASCADE sunucusu (Python, OCP) — occ_env içindeki Python ile çalışır
src/view/     3B görünüm, CAD kamerası, taslak editörü (boyut/ilişki çizimi), eksen göstergesi
src/ui/       Özellik ağacı, özellik paneli, sayı alanı, SVG ikonlar, kısayollar (Keymap), fare hareketleri (MouseGesture), tema (UiTheme), dil (I18n), Seçenekler penceresi
src/io/       STL, OBJ, DXF, SVG dışa aktarma
src/special/  Faz 8: sac metal (SheetMetal), kaynaklı konstrüksiyon (Weldment), konfigürasyonlar (Configs), yüzeyler (Surfaces), statik analiz + eğim analizi (Fea), CAM (Cam), arayüz + görselleştirme (SpecialUI)
src/assembly/ Montaj: belge (CadAssembly), eşleştirme çözücüsü (MateSolver), referans geometrisi (MateGeom), görünüm (AssemblyView), mod denetleyicisi (AssemblyMode), bağlantı elemanları (Toolbox), LOD (AsmLod)
src/drawing/  Teknik resim: veri modeli ve izdüşüm geometrisi (Drawing), sayfa çizimi (DrawingRender), PDF/SVG/DXF (DrawingExport), tuval (DrawingCanvas)
plugins/      Örnek eklentiler (Hızlı Kutu, Parça Bilgisi); src/core/plugin_api.gd + plugins.gd
macros/       Örnek makrolar; i18n/ İngilizce sözlük ve yardım; installer/ Inno Setup betiği; tools/ simge üretici
tests/        selftest.gd (birim), solver_test.gd (kısıt çözücü), ops_test.gd (taslak işlemleri), drawing_test.gd (teknik resim), assembly_test.gd (montaj çözücüsü), special_test.gd (sac metal, kaynak, konfigürasyon, CAM, analiz), pro_test.gd (ayarlar, kısayollar, makro, dil), occ_test.gd (B-rep), ui_flow.gd (uçtan uca)
```

Dosya formatı `.dcad` okunabilir JSON'dur.

## Gereksinimler

- Windows 10/11, [Godot 4.7.1](https://godotengine.org/download) (standart sürüm; `Godot\` klasörü projenin bir üst klasöründe)
- İsteğe bağlı OpenCASCADE çekirdeği için Python 3.11–3.13 (`OCC_Kur.bat` gerisini kurar). `occ_env` ve `build` klasörleri depoda yoktur, yerelde oluşturulur.

## Lisans

[MIT](LICENSE). OpenCASCADE çekirdeği (OCP / OCCT) kendi lisansıyla (LGPL 2.1, istisnalı) ayrıca kurulur; depoya dahil değildir.
