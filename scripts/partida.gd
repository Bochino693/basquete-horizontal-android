extends Control

const UI = preload("res://scripts/ui.gd")

## PARTIDA DO SWISH ARENA (1 jogador), no estilo das máquinas Game On.
##
## - 3 fases. Nas duas primeiras há uma META de pontos: bateu, passa de fase
##   quando o tempo acaba; não bateu, fim de jogo. A 3ª é a final (sem meta).
## - Cesta = sinal do sensor (ação input_pointer), com trava contra sinal
##   repetido da mesma bola (Jogo.config.trava_sensor).
## - COMBO: cestas seguidas com menos de janela_fogo segundos entre elas.
##   Com cestas_fogo seguidas: EM CHAMAS, pontos x2 enquanto durar.
## - Últimos segundos_sprint de cada fase: a cesta vale pontos_sprint.
## - Fim: placar final contando, estatísticas, recorde e ranking.

enum { CONTAGEM, JOGANDO, ENTRE_FASES, RESULTADO }

const RIM := Vector2(640, 600)
const CENTRO_PLACAR := Vector2(640, 118)

var estado := CONTAGEM
var fases := []
var fase := 0
var tempo := 0.0
var pontos := 0
var pontos_fase := 0
var cestas := 0
var combo := 0
var maior_combo := 0
var meta_batida := false
var fogo_restante := 0.0
var _ultima_cesta_t := -100.0
var _trava_ate := 0.0
var _t := 0.0
var _ultimo_segundo := -1
var _sprint_avisado := false
var _tempo_resultado := 0.0
var _posicao_ranking := 0
var _novo_recorde := false
var _pode_reiniciar := false

# interface
var fundo
var cesta
var placar
var anel
var lbl_fase: Label
var lbl_meta: Label
var barra_meta: Control
var painel_placar: Panel
var painel_fase: Panel
var painel_tempo: Panel
var chip_combo: Label
var chip_fogo: Label
var chip_sprint: Label
var lbl_cestas: Label
var lbl_recorde_val
var camada_fx: Control
var camada_topo: CanvasLayer
var chamas_tela: CPUParticles2D
var _tremor := 0.0
var _raiz: Control

# fontes
var f_titulo: Font
var f_titulo_grande: Font
var f_sub: Font
var f_painel: Font
var f_painel_p: Font
var f_numero_gigante: Font
var f_flutua: Font


func _ready() -> void:
	fases = Jogo.fases()
	f_titulo = Jogo.fonte("titan", 84, 6)
	f_titulo_grande = Jogo.fonte("titan", 120, 8)
	f_sub = Jogo.fonte("bungee", 30, 3)
	f_painel = Jogo.fonte("bungee", 22, 2)
	f_painel_p = Jogo.fonte("bungee", 17, 2)
	f_numero_gigante = Jogo.fonte("titan", 220, 10)
	f_flutua = Jogo.fonte("titan", 64, 5)
	for f in [f_titulo, f_titulo_grande, f_flutua]:
		Jogo.preaquecer(f, "0123456789+xX!ÇÃÉÊÍÓÚ ABCDEFGHIJKLMNOPQRSTUVWXYZ")
	Jogo.preaquecer(f_numero_gigante, "123VAI!")
	_montar()
	Leds.enviar("PLAY")
	Jogo.musica("partida", -2.0)
	_iniciar_fase(0)


