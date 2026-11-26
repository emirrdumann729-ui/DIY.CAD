extends SceneTree
## icon.svg'den Windows simgesi (icon.ico: 16–256 px PNG girdili) üretir.
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/make_icon.gd

const SIZES := [16, 24, 32, 48, 64, 128, 256]


func _initialize() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	var blobs: Array = []
	for s in SIZES:
		var img := Image.new()
		var base := 128.0
		var err := img.load_svg_from_string(svg, float(s) / base)
		if err != OK:
			push_error("SVG okunamadı")
			quit(1)
			return
		if img.get_width() != s:
			img.resize(s, s, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGBA8)
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
