extends Control
# =====================================================================
# ABERTURA — SWISH ARENA
# Tela de abertura vistosa, montada 100% em código.
#
# Recursos:
#  - Imagem de fundo (back_op) com SHADER: respiração/zoom suave,
#    aberração cromática nas bordas, brilho quente pulsando no centro,
#    sweep de luz diagonal, realce roxo nas bordas, bloom falso,
#    vinheta e grão anti-banding.
#  - PARTÍCULAS: brasas subindo, faíscas no centro e poeira flutuando.
#  - Scanlines CRT bem leves por cima.
#  - "PRESSIONE START" com glow pulsante.
#  - MODAL DE PLAYERS: cada START soma 1 jogador, cronômetro que
#    reinicia a cada toque, pop-in encadeado, pulso no card escolhido,
#    pills de LED arredondadas e animação de confirmação.
#  - LEDS ARDUINO (NeoPixel): ponte PowerShell em COM5, comandos
#    ATTRACT / MENU_LOCK / SELECT1..4 / STARTING / OFF. Ao encerrar
#    ou trocar para o Play, envia OFF e fecha a porta COM com segurança.
#  - Transições à prova de "flash" (sempre fecha preto antes da troca).
#    START avança via autoload Tela (rotação).
#
# Tudo com CANTOS ARREDONDADOS — sem quadradinhos.
#
# COMO USAR:
#  - Nó raiz: um Control (ex.: "Abertura") com este script.
#  - Ajuste 'caminho_fundo' para a sua imagem (back_op).
# =====================================================================

# ---------- CONFIG ----------
@export var caminho_fundo: String = "res://images/back_op.png"
@export_file("*.tscn") var proxima_cena: String = "res://scenes/play.tscn"
@export_file("*.tscn") var cena_config: String = "res://scenes/config.tscn"
@export var caminho_fonte: String = "res://fonts/titan.ttf"
@export var caminho_config_basket: String = "user://basket_config.cfg"
@export var texto_start_livre: String = "APERTE START"
@export var texto_start_credito: String = "INSIRA UM COIN"
@export var texto_start: String = "APERTE START"
@export var acao_start: String = "input_start"
@export var permitir_avancar: bool = true
@export var tempo_fade_saida: float = 0.42


@export_file("*.tscn") var cena_network_lobby: String = "res://scenes/network_lobby.tscn"


# ---------- MODAL DE JOGADORES ----------
@export var jogadores_min: int = 1
@export var jogadores_max: int = 4
@export var tempo_para_confirmar: float = 3.5     # janela que reinicia a cada START
@export var tempo_maximo_modal: float = 16.0      # teto absoluto
@export var atraso_entrada_apos_max: float = 0.55 # ao bater no máximo, confirma rápido
@export var meta_num_jogadores: String = "num_jogadores"
@export var debounce_start_ms: int = 180  # tempo mínimo entre registros de START — evita bounce do botão físico ou eventos duplicados contando como 2 toques
@export var texto_modal_titulo: String = "QUANTOS JOGADORES?"
@export var texto_modal_subtitulo: String = "CADA TOQUE ADICIONA 1 JOGADOR"
@export var texto_comando_start: String = "APERTE START"
@export var texto_acao_start: String = ""

# ---------- PALETA (combina com a arte) ----------
@export var cor_quente: Color = Color(1.0, 0.45, 0.08)   # laranja
@export var cor_fria: Color = Color(0.45, 0.22, 1.0)     # roxo

# ---------- LIGA/DESLIGA EFEITOS ----------
@export var usar_shader_fundo: bool = true
@export var usar_particulas: bool = true
@export var usar_scanlines: bool = true

# ---------- INTENSIDADES DO SHADER ----------
@export var brilho_centro: float = 0.18
@export var aberracao: float = 0.0030
@export var vinheta_forca: float = 0.55
@export var intensidade_scanlines: float = 0.06

# ---------- LEDS ARDUINO / RGB ----------
@export var usar_leds: bool = true
@export var porta_leds: String = "COM5"
@export var baud_leds: int = 9600
@export var caminho_fila_leds: String = "user://basket_led_cmd.txt"


# ---------- ÁUDIO ----------
@export var caminho_musica_abertura: String = "res://songs/opening.mp3"
@export var volume_musica_abertura_db: float = -8.0
@export var caminho_som_selecionado: String = "res://songs/selected.mp3"
@export var volume_som_selecionado_db: float = 0.0


# ---------- NÓS ----------
var fundo: TextureRect = null
var brasas: CPUParticles2D = null
var faiscas: CPUParticles2D = null
var poeira: CPUParticles2D = null
var ui: CanvasLayer = null
var vinheta: TextureRect = null
var scanlines: ColorRect = null
var lbl_start: Label = null
var fade: ColorRect = null

var modal_jogadores: ColorRect = null
var modal_box: Panel = null
var modal_glow: Panel = null
var lbl_modal_titulo: Label = null
var lbl_modal_opcao: Label = null
var lbl_modal_subtitulo: Label = null
var lbl_modal_status: Label = null
var modal_linha_topo: Panel = null
var modal_linha_base: Panel = null
var modal_timer_box: Panel = null
var modal_timer_bar_bg: Panel = null
var modal_timer_bar: Panel = null
var _timer_bar_style: StyleBoxFlat = null
var lbl_modal_timer: Label = null
var modal_cmd_start_box: Panel = null
var lbl_comando_start: Label = null
var lbl_acao_start: Label = null
var modal_cards: Array = []
var modal_card_nums: Array = []
var modal_card_nomes: Array = []
var modal_leds: Array = []
var _led_estilos: Array = []

# Efeito LED arredondado — substitui o "hover" antigo, que ficava com
# cantos pontudos porque o corner_detail era baixo demais para o
# tamanho da sombra/borda. Um glow atrás do número de jogadores e
# outro atrás do card selecionado, ambos verdadeiramente arredondados
# (pill), com corner_detail alto o bastante pra sombra grande não
# virar polígono facetado.
var modal_opcao_glow: Panel = null
var _opcao_glow_style: StyleBoxFlat = null
var card_glow: Panel = null
var _card_glow_style: StyleBoxFlat = null
var _tween_pulso_card_glow: Tween = null

# ---------- ESTADO ----------
var _avancando: bool = false
var _modal_aberto: bool = false
var _coletando: bool = false
var _confirmando: bool = false
var _qtd: int = 1
var modo_credito: bool = false
var _deadline_ms: int = 0
var _hard_deadline_ms: int = 0
var _ultimo_registro_start_ms: int = -999999   # debounce: bloqueia START repetido chegando rápido demais

# Tweens de feedback do modal — guardados para poder matar a versão
# anterior antes de criar uma nova. Sem isso, dois STARTs muito
# próximos empilhavam tweens de escala no mesmo card/LED/label,
# causando aquele "rasgo" visual de duas animações brigando.
var _tween_pulso_card: Tween = null
var _tween_pulso_opcao: Tween = null
var _tween_flash_led: Tween = null

# ---------- LEDS (runtime) ----------
var _ponte_leds_pid: int = -1
var _ponte_leds_ps: String = "user://swish_opening_bridge.ps1"
var _mudando_para_cena: bool = false
var _fechando_programa: bool = false


var _config_overlay_ativo: Control = null

var musica_abertura: AudioStreamPlayer = null
var som_selecionado: AudioStreamPlayer = null





# ---------- PONTE POWERSHELL (escrita em código) ----------
# Lê o arquivo de comando, manda a 1ª palavra pra serial e apaga o arquivo.
# DtrEnable=$false evita reset do Arduino ao abrir a porta.
const _PS_BRIDGE_OPENING_CMD := """
param(
	[string]$Porta = "COM5",
	[int]$Baud = 9600,
	[string]$Arquivo = ""
)

$ErrorActionPreference = "SilentlyContinue"

try {
	$sp = New-Object System.IO.Ports.SerialPort($Porta, $Baud, "None", 8, "One")
	$sp.DtrEnable = $false
	$sp.RtsEnable = $false
	$sp.NewLine = "`n"
	$sp.WriteTimeout = 80
	$sp.Open()
} catch {
	exit 1
}

while ($true) {
	try {
		if (Test-Path -LiteralPath $Arquivo) {
			$cmd = [System.IO.File]::ReadAllText($Arquivo).Trim()
			[System.IO.File]::Delete($Arquivo)

			if ($cmd.Length -gt 0) {
				$partes = $cmd.Split(":")
				$limpo = $partes[0].Trim()
				$sp.WriteLine($limpo)
			}
		}
	} catch {}

	Start-Sleep -Milliseconds 8
}
"""


