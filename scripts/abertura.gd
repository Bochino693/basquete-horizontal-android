extends Control

const UI = preload("res://scripts/ui.gd")
const Cartao = preload("res://scripts/cartao.gd")

## ABERTURA (tela de espera): a arte SWISH ARENA viva, bola voando para a
## cesta de tempos em tempos, ACERTE A CESTA pulsando, o RECORDE em LED e um
## cartão que troca entre o RANKING e o COMO JOGAR.
## A PRIMEIRA CESTA (sensor) começa a partida; START também (operador).
## Segurar SELECT (ou F10 no PC) abre a configuração.
##
## SEM ENGASGO: a abertura é montada UMA vez (quando o app abre, por baixo
## da capa parada) e fica guardada no Jogo enquanto outra tela está na
## frente; voltar para ela não monta nada (entrar). As duas páginas do
## cartão já ficam prontas: trocar de página só desliza (nada é criado no
## meio da animação). A bola da demonstração e o "SWISH!" são sempre os
## mesmos.
## ENTRADA: cada peça entra na sua vez (o recorde desce, o logo salta, o
## cartão chega da direita com as linhas uma a uma, a chamada cresce) e os
## textos com contorno nunca ficam meio transparentes: entram deslizando
## (cortados na borda do cartão) ou crescendo.

const CESTA_ARTE := Vector2(1132, 160)   # onde fica o aro na arte de abertura
const SEGURAR_CONFIG := 4.0
## Parada (ninguém jogando) por este tempo: volta a APRESENTAÇÃO animada.
const OCIOSO_APRESENTACAO := 60.0
const TROCA_PAINEL := 7.0
const CHAMADA := "ACERTE PARA\nCOMEÇAR A JOGAR"

# onde cada peça fica (a entrada começa longe e termina aqui)
const REC_POS := Vector2(28, 22)
const REC_TAM := Vector2(330, 118)
const LOGO_POS := Vector2(376, 22)
const PAINEL_POS := Vector2(868, 262)
const PAINEL_TAM := Vector2(384, 430)
const CHAMADA_POS := Vector2(40, 528)
const LINHA_X := 16.0

var fundo
var _t := 0.0
var _ocioso := 0.0
var _proxima_bola := 3.2
var _proxima_troca := TROCA_PAINEL
var _proxima_varredura := 2.5
var _painel_modo := 0
var _virando := false
var _saindo := true
var _segurando := 0.0
var _brilho_chamada := -1.0      # tempo da faixa de luz na chamada (< 0: parada)
var _proximo_brilho := 1.4

var _rec                         # Cartao (recorde)
var _rec_led
var _logo: TextureRect
var _chamada: Label
var _mat_chamada: ShaderMaterial
var _painel                      # Cartao (ranking / como jogar)
var _titulo: Label
var _paginas := []               # [ranking, como jogar]
var _linhas_rank := []
var _linhas_como := []
var _vazio: Control
var _halo: Sprite
var _varredura: Sprite
var _explosao: CPUParticles2D
var _anel_config: Control
var _bola: Sprite
var _bola_arco := []
var _swish: Label
var _tweens := []


func _ready() -> void:
	Jogo.guardar_abertura(self)
	_montar()
	set_process(false)
	set_process_input(false)
	if not Jogo.apresentou:
		Jogo.apresentou = true
		_preparar_na_capa()
		return
	entrar(false)


