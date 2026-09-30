extends Control

const UI = preload("res://scripts/ui.gd")

## ABERTURA (tela de espera): a arte SWISH ARENA viva, bola voando para a
## cesta de tempos em tempos, APERTE START pulsando, recorde em LED e um
## painel que gira entre o RANKING e o COMO JOGAR.
## START começa a partida. Segurar SELECT (ou F10 no PC) abre a configuração.

const CESTA_ARTE := Vector2(1132, 160)   # onde fica o aro na arte de abertura
const SEGURAR_CONFIG := 4.0

var fundo
var _t := 0.0
var _proxima_bola := 2.5
var _painel: Panel
var _painel_modo := 0
var _proxima_troca := 7.0
var _chamada: Label
var _sub: Label
var _varredura: Sprite
var _halo: Sprite
var _segurando := 0.0
var _anel_config: Control
var _explosao: CPUParticles2D
var _saindo := false
var _tex_bola: Texture


func _ready() -> void:
	_tex_bola = load("res://imagens/bola.png")
	fundo = preload("res://scripts/fundo_animado.gd").new()
	fundo.imagem = "res://imagens/fundo_abertura.png"
	fundo.qtd_faiscas = 44
	add_child(fundo)

	var aditivo := CanvasItemMaterial.new()
	aditivo.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_halo = Sprite.new()
	_halo.texture = load("res://imagens/brilho.png")
	_halo.material = aditivo
	_halo.position = CESTA_ARTE + Vector2(0, 30)
	_halo.scale = Vector2(1.6, 1.2)
	add_child(_halo)

	_varredura = Sprite.new()
	_varredura.texture = load("res://imagens/brilho.png")
	_varredura.material = aditivo
	_varredura.scale = Vector2(0.45, 2.1)
	_varredura.rotation_degrees = 18
	_varredura.modulate = Color(1, 1, 1, 0.0)
	add_child(_varredura)

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

	# recorde (canto de cima)
	var p_rec := UI.painel(Jogo.AMARELO, Color(0.04, 0.02, 0.10, 0.75), 16, 2, 14)
	UI.colocar(p_rec, 28, 22, 330, 118)
	add_child(p_rec)
	var t := UI.label("RECORDE", Jogo.fonte("bungee", 18, 2), Jogo.AMARELO)
	UI.colocar(t, 0, 6, 330, 26)
	p_rec.add_child(t)
	var led = preload("res://scripts/placar_led.gd").new()
	led.cor = Jogo.AMARELO
	led.contar = false
	UI.colocar(led, 26, 38, 278, 66)
	p_rec.add_child(led)
	led.mostrar_direto(Jogo.recorde())
	UI.deslizar(p_rec, Vector2(-400, 0), 0.3)

	# logo da empresa ao lado do recorde
	var logo := TextureRect.new()
	logo.texture = load("res://imagens/logo_lazer_sport.png")
	logo.expand = true
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	UI.colocar(logo, 376, 22, 178, 118)
	add_child(logo)
	UI.pop(logo, 0.5)

	# APERTE START
	_chamada = UI.label("APERTE START", Jogo.fonte("titan", 76, 7), Jogo.LARANJA)
	UI.colocar(_chamada, 60, 560, 760, 96)
	add_child(_chamada)
	_sub = UI.label("JOGUE E ENTRE PARA O RANKING!", Jogo.fonte("bungee", 24, 3), Jogo.CIANO)
	UI.colocar(_sub, 60, 652, 760, 40)
	add_child(_sub)
	UI.pop(_chamada, 0.6, 0.6)
	UI.deslizar(_sub, Vector2(0, 80), 0.8)

	# painel ranking / como jogar
	_painel = UI.painel(Jogo.ROXO, Color(0.05, 0.02, 0.12, 0.85), 22, 3, 22)
	UI.colocar(_painel, 868, 262, 384, 430)
	add_child(_painel)
	_montar_painel()
	UI.deslizar(_painel, Vector2(460, 0), 0.5)

	# anel de "segurando SELECT"
	_anel_config = preload("res://scripts/anel_segurar.gd").new()
	UI.colocar(_anel_config, 540, 260, 200, 200)
	_anel_config.visible = false
	add_child(_anel_config)

	Leds.enviar("IDLE")
	Jogo.musica("abertura", -3.0)