const _SHADER_FUNDO := """
shader_type canvas_item;

uniform float zoom_resp = 0.012;
uniform float aberracao = 0.0030;
uniform float brilho_centro = 0.18;
uniform float vinheta_forca = 0.55;
uniform float grao = 0.015;
uniform vec4 cor_quente : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform vec4 cor_fria : source_color = vec4(0.45, 0.22, 1.0, 1.0);

float hash(vec2 p){ return fract(sin(dot(p, vec2(41.0, 289.0))) * 43758.5453); }

void fragment(){
	vec2 centro = vec2(0.5);

	float z = 1.0 + sin(TIME * 0.6) * zoom_resp;
	vec2 uv = centro + (UV - centro) / z;

	float d = distance(uv, centro);
	vec2 dir = normalize(uv - centro + vec2(0.0001));

	float ab = aberracao * d * 2.0;
	float r = texture(TEXTURE, uv - dir * ab).r;
	vec4 base = texture(TEXTURE, uv);
	float b = texture(TEXTURE, uv + dir * ab).b;
	vec3 col = vec3(r, base.g, b);

	float pulso = 0.5 + 0.5 * sin(TIME * 1.4);
	float glow = smoothstep(0.62, 0.0, d);
	col += cor_quente.rgb * glow * brilho_centro * (0.6 + 0.4 * pulso);

	float sweep = sin((uv.x + uv.y) * 3.0 - TIME * 1.1 * 6.2831853);
	sweep = smoothstep(0.96, 1.0, sweep);
	col += sweep * 0.10;

	float borda = smoothstep(0.35, 1.0, d);
	col += cor_fria.rgb * borda * 0.05;

	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float bloom = smoothstep(0.60, 1.0, lum);
	col += col * bloom * 0.40;

	float vin = smoothstep(1.05, 0.25, d);
	col *= mix(1.0 - vinheta_forca, 1.0, vin);

	float n = hash(uv * vec2(440.0, 760.0) + TIME * 0.6);
	col += (n - 0.5) * grao;

	COLOR = vec4(col, base.a);
}
"""

const _SHADER_SCANLINES := """
shader_type canvas_item;

uniform float intensidade : hint_range(0.0, 0.5) = 0.06;
uniform float espessura = 3.0;

void fragment(){
	float s = sin(FRAGCOORD.y / espessura * 3.14159265);
	float linha = smoothstep(-1.0, 1.0, s);
	COLOR = vec4(0.0, 0.0, 0.0, (1.0 - linha) * intensidade);
}
"""


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_carregar_modo_operacao()

	# Não deixa o Windows fechar direto sem antes apagar os LEDs.
	get_tree().auto_accept_quit = false

	_montar_fundo()
	_montar_particulas()
	_montar_ui()
	_preparar_som_selecionado()
	_iniciar_musica_abertura()

	# Abre a ponte serial e liga o efeito de atração.
	# Abre a ponte serial e agenda o efeito de atração.
	_iniciar_ponte_leds()
	_acender_leds_abertura()

	if not get_viewport().size_changed.is_connected(_ajustar):
		get_viewport().size_changed.connect(_ajustar)

	await get_tree().process_frame
	_ajustar()
	_animar_entrada()
	_animar_start()
	_pulsar_vinheta()


func _process(_delta: float) -> void:
	# Único ponto de verdade do cronômetro: sem timers soltos / corrida.
	if _coletando and not _avancando and not _confirmando:
		_atualizar_barra_tempo_players()
		if Time.get_ticks_msec() >= _deadline_ms:
			_confirmar_modal_jogadores()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_MOUSE_ENTER:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_fechar_programa_seguro()


func _exit_tree() -> void:
	# Sempre garante LEDs apagados e porta COM fechada ao sair desta tela.
	# Isso evita a fita ficar acesa ou a COM presa para a próxima cena.
	_fechar_ponte_leds(true)


func _carregar_modo_operacao() -> void:
	modo_credito = false

	var cfg := ConfigFile.new()
	var err: int = cfg.load(caminho_config_basket)
	if err != OK:
		texto_start = texto_start_livre
		return

	modo_credito = bool(cfg.get_value("jogo", "modo_credito", false))
	var modo_txt: String = str(cfg.get_value("jogo", "modo_operacao", "livre")).to_lower()
	if modo_txt == "credito" or modo_txt == "crédito":
		modo_credito = true

	texto_start = _texto_chamada_principal()


func _texto_chamada_principal() -> String:
	return texto_start_credito if modo_credito else texto_start_livre


func _texto_subtitulo_modal_atual() -> String:
	return "CADA COIN ADICIONA 1 JOGADOR" if modo_credito else "CADA START ADICIONA 1 JOGADOR"


func _fechar_programa_seguro() -> void:
	if _fechando_programa:
		return
	_fechando_programa = true
	_fechar_ponte_leds(true)
	get_tree().quit()


# =====================================================================
# FUNDO + SHADER
# =====================================================================
func _montar_fundo() -> void:
	fundo = TextureRect.new()
	fundo.name = "Fundo"
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fundo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fundo)

	if caminho_fundo != "" and ResourceLoader.exists(caminho_fundo):
		fundo.texture = load(caminho_fundo)
	else:
		push_warning("Abertura: imagem de fundo não encontrada em " + caminho_fundo)

	if usar_shader_fundo:
		var sh := Shader.new()
		sh.code = _SHADER_FUNDO
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("brilho_centro", brilho_centro)
		mat.set_shader_parameter("aberracao", aberracao)
		mat.set_shader_parameter("vinheta_forca", vinheta_forca)
		mat.set_shader_parameter("cor_quente", cor_quente)
		mat.set_shader_parameter("cor_fria", cor_fria)
		fundo.material = mat


# =====================================================================
# PARTÍCULAS
# =====================================================================
func _montar_particulas() -> void:
	if not usar_particulas:
		return

	brasas = CPUParticles2D.new()
	brasas.name = "Brasas"
	brasas.texture = _textura_particula(0.42)
	var mat_brasas := CanvasItemMaterial.new()
	mat_brasas.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	brasas.material = mat_brasas
	add_child(brasas)

	faiscas = CPUParticles2D.new()
	faiscas.name = "Faiscas"
	faiscas.texture = _textura_particula(0.30)
	var mat_faiscas := CanvasItemMaterial.new()
	mat_faiscas.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	faiscas.material = mat_faiscas
	add_child(faiscas)

	poeira = CPUParticles2D.new()
	poeira.name = "Poeira"
	poeira.texture = _textura_particula(0.60)
	# Poeira fica em blend normal (não aditivo) — é atmosfera de
	# fundo, não brilho; aditivo deixaria ela "estourando" de branco.
	add_child(poeira)



