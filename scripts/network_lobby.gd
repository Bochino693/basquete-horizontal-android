extends Control
# =====================================================================
# LOBBY DE REDE — TELA DE CONEXÃO ENTRE MÁQUINAS (ESTILO ARCADE)
# =====================================================================
# ESTRUTURA EM DOIS ESTADOS:
#   1) box_pre_conexao  — visível até a conexão ser CONFIRMADA de verdade
#      (hospedar OU digitar IP + conectar)
#   2) box_pos_conexao  — visível só depois que Rede.conectado é true e
#      o roster já chegou (lista de jogadores, botão PRONTO, e pro host
#      o botão de forçar início)
#
# ENQUADRAMENTO: CenterContainer + PanelContainer fazem o card se
# centralizar e se redimensionar sozinho conforme o conteúdo — sem
# nenhum cálculo manual de posição, então a lista de jogadores pode
# crescer/encolher sem quebrar o layout.
#
# FLUXO LÓGICO:
#   HOSPEDAR/CONECTAR → conexão confirmada → troca pra box_pos_conexao
#   → ESTOU PRONTO (dos dois lados) → Rede.todos_prontos dispara →
#   host chama iniciar_partida_para_todos → sinal comeca_partida chega
#   nas DUAS máquinas ao mesmo tempo → troca de cena pro
#   network_versus_test.tscn, já com a duração da partida combinada.
#
# CAMPO DE IP: 4 caixinhas (um octeto cada), só números, avanço
# automático de foco, sem precisar digitar ponto.
#
# REDE: não precisa de internet — só de um roteador (ou switch) ligando
# as duas máquinas na mesma rede local (Wi-Fi ou cabo).
# =====================================================================

@export var caminho_fonte: String = "res://fonts/titan.ttf"
@export_file("*.tscn") var proxima_cena: String = "res://scenes/network_versus_test.tscn"
@export var duracao_partida_padrao: float = 60.0

const COR_LARANJA := Color(1.0, 0.46, 0.04)
const COR_LARANJA_CLARO := Color(1.0, 0.72, 0.30)
const COR_AZUL := Color(0.25, 0.55, 1.0)
const COR_VERDE := Color(0.35, 1.0, 0.55)
const COR_VERMELHO := Color(1.0, 0.35, 0.30)
const COR_FUNDO := Color(0.015, 0.02, 0.045, 1.0)

var painel_central: PanelContainer
var lbl_titulo: Label
var lbl_meu_ip: Label
var lbl_status: Label
var lbl_papel: Label

var box_pre_conexao: VBoxContainer
var btn_hospedar: Button
var box_conectar: HBoxContainer
var campos_ip: Array = []
var btn_conectar: Button

var box_pos_conexao: VBoxContainer
var box_lista: VBoxContainer
var btn_pronto: Button
var btn_iniciar_host: Button
var btn_cancelar: Button