# =================================================================== montar
func _montar() -> void:
	fundo = preload("res://scripts/fundo_animado.gd").new()
	fundo.imagem = "res://imagens/fundo_abertura.png"
	fundo.qtd_faiscas = 44
	add_child(fundo)

	var aditivo := CanvasItemMaterial.new()
	aditivo.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var tex_brilho: Texture = load("res://imagens/brilho.png")
	_halo = Sprite.new()
	_halo.texture = tex_brilho
	_halo.material = aditivo
	_halo.position = CESTA_ARTE + Vector2(0, 30)
	_halo.scale = Vector2(1.6, 1.2)
	add_child(_halo)

	_varredura = Sprite.new()
	_varredura.texture = tex_brilho
	_varredura.material = aditivo
	_varredura.scale = Vector2(0.45, 2.1)
	_varredura.rotation_degrees = 18
	_varredura.modulate = Color(1, 1, 1, 0.0)
	add_child(_varredura)

	# a bola da demonstração (sempre a mesma)
	_bola = Sprite.new()
	_bola.texture = load("res://imagens/bola.png")
	_bola.visible = false
	add_child(_bola)

	_explosao = CPUParticles2D.new()
	_explosao.texture = load("res://imagens/estrela.png")
	_explosao.material = aditivo
	_explosao.amount = 26
	_explosao.scale_amount = 0.5   # estrela.png tem 128 px
	_explosao.one_shot = true
	_explosao.explosiveness = 0.95
	_explosao.lifetime = 1.0
	_explosao.emitting = false
	_explosao.position = CESTA_ARTE + Vector2(0, 20)
	_explosao.spread = 180
	_explosao.gravity = Vector2(0, 300)
	_explosao.initial_velocity = 260
	_explosao.initial_velocity_random = 0.5
	_explosao.hue_variation = 0.3
	_explosao.hue_variation_random = 1.0
	_explosao.color = Color(1, 0.6, 0.2)
	add_child(_explosao)

	_montar_recorde()

	# logo da empresa ao lado do recorde
	_logo = TextureRect.new()
	_logo.texture = load("res://imagens/logo_lazer_sport.png")
	_logo.expand = true
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = MOUSE_FILTER_IGNORE
	UI.colocar(_logo, LOGO_POS.x, LOGO_POS.y, 178, 118)
	add_child(_logo)

	# ACERTE PARA COMEÇAR A JOGAR: a primeira bola na cesta começa o jogo
	# (grande, em duas linhas; uma faixa de luz atravessa as letras)
	_chamada = UI.label(CHAMADA, UI.fonte_que_cabe("titan", 84, 7, CHAMADA, 760), Jogo.LARANJA)
	UI.colocar(_chamada, CHAMADA_POS.x, CHAMADA_POS.y, 800, 184)
	_mat_chamada = ShaderMaterial.new()
	_mat_chamada.shader = load("res://shaders/brilho_texto.shader")
	_chamada.material = _mat_chamada
	add_child(_chamada)

	_montar_painel()

	# o "SWISH!" da demonstração (sempre o mesmo)
	_swish = UI.label("SWISH!", Jogo.fonte("titan", 44, 4), Jogo.AMARELO)
	_swish.rect_size = Vector2(400, 120)
	_swish.rect_pivot_offset = _swish.rect_size / 2
	_swish.visible = false
	add_child(_swish)

	# anel de "segurando SELECT"
	_anel_config = preload("res://scripts/anel_segurar.gd").new()
	UI.colocar(_anel_config, 540, 260, 200, 200)
	_anel_config.visible = false
	add_child(_anel_config)


func _montar_recorde() -> void:
	_rec = Cartao.new(Jogo.AMARELO, 18)
	UI.colocar(_rec, REC_POS.x, REC_POS.y, REC_TAM.x, REC_TAM.y)
	add_child(_rec)
	var f := Jogo.fonte("bungee", 18, 2)
	var t := UI.label("RECORDE", f, Jogo.AMARELO)
	var w := f.get_string_size("RECORDE").x
	UI.colocar(t, 0, 6, REC_TAM.x, 26)
	_rec.conteudo.add_child(t)
	# a coroa ao lado do título
	var coroa := TextureRect.new()
	coroa.texture = load("res://imagens/coroa.png")
	coroa.expand = true
	coroa.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coroa.mouse_filter = MOUSE_FILTER_IGNORE
	UI.colocar(coroa, (REC_TAM.x - w) * 0.5 - 40, 5, 34, 26)
	_rec.conteudo.add_child(coroa)
	_rec_led = preload("res://scripts/placar_led.gd").new()
	_rec_led.cor = Jogo.AMARELO
	_rec_led.contar = true
	UI.colocar(_rec_led, 26, 38, 278, 66)
	_rec.conteudo.add_child(_rec_led)


func _montar_painel() -> void:
	_painel = Cartao.new(Jogo.ROXO, 22)
	UI.colocar(_painel, PAINEL_POS.x, PAINEL_POS.y, PAINEL_TAM.x, PAINEL_TAM.y)
	add_child(_painel)
	_titulo = UI.label("RANKING", Jogo.fonte("titan", 40, 4), Jogo.AMARELO)
	UI.colocar(_titulo, 0, 10, PAINEL_TAM.x, 56)
	_painel.add_child(_titulo)
	# as duas páginas (prontas): só deslizam dentro do cartão
	for i in 2:
		var p := Control.new()
		p.mouse_filter = MOUSE_FILTER_IGNORE
		p.rect_size = PAINEL_TAM
		_painel.conteudo.add_child(p)
		_paginas.append(p)
	_montar_ranking(_paginas[0])
	_montar_como_jogar(_paginas[1])