func _config_particulas() -> void:
	if not usar_particulas:
		return

	var tela: Vector2 = get_viewport_rect().size

	if brasas != null:
		brasas.position = Vector2(tela.x * 0.5, tela.y + 10.0)
		brasas.amount = 70
		brasas.lifetime = 6.5
		brasas.preprocess = 3.0
		brasas.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		brasas.emission_rect_extents = Vector2(tela.x * 0.5, 6.0)
		brasas.direction = Vector2(0, -1)
		brasas.spread = 22.0
		brasas.gravity = Vector2.ZERO
		brasas.initial_velocity_min = 26.0
		brasas.initial_velocity_max = 95.0
		brasas.angular_velocity_min = -30.0
		brasas.angular_velocity_max = 30.0
		# Escala calibrada para a textura de 64px (0.10 ≈ 6px, 0.46 ≈ 29px)
		# — dá uma mistura de brasas pequenas e orbes maiores e suaves.
		brasas.scale_amount_min = 0.10
		brasas.scale_amount_max = 0.46
		brasas.color_ramp = _ramp_brasa()
		brasas.emitting = true

	if faiscas != null:
		faiscas.position = Vector2(tela.x * 0.5, tela.y * 0.5)
		faiscas.amount = 34
		faiscas.lifetime = 2.2
		faiscas.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		faiscas.emission_sphere_radius = tela.y * 0.22
		faiscas.direction = Vector2(0, -1)
		faiscas.spread = 180.0
		faiscas.gravity = Vector2(0, -10)
		faiscas.initial_velocity_min = 10.0
		faiscas.initial_velocity_max = 60.0
		faiscas.angular_velocity_min = -60.0
		faiscas.angular_velocity_max = 60.0
		# Fagulhas ficam bem menores que as brasas (0.06 ≈ 4px, 0.20 ≈ 13px).
		faiscas.scale_amount_min = 0.06
		faiscas.scale_amount_max = 0.20
		faiscas.color_ramp = _ramp_faisca()
		faiscas.emitting = true

	if poeira != null:
		poeira.position = Vector2(tela.x * 0.5, tela.y * 0.5)
		poeira.amount = 46
		poeira.lifetime = 9.0
		poeira.preprocess = 5.0
		poeira.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		poeira.emission_rect_extents = Vector2(tela.x * 0.5, tela.y * 0.5)
		poeira.direction = Vector2(0, -1)
		poeira.spread = 40.0
		poeira.gravity = Vector2.ZERO
		poeira.initial_velocity_min = 4.0
		poeira.initial_velocity_max = 16.0
		# Poeira em orbes grandes e bem translúcidos (0.35 ≈ 22px, 1.05 ≈ 67px).
		poeira.scale_amount_min = 0.35
		poeira.scale_amount_max = 1.05
		poeira.color_ramp = _ramp_poeira()
		poeira.emitting = true



func _ramp_brasa() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	g.colors = PackedColorArray([
		Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.0),
		Color(1.0, 0.85, 0.5, 0.95),
		Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.7),
		Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.0),
	])
	return g


func _ramp_faisca() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 0.92, 0.7, 0.95),
		Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.0),
	])
	return g


func _ramp_poeira() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([
		Color(cor_fria.r, cor_fria.g, cor_fria.b, 0.0),
		Color(cor_fria.r, cor_fria.g, cor_fria.b, 0.35),
		Color(cor_fria.r, cor_fria.g, cor_fria.b, 0.0),
	])
	return g


func _textura_particula(nucleo: float = 0.5) -> Texture2D:
	# Textura radial suave para as partículas — CPUParticles2D sem
	# textura desenha um "pontinho" quadrado bruto, sem antialiasing,
	# que é a causa do visual picotado/amador. Com essa textura, cada
	# partícula vira um orbe redondo com fade suave nas bordas.
	# 'nucleo' controla o quão concentrado é o brilho central antes
	# de começar a esmaecer (menor = núcleo mais compacto e intenso).
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, nucleo, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.55),
		Color(1, 1, 1, 0.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 64
	gt.height = 64
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	return gt


# =====================================================================
# UI (vinheta, scanlines, start, modal, fade)
# =====================================================================
func _montar_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 5
	add_child(ui)

	vinheta = TextureRect.new()
	vinheta.name = "Vinheta"
	vinheta.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vinheta.stretch_mode = TextureRect.STRETCH_SCALE
	vinheta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vinheta.texture = _criar_vinheta()
	ui.add_child(vinheta)

	if usar_scanlines:
		scanlines = ColorRect.new()
		scanlines.name = "Scanlines"
		scanlines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scanlines.color = Color.WHITE
		scanlines.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = _SHADER_SCANLINES
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("intensidade", intensidade_scanlines)
		scanlines.material = mat
		ui.add_child(scanlines)

	lbl_start = Label.new()
	lbl_start.name = "Start"
	lbl_start.text = _texto_chamada_principal()
	lbl_start.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	lbl_start.offset_top = -170
	lbl_start.offset_bottom = -90
	lbl_start.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_start.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_start.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_start.add_theme_color_override("font_color", Color.WHITE)
	lbl_start.add_theme_color_override("font_outline_color", cor_quente)
	lbl_start.add_theme_constant_override("outline_size", 10)
	_aplicar_fonte(lbl_start)
	ui.add_child(lbl_start)

	_montar_modal_jogadores()

	fade = ColorRect.new()
	fade.name = "Fade"
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 1)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fade)


func _montar_modal_jogadores() -> void:
	_qtd = int(clamp(jogadores_min, jogadores_min, jogadores_max))
	modal_cards.clear()
	modal_card_nums.clear()
	modal_card_nomes.clear()
	modal_leds.clear()
	_led_estilos.clear()

	modal_jogadores = ColorRect.new()
	modal_jogadores.name = "ModalJogadores"
	modal_jogadores.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_jogadores.color = Color(0.0, 0.0, 0.0, 0.74)
	modal_jogadores.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_jogadores.visible = false
	ui.add_child(modal_jogadores)

	# Glow externo arredondado (efeito LED em volta da box).
	modal_glow = Panel.new()
	modal_glow.name = "ModalGlow"
	modal_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_glow.add_theme_stylebox_override("panel", _style_modal_glow())
	modal_jogadores.add_child(modal_glow)

	modal_box = Panel.new()
	modal_box.name = "BoxArcadePlayers"
	modal_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_box.clip_contents = true
	modal_jogadores.add_child(modal_box)
	modal_box.add_theme_stylebox_override("panel", _style_modal_box())

	# Linha neon do topo (pill arredondado).
	modal_linha_topo = _novo_pill("LinhaNeonTopo", cor_quente, 0.85)
	modal_box.add_child(modal_linha_topo)

	lbl_modal_titulo = _criar_label_modal("Titulo", texto_modal_titulo, Color.WHITE, 8)
	modal_box.add_child(lbl_modal_titulo)

	lbl_modal_subtitulo = _criar_label_modal("Subtitulo", _texto_subtitulo_modal_atual(), Color(0.78, 0.86, 1.0, 0.96), 4)
	modal_box.add_child(lbl_modal_subtitulo)

	# Glow LED atrás do número de jogadores — adicionado ANTES do
	# label para ficar desenhado por baixo do texto.
	modal_opcao_glow = Panel.new()
	modal_opcao_glow.name = "OpcaoGlow"
	modal_opcao_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_opcao_glow_style = _style_opcao_glow()
	modal_opcao_glow.add_theme_stylebox_override("panel", _opcao_glow_style)
	modal_box.add_child(modal_opcao_glow)

	lbl_modal_opcao = _criar_label_modal("OpcaoAtual", "", cor_quente, 12)
	modal_box.add_child(lbl_modal_opcao)

	lbl_modal_status = _criar_label_modal("Status", "", Color.WHITE, 5)
	modal_box.add_child(lbl_modal_status)

	# Glow LED atrás do card selecionado — também adicionado ANTES dos
	# cards, para ficar por baixo e "vazar" ao redor deles.
	card_glow = Panel.new()
	card_glow.name = "CardGlow"
	card_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_glow_style = _style_card_glow()
	card_glow.add_theme_stylebox_override("panel", _card_glow_style)
	card_glow.visible = false
	modal_box.add_child(card_glow)

	for i in range(jogadores_min, jogadores_max + 1):
		var card := Panel.new()
		card.name = "CardPlayer" + str(i)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.clip_contents = true
		modal_box.add_child(card)
		modal_cards.append(card)

		var num := _criar_label_modal("Numero" + str(i), str(i), Color.WHITE, 6)
		card.add_child(num)
		modal_card_nums.append(num)

		var nome_txt: String = "PLAYER" if i == 1 else "PLAYERS"
		var nome := _criar_label_modal("Nome" + str(i), nome_txt, Color(0.74, 0.82, 1.0, 0.95), 3)
		card.add_child(nome)
		modal_card_nomes.append(nome)

	# LEDs do modal: pills arredondadas com glow (espelham a fita real).
	for i in range(4):
		var estilo := _style_led(false)
		_led_estilos.append(estilo)
		var led := Panel.new()
		led.name = "LedPlayer" + str(i + 1)
		led.mouse_filter = Control.MOUSE_FILTER_IGNORE
		led.add_theme_stylebox_override("panel", estilo)
		modal_box.add_child(led)
		modal_leds.append(led)

	# Linha neon da base (pill arredondado).
	modal_linha_base = _novo_pill("LinhaNeonBase", cor_fria, 0.80)
	modal_box.add_child(modal_linha_base)

	modal_cmd_start_box = Panel.new()
	modal_cmd_start_box.name = "BoxComandoStart"
	modal_cmd_start_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_cmd_start_box.add_theme_stylebox_override("panel", _style_comando(cor_quente))
	modal_box.add_child(modal_cmd_start_box)

	lbl_comando_start = _criar_label_modal("ComandoStart", _texto_chamada_principal(), cor_quente, 9)
	modal_box.add_child(lbl_comando_start)

	lbl_acao_start = _criar_label_modal("AcaoStart", texto_acao_start, Color.WHITE, 4)
	lbl_acao_start.visible = false
	modal_box.add_child(lbl_acao_start)

	modal_timer_box = Panel.new()
	modal_timer_box.name = "BoxTimerPlayers"
	modal_timer_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_timer_box.add_theme_stylebox_override("panel", _style_comando(cor_fria))
	modal_box.add_child(modal_timer_box)

	modal_timer_bar_bg = Panel.new()
	modal_timer_bar_bg.name = "TimerBarBg"
	modal_timer_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_timer_bar_bg.add_theme_stylebox_override("panel", _style_barra_tempo_bg())
	modal_box.add_child(modal_timer_bar_bg)

	# Barra de tempo agora é um Panel arredondado (pill), sem cantos retos.
	_timer_bar_style = StyleBoxFlat.new()
	_timer_bar_style.bg_color = cor_quente
	_timer_bar_style.set_corner_radius_all(8)
	_timer_bar_style.corner_detail = 16
	_timer_bar_style.shadow_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.45)
	_timer_bar_style.shadow_size = 8
	_timer_bar_style.anti_aliasing = true
	modal_timer_bar = Panel.new()
	modal_timer_bar.name = "TimerBar"
	modal_timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_timer_bar.add_theme_stylebox_override("panel", _timer_bar_style)
	modal_box.add_child(modal_timer_bar)
	
	

	lbl_modal_timer = _criar_label_modal("TimerTexto", "", Color.WHITE, 4)
	modal_box.add_child(lbl_modal_timer)

	_atualizar_texto_modal()


