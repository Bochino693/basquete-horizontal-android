extends Control

# =====================================================================
# CONFIG OVERLAY — SWISH ARENA
#
# 1) OVERLAY (modo_overlay = true): instanciado em cima da cena atual
#    (abertura ou jogo). Ao fechar, emite "fechado(salvou)" e quem
#    chamou decide o que fazer. É como o F10 usa.
# 2) CENA NORMAL (modo_overlay = false): navega via Tela.trocar().
#
# LAYOUT: coluna única moderna, com botões grandes, confirmação visual
# por botões e rodapé fixo. Título/Salvar/Voltar/Ajuda/Status ficam
# sempre visíveis; o conteúdo central rola somente se a tela for menor.
#
# IMPORTANTE — FUNDO x LOGO:
#   'caminho_fundo' (abaixo) é só o pôster decorativo ATRÁS DESTE
#   PAINEL DE CONFIGURAÇÃO — nada a ver com o jogo.
#   O FUNDO da tela de jogo (Play) é FIXO (back_basquet.png) e NUNCA
#   é editável por aqui — só o LOGO da empresa (canto inferior
#   esquerdo da Play) é personalizável, através de um seletor de
#   arquivos que abre o sistema operacional de verdade (não uma
#   pasta interna do jogo), com o arquivo escolhido copiado para
#   user:// para persistir e funcionar também no executável exportado.
#
# Salva configuração em:
#   user://basket_config.cfg
#   user://basket_record.cfg
# =====================================================================

signal fechado(salvou: bool)

@export var modo_overlay: bool = false

@export_file("*.tscn") var cena_voltar: String = "res://scenes/opening.tscn"
@export_file("*.tscn") var cena_jogo: String = "res://scenes/play.tscn"
@export var caminho_config_basket: String = "user://basket_config.cfg"
@export var caminho_record: String = "user://basket_record.cfg"

@export var tempo_minimo: int = 10
@export var tempo_maximo: int = 600
@export var passo_tempo: int = 10
@export var passo_tempo_grande: int = 60

@export var tempo_trava_min: float = 0.30
@export var tempo_trava_max: float = 3.00
@export var passo_trava_fino: float = 0.10
@export var passo_trava_grosso: float = 0.50

# ---------- LOGO DA EMPRESA ----------
@export var caminho_logo_padrao: String = "res://images/logo_lazer_sport.png"

@export var cor_neon: Color = Color(1.0, 0.38, 0.02, 1.0)
@export var cor_credito: Color = Color(1.0, 0.18, 0.12, 1.0)
@export var cor_livre: Color = Color(0.24, 1.0, 0.48, 1.0)
@export var cor_reset: Color = Color(1.0, 0.42, 0.02, 1.0)

@export var caminho_fonte: String = "res://fonts/titan.ttf"

# Pôster decorativo ATRÁS deste painel (não é o fundo do jogo).
@export var caminho_fundo: String = "res://images/back_basquet.png"

var cursor_layer: CanvasLayer = null
var cursor_neon: CursorNeon = null

var tempo_partida: int = 60
var modo_credito: bool = false

var fundo: TextureRect = null
var escurecer: ColorRect = null
var painel: Panel = null

var titulo: Label = null

var tempo_titulo: Label = null
var tempo_valor: Label = null
var modo_titulo: Label = null
var modo_valor: Label = null
var ajuda: Label = null
var status: Label = null

var btn_menos_10: Button = null
var btn_mais_10: Button = null
var btn_menos_60: Button = null
var btn_mais_60: Button = null
var btn_modo: Button = null
var btn_reset_record: Button = null
var btn_salvar: Button = null
var btn_voltar: Button = null

var delay_titulo: Label = null
var delay_valor: Label = null
var btn_menos_delay_grande: Button = null
var btn_menos_delay: Button = null
var btn_mais_delay: Button = null
var btn_mais_delay_grande: Button = null

# ---------- LOGO DA EMPRESA (UI) ----------
var logo_titulo: Label = null
var logo_preview_moldura: Panel = null
var logo_preview: TextureRect = null
var logo_valor: Label = null
var btn_logo_escolher: Button = null
var btn_logo_padrao: Button = null
var file_dialog: FileDialog = null
var logo_empresa_atual: String = "res://images/logo_lazer_sport.png"

var tempo_trava_cesta: float = 1.20

# ---------- DIVISORES VISUAIS ENTRE SEÇÕES ----------
var divisor_1: Panel = null
var divisor_2: Panel = null
var divisor_3: Panel = null
var divisor_4: Panel = null

var _opcoes_botoes: Array[Button] = []
var _opcoes_acoes: Array[String] = []
var _opcoes_cores: Array[Color] = []
var _opcao_atual: int = 0

var _salvando: bool = false
var _fechando: bool = false   # true durante a animação de saída — bloqueia reentrada de input/duplo-fechamento

var overlay_reset: Control = null
var painel_reset: Panel = null
var lbl_reset_titulo: Label = null
var lbl_reset_texto: Label = null
var lbl_reset_dica: Label = null
var btn_reset_confirmar: Button = null
var btn_reset_cancelar: Button = null
var _confirmando_reset: bool = false
var _opcao_reset_atual: int = 1
var _botoes_reset: Array[Button] = []
var _cores_reset: Array[Color] = []


var scroll: ScrollContainer = null
var conteudo: Control = null
var fade_topo_scroll: TextureRect = null
var fade_base_scroll: TextureRect = null


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	# A tela inteira nasce invisível — é revelada com fade suave em
	# _animar_entrada_overlay(), depois que o layout já foi calculado.
	modulate.a = 0.0

	_carregar_config()
	_montar_tela()
	_criar_file_dialog()
	_montar_overlay_reset()
	_criar_cursor_custom()
	_registrar_botoes_navegacao()
	_atualizar_textos()

	if modo_overlay:
		btn_salvar.text = "SALVAR E VOLTAR"
		btn_voltar.text = "FECHAR"

	await get_tree().process_frame
	_ajustar_layout()
	_atualizar_botoes_hover()
	_animar_entrada_overlay()

	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)



func _on_viewport_size_changed() -> void:
	call_deferred("_ajustar_layout")



func _process(_delta: float) -> void:
	if cursor_neon == null:
		return
	var mp := get_viewport().get_mouse_position()
	cursor_neon.position = mp
	cursor_neon.definir_hover(_mouse_sobre_botao(mp))



func _mouse_sobre_botao(pos_mouse: Vector2) -> bool:
	for b in _opcoes_botoes:
		if b != null and b.visible and b.get_global_rect().has_point(pos_mouse):
			return true
	return false



# =====================================================================
# CONFIG (load / save)
# =====================================================================
func _carregar_config() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(caminho_config_basket)

	if err == OK:
		tempo_partida = int(cfg.get_value("jogo", "tempo_partida", 60))
		modo_credito = bool(cfg.get_value("jogo", "modo_credito", false))

		var modo_txt: String = str(cfg.get_value("jogo", "modo_operacao", "livre")).to_lower()
		if modo_txt == "credito" or modo_txt == "crédito":
			modo_credito = true

		tempo_trava_cesta = float(cfg.get_value("jogo", "tempo_trava_cesta", 1.20))
		logo_empresa_atual = str(cfg.get_value("jogo", "logo_empresa", caminho_logo_padrao))
	else:
		tempo_partida = 60
		modo_credito = false
		tempo_trava_cesta = 1.20
		logo_empresa_atual = caminho_logo_padrao

	tempo_partida = clampi(tempo_partida, tempo_minimo, tempo_maximo)
	tempo_trava_cesta = clampf(tempo_trava_cesta, tempo_trava_min, tempo_trava_max)

	# Se o logo salvo não existir mais (ex: usuário apagou o arquivo
	# customizado manualmente, ou é a primeira vez rodando em outra
	# máquina), volta pro padrão em vez de deixar a prévia vazia.
	if not (ResourceLoader.exists(logo_empresa_atual) or FileAccess.file_exists(logo_empresa_atual)):
		logo_empresa_atual = caminho_logo_padrao