# ================================================================ MONTAGEM
func _montar() -> void:
	_raiz = Control.new()
	_raiz.anchor_right = 1
	_raiz.anchor_bottom = 1
	_raiz.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_raiz)

	fundo = preload("res://scripts/fundo_animado.gd").new()
	fundo.imagem = "res://imagens/fundo_arena.png"
	fundo.mascara = "res://imagens/fundo_arena_mascara.png"
	fundo.holofotes = [Vector2(120, 32), Vector2(373, 32), Vector2(907, 32), Vector2(1160, 32)]
	fundo.qtd_feixes = 2
	fundo.escurecer = 0.0
	_raiz.add_child(fundo)

	cesta = preload("res://scripts/cesta.gd").new()
	cesta.position = RIM
	_raiz.add_child(cesta)

	chamas_tela = _criar_chamas_da_tela()
	_raiz.add_child(chamas_tela)

	# ---- placar central (LED gigante)
	painel_placar = UI.painel(Jogo.LARANJA)
	UI.colocar(painel_placar, 300, 16, 680, 186)
	_raiz.add_child(painel_placar)
	var t_pontos := UI.label("PONTOS", f_painel, Jogo.AMARELO)
	UI.colocar(t_pontos, 0, 8, 680, 30)
	painel_placar.add_child(t_pontos)
	placar = preload("res://scripts/placar_led.gd").new()
	placar.digitos = 6
	placar.cor = Jogo.LARANJA
	UI.colocar(placar, 40, 46, 600, 118)
	painel_placar.add_child(placar)

	# ---- fase + meta (esquerda)
	painel_fase = UI.painel(Jogo.ROXO)
	UI.colocar(painel_fase, 24, 16, 256, 186)
	_raiz.add_child(painel_fase)
	lbl_fase = UI.label("FASE 1", Jogo.fonte("titan", 50, 4), Jogo.BRANCO)
	UI.colocar(lbl_fase, 0, 10, 256, 64)
	painel_fase.add_child(lbl_fase)
	lbl_meta = UI.label("META 30", f_painel, Jogo.CIANO)
	UI.colocar(lbl_meta, 0, 80, 256, 32)
	painel_fase.add_child(lbl_meta)
	barra_meta = preload("res://scripts/barra_meta.gd").new()
	UI.colocar(barra_meta, 22, 122, 212, 40)
	painel_fase.add_child(barra_meta)

	# ---- tempo (direita)
	painel_tempo = UI.painel(Jogo.VERDE)
	UI.colocar(painel_tempo, 1000, 16, 256, 186)
	_raiz.add_child(painel_tempo)
	anel = preload("res://scripts/anel_tempo.gd").new()
	UI.colocar(anel, 38, 3, 180, 180)
	painel_tempo.add_child(anel)

	# ---- chips de estado (embaixo do placar)
	chip_combo = _chip("COMBO x2", Jogo.CIANO)
	UI.colocar(chip_combo, 300, 214, 216, 46)
	chip_fogo = _chip("EM CHAMAS x2", Jogo.VERMELHO)
	UI.colocar(chip_fogo, 532, 214, 216, 46)
	chip_sprint = _chip("CESTA VALE 3", Jogo.AMARELO)
	UI.colocar(chip_sprint, 764, 214, 216, 46)
	for c in [chip_combo, chip_fogo, chip_sprint]:
		c.visible = false

	# ---- laterais de baixo: recorde e cestas
	var p_rec := UI.painel(Jogo.AMARELO, Color(0.04, 0.02, 0.10, 0.7), 16, 2, 12)
	UI.colocar(p_rec, 24, 560, 300, 130)
	_raiz.add_child(p_rec)
	var t_rec := UI.label("RECORDE", f_painel_p, Jogo.AMARELO)
	UI.colocar(t_rec, 0, 8, 300, 26)
	p_rec.add_child(t_rec)
	lbl_recorde_val = preload("res://scripts/placar_led.gd").new()
	lbl_recorde_val.cor = Jogo.AMARELO
	lbl_recorde_val.contar = false
	UI.colocar(lbl_recorde_val, 24, 44, 252, 66)
	p_rec.add_child(lbl_recorde_val)
	lbl_recorde_val.mostrar_direto(Jogo.recorde())

	var p_cestas := UI.painel(Jogo.CIANO, Color(0.04, 0.02, 0.10, 0.7), 16, 2, 12)
	UI.colocar(p_cestas, 956, 560, 300, 130)
	_raiz.add_child(p_cestas)
	var t_c := UI.label("CESTAS", f_painel_p, Jogo.CIANO)
	UI.colocar(t_c, 0, 8, 300, 26)
	p_cestas.add_child(t_c)
	lbl_cestas = UI.label("0", Jogo.fonte("titan", 64, 5), Jogo.BRANCO)
	UI.colocar(lbl_cestas, 0, 36, 300, 84)
	p_cestas.add_child(lbl_cestas)

	camada_fx = Control.new()
	camada_fx.anchor_right = 1
	camada_fx.anchor_bottom = 1
	camada_fx.mouse_filter = MOUSE_FILTER_IGNORE
	_raiz.add_child(camada_fx)

	camada_topo = CanvasLayer.new()
	camada_topo.layer = 10
	add_child(camada_topo)

	# entrada animada de tudo
	UI.deslizar(painel_placar, Vector2(0, -240), 0.05)
	UI.deslizar(painel_fase, Vector2(-320, 0), 0.15)
	UI.deslizar(painel_tempo, Vector2(320, 0), 0.15)
	UI.deslizar(p_rec, Vector2(-360, 0), 0.30)
	UI.deslizar(p_cestas, Vector2(360, 0), 0.30)
	UI.pop(cesta, 0.25, 0.6)


