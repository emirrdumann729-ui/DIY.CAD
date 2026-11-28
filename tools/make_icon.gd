extends SceneTree
## Logodan Windows simgesi (icon.ico: 16–256 px PNG girdili) üretir.
## Küçük boyutlarda (≤ 32 px) yazısız simge (branding/icon_small.png), büyüklerde tam logo (branding/logo.png).
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/make_icon.gd

const SIZES := [16, 24, 32, 48, 64, 128, 256]
const SMALL_MAX := 32


func _load(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		push_error("Görüntü okunamadı: " + path)
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func _initialize() -> void:
	var logo := _load("res://branding/logo.png")
	var small := _load("res://branding/icon_small.png")
	if logo == null or small == null:
		quit(1)
		return
	var blobs: Array = []
	for s in SIZES:
		var img := (small if s <= SMALL_MAX else logo).duplicate() as Image
		img.resize(s, s, Image.INTERPOLATE_LANCZOS)
		blobs.append(img.save_png_to_buffer())
	var f := FileAccess.open("res://icon.ico", FileAccess.WRITE)
	f.store_16(0)
	f.store_16(1)
	f.store_16(SIZES.size())
	var offset := 6 + 16 * SIZES.size()
	for i in SIZES.size():
		var s: int = SIZES[i]
		var b: PackedByteArray = blobs[i]
		f.store_8(0 if s >= 256 else s)
		f.store_8(0 if s >= 256 else s)
		f.store_8(0)
		f.store_8(0)
		f.store_16(1)
		f.store_16(32)
		f.store_32(b.size())
		f.store_32(offset)
		offset += b.size()
	for b2 in blobs:
		f.store_buffer(b2)
	f.close()
	print("icon.ico yazıldı (%d boyut)" % SIZES.size())
	quit(0)
