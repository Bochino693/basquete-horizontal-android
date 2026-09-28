extends Control
# =====================================================================
# TESTE VERSUS — DOIS PLAYERS JOGANDO AO MESMO TEMPO (ESTILO ARCADE)
# Visual: dois painéis coloridos lado a lado, "VS" central, cronômetro
# em destaque, pulso no placar a cada ponto e tela de resultado final
# com o vencedor em glow dourado.
# =====================================================================

const COR_MEU := Color(0.30, 1.0, 0.55)
const COR_ADVERSARIO := Color(1.0, 0.42, 0.30)
const COR_LARANJA := Color(1.0, 0.46, 0.04)
const COR_OURO := Color(1.0, 0.84, 0.20)
const COR_FUNDO := Color(0.015, 0.02, 0.045, 1.0)

@export var caminho_fonte: String = "res://fonts/titan.ttf"

var _meu_placar: int = 0
var _placar_adversario: int = 0
var _minha_partida_acabou: bool = false
var _adversario_acabou: bool = false
var _tempo_restante: float = 60.0
var _tempo_total: float = 60.0
var _rodando: bool = false

var painel_meu: Panel
var painel_adversario: Panel
var lbl_meu_nome: Label
var lbl_meu_placar: Label
var lbl_adversario_nome: Label
var lbl_adversario_placar: Label
var lbl_cronometro: Label
var anel_tempo: Control
var lbl_status: Label
var btn_marcar: Button
var painel_resultado: Panel


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var fundo := ColorRect.new()
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.color = COR_FUNDO
	add_child(fundo)

	var raiz := VBoxContainer.new()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.offset_left = 40
	raiz.offset_right = -40
	raiz.offset_top = 30
	raiz.offset_bottom = -30
	raiz.alignment = BoxContainer.ALIGNMENT_CENTER
	raiz.add_theme_constant_override("separation", 24)
	add_child(raiz)

	var titulo := _label("PARTIDA EM REDE", 26, Color(0.8, 0.85, 1.0), Color.BLACK, 3)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	raiz.add_child(titulo)

	# --- Cronômetro central ---
	var box_crono := Control.new()
	box_crono.custom_minimum_size = Vector2(0, 160)
	box_crono.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	raiz.add_child(box_crono)

	anel_tempo = Control.new()
	anel_tempo.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	anel_tempo.custom_minimum_size = Vector2(180, 180)
	anel_tempo.position = Vector2(-90, -80)
	anel_tempo.draw.connect(_desenhar_anel_tempo)
	box_crono.add_child(anel_tempo)

	lbl_cronometro = _label("60", 56, Color.WHITE, COR_LARANJA, 8)
	lbl_cronometro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_cronometro.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_cronometro.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lbl_cronometro.position = Vector2(-90, -80)
	lbl_cronometro.size = Vector2(180, 180)
	box_crono.add_child(lbl_cronometro)

	# --- Linha VS ---
	var linha := HBoxContainer.new()
	linha.alignment = BoxContainer.ALIGNMENT_CENTER
	linha.size_flags_vertical = Control.SIZE_EXPAND_FILL
	linha.add_theme_constant_override("separation", 30)
	raiz.add_child(linha)

	painel_meu = _criar_painel_jogador(COR_MEU)
	linha.add_child(painel_meu)
	lbl_meu_nome = _achar_label(painel_meu, "nome")
	lbl_meu_placar = _achar_label(painel_meu, "placar")

	var vs := _label("VS", 40, Color(0.6, 0.6, 0.7), Color.BLACK, 4)
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	linha.add_child(vs)

	painel_adversario = _criar_painel_jogador(COR_ADVERSARIO)
	linha.add_child(painel_adversario)
	lbl_adversario_nome = _achar_label(painel_adversario, "nome")
	lbl_adversario_placar = _achar_label(painel_adversario, "placar")

	lbl_status = _label("AGUARDANDO INÍCIO...", 18, Color(0.8, 0.8, 0.85), Color.BLACK, 2)
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	raiz.add_child(lbl_status)

	btn_marcar = Button.new()
	btn_marcar.text = "MARCAR PONTO  [ SPACE ]"
	btn_marcar.custom_minimum_size = Vector2(0, 64)
	btn_marcar.add_theme_font_size_override("font_size", 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(COR_LARANJA.r * 0.16, COR_LARANJA.g * 0.16, COR_LARANJA.b * 0.16, 0.95)
	sb.border_color = COR_LARANJA
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(18)
	sb.corner_detail = 14
	sb.shadow_color = Color(COR_LARANJA.r, COR_LARANJA.g, COR_LARANJA.b, 0.5)
	sb.shadow_size = 20
	sb.anti_aliasing = true
	btn_marcar.add_theme_stylebox_override("normal", sb)
	btn_marcar.add_theme_stylebox_override("hover", sb)
	btn_marcar.add_theme_stylebox_override("pressed", sb)
	btn_marcar.add_theme_color_override("font_color", Color.WHITE)
	btn_marcar.pressed.connect(_marcar_ponto_local)
	raiz.add_child(btn_marcar)

	# --- Overlay de resultado (escondido até acabar) ---
	painel_resultado = Panel.new()
	painel_resultado.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	painel_resultado.custom_minimum_size = Vector2(560, 260)
	painel_resultado.visible = false
	add_child(painel_resultado)

	Rede.ponto_remoto_marcado.connect(_ao_ponto_remoto)
	Rede.partida_remota_encerrada.connect(_ao_fim_remoto)

	if Rede.sou_host:
		lbl_meu_nome.text = "VOCÊ (HOST)"
	else:
		lbl_meu_nome.text = "VOCÊ (CLIENTE)"

	if get_tree().has_meta("duracao_partida"):
		_tempo_total = float(get_tree().get_meta("duracao_partida"))
		_tempo_restante = _tempo_total
	lbl_cronometro.text = str(int(_tempo_restante))

	_rodando = true
	lbl_status.text = "PARTIDA EM ANDAMENTO!"


func _criar_painel_jogador(cor: Color) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(260, 220)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(cor.r * 0.08, cor.g * 0.08, cor.b * 0.08, 0.92)
	sb.border_color = cor
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(24)
	sb.corner_detail = 16
	sb.shadow_color = Color(cor.r, cor.g, cor.b, 0.4)
	sb.shadow_size = 26
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	p.add_child(vbox)

	var nome := _label("JOGADOR", 18, cor, Color.BLACK, 3)
	nome.name = "nome"
	nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(nome)

	var placar := _label("0", 64, Color.WHITE, cor, 6)
	placar.name = "placar"
	placar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(placar)

	return p


func _achar_label(painel: Panel, nome_no: String) -> Label:
	return painel.get_child(0).get_node(nome_no) as Label


func _label(texto: String, tam: int, cor: Color, outline: Color, outline_size: int) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", cor)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", outline_size)
	if caminho_fonte != "" and ResourceLoader.exists(caminho_fonte):
		var f := load(caminho_fonte)
		if f is Font:
			l.add_theme_font_override("font", f)
	return l