func _salvar_config() -> void:
	if _salvando:
		return

	_salvando = true

	var cfg := ConfigFile.new()
	cfg.load(caminho_config_basket)

	cfg.set_value("jogo", "tempo_partida", float(tempo_partida))
	cfg.set_value("jogo", "modo_credito", modo_credito)
	cfg.set_value("jogo", "modo_operacao", "credito" if modo_credito else "livre")
	cfg.set_value("jogo", "tempo_trava_cesta", tempo_trava_cesta)
	cfg.set_value("jogo", "logo_empresa", logo_empresa_atual)

	var err: int = cfg.save(caminho_config_basket)

	if err == OK:
		if modo_overlay:
			_mostrar_status("CONFIGURAÇÃO SALVA!", Color(0.45, 1.0, 0.55, 1.0))
			await get_tree().create_timer(0.40).timeout
			_fechar_overlay(true)
		else:
			_mostrar_status("CONFIGURAÇÃO SALVA! INDO PRO JOGO...", Color(0.45, 1.0, 0.55, 1.0))
			await get_tree().create_timer(0.45).timeout
			_ir_para_jogo()
	else:
		_mostrar_status("ERRO AO SALVAR CONFIGURAÇÃO", Color(1.0, 0.22, 0.18, 1.0))

	_salvando = false



func _mostrar_status(txt: String, cor: Color) -> void:
	if status == null:
		return
	status.text = txt
	status.add_theme_color_override("font_color", cor)



# =====================================================================
# RESET RECORD
# =====================================================================
func _pedir_confirmacao_reset() -> void:
	if _confirmando_reset or _salvando or _fechando:
		return
	_confirmando_reset = true
	_opcao_reset_atual = 1
	_atualizar_botoes_reset_hover()
	overlay_reset.visible = true
	overlay_reset.modulate.a = 0.0
	painel_reset.pivot_offset = painel_reset.size * 0.5
	painel_reset.scale = Vector2(0.9, 0.9)

	var t := create_tween().set_parallel(true)
	t.tween_property(overlay_reset, "modulate:a", 1.0, 0.18)
	t.tween_property(painel_reset, "scale", Vector2.ONE, 0.26)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)



func _cancelar_reset() -> void:
	if not _confirmando_reset:
		return
	var t := create_tween()
	t.tween_property(overlay_reset, "modulate:a", 0.0, 0.16)
	await t.finished
	overlay_reset.visible = false
	_confirmando_reset = false



func _resetar_record() -> void:
	var rec := ConfigFile.new()
	rec.set_value("record", "valor", 0)
	rec.set_value("record", "recorde", 0)
	rec.set_value("record", "high", 0)
	rec.set_value("recorde", "valor", 0)
	rec.set_value("high", "valor", 0)
	rec.set_value("recorde", "maximo", 0)
	rec.save(caminho_record)

	var cfg := ConfigFile.new()
	cfg.load(caminho_config_basket)
	cfg.set_value("record", "valor", 0)
	cfg.set_value("record", "recorde", 0)
	cfg.set_value("jogo", "record", 0)
	cfg.set_value("jogo", "recorde", 0)
	cfg.set_value("jogo", "all_time_high", 0)
	cfg.save(caminho_config_basket)

	var t := create_tween()
	t.tween_property(overlay_reset, "modulate:a", 0.0, 0.16)
	await t.finished
	overlay_reset.visible = false
	_confirmando_reset = false

	_mostrar_status("RECORD ZERADO!", Color(1.0, 0.62, 0.20, 1.0))
	_pulse(status)



# =====================================================================
# LOGO DA EMPRESA — seletor de arquivos REAL do sistema operacional
# =====================================================================
func _criar_file_dialog() -> void:
	file_dialog = FileDialog.new()
	file_dialog.name = "FileDialogLogo"
	file_dialog.title = "Escolher logo da empresa"
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE

	# ACCESS_FILESYSTEM é o que permite navegar em QUALQUER pasta do
	# computador do usuário — não só dentro do projeto/jogo. É esse
	# modo que faz o seletor se comportar como um "abrir arquivo"
	# normal do Windows, e não uma navegação restrita aos assets.
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg ; Imagens (PNG, JPG)"])
	file_dialog.size = Vector2(900, 620)

	# Tenta abrir o seletor NATIVO do sistema operacional primeiro
	# (janela de verdade do Windows); se a plataforma não suportar,
	# cai automaticamente pro seletor embutido do próprio Godot — os
	# dois caminhos funcionam igual no executável exportado.
	file_dialog.use_native_dialog = true

	add_child(file_dialog)

	file_dialog.file_selected.connect(_ao_escolher_arquivo_logo)
	file_dialog.canceled.connect(func():
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	)


func _abrir_seletor_logo() -> void:
	if file_dialog == null:
		return

	# O seletor é uma janela de verdade (nativa ou do Godot) — precisa
	# do cursor normal do mouse pra ser usável, então mostramos o
	# cursor do sistema enquanto ele estiver aberto.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	file_dialog.popup_centered()


func _ao_escolher_arquivo_logo(caminho_origem: String) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	var ext: String = caminho_origem.get_extension().to_lower()
	if ext != "png" and ext != "jpg" and ext != "jpeg":
		_mostrar_status("FORMATO INVÁLIDO — USE PNG OU JPG", Color(1.0, 0.30, 0.25, 1.0))
		return

	# Lê os bytes do arquivo ORIGINAL (pode estar em qualquer lugar do
	# PC do usuário — pendrive, Desktop, Downloads, etc.) e copia pra
	# dentro de user://. Isso é o que garante que o logo continua
	# funcionando mesmo se o arquivo original for movido, apagado, ou
	# se o jogo rodar em outra máquina — e funciona idêntico dentro
	# do executável exportado, já que user:// sempre é gravável.
	var bytes := FileAccess.get_file_as_bytes(caminho_origem)
	if bytes.is_empty():
		_mostrar_status("NÃO CONSEGUI LER O ARQUIVO ESCOLHIDO", Color(1.0, 0.30, 0.25, 1.0))
		return

	var destino: String = "user://logo_empresa_custom.%s" % ext

	# Limpa versões antigas com outra extensão, pra não acumular lixo
	# no user:// a cada vez que o usuário troca de logo.
	for outra_ext in ["png", "jpg", "jpeg"]:
		var caminho_antigo := "user://logo_empresa_custom.%s" % outra_ext
		if caminho_antigo != destino and FileAccess.file_exists(caminho_antigo):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(caminho_antigo))

	var f := FileAccess.open(destino, FileAccess.WRITE)
	if f == null:
		_mostrar_status("ERRO AO SALVAR O LOGO", Color(1.0, 0.30, 0.25, 1.0))
		return
	f.store_buffer(bytes)
	f.close()

	logo_empresa_atual = destino
	_atualizar_preview_logo()
	_mostrar_status("LOGO ATUALIZADO! CLIQUE EM SALVAR", Color(0.45, 1.0, 0.55, 1.0))
	_pulse(logo_preview_moldura)