static func _pilula(cor: Color, raio: int, borda := 0, cor_borda := Color(0, 0, 0, 0)) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = cor
	s.set_corner_radius_all(raio)
	s.corner_detail = 8
	s.anti_aliasing = true
	if borda > 0:
		s.set_border_width_all(borda)
		s.border_color = cor_borda
	p.add_stylebox_override("panel", s)
	return p


func _montar_ranking(pagina: Control) -> void:
	var cores_medalha := [Color(1.0, 0.80, 0.20), Color(0.82, 0.86, 0.95), Color(0.95, 0.58, 0.30)]
	var f_pts := Jogo.fonte("titan", 36, 3)
	var f_fase := Jogo.fonte("bungee", 15, 1)
	var f_data := Jogo.fonte("bungee", 13, 1)
	for i in 5:
		var linha := Control.new()
		linha.mouse_filter = MOUSE_FILTER_IGNORE
		UI.colocar(linha, LINHA_X, 78 + i * 68, 352, 62)
		pagina.add_child(linha)
		var tom: Color = cores_medalha[i] if i < 3 else Jogo.CIANO
		var fundo_linha := _pilula(Color(tom.r, tom.g, tom.b, 0.13 if i < 3 else 0.07), 16)
		fundo_linha.rect_size = linha.rect_size
		linha.add_child(fundo_linha)
		if i < 3:
			var m := TextureRect.new()
			m.texture = load("res://imagens/medalha_%d.png" % (i + 1))
			m.expand = true
			m.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			m.mouse_filter = MOUSE_FILTER_IGNORE
			UI.colocar(m, 6, 4, 54, 54)
			linha.add_child(m)
		else:
			var b := _pilula(Color(0.05, 0.25, 0.32, 0.9), 22, 2, Jogo.CIANO)
			UI.colocar(b, 11, 9, 44, 44)
			linha.add_child(b)
			var n := UI.label(str(i + 1), Jogo.fonte("titan", 24, 2), Jogo.CIANO)
			UI.colocar(n, 0, 0, 44, 44)
			b.add_child(n)
		var pts := UI.label("", f_pts, Jogo.BRANCO, Label.ALIGN_LEFT)
		UI.colocar(pts, 70, 0, 150, 62)
		linha.add_child(pts)
		var un := UI.label("PTS", f_data, Color(0.78, 0.76, 0.9), Label.ALIGN_LEFT)
		UI.colocar(un, 120, 25, 50, 24)
		linha.add_child(un)
		var fase := UI.label("", f_fase, tom, Label.ALIGN_RIGHT)
		UI.colocar(fase, 190, 7, 150, 26)
		linha.add_child(fase)
		var data := UI.label("", f_data, Color(0.78, 0.76, 0.9), Label.ALIGN_RIGHT)
		UI.colocar(data, 190, 31, 150, 24)
		linha.add_child(data)
		_linhas_rank.append({"no": linha, "pts": pts, "un": un, "fase": fase, "data": data})
	# ninguém jogou ainda
	_vazio = Control.new()
	_vazio.mouse_filter = MOUSE_FILTER_IGNORE
	_vazio.rect_size = PAINEL_TAM
	pagina.add_child(_vazio)
	var coroa := TextureRect.new()
	coroa.texture = load("res://imagens/coroa.png")
	coroa.expand = true
	coroa.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coroa.mouse_filter = MOUSE_FILTER_IGNORE
	UI.colocar(coroa, PAINEL_TAM.x * 0.5 - 60, 120, 120, 86)
	_vazio.add_child(coroa)
	var v := UI.label("SEJA O PRIMEIRO!", Jogo.fonte("bungee", 26, 2), Jogo.BRANCO)
	UI.colocar(v, 0, 222, PAINEL_TAM.x, 44)
	_vazio.add_child(v)
	var v2 := UI.label("ACERTE A CESTA E\nENTRE NO RANKING", Jogo.fonte("bungee", 18, 2), Jogo.AMARELO)
	UI.colocar(v2, 0, 272, PAINEL_TAM.x, 64)
	_vazio.add_child(v2)