func _montar_painel() -> void:
	for c in _painel.get_children():
		c.queue_free()
	var cor := Jogo.AMARELO if _painel_modo == 0 else Jogo.CIANO
	UI.cor_painel(_painel, Jogo.ROXO if _painel_modo == 0 else Jogo.ROSA)
	var titulo := UI.label("RANKING" if _painel_modo == 0 else "COMO JOGAR", Jogo.fonte("titan", 42, 4), cor)
	UI.colocar(titulo, 0, 12, 384, 56)
	_painel.add_child(titulo)
	if _painel_modo == 0:
		var r: Array = Jogo.ranking
		if r.empty():
			var v := UI.label("SEJA O PRIMEIRO!", Jogo.fonte("bungee", 24, 2), Jogo.BRANCO)
			UI.colocar(v, 0, 190, 384, 40)
			_painel.add_child(v)
			UI.pop(v, 0.2)
		var cores := [Jogo.AMARELO, Color(0.85, 0.9, 1.0), Color(1.0, 0.62, 0.35), Jogo.CIANO, Jogo.CIANO]
		for i in range(min(5, r.size())):
			var y := 84 + i * 66
			var linha := ColorRect.new()
			linha.color = Color(1, 1, 1, 0.06 if i % 2 else 0.11)
			UI.colocar(linha, 16, y, 352, 58)
			_painel.add_child(linha)
			var pos := UI.label("%dº" % (i + 1), Jogo.fonte("titan", 34, 3), cores[i], Label.ALIGN_LEFT)
			UI.colocar(pos, 12, 0, 70, 58)
			linha.add_child(pos)
			var pts := UI.label(str(int(r[i].pontos)), Jogo.fonte("titan", 36, 3), Jogo.BRANCO, Label.ALIGN_RIGHT)
			UI.colocar(pts, 70, 0, 150, 58)
			linha.add_child(pts)
			var info := UI.label("FASE %s  %s" % [str(r[i].fase), str(r[i].get("data", ""))], Jogo.fonte("bungee", 15, 1), Color(1, 1, 1, 0.75), Label.ALIGN_RIGHT)
			UI.colocar(info, 220, 0, 124, 58)
			linha.add_child(info)
			UI.deslizar(linha, Vector2(60, 0), 0.08 * i, 0.4)
	else:
		var passos := [
			[Jogo.LARANJA, "ACERTE O MÁXIMO\nDE CESTAS"],
			[Jogo.VERDE, "BATA A META PARA\nPASSAR DE FASE"],
			[Jogo.VERMELHO, "%d SEGUIDAS =\nEM CHAMAS x2" % int(Jogo.valor("cestas_fogo"))],
			[Jogo.AMARELO, "ÚLTIMOS %d s:\nCESTA VALE %d" % [int(Jogo.valor("segundos_sprint")), int(Jogo.valor("pontos_sprint"))]],
		]
		for i in range(passos.size()):
			var y := 90 + i * 82
			var bola := ColorRect.new()
			bola.color = passos[i][0]
			UI.colocar(bola, 22, y + 14, 18, 18)
			_painel.add_child(bola)
			var l := UI.label(passos[i][1], Jogo.fonte("bungee", 20, 2), Jogo.BRANCO, Label.ALIGN_LEFT)
			UI.colocar(l, 54, y - 6, 316, 72)
			_painel.add_child(l)
			UI.deslizar(l, Vector2(60, 0), 0.1 * i, 0.4)
			UI.pop(bola, 0.1 * i + 0.1)