func _novo_pill(nome: String, cor: Color, alpha: float) -> Panel:
	var p := Panel.new()
	p.name = nome
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var e := StyleBoxFlat.new()
	e.bg_color = Color(cor.r, cor.g, cor.b, alpha)
	e.set_corner_radius_all(20)
	e.corner_detail = 18
	e.shadow_color = Color(cor.r, cor.g, cor.b, 0.55)
	e.shadow_size = 8
	e.anti_aliasing = true
	p.add_theme_stylebox_override("panel", e)
	return p


# =====================================================================
# ESTILOS DO MODAL (tudo arredondado)
# =====================================================================
func _style_modal_box() -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	e.bg_color = Color(0.010, 0.014, 0.030, 0.97)
	e.border_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.95)
	e.set_border_width_all(3)
	e.set_corner_radius_all(32)
	e.corner_detail = 14
	e.shadow_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.24)
	e.shadow_size = 30
	e.set_content_margin_all(22)
	e.anti_aliasing = true
	return e


func _style_modal_glow() -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	e.bg_color = Color(cor_quente.r * 0.05, cor_quente.g * 0.05, cor_quente.b * 0.05, 0.22)
	e.border_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.92)
	e.set_border_width_all(2)
	e.set_corner_radius_all(40)
	e.corner_detail = 22
	e.shadow_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.85)
	e.shadow_size = 52
	e.anti_aliasing = true
	return e


func _style_card(selecionado: bool) -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	if selecionado:
		e.bg_color = Color(0.13, 0.06, 0.012, 0.98)
		e.border_color = Color.WHITE
		e.set_border_width_all(2)
		e.shadow_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.40)
		e.shadow_size = 14
	else:
		e.bg_color = Color(0.022, 0.030, 0.064, 0.82)
		e.border_color = Color(cor_fria.r, cor_fria.g, cor_fria.b, 0.34)
		e.set_border_width_all(2)
		e.shadow_color = Color(0, 0, 0, 0.34)
		e.shadow_size = 6
	e.set_corner_radius_all(18)
	e.corner_detail = 20
	e.anti_aliasing = true
	return e



func _style_comando(cor: Color) -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	e.bg_color = Color(cor.r * 0.08, cor.g * 0.08, cor.b * 0.08, 0.88)
	e.border_color = Color(cor.r, cor.g, cor.b, 0.78)
	e.set_border_width_all(2)
	e.set_corner_radius_all(18)
	e.corner_detail = 16
	e.shadow_color = Color(cor.r, cor.g, cor.b, 0.24)
	e.shadow_size = 14
	e.anti_aliasing = true
	return e



func _style_barra_tempo_bg() -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	e.bg_color = Color(0.015, 0.018, 0.040, 0.90)
	e.border_color = Color(cor_fria.r, cor_fria.g, cor_fria.b, 0.48)
	e.set_border_width_all(2)
	e.set_corner_radius_all(14)
	e.corner_detail = 14
	e.shadow_color = Color(cor_fria.r, cor_fria.g, cor_fria.b, 0.16)
	e.shadow_size = 10
	e.anti_aliasing = true
	return e


func _style_led(aceso: bool) -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	if aceso:
		e.bg_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.98)
		e.border_color = Color(1.0, 0.92, 0.72, 0.95)
		e.set_border_width_all(2)
		e.shadow_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.85)
		e.shadow_size = 18
	else:
		e.bg_color = Color(cor_fria.r * 0.30, cor_fria.g * 0.30, cor_fria.b * 0.40, 0.55)
		e.border_color = Color(cor_fria.r, cor_fria.g, cor_fria.b, 0.42)
		e.set_border_width_all(2)
		e.shadow_color = Color(cor_fria.r, cor_fria.g, cor_fria.b, 0.18)
		e.shadow_size = 6
	e.set_corner_radius_all(40)   # pill totalmente arredondada
	e.corner_detail = 16
	e.anti_aliasing = true
	return e



func _style_opcao_glow() -> StyleBoxFlat:
	# Pill de LED atrás do número de jogadores. corner_radius é
	# recalculado em tempo real em _ajustar() para casar com a altura
	# exata da caixa — isso é o que garante o formato pill perfeito,
	# sem depender de um valor fixo que pode ficar "quase redondo".
	var e := StyleBoxFlat.new()
	e.bg_color = Color(cor_quente.r * 0.14, cor_quente.g * 0.14, cor_quente.b * 0.14, 0.50)
	e.border_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.80)
	e.set_border_width_all(2)
	e.set_corner_radius_all(40)
	e.corner_detail = 20
	e.shadow_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.55)
	e.shadow_size = 20
	e.anti_aliasing = true
	return e


func _style_card_glow() -> StyleBoxFlat:
	# Glow arredondado que "abraça" o card selecionado por fora,
	# maior que o card em si — é isso que dá a sensação de LED
	# iluminando ao redor, em vez do contorno reto do card sozinho.
	var e := StyleBoxFlat.new()
	e.bg_color = Color(cor_quente.r * 0.10, cor_quente.g * 0.10, cor_quente.b * 0.10, 0.26)
	e.border_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.55)
	e.set_border_width_all(2)
	e.set_corner_radius_all(26)
	e.corner_detail = 22
	e.shadow_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.60)
	e.shadow_size = 26
	e.anti_aliasing = true
	return e


func _criar_label_modal(nome: String, texto: String, cor: Color, outline: int) -> Label:
	var lbl := Label.new()
	lbl.name = nome
	lbl.text = texto
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_color", cor)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.88))
	lbl.add_theme_constant_override("outline_size", outline)
	_aplicar_fonte(lbl)
	return lbl