func _desenhar_anel_tempo() -> void:
	var r := anel_tempo.size
	var c := r * 0.5
	var raio: float = min(r.x, r.y) * 0.42
	var frac: float = clampf(_tempo_restante / max(0.01, _tempo_total), 0.0, 1.0)

	anel_tempo.draw_arc(c, raio, 0.0, TAU, 64, Color(0.12, 0.14, 0.20, 0.8), 10.0, true)

	var cor_anel := COR_LARANJA
	if _tempo_restante <= 10.0 and _rodando:
		cor_anel = COR_ADVERSARIO

	anel_tempo.draw_arc(c, raio, -PI / 2.0, -PI / 2.0 + TAU * frac, 64, cor_anel, 10.0, true)


func _process(delta: float) -> void:
	if not _rodando:
		return

	_tempo_restante -= delta
	if anel_tempo != null:
		anel_tempo.queue_redraw()

	if _tempo_restante <= 0.0:
		_tempo_restante = 0.0
		_rodando = false
		lbl_cronometro.text = "0"
		_encerrar_minha_partida()
	else:
		lbl_cronometro.text = str(int(ceil(_tempo_restante)))


func _unhandled_input(evento: InputEvent) -> void:
	if not _rodando:
		return
	if evento.is_action_pressed("ui_accept"):
		_marcar_ponto_local()
		get_viewport().set_input_as_handled()