func _process(delta: float) -> void:
	_t += delta
	# chamada pulsando e trocando de cor
	var k := abs(sin(_t * 2.6))
	_chamada.rect_scale = Vector2.ONE * (1.0 + k * 0.06)
	_chamada.add_color_override("font_color", Jogo.LARANJA.linear_interpolate(Jogo.AMARELO, k))
	_sub.modulate.a = 0.6 + k * 0.4
	# halo da cesta da arte
	_halo.modulate = Color(1.0, 0.45, 0.1, 0.18 + abs(sin(_t * 1.7)) * 0.2)
	# brilho passando pelo logo a cada 5 s
	var ciclo := fmod(_t, 5.0) / 1.2
	if ciclo <= 1.0:
		_varredura.position = Vector2(lerp(80.0, 820.0, ciclo), 350)
		_varredura.modulate = Color(1, 1, 1, sin(ciclo * PI) * 0.55)
	else:
		_varredura.modulate.a = 0.0
	# bola demonstrando a cesta
	if _t >= _proxima_bola:
		_proxima_bola = _t + rand_range(4.5, 6.5)
		_bola_demo()
	# painel gira entre ranking e como jogar
	if _t >= _proxima_troca:
		_proxima_troca = _t + 7.0
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


func _virar_painel() -> void:
	var tw := Tween.new()
	_painel.add_child(tw)
	tw.interpolate_property(_painel, "rect_scale", Vector2.ONE, Vector2(0, 1), 0.2, Tween.TRANS_SINE, Tween.EASE_IN)
	tw.start()
	yield(tw, "tween_all_completed")
	_painel_modo = 1 - _painel_modo
	_montar_painel()
	var tw2 := Tween.new()
	add_child(tw2)
	tw2.interpolate_property(_painel, "rect_scale", Vector2(0, 1), Vector2.ONE, 0.3, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw2.start()
	yield(tw2, "tween_all_completed")
	tw2.queue_free()


func _bola_demo() -> void:
	var b := Sprite.new()
	b.texture = _tex_bola
	b.scale = Vector2(0.42, 0.42)
	add_child(b)
	move_child(b, _halo.get_index() + 1)
	var inicio := Vector2(rand_range(640, 820), 780)
	var topo := Vector2(lerp(inicio.x, CESTA_ARTE.x, 0.6), 20)
	var tw := Tween.new()
	b.add_child(tw)
	# subida e descida (duas metades de parábola)
	tw.interpolate_method(self, "_arco", 0.0, 1.0, 1.25, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	b.set_meta("arco", [inicio, topo, CESTA_ARTE + Vector2(0, 40)])
	_bola_atual = b
	tw.interpolate_property(b, "rotation", 0.0, 7.0, 1.25)
	tw.interpolate_property(b, "scale", Vector2(0.42, 0.42), Vector2(0.26, 0.26), 1.25)
	tw.interpolate_property(b, "modulate:a", 1.0, 0.0, 0.15, Tween.TRANS_LINEAR, Tween.EASE_IN, 1.12)
	tw.interpolate_callback(self, 1.08, "_cesta_demo")
	tw.interpolate_callback(b, 1.3, "queue_free")
	tw.start()


var _bola_atual: Sprite


func _arco(k: float) -> void:
	if _bola_atual == null or not is_instance_valid(_bola_atual):
		return
	var pts: Array = _bola_atual.get_meta("arco")
	var a: Vector2 = pts[0]
	var t: Vector2 = pts[1]
	var c: Vector2 = pts[2]
	# curva de Bézier quadrática passando perto do topo
	var ctrl := t * 2.0 - (a + c) * 0.5
	_bola_atual.position = a.linear_interpolate(ctrl, k).linear_interpolate(ctrl.linear_interpolate(c, k), k)


func _cesta_demo() -> void:
	_explosao.restart()
	fundo.flash(Jogo.LARANJA, 0.18)
	UI.flutuar(self, "SWISH!", Jogo.fonte("titan", 48, 4), Jogo.AMARELO, CESTA_ARTE + Vector2(-40, 120), CESTA_ARTE + Vector2(-60, 60), 1.0)


func _input(ev: InputEvent) -> void:
	if _saindo:
		return
	if ev.is_action_pressed("input_start") and not ev.is_echo():
		Jogo.tocar("selecao")
		fundo.flash(Jogo.AMARELO, 0.5)
		UI.pulsar(_chamada, 0.3)
		_ir("res://cenas/partida.tscn")
	elif ev is InputEventKey and ev.pressed and ev.scancode == KEY_F10:
		_ir("res://cenas/config.tscn")


func _ir(cena: String) -> void:
	_saindo = true
	if cena.ends_with("partida.tscn"):
		Jogo.parar_musica(0.3)
	Jogo.ir_para(cena)