func _montar_como_jogar(pagina: Control) -> void:
	var passos := [
		[Jogo.LARANJA, "ACERTE O MÁXIMO\nDE CESTAS"],
		[Jogo.VERDE, "BATA A META PARA\nPASSAR DE FASE"],
		[Jogo.VERMELHO, "%d SEGUIDAS =\nEM CHAMAS x2" % int(Jogo.valor("cestas_fogo"))],
		[Jogo.AMARELO, "ÚLTIMOS %d s:\nCESTA VALE %d" % [int(Jogo.valor("segundos_sprint")), int(Jogo.valor("pontos_sprint"))]],
	]
	var f := Jogo.fonte("bungee", 19, 2)
	for i in passos.size():
		var c: Color = passos[i][0]
		var linha := Control.new()
		linha.mouse_filter = MOUSE_FILTER_IGNORE
		UI.colocar(linha, LINHA_X, 80 + i * 84, 352, 76)
		pagina.add_child(linha)
		var fundo_linha := _pilula(Color(c.r, c.g, c.b, 0.10), 16)
		fundo_linha.rect_size = linha.rect_size
		linha.add_child(fundo_linha)
		var b := _pilula(Color(c.r * 0.25, c.g * 0.25, c.b * 0.25, 0.95), 22, 2, c)
		UI.colocar(b, 10, 16, 44, 44)
		linha.add_child(b)
		var n := UI.label(str(i + 1), Jogo.fonte("titan", 24, 2), c)
		UI.colocar(n, 0, 0, 44, 44)
		b.add_child(n)
		var l := UI.label(passos[i][1], f, Jogo.BRANCO, Label.ALIGN_LEFT)
		UI.colocar(l, 66, 2, 282, 72)
		linha.add_child(l)
		_linhas_como.append(l.get_parent())


## Os textos do ranking e do recorde (na entrada e quando a página volta).
func _preencher() -> void:
	var r: Array = Jogo.ranking
	for i in _linhas_rank.size():
		var d: Dictionary = _linhas_rank[i]
		var tem: bool = i < r.size()
		d.no.visible = tem
		if tem:
			d.pts.text = str(int(r[i].pontos))
			# "PTS" logo depois do número
			d.un.rect_position.x = 70 + d.pts.get_font("font").get_string_size(d.pts.text).x + 6
			var fase := int(r[i].get("fase", 1))
			d.fase.text = "FINAL" if fase >= 3 else "FASE %d" % fase
			d.data.text = str(r[i].get("data", ""))
	_vazio.visible = r.empty()


# ====================================================== capa (o app abrindo)
## O APP ABRE AQUI: a capa (a mesma imagem de abertura do app, parada)
## cobre a tela enquanto tudo da abertura é desenhado uma vez por baixo (as
## letras de cada fonte, os shaders, as medalhas, as duas páginas do
## cartão). Imagem parada não engasga: o trabalho da placa de vídeo fica
## aqui, antes de qualquer animação. Depois: a apresentação (se houver) ou
## a abertura.
func _preparar_na_capa() -> void:
	var capa := TextureRect.new()
	capa.texture = load("res://imagens/splash_lazer.png")
	capa.expand = true
	capa.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	capa.anchor_right = 1
	capa.anchor_bottom = 1
	capa.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(capa)
	# tudo à mostra por baixo da capa
	_preencher()
	_vazio.visible = true
	for d in _linhas_rank:
		d.no.visible = true
	for p in _paginas:
		p.visible = true
		p.rect_position = Vector2.ZERO
	_rec_led.mostrar_direto(888888)
	_bola.visible = true
	_bola.position = Vector2(700, 400)
	_swish.visible = true
	_anel_config.visible = true
	_explosao.emitting = true
	_mat_chamada.set_shader_param("forca", 1.0)
	_mat_chamada.set_shader_param("pos", 300.0)
	_rec.varrer()
	_painel.varrer()
	for i in 4:
		yield(get_tree(), "idle_frame")
	_bola.visible = false
	_swish.visible = false
	_anel_config.visible = false
	_explosao.restart()
	_explosao.emitting = false
	_mat_chamada.set_shader_param("forca", 0.0)
	if Jogo.tem_apresentacao():
		# a apresentação começa na mesma imagem: sem piscar
		Jogo.trocar_cena(Jogo.CENA_APRESENTACAO)
		capa.queue_free()
		return
	entrar(false)
	var tw := create_tween()
	tw.tween_property(capa, "modulate:a", 0.0, 0.4)
	tw.tween_callback(capa, "queue_free")


