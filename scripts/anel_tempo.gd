extends Control

## Relógio circular: anel neon que esvazia com o tempo, muda de cor
## (verde -> amarelo -> vermelho) e pulsa nos segundos finais. Os segundos
## ficam no meio em LED.
##
## LEVE PARA A TV BOX: as faixas (fundo, arco e brilho) são malhas montadas
## UMA vez com o shaders/anel_tempo.shader; por quadro só mudam a fração e a
## cor (nada de geometria refeita no GDScript). A ponta do arco é um brilho
## que só anda.

var total := 40.0
var restante := 40.0
var alerta := 10.0
var _t := 0.0
var _led: Control
var _fundo: MeshInstance2D
var _arco: MeshInstance2D
var _halo: MeshInstance2D
var _mat_fundo: ShaderMaterial
var _mat_arco: ShaderMaterial
var _mat_halo: ShaderMaterial
var _ponta: Sprite
var _ponta_brilho: Sprite
var _raio := 1.0
var _centro := Vector2.ZERO


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	var shader := load("res://shaders/anel_tempo.shader")
	_mat_fundo = ShaderMaterial.new()
	_mat_fundo.shader = shader
	_mat_arco = ShaderMaterial.new()
	_mat_arco.shader = shader
	_mat_halo = ShaderMaterial.new()
	_mat_halo.shader = shader
	_mat_halo.set_shader_param("macio", 1.0)
	_halo = MeshInstance2D.new()
	_halo.material = _mat_halo
	add_child(_halo)
	_fundo = MeshInstance2D.new()
	_fundo.material = _mat_fundo
	add_child(_fundo)
	_arco = MeshInstance2D.new()
	_arco.material = _mat_arco
	add_child(_arco)
	var aditivo := CanvasItemMaterial.new()
	aditivo.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_ponta_brilho = Sprite.new()
	_ponta_brilho.texture = load("res://imagens/brilho.png")
	_ponta_brilho.material = aditivo
	add_child(_ponta_brilho)
	_ponta = Sprite.new()
	_ponta.texture = load("res://imagens/brilho.png")
	_ponta.material = aditivo
	add_child(_ponta)
	_led = preload("res://scripts/placar_led.gd").new()
	_led.digitos = 2
	_led.espaco_grupo = false
	_led.contar = false
	_led.cor = Jogo.VERDE
	add_child(_led)
	connect("resized", self, "_ajustar")
	_ajustar()


func _ajustar() -> void:
	var r := min(rect_size.x, rect_size.y) * 0.5
	var w := r * 0.95
	var h := r * 0.70
	_led.rect_position = rect_size / 2 - Vector2(w, h) / 2
	_led.rect_size = Vector2(w, h)
	_centro = rect_size / 2
	_raio = r - 12.0
	var esc := 1.0
	var vp := get_viewport()
	if vp != null:
		esc = vp.get_final_transform().get_scale().x * vp.canvas_transform.get_scale().x
	_fundo.mesh = _faixa(_raio, 12.0)
	_arco.mesh = _faixa(_raio, 10.0)
	_halo.mesh = _faixa(_raio, 30.0)
	for m in [_fundo, _arco, _halo]:
		m.position = _centro
	_mat_fundo.set_shader_param("largura_px", 12.0 * esc)
	_mat_fundo.set_shader_param("cor", Color(1, 1, 1, 0.08))
	_mat_arco.set_shader_param("largura_px", 10.0 * esc)
	_ponta.scale = Vector2.ONE * 16.0 / 256.0 * 1.6
	_ponta_brilho.scale = Vector2.ONE * 46.0 / 256.0 * 1.6


## A faixa redonda (do topo, no sentido do relógio): UV.x = fração, UV.y = lado.
func _faixa(r: float, largura: float) -> ArrayMesh:
	var n := 120
	var pts := PoolVector2Array()
	var uvs := PoolVector2Array()
	var idx := PoolIntArray()
	for k in range(n + 1):
		var a := -PI / 2 + TAU * float(k) / n
		var d := Vector2(cos(a), sin(a))
		pts.append(d * (r - largura * 0.5))
		uvs.append(Vector2(float(k) / n, -1.0))
		pts.append(d * (r + largura * 0.5))
		uvs.append(Vector2(float(k) / n, 1.0))
		if k > 0:
			var b := (k - 1) * 2
			idx.append_array(PoolIntArray([b, b + 1, b + 3, b, b + 3, b + 2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _cor() -> Color:
	var k := restante / max(total, 0.001)
	if restante <= alerta:
		return Jogo.VERMELHO
	if k < 0.5:
		return Jogo.AMARELO
	return Jogo.VERDE


func _process(delta: float) -> void:
	_t += delta
	var seg := int(ceil(max(restante, 0.0)))
	if _led.valor != seg:
		_led.valor = seg
	var cor := _cor()
	_led.cor = cor
	_led.piscar(restante <= 5.0 and restante > 0.0)
	var k := clamp(restante / max(total, 0.001), 0.0, 1.0)
	_mat_arco.set_shader_param("frac", k)
	_mat_arco.set_shader_param("cor", cor)
	var pulso := 1.0
	if restante <= alerta and restante > 0:
		pulso = 1.0 + abs(sin(_t * 6.0)) * 0.6
	_mat_halo.set_shader_param("frac", k)
	_mat_halo.set_shader_param("cor", Color(cor.r, cor.g, cor.b, 0.35 * pulso))
	var a := -PI / 2 + TAU * k
	var p := _centro + Vector2(cos(a), sin(a)) * _raio
	_ponta.position = p
	_ponta_brilho.position = p
	_ponta.visible = k > 0.0
	_ponta_brilho.visible = k > 0.0
	_ponta.modulate = Color(1, 1, 1, 0.95)
	_ponta_brilho.modulate = Color(cor.r, cor.g, cor.b, 0.6 * pulso)