# =====================================================================
# ABERTURA / FLUXO DO MODAL
# =====================================================================
func _registrar_start_player() -> void:
	if _avancando or _confirmando:
		return

	# Debounce: ignora START chegando rápido demais desde o último
	# registrado com sucesso. Protege contra bounce do botão físico
	# (Zero Delay) e contra a mesma ação de input disparando duas vezes
	# no mesmo frame (ex: tecla + botão mapeados na mesma ação).
	var agora_ms: int = Time.get_ticks_msec()
	if agora_ms - _ultimo_registro_start_ms < debounce_start_ms:
		return
	_ultimo_registro_start_ms = agora_ms

	_tocar_som_selecionado()

	var agora: int = agora_ms
	var primeira: bool = not _coletando

	if primeira:
		_coletando = true
		_modal_aberto = true
		_qtd = jogadores_min
		_hard_deadline_ms = agora + int(tempo_maximo_modal * 1000.0)
		_deadline_ms = min(agora + int(tempo_para_confirmar * 1000.0), _hard_deadline_ms)
		_enviar_led("MENU_LOCK")
		_abrir_modal_jogadores()
	else:
		if _qtd < jogadores_max:
			_qtd += 1
		_deadline_ms = min(agora + int(tempo_para_confirmar * 1000.0), _hard_deadline_ms)

	_atualizar_texto_modal()
	_atualizar_barra_tempo_players()
	_led_mudou_opcao(_qtd)

	if not primeira:
		_pulsar_card_selecionado()

	if _qtd >= jogadores_max:
		_deadline_ms = agora + int(atraso_entrada_apos_max * 1000.0)



func _abrir_modal_jogadores() -> void:
	if modal_jogadores == null:
		return

	if lbl_start != null:
		lbl_start.visible = false

	modal_jogadores.visible = true
	modal_jogadores.modulate.a = 0.0

	if modal_box != null:
		modal_box.pivot_offset = modal_box.size * 0.5
		modal_box.scale = Vector2(0.90, 0.90)

	var t := create_tween().set_parallel(true)
	t.tween_property(modal_jogadores, "modulate:a", 1.0, 0.16)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if modal_box != null:
		t.tween_property(modal_box, "scale", Vector2.ONE, 0.22)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_pulsar_glow_modal()
	_pulsar_opcao_glow()
	_pulsar_card_glow_loop()
	_atualizar_card_glow()

	for i in range(modal_cards.size()):	
		var card: Panel = modal_cards[i] as Panel
		card.pivot_offset = card.size * 0.5
		card.modulate.a = 0.0
		card.scale = Vector2(0.70, 0.70)
		var atraso: float = 0.10 + float(i) * 0.05
		var tc := create_tween().set_parallel(true)
		tc.tween_property(card, "modulate:a", 1.0, 0.18).set_delay(atraso)
		tc.tween_property(card, "scale", Vector2.ONE, 0.26).set_delay(atraso)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pulsar_glow_modal() -> void:
	if modal_glow == null:
		return
	modal_glow.modulate.a = 0.60
	var t := create_tween().set_loops()
	t.tween_property(modal_glow, "modulate:a", 1.0, 0.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(modal_glow, "modulate:a", 0.58, 0.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)



func _atualizar_card_glow() -> void:
	# Posiciona o glow LED ao redor do card atualmente selecionado —
	# maior que o card, com cantos bem arredondados. É isso que
	# substitui o antigo "hover pontudo": em vez do card sozinho
	# tentar fazer sombra grande com pouco corner_detail, agora existe
	# um painel dedicado, maior e com detail alto o bastante.
	if card_glow == null or modal_cards.is_empty():
		return

	var idx: int = _qtd - jogadores_min
	if idx < 0 or idx >= modal_cards.size():
		card_glow.visible = false
		return

	var card: Panel = modal_cards[idx] as Panel
	if card.size.x <= 0.0 or card.size.y <= 0.0:
		return

	var pad: float = max(10.0, card.size.x * 0.10)
	card_glow.position = card.position - Vector2(pad, pad)
	card_glow.size = card.size + Vector2(pad, pad) * 2.0
	card_glow.pivot_offset = card_glow.size * 0.5

	if _card_glow_style != null:
		_card_glow_style.set_corner_radius_all(int(min(card_glow.size.x, card_glow.size.y) * 0.22))

	card_glow.visible = true


func _pulsar_opcao_glow() -> void:
	if modal_opcao_glow == null:
		return
	modal_opcao_glow.modulate.a = 0.65
	var t := create_tween().set_loops()
	t.tween_property(modal_opcao_glow, "modulate:a", 1.0, 0.55)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(modal_opcao_glow, "modulate:a", 0.62, 0.55)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _pulsar_card_glow_loop() -> void:
	if card_glow == null:
		return
	card_glow.modulate.a = 0.70
	var t := create_tween().set_loops()
	t.tween_property(card_glow, "modulate:a", 1.0, 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(card_glow, "modulate:a", 0.68, 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)



func _confirmar_modal_jogadores() -> void:
	if _avancando or _confirmando:
		return

	_confirmando = true
	_coletando = false

	# Mata qualquer tween de pulso ainda rodando do último START — evita
	# que a animação de confirmação (_animar_confirmacao) comece por
	# cima de uma escala que ainda estava em trânsito.
	for tw in [_tween_pulso_card, _tween_pulso_opcao, _tween_flash_led]:
		if tw != null:
			tw.kill()
	_tween_pulso_card = null
	_tween_pulso_opcao = null
	_tween_flash_led = null
	_qtd = clampi(_qtd, jogadores_min, jogadores_max)
	_led_confirmou_opcao(_qtd)
	get_tree().set_meta(meta_num_jogadores, _qtd)

	await _animar_confirmacao()
	_avancar()


func _animar_confirmacao() -> void:
	if lbl_modal_status != null:
		lbl_modal_status.text = "VAMOS JOGAR!"
		lbl_modal_status.add_theme_color_override("font_color", cor_quente)

	if lbl_modal_subtitulo != null:
		lbl_modal_subtitulo.text = ("ENTRANDO COM 1 PLAYER" if _qtd == 1 else "ENTRANDO COM %d PLAYERS" % _qtd)

	if lbl_comando_start != null:
		lbl_comando_start.text = "CONFIRMADO"

	var idx: int = _qtd - jogadores_min

	for i in range(modal_cards.size()):
		var card: Panel = modal_cards[i] as Panel
		card.pivot_offset = card.size * 0.5
		var t := create_tween().set_parallel(true)
		if i == idx:
			t.tween_property(card, "scale", Vector2(1.16, 1.16), 0.22)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			t.tween_property(card, "modulate:a", 0.0, 0.20)
			t.tween_property(card, "scale", Vector2(0.90, 0.90), 0.20)

	if modal_box != null:
		modal_box.pivot_offset = modal_box.size * 0.5
		var tb := create_tween()
		tb.tween_property(modal_box, "scale", Vector2(1.03, 1.03), 0.12)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tb.tween_property(modal_box, "scale", Vector2.ONE, 0.16)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(0.55).timeout


func _atualizar_texto_modal() -> void:
	if lbl_modal_opcao != null:
		lbl_modal_opcao.text = ("1 PLAYER" if _qtd == 1 else "%d PLAYERS" % _qtd)

	if lbl_modal_subtitulo != null and not _confirmando:
		lbl_modal_subtitulo.text = _texto_subtitulo_modal_atual()

	if lbl_comando_start != null and not _confirmando:
		lbl_comando_start.text = _texto_chamada_principal()

	# Remove texto redundante no miolo do modal: a quantidade já aparece
	# grande no centro, os cards mostram a escolha e o cronômetro mostra
	# quando confirma.
	if lbl_modal_status != null and not _confirmando:
		lbl_modal_status.text = ""

	for i in range(modal_cards.size()):
		var qtd_card: int = jogadores_min + i
		var selecionado: bool = qtd_card == _qtd
		var card: Panel = modal_cards[i] as Panel
		card.add_theme_stylebox_override("panel", _style_card(selecionado))

		var num: Label = modal_card_nums[i] as Label
		var nome: Label = modal_card_nomes[i] as Label
		num.add_theme_color_override("font_color", cor_quente if selecionado else Color(0.80, 0.86, 1.0, 0.92))
		num.add_theme_constant_override("outline_size", 8 if selecionado else 5)
		nome.add_theme_color_override("font_color", Color.WHITE if selecionado else Color(0.62, 0.70, 0.90, 0.72))

	# LEDs arredondados: muda o próprio estilo (sem recriar nó).
	for i in range(_led_estilos.size()):
		var aceso: bool = i < _qtd
		var e: StyleBoxFlat = _led_estilos[i] as StyleBoxFlat
		if aceso:
			e.bg_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.98)
			e.border_color = Color(1.0, 0.92, 0.72, 0.95)
			e.shadow_color = Color(cor_quente.r, cor_quente.g, cor_quente.b, 0.85)
			e.shadow_size = 18
		else:
			e.bg_color = Color(cor_fria.r * 0.30, cor_fria.g * 0.30, cor_fria.b * 0.40, 0.55)
			e.border_color = Color(cor_fria.r, cor_fria.g, cor_fria.b, 0.42)
			e.shadow_color = Color(cor_fria.r, cor_fria.g, cor_fria.b, 0.18)
			e.shadow_size = 6

	_atualizar_card_glow()


func _bolinhas_status(qtd: int) -> String:
	var txt: String = ""
	for i in range(jogadores_max):
		txt += "●" if i < qtd else "○"
		if i < jogadores_max - 1:
			txt += " "
	return txt



func _pulsar_card_selecionado() -> void:
	var idx: int = _qtd - jogadores_min
	if idx < 0 or idx >= modal_cards.size():
		return

	var card: Panel = modal_cards[idx] as Panel
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(1.14, 1.14)

	if _tween_pulso_card != null:
		_tween_pulso_card.kill()
	_tween_pulso_card = create_tween()
	_tween_pulso_card.tween_property(card, "scale", Vector2.ONE, 0.16)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_atualizar_card_glow()
	if card_glow != null:
		card_glow.modulate = Color(1, 1, 1, 1)
		if _tween_pulso_card_glow != null:
			_tween_pulso_card_glow.kill()
		_tween_pulso_card_glow = create_tween()
		_tween_pulso_card_glow.tween_property(card_glow, "modulate", Color(1.6, 1.6, 1.6, 1), 0.07)
		_tween_pulso_card_glow.tween_property(card_glow, "modulate", Color(1, 1, 1, 1), 0.20)

	# Flash no LED recém-aceso (pill).
	if idx < modal_leds.size():
		var led: Panel = modal_leds[idx] as Panel
		led.modulate = Color(1, 1, 1, 1)

		if _tween_flash_led != null:
			_tween_flash_led.kill()
		_tween_flash_led = create_tween()
		_tween_flash_led.tween_property(led, "modulate", Color(2, 2, 2, 1), 0.06)
		_tween_flash_led.tween_property(led, "modulate", Color(1, 1, 1, 1), 0.18)

	if lbl_modal_opcao != null:
		lbl_modal_opcao.pivot_offset = lbl_modal_opcao.size * 0.5
		lbl_modal_opcao.scale = Vector2(1.08, 1.08)

		if _tween_pulso_opcao != null:
			_tween_pulso_opcao.kill()
		_tween_pulso_opcao = create_tween()
		_tween_pulso_opcao.tween_property(lbl_modal_opcao, "scale", Vector2.ONE, 0.14)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)