func _restaurar_logo_padrao() -> void:
	logo_empresa_atual = caminho_logo_padrao
	_atualizar_preview_logo()
	_mostrar_status("LOGO PADRÃO RESTAURADO", Color(0.60, 0.85, 1.0, 1.0))
	_pulse(logo_preview_moldura)


func _carregar_textura_generica(caminho: String) -> Texture2D:
	# Helper genérico de carregamento de imagem: tenta primeiro como
	# recurso normal do projeto (funciona pro logo padrão, que vem de
	# res://). Se não for um recurso reconhecido pelo ResourceLoader
	# (caso do logo customizado, salvo em user:// como bytes crus de
	# PNG/JPG escolhidos pelo usuário), cai pro carregamento via
	# Image — que funciona com qualquer PNG/JPG em disco, dentro ou
	# fora do projeto, inclusive no executável exportado.
	if caminho == "":
		return null

	if ResourceLoader.exists(caminho):
		var res := load(caminho)
		if res is Texture2D:
			return res

	var img := Image.new()
	var err := img.load(caminho)
	if err == OK:
		return ImageTexture.create_from_image(img)

	return null


func _atualizar_preview_logo() -> void:
	if logo_preview != null:
		logo_preview.texture = _carregar_textura_generica(logo_empresa_atual)

	if logo_valor != null:
		var nome: String = logo_empresa_atual.get_file()
		if logo_empresa_atual == caminho_logo_padrao:
			logo_valor.text = "PADRÃO   (%s)" % nome
		else:
			logo_valor.text = "PERSONALIZADO   (%s)" % nome



# =====================================================================
# TELA — coluna única, com SCROLL bem visível
# =====================================================================
func _montar_tela() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	fundo = TextureRect.new()
	fundo.name = "Fundo"
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fundo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fundo)

	if caminho_fundo != "" and ResourceLoader.exists(caminho_fundo):
		fundo.texture = load(caminho_fundo)

	escurecer = ColorRect.new()
	escurecer.name = "Escurecer"
	escurecer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	escurecer.color = Color(0.0, 0.0, 0.0, 0.72)
	escurecer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(escurecer)

	painel = Panel.new()
	painel.name = "PainelConfig"
	painel.clip_contents = true
	painel.add_theme_stylebox_override("panel", _estilo_painel(cor_neon))
	add_child(painel)

	titulo = _criar_label("CONFIGURAÇÃO", 58, Color.WHITE, cor_neon, 9)
	painel.add_child(titulo)

	# ---------------------------------------------------------------
	# ÁREA COM SCROLL — o painel tem altura FIXA que sempre cabe na
	# tela (calculada em _ajustar_layout); todo o conteúdo do meio
	# (tempo, modo, delay, logo e reset) fica dentro deste
	# ScrollContainer, que rola verticalmente quando não couber. Título
	# e rodapé (Salvar/Voltar/Ajuda/Status) ficam FORA do scroll, fixos
	# no topo e na base — assim eles nunca somem de vista.
	# ---------------------------------------------------------------
	scroll = ScrollContainer.new()
	scroll.name = "ScrollConfig"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	painel.add_child(scroll)

	conteudo = Control.new()
	conteudo.name = "ConteudoConfig"
	conteudo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(conteudo)

	# Barra de rolagem BEM visível: mais grossa que o padrão e com
	# cores neon, pra deixar óbvio (mesmo de longe) que dá pra rolar.
	var sb_grabber := StyleBoxFlat.new()
	sb_grabber.bg_color = Color(cor_neon.r, cor_neon.g, cor_neon.b, 0.90)
	sb_grabber.set_corner_radius_all(9)
	sb_grabber.anti_aliasing = true
	var sb_trilho := StyleBoxFlat.new()
	sb_trilho.bg_color = Color(1.0, 1.0, 1.0, 0.08)
	sb_trilho.set_corner_radius_all(9)
	var vbar := scroll.get_v_scroll_bar()
	if vbar != null:
		vbar.custom_minimum_size = Vector2(20, 0)
		vbar.add_theme_stylebox_override("grabber", sb_grabber)
		vbar.add_theme_stylebox_override("grabber_highlight", sb_grabber)
		vbar.add_theme_stylebox_override("grabber_pressed", sb_grabber)
		vbar.add_theme_stylebox_override("scroll", sb_trilho)

	# --- TEMPO DA PARTIDA ---
	tempo_titulo = _criar_label("TEMPO DA PARTIDA", 28, Color(1.0, 0.88, 0.55, 1.0), Color.BLACK, 5)
	conteudo.add_child(tempo_titulo)

	tempo_valor = _criar_label("01:00", 82, Color.WHITE, cor_neon, 10)
	conteudo.add_child(tempo_valor)

	btn_menos_60 = _criar_botao("-60s", cor_neon)
	btn_menos_10 = _criar_botao("-10s", cor_neon)
	btn_mais_10 = _criar_botao("+10s", cor_neon)
	btn_mais_60 = _criar_botao("+60s", cor_neon)
	conteudo.add_child(btn_menos_60)
	conteudo.add_child(btn_menos_10)
	conteudo.add_child(btn_mais_10)
	conteudo.add_child(btn_mais_60)

	divisor_1 = Panel.new()
	divisor_1.name = "Divisor1"
	divisor_1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divisor_1.add_theme_stylebox_override("panel", _estilo_divisor())
	conteudo.add_child(divisor_1)

	# --- MODO DE OPERAÇÃO ---
	modo_titulo = _criar_label("MODO DE OPERAÇÃO", 28, Color(1.0, 0.88, 0.55, 1.0), Color.BLACK, 5)
	conteudo.add_child(modo_titulo)

	modo_valor = _criar_label("LIVRE", 64, cor_livre, Color.BLACK, 9)
	conteudo.add_child(modo_valor)

	btn_modo = _criar_botao("ALTERAR MODO", cor_livre)
	conteudo.add_child(btn_modo)

	divisor_2 = Panel.new()
	divisor_2.name = "Divisor2"
	divisor_2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divisor_2.add_theme_stylebox_override("panel", _estilo_divisor())
	conteudo.add_child(divisor_2)

	# --- DELAY ENTRE CESTAS ---
	delay_titulo = _criar_label("DELAY ENTRE CESTAS", 28, Color(1.0, 0.88, 0.55, 1.0), Color.BLACK, 5)
	conteudo.add_child(delay_titulo)

	delay_valor = _criar_label("1.2 s", 64, Color.WHITE, cor_neon, 9)
	conteudo.add_child(delay_valor)

	btn_menos_delay_grande = _criar_botao("-0.5s", cor_neon)
	btn_menos_delay = _criar_botao("-0.1s", cor_neon)
	btn_mais_delay = _criar_botao("+0.1s", cor_neon)
	btn_mais_delay_grande = _criar_botao("+0.5s", cor_neon)
	conteudo.add_child(btn_menos_delay_grande)
	conteudo.add_child(btn_menos_delay)
	conteudo.add_child(btn_mais_delay)
	conteudo.add_child(btn_mais_delay_grande)

	divisor_3 = Panel.new()
	divisor_3.name = "Divisor3"
	divisor_3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divisor_3.add_theme_stylebox_override("panel", _estilo_divisor())
	conteudo.add_child(divisor_3)

	# --- LOGO DA EMPRESA ---
	logo_titulo = _criar_label("LOGO DA EMPRESA (CANTO INFERIOR ESQ.)", 26, Color(1.0, 0.88, 0.55, 1.0), Color.BLACK, 5)
	conteudo.add_child(logo_titulo)

	logo_preview_moldura = Panel.new()
	logo_preview_moldura.name = "LogoPreviewMoldura"
	logo_preview_moldura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_preview_moldura.clip_contents = true
	logo_preview_moldura.add_theme_stylebox_override("panel", _estilo_preview_logo())
	conteudo.add_child(logo_preview_moldura)

	logo_preview = TextureRect.new()
	logo_preview.name = "LogoPreview"
	logo_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	conteudo.add_child(logo_preview)

	logo_valor = _criar_label("", 22, Color(0.86, 0.92, 1.0, 1.0), Color.BLACK, 4)
	conteudo.add_child(logo_valor)

	btn_logo_escolher = _criar_botao("ESCOLHER LOGO...", cor_neon)
	btn_logo_padrao = _criar_botao("USAR PADRÃO", Color(0.55, 0.70, 1.0, 1.0))
	conteudo.add_child(btn_logo_escolher)
	conteudo.add_child(btn_logo_padrao)

	divisor_4 = Panel.new()
	divisor_4.name = "Divisor4"
	divisor_4.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divisor_4.add_theme_stylebox_override("panel", _estilo_divisor())
	conteudo.add_child(divisor_4)

	# --- RESET DO RECORD ---
	btn_reset_record = _criar_botao("RESETAR RECORD", cor_reset)
	conteudo.add_child(btn_reset_record)

	# Fades de borda do scroll — reforço visual de que a área rola.
	# Adicionados DEPOIS do scroll na árvore, então desenham por cima
	# das bordas do conteúdo, criando o efeito de "esmaecer" suave.
	fade_topo_scroll = _criar_fade_scroll(true)
	painel.add_child(fade_topo_scroll)

	fade_base_scroll = _criar_fade_scroll(false)
	painel.add_child(fade_base_scroll)

	# --- RODAPÉ FIXO (fora do scroll) ---
	btn_salvar = _criar_botao("SALVAR E JOGAR", Color(0.30, 1.0, 0.48, 1.0))
	painel.add_child(btn_salvar)

	btn_voltar = _criar_botao("VOLTAR", Color(1.0, 0.22, 0.18, 1.0))
	painel.add_child(btn_voltar)

	btn_salvar.add_theme_font_size_override("font_size", 32)
	btn_voltar.add_theme_font_size_override("font_size", 28)

	ajuda = _criar_label(
		"USE OS BOTÕES DA TELA PARA AJUSTAR E CONFIRMAR",
		20,
		Color(0.86, 0.92, 1.0, 1.0),
		Color.BLACK,
		4
	)
	painel.add_child(ajuda)

	status = _criar_label("", 26, Color.WHITE, Color.BLACK, 5)
	painel.add_child(status)

	btn_menos_60.pressed.connect(_alterar_tempo.bind(-passo_tempo_grande))
	btn_menos_10.pressed.connect(_alterar_tempo.bind(-passo_tempo))
	btn_mais_10.pressed.connect(_alterar_tempo.bind(passo_tempo))
	btn_mais_60.pressed.connect(_alterar_tempo.bind(passo_tempo_grande))

	btn_modo.pressed.connect(_alternar_modo)
	btn_reset_record.pressed.connect(_pedir_confirmacao_reset)

	btn_menos_delay_grande.pressed.connect(_alterar_delay.bind(-passo_trava_grosso))
	btn_menos_delay.pressed.connect(_alterar_delay.bind(-passo_trava_fino))
	btn_mais_delay.pressed.connect(_alterar_delay.bind(passo_trava_fino))
	btn_mais_delay_grande.pressed.connect(_alterar_delay.bind(passo_trava_grosso))

	btn_logo_escolher.pressed.connect(_abrir_seletor_logo)
	btn_logo_padrao.pressed.connect(_restaurar_logo_padrao)

	btn_salvar.pressed.connect(_salvar_config)
	btn_voltar.pressed.connect(_voltar)



