extends Control

const UI = preload("res://scripts/ui.gd")

## APRESENTAÇÃO DA LAZER & SPORT GAMES + SWISH ARENA (~8 s), toda feita em
## código e leve para a Mali-450 (Godot 3.6, GLES2): só sprites, polígonos
## com a cor nos vértices, partículas da CPU e um shader de uma leitura.
##
##   1. o primeiro quadro é IGUAL à imagem de abertura do app
##      (imagens/splash_lazer.png): o logo da LAZER & SPORT já está ali e
##      "ganha vida" - sem nenhuma tela preta entre o app abrir e a
##      apresentação;
##   2. o logo pulsa com impacto, estrelas, holofotes varrendo e um reflexo
##      dourado atravessando; "GAMES" entra letra por letra e "APRESENTA";
##   3. faixas laranja e roxas cortam a tela e a bola vem com tudo, a cesta
##      aparece e a bola cai na rede: SWISH!;
##   4. clarão e a arte SWISH ARENA entra - e segue direto para a abertura
##      (a mesma arte: sem corte).
## START pula para a abertura; uma CESTA começa o jogo direto. Se algo der
## errado, em 15 s ela segue sozinha para a abertura (o jogo nunca para
## aqui).

const LOGO_ESCALA := 0.40
const LOGO_Y := 0.42           # centro do logo (fração da altura)
const SEGURANCA := 15.0

var _tela := Vector2(1280, 720)
var _centro := Vector2(640, 302)
var _aditivo: CanvasItemMaterial
var _tex_brilho: Texture
var _halo: Sprite
var _logo: Sprite
var _mat_logo: ShaderMaterial
var _feixes := []
var _faiscas: CPUParticles2D
var _estouro: CPUParticles2D
var _letras := []
var _linha: ColorRect
var _linha_brilho: Sprite
var _apresenta: Label
var _palco: Node2D             # holofotes, halo e faíscas: ficam até a arte entrar
var _marca: Node2D             # logo + GAMES + APRESENTA (somem juntos)
var _faixas := []
var _bola: Sprite
var _rastro := []
var _cesta: Node2D
var _fundo
var _brilho: Sprite
var _estrelas: CPUParticles2D
var _clarao: ColorRect
var _t := 0.0
var _fase := "marca"
var _fase_t := 0.0
var _reflexo_t := -1.0
var _tremor := 0.0
var _saindo := false


func _ready() -> void:
	_tela = get_viewport_rect().size
	_centro = Vector2(_tela.x * 0.5, _tela.y * LOGO_Y)
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_IGNORE
	_aditivo = CanvasItemMaterial.new()
	_aditivo.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_tex_brilho = load("res://imagens/brilho.png")
	var fundo := ColorRect.new()
	fundo.color = Jogo.FUNDO
	fundo.anchor_right = 1
	fundo.anchor_bottom = 1
	add_child(fundo)
	_montar_marca()
	_montar_faixas()
	_montar_bola()
	_cesta = preload("res://scripts/cesta.gd").new()
	_cesta.position = Vector2(_tela.x * 0.5, _tela.y * 0.40)
	_cesta.visible = false
	add_child(_cesta)
	_fundo = preload("res://scripts/fundo_animado.gd").new()
	_fundo.imagem = "res://imagens/fundo_abertura.png"
	_fundo.qtd_faiscas = 44
	_fundo.visible = false
	add_child(_fundo)
	_brilho = Sprite.new()
	_brilho.texture = _tex_brilho
	_brilho.material = _aditivo
	_brilho.scale = Vector2(0.45, 2.1)
	_brilho.rotation_degrees = 18
	_brilho.modulate.a = 0.0
	add_child(_brilho)
	_estrelas = _explosao(40, 420.0, Color(1.0, 0.7, 0.3))
	add_child(_estrelas)
	_clarao = ColorRect.new()
	_clarao.color = Color(1, 1, 1)
	_clarao.anchor_right = 1
	_clarao.anchor_bottom = 1
	_clarao.mouse_filter = MOUSE_FILTER_IGNORE
	_clarao.visible = false
	add_child(_clarao)
	# as letras grandes prontas antes de aparecer
	Jogo.preaquecer(Jogo.fonte("titan", 104, 8), "GAMES")
	Jogo.preaquecer(Jogo.fonte("titan", 96, 8), "SWISH!")
	Leds.enviar("IDLE")
	Jogo.musica("abertura", -3.0)
	# rede de segurança: aconteça o que acontecer, segue para a abertura
	get_tree().create_timer(SEGURANCA).connect("timeout", self, "_ir_abertura")
	_preparar()