var _tween_status: Tween = null
var _tween_titulo: Tween = null


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var fundo := ColorRect.new()
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.color = COR_FUNDO
	add_child(fundo)

	_montar_glow_fundo()

	# CenterContainer + PanelContainer: o card se auto-enquadra e
	# centraliza sozinho, sem precisar de nenhum cálculo manual de
	# posição/tamanho — se a lista de jogadores crescer, o card cresce
	# junto e continua centralizado.
	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centro)

	painel_central = PanelContainer.new()
	painel_central.add_theme_stylebox_override("panel", _estilo_painel(COR_LARANJA, 0.85))
	centro.add_child(painel_central)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(480, 0)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	painel_central.add_child(vbox)

	lbl_titulo = _criar_label("REDE ARCADE", 38, Color.WHITE, COR_LARANJA, 8)
	lbl_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl_titulo)

	var sub := _criar_label("CONEXÃO ENTRE ESTAÇÕES", 16, Color(0.75, 0.82, 0.95), Color.BLACK, 3)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	var painel_ip := PanelContainer.new()
	painel_ip.add_theme_stylebox_override("panel", _estilo_capsula(COR_AZUL))
	vbox.add_child(painel_ip)
	lbl_meu_ip = _criar_label("MEU IP: ...", 20, COR_AZUL, Color.BLACK, 3)
	lbl_meu_ip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	painel_ip.add_child(lbl_meu_ip)

	lbl_papel = _criar_label("", 16, Color(0.8, 0.85, 0.9), Color.BLACK, 2)
	lbl_papel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_papel.visible = false
	vbox.add_child(lbl_papel)

	lbl_status = _criar_label("DESCONECTADO", 20, COR_LARANJA_CLARO, Color.BLACK, 3)
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl_status)

	# ---------------------------------------------------------------
	# ESTADO 1: PRÉ-CONEXÃO — hospedar ou conectar via IP
	# ---------------------------------------------------------------
	box_pre_conexao = VBoxContainer.new()
	box_pre_conexao.add_theme_constant_override("separation", 14)
	vbox.add_child(box_pre_conexao)

	btn_hospedar = _criar_botao("HOSPEDAR (SOU O JOGADOR 1)", COR_LARANJA)
	btn_hospedar.pressed.connect(_ao_apertar_hospedar)
	box_pre_conexao.add_child(btn_hospedar)

	var linha_sep := _criar_label("— OU —", 14, Color(0.5, 0.5, 0.6), Color.BLACK, 0)
	linha_sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box_pre_conexao.add_child(linha_sep)

	var lbl_dica_ip := _criar_label("DIGITE O IP DO HOST (SÓ NÚMEROS)", 14, Color(0.6, 0.65, 0.75), Color.BLACK, 0)
	lbl_dica_ip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box_pre_conexao.add_child(lbl_dica_ip)

	var painel_campo_ip := PanelContainer.new()
	painel_campo_ip.add_theme_stylebox_override("panel", _estilo_capsula(Color(0.3, 0.35, 0.45)))
	box_pre_conexao.add_child(painel_campo_ip)

	box_conectar = HBoxContainer.new()
	box_conectar.alignment = BoxContainer.ALIGNMENT_CENTER
	box_conectar.add_theme_constant_override("separation", 6)
	painel_campo_ip.add_child(box_conectar)

	campos_ip.clear()
	for i in range(4):
		var campo := _criar_campo_octeto(i)
		box_conectar.add_child(campo)
		campos_ip.append(campo)
		if i < 3:
			var ponto := _criar_label(".", 24, Color(0.6, 0.65, 0.75), Color.BLACK, 0)
			ponto.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			box_conectar.add_child(ponto)

	var espaco_conectar := Control.new()
	espaco_conectar.custom_minimum_size = Vector2(10, 0)
	box_conectar.add_child(espaco_conectar)

	btn_conectar = _criar_botao("CONECTAR", COR_AZUL)
	btn_conectar.custom_minimum_size = Vector2(150, 50)
	btn_conectar.pressed.connect(_ao_apertar_conectar)
	box_conectar.add_child(btn_conectar)

	# ---------------------------------------------------------------
	# ESTADO 2: PÓS-CONEXÃO — lista de jogadores, pronto, iniciar
	# ---------------------------------------------------------------
	box_pos_conexao = VBoxContainer.new()
	box_pos_conexao.add_theme_constant_override("separation", 14)
	box_pos_conexao.visible = false
	vbox.add_child(box_pos_conexao)

	var painel_lista := PanelContainer.new()
	painel_lista.custom_minimum_size = Vector2(0, 110)
	painel_lista.add_theme_stylebox_override("panel", _estilo_capsula(Color(0.3, 0.35, 0.45)))
	box_pos_conexao.add_child(painel_lista)

	box_lista = VBoxContainer.new()
	box_lista.add_theme_constant_override("separation", 6)
	painel_lista.add_child(box_lista)

	btn_pronto = _criar_botao("ESTOU PRONTO", COR_VERDE)
	btn_pronto.disabled = true
	btn_pronto.pressed.connect(_ao_apertar_pronto)
	box_pos_conexao.add_child(btn_pronto)

	btn_iniciar_host = _criar_botao("(HOST) FORÇAR INÍCIO", COR_LARANJA_CLARO)
	btn_iniciar_host.visible = false
	btn_iniciar_host.pressed.connect(_ao_apertar_iniciar_host)
	box_pos_conexao.add_child(btn_iniciar_host)

	btn_cancelar = _criar_botao("CANCELAR / VOLTAR", COR_VERMELHO)
	btn_cancelar.custom_minimum_size = Vector2(0, 44)
	btn_cancelar.pressed.connect(_ao_apertar_cancelar)
	box_pos_conexao.add_child(btn_cancelar)

	# ---------------------------------------------------------------
	# RODAPÉ — dica fixa sobre rede local, sempre visível
	# ---------------------------------------------------------------
	var lbl_footer := _criar_label(
		"REQUER REDE LOCAL (ROTEADOR/WI-FI LIGANDO AS 2 MÁQUINAS) — SEM INTERNET",
		12, Color(0.45, 0.5, 0.6), Color.BLACK, 0
	)
	lbl_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_footer.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(lbl_footer)

	lbl_meu_ip.text = "MEU IP: " + Rede.meu_ip_local()

	Rede.lista_jogadores_atualizada.connect(_ao_atualizar_lista)
	Rede.todos_prontos.connect(_ao_todos_prontos)
	Rede.comeca_partida.connect(_ao_comecar_partida)
	Rede.falha_conexao.connect(_ao_falha_conexao)
	Rede.desconectado_do_host.connect(_ao_desconectado)

	_atualizar_lista_vazia()
	_animar_titulo()