func _criar_fade_scroll(de_cima: bool) -> TextureRect:
	var cor_base := Color(0.035, 0.030, 0.045)
	var grad := Gradient.new()
	if de_cima:
		grad.offsets = PackedFloat32Array([0.0, 1.0])
		grad.colors = PackedColorArray([
			Color(cor_base.r, cor_base.g, cor_base.b, 0.95),
			Color(cor_base.r, cor_base.g, cor_base.b, 0.0)
		])
	else:
		grad.offsets = PackedFloat32Array([0.0, 1.0])
		grad.colors = PackedColorArray([
			Color(cor_base.r, cor_base.g, cor_base.b, 0.0),
			Color(cor_base.r, cor_base.g, cor_base.b, 0.95)
		])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 4
	gt.height = 64
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)

	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr



func _montar_overlay_reset() -> void:
	overlay_reset = Control.new()
	overlay_reset.name = "OverlayReset"
	overlay_reset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_reset.visible = false
	overlay_reset.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay_reset)

	var escuro := ColorRect.new()
	escuro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	escuro.color = Color(0.0, 0.0, 0.0, 0.82)
	escuro.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_reset.add_child(escuro)

	painel_reset = Panel.new()
	painel_reset.clip_contents = true
	painel_reset.add_theme_stylebox_override("panel", _estilo_painel(cor_reset))
	overlay_reset.add_child(painel_reset)

	lbl_reset_titulo = _criar_label("RESETAR RECORD?", 46, Color.WHITE, cor_reset, 8)
	painel_reset.add_child(lbl_reset_titulo)

	lbl_reset_texto = _criar_label(
		"Essa ação apaga o recorde salvo\ne grava ZERO no banco do jogo.",
		26, Color(1.0, 0.92, 0.82, 1.0), Color.BLACK, 5
	)
	painel_reset.add_child(lbl_reset_texto)

	lbl_reset_dica = _criar_label(
		"ESCOLHA UMA OPÇÃO ABAIXO",
		24, Color(0.86, 0.92, 1.0, 1.0), Color.BLACK, 4
	)
	painel_reset.add_child(lbl_reset_dica)

	btn_reset_confirmar = _criar_botao("SIM, ZERAR", cor_reset)
	btn_reset_cancelar = _criar_botao("CANCELAR", Color(0.30, 1.0, 0.48, 1.0))
	painel_reset.add_child(btn_reset_confirmar)
	painel_reset.add_child(btn_reset_cancelar)

	_botoes_reset = [btn_reset_confirmar, btn_reset_cancelar]
	_cores_reset = [cor_reset, Color(0.30, 1.0, 0.48, 1.0)]
	_opcao_reset_atual = 1

	btn_reset_confirmar.pressed.connect(_resetar_record)
	btn_reset_cancelar.pressed.connect(_cancelar_reset)
	btn_reset_confirmar.mouse_entered.connect(_selecionar_opcao_reset.bind(0))
	btn_reset_cancelar.mouse_entered.connect(_selecionar_opcao_reset.bind(1))
	_atualizar_botoes_reset_hover()