# =====================================================================
# LEDS ARDUINO — PONTE POWERSHELL + COMANDOS
# =====================================================================
func _iniciar_ponte_leds() -> void:
	if not usar_leds:
		return
	if OS.get_name() != "Windows":
		return
	if _ponte_leds_pid > 0:
		return

	var cmd_abs := ProjectSettings.globalize_path(caminho_fila_leds)

	# Limpa comando velho.
	if FileAccess.file_exists(caminho_fila_leds):
		DirAccess.remove_absolute(cmd_abs)

	var f := FileAccess.open(_ponte_leds_ps, FileAccess.WRITE)
	if f:
		f.store_string(_PS_BRIDGE_OPENING_CMD)
		f.close()

	var ps_abs := ProjectSettings.globalize_path(_ponte_leds_ps)
	var args := [
		"-ExecutionPolicy", "Bypass",
		"-NoProfile",
		"-WindowStyle", "Hidden",
		"-File", ps_abs,
		"-Porta", porta_leds,
		"-Baud", str(baud_leds),
		"-Arquivo", cmd_abs
	]
	_ponte_leds_pid = OS.create_process("powershell.exe", args)

	# Dá tempo da COM abrir antes do primeiro comando.
	OS.delay_msec(500)


func _acender_leds_abertura() -> void:
	if not usar_leds:
		return

	# Dá tempo real para o PowerShell abrir a COM e para o Arduino acordar.
	await get_tree().create_timer(0.90).timeout

	if _avancando or _confirmando or _fechando_programa or _mudando_para_cena:
		return

	_enviar_led("ATTRACT")

	# Reforço: alguns Arduinos perdem o primeiro comando logo após abrir a Serial.
	await get_tree().create_timer(0.30).timeout

	if _avancando or _confirmando or _fechando_programa or _mudando_para_cena:
		return

	_enviar_led("ATTRACT")


func _enviar_led(cmd: String) -> void:
	if not usar_leds:
		return
	var f := FileAccess.open(caminho_fila_leds, FileAccess.WRITE)
	if f == null:
		push_warning("Abertura LEDs: não consegui escrever comando " + cmd)
		return
	# O número no final garante que SELECT repetido seja sempre comando novo.
	var linha := "%s:%d" % [cmd, Time.get_ticks_msec()]
	f.store_line(linha)
	f.close()
	print("LED OPENING CMD -> ", linha)


func _fechar_ponte_leds(apagar: bool = false) -> void:
	if apagar and usar_leds:
		_enviar_led("OFF")
		# Tempo para a ponte ler o arquivo, mandar OFF e liberar os LEDs.
		OS.delay_msec(220)

	if _ponte_leds_pid > 0:
		OS.kill(_ponte_leds_pid)
		_ponte_leds_pid = -1
		# Pequena folga para o Windows liberar a porta COM.
		OS.delay_msec(140)

	# Limpa comando pendente para a próxima tela não herdar comando antigo.
	var cmd_abs := ProjectSettings.globalize_path(caminho_fila_leds)
	if FileAccess.file_exists(caminho_fila_leds):
		DirAccess.remove_absolute(cmd_abs)


func _led_mudou_opcao(qtd: int) -> void:
	# 1 player: trava aceso. 2..4: ondas conforme a quantidade.
	_enviar_led("SELECT%d" % clampi(qtd, 1, 4))


func _led_confirmou_opcao(_qtd_val: int) -> void:
	# Efeito de "entrando no jogo".
	_enviar_led("STARTING")


# =====================================================================
# ÁUDIO — MÚSICA DE FUNDO E SOM DE SELEÇÃO
# =====================================================================
func _iniciar_musica_abertura() -> void:
	if musica_abertura == null:
		musica_abertura = AudioStreamPlayer.new()
		musica_abertura.name = "MusicaAbertura"
		add_child(musica_abertura)

	var s := load(caminho_musica_abertura) as AudioStream
	if s == null:
		push_warning("Abertura: música não encontrada em " + caminho_musica_abertura)
		return

	if s is AudioStreamMP3:
		s.loop = true
	elif s is AudioStreamOggVorbis:
		s.loop = true

	musica_abertura.stream = s
	musica_abertura.volume_db = volume_musica_abertura_db
	musica_abertura.play()


func _preparar_som_selecionado() -> void:
	if som_selecionado == null:
		som_selecionado = AudioStreamPlayer.new()
		som_selecionado.name = "SomSelecionado"
		add_child(som_selecionado)

	var s := load(caminho_som_selecionado) as AudioStream
	if s == null:
		push_warning("Abertura: som não encontrado em " + caminho_som_selecionado)
		return

	som_selecionado.stream = s
	som_selecionado.volume_db = volume_som_selecionado_db


func _tocar_som_selecionado() -> void:
	if som_selecionado == null or som_selecionado.stream == null:
		return
	som_selecionado.stop()
	som_selecionado.play()


func _criar_vinheta() -> Texture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.45, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.62)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 512
	gt.height = 512
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	return gt


func _aplicar_fonte(no: Control) -> void:
	if caminho_fonte == "" or not ResourceLoader.exists(caminho_fonte):
		return
	var f := load(caminho_fonte)
	if f is Font:
		no.add_theme_font_override("font", f)


