extends SceneTree
## Converte assets/body/*.json (gerado por bodygen.py) em recursos do Godot.
## godot --headless --path . -s tools/convert_body.gd

func _init() -> void:
	for name in ["hand", "foot", "back", "face", "head"]:
		var f := FileAccess.open("res://assets/body/%s.json" % name, FileAccess.READ)
		if f == null:
			print("faltando ", name)
			continue
		var d: Dictionary = JSON.parse_string(f.get_as_text())
		var v: Array = d["verts"]
		var n: Array = d["norms"]
		var ao: Array = d["ao"]
		var fc: Array = d["faces"]
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var cols := PackedColorArray()
		for i in range(0, v.size(), 3):
			verts.append(Vector3(v[i], v[i + 1], v[i + 2]))
			norms.append(Vector3(n[i], n[i + 1], n[i + 2]))
			var a: float = ao[i / 3]
			cols.append(Color(a, a, a, 1.0))
		var idx := PackedInt32Array()
		for x in fc:
			idx.append(int(x))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		ResourceSaver.save(mesh, "res://assets/body/%s_mesh.res" % name, ResourceSaver.FLAG_COMPRESS)
		# mapa de altura (vista de cima): R = altura, GBA = normal
		var hm: Dictionary = d["hmap"]
		var w: int = hm["w"]
		var h: int = hm["h"]
		var hy: Array = hm["y"]
		var hn: Array = hm["n"]
		var img := Image.create(h, w, false, Image.FORMAT_RGBAF)
		for ix in w:
			for iz in h:
				var k := ix * h + iz
				img.set_pixel(iz, ix, Color(hy[k], hn[k * 3], hn[k * 3 + 1], hn[k * 3 + 2]))
		ResourceSaver.save(img, "res://assets/body/%s_hmap.res" % name, ResourceSaver.FLAG_COMPRESS)
		var meta := {"x0": hm["x0"], "z0": hm["z0"], "res": hm["res"], "w": w, "h": h, "digits": d["digits"]}
		var mf := FileAccess.open("res://assets/body/%s_meta.json" % name, FileAccess.WRITE)
		mf.store_string(JSON.stringify(meta))
		print(name, " ok: ", verts.size(), " verts")
	quit()