## SEM ENGASGO NO MEIO DA ANIMAÇÃO: os primeiros quadros mostram a capa (a
## mesma imagem de abertura do app, parada: é o primeiro quadro da
## apresentação) e, por baixo dela, TUDO o que a apresentação vai mostrar
## é desenhado uma vez (as letras grandes, os shaders, a cesta, a arte, as
## partículas). Na Mali-450 preparar um shader ou uma letra grande custa um
## tranco: aqui ele acontece com a imagem parada, onde não aparece. Depois
## a capa sai (é igual ao quadro de baixo: não pisca) e a animação começa.
func _preparar() -> void:
	var capa := TextureRect.new()
	capa.texture = load("res://imagens/splash_lazer.png")
	capa.expand = true
	capa.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	capa.anchor_right = 1
	capa.anchor_bottom = 1
	capa.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(capa)
	var swish := UI.label("SWISH!", Jogo.fonte("titan", 96, 8), Jogo.AMARELO)
	UI.colocar(swish, 200, 200, 600, 140)
	add_child(swish)
	move_child(swish, capa.get_index())
	for l in _letras:
		l.modulate.a = 1.0
	_apresenta.modulate.a = 1.0
	_linha.rect_scale = Vector2.ONE
	_linha_brilho.modulate.a = 0.8
	for f in _faixas:
		f.visible = true
		f.position = _tela * 0.5
	_bola.visible = true
	for r in _rastro:
		r.visible = true
	_cesta.visible = true
	_cesta.anotar(Jogo.AMARELO)
	_fundo.visible = true
	_brilho.modulate.a = 0.5
	for f in _feixes:
		f.modulate.a = 1.0
	_estouro.emitting = true
	_estrelas.emitting = true
	_faiscas.emitting = true
	for i in 4:
		yield(get_tree(), "idle_frame")
	# tudo de volta como no primeiro quadro
	swish.queue_free()
	for l in _letras:
		l.modulate.a = 0.0
	_apresenta.modulate.a = 0.0
	_linha.rect_scale = Vector2(0, 1)
	_linha_brilho.modulate.a = 0.0
	for f in _faixas:
		f.visible = false
		f.position = Vector2(-700, _tela.y * 0.5)
	_bola.visible = false
	for r in _rastro:
		r.visible = false
	_cesta.visible = false
	_fundo.visible = false
	_brilho.modulate.a = 0.0
	for f in _feixes:
		f.modulate.a = 0.0
	for p in [_estouro, _estrelas, _faiscas]:
		p.restart()
		p.emitting = false
	capa.queue_free()
	if _saindo:
		return
	_roteiro()