# =====================================================================
# LAYOUT RESPONSIVO
# =====================================================================
func _fs(frac: float) -> int:
	return max(12, int(get_viewport_rect().size.y * frac))


func _ajustar() -> void:
	var tela: Vector2 = get_viewport_rect().size

	if fundo != null:
		fundo.position = Vector2.ZERO
		fundo.size = tela

	if vinheta != null:
		vinheta.position = Vector2.ZERO
		vinheta.size = tela

	if scanlines != null:
		scanlines.position = Vector2.ZERO
		scanlines.size = tela

	if modal_jogadores != null:
		modal_jogadores.position = Vector2.ZERO
		modal_jogadores.size = tela

	if modal_box != null:
		# Modal mais amplo e limpo: menos texto miúdo, áreas maiores para
		# quantidade, cards, chamada principal e cronômetro.
		var box_w: float = clamp(tela.x * 0.70, 860.0, 1240.0)
		var box_h: float = clamp(tela.y * 0.72, 640.0, 840.0)
		modal_box.size = Vector2(box_w, box_h)
		modal_box.position = (tela - modal_box.size) * 0.5
		modal_box.pivot_offset = modal_box.size * 0.5

		if modal_glow != null:
			modal_glow.size = modal_box.size + Vector2(20, 20)
			modal_glow.position = modal_box.position - Vector2(10, 10)

		var margem: float = max(60.0, modal_box.size.x * 0.068)
		var y: float = modal_box.size.y
		var w: float = modal_box.size.x

		if modal_linha_topo != null:
			modal_linha_topo.position = Vector2(margem + w * 0.10, 20.0)
			modal_linha_topo.size = Vector2(w - margem * 2.0 - w * 0.20, 5.0)

		if lbl_modal_titulo != null:
			lbl_modal_titulo.position = Vector2(margem, y * 0.038)
			lbl_modal_titulo.size = Vector2(w - margem * 2.0, y * 0.090)
			lbl_modal_titulo.add_theme_font_size_override("font_size", _fs(0.046))

		if lbl_modal_subtitulo != null:
			lbl_modal_subtitulo.position = Vector2(margem, y * 0.128)
			lbl_modal_subtitulo.size = Vector2(w - margem * 2.0, y * 0.052)
			lbl_modal_subtitulo.add_theme_font_size_override("font_size", _fs(0.024))

		# Texto dinâmico "X PLAYERS" — área quase dobrada em altura
		# (era y*0.128, agora y*0.150) para caber confortavelmente
		# com fonte maior, sem cortar.
		if lbl_modal_opcao != null:
			lbl_modal_opcao.position = Vector2(margem, y * 0.190)
			lbl_modal_opcao.size = Vector2(w - margem * 2.0, y * 0.140)
			lbl_modal_opcao.pivot_offset = lbl_modal_opcao.size * 0.5
			lbl_modal_opcao.add_theme_font_size_override("font_size", _fs(0.078))

		# Pill LED atrás do número de jogadores — corner_radius
		# recalculado sempre pela altura real da caixa, garantindo
		# formato pill perfeito em qualquer resolução.
		if modal_opcao_glow != null:
			var op_h: float = (y * 0.140) * 0.76
			var op_w: float = clampf(w * 0.48, 260.0, w - margem * 2.0)
			var op_x: float = (w - op_w) * 0.5
			var op_y: float = y * 0.190 + (y * 0.140 - op_h) * 0.5
			modal_opcao_glow.position = Vector2(op_x, op_y)
			modal_opcao_glow.size = Vector2(op_w, op_h)
			modal_opcao_glow.pivot_offset = modal_opcao_glow.size * 0.5
			if _opcao_glow_style != null:
				_opcao_glow_style.set_corner_radius_all(int(op_h * 0.5))

		if lbl_modal_status != null:
			lbl_modal_status.position = Vector2(margem, y * 0.330)
			lbl_modal_status.size = Vector2(w - margem * 2.0, y * 0.038)
			lbl_modal_status.add_theme_font_size_override("font_size", _fs(0.022))

		# Cards 1..4 — altura aumentada (era y*0.190, agora y*0.225)
		# para o número e o rótulo "PLAYER"/"PLAYERS" terem espaço de
		# sobra dentro do card, sem risco de clip_contents cortar nada.
		var gap: float = max(12.0, w * 0.016)
		var cards_total: float = w - margem * 2.0 - gap * float(max(0, modal_cards.size() - 1))
		var card_w: float = cards_total / float(max(1, modal_cards.size()))
		var card_h: float = y * 0.215
		var card_y: float = y * 0.370
		for i in range(modal_cards.size()):
			var card: Panel = modal_cards[i] as Panel
			card.size = Vector2(card_w, card_h)
			card.position = Vector2(margem + float(i) * (card_w + gap), card_y)
			card.pivot_offset = card.size * 0.5

			var num: Label = modal_card_nums[i] as Label
			num.position = Vector2(0.0, card_h * 0.06)
			num.size = Vector2(card_w, card_h * 0.56)
			num.add_theme_font_size_override("font_size", _fs(0.060))

			var nome: Label = modal_card_nomes[i] as Label
			nome.position = Vector2(0.0, card_h * 0.60)
			nome.size = Vector2(card_w, card_h * 0.30)
			nome.add_theme_font_size_override("font_size", _fs(0.020))

		_atualizar_card_glow()

		# LEDs (pills)
		var led_gap: float = 12.0
		var led_w: float = ((w - margem * 2.0) - led_gap * 3.0) / 4.0
		var led_h: float = max(10.0, y * 0.024)
		var led_y: float = y * 0.605
		for i in range(modal_leds.size()):
			var led: Panel = modal_leds[i] as Panel
			led.position = Vector2(margem + float(i) * (led_w + led_gap), led_y)
			led.size = Vector2(led_w, led_h)
			var e: StyleBoxFlat = _led_estilos[i] as StyleBoxFlat
			e.set_corner_radius_all(int(led_h * 0.5))   # pill perfeita

		if modal_linha_base != null:
			modal_linha_base.position = Vector2(margem + w * 0.12, y * 0.645)
			modal_linha_base.size = Vector2(w - margem * 2.0 - w * 0.24, 3.0)

		# Chamada principal do modal: grande e fácil de ler.
		var cmd_y: float = y * 0.668
		var cmd_h: float = y * 0.112
		if modal_cmd_start_box != null:
			modal_cmd_start_box.position = Vector2(margem, cmd_y)
			modal_cmd_start_box.size = Vector2(w - margem * 2.0, cmd_h)
		if lbl_comando_start != null:
			lbl_comando_start.position = Vector2(margem, cmd_y)
			lbl_comando_start.size = Vector2(w - margem * 2.0, cmd_h)
			lbl_comando_start.add_theme_font_size_override("font_size", _fs(0.046))
		if lbl_acao_start != null:
			lbl_acao_start.visible = false

		# Barra de tempo (pill)
		var bar_y: float = y * 0.810
		var bar_h: float = y * 0.050
		if modal_timer_box != null:
			modal_timer_box.position = Vector2(margem, bar_y)
			modal_timer_box.size = Vector2(w - margem * 2.0, bar_h * 1.35)
		if modal_timer_bar_bg != null:
			modal_timer_bar_bg.position = Vector2(margem + 16.0, bar_y + bar_h * 0.30)
			modal_timer_bar_bg.size = Vector2(w - margem * 2.0 - 32.0, bar_h * 0.56)
		if modal_timer_bar != null:
			modal_timer_bar.position = Vector2(margem + 20.0, bar_y + bar_h * 0.38)
		if _timer_bar_style != null:
			var alt: float = max(2.0, bar_h * 0.56 - 8.0)
			_timer_bar_style.set_corner_radius_all(int(alt * 0.5))
		if lbl_modal_timer != null:
			lbl_modal_timer.position = Vector2(margem, y * 0.890)
			lbl_modal_timer.size = Vector2(w - margem * 2.0, y * 0.070)
			lbl_modal_timer.add_theme_font_size_override("font_size", _fs(0.024))

		_atualizar_barra_tempo_players()

	if lbl_start != null:
		lbl_start.add_theme_font_size_override("font_size", _fs(0.046))

	_config_particulas()



