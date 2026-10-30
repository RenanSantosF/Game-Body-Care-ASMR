extends Node
## Gera texturas de ruído sem emendas (uma vez) e entrega aos shaders via uniforms globais.

func _ready() -> void:
	_set_global("g_vn", _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 256, 1.0 / 8.0, 1))
	_set_global("g_fbm", _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 256, 1.0 / 8.0, 4))
	_set_global("g_c1", _cell(512, FastNoiseLite.RETURN_DISTANCE))
	_set_global("g_c2", _cell(512, FastNoiseLite.RETURN_DISTANCE2_SUB))
	# celular: renderiza 3D um pouco menor e limita o FPS
	if OS.has_feature("mobile"):
		get_viewport().scaling_3d_scale = 0.8
		Engine.max_fps = 60

func _set_global(param: String, tex: Texture2D) -> void:
	RenderingServer.global_shader_parameter_set(param, tex)

func _noise(kind: int, size: int, freq: float, octaves: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = kind
	n.frequency = freq
	n.seed = 7
	if octaves > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	return t

func _cell(size: int, ret: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 1.0 / 16.0
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.cellular_return_type = ret
	n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	n.cellular_jitter = 1.0
	n.seed = 11
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	return t