# ================================================================== entrar
## A abertura aparece (o app abrindo, a apresentação acabando ou a volta da
## partida/configuração): tudo do começo e a entrada em sequência.
func entrar(da_apresentacao := false) -> void:
	_saindo = false
	_t = 0.0
	_ocioso = 0.0
	_segurando = 0.0
	_proxima_bola = 3.2
	_proxima_troca = TROCA_PAINEL
	_proxima_varredura = 2.6
	_proximo_brilho = 1.4
	_brilho_chamada = -1.0
	_virando = false
	_anel_config.visible = false
	_bola.visible = false
	_swish.visible = false
	_chamada.text = CHAMADA
	_mat_chamada.set_shader_param("forca", 0.0)
	_matar_tweens()
	_preencher()
	_painel_modo = 0
	_paginas[0].visible = true
	_paginas[0].rect_position = Vector2.ZERO
	_paginas[1].visible = false
	_titulo.text = "RANKING"
	_titulo.add_color_override("font_color", Jogo.AMARELO)
	_painel.cor = Jogo.ROXO
	set_process(true)
	set_process_input(true)
	Leds.enviar("IDLE")
	Jogo.musica("abertura", -3.0)
	_entrada(da_apresentacao)


func sair() -> void:
	_saindo = true
	_matar_tweens()
	set_process(false)
	set_process_input(false)
	_anel_config.visible = false


func _novo_tween() -> SceneTreeTween:
	var tw := create_tween()
	_tweens.append(tw)
	return tw


func _matar_tweens() -> void:
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()