func _criar_label(texto: String, tamanho: int, cor: Color, outline: Color, outline_size: int) -> Label:
	var l := Label.new()
	l.text = texto
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", tamanho)
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
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.disabled = false

	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.BLACK)
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_theme_constant_override("outline_size", 4)

	if caminho_fonte != "" and ResourceLoader.exists(caminho_fonte):
		var f := load(caminho_fonte)
		if f is Font:
			b.add_theme_font_override("font", f)

	b.add_theme_stylebox_override("normal", _estilo_botao(cor, 0))
	b.add_theme_stylebox_override("hover", _estilo_botao(cor, 1))
	b.add_theme_stylebox_override("pressed", _estilo_botao(cor, 2))
	b.add_theme_stylebox_override("focus", _estilo_botao(cor, 1))

	return b



func _estilo_painel(cor: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.030, 0.045, 0.98)
	sb.border_color = cor
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(32)
	sb.corner_detail = 14
	sb.set_content_margin_all(26)
	sb.shadow_color = Color(cor.r, cor.g, cor.b, 0.62)
	sb.shadow_size = 46
	sb.shadow_offset = Vector2.ZERO
	sb.anti_aliasing = true
	return sb


func _estilo_botao(cor: Color, estado: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()

	if estado == 0:
		sb.bg_color = Color(0.055, 0.050, 0.070, 0.98)
		sb.shadow_size = 12
	elif estado == 1:
		sb.bg_color = Color(cor.r * 0.28, cor.g * 0.28, cor.b * 0.28, 0.98)
		sb.shadow_size = 28
	else:
		sb.bg_color = Color(cor.r, cor.g, cor.b, 0.96)
		sb.shadow_size = 32

	sb.border_color = cor
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(18)
	sb.corner_detail = 10
	sb.shadow_color = Color(cor.r, cor.g, cor.b, 0.68)
	sb.shadow_offset = Vector2.ZERO
	sb.anti_aliasing = true
	return sb


func _estilo_preview_logo() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.035, 0.95)
	sb.border_color = cor_neon
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(20)
	sb.corner_detail = 12
	sb.shadow_color = Color(cor_neon.r, cor_neon.g, cor_neon.b, 0.42)
	sb.shadow_size = 18
	sb.anti_aliasing = true
	return sb


func _estilo_divisor() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(cor_neon.r, cor_neon.g, cor_neon.b, 0.22)
	sb.set_corner_radius_all(3)
	sb.anti_aliasing = true
	return sb



func _ajustar_layout() -> void:
	var tela: Vector2 = get_viewport_rect().size

	if fundo != null:
		fundo.position = Vector2.ZERO
		fundo.size = tela

	if escurecer != null:
		escurecer.position = Vector2.ZERO
		escurecer.size = tela

	# Painel com ALTURA TRAVADA: nunca ultrapassa o espaço real da tela.
	# O que não couber dentro dessa altura fixa rola dentro do
	# ScrollContainer — nada mais cresce pra fora da viewport.
	var painel_w: float = clampf(tela.x - 80.0, 760.0, 1000.0)
	var painel_h: float = tela.y - 60.0

	if painel != null:
		painel.size = Vector2(painel_w, painel_h)
		painel.position = Vector2(
			round((tela.x - painel_w) * 0.5),
			round((tela.y - painel_h) * 0.5)
		)

	var margem: float = 44.0
	var largura_util: float = painel_w - margem * 2.0

	# --- CABEÇALHO FIXO ---
	var y_topo: float = 24.0
	if titulo != null:
		titulo.position = Vector2(margem, y_topo)
		titulo.size = Vector2(largura_util, 64.0)
	y_topo += 64.0 + 14.0

	# --- RODAPÉ FIXO — calculado de baixo pra cima, sempre colado na
	# base do painel, com sua própria margem interna.
	var alt_status: float = 32.0
	var alt_ajuda: float = 40.0
	var alt_botoes: float = 70.0
	var gaps_rodape: float = 16.0 + 8.0
	var altura_rodape: float = alt_botoes + gaps_rodape + alt_ajuda + alt_status + 18.0
	var y_rodape_topo: float = painel_h - altura_rodape

	var gap_rodape: float = 20.0
	var btn_w2_rodape: float = (largura_util - gap_rodape) * 0.5
	var yr: float = y_rodape_topo
	if btn_salvar != null:
		btn_salvar.position = Vector2(margem, yr)
		btn_salvar.size = Vector2(btn_w2_rodape, alt_botoes)
	if btn_voltar != null:
		btn_voltar.position = Vector2(margem + btn_w2_rodape + gap_rodape, yr)
		btn_voltar.size = Vector2(btn_w2_rodape, alt_botoes)
	yr += alt_botoes + 16.0

	if ajuda != null:
		ajuda.position = Vector2(margem, yr)
		ajuda.size = Vector2(largura_util, alt_ajuda)
	yr += alt_ajuda + 8.0

	if status != null:
		status.position = Vector2(margem, yr)
		status.size = Vector2(largura_util, alt_status)

	# --- ÁREA COM SCROLL (entre o cabeçalho e o rodapé) ---
	if scroll != null:
		scroll.position = Vector2(0.0, y_topo)
		scroll.size = Vector2(painel_w, max(60.0, y_rodape_topo - 12.0 - y_topo))

	if fade_topo_scroll != null:
		fade_topo_scroll.position = Vector2(0.0, scroll.position.y)
		fade_topo_scroll.size = Vector2(painel_w, 30.0)
	if fade_base_scroll != null:
		fade_base_scroll.position = Vector2(0.0, scroll.position.y + scroll.size.y - 30.0)
		fade_base_scroll.size = Vector2(painel_w, 30.0)

	# --- CONTEÚDO INTERNO — coordenadas locais dentro do scroll. O
	# que passar da altura visível simplesmente fica rolável.
	var yc: float = 12.0
	var btn_w4: float = (largura_util - 3.0 * 14.0) / 4.0
	var margem_divisor: float = largura_util * 0.06
	var largura_divisor: float = largura_util * 0.88

	if tempo_titulo != null:
		tempo_titulo.position = Vector2(margem, yc)
		tempo_titulo.size = Vector2(largura_util, 36.0)
	yc += 36.0 + 4.0

	if tempo_valor != null:
		tempo_valor.position = Vector2(margem, yc)
		tempo_valor.size = Vector2(largura_util, 104.0)
	yc += 104.0 + 10.0

	var botoes_tempo := [btn_menos_60, btn_menos_10, btn_mais_10, btn_mais_60]
	for i in range(botoes_tempo.size()):
		var b: Button = botoes_tempo[i]
		if b == null:
			continue
		b.position = Vector2(margem + float(i) * (btn_w4 + 14.0), yc)
		b.size = Vector2(btn_w4, 64.0)
	yc += 64.0 + 14.0

	if divisor_1 != null:
		divisor_1.position = Vector2(margem + margem_divisor, yc)
		divisor_1.size = Vector2(largura_divisor, 2.0)
	yc += 16.0

	if modo_titulo != null:
		modo_titulo.position = Vector2(margem, yc)
		modo_titulo.size = Vector2(largura_util, 36.0)
	yc += 36.0 + 4.0

	if modo_valor != null:
		modo_valor.position = Vector2(margem, yc)
		modo_valor.size = Vector2(largura_util, 62.0)
	yc += 62.0 + 8.0

	if btn_modo != null:
		btn_modo.position = Vector2(margem + largura_util * 0.10, yc)
		btn_modo.size = Vector2(largura_util * 0.80, 56.0)
	yc += 56.0 + 14.0

	if divisor_2 != null:
		divisor_2.position = Vector2(margem + margem_divisor, yc)
		divisor_2.size = Vector2(largura_divisor, 2.0)
	yc += 16.0

	if delay_titulo != null:
		delay_titulo.position = Vector2(margem, yc)
		delay_titulo.size = Vector2(largura_util, 36.0)
	yc += 36.0 + 4.0

	if delay_valor != null:
		delay_valor.position = Vector2(margem, yc)
		delay_valor.size = Vector2(largura_util, 62.0)
	yc += 62.0 + 10.0

	var botoes_delay := [btn_menos_delay_grande, btn_menos_delay, btn_mais_delay, btn_mais_delay_grande]
	for i in range(botoes_delay.size()):
		var bd: Button = botoes_delay[i]
		if bd == null:
			continue
		bd.position = Vector2(margem + float(i) * (btn_w4 + 14.0), yc)
		bd.size = Vector2(btn_w4, 56.0)
	yc += 56.0 + 18.0

	if divisor_3 != null:
		divisor_3.position = Vector2(margem + margem_divisor, yc)
		divisor_3.size = Vector2(largura_divisor, 2.0)
	yc += 16.0

	if logo_titulo != null:
		logo_titulo.position = Vector2(margem, yc)
		logo_titulo.size = Vector2(largura_util, 36.0)
	yc += 36.0 + 12.0

	var preview_h: float = 260.0
	if logo_preview_moldura != null:
		logo_preview_moldura.position = Vector2(margem, yc)
		logo_preview_moldura.size = Vector2(largura_util, preview_h)
	if logo_preview != null:
		var pad: float = 8.0
		logo_preview.position = Vector2(margem + pad, yc + pad)
		logo_preview.size = Vector2(largura_util - pad * 2.0, preview_h - pad * 2.0)
	yc += preview_h + 14.0

	if logo_valor != null:
		logo_valor.position = Vector2(margem, yc)
		logo_valor.size = Vector2(largura_util, 36.0)
	yc += 36.0 + 14.0

	var gap_logo: float = 16.0
	var btn_w2_logo: float = (largura_util - gap_logo) * 0.5
	if btn_logo_escolher != null:
		btn_logo_escolher.position = Vector2(margem, yc)
		btn_logo_escolher.size = Vector2(btn_w2_logo, 64.0)
	if btn_logo_padrao != null:
		btn_logo_padrao.position = Vector2(margem + btn_w2_logo + gap_logo, yc)
		btn_logo_padrao.size = Vector2(btn_w2_logo, 64.0)
	yc += 64.0 + 14.0

	if divisor_4 != null:
		divisor_4.position = Vector2(margem + margem_divisor, yc)
		divisor_4.size = Vector2(largura_divisor, 2.0)
	yc += 16.0

	if btn_reset_record != null:
		btn_reset_record.position = Vector2(margem + largura_util * 0.10, yc)
		btn_reset_record.size = Vector2(largura_util * 0.80, 64.0)
	yc += 64.0 + 20.0

	if conteudo != null:
		conteudo.custom_minimum_size = Vector2(painel_w, yc)

	_ajustar_layout_overlay(tela)



