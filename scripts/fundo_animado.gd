extends Control

## Fundo vivo: a arte cobrindo a tela, feixes de luz coloridos varrendo
## devagar, faíscas subindo e um flash de cor para os momentos fortes.
## Leve para a TV Box: poucos sprites com mistura aditiva.
##
## Com "mascara" (arena da partida): as luzes da própria arte ganham vida
## com o shader luzes_arena (neon correndo, lâmpadas em sequência, faixa de
## LED), a mesma técnica do brilho da pista do Dragon Bowling. "holofotes"
## são os pontos do teto de onde saem fachos de luz balançando.

export var imagem := "res://imagens/fundo_arena.png"
export var escurecer := 0.0
export var qtd_feixes := 4
export var qtd_faiscas := 36
export var mascara := ""
export var holofotes := []
export var cores := [Color(1.0, 0.48, 0.10), Color(0.55, 0.24, 1.0), Color(1.0, 0.18, 0.55), Color(0.13, 0.88, 1.0)]

var _feixes := []
var _t := 0.0
var _flash: ColorRect
var _escuro: ColorRect
var _faiscas: CPUParticles2D
var intensidade := 1.0 setget definir_intensidade   # 1 normal; mais alto = EM CHAMAS
var _material: ShaderMaterial
var _fachos := []


func _ready() -> void:
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_IGNORE
	var fundo := TextureRect.new()
	fundo.texture = load(_imagem_para_tela())
	fundo.expand = true
	fundo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fundo.anchor_right = 1
	fundo.anchor_bottom = 1
	fundo.mouse_filter = MOUSE_FILTER_IGNORE
	if mascara != "":
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/luzes_arena.shader")
		_material.set_shader_param("mascara", load(mascara))
		fundo.material = _material
	add_child(fundo)

	_escuro = ColorRect.new()
	_escuro.color = Color(0, 0, 0, escurecer)
	_escuro.anchor_right = 1
	_escuro.anchor_bottom = 1
	_escuro.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_escuro)

	var aditivo := CanvasItemMaterial.new()
	aditivo.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var tex_brilho: Texture = load("res://imagens/brilho.png")
	for i in range(qtd_feixes):
		var s := Sprite.new()
		s.texture = tex_brilho
		s.material = aditivo
		s.scale = Vector2(7.0, 0.45 + randf() * 0.4)
		s.rotation_degrees = -28 + randf() * 12
		var c: Color = cores[i % cores.size()]
		s.modulate = Color(c.r, c.g, c.b, 0.0)
		add_child(s)
		_feixes.append({"no": s, "fase": randf() * TAU, "vel": 0.12 + randf() * 0.10,
			"y": 0.15 + 0.7 * float(i) / max(1, qtd_feixes - 1), "cor": c})

	var tex_facho: Texture = load("res://imagens/feixe.png")
	var cores_facho := [Color(1.0, 0.92, 0.75), Color(0.65, 0.4, 1.0), Color(1.0, 0.6, 0.25), Color(1.0, 0.92, 0.75)]
	for i in range(holofotes.size()):
		var f := Sprite.new()
		f.texture = tex_facho
		f.centered = false
		f.offset = Vector2(-tex_facho.get_width() / 2.0, 0)
		f.position = holofotes[i]
		f.scale = Vector2(1.5, 1.3)
		f.material = aditivo
		add_child(f)
		_fachos.append({"no": f, "fase": randf() * TAU, "cor": cores_facho[i % cores_facho.size()]})

	_faiscas = CPUParticles2D.new()
	_faiscas.texture = load("res://imagens/faisca.png")
	_faiscas.material = aditivo
	_faiscas.amount = qtd_faiscas
	_faiscas.lifetime = 5.0
	_faiscas.preprocess = 5.0
	_faiscas.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_faiscas.direction = Vector2(0, -1)
	_faiscas.spread = 25
	_faiscas.gravity = Vector2(0, -8)
	_faiscas.initial_velocity = 40
	_faiscas.initial_velocity_random = 0.6
	_faiscas.scale_amount = 0.3
	_faiscas.scale_amount_random = 0.8
	var rampa := Gradient.new()
	rampa.set_color(0, Color(1, 0.7, 0.3, 0.0))
	rampa.set_color(1, Color(1, 0.4, 0.8, 0.0))
	rampa.add_point(0.2, Color(1, 0.75, 0.35, 0.9))
	rampa.add_point(0.7, Color(0.7, 0.4, 1.0, 0.6))
	_faiscas.color_ramp = rampa
	add_child(_faiscas)

	_flash = ColorRect.new()
	_flash.anchor_right = 1
	_flash.anchor_bottom = 1
	_flash.mouse_filter = MOUSE_FILTER_IGNORE
	_flash.material = aditivo
	_flash.color = Color(0, 0, 0, 0)
	add_child(_flash)
	_posicionar()
	connect("resized", self, "_posicionar")


## Janela em 720p (TV Box que roda a interface em 1280x720): usa a versão
## da arte já reduzida com filtro bom. Reduzir a de 1920 na placa de vídeo,
## sem mipmap, deixa as linhas finas e as lâmpadas serrilhadas.
func _imagem_para_tela() -> String:
	if OS.window_size.y < 900:
		var menor := imagem.replace(".png", "_720.png")
		if ResourceLoader.exists(menor):
			return menor
	return imagem


func _posicionar() -> void:
	_faiscas.position = Vector2(rect_size.x / 2, rect_size.y + 10)
	_faiscas.emission_rect_extents = Vector2(rect_size.x / 2, 10)


func _process(delta: float) -> void:
	_t += delta
	var larg := rect_size.x
	for f in _feixes:
		var s: Sprite = f.no
		var ciclo: float = fmod(_t * f.vel + f.fase / TAU, 1.0)
		s.position = Vector2(lerp(-larg * 0.3, larg * 1.3, ciclo), rect_size.y * f.y)
		var a := sin(ciclo * PI) * 0.22 * intensidade
		var c: Color = f.cor
		s.modulate = Color(c.r, c.g, c.b, a)
	for f in _fachos:
		var sp: Sprite = f.no
		sp.rotation = sin(_t * 0.45 + f.fase) * 0.26
		var c: Color = f.cor
		sp.modulate = Color(c.r, c.g, c.b, (0.16 + 0.06 * sin(_t * 1.3 + f.fase)) * min(intensidade, 1.8))
	if _flash.color.a > 0.0:
		_flash.color.a = max(0.0, _flash.color.a - delta * 2.2)


## Clarão de cor na tela inteira (cesta, combo, recorde).
func flash(cor: Color, forca: float = 0.35) -> void:
	_flash.color = Color(cor.r * forca, cor.g * forca, cor.b * forca, 1.0)


func definir_faiscas(qtd: int, cor_rapida := false) -> void:
	_faiscas.amount = qtd
	_faiscas.initial_velocity = 120 if cor_rapida else 40


func definir_intensidade(v: float) -> void:
	intensidade = v
	if _material != null:
		var fogo := v > 1.5
		_material.set_shader_param("velocidade", 2.4 if fogo else 1.0)
		_material.set_shader_param("intensidade", 1.35 if fogo else 1.0)
		_material.set_shader_param("cor_neon", Color(1.0, 0.32, 0.08) if fogo else Color(1.0, 0.78, 0.22))
		_material.set_shader_param("cor_lampada", Color(1.0, 0.45, 0.2) if fogo else Color(1.0, 0.86, 0.45))