func _chip(texto: String, cor: Color) -> Label:
	var fundo_chip := StyleBoxFlat.new()
	fundo_chip.bg_color = Color(cor.r * 0.25, cor.g * 0.25, cor.b * 0.25, 0.9)
	fundo_chip.border_color = cor
	fundo_chip.set_border_width_all(2)
	fundo_chip.set_corner_radius_all(23)
	fundo_chip.shadow_color = Color(cor.r, cor.g, cor.b, 0.5)
	fundo_chip.shadow_size = 10
	var l := UI.label(texto, f_painel, cor.lightened(0.35))
	l.add_stylebox_override("normal", fundo_chip)
	_raiz.add_child(l)
	return l


func _criar_chamas_da_tela() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	var aditivo := CanvasItemMaterial.new()
	aditivo.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = aditivo
	p.texture = load("res://imagens/brilho.png")
	p.amount = 40
	p.lifetime = 1.1
	p.position = Vector2(640, 740)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(660, 10)
	p.direction = Vector2(0, -1)
	p.spread = 8
	p.gravity = Vector2(0, -120)
	p.initial_velocity = 170
	p.initial_velocity_random = 0.5
	p.scale_amount = 0.45
	p.scale_amount_random = 0.6
	var rampa := Gradient.new()
	rampa.set_color(0, Color(1, 0.9, 0.4, 0.8))
	rampa.set_color(1, Color(0.7, 0.0, 0.2, 0.0))
	rampa.add_point(0.4, Color(1, 0.35, 0.05, 0.6))
	p.color_ramp = rampa
	p.emitting = false
	return p


# ================================================================== FASES
func _iniciar_fase(i: int) -> void:
	fase = i
	var f: Dictionary = fases[i]
	tempo = float(f.tempo)
	pontos_fase = 0
	meta_batida = f.meta <= 0
	_sprint_avisado = false
	_ultimo_segundo = -1
	anel.total = tempo
	anel.restante = tempo
	anel.alerta = float(Jogo.valor("segundos_sprint"))
	var final := i == fases.size() - 1
	lbl_fase.text = "FINAL" if final else "FASE %d" % (i + 1)
	lbl_meta.text = "VALENDO TUDO!" if final else "META %d" % f.meta
	barra_meta.meta = f.meta
	barra_meta.valor = 0
	UI.pulsar(painel_fase, 0.25)
	estado = CONTAGEM
	var titulo := "FINAL!" if final else "FASE %d" % (i + 1)
	var sub := "FAÇA O MÁXIMO DE PONTOS" if final else "META: %d PONTOS EM %d s" % [f.meta, f.tempo]
	yield(_banner(titulo, sub, Jogo.ROXO if not final else Jogo.ROSA, 1.7), "completed")
	yield(_contagem(), "completed")
	estado = JOGANDO
	_trava_ate = 0.0