func _ajustar_layout_overlay(tela: Vector2) -> void:
	if painel_reset == null:
		return
	var w: float = min(760.0, tela.x - 100.0)
	var h: float = min(520.0, tela.y - 160.0)
	painel_reset.position = Vector2(round((tela.x - w) * 0.5), round((tela.y - h) * 0.5))
	painel_reset.size = Vector2(w, h)

	if lbl_reset_titulo != null:
		lbl_reset_titulo.position = Vector2(30.0, 56.0)
		lbl_reset_titulo.size = Vector2(w - 60.0, 70.0)
	if lbl_reset_texto != null:
		lbl_reset_texto.position = Vector2(30.0, 168.0)
		lbl_reset_texto.size = Vector2(w - 60.0, 110.0)
	if lbl_reset_dica != null:
		lbl_reset_dica.position = Vector2(30.0, h - 174.0)
		lbl_reset_dica.size = Vector2(w - 60.0, 52.0)

	var gap_btn: float = 18.0
	var btn_w: float = (w - 60.0 - gap_btn) * 0.5
	var btn_h: float = 68.0
	var y_btn: float = h - 96.0
	if btn_reset_confirmar != null:
		btn_reset_confirmar.position = Vector2(30.0, y_btn)
		btn_reset_confirmar.size = Vector2(btn_w, btn_h)
	if btn_reset_cancelar != null:
		btn_reset_cancelar.position = Vector2(30.0 + btn_w + gap_btn, y_btn)
		btn_reset_cancelar.size = Vector2(btn_w, btn_h)



# =====================================================================
# AÇÕES
# =====================================================================
func _alterar_tempo(valor: int) -> void:
	tempo_partida = clampi(tempo_partida + valor, tempo_minimo, tempo_maximo)
	_atualizar_textos()
	_pulse(tempo_valor)



func _alternar_modo() -> void:
	modo_credito = not modo_credito
	_atualizar_textos()
	_pulse(modo_valor)




func _alterar_delay(valor: float) -> void:
	tempo_trava_cesta = clampf(tempo_trava_cesta + valor, tempo_trava_min, tempo_trava_max)
	_atualizar_textos()
	_pulse(delay_valor)



func _atualizar_textos() -> void:
	var minutos: int = tempo_partida / 60
	var segundos: int = tempo_partida % 60

	if tempo_valor != null:
		tempo_valor.text = "%02d:%02d" % [minutos, segundos]

	if modo_valor != null:
		if modo_credito:
			modo_valor.text = "CRÉDITO"
			modo_valor.add_theme_color_override("font_color", cor_credito)
		else:
			modo_valor.text = "LIVRE"
			modo_valor.add_theme_color_override("font_color", cor_livre)

	if btn_modo != null:
		btn_modo.text = "MUDAR PARA LIVRE" if modo_credito else "MUDAR PARA CRÉDITO"


	if delay_valor != null:
		delay_valor.text = "%.1f s" % tempo_trava_cesta

	_atualizar_preview_logo()

	if status != null:
		status.text = ""

	_atualizar_botoes_hover()



func _pulse(no: Control) -> void:
	if no == null:
		return
	no.pivot_offset = no.size * 0.5
	var tw := create_tween()
	tw.tween_property(no, "scale", Vector2(1.08, 1.08), 0.08)
	tw.tween_property(no, "scale", Vector2.ONE, 0.14)



func _voltar() -> void:
	if _fechando:
		return
	if modo_overlay:
		_fechar_overlay(false)
		return
	_fechando = true
	await _animar_saida_overlay()
	var alvo := cena_voltar if cena_voltar != "" else "res://scenes/opening.tscn"
	_trocar_cena(alvo)


func _ir_para_jogo() -> void:
	_fechando = true
	await _animar_saida_overlay()
	var alvo := cena_jogo if cena_jogo != "" else "res://scenes/play.tscn"
	_trocar_cena(alvo)


func _fechar_overlay(salvou: bool) -> void:
	if _fechando:
		return
	_fechando = true
	await _animar_saida_overlay()
	# Não damos free aqui: quem instanciou o overlay (abertura.gd) é
	# responsável por remover a CanvasLayer que o contém. Como o fade
	# acima já deixou TUDO (fundo, painel, cursor) transparente antes
	# de emitir o sinal, remover a camada é invisível pro jogador —
	# sem corte seco voltando pra tela de abertura.
	fechado.emit(salvou)