# ------------------------------------------------------------------ montar
## O logo, o halo atrás dele (exatamente como na imagem de abertura do app),
## os holofotes, as faíscas, GAMES e APRESENTA.
func _montar_marca() -> void:
	_palco = Node2D.new()
	add_child(_palco)
	_marca = Node2D.new()
	add_child(_marca)
	# holofotes: polígonos com a cor nos vértices (só pintam a luz)
	var cores := [Color(1.0, 0.48, 0.10), Color(0.55, 0.24, 1.0)]
	for i in range(2):
		var c: Color = cores[i]
		var f := Polygon2D.new()
		var h := _tela.y * 1.25
		f.polygon = PoolVector2Array([Vector2(-14, 0), Vector2(14, 0), Vector2(190, -h), Vector2(-190, -h)])
		f.vertex_colors = PoolColorArray([Color(c.r, c.g, c.b, 0.55), Color(c.r, c.g, c.b, 0.55),
			Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, 0.0)])
		f.material = _aditivo
		f.position = Vector2(_tela.x * (0.08 if i == 0 else 0.92), _tela.y + 20)
		f.modulate.a = 0.0
		_palco.add_child(f)
		_feixes.append(f)
	_halo = Sprite.new()
	_halo.texture = _tex_brilho
	_halo.material = _aditivo
	_halo.position = _centro
	_halo.scale = Vector2(4.2, 3.0)
	_halo.modulate = Color(0.55, 0.30, 1.0, 0.45)
	_palco.add_child(_halo)
	_faiscas = CPUParticles2D.new()
	_faiscas.texture = load("res://imagens/faisca.png")
	_faiscas.material = _aditivo
	_faiscas.amount = 30
	_faiscas.lifetime = 3.0
	_faiscas.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_faiscas.emission_rect_extents = Vector2(_tela.x * 0.5, 8)
	_faiscas.position = Vector2(_tela.x * 0.5, _tela.y + 10)
	_faiscas.direction = Vector2(0, -1)
	_faiscas.spread = 12
	_faiscas.gravity = Vector2.ZERO
	_faiscas.initial_velocity = 120
	_faiscas.initial_velocity_random = 0.5
	_faiscas.scale_amount = 0.35
	_faiscas.scale_amount_random = 0.6
	_faiscas.color = Color(1.0, 0.62, 0.25, 0.8)
	_faiscas.emitting = false
	_palco.add_child(_faiscas)
	_logo = Sprite.new()
	_logo.texture = load("res://imagens/logo_lazer_sport.png")
	_logo.position = _centro
	_logo.scale = Vector2.ONE * LOGO_ESCALA
	_mat_logo = ShaderMaterial.new()
	_mat_logo.shader = load("res://shaders/brilho_logo.shader")
	_mat_logo.set_shader_param("pos", -1.0)
	_mat_logo.set_shader_param("forca", 0.0)
	_logo.material = _mat_logo
	_marca.add_child(_logo)
	_estouro = _explosao(34, 380.0, Color(1.0, 0.75, 0.35))
	_estouro.position = _centro
	_marca.add_child(_estouro)
	# GAMES: uma letra por Label (cada uma entra batendo)
	var f := Jogo.fonte("titan", 104, 8)
	var texto := "GAMES"
	var vao := 6.0
	var total := 0.0
	var larguras := []
	for ch in texto:
		var w: float = f.get_string_size(ch).x + 16.0
		larguras.append(w)
		total += w
	total += vao * (texto.length() - 1)
	var x := _tela.x * 0.5 - total * 0.5
	# logo_lazer_sport.png tem 1280 x 849: GAMES logo abaixo dele
	var y := _centro.y + 849.0 * LOGO_ESCALA * 0.5 - 8.0
	for i in range(texto.length()):
		var l := UI.label(texto[i], f, Jogo.LARANJA)
		l.add_color_override("font_outline_modulate", Color(0.16, 0.04, 0.0))
		UI.colocar(l, x, y, larguras[i], 130)
		l.modulate.a = 0.0
		_marca.add_child(l)
		_letras.append(l)
		x += larguras[i] + vao
	_linha_brilho = Sprite.new()
	_linha_brilho.texture = _tex_brilho
	_linha_brilho.material = _aditivo
	_linha_brilho.position = Vector2(_tela.x * 0.5, y + 132)
	_linha_brilho.scale = Vector2(2.4, 0.22)
	_linha_brilho.modulate = Color(1.0, 0.48, 0.10, 0.0)
	_marca.add_child(_linha_brilho)
	_linha = ColorRect.new()
	_linha.color = Jogo.LARANJA
	UI.colocar(_linha, _tela.x * 0.5 - total * 0.5, y + 130, total, 4)
	_linha.rect_scale = Vector2(0, 1)
	_marca.add_child(_linha)
	_apresenta = UI.label("A P R E S E N T A", Jogo.fonte("bungee", 32, 3), Color(0.92, 0.9, 1.0))
	UI.colocar(_apresenta, 0, y + 140, _tela.x, 48)
	_apresenta.modulate.a = 0.0
	_marca.add_child(_apresenta)


