class_name Body
extends Node3D
## Mão ou pé suave (malha gerada por tools/bodygen.py) + mapa de altura para
## posicionar problemas na superfície + textura de pintura dinâmica.

var part := "mao"
var meta := {}
var hmap: Image
var mesh_inst: MeshInstance3D
var skin_mat: ShaderMaterial
var paint_img: Image
var paint_tex: ImageTexture
var paint_rect := Rect2(-3.0, -1.5, 6.0, 3.0)
var paint_dirty := false
var digits: Array = []
var nails: Array = []            # [{node, mat, mesh_inst, w, len, dir, normal, r, i}]
var shadow: MeshInstance3D
var cam_center := Vector3.ZERO
var wide_height := 4.6

const PAINT_W := 1024
const PAINT_H := 512

func build(p_part: String, skin: Color) -> void:
	part = p_part
	var key := "hand" if part == "mao" else "foot"
	mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = load("res://assets/body/%s_mesh.res" % key)
	add_child(mesh_inst)
	hmap = load("res://assets/body/%s_hmap.res" % key)
	var f := FileAccess.open("res://assets/body/%s_meta.json" % key, FileAccess.READ)
	meta = JSON.parse_string(f.get_as_text())
	digits = meta["digits"]
	paint_img = Image.create(PAINT_W, PAINT_H, false, Image.FORMAT_RGBA8)
	paint_img.fill(Color(0, 0, 0, 0))
	paint_tex = ImageTexture.create_from_image(paint_img)
	skin_mat = ShaderMaterial.new()
	skin_mat.shader = load("res://shaders/skin.gdshader")
	skin_mat.set_shader_parameter("skin", skin)
	skin_mat.set_shader_parameter("skin_deep", skin.darkened(0.25).lerp(Color("c0504d"), 0.45))
	skin_mat.set_shader_parameter("paint", paint_tex)
	skin_mat.set_shader_parameter("paint_rect", Vector4(paint_rect.position.x, paint_rect.position.y, paint_rect.size.x, paint_rect.size.y))
	mesh_inst.material_override = skin_mat
	cam_center = Vector3(0.1, 0, -0.15) if part == "mao" else Vector3(-0.1, 0, 0)
	_build_shadow()
	_build_nails()

## Sombra de contato macia no travesseiro (silhueta borrada do mapa de altura)
func _build_shadow() -> void:
	var nz := hmap.get_width()
	var nx := hmap.get_height()
	var small := Image.create(nx / 4, nz / 4, false, Image.FORMAT_RGBA8)
	for zi in small.get_height():
		for xi in small.get_width():
			var v := hmap.get_pixel(zi * 4, xi * 4).r
			small.set_pixel(xi, zi, Color(0.12, 0.02, 0.18, 0.6 if v > -5.0 else 0.0))
	for i in 3:
		var sw := small.get_width()
		var sh := small.get_height()
		small.resize(maxi(4, sw / 3), maxi(4, sh / 3), Image.INTERPOLATE_BILINEAR)
		small.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(small)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pm := PlaneMesh.new()
	var res: float = meta["res"]
	pm.size = Vector2(nx * res, nz * res)
	shadow = MeshInstance3D.new()
	shadow.mesh = pm
	shadow.material_override = mat
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	shadow.position = Vector3(float(meta["x0"]) + nx * res * 0.5 + 0.06, -0.15, float(meta["z0"]) + nz * res * 0.5 + 0.1)

