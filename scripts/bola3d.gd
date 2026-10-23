extends Sprite

## A BOLA DE BASQUETE DESENHADA (shaders/bola.shader: esfera com luz, gomos
## e as costuras que giram de verdade). Sem imagem: um quadradinho branco
## esticado ao tamanho pedido - nítida do tamanho do aro ao tamanho da tela.

var velocidade := 3.0          # giro (radianos por segundo)
var _giro := 0.0
var _mat: ShaderMaterial


func _init() -> void:
	var im := Image.new()
	im.create(4, 4, false, Image.FORMAT_RGBA8)
	im.fill(Color(1, 1, 1, 1))
	var t := ImageTexture.new()
	t.create_from_image(im, Texture.FLAG_FILTER)
	texture = t
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/bola.shader")
	material = _mat


func tamanho(px: float) -> void:
	scale = Vector2.ONE * px / 4.0


func ouro(v: float) -> void:
	_mat.set_shader_param("ouro", v)


func _process(delta: float) -> void:
	_giro = fposmod(_giro + delta * velocidade, TAU)
	_mat.set_shader_param("giro", _giro)