func _contagem() -> void:
	for n in ["3", "2", "1"]:
		Jogo.tocar("bip")
		_numero_grande(n, Jogo.AMARELO)
		yield(get_tree().create_timer(0.8), "timeout")
	Jogo.tocar("apito")
	Jogo.tocar("vai")
	_numero_grande("VAI!", Jogo.VERDE)
	fundo.flash(Jogo.VERDE, 0.4)
	yield(get_tree().create_timer(0.1), "timeout")


func _numero_grande(texto: String, cor: Color) -> void:
	var l := UI.label(texto, f_numero_gigante, cor)
	UI.colocar(l, 0, 150, 1280, 320)
	l.rect_pivot_offset = Vector2(640, 160)
	camada_fx.add_child(l)
	var tw := Tween.new()
	l.add_child(tw)
	tw.interpolate_property(l, "rect_scale", Vector2(2.4, 2.4), Vector2.ONE, 0.35, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw.interpolate_property(l, "modulate:a", 0.0, 1.0, 0.15)
	tw.interpolate_property(l, "rect_scale", Vector2.ONE, Vector2(0.6, 0.6), 0.3, Tween.TRANS_SINE, Tween.EASE_IN, 0.5)
	tw.interpolate_property(l, "modulate:a", 1.0, 0.0, 0.3, Tween.TRANS_SINE, Tween.EASE_IN, 0.5)
	tw.interpolate_callback(l, 0.82, "queue_free")
	tw.start()


## Faixa grande no meio da tela: título + subtítulo, entra e sai animada.
func _banner(titulo: String, sub: String, cor: Color, dur: float) -> void:
	_tirar_aviso()
	var faixa := ColorRect.new()
	faixa.color = Color(cor.r * 0.35, cor.g * 0.35, cor.b * 0.35, 0.92)
	UI.colocar(faixa, 0, 250, 1280, 220)
	camada_fx.add_child(faixa)
	var borda1 := ColorRect.new()
	borda1.color = cor
	UI.colocar(borda1, 0, 0, 1280, 5)
	faixa.add_child(borda1)
	var borda2 := ColorRect.new()
	borda2.color = cor
	UI.colocar(borda2, 0, 215, 1280, 5)
	faixa.add_child(borda2)
	var lt := UI.label(titulo, UI.fonte_que_cabe("titan", 120, 8, titulo, 1180), Jogo.BRANCO)
	UI.colocar(lt, 0, 10, 1280, 140)
	faixa.add_child(lt)
	var ls := UI.label(sub, UI.fonte_que_cabe("bungee", 30, 3, sub, 1180), cor.lightened(0.5))
	UI.colocar(ls, 0, 150, 1280, 50)
	faixa.add_child(ls)
	var tw := Tween.new()
	faixa.add_child(tw)
	faixa.rect_pivot_offset = Vector2(640, 110)
	tw.interpolate_property(faixa, "rect_scale", Vector2(1, 0), Vector2(1, 1), 0.28, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw.interpolate_property(lt, "rect_position:x", -900.0, 0.0, 0.45, Tween.TRANS_QUINT, Tween.EASE_OUT, 0.1)
	tw.interpolate_property(ls, "rect_position:x", 900.0, 0.0, 0.45, Tween.TRANS_QUINT, Tween.EASE_OUT, 0.18)
	tw.interpolate_property(faixa, "rect_scale", Vector2(1, 1), Vector2(1, 0), 0.25, Tween.TRANS_SINE, Tween.EASE_IN, dur)
	tw.interpolate_callback(faixa, dur + 0.26, "queue_free")
	tw.start()
	Jogo.tocar("selecao", -3.0)
	yield(get_tree().create_timer(dur + 0.26), "timeout")


# ================================================================== CESTA
func _input(ev: InputEvent) -> void:
	if ev.is_action_pressed("input_pointer") and not ev.is_echo():
		if estado == RESULTADO:
			# no resultado, uma cesta joga de novo (depois de 3 s: a bola
			# que ainda caía no fim do tempo não reinicia sem querer)
			if _pode_reiniciar and _tempo_resultado <= 14.0 - 3.0:
				_jogar_de_novo()
		else:
			_sensor()
	elif ev.is_action_pressed("input_start") and not ev.is_echo():
		if estado == RESULTADO and _pode_reiniciar:
			_jogar_de_novo()


func _jogar_de_novo() -> void:
	if Jogo.trocando():
		return
	Jogo.tocar("selecao")
	Jogo.ir_para("res://cenas/partida.tscn")


func _sensor() -> void:
	if estado != JOGANDO:
		return
	if _t < _trava_ate:
		return
	_trava_ate = _t + float(Jogo.valor("trava_sensor"))
	_cesta()


func _cesta() -> void:
	cestas += 1
	# combo e EM CHAMAS
	if _t - _ultima_cesta_t <= float(Jogo.valor("janela_fogo")):
		combo += 1
	else:
		combo = 1
	_ultima_cesta_t = _t
	maior_combo = max(maior_combo, combo)
	var entrou_fogo := false
	if combo >= int(Jogo.valor("cestas_fogo")):
		if fogo_restante <= 0.0:
			entrou_fogo = true
		fogo_restante = float(Jogo.valor("duracao_fogo"))

	var sprint := tempo <= float(Jogo.valor("segundos_sprint"))
	var valor_cesta := int(Jogo.valor("pontos_sprint")) if sprint else int(Jogo.valor("pontos_cesta"))
	if fogo_restante > 0.0:
		valor_cesta *= 2
	pontos += valor_cesta
	pontos_fase += valor_cesta
	placar.valor = pontos
	barra_meta.valor = pontos_fase
	lbl_cestas.text = str(cestas)
	UI.pulsar(lbl_cestas, 0.3)
	UI.pulsar(painel_placar, 0.06, 0.25)

	var cor := Jogo.VERMELHO if fogo_restante > 0.0 else (Jogo.AMARELO if sprint else Jogo.LARANJA)
	cesta.anotar(cor)
	fundo.flash(cor, 0.22 if combo < 3 else 0.35)
	_tremor = 6.0 if fogo_restante > 0.0 else 3.0
	# o "+2" sobe do aro e some dentro da tabela: não cruza os avisos nem o
	# placar (texto nenhum em cima de outro)
	UI.flutuar(camada_fx, "+%d" % valor_cesta, f_flutua, cor.lightened(0.3), RIM + Vector2(0, -40), RIM + Vector2(0, -105), 0.8)

	Jogo.tocar("swish", 0.0, rand_range(0.95, 1.05))
	if combo >= 2:
		Jogo.tocar("combo_%d" % min(combo - 1, 12), 1.0)
		chip_combo.text = "COMBO x%d" % combo
		if not chip_combo.visible:
			chip_combo.visible = true
			UI.pop(chip_combo)
		else:
			UI.pulsar(chip_combo, 0.25)
		if combo in [3, 5, 8, 10, 15, 20]:
			_aviso(_frase_combo(combo), Jogo.CIANO, 1.1)
	else:
		Jogo.tocar("ponto", -4.0)
	Leds.enviar("HIT")

	if entrou_fogo:
		_entrar_fogo()

	if not meta_batida and pontos_fase >= fases[fase].meta:
		meta_batida = true
		Jogo.tocar("fase")
		_aviso("META BATIDA!", Jogo.VERDE, 1.6)
		fundo.flash(Jogo.VERDE, 0.45)
		UI.cor_painel(painel_fase, Jogo.VERDE)


## AVISOS GRANDES (EM CHAMAS, combo, meta, últimos segundos): sempre no
## MESMO lugar (parte de cima da tabela, abaixo dos selos) e um de cada vez:
## o novo tira o anterior na hora, então nunca ficam um em cima do outro.
var _aviso_atual: Label


func _aviso(texto: String, cor: Color, dur: float, grande := false) -> void:
	if _aviso_atual != null and is_instance_valid(_aviso_atual):
		_aviso_atual.queue_free()
	var f := UI.fonte_que_cabe("titan", 88 if grande else 72, 6, texto, 960)
	var l := UI.label(texto, f, cor)
	UI.colocar(l, 160, 332, 960, 106)
	camada_fx.add_child(l)
	_aviso_atual = l
	var tw := Tween.new()
	l.add_child(tw)
	tw.interpolate_property(l, "rect_scale", Vector2(0.3, 0.3), Vector2(1.08, 1.08), 0.2, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw.interpolate_property(l, "rect_scale", Vector2(1.08, 1.08), Vector2.ONE, 0.15, Tween.TRANS_SINE, Tween.EASE_OUT, 0.2)
	tw.interpolate_property(l, "modulate:a", 1.0, 0.0, 0.25, Tween.TRANS_SINE, Tween.EASE_IN, dur - 0.25)
	tw.interpolate_callback(l, dur, "queue_free")
	tw.start()


func _tirar_aviso() -> void:
	if _aviso_atual != null and is_instance_valid(_aviso_atual):
		_aviso_atual.queue_free()
	_aviso_atual = null


func _frase_combo(n: int) -> String:
	match n:
		3: return "EM SEQUÊNCIA!"
		5: return "IMPARÁVEL!"
		8: return "MÃO QUENTE!"
		10: return "LENDÁRIO!"
	return "COMBO x%d!" % n


func _entrar_fogo() -> void:
	Jogo.tocar("fogo", 2.0)
	Leds.enviar("BOOST")
	cesta.em_chamas = true
	chamas_tela.emitting = true
	fundo.intensidade = 2.2
	placar.cor = Jogo.AMARELO
	UI.cor_painel(painel_placar, Jogo.VERMELHO)
	chip_fogo.visible = true
	UI.pop(chip_fogo)
	_aviso("EM CHAMAS!", Color(1, 0.55, 0.1), 1.5, true)


func _sair_fogo() -> void:
	cesta.em_chamas = false
	chamas_tela.emitting = false
	fundo.intensidade = 1.0
	placar.cor = Jogo.LARANJA
	UI.cor_painel(painel_placar, Jogo.LARANJA)
	UI.sumir(chip_fogo, 0.0, 0.3, false)
	yield(get_tree().create_timer(0.31), "timeout")
	chip_fogo.visible = false
	chip_fogo.modulate.a = 1.0


# ================================================================== RELÓGIO
func _process(delta: float) -> void:
	_t += delta
	# tremor da tela
	if _tremor > 0.0:
		_tremor = max(0.0, _tremor - delta * 30.0)
		_raiz.rect_position = Vector2(rand_range(-_tremor, _tremor), rand_range(-_tremor, _tremor))
	elif _raiz.rect_position != Vector2.ZERO:
		_raiz.rect_position = Vector2.ZERO
	if estado == RESULTADO:
		_processar_resultado(delta)
		return
	if estado != JOGANDO:
		return
	tempo = max(0.0, tempo - delta)
	anel.restante = tempo
	# combo acaba se demorar
	if combo > 0 and _t - _ultima_cesta_t > float(Jogo.valor("janela_fogo")):
		combo = 0
		if chip_combo.visible:
			UI.sumir(chip_combo, 0.0, 0.25, false)
			get_tree().create_timer(0.26).connect("timeout", self, "_esconder_chip", [chip_combo])
	if fogo_restante > 0.0:
		fogo_restante -= delta
		if fogo_restante <= 0.0:
			_sair_fogo()
	# últimos segundos
	var seg := int(ceil(tempo))
	if seg != _ultimo_segundo:
		_ultimo_segundo = seg
		if seg <= 5 and seg > 0:
			Jogo.tocar("tique")
	if not _sprint_avisado and tempo <= float(Jogo.valor("segundos_sprint")):
		_sprint_avisado = true
		chip_sprint.text = "CESTA VALE %d" % int(Jogo.valor("pontos_sprint"))
		chip_sprint.visible = true
		UI.pop(chip_sprint)
		_aviso("ÚLTIMOS %d s!" % int(Jogo.valor("segundos_sprint")), Jogo.AMARELO, 1.4)
		fundo.flash(Jogo.AMARELO, 0.35)
		UI.cor_painel(painel_tempo, Jogo.VERMELHO)
	if tempo <= 0.0:
		_fim_da_fase()


func _esconder_chip(chip: Control) -> void:
	if combo == 0:
		chip.visible = false
	chip.modulate.a = 1.0


func _fim_da_fase() -> void:
	estado = ENTRE_FASES
	Jogo.tocar("buzina")
	if fogo_restante > 0.0:
		fogo_restante = 0.0
		_sair_fogo()
	combo = 0
	chip_combo.visible = false
	chip_sprint.visible = false
	UI.cor_painel(painel_tempo, Jogo.VERDE)
	yield(get_tree().create_timer(1.2), "timeout")
	var ultima := fase >= fases.size() - 1
	if meta_batida and not ultima:
		yield(_banner("FASE CONCLUÍDA!", "%d PONTOS NESTA FASE" % pontos_fase, Jogo.VERDE, 1.6), "completed")
		UI.cor_painel(painel_fase, Jogo.ROXO)
		_iniciar_fase(fase + 1)
	else:
		if not meta_batida:
			Jogo.tocar("alerta")
			yield(_banner("NÃO BATEU A META", "FALTARAM %d PONTOS" % (fases[fase].meta - pontos_fase), Jogo.VERMELHO, 1.8), "completed")
		_mostrar_resultado(ultima and meta_batida)


# ================================================================ RESULTADO
func _mostrar_resultado(campeao: bool) -> void:
	estado = RESULTADO
	_tirar_aviso()
	_tempo_resultado = 14.0
	_posicao_ranking = Jogo.registrar_partida(pontos, fase + 1, cestas)
	_novo_recorde = _posicao_ranking == 1
	Jogo.parar_musica(0.4)
	Jogo.tocar("fim")

	var escuro := ColorRect.new()
	escuro.color = Color(0.02, 0.0, 0.06, 0.0)
	escuro.anchor_right = 1
	escuro.anchor_bottom = 1
	camada_topo.add_child(escuro)
	var tw := Tween.new()
	escuro.add_child(tw)
	tw.interpolate_property(escuro, "color:a", 0.0, 0.78, 0.4)
	tw.start()

	var cor := Jogo.AMARELO if (_novo_recorde or campeao) else Jogo.LARANJA
	var p := UI.painel(cor, Color(0.05, 0.02, 0.12, 0.95), 26, 4, 30)
	p.name = "Resultado"
	UI.colocar(p, 190, 60, 900, 600)
	camada_topo.add_child(p)
	UI.pop(p, 0.15, 0.5)

	var titulo := "NOVO RECORDE!" if _novo_recorde else ("CAMPEÃO!" if campeao else "FIM DE JOGO")
	var lt := UI.label(titulo, f_titulo, cor)
	UI.colocar(lt, 0, 24, 900, 100)
	p.add_child(lt)
	UI.pop(lt, 0.45, 0.5)

	var lp := UI.label("SUA PONTUAÇÃO", f_painel, Jogo.BRANCO)
	UI.colocar(lp, 0, 132, 900, 30)
	p.add_child(lp)
	var final_led = preload("res://scripts/placar_led.gd").new()
	final_led.cor = cor
	UI.colocar(final_led, 150, 170, 600, 130)
	p.add_child(final_led)
	final_led.mostrar_direto(0)
	get_tree().create_timer(0.7).connect("timeout", final_led, "set", ["valor", pontos])

	var stats := [["CESTAS", str(cestas), Jogo.CIANO], ["MAIOR COMBO", "x%d" % maior_combo, Jogo.ROSA],
		["FASE", "FINAL" if fase == fases.size() - 1 else str(fase + 1), Jogo.ROXO]]
	for i in range(stats.size()):
		var s: Array = stats[i]
		var caixa := UI.painel(s[2], Color(0.08, 0.04, 0.16, 0.9), 16, 2, 8)
		UI.colocar(caixa, 60 + i * 270, 325, 240, 110)
		p.add_child(caixa)
		var a := UI.label(s[0], f_painel_p, s[2])
		UI.colocar(a, 0, 10, 240, 26)
		caixa.add_child(a)
		var b := UI.label(s[1], Jogo.fonte("titan", 52, 4), Jogo.BRANCO)
		UI.colocar(b, 0, 36, 240, 66)
		caixa.add_child(b)
		UI.pop(caixa, 0.9 + i * 0.15, 0.4)

	var texto_rank := ""
	if _posicao_ranking > 0:
		texto_rank = "VOCÊ FICOU EM %dº NO RANKING!" % _posicao_ranking
	else:
		texto_rank = "RECORDE DA MÁQUINA: %d" % Jogo.recorde()
	var lr := UI.label(texto_rank, f_sub, Jogo.VERDE if _posicao_ranking > 0 else Jogo.BRANCO)
	UI.colocar(lr, 0, 455, 900, 50)
	p.add_child(lr)
	UI.pop(lr, 1.4, 0.4)

	var lj := UI.label("ACERTE A CESTA PARA JOGAR DE NOVO", f_painel, Jogo.AMARELO)
	lj.name = "Chamada"
	UI.colocar(lj, 0, 520, 900, 34)
	p.add_child(lj)
	var lv := UI.label("", f_painel_p, Color(1, 1, 1, 0.7))
	lv.name = "Volta"
	UI.colocar(lv, 0, 556, 900, 26)
	p.add_child(lv)

	if _novo_recorde:
		Leds.enviar("RECORD")
		get_tree().create_timer(0.9).connect("timeout", self, "_festa_recorde")
	elif campeao or _posicao_ranking > 0:
		get_tree().create_timer(0.9).connect("timeout", Jogo, "musica", ["resultado"])
	get_tree().create_timer(1.6).connect("timeout", self, "set", ["_pode_reiniciar", true])


func _festa_recorde() -> void:
	Jogo.tocar("recorde")
	Jogo.musica("resultado")
	lbl_recorde_val.mostrar_direto(pontos)
	var confete := CPUParticles2D.new()
	confete.texture = load("res://imagens/estrela.png")
	confete.amount = 90
	confete.lifetime = 3.0
	confete.position = Vector2(640, -20)
	confete.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confete.emission_rect_extents = Vector2(640, 10)
	confete.direction = Vector2(0, 1)
	confete.spread = 30
	confete.gravity = Vector2(0, 220)
	confete.initial_velocity = 120
	confete.angular_velocity = 180
	confete.angular_velocity_random = 1.0
	confete.scale_amount = 0.35
	confete.scale_amount_random = 0.6
	confete.hue_variation = 1.0
	confete.hue_variation_random = 1.0
	confete.color = Color(1, 0.3, 0.3)
	camada_topo.add_child(confete)
	# atrás do painel: o confete não passa por cima dos textos
	var painel_res := camada_topo.get_node_or_null("Resultado")
	if painel_res != null:
		camada_topo.move_child(confete, painel_res.get_index())


func _processar_resultado(delta: float) -> void:
	_tempo_resultado -= delta
	var p := camada_topo.get_node_or_null("Resultado")
	if p != null:
		var chamada: Label = p.get_node_or_null("Chamada")
		if chamada != null:
			chamada.modulate.a = 0.55 + abs(sin(_t * 3.0)) * 0.45
		var volta: Label = p.get_node_or_null("Volta")
		if volta != null:
			volta.text = "VOLTA AO INÍCIO EM %d" % int(ceil(max(_tempo_resultado, 0.0)))
	if _tempo_resultado <= 0.0 and not Jogo.trocando():
		Jogo.ir_para("res://cenas/abertura.tscn")