func _atualizar_barra_tempo_players() -> void:
	if modal_timer_bar_bg == null or modal_timer_bar == null:
		return

	var total: float = max(0.01, tempo_para_confirmar)
	var restante: float = total
	if _coletando and _deadline_ms > 0:
		restante = max(0.0, float(_deadline_ms - Time.get_ticks_msec()) / 1000.0)

	var frac: float = clampf(restante / total, 0.0, 1.0)
	var bg: Vector2 = modal_timer_bar_bg.size
	var mi: float = 4.0
	modal_timer_bar.size = Vector2(max(2.0, (bg.x - mi * 2.0) * frac), max(2.0, bg.y - mi * 2.0))

	if _timer_bar_style != null:
		var cor := cor_quente.lerp(Color(1.0, 0.12, 0.02), 1.0 - frac)
		_timer_bar_style.bg_color = cor
		_timer_bar_style.shadow_color = Color(cor.r, cor.g, cor.b, 0.45)

	if lbl_modal_timer != null and not _confirmando:
		lbl_modal_timer.text = "ENTRA EM %02d s" % int(ceil(restante))


# =====================================================================
# ANIMAÇÕES DA TELA
# =====================================================================
func _animar_entrada() -> void:
	if fade == null:
		return
	fade.visible = true
	fade.color = Color(0, 0, 0, 1)
	fade.move_to_front()
	var t := create_tween()
	t.tween_property(fade, "color:a", 0.0, 1.2)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _animar_start() -> void:
	if lbl_start == null:
		return
	lbl_start.pivot_offset = lbl_start.size * 0.5

	var ta := create_tween().set_loops()
	ta.tween_property(lbl_start, "modulate:a", 0.25, 0.7)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ta.tween_property(lbl_start, "modulate:a", 1.0, 0.7)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var te := create_tween().set_loops()
	te.tween_property(lbl_start, "scale", Vector2(1.06, 1.06), 0.7)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	te.tween_property(lbl_start, "scale", Vector2.ONE, 0.7)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _pulsar_vinheta() -> void:
	if vinheta == null:
		return
	var t := create_tween().set_loops()
	t.tween_property(vinheta, "modulate:a", 0.78, 1.9)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(vinheta, "modulate:a", 1.0, 1.9)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# =====================================================================
# INPUT / TROCA DE CENA
# =====================================================================
func _unhandled_input(evento: InputEvent) -> void:
	# Atalho de desenvolvedor: pula direto para o lobby de rede,
	# sem precisar passar pelo fluxo normal de START/modal de players.
	# Útil para testar a conexão entre 2 PCs rapidamente.
	if evento is InputEventKey and evento.pressed and not evento.echo and evento.keycode == KEY_F12:
		_ir_para_network_lobby()
		get_viewport().set_input_as_handled()
		return
	
	if evento is InputEventKey and evento.pressed and not evento.echo and evento.keycode == KEY_F10:
		_abrir_config_overlay()
		get_viewport().set_input_as_handled()
		return

	if _config_overlay_ativo != null and is_instance_valid(_config_overlay_ativo):
		return
	
	if _avancando or _confirmando or not permitir_avancar:
		return

	var apertou_start := false
	if acao_start != "" and InputMap.has_action(acao_start) and evento.is_action_pressed(acao_start):
		apertou_start = true
	elif evento is InputEventKey and evento.pressed and not evento.echo:
		var k := (evento as InputEventKey).keycode
		if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE or k == KEY_1:
			apertou_start = true

	if apertou_start:
		_registrar_start_player()
		get_viewport().set_input_as_handled()


func _abrir_config_overlay() -> void:
	if _config_overlay_ativo != null and is_instance_valid(_config_overlay_ativo):
		return
	if _avancando or _confirmando:
		return

	# Agora carregamos a CENA (.tscn), não o script solto. Isso exige
	# que exista um arquivo de cena de verdade em 'cena_config' com um
	# Control na raiz e o script config_overlay.gd anexado a ele —
	# criado uma vez no editor (Cena > Nova Cena > Control > anexar
	# script > salvar como res://scenes/config.tscn).
	var recurso := load(cena_config)
	if recurso == null or not (recurso is PackedScene):
		push_error("Abertura: FALHA ao carregar %s — verifique se o arquivo existe em Cena e se é uma cena válida (.tscn). Veja o painel Output/Debugger para detalhes." % cena_config)
		return

	var camada := CanvasLayer.new()
	camada.name = "ConfigOverlayLayer"
	camada.layer = 500
	add_child(camada)

	var overlay: Control = (recurso as PackedScene).instantiate()
	overlay.name = "ConfigOverlay"
	overlay.modo_overlay = true
	overlay.fechado.connect(_ao_fechar_config_overlay.bind(camada))
	camada.add_child(overlay)

	_config_overlay_ativo = overlay


func _ir_para_network_lobby() -> void:
	if _avancando or _confirmando:
		return
	if cena_network_lobby == "" or not ResourceLoader.exists(cena_network_lobby):
		push_warning("Abertura: cena de network lobby não encontrada em " + cena_network_lobby)
		return

	# Mesmo cuidado do fluxo normal de avanço: apaga os LEDs e fecha a
	# ponte serial ANTES de trocar de cena, para o lobby (ou o play,
	# se a conexão der certo) não brigar pela mesma porta COM.
	_avancando = true
	_mudando_para_cena = true
	_fechar_ponte_leds(true)

	if musica_abertura != null and musica_abertura.playing:
		var tm_musica := create_tween()
		tm_musica.tween_property(musica_abertura, "volume_db", -40.0, tempo_fade_saida)

	if fade != null:
		fade.visible = true
		fade.mouse_filter = Control.MOUSE_FILTER_STOP
		fade.move_to_front()
		fade.color = Color(0, 0, 0, 0)
		var t := create_tween()
		t.tween_property(fade, "color:a", 1.0, tempo_fade_saida)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await t.finished
		fade.color = Color(0, 0, 0, 1)
		fade.move_to_front()

	await get_tree().process_frame
	await get_tree().process_frame
	_trocar_cena(cena_network_lobby)



func _ao_fechar_config_overlay(_salvou: bool, camada: CanvasLayer) -> void:
	_config_overlay_ativo = null
	if _salvou:
		_carregar_modo_operacao()
		if lbl_start != null:
			lbl_start.text = _texto_chamada_principal()
		_atualizar_texto_modal()
	if camada != null and is_instance_valid(camada):
		camada.queue_free()



func _avancar() -> void:
	if _avancando:
		return
	_avancando = true
	_modal_aberto = false
	_coletando = false
	permitir_avancar = false

	if lbl_start != null:
		lbl_start.visible = false
	if modal_jogadores != null:
		var tm := create_tween()
		tm.tween_property(modal_jogadores, "modulate:a", 0.0, tempo_fade_saida * 0.7)
	if brasas != null:
		brasas.emitting = false
	if faiscas != null:
		faiscas.emitting = false
	if poeira != null:
		poeira.emitting = false

	if musica_abertura != null and musica_abertura.playing:
		var tm_musica := create_tween()
		tm_musica.tween_property(musica_abertura, "volume_db", -40.0, tempo_fade_saida)


	if fade != null:
		fade.visible = true
		fade.mouse_filter = Control.MOUSE_FILTER_STOP
		fade.move_to_front()
		fade.color = Color(0, 0, 0, 0)
		var t := create_tween()
		t.tween_property(fade, "color:a", 1.0, tempo_fade_saida)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await t.finished
		fade.color = Color(0, 0, 0, 1)
		fade.move_to_front()

	# Apaga os LEDs e fecha a COM da Abertura antes de entrar no Play.
	# O Play abre a própria ponte depois, sem disputar a mesma porta.
	_mudando_para_cena = true
	_fechar_ponte_leds(true)

	await get_tree().process_frame
	await get_tree().process_frame
	_trocar_cena(proxima_cena)


func _trocar_cena(caminho: String) -> void:
	if caminho == "":
		return
	var tela_node := get_node_or_null("/root/Tela")
	if tela_node != null and tela_node.has_method("trocar"):
		tela_node.trocar(caminho)
	elif ResourceLoader.exists(caminho):
		get_tree().change_scene_to_file(caminho)