func _explosao(qtd: int, vel: float, cor: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = load("res://imagens/estrela.png")
	p.material = _aditivo
	p.amount = qtd
	p.scale_amount = 0.45
	p.scale_amount_random = 0.5
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 1.2
	p.emitting = false
	p.spread = 180
	p.gravity = Vector2(0, 260)
	p.initial_velocity = vel
	p.initial_velocity_random = 0.6
	p.hue_variation = 0.25
	p.hue_variation_random = 1.0
	p.color = cor
	return p


func _montar_faixas() -> void:
	var cores := [Jogo.LARANJA, Jogo.ROXO, Jogo.AMARELO, Jogo.ROXO, Jogo.LARANJA, Jogo.ROSA]
	for i in range(cores.size()):
		var c: Color = cores[i]
		var p = Polygon2D.new()
		var w = 70.0 + (i % 3) * 40.0
		var h = _tela.y * 1.6
		# faixa inclinada (como as da arte) com as bordas apagadas
		p.polygon = PoolVector2Array([Vector2(-w, -h * 0.5), Vector2(0, -h * 0.5), Vector2(w, -h * 0.5),
			Vector2(w, h * 0.5), Vector2(0, h * 0.5), Vector2(-w, h * 0.5)])
		p.vertex_colors = PoolColorArray([Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, 0.9), Color(c.r, c.g, c.b, 0.0),
			Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, 0.9), Color(c.r, c.g, c.b, 0.0)])
		p.polygons = [PoolIntArray([0, 1, 4, 5]), PoolIntArray([1, 2, 3, 4])]
		p.material = _aditivo
		p.rotation_degrees = 28
		p.position = Vector2(-700, _tela.y * 0.5)
		p.visible = false
		add_child(p)
		_faixas.append(p)


func _montar_bola() -> void:
	var tex: Texture = load("res://imagens/bola.png")
	var faisca: Texture = load("res://imagens/faisca.png")
	for i in range(7):
		var r = Sprite.new()
		r.texture = faisca
		r.material = _aditivo
		r.visible = false
		r.modulate = Jogo.LARANJA.linear_interpolate(Jogo.AMARELO, float(i) / 7.0)
		add_child(r)
		_rastro.append(r)
	_bola = Sprite.new()
	_bola.texture = tex
	_bola.visible = false
	add_child(_bola)


# ----------------------------------------------------------------- roteiro
func _esperar(s: float) -> void:
	yield(get_tree().create_timer(s), "timeout")


func _tw() -> Tween:
	var tw := Tween.new()
	add_child(tw)
	tw.connect("tween_all_completed", tw, "queue_free")
	return tw