# =====================================================================
# TRANSIÇÕES DE ENTRADA E SAÍDA
# =====================================================================
func _animar_entrada_grupo(nos: Array, atraso: float, offset: Vector2) -> void:
	for n in nos:
		if n == null:
			continue
		var alvo: Vector2 = n.position
		n.position = alvo + offset
		var t := create_tween()
		t.tween_property(n, "position", alvo, 0.34)\
			.set_delay(atraso)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _animar_entrada_overlay() -> void:
	var tg := create_tween()
	tg.tween_property(self, "modulate:a", 1.0, 0.22)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if cursor_neon != null:
		var tc := create_tween()
		tc.tween_property(cursor_neon, "modulate:a", 1.0, 0.24)

	if painel != null:
		painel.pivot_offset = painel.size * 0.5
		painel.scale = Vector2(0.93, 0.93)
		var tp := create_tween()
		tp.tween_property(painel, "scale", Vector2.ONE, 0.32)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# "Montagem": cada bloco desliza pra dentro alternando esquerda e
	# direita, com atraso crescente — dá a sensação de a tela sendo
	# construída em vez de simplesmente aparecer inteira de uma vez.
	var atraso: float = 0.0
	_animar_entrada_grupo([titulo], atraso, Vector2(0, -18))
	atraso += 0.05
	_animar_entrada_grupo([tempo_titulo, tempo_valor, btn_menos_60, btn_menos_10, btn_mais_10, btn_mais_60], atraso, Vector2(-32, 0))
	atraso += 0.05
	_animar_entrada_grupo([modo_titulo, modo_valor, btn_modo], atraso, Vector2(32, 0))
	atraso += 0.05
	_animar_entrada_grupo([delay_titulo, delay_valor, btn_menos_delay_grande, btn_menos_delay, btn_mais_delay, btn_mais_delay_grande], atraso, Vector2(-32, 0))
	atraso += 0.05
	_animar_entrada_grupo([logo_titulo, logo_preview_moldura, logo_preview, logo_valor, btn_logo_escolher, btn_logo_padrao], atraso, Vector2(32, 0))
	atraso += 0.05
	_animar_entrada_grupo([btn_reset_record], atraso, Vector2(-24, 0))
	atraso += 0.06
	_animar_entrada_grupo([btn_salvar, btn_voltar, ajuda, status], atraso, Vector2(0, 24))


func _animar_saida_overlay() -> void:
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 0.0, 0.22)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if painel != null:
		painel.pivot_offset = painel.size * 0.5
		t.tween_property(painel, "scale", Vector2(0.95, 0.95), 0.22)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if cursor_neon != null:
		t.tween_property(cursor_neon, "modulate:a", 0.0, 0.16)
	await t.finished



# =====================================================================
# INPUT
# =====================================================================
func _unhandled_input(evento: InputEvent) -> void:
	if _fechando:
		return

	if _confirmando_reset:
		if evento.is_action_pressed("input_select"):
			_navegar_reset(1)
			_input_handled_seguro()
			return
		if evento.is_action_pressed("input_start"):
			_executar_reset_atual()
			_input_handled_seguro()
			return
		if evento is InputEventKey and evento.pressed and not evento.echo:
			match (evento as InputEventKey).keycode:
				KEY_ENTER:
					_executar_reset_atual()
					_input_handled_seguro()
				KEY_ESCAPE:
					_cancelar_reset()
					_input_handled_seguro()
				KEY_RIGHT, KEY_DOWN:
					_navegar_reset(1)
					_input_handled_seguro()
				KEY_LEFT, KEY_UP:
					_navegar_reset(-1)
					_input_handled_seguro()
		return

	if _salvando:
		return

	if evento.is_action_pressed("input_select"):
		_navegar_opcao(1)
		_input_handled_seguro()
		return

	if evento.is_action_pressed("input_start"):
		_executar_opcao_atual()
		_input_handled_seguro()
		return

	if evento is InputEventKey:
		var k := evento as InputEventKey
		if not k.pressed or k.echo:
			return

		match k.keycode:
			KEY_ENTER:
				_executar_opcao_atual()
				_input_handled_seguro()
				return
			KEY_ESCAPE:
				_voltar()
				_input_handled_seguro()
				return
			KEY_RIGHT, KEY_DOWN:
				_navegar_opcao(1)
				_input_handled_seguro()
				return
			KEY_LEFT, KEY_UP:
				_navegar_opcao(-1)
				_input_handled_seguro()
				return



func _registrar_botoes_navegacao() -> void:
	_opcoes_botoes.clear()
	_opcoes_acoes.clear()
	_opcoes_cores.clear()

	_adicionar_opcao(btn_menos_60, "menos_60", cor_neon)
	_adicionar_opcao(btn_menos_10, "menos_10", cor_neon)
	_adicionar_opcao(btn_mais_10, "mais_10", cor_neon)
	_adicionar_opcao(btn_mais_60, "mais_60", cor_neon)
	_adicionar_opcao(btn_modo, "modo", cor_livre)
	_adicionar_opcao(btn_menos_delay_grande, "menos_delay_grande", cor_neon)
	_adicionar_opcao(btn_menos_delay, "menos_delay", cor_neon)
	_adicionar_opcao(btn_mais_delay, "mais_delay", cor_neon)
	_adicionar_opcao(btn_mais_delay_grande, "mais_delay_grande", cor_neon)
	_adicionar_opcao(btn_logo_escolher, "logo_escolher", cor_neon)
	_adicionar_opcao(btn_logo_padrao, "logo_padrao", Color(0.55, 0.70, 1.0, 1.0))
	_adicionar_opcao(btn_reset_record, "reset_record", cor_reset)
	_adicionar_opcao(btn_salvar, "salvar", Color(0.30, 1.0, 0.48, 1.0))
	_adicionar_opcao(btn_voltar, "voltar", Color(1.0, 0.22, 0.18, 1.0))

	_opcao_atual = clampi(_opcao_atual, 0, max(_opcoes_botoes.size() - 1, 0))
	_atualizar_botoes_hover()



func _adicionar_opcao(btn: Button, acao: String, cor: Color) -> void:
	if btn == null:
		return

	_opcoes_botoes.append(btn)
	_opcoes_acoes.append(acao)
	_opcoes_cores.append(cor)

	if not btn.mouse_entered.is_connected(_selecionar_opcao_mouse_por_botao):
		btn.mouse_entered.connect(_selecionar_opcao_mouse_por_botao.bind(btn))



func _selecionar_opcao_mouse_por_botao(btn: Button) -> void:
	if _salvando or _confirmando_reset or _fechando:
		return
	var idx := _opcoes_botoes.find(btn)
	if idx >= 0:
		_opcao_atual = idx
		_atualizar_botoes_hover()



func _navegar_opcao(direcao: int) -> void:
	if _opcoes_botoes.is_empty():
		return

	_opcao_atual += direcao
	if _opcao_atual >= _opcoes_botoes.size():
		_opcao_atual = 0
	if _opcao_atual < 0:
		_opcao_atual = _opcoes_botoes.size() - 1

	_atualizar_botoes_hover()



func _executar_opcao_atual() -> void:
	if _opcoes_acoes.is_empty():
		return

	var acao: String = str(_opcoes_acoes[_opcao_atual])

	match acao:
		"menos_60":
			_alterar_tempo(-passo_tempo_grande)
		"menos_10":
			_alterar_tempo(-passo_tempo)
		"mais_10":
			_alterar_tempo(passo_tempo)
		"mais_60":
			_alterar_tempo(passo_tempo_grande)
		"modo":
			_alternar_modo()
		"reset_record":
			_pedir_confirmacao_reset()
		"menos_delay_grande":
			_alterar_delay(-passo_trava_grosso)
		"menos_delay":
			_alterar_delay(-passo_trava_fino)
		"mais_delay":
			_alterar_delay(passo_trava_fino)
		"mais_delay_grande":
			_alterar_delay(passo_trava_grosso)
		"logo_escolher":
			_abrir_seletor_logo()
		"logo_padrao":
			_restaurar_logo_padrao()
		"salvar":
			_salvar_config()
		"voltar":
			_voltar()


