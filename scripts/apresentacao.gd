extends Control

const UI = preload("res://scripts/ui.gd")

## APRESENTAÇÃO DO SWISH ARENA (~8,5 s), toda feita em código para a OpenGL
## ES 2.0 (leve para a S905L / Mali-450):
##   1. faixas diagonais laranja e roxas cortam a tela (as da arte);
##   2. um PAINEL DE LED de pontinhos (fonte 5x7 desenhada à mão) escreve
##      "LAZER & SPORT", "GAMES" e "APRESENTA";
##   3. a bola vem em alta velocidade na direção da tela, com rastro;
##   4. a cesta (a mesma da partida) aparece e a bola cai na rede: SWISH!;
##   5. clarão e a arte SWISH ARENA entra com impacto, estrelas e o brilho
##      passando pelo letreiro - e segue direto para a abertura (a mesma
##      arte: sem corte).
## Abre o jogo e volta sozinha depois de 1 minuto parado na abertura
## (configuração: APRESENTAÇÃO). START pula para a abertura; uma CESTA
## começa o jogo direto, como na abertura.

# fonte de LED 5x7 (cada letra: 7 linhas de 5 pontos)
const FONTE_LED := {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
	"Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
	"&": ["01100", "10010", "10100", "01000", "10101", "10010", "01101"],
	"!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
}
const COLUNAS := 84
const LINHAS := 9
const PASSO := 14.0

var _tela := Vector2(1280, 720)
var _aditivo: CanvasItemMaterial
var _tex_brilho: Texture
var _faixas := []
var _painel: Panel
var _leds_fundo: Node2D
var _leds: Node2D
var _msg_cols := []          # colunas acesas da mensagem atual: [[bits por linha]]
var _msg_cor := Color(1, 0.62, 0.12)
var _msg_desl := 0.0         # coluna do painel onde a mensagem começa
var _msg_visiveis := 9999    # para o efeito de "escrever" coluna por coluna
var _ultimo_desenho := ""
var _bola: Sprite
var _rastro := []
var _cesta: Node2D
var _fundo
var _brilho: Sprite
var _estrelas: CPUParticles2D
var _clarao: ColorRect
var _t := 0.0
var _fase := ""
var _fase_t := 0.0
var _saindo := false


func _ready() -> void:
	_tela = get_viewport_rect().size
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
	_montar_faixas()
	_montar_painel()
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
	_estrelas = CPUParticles2D.new()
	_estrelas.texture = load("res://imagens/estrela.png")
	_estrelas.material = _aditivo
	_estrelas.amount = 40
	_estrelas.scale_amount = 0.45
	_estrelas.scale_amount_random = 0.5
	_estrelas.one_shot = true
	_estrelas.explosiveness = 0.95
	_estrelas.lifetime = 1.2
	_estrelas.emitting = false
	_estrelas.spread = 180
	_estrelas.gravity = Vector2(0, 260)
	_estrelas.initial_velocity = 420
	_estrelas.initial_velocity_random = 0.6
	_estrelas.hue_variation = 0.25
	_estrelas.hue_variation_random = 1.0
	_estrelas.color = Color(1.0, 0.7, 0.3)
	add_child(_estrelas)
	_clarao = ColorRect.new()
	_clarao.color = Color(1, 1, 1)
	_clarao.anchor_right = 1
	_clarao.anchor_bottom = 1
	_clarao.mouse_filter = MOUSE_FILTER_IGNORE
	_clarao.visible = false
	add_child(_clarao)
	# as letras do LED e o SWISH! prontos antes de aparecer
	Jogo.preaquecer(Jogo.fonte("titan", 96, 8), "SWISH!")
	Leds.enviar("IDLE")
	Jogo.musica("abertura", -3.0)
	_roteiro()


# ------------------------------------------------------------------ montar
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


func _montar_painel() -> void:
	var largura := COLUNAS * PASSO
	var altura := LINHAS * PASSO
	_painel = UI.painel(Jogo.ROXO, Color(0.03, 0.01, 0.07, 0.92), 18, 3, 22)
	UI.colocar(_painel, (_tela.x - largura) * 0.5 - 24, _tela.y * 0.42 - altura * 0.5 - 20, largura + 48, altura + 40)
	_painel.visible = false
	add_child(_painel)
	_leds_fundo = Node2D.new()
	_leds_fundo.position = Vector2(24, 20)
	_leds_fundo.connect("draw", self, "_desenhar_leds_fundo")
	_painel.add_child(_leds_fundo)
	_leds = Node2D.new()
	_leds.position = Vector2(24, 20)
	_leds.material = _aditivo
	_leds.connect("draw", self, "_desenhar_leds")
	_painel.add_child(_leds)


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


# ------------------------------------------------------------ painel de LED
## Os pontos apagados: desenhados UMA vez.
func _desenhar_leds_fundo() -> void:
	var s := Vector2(PASSO, PASSO) * 0.55
	for y in range(LINHAS):
		for x in range(COLUNAS):
			var c = Vector2(x * PASSO + PASSO * 0.5, y * PASSO + PASSO * 0.5)
			_leds_fundo.draw_rect(Rect2(c - s * 0.5, s), Color(0.20, 0.10, 0.30, 0.55))