func _roteiro() -> void:
	# 1. o logo (já na tela, igual à imagem de abertura) ganha vida
	var tw := _tw()
	for f in _feixes:
		tw.interpolate_property(f, "modulate:a", 0.0, 1.0, 0.6, Tween.TRANS_SINE, Tween.EASE_OUT, 0.1)
	tw.start()
	_faiscas.emitting = true
	yield(_esperar(0.35), "completed")
	if _saindo:
		return
	Jogo.tocar("impacto")
	Jogo.tocar("fase", -5.0)
	_tremor = 7.0
	_estouro.restart()
	var tl := _tw()
	tl.interpolate_property(_logo, "scale", Vector2.ONE * LOGO_ESCALA, Vector2.ONE * LOGO_ESCALA * 1.12, 0.12, Tween.TRANS_SINE, Tween.EASE_OUT)
	tl.interpolate_property(_logo, "scale", Vector2.ONE * LOGO_ESCALA * 1.12, Vector2.ONE * LOGO_ESCALA, 0.4, Tween.TRANS_BACK, Tween.EASE_OUT, 0.12)
	tl.interpolate_property(_halo, "modulate", Color(1.0, 0.6, 0.25, 0.95), Color(0.55, 0.30, 1.0, 0.5), 0.9, Tween.TRANS_SINE, Tween.EASE_OUT)
	tl.start()
	yield(_esperar(0.25), "completed")
	if _saindo:
		return
	_reflexo_t = 0.0
	yield(_esperar(0.4), "completed")
	if _saindo:
		return
	# 2. GAMES, letra por letra
	for i in range(_letras.size()):
		var l: Label = _letras[i]
		var tg := _tw()
		tg.interpolate_property(l, "rect_scale", Vector2(0.45, 0.45), Vector2.ONE, 0.24, Tween.TRANS_EXPO, Tween.EASE_OUT)
		tg.interpolate_property(l, "modulate:a", 0.0, 1.0, 0.1)
		tg.start()
		Jogo.tocar("tique", -4.0, 0.9 + i * 0.12)
		yield(_esperar(0.08), "completed")
		if _saindo:
			return
	yield(_esperar(0.12), "completed")
	if _saindo:
		return
	Jogo.tocar("ponto", -3.0)
	_tremor = 5.0
	var ta := _tw()
	ta.interpolate_property(_linha, "rect_scale", Vector2(0, 1), Vector2.ONE, 0.35, Tween.TRANS_QUART, Tween.EASE_OUT)
	ta.interpolate_property(_linha_brilho, "modulate:a", 0.0, 0.85, 0.35)
	ta.interpolate_property(_apresenta, "modulate:a", 0.0, 1.0, 0.45, Tween.TRANS_SINE, Tween.EASE_OUT, 0.2)
	ta.interpolate_property(_apresenta, "rect_scale", Vector2(0.8, 1.0), Vector2.ONE, 0.6, Tween.TRANS_QUART, Tween.EASE_OUT, 0.2)
	ta.start()
	yield(_esperar(0.9), "completed")
	if _saindo:
		return
	_reflexo_t = 0.0
	yield(_esperar(1.0), "completed")
	if _saindo:
		return
	# 3. as faixas cortam a tela e a marca sai
	Jogo.tocar("fogo", -6.0)
	for i in range(_faixas.size()):
		var f: Polygon2D = _faixas[i]
		f.visible = true
		var tf := _tw()
		var y = _tela.y * (0.25 + 0.1 * (i % 5))
		# (inclinada e comprida: só some de vez bem depois da borda)
		tf.interpolate_property(f, "position", Vector2(-700, y), Vector2(_tela.x + 900, y + 120), 0.8,
			Tween.TRANS_QUART, Tween.EASE_IN_OUT, 0.06 * i)
		tf.interpolate_callback(f, 0.8 + 0.06 * i, "hide")
		tf.start()
	var ts := _tw()
	ts.interpolate_property(_marca, "modulate:a", 1.0, 0.0, 0.4, Tween.TRANS_SINE, Tween.EASE_IN, 0.25)
	ts.interpolate_property(_marca, "scale", Vector2.ONE, Vector2(1.06, 1.06), 0.65, Tween.TRANS_SINE, Tween.EASE_IN)
	ts.interpolate_property(_marca, "position", Vector2.ZERO, -_tela * 0.03, 0.65, Tween.TRANS_SINE, Tween.EASE_IN)
	ts.start()
	yield(_esperar(0.7), "completed")
	if _saindo:
		return
	_marca.visible = false
	# (o palco continua: holofotes, halo e faíscas atrás da bola e da cesta)
	var th := _tw()
	th.interpolate_property(_halo, "modulate", _halo.modulate, Color(1.0, 0.48, 0.10, 0.35), 0.8)
	th.interpolate_property(_halo, "position", _halo.position, _cesta.position, 0.8, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	th.start()
	# 4. a bola vem com tudo
	Jogo.tocar("fogo", -4.0)
	_fase = "bola"
	_fase_t = 0.0
	_bola.visible = true
	for r in _rastro:
		r.visible = true
	yield(_esperar(0.7), "completed")
	if _saindo:
		return
	_bola.visible = false
	for r in _rastro:
		r.visible = false
	# 5. a cesta e o SWISH
	_cesta.visible = true
	UI.pop(_cesta, 0.0, 0.4)
	yield(_esperar(0.45), "completed")
	if _saindo:
		return
	_cesta.anotar(Jogo.AMARELO)
	yield(_esperar(0.3), "completed")
	if _saindo:
		return
	Jogo.tocar("swish")
	Leds.enviar("HIT")
	UI.flutuar(self, "SWISH!", Jogo.fonte("titan", 96, 8), Jogo.AMARELO, _cesta.position + Vector2(0, 150), _cesta.position + Vector2(0, 90), 1.1)
	yield(_esperar(0.95), "completed")
	if _saindo:
		return
	# 6. clarão e a arte
	Jogo.tocar("recorde")
	Leds.enviar("BOOST")
	_clarao.visible = true
	_clarao.modulate.a = 1.0
	_cesta.visible = false
	_fundo.visible = true
	_fundo.rect_pivot_offset = _tela * 0.5
	_fundo.rect_scale = Vector2(1.14, 1.14)
	var tc := _tw()
	tc.interpolate_property(_clarao, "modulate:a", 1.0, 0.0, 0.55, Tween.TRANS_SINE, Tween.EASE_OUT)
	tc.interpolate_property(_fundo, "rect_scale", Vector2(1.14, 1.14), Vector2.ONE, 0.55, Tween.TRANS_EXPO, Tween.EASE_OUT)
	tc.start()
	_estrelas.position = Vector2(_tela.x * 0.37, _tela.y * 0.42)
	_estrelas.restart()
	_palco.visible = false
	_faiscas.emitting = false
	_fundo.flash(Jogo.LARANJA, 0.4)
	_fase = "logo"
	_fase_t = 0.0
	yield(_esperar(2.0), "completed")
	if _saindo:
		return
	Leds.enviar("IDLE")
	_ir_abertura()


## A abertura começa com a mesma arte: sem cortina (ela já está pronta:
## só entra).
func _ir_abertura() -> void:
	if _saindo:
		return
	_saindo = true
	Jogo.trocar_cena(Jogo.CENA_ABERTURA)


func _process(delta: float) -> void:
	_t += delta
	_fase_t += delta
	# tremor (só a marca)
	if _tremor > 0.1:
		_marca.position = Vector2(rand_range(-1, 1), rand_range(-1, 1)) * _tremor
		_tremor = max(0.0, _tremor - delta * 40.0)
	elif _tremor > 0.0:
		_tremor = 0.0
		_marca.position = Vector2.ZERO
	# reflexo dourado atravessando o logo
	if _reflexo_t >= 0.0:
		_reflexo_t += delta
		var k: float = _reflexo_t / 0.8
		_mat_logo.set_shader_param("pos", lerp(-0.3, 1.6, k))
		_mat_logo.set_shader_param("forca", 1.0)
		if k >= 1.0:
			_reflexo_t = -1.0
			_mat_logo.set_shader_param("forca", 0.0)
	# holofotes varrendo (até a arte entrar)
	if _palco.visible:
		for i in range(_feixes.size()):
			var f: Polygon2D = _feixes[i]
			f.rotation = sin(_t * (0.9 + i * 0.25) + i * 2.1) * 0.35 + (0.32 if i == 0 else -0.32)
	match _fase:
		"marca":
			# o logo flutuando
			if _tremor <= 0.0:
				_logo.position.y = _centro.y + sin(_t * 2.2) * 4.0
		"bola":
			# de longe (direita, pequena) até passar perto da tela (esquerda)
			var k: float = clamp(_fase_t / 0.6, 0.0, 1.0)
			var e := k * k
			var de := Vector2(_tela.x + 80, _tela.y * 0.22)
			var ate := Vector2(_tela.x * 0.18, _tela.y * 0.62)
			_bola.position = de.linear_interpolate(ate, e)
			_bola.scale = Vector2.ONE * lerp(0.12, 2.4, e)
			_bola.rotation = -_t * 14.0
			_bola.modulate.a = 1.0 - clamp((k - 0.85) / 0.15, 0.0, 1.0)
			for i in range(_rastro.size()):
				var r: Sprite = _rastro[i]
				var atras: float = clamp(e - 0.035 * (i + 1), 0.0, 1.0)
				r.position = de.linear_interpolate(ate, atras)
				var dir = (ate - de).normalized()
				r.rotation = dir.angle() + PI * 0.5
				r.scale = Vector2(0.5, 3.0) * lerp(0.2, 2.2, atras)
				r.modulate.a = 0.6 * (1.0 - float(i) / _rastro.size()) * _bola.modulate.a
		"logo":
			# brilho passando pelo letreiro
			var k: float = clamp((_fase_t - 0.4) / 1.1, 0.0, 1.0)
			_brilho.position = Vector2(lerp(_tela.x * 0.05, _tela.x * 0.7, k), _tela.y * 0.42)
			_brilho.modulate = Color(1, 1, 1, sin(k * PI) * 0.7)


func _input(ev: InputEvent) -> void:
	if _saindo:
		return
	if ev.is_action_pressed("input_pointer") and not ev.is_echo():
		# alguém acertou a cesta: já começa o jogo (como na abertura)
		_saindo = true
		Jogo.tocar("swish")
		Jogo.parar_musica(0.3)
		Jogo.ir_para("res://cenas/partida.tscn")
	elif ev.is_action_pressed("input_start") and not ev.is_echo():
		_saindo = true
		Jogo.tocar("selecao")
		Jogo.ir_para("res://cenas/abertura.tscn")
	elif Jogo.pede_config(ev):
		# controle remoto da TV Box: direto para a configuração
		_saindo = true
		Jogo.tocar("selecao")
		Jogo.parar_musica(0.3)
		Jogo.ir_para("res://cenas/config.tscn")
