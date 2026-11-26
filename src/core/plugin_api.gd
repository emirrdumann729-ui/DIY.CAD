class_name PluginApi
extends RefCounted
## Eklenti arayüzü (Faz 9). Eklenti, `plugins/` klasöründeki bir GDScript dosyasıdır:
##
##   extends RefCounted
##   const NAME := "Örnek"
##   const DESCRIPTION := "Ne yaptığı"
##   func setup(api: PluginApi) -> void:
##       api.add_command("ornek", "Örnek\nKomut", "İpucu", "part", _calistir)
##
## Komutlar "Eklentiler" sekmesinde düğme olur; kısayol ve fare hareketi atanabilir. Modelleme için
## `api.macro` (MacroApi), özel panel için `api.show_panel(başlık, kurucu)` kullanılır.

var app: Node
var plugin_id := ""
var plugin_name := ""
var macro: MacroApi
var _panel_title := ""
var _panel_builder: Callable


func _init(a: Node, id: String, display_name := "") -> void:
	app = a
	plugin_id = id
	plugin_name = display_name if display_name != "" else id
	macro = a.macro


## Komut ekle: düğme ("Eklentiler" sekmesi) + komut kaydı (kısayol / fare hareketi / makro cmd())
func add_command(id: String, label: String, tip: String, icon_name: String, cb: Callable) -> void:
	app.add_plugin_command(id, label, tip + "  [" + plugin_name + "]", icon_name, cb)


## Sol panelde özel panel: builder(panel: PropertyPanel) içeriği kurar
func show_panel(title: String, builder: Callable) -> void:
	_panel_title = title
	_panel_builder = builder
	app.show_plugin_panel(self)


func build_panel(panel: PropertyPanel) -> void:
	panel.title(_panel_title, Icons.get_icon("plugin", 22))
	if _panel_builder.is_valid():
		_panel_builder.call(panel)


func is_panel_open() -> bool:
	return app.mode == "plugin" and app._plugin_panel_api == self


func refresh_panel() -> void:
	if is_panel_open():
		app._refresh_panel()


func close_panel() -> void:
	if is_panel_open():
		app._leave_aux_mode()


func status(msg: String) -> void:
	app._set_status(msg)


func doc() -> CadDocument:
	return app.doc


func model() -> ModelMesh:
	return app.viewport.model


## Model her yeniden oluşturulduğunda cb() çağrılır
func on_built(cb: Callable) -> void:
	app.viewport.kernel.built.connect(cb.unbind(1))


## Belge her değiştiğinde cb() çağrılır
func on_document_changed(cb: Callable) -> void:
	app.doc.changed.connect(cb)