## Os pontos acesos da mensagem (refeito só quando a mensagem anda).
func _desenhar_leds() -> void:
	var s := Vector2(PASSO, PASSO) * 2.4
	var miolo := Vector2(PASSO, PASSO) * 0.62
	var desl := int(round(_msg_desl))
	for i in range(min(_msg_cols.size(), _msg_visiveis)):
		var x = desl + i
		if x < 0 or x >= COLUNAS:
			continue
		var bits: Array = _msg_cols[i]
		for y in range(7):
			if bits[y]:
				var c = Vector2(x * PASSO + PASSO * 0.5, (y + 1) * PASSO + PASSO * 0.5)
				_leds.draw_texture_rect(_tex_brilho, Rect2(c - s * 0.5, s), false, Color(_msg_cor.r, _msg_cor.g, _msg_cor.b, 0.9))
				_leds.draw_rect(Rect2(c - miolo * 0.5, miolo), _msg_cor.linear_interpolate(Color(1, 1, 1), 0.3))


## A mensagem vira colunas de pontos (fonte 5x7, 1 coluna de espaço).
func _mensagem(texto: String, cor: Color) -> void:
	_msg_cols = []
	for ch in texto:
		var g: Array = FONTE_LED.get(ch, FONTE_LED[" "])
		for col in range(5):
			var bits = []
			for y in range(7):
				bits.append(g[y][col] == "1")
			_msg_cols.append(bits)
		_msg_cols.append([false, false, false, false, false, false, false])
	_msg_cols.pop_back()
	_msg_cor = cor


func _centro_msg() -> float:
	return floor((COLUNAS - _msg_cols.size()) * 0.5)


func _redesenhar_leds() -> void:
	var chave := "%d|%d|%d" % [int(round(_msg_desl)), _msg_visiveis, _msg_cols.size()]
	if chave != _ultimo_desenho:
		_ultimo_desenho = chave
		_leds.update()


# ----------------------------------------------------------------- roteiro
func _esperar(s: float) -> void:
	yield(get_tree().create_timer(s), "timeout")


func _roteiro() -> void:
	# 1. faixas
	Jogo.tocar("fase", -6.0)
	for i in range(_faixas.size()):
		var f: Polygon2D = _faixas[i]
		f.visible = true
		var tw = Tween.new()
		f.add_child(tw)
		var y = _tela.y * (0.25 + 0.1 * (i % 5))
		# (inclinada e comprida: só some de vez bem depois da borda)
		tw.interpolate_property(f, "position", Vector2(-700, y), Vector2(_tela.x + 900, y + 120), 0.8,
			Tween.TRANS_QUART, Tween.EASE_IN_OUT, 0.09 * i)
		tw.interpolate_callback(f, 0.8 + 0.09 * i, "hide")
		tw.start()
	yield(_esperar(0.85), "completed")
	if _saindo:
		return
	# 2. painel de LED
	_painel.visible = true
	UI.pop(_painel, 0.0, 0.35)
	_mensagem("LAZER & SPORT", Jogo.LARANJA)
	_msg_desl = COLUNAS
	_msg_visiveis = 9999
	_fase = "rolar"
	_fase_t = 0.0
	yield(_esperar(1.9), "completed")
	if _saindo:
		return
	_escrever("GAMES", Jogo.CIANO)
	yield(_esperar(0.75), "completed")
	if _saindo:
		return
	_escrever("APRESENTA", Jogo.ROSA)
	yield(_esperar(0.9), "completed")
	if _saindo:
		return
	UI.sumir(_painel, 0.0, 0.25, false)
	# 3. a bola vem com tudo
	yield(_esperar(0.2), "completed")
	if _saindo:
		return
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
	# 4. a cesta e o SWISH
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
	# 5. clarão e a arte
	Jogo.tocar("recorde")
	Leds.enviar("BOOST")
	_clarao.visible = true
	_clarao.modulate.a = 1.0
	_cesta.visible = false
	_fundo.visible = true
	_fundo.rect_pivot_offset = _tela * 0.5
	_fundo.rect_scale = Vector2(1.14, 1.14)
	var tw := Tween.new()
	add_child(tw)
	tw.interpolate_property(_clarao, "modulate:a", 1.0, 0.0, 0.55, Tween.TRANS_SINE, Tween.EASE_OUT)
	tw.interpolate_property(_fundo, "rect_scale", Vector2(1.14, 1.14), Vector2.ONE, 0.55, Tween.TRANS_EXPO, Tween.EASE_OUT)
	tw.start()
	_estrelas.position = Vector2(_tela.x * 0.37, _tela.y * 0.42)
	_estrelas.restart()
	_fundo.flash(Jogo.LARANJA, 0.4)
	_fase = "logo"
	_fase_t = 0.0
	yield(_esperar(2.0), "completed")
	if _saindo:
		return
	Leds.enviar("IDLE")
	_saindo = true
	# a abertura começa com a mesma arte: sem cortina
	get_tree().change_scene("res://cenas/abertura.tscn")


## Escreve uma mensagem coluna por coluna, já centrada.
func _escrever(texto: String, cor: Color) -> void:
	_mensagem(texto, cor)
	_msg_desl = _centro_msg()
	_msg_visiveis = 0
	_fase = "escrever"
	_fase_t = 0.0
	Jogo.tocar("bip", -6.0)


func _process(delta: float) -> void:
	_t += delta
	_fase_t += delta
	match _fase:
		"rolar":
			# entra da direita até o centro, desacelerando
			var alvo := _centro_msg()
			var k: float = clamp(_fase_t / 1.0, 0.0, 1.0)
			k = 1.0 - pow(1.0 - k, 3.0)
			_msg_desl = lerp(float(COLUNAS), alvo, k)
			if k >= 1.0 and _fase_t < 1.05:
				Jogo.tocar("bip", -6.0)
			_redesenhar_leds()
		"escrever":
			_msg_visiveis = int(_fase_t * 90.0)
			_redesenhar_leds()
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