func _pulsar_placar(lbl: Label) -> void:
	lbl.pivot_offset = lbl.size * 0.5
	lbl.scale = Vector2(1.28, 1.28)
	var t := create_tween()
	t.tween_property(lbl, "scale", Vector2.ONE, 0.22)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _marcar_ponto_local() -> void:
	if not _rodando:
		return

	_meu_placar += 1
	lbl_meu_placar.text = str(_meu_placar)
	_pulsar_placar(lbl_meu_placar)

	Rede.notificar_ponto(Rede.meu_indice_jogador, _meu_placar)


func _ao_ponto_remoto(indice_jogador: int, total: int) -> void:
	if indice_jogador == Rede.meu_indice_jogador:
		return

	_placar_adversario = total
	lbl_adversario_placar.text = str(_placar_adversario)
	_pulsar_placar(lbl_adversario_placar)


func _encerrar_minha_partida() -> void:
	_minha_partida_acabou = true
	Rede.notificar_fim_partida(Rede.meu_indice_jogador, _meu_placar)
	lbl_status.text = "VOCÊ TERMINOU! AGUARDANDO O ADVERSÁRIO..."
	btn_marcar.disabled = true
	_verificar_fim_geral()


func _ao_fim_remoto(indice_jogador: int, total_final: int) -> void:
	if indice_jogador == Rede.meu_indice_jogador:
		return

	_placar_adversario = total_final
	lbl_adversario_placar.text = str(_placar_adversario)
	_adversario_acabou = true
	_verificar_fim_geral()


func _verificar_fim_geral() -> void:
	if not (_minha_partida_acabou and _adversario_acabou):
		return

	var titulo: String
	var cor: Color

	if _meu_placar > _placar_adversario:
		titulo = "VOCÊ VENCEU!"
		cor = COR_MEU
	elif _meu_placar < _placar_adversario:
		titulo = "VOCÊ PERDEU"
		cor = COR_ADVERSARIO
	else:
		titulo = "EMPATE"
		cor = COR_OURO

	_mostrar_resultado(titulo, cor)


func _mostrar_resultado(titulo: String, cor: Color) -> void:
	for c in painel_resultado.get_children():
		c.queue_free()

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.04, 0.97)
	sb.border_color = cor
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(32)
	sb.corner_detail = 20
	sb.shadow_color = Color(cor.r, cor.g, cor.b, 0.6)
	sb.shadow_size = 40
	sb.anti_aliasing = true
	painel_resultado.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	painel_resultado.add_child(vbox)

	var lbl_titulo := _label(titulo, 44, cor, Color.BLACK, 8)
	lbl_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl_titulo)

	var placar := _label("%d x %d" % [_meu_placar, _placar_adversario], 30, Color.WHITE, Color.BLACK, 4)
	placar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(placar)

	painel_resultado.visible = true
	painel_resultado.modulate.a = 0.0
	painel_resultado.pivot_offset = painel_resultado.size * 0.5
	painel_resultado.scale = Vector2(0.8, 0.8)

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(painel_resultado, "modulate:a", 1.0, 0.3)
	t.tween_property(painel_resultado, "scale", Vector2.ONE, 0.4)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