func _montar_glow_fundo() -> void:
	var glow := Control.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	glow.draw.connect(func():
		var tela := get_viewport_rect().size
		var centro := Vector2(tela.x * 0.5, tela.y * 0.5)
		for i in range(5):
			var raio: float = 140.0 + float(i) * 90.0
			glow.draw_circle(centro, raio, Color(COR_LARANJA.r, COR_LARANJA.g, COR_LARANJA.b, 0.012))
	)


func _animar_titulo() -> void:
	if lbl_titulo == null:
		return
	lbl_titulo.pivot_offset = lbl_titulo.size * 0.5
	_tween_titulo = create_tween().set_loops()
	_tween_titulo.tween_property(lbl_titulo, "scale", Vector2(1.03, 1.03), 1.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween_titulo.tween_property(lbl_titulo, "scale", Vector2.ONE, 1.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _criar_label(texto: String, tam: int, cor: Color, outline: Color, outline_size: int) -> Label:
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


func _criar_botao(texto: String, cor: Color) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Vector2(0, 58)
	b.add_theme_font_size_override("font_size", 20)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(cor.r * 0.14, cor.g * 0.14, cor.b * 0.14, 0.92)
	normal.border_color = cor
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(16)
	normal.corner_detail = 12
	normal.shadow_color = Color(cor.r, cor.g, cor.b, 0.45)
	normal.shadow_size = 16
	normal.anti_aliasing = true

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(cor.r * 0.28, cor.g * 0.28, cor.b * 0.28, 0.95)

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.06, 0.06, 0.08, 0.6)
	disabled.border_color = Color(0.3, 0.3, 0.35, 0.5)
	disabled.set_border_width_all(2)
	disabled.set_corner_radius_all(16)
	disabled.corner_detail = 12

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55))
	return b


func _estilo_painel(cor: Color, alpha_borda: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.035, 0.06, 0.96)
	sb.border_color = Color(cor.r, cor.g, cor.b, alpha_borda)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(30)
	sb.corner_detail = 20
	sb.shadow_color = Color(cor.r, cor.g, cor.b, 0.35)
	sb.shadow_size = 40
	sb.set_content_margin_all(34)
	sb.anti_aliasing = true
	return sb