func _build_nails() -> void:
	for i in digits.size():
		var an := nail_anchor(i)
		if an.is_empty():
			continue
		var r: float = an[3]
		var big := (part == "pe" and i == 0) or (part == "mao" and i == 0)
		var w := r * (1.45 if big else 1.4)
		var L := r * (1.55 if big else 1.6)
		var dir: Vector3 = an[1]
		dir.y = 0
		dir = dir.normalized()
		var tip: Vector3 = an[0] + dir * r * 0.5
		var base := tip - dir * L * 0.95
		var sb := surface(base.x, base.z)
		if sb.is_empty():
			continue
		var n: Vector3 = sb[1]
		var node := Node3D.new()
		add_child(node)
		node.position = sb[0] + n * 0.007
		node.basis = MeshGen.basis_from_normal(n, dir)
		var mat := MeshGen.shader_mat("res://shaders/nail.gdshader")
		mat.set_shader_parameter("seed", float(i) * 3.1)
		var mi := MeshGen.inst(node, MeshGen.nail(w, L, w * 0.17), mat)
		nails.append({"node": node, "mat": mat, "mi": mi, "w": w, "len": L, "dir": dir, "normal": n, "r": r, "i": i})

## Altura e normal da superfície vista de cima. Retorna [] fora do corpo.
func surface(x: float, z: float) -> Array:
	var res: float = meta["res"]
	var fx := (z - float(meta["z0"])) / res
	var fy := (x - float(meta["x0"])) / res
	var w := hmap.get_width()
	var h := hmap.get_height()
	if fx < 0 or fy < 0 or fx >= w - 1 or fy >= h - 1:
		return []
	var ix := int(fx)
	var iy := int(fy)
	var tx := fx - ix
	var ty := fy - iy
	var c00 := hmap.get_pixel(ix, iy)
	var c10 := hmap.get_pixel(ix + 1, iy)
	var c01 := hmap.get_pixel(ix, iy + 1)
	var c11 := hmap.get_pixel(ix + 1, iy + 1)
	if minf(minf(c00.r, c10.r), minf(c01.r, c11.r)) < -5.0:
		return []
	var c := c00.lerp(c10, tx).lerp(c01.lerp(c11, tx), ty)
	return [to_global(Vector3(x, c.r, z)), (global_basis * Vector3(c.g, c.b, c.a)).normalized()]

## Ponto da ponta do dedo/artelho para a unha: [pos, direção, normal, largura]
func nail_anchor(i: int) -> Array:
	var d: Dictionary = digits[i]
	var pts: Array = d["pts"]
	var rr: Array = d["r"]
	var a := Vector3(pts[pts.size() - 2][0], pts[pts.size() - 2][1], pts[pts.size() - 2][2])
	var b := Vector3(pts[pts.size() - 1][0], pts[pts.size() - 1][1], pts[pts.size() - 1][2])
	var dir := (b - a).normalized()
	var r: float = rr[rr.size() - 1]
	var c := b - dir * r * 0.55
	var s := surface(c.x, c.z)
	if s.is_empty():
		return []
	return [s[0], dir, s[1], r]

func digit_point(i: int, t: float) -> Vector3:
	var pts: Array = digits[i]["pts"]
	var seg := clampf(t, 0.0, 0.999) * (pts.size() - 1)
	var k := int(seg)
	var a := Vector3(pts[k][0], pts[k][1], pts[k][2])
	var b := Vector3(pts[k + 1][0], pts[k + 1][1], pts[k + 1][2])
	return a.lerp(b, seg - k)

# ------------------------------------------------------------- pintura

func _to_px(x: float, z: float) -> Vector2:
	return Vector2((x - paint_rect.position.x) / paint_rect.size.x * PAINT_W,
		(z - paint_rect.position.y) / paint_rect.size.y * PAINT_H)

## Carimba um pincel macio (Image com alfa) na pele.
func stamp(x: float, z: float, brush: Image, scale_px := 1.0) -> void:
	var b := brush
	if scale_px != 1.0:
		b = brush.duplicate()
		var s := maxi(2, int(brush.get_width() * scale_px))
		b.resize(s, s, Image.INTERPOLATE_BILINEAR)
	var p := _to_px(x, z) - Vector2(b.get_width(), b.get_height()) * 0.5
	paint_img.blend_rect(b, Rect2i(0, 0, b.get_width(), b.get_height()), Vector2i(p))
	paint_dirty = true

func _process(_d: float) -> void:
	if paint_dirty:
		paint_dirty = false
		paint_tex.update(paint_img)