func _selecionar_opcao_reset(indice: int) -> void:
	if not _confirmando_reset:
		return
	_opcao_reset_atual = clampi(indice, 0, max(_botoes_reset.size() - 1, 0))
	_atualizar_botoes_reset_hover()



func _navegar_reset(direcao: int) -> void:
	if _botoes_reset.is_empty():
		return
	_opcao_reset_atual += direcao
	if _opcao_reset_atual >= _botoes_reset.size():
		_opcao_reset_atual = 0
	if _opcao_reset_atual < 0:
		_opcao_reset_atual = _botoes_reset.size() - 1
	_atualizar_botoes_reset_hover()



func _executar_reset_atual() -> void:
	if _opcao_reset_atual == 0:
		_resetar_record()
	else:
		_cancelar_reset()



func _atualizar_botoes_reset_hover() -> void:
	for i in range(_botoes_reset.size()):
		var btn: Button = _botoes_reset[i]
		if btn == null:
			continue
		var cor: Color = _cores_reset[i]
		var selecionado: bool = i == _opcao_reset_atual
		if selecionado:
			btn.add_theme_stylebox_override("normal", _estilo_botao(cor, 1))
			btn.add_theme_stylebox_override("hover", _estilo_botao(cor, 2))
			btn.scale = Vector2(1.04, 1.04)
			btn.modulate = Color.WHITE
		else:
			btn.add_theme_stylebox_override("normal", _estilo_botao(cor, 0))
			btn.add_theme_stylebox_override("hover", _estilo_botao(cor, 1))
			btn.scale = Vector2.ONE
			btn.modulate = Color(1, 1, 1, 0.78)




func _atualizar_botoes_hover() -> void:
	for i in range(_opcoes_botoes.size()):
		var btn: Button = _opcoes_botoes[i]
		if btn == null:
			continue

		var selecionado: bool = i == _opcao_atual
		var cor: Color = _opcoes_cores[i]

		if btn == btn_modo:
			cor = cor_credito if modo_credito else cor_livre

		if selecionado:
			btn.add_theme_stylebox_override("normal", _estilo_botao(cor, 1))
			btn.add_theme_stylebox_override("hover", _estilo_botao(cor, 2))
			btn.scale = Vector2(1.04, 1.04)
			btn.modulate = Color.WHITE
		else:
			btn.add_theme_stylebox_override("normal", _estilo_botao(cor, 0))
			btn.add_theme_stylebox_override("hover", _estilo_botao(cor, 1))
			btn.scale = Vector2.ONE
			btn.modulate = Color(1, 1, 1, 0.76)

	# Rolagem automática: se o botão selecionado por teclado/joystick
	# estiver dentro da área com scroll e fora da parte visível, o
	# ScrollContainer rola sozinho até ele aparecer. Botões do rodapé
	# (Salvar/Voltar) ficam fora do scroll, então são ignorados aqui.
	if scroll != null and conteudo != null and _opcao_atual >= 0 and _opcao_atual < _opcoes_botoes.size():
		var btn_atual: Button = _opcoes_botoes[_opcao_atual]
		if btn_atual != null and conteudo.is_ancestor_of(btn_atual):
			scroll.ensure_control_visible(btn_atual)



func _input_handled_seguro() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()



# =====================================================================
# CURSOR NEON
# =====================================================================
func _criar_cursor_custom() -> void:
	cursor_layer = CanvasLayer.new()
	cursor_layer.layer = 999
	add_child(cursor_layer)

	cursor_neon = CursorNeon.new()
	cursor_neon.name = "CursorNeon"
	cursor_neon.cor_normal = cor_neon
	cursor_neon.cor_hover = cor_livre
	cursor_neon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# CanvasLayer quebra a herança de modulate do pai — por isso o
	# cursor precisa ter seu próprio fade manual em vez de herdar o
	# fade da tela inteira (ver _animar_entrada_overlay/_saida_overlay).
	cursor_neon.modulate.a = 0.0
	cursor_layer.add_child(cursor_neon)



class CursorNeon extends Control:
	var cor_normal: Color = Color(1.0, 0.55, 0.10, 1.0)
	var cor_hover: Color = Color(0.24, 1.0, 0.48, 1.0)

	var _hover: bool = false
	var _fase: float = 0.0
	var _escala: float = 1.0

	const _PTS := [
		Vector2(0.0, 0.0),
		Vector2(0.0, 20.0),
		Vector2(5.0, 15.0),
		Vector2(9.0, 23.0),
		Vector2(13.0, 19.0),
		Vector2(8.0, 11.0),
		Vector2(15.0, 11.0),
	]
	const _TRIS := [
		[0, 1, 2],
		[0, 2, 5],
		[0, 5, 6],
		[2, 3, 4],
		[2, 4, 5],
	]
	const _CONTORNO := [0, 6, 5, 4, 3, 2, 1, 0]


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_level = true
		z_index = 4096
		custom_minimum_size = Vector2(28, 28)
		set_process(true)


	func definir_hover(v: bool) -> void:
		if v != _hover:
			_hover = v
		queue_redraw()


	func _process(delta: float) -> void:
		_fase += delta * (6.5 if _hover else 3.2)
		var alvo := 1.18 if _hover else 1.0
		_escala = lerp(_escala, alvo, clamp(delta * 12.0, 0.0, 1.0))
		queue_redraw()


	func _draw() -> void:
		var cor := cor_hover if _hover else cor_normal
		var pulso := 0.5 + 0.5 * sin(_fase)

		var pts: PackedVector2Array = PackedVector2Array()
		for p in _PTS:
			pts.append(p * _escala)

		var contorno := PackedVector2Array()
		for idx in _CONTORNO:
			contorno.append(pts[idx])
		var camadas := 4
		for c in range(camadas):
			var t := float(c) / float(camadas - 1)
			var largura : float = lerp(10.0, 2.0, t) * (1.0 + 0.25 * pulso)
			var alfa : float = lerp(0.05, 0.22, t) * (0.7 + 0.3 * pulso)
			draw_polyline(contorno, Color(cor.r, cor.g, cor.b, alfa), largura, true)

		var preenche := Color(0.05, 0.05, 0.07, 0.96)
		for tri in _TRIS:
			var tri_pts := PackedVector2Array([pts[tri[0]], pts[tri[1]], pts[tri[2]]])
			draw_colored_polygon(tri_pts, preenche)

		draw_polyline(contorno, Color(cor.r, cor.g, cor.b, 0.95), 2.0, true)

		draw_circle(pts[0], 2.2 + 1.4 * pulso, Color(cor.r, cor.g, cor.b, 0.30 + 0.25 * pulso))


func _trocar_cena(caminho: String) -> void:
	if caminho == "":
		return
	var tela_node := get_node_or_null("/root/Tela")
	if tela_node != null and tela_node.has_method("trocar"):
		tela_node.trocar(caminho)
	else:
		if ResourceLoader.exists(caminho):
			get_tree().change_scene_to_file(caminho)
	