## A ENTRADA, peça por peça (da apresentação a arte já está na tela; vindo
## da cortina, ela ainda está clareando: começa um pouco depois).
func _entrada(da_apresentacao: bool) -> void:
	var a := 0.12 if da_apresentacao else 0.3
	# o recorde desce do alto e o LED conta até o recorde
	_rec.rect_position = REC_POS + Vector2(0, -190)
	_rec_led.mostrar_direto(0)
	var tr := _novo_tween()
	tr.tween_interval(a)
	tr.tween_property(_rec, "rect_position", REC_POS, 0.7).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tr.parallel().tween_callback(_rec_led, "set", ["valor", Jogo.recorde()]).set_delay(0.35)
	tr.tween_callback(_rec, "varrer")
	# o logo salta
	_logo.rect_scale = Vector2.ZERO
	var tl := _novo_tween()
	tl.tween_interval(a + 0.18)
	tl.tween_property(_logo, "rect_scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# o cartão chega da direita e as linhas entram uma a uma
	_painel.rect_position = PAINEL_POS + Vector2(470, 0)
	_titulo.rect_scale = Vector2(1, 0)
	var tp := _novo_tween()
	tp.tween_interval(a + 0.22)
	tp.tween_property(_painel, "rect_position", PAINEL_POS, 0.75).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tp.parallel().tween_property(_titulo, "rect_scale", Vector2.ONE, 0.45).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tp.tween_callback(_painel, "varrer")
	_linhas_entram(_paginas[0], a + 0.5)
	# a chamada cresce (sobe um pouco) e a luz passa nela
	_chamada.rect_scale = Vector2.ZERO
	_chamada.rect_position = CHAMADA_POS + Vector2(0, 36)
	var tc := _novo_tween()
	tc.tween_interval(a + 0.45)
	tc.tween_property(_chamada, "rect_scale", Vector2.ONE, 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tc.parallel().tween_property(_chamada, "rect_position", CHAMADA_POS, 0.65).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_proximo_brilho = a + 1.15


## As linhas de uma página entram deslizando da direita, uma depois da
## outra (cortadas na borda do cartão).
func _linhas_entram(pagina: Control, atraso: float) -> void:
	var k := 0
	for linha in pagina.get_children():
		if not (linha is Control) or linha == _vazio or not linha.visible:
			continue
		linha.rect_position.x = LINHA_X + PAINEL_TAM.x
		var tw := _novo_tween()
		tw.tween_interval(atraso + 0.07 * k)
		tw.tween_property(linha, "rect_position:x", LINHA_X, 0.55).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		k += 1
	if _vazio.get_parent() == pagina and _vazio.visible:
		_vazio.rect_scale = Vector2.ZERO
		_vazio.rect_pivot_offset = PAINEL_TAM * 0.5
		var tv := _novo_tween()
		tv.tween_interval(atraso)
		tv.tween_property(_vazio, "rect_scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ================================================================ por quadro
func _process(delta: float) -> void:
	_t += delta
	# parada há 1 minuto: a apresentação de novo (chama a atenção)
	_ocioso += delta
	if _ocioso >= OCIOSO_APRESENTACAO and not _saindo and Jogo.tem_apresentacao():
		_saindo = true
		Jogo.ir_para(Jogo.CENA_APRESENTACAO)
		return
	# chamada pulsando e trocando de cor (depois de entrar)
	var k: float = abs(sin(_t * 2.6))
	if _t > 1.6 and not _saindo:
		_chamada.rect_scale = Vector2.ONE * (1.0 + k * 0.05)
	_chamada.add_color_override("font_color", Jogo.LARANJA.linear_interpolate(Jogo.AMARELO, k))
	# a faixa de luz nas letras da chamada (de tempos em tempos)
	if _brilho_chamada < 0.0 and _t >= _proximo_brilho:
		_brilho_chamada = 0.0
		_proximo_brilho = _t + 3.6
	if _brilho_chamada >= 0.0:
		_brilho_chamada += delta
		var b := _brilho_chamada / 0.85
		_mat_chamada.set_shader_param("pos", lerp(-120.0, 1000.0, b))
		_mat_chamada.set_shader_param("forca", 0.75)
		if b >= 1.0:
			_brilho_chamada = -1.0
			_mat_chamada.set_shader_param("forca", 0.0)
	# halo da cesta da arte
	_halo.modulate = Color(1.0, 0.45, 0.1, 0.18 + abs(sin(_t * 1.7)) * 0.2)
	# brilho passando pelo logo a cada 5 s
	var ciclo := fmod(_t, 5.0) / 1.2
	if ciclo <= 1.0:
		_varredura.position = Vector2(lerp(80.0, 820.0, ciclo), 350)
		_varredura.modulate = Color(1, 1, 1, sin(ciclo * PI) * 0.55)
	else:
		_varredura.modulate.a = 0.0
	# a luz passa pelos cartões de vez em quando
	if _t >= _proxima_varredura:
		_proxima_varredura = _t + 6.5
		_rec.varrer()
	# bola demonstrando a cesta
	if _t >= _proxima_bola:
		_proxima_bola = _t + rand_range(4.5, 6.5)
		_bola_demo()
	# o cartão troca entre ranking e como jogar
	if _t >= _proxima_troca:
		_proxima_troca = _t + TROCA_PAINEL
		_virar_painel()
	# segurando SELECT para configuração
	if Input.is_action_pressed("input_select") and not _saindo:
		_segurando += delta
		_anel_config.visible = true
		_anel_config.progresso = _segurando / SEGURAR_CONFIG
		if _segurando >= SEGURAR_CONFIG:
			_ir("res://cenas/config.tscn")
	elif _segurando > 0.0:
		_segurando = 0.0
		_anel_config.visible = false


## Troca a página do cartão: a de agora sai pela esquerda, a outra chega da
## direita com as linhas uma a uma; o título vira e a borda muda de cor.
func _virar_painel() -> void:
	if _virando:
		return
	_virando = true
	var de: Control = _paginas[_painel_modo]
	_painel_modo = 1 - _painel_modo
	var para: Control = _paginas[_painel_modo]
	if _painel_modo == 0:
		_preencher()
	para.visible = true
	para.rect_position = Vector2.ZERO
	var tw := _novo_tween()
	tw.tween_property(de, "rect_position:x", -PAINEL_TAM.x, 0.34).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_titulo, "rect_scale", Vector2(1, 0), 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_painel, "cor", Jogo.ROXO if _painel_modo == 0 else Jogo.ROSA, 0.5)
	tw.parallel().tween_callback(self, "_titulo_da_pagina").set_delay(0.16)
	tw.parallel().tween_property(_titulo, "rect_scale", Vector2.ONE, 0.3).set_delay(0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(de, "set_visible", [false])
	tw.tween_interval(0.5)
	tw.tween_callback(self, "_virou")
	# (as linhas novas só chegam quando a página de agora já saiu: nada de
	# texto cruzando texto)
	_linhas_entram(para, 0.3)


func _titulo_da_pagina() -> void:
	_titulo.text = "RANKING" if _painel_modo == 0 else "COMO JOGAR"
	_titulo.add_color_override("font_color", Jogo.AMARELO if _painel_modo == 0 else Jogo.CIANO)


func _virou() -> void:
	_virando = false
	_painel.varrer()


# ============================================================ demonstração
func _bola_demo() -> void:
	var inicio := Vector2(rand_range(640, 820), 780)
	var topo := Vector2(lerp(inicio.x, CESTA_ARTE.x, 0.6), 20)
	_bola_arco = [inicio, topo, CESTA_ARTE + Vector2(0, 40)]
	_bola.visible = true
	_bola.modulate.a = 1.0
	_bola.position = inicio
	var tw := _novo_tween()
	tw.tween_method(self, "_arco", 0.0, 1.0, 1.25)
	tw.parallel().tween_property(_bola, "rotation", 7.0, 1.25).from(0.0)
	tw.parallel().tween_property(_bola, "scale", Vector2(0.26, 0.26), 1.25).from(Vector2(0.42, 0.42))
	tw.parallel().tween_property(_bola, "modulate:a", 0.0, 0.15).set_delay(1.1)
	tw.parallel().tween_callback(self, "_cesta_demo").set_delay(1.08)
	tw.tween_callback(_bola, "set_visible", [false])


func _arco(k: float) -> void:
	var a: Vector2 = _bola_arco[0]
	var t: Vector2 = _bola_arco[1]
	var c: Vector2 = _bola_arco[2]
	# curva de Bézier quadrática passando perto do topo
	var ctrl := t * 2.0 - (a + c) * 0.5
	_bola.position = a.linear_interpolate(ctrl, k).linear_interpolate(ctrl.linear_interpolate(c, k), k)


func _cesta_demo() -> void:
	_explosao.restart()
	fundo.flash(Jogo.LARANJA, 0.18)
	# à esquerda do aro, acima do cartão (não cobre o título dele); sai
	# encolhendo (texto com contorno nunca meio transparente)
	var de := CESTA_ARTE + Vector2(-190, 40)
	var ate := CESTA_ARTE + Vector2(-200, -10)
	_swish.rect_position = de - _swish.rect_size / 2
	_swish.rect_scale = Vector2(0.3, 0.3)
	_swish.visible = true
	var tw := _novo_tween()
	tw.tween_property(_swish, "rect_scale", Vector2(1.25, 1.25), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_swish, "rect_position", ate - _swish.rect_size / 2, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_swish, "rect_scale", Vector2(0.9, 0.9), 0.45)
	tw.tween_property(_swish, "rect_scale", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(_swish, "set_visible", [false])


# =================================================================== botões
func _input(ev: InputEvent) -> void:
	if _saindo:
		return
	if ev is InputEventKey or ev is InputEventJoypadButton:
		_ocioso = 0.0
	if ev.is_action_pressed("input_pointer") and not ev.is_echo():
		# a bola caiu na cesta: festa e começa
		Jogo.tocar("swish")
		Jogo.tocar("selecao", -4.0)
		_explosao.restart()
		fundo.flash(Jogo.LARANJA, 0.55)
		_chamada.text = "VAMOS JOGAR!"
		UI.pulsar(_chamada, 0.35)
		_saindo = true
		get_tree().create_timer(0.7).connect("timeout", self, "_ir", ["res://cenas/partida.tscn"])
	elif ev.is_action_pressed("input_start") and not ev.is_echo():
		Jogo.tocar("selecao")
		fundo.flash(Jogo.AMARELO, 0.5)
		UI.pulsar(_chamada, 0.3)
		_ir("res://cenas/partida.tscn")
	elif Jogo.pede_config(ev):
		# controle remoto da TV Box (MENU, VOLTAR ou seta)
		Jogo.tocar("selecao")
		_ir("res://cenas/config.tscn")


func _ir(cena: String) -> void:
	_saindo = true
	set_process_input(false)
	if cena.ends_with("partida.tscn"):
		Jogo.parar_musica(0.3)
	Jogo.ir_para(cena)
