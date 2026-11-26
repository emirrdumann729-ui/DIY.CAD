class_name MeshJob
extends RefCounted
## Arka plan ağ işleme işi (Faz 9): çekirdekten gelen ağdan ModelMesh (komşuluk, kenarlar, normaller) ve
## gösterim dizilerini WorkerThreadPool iş parçacığında hazırlar; arayüz bu sırada donmaz.

var surfs: Array = []
var aabb := AABB()
var brep := {}
var model: ModelMesh
var display: Array = []
var ms := 0.0


func run() -> void:
	var t0 := Time.get_ticks_usec()
	model = ModelMesh.new()
	model.build_surfaces(surfs, aabb, brep)
	display = model.display_arrays()
	ms = (Time.get_ticks_usec() - t0) / 1000.0