func _estilo_capsula(cor: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(cor.r * 0.10, cor.g * 0.10, cor.b * 0.10, 0.65)
	sb.border_color = Color(cor.r, cor.g, cor.b, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.corner_detail = 14
	sb.set_content_margin_all(12)
	sb.anti_aliasing = true
	return sb


func _estilo_campo_octeto() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.95)
	sb.border_color = Color(COR_AZUL.r, COR_AZUL.g, COR_AZUL.b, 0.65)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.corner_detail = 10
	sb.set_content_margin_all(6)
	sb.anti_aliasing = true
	return sb


# =====================================================================
# CAMPO DE IP — 4 caixinhas com máscara automática (só números)
# =====================================================================
func _criar_campo_octeto(idx: int) -> LineEdit:
	var le := LineEdit.new()
	le.custom_minimum_size = Vector2(64, 50)
	le.max_length = 3
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.placeholder_text = "0"
	le.add_theme_font_size_override("font_size", 22)
	le.add_theme_stylebox_override("normal", _estilo_campo_octeto())
	le.add_theme_stylebox_override("focus", _estilo_campo_octeto())
	le.text_changed.connect(_on_octeto_texto_mudou.bind(idx))
	le.gui_input.connect(_on_octeto_gui_input.bind(idx))
	return le


func _on_octeto_texto_mudou(novo_texto: String, idx: int) -> void:
	var campo: LineEdit = campos_ip[idx]

	var digitos: String = ""
	for c in novo_texto:
		if c.is_valid_int():
			digitos += c

	if digitos.length() > 0:
		var valor: int = clampi(int(digitos), 0, 255)
		digitos = str(valor)

	if digitos != campo.text:
		campo.text = digitos
		campo.caret_column = digitos.length()

	if digitos.length() >= 3 and idx < campos_ip.size() - 1:
		var proximo: LineEdit = campos_ip[idx + 1]
		proximo.grab_focus()
		proximo.caret_column = proximo.text.length()


func _on_octeto_gui_input(evento: InputEvent, idx: int) -> void:
	if not (evento is InputEventKey and evento.pressed):
		return

	var campo: LineEdit = campos_ip[idx]
	var tecla := evento as InputEventKey

	if (tecla.keycode == KEY_PERIOD or tecla.keycode == KEY_KP_PERIOD or tecla.keycode == KEY_SPACE) and idx < campos_ip.size() - 1:
		campos_ip[idx + 1].grab_focus()
		campos_ip[idx + 1].caret_column = campos_ip[idx + 1].text.length()
		get_viewport().set_input_as_handled()
		return

	if tecla.keycode == KEY_BACKSPACE and campo.text == "" and idx > 0:
		var anterior: LineEdit = campos_ip[idx - 1]
		anterior.grab_focus()
		anterior.caret_column = anterior.text.length()
		get_viewport().set_input_as_handled()


func _obter_ip_completo() -> String:
	var partes: Array = []
	for campo in campos_ip:
		partes.append(campo.text if campo.text != "" else "0")
	return ".".join(partes)


func _limpar_campos_ip() -> void:
	for campo in campos_ip:
		campo.text = ""


func _atualizar_lista_vazia() -> void:
	for c in box_lista.get_children():
		c.queue_free()
	var placeholder := _criar_label("Nenhum jogador conectado ainda.", 16, Color(0.5, 0.55, 0.65), Color.BLACK, 0)
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box_lista.add_child(placeholder)


func _pulsar_status(cor: Color) -> void:
	lbl_status.add_theme_color_override("font_color", cor)
	if _tween_status != null:
		_tween_status.kill()
	lbl_status.scale = Vector2(1.12, 1.12)
	lbl_status.pivot_offset = lbl_status.size * 0.5
	_tween_status = create_tween()
	_tween_status.tween_property(lbl_status, "scale", Vector2.ONE, 0.25)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# =====================================================================
# TRANSIÇÃO DE ESTADO — só muda de tela quando a conexão é CONFIRMADA
# =====================================================================
func _entrar_modo_conectado(sou_host: bool) -> void:
	box_pre_conexao.visible = false
	box_pos_conexao.visible = true
	btn_iniciar_host.visible = sou_host
	btn_pronto.disabled = false
	btn_pronto.text = "ESTOU PRONTO"

	lbl_papel.visible = true
	lbl_papel.text = "VOCÊ: HOST" if sou_host else "VOCÊ: CLIENTE"
	lbl_papel.add_theme_color_override("font_color", COR_LARANJA if sou_host else COR_AZUL)

	if sou_host:
		lbl_status.text = "HOSPEDANDO — AGUARDANDO JOGADORES"
	else:
		lbl_status.text = "CONECTADO — AGUARDANDO OS DOIS FICAREM PRONTOS"
	_pulsar_status(COR_VERDE)


func _resetar_tela_inicial() -> void:
	box_pos_conexao.visible = false
	box_pre_conexao.visible = true
	lbl_papel.visible = false

	btn_hospedar.disabled = false
	btn_conectar.disabled = false
	for campo in campos_ip:
		campo.editable = true
	_limpar_campos_ip()

	btn_pronto.disabled = true
	btn_pronto.text = "ESTOU PRONTO"
	btn_iniciar_host.visible = false

	_atualizar_lista_vazia()
	lbl_status.text = "DESCONECTADO"
	_pulsar_status(COR_LARANJA_CLARO)


func _ao_apertar_hospedar() -> void:
	var erro: int = Rede.hospedar("JOGADOR 1")
	if erro == OK:
		_entrar_modo_conectado(true)


func _ao_apertar_conectar() -> void:
	var preenchido: bool = false
	for campo in campos_ip:
		if campo.text != "":
			preenchido = true
			break

	if not preenchido:
		lbl_status.text = "DIGITE O IP DO HOST PRIMEIRO"
		_pulsar_status(COR_VERMELHO)
		return

	var ip: String = _obter_ip_completo()
	var erro: int = Rede.conectar_a(ip, "JOGADOR 2")
	if erro == OK:
		# Ainda NÃO troca de tela aqui — só desabilita os campos e
		# aguarda a confirmação real da conexão (ver _ao_atualizar_lista).
		lbl_status.text = "CONECTANDO A %s..." % ip
		_pulsar_status(COR_AZUL)
		btn_hospedar.disabled = true
		btn_conectar.disabled = true
		for campo in campos_ip:
			campo.editable = false


func _ao_apertar_pronto() -> void:
	Rede.marcar_pronto()
	btn_pronto.disabled = true
	btn_pronto.text = "AGUARDANDO OUTROS..."


func _ao_apertar_iniciar_host() -> void:
	Rede.iniciar_partida_para_todos(duracao_partida_padrao)


func _ao_apertar_cancelar() -> void:
	Rede.encerrar_conexao()
	_resetar_tela_inicial()


func _ao_atualizar_lista(jogadores: Dictionary) -> void:
	for c in box_lista.get_children():
		c.queue_free()

	if jogadores.is_empty():
		_atualizar_lista_vazia()
	else:
		var cores := [COR_LARANJA, COR_AZUL, COR_VERDE, COR_LARANJA_CLARO]
		for info in jogadores.values():
			var idx: int = int(info["indice"])
			var pronto: bool = bool(info["pronto"])
			var cor: Color = cores[idx % cores.size()]

			var linha := HBoxContainer.new()
			linha.add_theme_constant_override("separation", 10)
			box_lista.add_child(linha)

			var dot := Panel.new()
			dot.custom_minimum_size = Vector2(16, 16)
			var sb_dot := StyleBoxFlat.new()
			sb_dot.bg_color = cor if pronto else Color(cor.r, cor.g, cor.b, 0.3)
			sb_dot.set_corner_radius_all(999)
			sb_dot.shadow_color = Color(cor.r, cor.g, cor.b, 0.7 if pronto else 0.1)
			sb_dot.shadow_size = 8 if pronto else 2
			dot.add_theme_stylebox_override("panel", sb_dot)
			linha.add_child(dot)

			var nome := _criar_label(str(info["nome"]), 18, Color.WHITE if pronto else Color(0.7, 0.7, 0.75), Color.BLACK, 2)
			linha.add_child(nome)

			var status := _criar_label("PRONTO" if pronto else "AGUARDANDO", 16, cor if pronto else Color(0.55, 0.55, 0.6), Color.BLACK, 2)
			linha.add_child(status)

	# Confirmação REAL de conexão (não a tentativa) — é aqui que o
	# cliente finalmente troca de tela, depois do roster chegar do
	# host. O host já trocou de tela antes (em _ao_apertar_hospedar),
	# então esse "if" simplesmente não repete a transição pra ele.
	if Rede.conectado and not box_pos_conexao.visible:
		_entrar_modo_conectado(Rede.sou_host)

	if Rede.conectado and box_pos_conexao.visible:
		lbl_status.text = "%d JOGADOR(ES) NA SALA" % jogadores.size()


func _ao_todos_prontos() -> void:
	lbl_status.text = "TODOS PRONTOS — INICIANDO!"
	_pulsar_status(COR_VERDE)
	if Rede.sou_host:
		Rede.iniciar_partida_para_todos(duracao_partida_padrao)


func _ao_comecar_partida(duracao: float) -> void:
	get_tree().set_meta("duracao_partida", duracao)
	var tela_node := get_node_or_null("/root/Tela")
	if tela_node != null and tela_node.has_method("trocar"):
		tela_node.trocar(proxima_cena)
	elif ResourceLoader.exists(proxima_cena):
		get_tree().change_scene_to_file(proxima_cena)


func _ao_falha_conexao(motivo: String) -> void:
	lbl_status.text = motivo.to_upper()
	_pulsar_status(COR_VERMELHO)
	btn_hospedar.disabled = false
	btn_conectar.disabled = false
	for campo in campos_ip:
		campo.editable = true


func _ao_desconectado() -> void:
	_resetar_tela_inicial()
	lbl_status.text = "O HOST CAIU / DESCONECTOU"
	_pulsar_status(COR_VERMELHO)
