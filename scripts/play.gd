extends Control
# =====================================================================
# TELA DE JOGO — BASKET (HORIZONTAL, por turnos) — BASE ORIGINAL PRESERVADA
# Base preservada da versão padrão: cronômetro circular, tempo por jogador, combo, recorde, LEDs e efeitos de cesta.
# Ajuste visual para usar a arte limpa back_basquet.png sem perder a lógica original.
# Mantém ponte PowerShell/Arduino e comandos LED: PLAY, HIT, RECORD, BOOST, OFF.
# Efeito de cesta original: GRADE DE TILES que afunda/ilumina em ONDA a partir
# do ponto da cesta + partículas modernas.
#
# Cesta = ação "input_pointer" (Zero Delay). Mouse oculto (tudo por input).
# =====================================================================

signal ponto_marcado(idx: int, total: int)
signal partida_encerrada(pontuacoes: Array)

# ---------- CONFIGURAÇÕES ----------
@export_range(1, 4) var num_jogadores: int = 4
@export var tempo_partida: float = 60.0
@export var usar_config_tempo_partida: bool = true
@export var caminho_config_basket: String = "user://basket_config.cfg"
@export var iniciar_automatico: bool = false
@export var caminho_fundo: String = "res://images/back_basquet.png"
@export var caminho_fonte: String = "res://fonts/titan.ttf"
@export var caminho_logo_canto_hardcoded: String = "res://images/logo_lazer_sport.png"

# ---------- CESTA / PONTUAÇÃO ----------
@export var pontos_por_cesta: int = 2
@export var acao_cesta: String = "input_pointer"
@export var acao_start: String = "input_start"

@export var segundos_retorno_opening_podio: int = 12
@export var tempo_para_confirmar_reinicio_podio: float = 3.5
@export var tempo_maximo_reinicio_podio: float = 16.0
@export var atraso_reinicio_apos_max_podio: float = 0.55
@export var debounce_reinicio_podio_ms: int = 180
@export var usar_shootout_desempate: bool = true
@export var tempo_shootout_desempate: float = 10.0
@export var nome_shootout_desempate: String = "SHOOTOUT BASKET"

# ---------- PONTE POWERSHELL / ARDUINO ----------
@export var porta_leds: String = "COM5"
@export var baud_leds: int = 9600
@export var usar_ponte_leds_no_play: bool = true

var _led_bridge_pid: int = -1
var _led_bridge_ps: String = "user://basket_led_bridge.ps1"


# ---------- COROA / VISUAL DE RECORDE ----------
var record_coroa_layer: CanvasLayer = null
var record_coroa_ctrl: Control = null


var fx_fogo_pontos_atuais: Control = null
var logo_canto_fx: Control = null
var logo_canto_img: TextureRect = null
var _logo_canto_t: float = 0.0

# ---------- SHAKE DE TELA (cesta / combo / recorde) ----------
var _shake_forca: float = 0.0
var _shake_decaimento: float = 14.0
var _shake_tempo: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO

# ---------- PARTÍCULAS DE IMPACTO NA CESTA ----------
var particulas_cesta: CPUParticles2D = null

var painel_players_score: Panel = null  # fundo do mini-ranking PLAYERS SCORE (topo-direita)
var painel_record: Panel = null             # fundo elegante do RECORDE (topo-esquerda)

var _logo_empresa_config: String = ""


# Raio de canto ÚNICO usado tanto no card de pontos atuais quanto na
# cápsula do ranking — antes eram valores diferentes (10 vs 16), o
# que fazia o visual "recorde" e o visual "pontuação normal" parecerem
# de famílias diferentes. Agora os dois usam o mesmo padrão quadrado.
const _RAIO_CANTO_PADRAO := 8.0

# Cache da geometria da borda de fogo por card — evita RECALCULAR a
# lista inteira de pontos a cada frame (antes isso rodava 60x/seg
# junto com toda a trigonometria de cada língua de fogo, causando o
# engasgo ao entrar em recorde). Só recalcula se o tamanho do card
# realmente mudou.
var _cache_bordas_fogo: Dictionary = {}


# Layout do mini-ranking "PLAYERS SCORE" (topo-direita). Fica sempre
# fora da faixa do cronômetro central (x até 0.740) e acima do painel
# CURRENT SCORE (que começa em y=0.222) — nunca sobrepõe nenhum dos dois.
const _RANK_LEFT := 0.745
const _RANK_RIGHT := 0.968
const _RANK_TITULO_TOP := 0.020
const _RANK_TITULO_BOTTOM := 0.062
const _RANK_LISTA_TOP := 0.068
const _RANK_LISTA_BOTTOM := 0.214


const COR_COMBO_LARANJA_CLARO := Color(1.0, 0.70, 0.28)  # laranja claro do combo 4-5 — amarelo fica exclusivo do recorde

const _PS_BRIDGE_BASKET := """
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


var lbl_podio_timer: Label = null
var lbl_podio_cta_principal: Label = null
var lbl_podio_cta_sub: Label = null
var _podio_retorno_token: int = 0
var _podio_reinicio_coletando: bool = false
var _podio_reinicio_confirmando: bool = false
var _podio_reinicio_pulsos: int = 0
var _podio_reinicio_deadline_ms: int = 0
var _podio_reinicio_hard_deadline_ms: int = 0
var _ultimo_pulso_reinicio_podio_ms: int = -999999

var _shootout_ativo: bool = false
var _shootout_participantes: Array = []
var _shootout_participantes_rodada: Array = []
var _shootout_pos: int = 0
var _shootout_rodada: int = 0
var _shootout_pontos_rodada: Array = [0, 0, 0, 0]
var _shootout_pontos_total: Array = [0, 0, 0, 0]
var _shootout_base_pontos: Array = [0, 0, 0, 0]
var _shootout_historico: Array = []
var _partida_teve_shootout: bool = false

var box_players_score: VBoxContainer = null


var _fechando_tela: bool = false

# ---------- ÁUDIO ----------
@export var caminho_musica_fundo: String = "res://songs/bask_play.mp3"
@export var caminho_som_cesta: String = "res://songs/switch.mp3"
@export var caminho_apito_inicio: String = "res://songs/apito_inicio.mp3"
@export var caminho_end_bask: String = "res://songs/end_bask.mp3"
@export var caminho_song_good_player: String = "res://songs/good_player.mp3"
@export var volume_song_good_player_db: float = 0.0
@export var volume_musica_db: float = -10.0
@export var volume_cesta_db: float = 0.0


# ---------- CONTAGEM REGRESSIVA ----------
@export var segundos_contagem: int = 3

# ---------- COMBO / BOA JOGADA ----------
@export var janela_combo_segundos: float = 4.0
@export var volume_combo_db: float = 2.0

@export var caminho_som_combo_1: String = "res://songs/combo_1.mp3"
@export var caminho_som_combo_2: String = "res://songs/combo_2.mp3"
@export var caminho_som_combo_3: String = "res://songs/combo_3.mp3"
@export var caminho_som_combo_4: String = "res://songs/combo_4.mp3"
@export var caminho_som_combo_5: String = "res://songs/combo_5.mp3"
@export var caminho_som_combo_6: String = "res://songs/combo_6.mp3"
@export var caminho_som_combo_7: String = "res://songs/combo_7.mp3"
@export var caminho_som_combo_8: String = "res://songs/combo_8.mp3"
@export var caminho_som_combo_9: String = "res://songs/combo_9.mp3"
@export var caminho_som_combo_10: String = "res://songs/combo_10.mp3"
@export var caminho_som_combo_11: String = "res://songs/combo_11.mp3"
@export var caminho_som_combo_12: String = "res://songs/combo_12.mp3"


# ---------- PÓDIO ----------
@export var mostrar_podio_automatico: bool = true
@export_file("*.tscn") var cena_abertura: String = "res://scenes/opening.tscn"

# ---------- CORES ----------
const CORES_PLAYERS := [
	Color(1.0, 0.27, 0.27),
	Color(0.27, 0.6, 1.0),
	Color(0.3, 1.0, 0.5),
	Color(1.0, 0.82, 0.2),
]
const NOMES_PADRAO := ["JOGADOR 1", "JOGADOR 2", "JOGADOR 3", "JOGADOR 4"]

# Paleta do tema "china arcade" (azul-elétrico + verde display + âmbar).
const COR_AZUL := Color(1.0, 0.38, 0.02)        # agora o tema base fica laranja
const COR_VERDE_DISPLAY := Color(1.0, 0.46, 0.04) # cronômetro/placar central em laranja
const COR_BRANCO_FX := Color(1.0, 1.0, 1.0)       # efeito que antes era verde
const COR_AMBAR := Color(1.0, 0.62, 0.08)

# Paleta do RECORDE (efeito dourado especial ao bater o recorde).
const COR_RECORDE := Color(1.0, 0.42, 0.02)        # laranja forte
const COR_RECORDE_BRILHO := Color(1.0, 0.68, 0.08) # brilho laranja quente
const COR_RECORDE_CLARO := Color(1.0, 0.88, 0.42)  # só para texto/realce


# ---------- BOOSTER DE RECORDE ----------
var _record_booster_ativo: bool = false
var _record_booster_pulso: float = 0.0
var _ondas_pontos_card: Array = []

# ---------- LEDS ARDUINO / RGB ----------
@export var usar_leds_arduino: bool = true
@export var caminho_fila_leds_basket: String = "user://basket_led_cmd.txt"


# ---------- ESTADO ----------
var _pontos: Array = [0, 0, 0, 0]
var _nomes: Array = NOMES_PADRAO.duplicate()
var _turnos_finalizados: Array = [false, false, false, false]
var _jogador_atual: int = 0
var _tempo_restante: float = 0.0
var _rodando: bool = false

var _podio_ativo: bool = false
var _podio_layer: CanvasLayer = null

var _modal_turno_layer: CanvasLayer = null
var _modal_turno_ativo: bool = false
var _modal_turno_pronto: bool = false

var transicao_root: Control = null

# ---------- NÓS HUD ----------
var fundo: TextureRect
var _hud: CanvasLayer
var _efeitos: CanvasLayer

var crono_ring: Control = null          # anel circular do cronômetro (desenhado)
var lbl_crono: Label = null             # número grande dentro do anel
var lbl_tempo_titulo: Label = null       # "TEMPO" acima do cronômetro
var lbl_high_titulo: Label = null       # "ALL-TIME HIGH"
var lbl_high_valor: Label = null        # recorde em 7-seg
var lbl_players_titulo: Label = null    # "PLAYERS SCORE"
var lbl_meta_titulo: Label = null       # "SCORE PASS"
var lbl_meta_valor: Label = null        # meta (7-seg amarelo)
var lbl_atual_titulo: Label = null      # "CURRENT SCORE"
var lbl_atual_pontos: Label = null      # pontos atuais (7-seg verde)
var painel_placar: Panel = null         # faixa do placar embaixo do anel

var painel_score_pass: Panel = null     # bloco esquerdo abaixo do cronômetro
var painel_current_score: Panel = null  # bloco direito abaixo do cronômetro

var col_players: HBoxContainer = null   # rodapé horizontal dos players
var card_jogando: Panel = null          # destaque do jogador da vez (topo)
var _player_cards: Array = []           # cards menores (1 por jogador)

var musica_fundo: AudioStreamPlayer
var som_cesta: AudioStreamPlayer
var som_apito: AudioStreamPlayer
var som_fim: AudioStreamPlayer
var som_good_player: AudioStreamPlayer

# ---------- FX AMBIENTE / GRADE ----------
var fx_ambiente_layer: CanvasLayer = null
var fx_ambiente: Control = null
var _fx_tempo: float = 0.0

@export var usar_fx_ambiente: bool = true
@export var usar_shader_fundo: bool = true
@export var intensidade_luz_fundo: float = 0.40

# Grade de tiles que reage à cesta (ondas).
var grade_layer: CanvasLayer = null
var grade_ctrl: Control = null
var _grade_cols: int = 0
var _grade_rows: int = 0
var _grade_passo: float = 0.0
var _grade_ondas: Array = []            # cada onda: {origem:Vector2, t:float, dur:float}

# Ondas de luz fortes no acerto da cesta
var luz_onda_layer: CanvasLayer = null
var luz_onda_ctrl: Control = null
var _ondas_luz: Array = []


@export var tempo_trava_cesta: float = 1.20
var _trava_cesta_t: float = 0.0

var modo_credito: bool = false

# ---------- RECORDE ----------
@export var caminho_record_basket: String = "user://basket_record.cfg"
var record_maximo: int = 0

# Marca o recorde do início do turno e se a quebra já foi celebrada.
var _record_inicial_turno: int = 0
var _recorde_celebrado_turno: bool = false

# ---------- TRANSIÇÃO ----------
var transicao_layer: CanvasLayer = null
var transicao_fundo: ColorRect = null
var transicao_titulo: Label = null
var transicao_subtitulo: Label = null
var transicao_barra_fundo: Panel = null
var transicao_barra: ColorRect = null
var transicao_fx: Control = null
var _transicao_t: float = 0.0
var _transicao_ativa: bool = false

var _podio_linha_dif: Control = null
var _podio_cards_ref: Array = []

var sons_combo: Array = []

var combo_layer: CanvasLayer = null
var lbl_combo: Label = null
var _combo_tween: Tween = null

var _combo_nivel: int = 0
var _combo_ultimo_t: float = -999.0
var _combo_ultima_frase: String = ""  # evita repetir a mesma frase duas vezes seguidas

var _config_overlay_ativo: Control = null
var _estava_rodando_antes_config: bool = false



# =====================================================================
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	# Alt+F4 / X da janela passam por fechamento seguro,
	# para apagar LEDs e fechar a ponte antes de sair.
	get_tree().auto_accept_quit = false

	_aplicar_config_basket()
	_carregar_record_basket()
	_ler_quantidade_da_opening()

	_montar_cena()
	_carregar_fundo()
	_aplicar_shader_fundo_retrato()
	_iniciar_musica_fundo()
	_carregar_sons()
	_criar_fx_ambiente()
	_criar_grade_tiles()
	_criar_luz_ondas_cesta()
	_criar_particulas_cesta()
	_criar_transicao_layer()
	_criar_combo_ui()
	#_criar_record_coroa_ui()
	_layout_responsivo()
	_atualizar_visao_turno()
	_atualizar_tempo_label()

	if not get_viewport().size_changed.is_connected(_layout_responsivo):
		get_viewport().size_changed.connect(_layout_responsivo)

	await get_tree().process_frame
	await _transicao_entrada("CARREGANDO ARENA", "CONECTANDO LEDS E MONTANDO A ARENA...")

	if iniciar_automatico:
		iniciar_partida(_duracao_turno_atual())
	else:
		_mostrar_modal_turno(true)


func _process(delta: float) -> void:
	_trava_cesta_t = max(0.0, _trava_cesta_t - delta)

	if _podio_ativo and _podio_reinicio_coletando and not _podio_reinicio_confirmando:
		_atualizar_cta_podio_reinicio()
		if Time.get_ticks_msec() >= _podio_reinicio_deadline_ms:
			_confirmar_reinicio_podio_com_pulsos()

	if _transicao_ativa:
		_transicao_t += delta
		if transicao_fx != null:
			transicao_fx.queue_redraw()

	if usar_fx_ambiente:
		_atualizar_fx_ambiente(delta)

	_atualizar_grade(delta)
	_atualizar_luz_ondas_cesta(delta)
	_atualizar_shake(delta)

	_atualizar_ondas_card_pontos(delta)
	_atualizar_logo_canto(delta)

	if _record_booster_ativo:
		_record_booster_pulso += delta * 9.0
		_queue_redraw_fire_pontos_cards()
		if fx_fogo_pontos_atuais != null:
			fx_fogo_pontos_atuais.queue_redraw()

	if grade_ctrl != null:
		grade_ctrl.queue_redraw()

	if fx_ambiente != null:
		fx_ambiente.queue_redraw()

	if luz_onda_ctrl != null:
		luz_onda_ctrl.queue_redraw()

	if crono_ring != null:
		crono_ring.queue_redraw()

	if not _rodando:
		return

	_tempo_restante -= delta
	if _tempo_restante <= 0.0:
		_tempo_restante = 0.0
		_rodando = false
		_atualizar_tempo_label()
		_encerrar_turno_atual()
	else:
		_atualizar_tempo_label()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_fechar_tela_seguro()



func _fechar_tela_seguro() -> void:
	if _fechando_tela:
		return

	_fechando_tela = true
	_rodando = false
	_modal_turno_ativo = false
	_modal_turno_pronto = false
	_podio_ativo = false

	# Apaga LED e fecha a ponte antes de sair.
	_fechar_ponte_leds_play(true)

	get_tree().quit()



# =====================================================================
# ONDAS DE LUZ DA CESTA — sem partículas
# =====================================================================
func _criar_luz_ondas_cesta() -> void:
	if luz_onda_layer != null and is_instance_valid(luz_onda_layer):
		return

	luz_onda_layer = CanvasLayer.new()
	luz_onda_layer.name = "LuzOndaCestaLayer"
	luz_onda_layer.layer = 3 # acima da grade, abaixo do HUD
	add_child(luz_onda_layer)

	luz_onda_ctrl = Control.new()
	luz_onda_ctrl.name = "LuzOndaCestaCtrl"
	luz_onda_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	luz_onda_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	luz_onda_layer.add_child(luz_onda_ctrl)

	if not luz_onda_ctrl.draw.is_connected(_desenhar_luz_ondas_cesta):
		luz_onda_ctrl.draw.connect(_desenhar_luz_ondas_cesta)


func _criar_particulas_cesta() -> void:
	if particulas_cesta != null and is_instance_valid(particulas_cesta):
		return

	particulas_cesta = CPUParticles2D.new()
	particulas_cesta.name = "ParticulasCesta"
	particulas_cesta.emitting = false
	particulas_cesta.one_shot = true
	particulas_cesta.amount = 26
	particulas_cesta.lifetime = 0.62
	particulas_cesta.explosiveness = 0.92
	particulas_cesta.direction = Vector2(0, -1)
	particulas_cesta.spread = 180.0
	particulas_cesta.gravity = Vector2(0, 340.0)
	particulas_cesta.initial_velocity_min = 120.0
	particulas_cesta.initial_velocity_max = 420.0
	particulas_cesta.scale_amount_min = 2.0
	particulas_cesta.scale_amount_max = 4.5
	particulas_cesta.color_ramp = _ramp_particulas_cesta(COR_VERDE_DISPLAY)

	if luz_onda_ctrl != null:
		luz_onda_ctrl.add_child(particulas_cesta)
	else:
		add_child(particulas_cesta)


func _ramp_particulas_cesta(cor: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(cor.r, cor.g, cor.b, 0.9),
		Color(cor.r, cor.g, cor.b, 0.0),
	])
	return g


func _disparar_particulas_cesta(origem: Vector2, cor: Color, forca: float = 1.0) -> void:
	if particulas_cesta == null or not is_instance_valid(particulas_cesta):
		return

	particulas_cesta.position = origem
	particulas_cesta.amount = int(clampf(22.0 * forca, 16.0, 60.0))
	particulas_cesta.color_ramp = _ramp_particulas_cesta(cor)
	particulas_cesta.restart()
	particulas_cesta.emitting = true



func _disparar_luz_onda_cesta(origem: Vector2, dourado: bool = false, forca: float = 1.0, combo_nivel: int = 1, record_mode: bool = false, tipo: int = TipoOnda.RADIAL) -> void:
	var nivel: int = max(1, combo_nivel)

	_ondas_luz.append({
		"origem": origem,
		"t": 0.0,
		"dur": 0.95 if record_mode else (1.05 if nivel >= 9 else 0.95),
		"forca": forca,
		"dourado": dourado,
		"inverso": false,
		"combo": nivel,
		"raio_ida_volta": record_mode or nivel >= 9,
		"record": record_mode,
		"tipo": tipo,
		"ciclo_cor": _ciclo_cor_onda
	})

	if luz_onda_ctrl != null:
		luz_onda_ctrl.queue_redraw()


func _disparar_implosao(origem: Vector2, cor: Color = Color(1.0, 0.55, 0.08), forca: float = 1.0) -> void:
	# Onda que vem das PERIFERIAS para DENTRO (efeito inverso da cesta).
	_ondas_luz.append({
		"origem": origem,
		"t": 0.0,
		"dur": 0.62,
		"forca": forca,
		"dourado": false,
		"inverso": true,
		"cor": cor
	})

	if luz_onda_ctrl != null:
		luz_onda_ctrl.queue_redraw()


func _atualizar_luz_ondas_cesta(delta: float) -> void:
	if luz_onda_ctrl == null:
		return

	if _ondas_luz.is_empty():
		return

	var vivas: Array = []

	for o in _ondas_luz:
		o["t"] = float(o["t"]) + delta
		if float(o["t"]) < float(o["dur"]):
			vivas.append(o)

	_ondas_luz = vivas
	luz_onda_ctrl.queue_redraw()



# =====================================================================
# SHAKE DE TELA — reforça o impacto de cestas fortes / combo / recorde
# =====================================================================
func _atualizar_shake(delta: float) -> void:
	if _shake_forca <= 0.02:
		if _shake_offset != Vector2.ZERO:
			_shake_offset = Vector2.ZERO
			_aplicar_shake_nas_camadas()
		return

	_shake_tempo += delta * 26.0
	_shake_forca = max(0.0, _shake_forca - delta * _shake_decaimento)

	_shake_offset = Vector2(
		sin(_shake_tempo * 1.7) + sin(_shake_tempo * 3.3) * 0.5,
		cos(_shake_tempo * 2.1) + cos(_shake_tempo * 4.2) * 0.5
	) * _shake_forca

	_aplicar_shake_nas_camadas()


func _aplicar_shake_nas_camadas() -> void:
	# Só os efeitos visuais tremem (grade de tiles e ondas de luz).
	# HUD, cards dos players e texto de combo ficam FIXOS — tremer
	# junto deixaria os cards ilegíveis e a UI "nervosa" demais.
	for camada in [grade_layer, luz_onda_layer]:
		if camada != null and is_instance_valid(camada):
			camada.offset = _shake_offset


func _disparar_shake(forca: float, decaimento: float = 14.0) -> void:
	_shake_forca = max(_shake_forca, forca)
	_shake_decaimento = decaimento


func _desenhar_luz_ondas_cesta() -> void:
	if luz_onda_ctrl == null:
		return

	var tela: Vector2 = get_viewport_rect().size

	if _record_booster_ativo:
		_desenhar_record_shader_eterno(tela)

	for o in _ondas_luz:
		var origem: Vector2 = o["origem"]
		var t: float = float(o["t"])
		var dur: float = float(o["dur"])
		var p: float = clampf(t / dur, 0.0, 1.0)
		var forca: float = float(o.get("forca", 1.0))
		var inverso: bool = bool(o.get("inverso", false))
		var dourado: bool = bool(o.get("dourado", false))
		var combo_nivel: int = int(o.get("combo", 1))
		var raio_ida_volta: bool = bool(o.get("raio_ida_volta", false))
		var record_onda: bool = bool(o.get("record", false))
		var tipo_onda: int = int(o.get("tipo", TipoOnda.RADIAL))

		if record_onda:
			_desenhar_record_hit_ida_volta(origem, p, forca, tela, tipo_onda)
			continue

		var cor_ring: Color
		var cor_glow: Color

		if o.has("cor"):
			cor_ring = o["cor"]
			cor_glow = COR_BRANCO_FX
		elif combo_nivel >= 13:
			cor_ring = Color(1.0, 0.02, 0.0)
			cor_glow = Color(1.0, 0.42, 0.25)
		elif combo_nivel >= 9:
			cor_ring = Color(0.62, 0.12, 1.0)
			cor_glow = Color(0.95, 0.35, 1.0)
		elif combo_nivel >= 6:
			cor_ring = Color(0.08, 0.42, 1.0)
			cor_glow = Color(0.38, 0.75, 1.0)
		elif dourado:
			cor_ring = COR_RECORDE
			cor_glow = COR_RECORDE_BRILHO
		else:
			# Antes o matiz girava por TODO o círculo de cores a cada "saco"
			# de padrões consumido — isso empurrava a cor pro AMARELO já no
			# primeiro ou segundo ciclo (matiz ~59°, quase idêntico ao
			# amarelo do recorde). Amarelo agora é EXCLUSIVO do recorde, então
			# aqui a variação fica PRESA numa faixa estreita de laranja,
			# oscilando com sin() (vai e volta) em vez de crescer sem limite.
			var ciclo_desta_onda: int = int(o.get("ciclo_cor", 0))
			var base := Color(1.0, 0.48, 0.06)
			var fase: float = float(ciclo_desta_onda) * 0.7
			var variacao_matiz: float = 0.018 * sin(fase)  # +-6.5 graus — sempre laranja, nunca amarelo
			var cor_ciclica: Color = Color.from_hsv(base.h + variacao_matiz, base.s, base.v, 1.0)
			cor_ring = cor_ciclica
			cor_glow = COR_BRANCO_FX

		if inverso:
			_desenhar_onda_inversa(origem, p, forca, cor_ring, cor_glow, tela)
		else:
			_desenhar_onda_formato(tipo_onda, origem, p, forca, dourado, cor_ring, cor_glow, tela, combo_nivel, raio_ida_volta)



func _desenhar_onda_formato(
	tipo: int,
	origem: Vector2,
	p: float,
	forca: float,
	dourado: bool,
	cor_ring: Color,
	cor_glow: Color,
	tela: Vector2,
	combo_nivel: int = 1,
	raio_ida_volta: bool = false
) -> void:
	match tipo:
		TipoOnda.FAIXA_H:
			_desenhar_onda_linha_quadrados(origem, p, forca, cor_ring, cor_glow, tela, combo_nivel, raio_ida_volta, [Vector2(1, 0)])
		TipoOnda.FAIXA_V:
			_desenhar_onda_linha_quadrados(origem, p, forca, cor_ring, cor_glow, tela, combo_nivel, raio_ida_volta, [Vector2(0, 1)])
		TipoOnda.DIAGONAL_A:
			_desenhar_onda_linha_quadrados(origem, p, forca, cor_ring, cor_glow, tela, combo_nivel, raio_ida_volta, [Vector2(0.7071, 0.7071)])
		TipoOnda.DIAGONAL_B:
			_desenhar_onda_linha_quadrados(origem, p, forca, cor_ring, cor_glow, tela, combo_nivel, raio_ida_volta, [Vector2(0.7071, -0.7071)])
		TipoOnda.XIS:
			# As DUAS diagonais ao mesmo tempo — o "X" propriamente dito.
			_desenhar_onda_linha_quadrados(origem, p, forca, cor_ring, cor_glow, tela, combo_nivel, raio_ida_volta, [Vector2(0.7071, 0.7071), Vector2(0.7071, -0.7071)])
		TipoOnda.CRUZ:
			_desenhar_onda_linha_quadrados(origem, p, forca, cor_ring, cor_glow, tela, combo_nivel, raio_ida_volta, [Vector2(1, 0), Vector2(0, 1)])
		TipoOnda.QUADRADO:
			_desenhar_onda_perimetro_quadrados(origem, p, forca, cor_ring, cor_glow, tela, combo_nivel, raio_ida_volta, false)
		TipoOnda.LOSANGO:
			_desenhar_onda_perimetro_quadrados(origem, p, forca, cor_ring, cor_glow, tela, combo_nivel, raio_ida_volta, true)
		_:
			_desenhar_onda_normal(origem, p, forca, dourado, cor_ring, cor_glow, tela, combo_nivel, raio_ida_volta)




func _desenhar_quadrado_glow_luz(centro: Vector2, tam: float, cor_ring: Color, cor_glow: Color, alpha_core: float, alpha_glow: float) -> void:
	# Bloco de UM único quadradinho glow — pequeno o bastante pra nunca
	# virar uma mancha de cor cobrindo a tela (o problema do "fundo
	# diferente" de antes). É essa peça que se repete, sozinha ou em
	# fileira, pra formar TODOS os padrões: faixa, cruz, X, losango...
	if luz_onda_ctrl == null:
		return
	if alpha_core <= 0.001 and alpha_glow <= 0.001:
		return
	var meia: float = tam * 0.5
	var rect := Rect2(centro - Vector2(meia, meia), Vector2(tam, tam))
	luz_onda_ctrl.draw_rect(rect.grow(tam * 0.35), Color(cor_glow.r, cor_glow.g, cor_glow.b, alpha_glow), true)
	luz_onda_ctrl.draw_rect(rect, Color(cor_ring.r, cor_ring.g, cor_ring.b, alpha_core), true)
	luz_onda_ctrl.draw_rect(rect, Color(1.0, 1.0, 1.0, alpha_core * 0.5), false, max(1.0, tam * 0.06), true)


func _pontos_perimetro_poligono(corners: PackedVector2Array, passo: float) -> PackedVector2Array:
	# Distribui pontos igualmente ao longo do perímetro de um polígono
	# (usado pra QUADRADO e LOSANGO) — cada ponto vira um quadradinho.
	var pts := PackedVector2Array()
	var n_edges: int = corners.size()
	if n_edges < 2:
		return pts
	var perimetro: float = 0.0
	for i in range(n_edges):
		perimetro += corners[i].distance_to(corners[(i + 1) % n_edges])
	if perimetro < 1.0:
		return pts
	var n: int = max(4, int(perimetro / passo))
	for i in range(n):
		var d: float = perimetro * float(i) / float(n)
		var acc: float = 0.0
		for e in range(n_edges):
			var a: Vector2 = corners[e]
			var b: Vector2 = corners[(e + 1) % n_edges]
			var seg_len: float = a.distance_to(b)
			if d <= acc + seg_len:
				var t: float = (d - acc) / max(0.001, seg_len)
				pts.append(a.lerp(b, t))
				break
			acc += seg_len
	return pts


func _desenhar_onda_linha_quadrados(
	origem: Vector2, p: float, forca: float, cor_ring: Color, cor_glow: Color,
	tela: Vector2, combo_nivel: int, raio_ida_volta: bool, direcoes: Array
) -> void:
	# FAIXA_H, FAIXA_V, DIAGONAL_A/B, CRUZ e XIS caem todos aqui. A
	# linha principal (camada 0) continua com força total, igual antes.
	# Ao redor dela nascem MAIS quadrados: preenchimento ao LONGO da
	# própria linha (entre os quadrados principais) e preenchimento
	# PERPENDICULAR (grudado na linha, pra cima e pra baixo dela) — os
	# dois sempre saindo da parte mais sólida (a linha principal), bem
	# mais transparentes, pra dar volume sem competir com o traço nítido.
	var p_raio: float = p_ping_pong(p) if raio_ida_volta else p
	var fade: float = (1.0 - abs(p - 0.5) * 0.85) if raio_ida_volta else (1.0 - p)
	if fade <= 0.0:
		return

	var alcance_max: float = max(tela.x, tela.y) * 0.62
	var alcance: float = lerpf(alcance_max * 0.10, alcance_max, p_raio)
	var tam: float = tela.y * (0.030 + 0.006 * min(float(combo_nivel), 13.0))
	var passo: float = tam * 1.55

	var alpha_core: float = 0.55 * fade * forca
	var alpha_glow: float = 0.22 * fade * forca

	# Camadas paralelas à linha (perpendicular), cada uma mais fraca.
	var mult_camada: Array = [0.34, 0.17, 0.08]

	for dir in direcoes:
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var d: float = passo * 0.5
		while d <= alcance:
			for sinal in [1.0, -1.0]:
				var centro_base: Vector2 = origem + dir * (d * sinal)
				var dist_da_frente: float = abs(d - alcance)
				var realce: float = clampf(1.0 - dist_da_frente / max(1.0, passo * 3.0), 0.35, 1.0)

				# --- Camada 0: linha sólida principal (sem mudanças) ---
				_desenhar_quadrado_glow_luz(centro_base, tam, cor_ring, cor_glow, alpha_core * realce, alpha_glow * realce)

				# --- Preenchimento AO LONGO da própria linha: um
				# quadrado extra bem fraco no meio do caminho até o
				# próximo, deixando o traço com MAIS quadrados acesos
				# sem ficar cheio de buracos entre eles. ---
				var centro_meio: Vector2 = origem + dir * ((d + passo * 0.5) * sinal)
				var dist_meio: float = abs(d + passo * 0.5 - alcance)
				if dist_meio <= passo * 3.5:
					var realce_meio: float = clampf(1.0 - dist_meio / max(1.0, passo * 3.5), 0.0, 1.0)
					_desenhar_quadrado_glow_luz(centro_meio, tam * 0.80, cor_ring, cor_glow, alpha_core * realce_meio * 0.30, alpha_glow * realce_meio * 0.30)

				# --- Camadas PERPENDICULARES: mais fileiras paralelas
				# grudadas na linha principal, cada vez mais fracas e
				# mais transparentes conforme se afastam — sempre
				# nascendo da parte sólida, nunca soltas no vazio. ---
				for camada in range(1, mult_camada.size() + 1):
					var mult: float = mult_camada[camada - 1]
					var offset_perp: float = passo * float(camada) * 0.90
					var tam_camada: float = tam * (1.0 - float(camada) * 0.13)
					for lado in [1.0, -1.0]:
						var centro_pre: Vector2 = centro_base + perp * (offset_perp * lado)
						_desenhar_quadrado_glow_luz(
							centro_pre, tam_camada, cor_ring, cor_glow,
							alpha_core * realce * mult, alpha_glow * realce * mult
						)
						# Mesmo preenchimento "ao longo" também nas
						# camadas paralelas — é isso que faz acender
						# BASTANTE quadrado no total, sempre bem fraco.
						if dist_meio <= passo * 3.5:
							var centro_pre_meio: Vector2 = centro_meio + perp * (offset_perp * lado)
							var realce_meio2: float = clampf(1.0 - dist_meio / max(1.0, passo * 3.5), 0.0, 1.0)
							_desenhar_quadrado_glow_luz(
								centro_pre_meio, tam_camada * 0.78, cor_ring, cor_glow,
								alpha_core * realce_meio2 * mult * 0.30, alpha_glow * realce_meio2 * mult * 0.30
							)
			d += passo

	_desenhar_quadrado_glow_luz(origem, tam * 1.3, cor_ring, cor_glow, alpha_core * 0.7, alpha_glow * 0.7)



func _desenhar_onda_perimetro_quadrados(
	origem: Vector2, p: float, forca: float, cor_ring: Color, cor_glow: Color,
	tela: Vector2, combo_nivel: int, raio_ida_volta: bool, losango: bool
) -> void:
	var p_raio: float = p_ping_pong(p) if raio_ida_volta else p
	var fade: float = (1.0 - abs(p - 0.5) * 0.85) if raio_ida_volta else (1.0 - p)
	if fade <= 0.0:
		return

	var raio_max_tela: float = max(tela.x, tela.y)
	var r: float = lerpf(raio_max_tela * 0.06, raio_max_tela * 0.55, p_raio)
	var tam: float = tela.y * (0.030 + 0.006 * min(float(combo_nivel), 13.0))
	var passo: float = tam * 1.55

	var corners: PackedVector2Array
	if losango:
		corners = PackedVector2Array([origem + Vector2(0, -r), origem + Vector2(r, 0), origem + Vector2(0, r), origem + Vector2(-r, 0)])
	else:
		corners = PackedVector2Array([origem + Vector2(-r, -r), origem + Vector2(r, -r), origem + Vector2(r, r), origem + Vector2(-r, r)])

	var pontos := _pontos_perimetro_poligono(corners, passo)

	var alpha_core: float = 0.55 * fade * forca
	var alpha_glow: float = 0.22 * fade * forca

	for i in range(pontos.size()):
		var pt: Vector2 = pontos[i]
		_desenhar_quadrado_glow_luz(pt, tam, cor_ring, cor_glow, alpha_core, alpha_glow)

		# Poeira leve — só 1 a cada 3 pontos, bem discreta (o perímetro
		# inteiro já preenche bastante área sozinho).
		if i % 3 == 0:
			var seed_p: float = origem.x * 0.017 + origem.y * 0.011 + float(i) * 4.7
			var dist_r: float = (_ruido01(seed_p) * 2.0 - 1.0) * tam * 2.2
			var dir_r: Vector2 = (pt - origem).normalized()
			var centro_poeira: Vector2 = pt + dir_r * dist_r
			var tam_poeira: float = tam * (0.30 + _ruido01(seed_p * 1.7) * 0.25)
			var alpha_poeira: float = alpha_core * (0.14 + _ruido01(seed_p * 2.3) * 0.10)
			_desenhar_quadrado_glow_luz(centro_poeira, tam_poeira, cor_ring, cor_glow, alpha_poeira, alpha_poeira * 0.4)
	
	

func _desenhar_record_shader_eterno(tela: Vector2) -> void:
	if luz_onda_ctrl == null:
		return

	var origem := _record_origem_fx()

	# Como _record_booster_pulso já sobe rápido no _process,
	# aqui usamos multiplicadores pequenos para deixar elegante.
	var tempo := _record_booster_pulso

	var pulso_forca: float = 0.72 + 0.28 * abs(sin(tempo * 1.35))
	var ciclo: float = fposmod(tempo * 0.075, 1.0)

	# Duas ondas em ciclos diferentes para nunca ficar vazio.
	# Cada uma tem frente amarela e rastro branco atrás.
	_desenhar_record_dupla_faixa(origem, ciclo, pulso_forca, tela, 1.00)
	_desenhar_record_dupla_faixa(origem, fposmod(ciclo + 0.50, 1.0), pulso_forca, tela, 0.78)

	# Brilho central constante na cesta, bem controlado.
	var brilho_cesta: float = 0.10 + 0.08 * abs(sin(tempo * 1.8))
	luz_onda_ctrl.draw_circle(
		origem,
		tela.y * 0.045,
		Color(1.0, 0.86, 0.18, brilho_cesta)
	)

	luz_onda_ctrl.draw_circle(
		origem,
		tela.y * 0.026,
		Color(1.0, 1.0, 1.0, brilho_cesta * 0.45)
	)


func _desenhar_record_dupla_faixa(origem: Vector2, p: float, pulso: float, tela: Vector2, intensidade: float = 1.0) -> void:
	p = clampf(p, 0.0, 1.0)

	var raio_min: float = tela.y * 0.090
	var raio_max: float = max(tela.x, tela.y) * 0.560
	var raio_frente: float = lerpf(raio_min, raio_max, p)

	# A faixa branca vem atrás da amarela.
	var atraso_branco: float = tela.y * 0.055
	var raio_tras: float = max(raio_min * 0.65, raio_frente - atraso_branco)

	# Fade suave para nascer e sumir sem corte.
	var envelope: float = sin(p * PI)
	envelope = pow(max(0.0, envelope), 0.72)

	var alpha_amarelo: float = 0.44 * envelope * pulso * intensidade
	var alpha_branco: float = 0.34 * envelope * pulso * intensidade

	var largura_amarela: float = max(5.0, tela.y * 0.014)
	var largura_branca: float = max(3.5, tela.y * 0.010)

	# Rastro branco atrás
	_desenhar_faixa_onda_record(
		origem,
		raio_tras,
		largura_branca,
		Color(1.0, 1.0, 1.0, alpha_branco)
	)

	# Frente amarela
	_desenhar_faixa_onda_record(
		origem,
		raio_frente,
		largura_amarela,
		Color(1.0, 0.78, 0.02, alpha_amarelo)
	)

	# Glow fino na frente
	_desenhar_faixa_onda_record(
		origem,
		raio_frente + largura_amarela * 0.72,
		max(1.5, largura_amarela * 0.28),
		Color(1.0, 0.96, 0.62, alpha_amarelo * 0.48)
	)


func _desenhar_record_hit_ida_volta(origem: Vector2, p: float, forca: float, tela: Vector2, tipo: int = TipoOnda.RADIAL) -> void:
	if tipo != TipoOnda.RADIAL:
		# O recorde também varia de forma — "alguns até voltam" continua
		# valendo (raio_ida_volta=true), só que agora o formato em si
		# também muda, mantendo a paleta dourada/branca característica
		# do recorde em vez das cores de combo normais.
		_desenhar_onda_formato(tipo, origem, p, forca * 1.15, true, Color(1.0, 0.80, 0.02), Color(1.0, 1.0, 1.0), tela, 9, true)
		return

	# Quando acerta no recorde: a onda sai e volta.
	var ping: float = p_ping_pong(p)
	var envelope: float = sin(p * PI)
	envelope = pow(max(0.0, envelope), 0.65)

	var raio_min: float = tela.y * 0.080
	var raio_max: float = max(tela.x, tela.y) * 0.500
	var raio_frente: float = lerpf(raio_min, raio_max, ping)
	var raio_tras: float = max(raio_min * 0.65, raio_frente - tela.y * 0.060)

	var largura_amarela: float = max(6.0, tela.y * 0.018)
	var largura_branca: float = max(4.0, tela.y * 0.012)

	var alpha_amarelo: float = 0.72 * envelope * forca
	var alpha_branco: float = 0.54 * envelope * forca

	_desenhar_faixa_onda_record(
		origem,
		raio_tras,
		largura_branca,
		Color(1.0, 1.0, 1.0, alpha_branco)
	)

	_desenhar_faixa_onda_record(
		origem,
		raio_frente,
		largura_amarela,
		Color(1.0, 0.80, 0.02, alpha_amarelo)
	)

	var flash: float = 0.20 * envelope * forca
	luz_onda_ctrl.draw_circle(
		origem,
		tela.y * 0.075,
		Color(1.0, 0.88, 0.18, flash)
	)

	luz_onda_ctrl.draw_circle(
		origem,
		tela.y * 0.045,
		Color(1.0, 1.0, 1.0, flash * 0.45)
	)



func _desenhar_faixa_onda_record(origem: Vector2, raio: float, largura: float, cor: Color) -> void:
	if luz_onda_ctrl == null:
		return
	if largura <= 0.0:
		return

	luz_onda_ctrl.draw_arc(
		origem,
		raio,
		0.0,
		TAU,
		128,
		cor,
		largura,
		true
	)


func _desenhar_onda_record(origem: Vector2, p: float, forca: float, tela: Vector2) -> void:
	var fade: float = 1.0 - p
	var raio_base: float = lerpf(tela.y * 0.030, tela.y * 0.52, p)
	var largura_amarela: float = max(4.0, tela.y * 0.0105) * (1.0 + 0.10 * (forca - 1.0))
	var largura_branca: float = max(2.5, largura_amarela * 0.48)
	var espacamento: float = tela.y * 0.072

	# glow de origem bem mais limpo e preso na cesta
	luz_onda_ctrl.draw_circle(
		origem,
		raio_base * 0.18,
		Color(1.0, 0.92, 0.72, 0.16 * fade * forca)
	)

	for i in range(4):
		var raio: float = raio_base + float(i) * espacamento
		var alpha: float = (0.34 - float(i) * 0.055) * fade * forca

		if alpha <= 0.0:
			continue

		# faixa amarela
		_desenhar_faixa_onda_record(
			origem,
			raio,
			largura_amarela,
			Color(1.0, 0.80, 0.05, alpha)
		)

		# faixa branca logo na sequência
		_desenhar_faixa_onda_record(
			origem,
			raio + largura_amarela * 0.78,
			largura_branca,
			Color(1.0, 1.0, 1.0, alpha * 0.95)
		)

	# halo externo leve, sem bagunça
	var halo_alpha: float = 0.09 * fade * forca
	if halo_alpha > 0.0:
		_desenhar_faixa_onda_record(
			origem,
			raio_base + espacamento * 0.35,
			max(1.5, largura_amarela * 0.28),
			Color(1.0, 0.96, 0.82, halo_alpha)
		)



func _desenhar_onda_normal(
	origem: Vector2,
	p: float,
	forca: float,
	dourado: bool,
	cor_ring: Color,
	cor_glow: Color,
	tela: Vector2,
	combo_nivel: int = 1,
	raio_ida_volta: bool = false
) -> void:
	var p_raio: float = p

	# De 9 para cima o raio também sai e volta.
	if raio_ida_volta:
		if p <= 0.5:
			p_raio = p * 2.0
		else:
			p_raio = (1.0 - p) * 2.0

	var fade: float = 1.0 - p
	if raio_ida_volta:
		fade = 1.0 - abs(p - 0.5) * 0.85

	var raio_max_tela: float = max(tela.x, tela.y)
	var raio_base: float = lerpf(raio_max_tela * 0.065, raio_max_tela * 0.62, p_raio)

	var num_aneis: int = 4
	if dourado:
		num_aneis = 6
	if combo_nivel >= 9:
		num_aneis = 7
	if combo_nivel >= 13:
		num_aneis = 9

	var flash_alpha: float = 0.20 * fade * forca
	if combo_nivel >= 9:
		flash_alpha *= 1.25
	if combo_nivel >= 13:
		flash_alpha *= 1.45

	luz_onda_ctrl.draw_circle(
		origem,
		raio_base * 0.32,
		Color(cor_glow.r, cor_glow.g, cor_glow.b, flash_alpha * 0.6)
	)

	for i in range(num_aneis):
		var raio: float = raio_base + float(i) * tela.y * 0.052
		var alpha: float = (0.34 - float(i) * 0.038) * fade * forca
		if combo_nivel >= 9:
			alpha *= 1.15
		if combo_nivel >= 13:
			alpha *= 1.35

		if alpha <= 0.0:
			continue

		var largura: float = max(3.0, tela.y * (0.006 + float(i) * 0.0015)) * (1.0 + 0.3 * (forca - 1.0))

		luz_onda_ctrl.draw_arc(
			origem,
			raio,
			0.0,
			TAU,
			128,
			Color(cor_ring.r, cor_ring.g, cor_ring.b, alpha),
			largura,
			true
		)

		luz_onda_ctrl.draw_arc(
			origem,
			raio + 7.0,
			0.0,
			TAU,
			128,
			Color(cor_glow.r, cor_glow.g, cor_glow.b, alpha * 0.42),
			max(1.5, largura * 0.42),
			true
		)

	# Raio extra no roxo e vermelho.
	if combo_nivel >= 9:
		var extra_alpha: float = 0.18 * fade * forca
		var extra_raio: float = raio_base * 0.72

		luz_onda_ctrl.draw_arc(
			origem,
			extra_raio,
			0.0,
			TAU,
			128,
			Color(cor_glow.r, cor_glow.g, cor_glow.b, extra_alpha),
			max(3.0, tela.y * 0.009),
			true
		)

	if combo_nivel >= 13:
		var extra2_alpha: float = 0.22 * fade * forca
		var extra2_raio: float = raio_base * 1.15

		luz_onda_ctrl.draw_arc(
			origem,
			extra2_raio,
			0.0,
			TAU,
			128,
			Color(cor_ring.r, cor_ring.g, cor_ring.b, extra2_alpha),
			max(4.0, tela.y * 0.011),
			true
		)

	var quantidade_raios: int = 10
	if combo_nivel >= 9:
		quantidade_raios = 14
	if combo_nivel >= 13:
		quantidade_raios = 18

	for i in range(quantidade_raios):
		var ang: float = -PI * 0.92 + TAU * float(i) / float(quantidade_raios)
		var dir := Vector2(cos(ang), sin(ang))

		var inicio: Vector2 = origem + dir * (raio_base * 0.10)
		var fim: Vector2 = origem + dir * (raio_base * 1.15)

		var a: float = 0.20 * fade * forca
		var w: float = max(2.0, tela.y * 0.004)

		luz_onda_ctrl.draw_line(
			inicio,
			fim,
			Color(cor_ring.r, cor_ring.g, cor_ring.b, a),
			w,
			true
		)

		luz_onda_ctrl.draw_line(
			inicio,
			fim,
			Color(cor_glow.r, cor_glow.g, cor_glow.b, a * 0.36),
			max(1.0, w * 0.38),
			true
		)



func _desenhar_onda_inversa(origem: Vector2, p: float, forca: float, cor_ring: Color, cor_glow: Color, tela: Vector2) -> void:
	# Raio GRANDE -> PEQUENO (da periferia para dentro).
	var raio_base: float = lerpf(tela.y * 0.85, tela.x * 0.06, p)
	# Brilha mais conforme converge.
	var intensidade: float = (0.25 + 0.75 * p) * forca

	var num_aneis: int = 3
	for i in range(num_aneis):
		var raio: float = raio_base + float(i) * tela.y * 0.05
		var alpha: float = (0.40 - float(i) * 0.10) * intensidade
		if alpha <= 0.0:
			continue
		var largura: float = max(3.0, tela.y * (0.007 + float(i) * 0.0015))

		luz_onda_ctrl.draw_arc(
			origem,
			raio,
			0.0,
			TAU,
			128,
			Color(cor_ring.r, cor_ring.g, cor_ring.b, alpha),
			largura,
			true
		)

		luz_onda_ctrl.draw_arc(
			origem,
			max(2.0, raio - 6.0),
			0.0,
			TAU,
			128,
			Color(cor_glow.r, cor_glow.g, cor_glow.b, alpha * 0.4),
			max(1.5, largura * 0.4),
			true
		)

	# Raios apontando para DENTRO
	var quantidade_raios: int = 12
	for i in range(quantidade_raios):
		var ang: float = TAU * float(i) / float(quantidade_raios)
		var dir := Vector2(cos(ang), sin(ang))

		var fim: Vector2 = origem + dir * raio_base
		var inicio: Vector2 = origem + dir * (raio_base + tela.y * 0.06)

		var a: float = 0.22 * intensidade
		var w: float = max(2.0, tela.y * 0.0035)

		luz_onda_ctrl.draw_line(
			inicio,
			fim,
			Color(cor_ring.r, cor_ring.g, cor_ring.b, a),
			w,
			true
		)

	# Flash de convergência no centro, no fim
	if p > 0.78:
		var f: float = (p - 0.78) / 0.22
		var raio_flash: float = lerpf(tela.x * 0.02, tela.x * 0.14, f)
		luz_onda_ctrl.draw_circle(origem, raio_flash, Color(cor_glow.r, cor_glow.g, cor_glow.b, 0.5 * f * forca))
		luz_onda_ctrl.draw_circle(origem, raio_flash * 0.5, Color(1, 1, 1, 0.6 * f * forca))


# =====================================================================
func _ler_quantidade_da_opening() -> void:
	var qtd := num_jogadores
	if get_tree().has_meta("num_jogadores"):
		qtd = int(get_tree().get_meta("num_jogadores"))
	num_jogadores = clampi(qtd, 1, 4)
	_pontos = [0, 0, 0, 0]
	_nomes = NOMES_PADRAO.duplicate()
	_turnos_finalizados = [false, false, false, false]
	_jogador_atual = 0
	_resetar_estado_shootout_total()


# =====================================================================
# AUTO-MONTAGEM — layout estilo referência
# =====================================================================
func _montar_cena() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Fundo
	if has_node("Fundo"):
		fundo = $Fundo
	else:
		fundo = TextureRect.new()
		fundo.name = "Fundo"
		add_child(fundo)
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fundo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Áudio
	musica_fundo = _garantir_audio("MusicaFundo")
	som_cesta = _garantir_audio("SomCesta")
	som_apito = _garantir_audio("SomApito")
	som_fim = _garantir_audio("SomFim")
	som_good_player = _garantir_audio("SomGoodPlayer")

	# HUD
	if has_node("HUD"):
		_hud = $HUD
	else:
		_hud = CanvasLayer.new()
		_hud.name = "HUD"
		_hud.layer = 5
		add_child(_hud)

		# --- RECORDE (topo-esquerda) ---
	painel_record = Panel.new()
	painel_record.name = "PainelRecorde"
	painel_record.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painel_record.add_theme_stylebox_override("panel", _estilo_painel_recorde())
	_hud.add_child(painel_record)

	lbl_high_titulo = _novo_label(_hud, COR_AZUL, 3, "RECORDE")
	lbl_high_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	lbl_high_valor = _novo_label_seg(_hud, COR_AZUL, "0000")
	lbl_high_valor.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	# --- PLACAR GERAL (topo-direita) ---
	painel_players_score = Panel.new()
	painel_players_score.name = "PainelPlayersScore"
	painel_players_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painel_players_score.add_theme_stylebox_override("panel", _estilo_faixa_placar())
	_hud.add_child(painel_players_score)

	lbl_players_titulo = _novo_label(_hud, COR_AZUL, 3, "PLACAR GERAL")
	lbl_players_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	box_players_score = VBoxContainer.new()
	box_players_score.name = "BoxPlayersScore"
	box_players_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box_players_score.alignment = BoxContainer.ALIGNMENT_CENTER
	box_players_score.add_theme_constant_override("separation", 3)
	_hud.add_child(box_players_score)

	# --- ANEL DO CRONÔMETRO ---
	crono_ring = Control.new()
	crono_ring.name = "CronoRing"
	crono_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(crono_ring)
	crono_ring.draw.connect(_desenhar_crono_ring)

	lbl_tempo_titulo = _novo_label(_hud, COR_VERDE_DISPLAY, 3, "TEMPO")
	lbl_tempo_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_tempo_titulo.add_theme_color_override("font_outline_color", Color(0.24, 0.07, 0.0))

	lbl_crono = _novo_label(_hud, COR_VERDE_DISPLAY, 8, "0")
	lbl_crono.add_theme_color_override("font_outline_color", Color(0.28, 0.08, 0.0))

	# --- BLOCO ANTIGO DA ESQUERDA (REMOVIDO VISUALMENTE) ---
	painel_score_pass = Panel.new()
	painel_score_pass.name = "PainelScorePass"
	painel_score_pass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painel_score_pass.add_theme_stylebox_override("panel", _estilo_faixa_placar())
	painel_score_pass.visible = false
	_hud.add_child(painel_score_pass)

	lbl_meta_titulo = _novo_label(_hud, COR_AMBAR, 3, "")
	lbl_meta_titulo.visible = false

	lbl_meta_valor = _novo_label_seg(_hud, COR_AMBAR, "")
	lbl_meta_valor.visible = false

	# --- PONTOS ATUAIS (novo bloco principal) ---
	painel_current_score = Panel.new()
	painel_current_score.name = "PainelCurrentScore"
	painel_current_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painel_current_score.add_theme_stylebox_override("panel", _estilo_faixa_placar())
	_hud.add_child(painel_current_score)

	fx_fogo_pontos_atuais = Control.new()
	fx_fogo_pontos_atuais.name = "FogoPontosAtuaisFx"
	fx_fogo_pontos_atuais.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(fx_fogo_pontos_atuais)
	if not fx_fogo_pontos_atuais.draw.is_connected(_desenhar_fogo_pontos_atuais.bind(fx_fogo_pontos_atuais)):
		fx_fogo_pontos_atuais.draw.connect(_desenhar_fogo_pontos_atuais.bind(fx_fogo_pontos_atuais))

	lbl_atual_titulo = _novo_label(_hud, COR_VERDE_DISPLAY, 3, "PONTOS")
	lbl_atual_pontos = _novo_label_seg(_hud, COR_VERDE_DISPLAY, "00")

	# --- CARD CENTRAL ANTIGO NÃO SERÁ MAIS USADO ---
	card_jogando = Panel.new()
	card_jogando.name = "CardJogando"
	card_jogando.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_jogando.visible = false
	_hud.add_child(card_jogando)

	var vj := VBoxContainer.new()
	vj.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vj.offset_left = 10
	vj.offset_right = -10
	vj.offset_top = 8
	vj.offset_bottom = -8
	vj.alignment = BoxContainer.ALIGNMENT_CENTER
	vj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_jogando.add_child(vj)
	card_jogando.set_meta("vbox", vj)

	# --- CONTAINER INFERIOR DOS PLAYERS ---
	col_players = HBoxContainer.new()
	col_players.name = "ColPlayersRodape"
	col_players.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col_players.alignment = BoxContainer.ALIGNMENT_CENTER
	col_players.add_theme_constant_override("separation", 18)
	_hud.add_child(col_players)

	# --- LOGO INFERIOR ESQUERDA (hard coded por enquanto) ---
	logo_canto_fx = Control.new()
	logo_canto_fx.name = "LogoCantoFx"
	logo_canto_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_canto_fx.z_index = -2
	_hud.add_child(logo_canto_fx)
	if not logo_canto_fx.draw.is_connected(_desenhar_logo_canto_fx):
		logo_canto_fx.draw.connect(_desenhar_logo_canto_fx)

	logo_canto_img = TextureRect.new()
	logo_canto_img.name = "LogoCantoInferior"
	logo_canto_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_canto_img.z_index = -1
	logo_canto_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_canto_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_canto_img.material = _material_logo_canto()
	_hud.add_child(logo_canto_img)
	_carregar_logo_canto_inferior()
	
	# Camada de efeitos (acima do HUD)
	if has_node("EfeitosLayer"):
		_efeitos = $EfeitosLayer
	else:
		_efeitos = CanvasLayer.new()
		_efeitos.name = "EfeitosLayer"
		_efeitos.layer = 12
		add_child(_efeitos)



func _garantir_audio(nome: String) -> AudioStreamPlayer:
	if has_node(nome):
		return get_node(nome)
	var a := AudioStreamPlayer.new()
	a.name = nome
	add_child(a)
	return a



func _novo_label(pai: Node, cor: Color, outline: int, txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", cor)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	_aplicar_fonte(l)
	pai.add_child(l)
	return l



func _novo_label_seg(pai: Node, cor: Color, txt: String) -> Label:
	# Placar estilo display 7-seg (cor forte + glow via outline da própria cor).
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", cor)
	l.add_theme_color_override("font_outline_color", Color(cor.r * 0.25, cor.g * 0.25, cor.b * 0.25, 0.9))
	l.add_theme_constant_override("outline_size", 11)
	_aplicar_fonte(l)
	pai.add_child(l)
	return l



func _aplicar_fonte(lbl: Control) -> void:
	if caminho_fonte == "":
		return
	var f := load(caminho_fonte)
	if f is Font:
		lbl.add_theme_font_override("font", f)



# =====================================================================
# LAYOUT RESPONSIVO
# =====================================================================
func _fs(frac: float) -> int:
	return max(12, int(get_viewport_rect().size.y * frac))



func _duracao_turno_atual() -> float:
	return tempo_shootout_desempate if _shootout_ativo else tempo_partida



func _raio_tela_max() -> float:
	# Usa a MAIOR dimensão da tela (agora é a LARGURA, no modo horizontal)
	# para as ondas sempre alcançarem as bordas — antes ficavam limitadas
	# a uma fração da altura, que sobrava no retrato mas fica curta na
	# tela larga.
	var tela := get_viewport_rect().size
	return max(tela.x, tela.y)



func _ancorar(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = l; c.anchor_top = t; c.anchor_right = r; c.anchor_bottom = b
	c.offset_left = 0; c.offset_top = 0; c.offset_right = 0; c.offset_bottom = 0



func _layout_responsivo() -> void:
	if _hud == null:
		return

	# -----------------------------
	# RECORDE — topo esquerdo
	# agora com background próprio, elegante e diferente dos pontos
	# -----------------------------
	if painel_record != null:
		painel_record.visible = true
		painel_record.add_theme_stylebox_override("panel", _estilo_painel_recorde())
		_ancorar(painel_record, 0.026, 0.026, 0.318, 0.218)

	_ancorar(lbl_high_titulo, 0.048, 0.046, 0.296, 0.098)
	_ancorar(lbl_high_valor, 0.044, 0.090, 0.300, 0.205)

	lbl_high_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_high_valor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_high_titulo.add_theme_font_size_override("font_size", _fs(0.031))
	lbl_high_valor.add_theme_font_size_override("font_size", _fs(0.100))

	# -----------------------------
	# BLOCO ANTIGO DO PLACAR GERAL — REMOVIDO
	# Não usamos mais card/fundo/título de ranking.
	# O VBox abaixo vira apenas LISTA FIXA dos players.
	# -----------------------------
	if painel_players_score != null:
		painel_players_score.visible = false
		_ancorar(painel_players_score, 0.0, 0.0, 0.0, 0.0)

	if lbl_players_titulo != null:
		lbl_players_titulo.visible = false
		_ancorar(lbl_players_titulo, 0.0, 0.0, 0.0, 0.0)

	# -----------------------------
	# PONTOS ATUAIS — topo direito
	# contra-ponto visual do recorde
	# -----------------------------
	if painel_current_score != null:
		painel_current_score.visible = true
		painel_current_score.add_theme_stylebox_override("panel", _estilo_painel_pontos_atual())
		_ancorar(painel_current_score, 0.705, 0.026, 0.970, 0.218)

	if fx_fogo_pontos_atuais != null:
		# O FX usa EXATAMENTE a mesma âncora do card de PONTOS.
		# Assim a borda de fogo nasce alinhada com o painel real, sem ficar
		# deslocada ou maior de um lado. O desenho pode passar para fora
		# porque o Control não usa clip_contents.
		_ancorar(fx_fogo_pontos_atuais, 0.705, 0.026, 0.970, 0.218)

	_ancorar(lbl_atual_titulo, 0.728, 0.046, 0.947, 0.102)
	_ancorar(lbl_atual_pontos, 0.720, 0.096, 0.955, 0.208)

	lbl_atual_titulo.text = "PONTOS"
	lbl_atual_titulo.add_theme_font_size_override("font_size", _fs(0.030))
	lbl_atual_pontos.add_theme_font_size_override("font_size", _fs(0.092))

	# -----------------------------
	# PLAYERS — lista fixa à direita, abaixo dos pontos
	# Sem ranking dinâmico: J1/J2/J3/J4 sempre no mesmo espaço.
	# -----------------------------
	if box_players_score != null:
		box_players_score.visible = true
		box_players_score.modulate.a = 1.0
		box_players_score.alignment = BoxContainer.ALIGNMENT_BEGIN
		box_players_score.clip_contents = false
		box_players_score.add_theme_constant_override("separation", int(clampf(get_viewport_rect().size.y * 0.009, 6.0, 9.0)))
		_ancorar(box_players_score, 0.712, 0.235, 0.978, 0.920)

	# -----------------------------
	# CRONÔMETRO + TEMPO
	# O texto TEMPO agora fica ACIMA do cronômetro, deixando a leitura
	# natural: título em cima, número grande dentro do anel.
	# -----------------------------
	if lbl_tempo_titulo != null:
		# TEMPO mais alto e com folga real antes do anel do cronômetro.
		# Antes encostava/entrava no anel; agora há respiro entre título e círculo.
		_ancorar(lbl_tempo_titulo, 0.382, 0.016, 0.618, 0.068)
		lbl_tempo_titulo.add_theme_font_size_override("font_size", _fs(0.038))

	# Cronômetro levemente mais baixo para não brigar com o título TEMPO.
	_ancorar(crono_ring, 0.305, 0.092, 0.695, 0.382)
	_ancorar(lbl_crono, 0.305, 0.105, 0.695, 0.367)
	lbl_crono.add_theme_font_size_override("font_size", _fs(0.136))

	# -----------------------------
	# BLOCOS ANTIGOS DESATIVADOS
	# -----------------------------
	if painel_score_pass != null:
		painel_score_pass.visible = false
		_ancorar(painel_score_pass, 0.0, 0.0, 0.0, 0.0)

	if lbl_meta_titulo != null:
		lbl_meta_titulo.visible = false
		_ancorar(lbl_meta_titulo, 0.0, 0.0, 0.0, 0.0)

	if lbl_meta_valor != null:
		lbl_meta_valor.visible = false
		_ancorar(lbl_meta_valor, 0.0, 0.0, 0.0, 0.0)

	# -----------------------------
	# CARD CENTRAL ANTIGO E PLAYERS INFERIORES REMOVIDOS
	# -----------------------------
	if card_jogando != null:
		card_jogando.visible = false
		_ancorar(card_jogando, 0.0, 0.0, 0.0, 0.0)

	if col_players != null:
		col_players.visible = false
		col_players.modulate.a = 0.0
		_ancorar(col_players, 0.0, 0.0, 0.0, 0.0)

	# -----------------------------
	# LOGO INFERIOR ESQUERDA — destaque profissional
	# Maior, mais presente e com glow moderno, sem virar um card pesado.
	# -----------------------------
	if logo_canto_fx != null:
		_ancorar(logo_canto_fx, 0.006, 0.690, 0.342, 0.988)
		logo_canto_fx.visible = logo_canto_img != null and logo_canto_img.texture != null

	if logo_canto_img != null:
		_ancorar(logo_canto_img, 0.024, 0.735, 0.305, 0.955)
		logo_canto_img.visible = logo_canto_img.texture != null

	_atualizar_high_label()
	_ajustar_transicao_layout()
	_layout_combo_ui()
	_atualizar_scores_players_hud()



func _altura_card_player_lateral() -> float:
	return clampf(get_viewport_rect().size.y * 0.102, 78.0, 116.0)



func _largura_card_player_lateral() -> float:
	var tela_x: float = get_viewport_rect().size.x

	match num_jogadores:
		1:
			return clampf(tela_x * 0.248, 242.0, 365.0)
		2:
			return clampf(tela_x * 0.235, 224.0, 335.0)
		3:
			return clampf(tela_x * 0.218, 208.0, 306.0)
		_:
			return clampf(tela_x * 0.206, 198.0, 286.0)



# =====================================================================
# VISÃO DO TURNO
# =====================================================================
func _atualizar_visao_turno() -> void:
	_atualizar_card_jogando()
	_reconstruir_players()
	_atualizar_placar_labels()
	_atualizar_scores_players_hud()



func _atualizar_card_jogando() -> void:
	if card_jogando != null:
		card_jogando.visible = false



func _reconstruir_players() -> void:
	# Os cards antigos separados em 2 à esquerda e 2 à direita foram removidos.
	# Agora os jogadores aparecem somente nos cards novos do lado direito,
	# gerados por _atualizar_scores_players_hud().
	_player_cards.clear()

	if col_players == null:
		return

	for c in col_players.get_children():
		c.queue_free()

	col_players.visible = false
	col_players.modulate.a = 0.0



func _criar_mini_player(i: int) -> Panel:
	var cor: Color = CORES_PLAYERS[i % CORES_PLAYERS.size()]
	var fin: bool = bool(_turnos_finalizados[i])
	var eh_atual: bool = i == _jogador_atual

	var card := Panel.new()
	card.custom_minimum_size = Vector2(_largura_card_player_lateral(), _altura_card_player_lateral())
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.clip_contents = true

	card.add_theme_stylebox_override("panel", _estilo_card_led_player(cor, eh_atual, fin))
	card.modulate.a = 1.0 if eh_atual else (0.38 if not fin else 0.22)

	var h := HBoxContainer.new()
	h.name = "HBox"
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 16
	h.offset_right = -16
	h.offset_top = 10
	h.offset_bottom = -10
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 8)
	card.add_child(h)

	var dot_size: float = clampf(get_viewport_rect().size.y * 0.016, 10.0, 18.0)

	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(dot_size, dot_size)
	dot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = cor if eh_atual else Color(cor.r, cor.g, cor.b, 0.68)
	sb.set_corner_radius_all(999)
	sb.shadow_color = Color(cor.r, cor.g, cor.b, 0.85 if eh_atual else 0.14)
	sb.shadow_size = 12 if eh_atual else 2
	sb.anti_aliasing = true
	dot.add_theme_stylebox_override("panel", sb)
	h.add_child(dot)

	var nome := Label.new()
	nome.text = str(_nomes[i])
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nome.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nome.clip_text = true
	nome.add_theme_font_size_override("font_size", _fonte_nome_card_player_rodape())
	nome.add_theme_color_override("font_color", Color.WHITE if eh_atual else Color(0.84, 0.84, 0.84, 0.90))
	nome.add_theme_color_override("font_outline_color", Color.BLACK)
	nome.add_theme_constant_override("outline_size", 3)
	_aplicar_fonte(nome)
	h.add_child(nome)

	var score_box := Panel.new()
	score_box.name = "ScoreBox"
	score_box.custom_minimum_size = Vector2(_largura_capsula_pontos_player(), _altura_capsula_pontos_player())
	score_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	score_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_box.clip_contents = true
	score_box.add_theme_stylebox_override("panel", _estilo_capsula_pontos_player(cor, eh_atual, fin))
	if _record_booster_ativo and eh_atual:
		_adicionar_fogo_capsula_pontos(score_box, cor)
	h.add_child(score_box)

	var pts := Label.new()
	pts.text = "%02d" % int(_pontos[i])
	pts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pts.add_theme_font_size_override("font_size", _fonte_pontos_card_player_rodape())

	var cor_pts := cor if eh_atual else Color(0.82, 0.82, 0.82)
	if _record_booster_ativo and eh_atual:
		cor_pts = COR_RECORDE_CLARO

	pts.add_theme_color_override("font_color", cor_pts)
	pts.add_theme_color_override("font_outline_color", Color.BLACK)
	pts.add_theme_constant_override("outline_size", 4)
	_aplicar_fonte(pts)
	score_box.add_child(pts)

	return card



func _estilo_card_led_player(cor: Color, eh_atual: bool, fin: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()

	if eh_atual:
		sb.bg_color = Color(0.018, 0.030, 0.060, 0.92)
		sb.border_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 1.0)
		sb.shadow_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.62)
		sb.shadow_size = 32
		sb.set_border_width_all(3)
	elif fin:
		sb.bg_color = Color(0.015, 0.020, 0.035, 0.22)
		sb.border_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.16)
		sb.shadow_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.04)
		sb.shadow_size = 4
		sb.set_border_width_all(2)
	else:
		sb.bg_color = Color(0.018, 0.030, 0.060, 0.36)
		sb.border_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.34)
		sb.shadow_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.18)
		sb.shadow_size = 12
		sb.set_border_width_all(2)

	sb.set_corner_radius_all(999)
	sb.corner_detail = 32
	sb.set_content_margin_all(14)
	sb.anti_aliasing = true
	return sb



func _atualizar_placar_labels() -> void:
	if lbl_atual_pontos != null:
		lbl_atual_pontos.text = "%02d" % int(_pontos[_jogador_atual])

		if _record_booster_ativo:
			lbl_atual_pontos.add_theme_color_override("font_color", COR_RECORDE_CLARO)
			lbl_atual_pontos.add_theme_color_override("font_outline_color", Color(0.18, 0.03, 0.0))
		else:
			lbl_atual_pontos.add_theme_color_override("font_color", COR_VERDE_DISPLAY)
			lbl_atual_pontos.add_theme_color_override("font_outline_color", Color(0.28, 0.08, 0.0))

	if lbl_high_valor != null:
		lbl_high_valor.text = "%04d" % record_maximo

	_atualizar_scores_players_hud()



func _atualizar_high_label() -> void:
	if lbl_high_valor != null:
		lbl_high_valor.text = "%04d" % record_maximo



# =====================================================================
# ANEL DO CRONÔMETRO (desenhado)
# =====================================================================
func _desenhar_crono_ring() -> void:
	if crono_ring == null:
		return
	var r := crono_ring.size
	var c := r * 0.5
	var raio : float = min(r.x, r.y) * 0.42
	var frac := 1.0
	if tempo_partida > 0.0:
		frac = clampf(_tempo_restante / tempo_partida, 0.0, 1.0)

	# trilho de fundo
	crono_ring.draw_arc(c, raio, 0.0, TAU, 80, Color(0.10, 0.18, 0.30, 0.85), max(4.0, raio * 0.10), true)
	# glow externo
	for g in range(3):
		crono_ring.draw_arc(c, raio + g * 3.0, -PI/2.0, -PI/2.0 + TAU * frac, 80,
			Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.10 - g * 0.025),
			max(6.0, raio * 0.16), true)
	# anel ativo (verde) — esvazia no sentido horário a partir do topo
	var cor_anel := COR_VERDE_DISPLAY
	if _tempo_restante <= 10.0 and _rodando:
		cor_anel = Color(1.0, 0.35, 0.3)
	crono_ring.draw_arc(c, raio, -PI/2.0, -PI/2.0 + TAU * frac, 80, cor_anel, max(4.0, raio * 0.10), true)

	# "tracinhos" do mostrador (estilo referência)
	var n := 40
	for i in range(n):
		var ang := -PI/2.0 + TAU * float(i) / float(n)
		var aceso := float(i) / float(n) <= frac
		var p1 := c + Vector2(cos(ang), sin(ang)) * (raio * 1.18)
		var p2 := c + Vector2(cos(ang), sin(ang)) * (raio * 1.30)
		var cc := cor_anel if aceso else Color(0.18, 0.25, 0.35, 0.55)
		crono_ring.draw_line(p1, p2, Color(cc.r, cc.g, cc.b, 0.9 if aceso else 0.4), 2.0, true)



func _carregar_textura_generica(caminho: String) -> Texture2D:
	# Helper genérico de carregamento de imagem: tenta primeiro como
	# recurso normal do projeto (funciona pro logo padrão, que vem de
	# res://). Se não for um recurso reconhecido pelo ResourceLoader
	# (caso do logo customizado, salvo em user:// como bytes crus de
	# PNG/JPG escolhidos pelo usuário na tela de configuração), cai
	# pro carregamento via Image — que funciona com qualquer PNG/JPG
	# em disco, inclusive no executável exportado.
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


# =====================================================================
# LOGO INFERIOR ESQUERDA — hard coded por enquanto
# Futuramente esse caminho pode vir do config.
# =====================================================================
func _carregar_logo_canto_inferior() -> void:
	if logo_canto_img == null:
		return

	# Ordem de prioridade: 1) logo escolhido pelo usuário na tela de
	# configuração (F10) — pode ser um PNG/JPG de QUALQUER lugar do
	# PC dele, copiado para user:// na hora da escolha; 2) o hardcoded
	# do Inspector; 3) fallbacks antigos, por compatibilidade.
	var caminhos: Array = [
		_logo_empresa_config,
		caminho_logo_canto_hardcoded,
		"res://images/logo_lazer_sport.png",
		"res://images/logo_lazar_sport.png",
		"res://images/logoofi.png",
		"res://images/logo.png"
	]

	for caminho in caminhos:
		if str(caminho).strip_edges() == "":
			continue

		var tex := _carregar_textura_generica(str(caminho))
		if tex != null:
			logo_canto_img.texture = tex
			logo_canto_img.visible = true

			if logo_canto_fx != null:
				logo_canto_fx.visible = true
				logo_canto_fx.queue_redraw()

			return

	logo_canto_img.texture = null
	logo_canto_img.visible = false

	if logo_canto_fx != null:
		logo_canto_fx.visible = false



func _material_logo_canto() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.46, 0.04, 1.0);
uniform float pulse = 0.0;
uniform float alpha_mix = 0.84;
uniform float glow_strength = 0.22;
uniform float brightness = 1.10;
uniform float contrast = 1.15;
uniform float shine_strength = 0.24;
uniform float scan_strength = 0.032;
uniform float edge_softness = 0.965;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	float dx = abs(UV.x - 0.5) * 2.0;
	float dy = abs(UV.y - 0.5) * 2.0;

	// Fade bem discreto nas bordas: a logo suaviza com o fundo,
	// mas sem apagar o símbolo.
	float edge_x = 1.0 - smoothstep(edge_softness, 1.04, dx);
	float edge_y = 1.0 - smoothstep(edge_softness, 1.04, dy);
	float edge = edge_x * edge_y;

	// Contraste premium para a logo ficar presente na TV.
	vec3 cor = (tex.rgb - vec3(0.5)) * contrast + vec3(0.5);
	cor *= brightness;

	// Brilho quente interno controlado.
	float dist = distance(UV, vec2(0.5, 0.5));
	float center_glow = 1.0 - smoothstep(0.16, 0.74, dist);
	cor = mix(cor, glow_color.rgb, glow_strength * center_glow * tex.a);

	// Reflexo diagonal moderno, mais visível porém sem lavar a arte.
	float diagonal = UV.x + UV.y;
	float shine_pos = mix(-0.35, 2.35, pulse);
	float shine = 1.0 - smoothstep(0.0, 0.060, abs(diagonal - shine_pos));
	cor += glow_color.rgb * shine * shine_strength * tex.a;

	// Scanline finíssima só para textura digital.
	float scan = 0.5 + 0.5 * sin((UV.y * 96.0) + pulse * 6.28318);
	cor += glow_color.rgb * scan * scan_strength * tex.a;

	// Limite alto para evitar estouro, sem deixar apagado.
	cor = min(cor, vec3(1.0, 0.92, 0.78));

	COLOR = vec4(cor, tex.a * edge * alpha_mix);
}
"""

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("glow_color", COR_VERDE_DISPLAY)
	mat.set_shader_parameter("pulse", 0.0)
	mat.set_shader_parameter("alpha_mix", 0.84)
	mat.set_shader_parameter("glow_strength", 0.22)
	mat.set_shader_parameter("brightness", 1.10)
	mat.set_shader_parameter("contrast", 1.15)
	mat.set_shader_parameter("shine_strength", 0.24)
	mat.set_shader_parameter("scan_strength", 0.032)
	mat.set_shader_parameter("edge_softness", 0.965)
	return mat



func _atualizar_logo_canto(delta: float) -> void:
	if logo_canto_img == null or logo_canto_img.texture == null:
		return

	_logo_canto_t += delta

	if logo_canto_img.material is ShaderMaterial:
		var mat := logo_canto_img.material as ShaderMaterial
		var pulso: float = abs(sin(_logo_canto_t * 0.78))
		var respiro: float = 0.5 + 0.5 * sin(_logo_canto_t * 1.10)

		mat.set_shader_parameter("pulse", fposmod(_logo_canto_t * 0.135, 1.0))
		mat.set_shader_parameter("alpha_mix", 0.80 + 0.075 * pulso)
		mat.set_shader_parameter("glow_strength", 0.18 + 0.075 * respiro)
		mat.set_shader_parameter("brightness", 1.04 + 0.075 * pulso)
		mat.set_shader_parameter("contrast", 1.12 + 0.060 * pulso)
		mat.set_shader_parameter("shine_strength", 0.18 + 0.090 * respiro)
		mat.set_shader_parameter("scan_strength", 0.024 + 0.018 * pulso)
		mat.set_shader_parameter("edge_softness", 0.965)

	if logo_canto_fx != null:
		logo_canto_fx.queue_redraw()



func _desenhar_logo_canto_fx() -> void:
	if logo_canto_fx == null:
		return
	if logo_canto_img == null or logo_canto_img.texture == null:
		return

	var s: Vector2 = logo_canto_fx.size
	if s.x <= 4.0 or s.y <= 4.0:
		return

	var tempo: float = _logo_canto_t
	var pulso: float = 0.5 + 0.5 * sin(tempo * 1.10)
	var centro := Vector2(s.x * 0.45, s.y * 0.55)
	var raio_base: float = min(s.x, s.y) * 0.43

	# Base escura larga atrás: dá leitura profissional sem parecer um card quadrado.
	for i in range(5):
		var k: float = float(i) / 4.0
		var raio_sombra: float = raio_base * lerpf(1.08, 2.65, k)
		var alpha_sombra: float = lerpf(0.210, 0.018, k)
		logo_canto_fx.draw_circle(
			centro + Vector2(s.x * 0.014, s.y * 0.035),
			raio_sombra,
			Color(0.0, 0.0, 0.0, alpha_sombra)
		)

	# Aura laranja premium, forte o bastante para destacar o símbolo.
	for i in range(5):
		var k_glow: float = float(i) / 4.0
		var raio_glow: float = raio_base * lerpf(0.96, 2.15, k_glow)
		var alpha_glow: float = lerpf(0.155, 0.018, k_glow) * (0.88 + 0.12 * pulso)
		logo_canto_fx.draw_arc(
			centro,
			raio_glow,
			-0.70 + tempo * 0.13,
			2.90 + tempo * 0.13,
			128,
			Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, alpha_glow),
			max(2.0, s.y * lerpf(0.012, 0.004, k_glow)),
			true
		)

	# Contra brilho branco/quente bem fino para dar acabamento de marca.
	logo_canto_fx.draw_arc(
		centro,
		raio_base * 1.10,
		0.18 + tempo * 0.18,
		1.58 + tempo * 0.18,
		96,
		Color(1.0, 0.92, 0.72, 0.090 + 0.035 * pulso),
		max(1.3, s.y * 0.0045),
		true
	)

	# Linha neon inferior, integrando com o piso/fundo da arte.
	var y: float = s.y * (0.705 + 0.010 * sin(tempo * 0.90))
	logo_canto_fx.draw_line(
		Vector2(s.x * 0.130, y),
		Vector2(s.x * 0.885, y - s.y * 0.045),
		Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.175 + 0.045 * pulso),
		max(2.0, s.y * 0.010),
		true
	)

	logo_canto_fx.draw_line(
		Vector2(s.x * 0.180, y + s.y * 0.030),
		Vector2(s.x * 0.745, y + s.y * 0.002),
		Color(1.0, 0.90, 0.64, 0.070 + 0.025 * pulso),
		max(1.0, s.y * 0.004),
		true
	)

	# Hot spot controlado atrás do símbolo.
	logo_canto_fx.draw_circle(
		centro + Vector2(s.x * 0.065, -s.y * 0.060),
		raio_base * 0.38,
		Color(1.0, 0.58, 0.12, 0.060 + 0.030 * pulso)
	)



# =====================================================================
# ESTILOS
# =====================================================================
func _estilo_faixa_placar() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.018, 0.035, 0.075, 0.94)
	sb.border_color = Color(COR_AZUL.r, COR_AZUL.g, COR_AZUL.b, 1.0)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(34)
	sb.corner_detail = 24
	sb.set_content_margin_all(18)
	sb.shadow_color = Color(COR_AZUL.r, COR_AZUL.g, COR_AZUL.b, 0.60)
	sb.shadow_size = 32
	sb.anti_aliasing = true
	return sb



func _estilo_painel_recorde() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()

	# Mais "premium" que os pontos: dourado/âmbar com fundo escuro,
	# borda forte e brilho mais quente.
	sb.bg_color = Color(0.060, 0.032, 0.012, 0.91)
	sb.border_color = Color(COR_RECORDE_CLARO.r, COR_RECORDE_CLARO.g, COR_RECORDE_CLARO.b, 0.96)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(28)
	sb.corner_detail = 24
	sb.set_content_margin_all(18)
	sb.shadow_color = Color(COR_RECORDE_BRILHO.r, COR_RECORDE_BRILHO.g, COR_RECORDE_BRILHO.b, 0.52)
	sb.shadow_size = 30
	sb.anti_aliasing = true
	return sb



func _estilo_painel_pontos_atual() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.018, 0.030, 0.060, 0.90)
	sb.border_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 1.0)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(999)
	sb.corner_detail = 32
	sb.set_content_margin_all(18)
	sb.shadow_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.62)
	sb.shadow_size = 34
	sb.anti_aliasing = true
	return sb



func _estilo_card_jogando(cor: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(cor.r * 0.14, cor.g * 0.14, cor.b * 0.14, 0.86)
	sb.border_color = Color(cor.r, cor.g, cor.b, 1.0)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(24)
	sb.corner_detail = 14
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(cor.r, cor.g, cor.b, 0.50)
	sb.shadow_size = 20
	sb.anti_aliasing = true
	return sb



func _estilo_mini_player(cor: Color, fin: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()

	if fin:
		sb.bg_color = Color(0.03, 0.03, 0.05, 0.56)
		sb.border_color = Color(0.44, 0.44, 0.50, 0.30)
		sb.shadow_color = Color(0.0, 0.0, 0.0, 0.14)
		sb.shadow_size = 4
	else:
		sb.bg_color = Color(cor.r * 0.09, cor.g * 0.09, cor.b * 0.09, 0.62)
		sb.border_color = Color(cor.r, cor.g, cor.b, 0.60)
		sb.shadow_color = Color(cor.r, cor.g, cor.b, 0.18)
		sb.shadow_size = 10

	sb.set_border_width_all(2)
	sb.set_corner_radius_all(20)
	sb.corner_detail = 14
	sb.set_content_margin_all(8)
	sb.anti_aliasing = true
	return sb



func _estilo_capsula_pontos_player(cor: Color, eh_atual: bool, fin: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()

	if fin and not eh_atual:
		sb.bg_color = Color(0.055, 0.060, 0.080, 0.42)
		sb.border_color = Color(0.45, 0.45, 0.50, 0.18)
		sb.shadow_color = Color(0.0, 0.0, 0.0, 0.0)
		sb.shadow_size = 0
	elif _record_booster_ativo and eh_atual:
		sb.bg_color = Color(0.14, 0.04, 0.01, 0.94)
		sb.border_color = Color(1.0, 0.74, 0.18, 1.0)
		sb.shadow_color = Color(1.0, 0.42, 0.02, 0.56)
		sb.shadow_size = 20
	else:
		sb.bg_color = Color(0.012, 0.020, 0.040, 0.90)
		sb.border_color = Color(cor.r, cor.g, cor.b, 0.98 if eh_atual else 0.42)
		sb.shadow_color = Color(cor.r, cor.g, cor.b, 0.38 if eh_atual else 0.10)
		sb.shadow_size = 14 if eh_atual else 3

	sb.set_border_width_all(2)
	sb.set_corner_radius_all(999)
	sb.corner_detail = 30
	sb.set_content_margin_all(8)
	sb.anti_aliasing = true
	return sb



func _largura_capsula_pontos_player() -> float:
	var tela_x: float = get_viewport_rect().size.x

	match num_jogadores:
		1:
			return clampf(tela_x * 0.066, 64.0, 98.0)
		2:
			return clampf(tela_x * 0.061, 60.0, 90.0)
		3:
			return clampf(tela_x * 0.056, 56.0, 82.0)
		_:
			return clampf(tela_x * 0.052, 52.0, 76.0)



func _altura_capsula_pontos_player() -> float:
	return clampf(_altura_card_player_lateral() * 0.62, 42.0, 68.0)



func _adicionar_fogo_capsula_pontos(score_box: Panel, cor: Color) -> void:
	var fire := Control.new()
	fire.name = "RecordFireFx"
	fire.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fire.z_index = 0
	score_box.add_child(fire)
	if not fire.draw.is_connected(_desenhar_fogo_capsula_pontos.bind(fire, cor)):
		fire.draw.connect(_desenhar_fogo_capsula_pontos.bind(fire, cor))



func _queue_redraw_fire_pontos_cards() -> void:
	for card in _player_cards:
		if card == null or not is_instance_valid(card):
			continue
		var score_box: Panel = card.get_node_or_null("HBox/ScoreBox")
		if score_box == null:
			continue
		var fire := score_box.get_node_or_null("RecordFireFx")
		if fire != null:
			fire.queue_redraw()



func _desenhar_chama_direcional(host: Control, base_pos: Vector2, dir_cauda: Vector2, altura: float, largura_base: float, tempo: float, semente: float, intensidade: float = 1.0) -> void:
	# Versão generalizada do cometa — antes só apontava pra CIMA. Agora
	# a cauda pode apontar em qualquer direção, o que permite "envolver"
	# o card inteiro em fogo: uma base embaixo com cauda subindo, e
	# bases nas laterais com cauda apontando pra dentro, formando um
	# anel contínuo em vez de uma chama solitária no centro.
	var dir: Vector2 = dir_cauda.normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)

	var raio_bola: float = largura_base * 0.40
	var centro_bola: Vector2 = base_pos

	host.draw_circle(centro_bola, raio_bola * 2.1, Color(1.0, 0.40, 0.03, 0.14 * intensidade))

	var segmentos: int = 5
	var topo: Vector2 = base_pos + dir * altura

	var contorno := PackedVector2Array()
	var pts_esq: Array = []
	var pts_dir: Array = []
	for i in range(segmentos + 1):
		var t: float = float(i) / float(segmentos)
		var centro_seg: Vector2 = base_pos.lerp(topo, t)
		var largura_t: float = lerpf(largura_base * 0.52, 0.0, pow(t, 0.72))
		var sway: float = sin(tempo * (2.6 + t * 2.0) + semente + t * 4.0) * largura_base * 0.16 * t
		var offset_sway: Vector2 = dir * sway
		pts_esq.append(centro_seg - perp * largura_t + offset_sway)
		pts_dir.append(centro_seg + perp * largura_t + offset_sway)
	for pt in pts_esq:
		contorno.append(pt)
	for i in range(pts_dir.size() - 1, -1, -1):
		contorno.append(pts_dir[i])
	host.draw_colored_polygon(contorno, Color(1.0, 0.34, 0.03, 0.62 * intensidade))

	var contorno_in := PackedVector2Array()
	var pts_esq_in: Array = []
	var pts_dir_in: Array = []
	var topo_in: Vector2 = base_pos + dir * (altura * 1.10)
	for i in range(segmentos + 1):
		var t: float = float(i) / float(segmentos)
		var centro_seg: Vector2 = base_pos.lerp(topo_in, t)
		var largura_t: float = lerpf(largura_base * 0.30, 0.0, pow(t, 0.68))
		var sway: float = sin(tempo * (3.4 + t * 2.4) + semente * 1.3 + t * 5.0) * largura_base * 0.12 * t
		var offset_sway: Vector2 = dir * sway
		pts_esq_in.append(centro_seg - perp * largura_t + offset_sway)
		pts_dir_in.append(centro_seg + perp * largura_t + offset_sway)
	for pt in pts_esq_in:
		contorno_in.append(pt)
	for i in range(pts_dir_in.size() - 1, -1, -1):
		contorno_in.append(pts_dir_in[i])
	host.draw_colored_polygon(contorno_in, Color(1.0, 0.86, 0.30, 0.55 * intensidade))

	var flicker: float = 0.75 + 0.25 * abs(sin(tempo * 9.0 + semente))
	host.draw_circle(centro_bola, raio_bola, Color(1.0, 0.42, 0.04, 0.85 * intensidade))
	host.draw_circle(centro_bola, raio_bola * 0.62, Color(1.0, 0.80, 0.28, 0.80 * intensidade * flicker))
	host.draw_circle(centro_bola - perp * (raio_bola * 0.12) - dir * (raio_bola * 0.15), raio_bola * 0.26, Color(1.0, 0.98, 0.88, 0.75 * intensidade * flicker))


func _desenhar_chama_cometa(host: Control, cx: float, base_y: float, altura: float, largura_base: float, tempo: float, semente: float, intensidade: float = 1.0) -> void:
	# Mantida por compatibilidade (usada na cápsula do player) — agora
	# é só um atalho pra versão direcional, apontando pra CIMA.
	_desenhar_chama_direcional(host, Vector2(cx, base_y), Vector2.UP, altura, largura_base, tempo, semente, intensidade)


func _obter_pontos_borda_fogo(host: Control, s: Vector2, passo: float) -> Array:
	var id: int = host.get_instance_id()
	if _cache_bordas_fogo.has(id):
		var cache: Dictionary = _cache_bordas_fogo[id]
		if cache["tam"].distance_to(s) < 1.0 and is_equal_approx(cache["passo"], passo):
			return cache["pontos"]

	var pontos: Array = []
	_acumular_pontos_borda_fogo(pontos, Vector2(0, 0), Vector2(s.x, 0), Vector2(0, -1), passo)
	_acumular_pontos_borda_fogo(pontos, Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(1, 0), passo)
	_acumular_pontos_borda_fogo(pontos, Vector2(s.x, s.y), Vector2(0, s.y), Vector2(0, 1), passo)
	_acumular_pontos_borda_fogo(pontos, Vector2(0, s.y), Vector2(0, 0), Vector2(-1, 0), passo)

	_cache_bordas_fogo[id] = {"tam": s, "passo": passo, "pontos": pontos}
	return pontos


func _desenhar_fogo_perimetro_card(host: Control, s: Vector2) -> void:
	# OTIMIZADO: a lista de pontos da borda agora é CACHEADA (só
	# recalcula se o tamanho do card mudar de verdade) em vez de ser
	# reconstruída do zero a cada frame — isso sozinho já elimina boa
	# parte do trabalho por frame. O espaçamento entre línguas também
	# aumentou um pouco (menos línguas, mesma cobertura visual).
	var tempo: float = _record_booster_pulso
	var espessura: float = clampf(min(s.x, s.y) * 0.15, 8.0, 24.0)
	var passo: float = clampf(min(s.x, s.y) * 0.085, 10.0, 18.0)

	var pontos: Array = _obter_pontos_borda_fogo(host, s, passo)
	var largura_lingua: float = passo * 1.7

	for i in range(pontos.size()):
		var info: Dictionary = pontos[i]
		var pt: Vector2 = info["pos"]
		var normal: Vector2 = info["normal"]
		var semente: float = float(i) * 1.63 + 0.9

		# Variação de altura por sin() puro (barato) em vez de
		# _ruido01(...floor(tempo*X)) (caro — chamava sin() por dentro
		# E recalculava floor() todo frame).
		var alt_var: float = 0.68 + 0.30 * (0.5 + 0.5 * sin(tempo * 1.7 + semente * 2.3))
		var altura: float = espessura * alt_var

		_desenhar_lingua_fogo(host, pt, normal, altura, largura_lingua, tempo, semente)


func _pontos_lingua_fogo(base_pos: Vector2, dir: Vector2, perp: Vector2, altura: float, largura: float, tempo: float, semente: float, intensidade_jitter: float) -> PackedVector2Array:
	# 4 segmentos em vez de 6, e jitter com UM sin() por segmento em
	# vez de sin() + _ruido01() (que embutia outro sin() + floor()).
	# Metade da trigonometria por segmento, silhueta ainda irregular.
	var segmentos: int = 4
	var pts_esq: Array = []
	var pts_dir: Array = []
	for i in range(segmentos + 1):
		var t: float = float(i) / float(segmentos)
		var centro_seg: Vector2 = base_pos + dir * (altura * t)
		var largura_t: float = lerpf(largura * 0.5, 0.0, pow(t, 0.62))
		var jitter: float = sin(tempo * (5.0 + t * 3.0) + semente + t * 6.0) * largura * 0.24 * t * intensidade_jitter
		var offset_lat: Vector2 = perp * jitter
		pts_esq.append(centro_seg - perp * largura_t + offset_lat)
		pts_dir.append(centro_seg + perp * largura_t + offset_lat)

	var contorno := PackedVector2Array()
	for p in pts_esq:
		contorno.append(p)
	for i in range(pts_dir.size() - 1, -1, -1):
		contorno.append(pts_dir[i])
	return contorno


func _desenhar_lingua_fogo(host: Control, base_pos: Vector2, normal: Vector2, altura: float, largura: float, tempo: float, semente: float) -> void:
	# OTIMIZADO: antes calculava a geometria completa 3 VEZES (glow,
	# corpo, núcleo), cada uma com seu próprio _pontos_lingua_fogo.
	# Agora calcula UMA VEZ (o corpo) e deriva o glow (mais largo) e o
	# núcleo (mais estreito) por ESCALA matemática simples em cima dos
	# mesmos pontos — é só multiplicação de Vector2, sem trigonometria
	# nova. Visualmente idêntico (camadas concêntricas), mas ~3x mais
	# barato nessa parte.
	var dir: Vector2 = normal.normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var flicker: float = 0.72 + 0.28 * abs(sin(tempo * 8.0 + semente * 1.3))

	var mid := _pontos_lingua_fogo(base_pos, dir, perp, altura, largura, tempo, semente, 1.0)

	var glow := PackedVector2Array()
	for p in mid:
		glow.append(base_pos + (p - base_pos) * 1.18)
	host.draw_colored_polygon(glow, Color(0.95, 0.22, 0.02, 0.14 * flicker))

	host.draw_colored_polygon(mid, Color(1.0, 0.40, 0.03, 0.58 * flicker))

	var core := PackedVector2Array()
	for p in mid:
		core.append(base_pos + (p - base_pos) * 0.55)
	host.draw_colored_polygon(core, Color(1.0, 0.86, 0.35, 0.55 * flicker))

	var ponta: Vector2 = base_pos + dir * (altura * 0.62)
	host.draw_circle(ponta, largura * 0.09, Color(1.0, 0.98, 0.85, 0.5 * flicker))

func _acumular_pontos_borda_fogo(lista: Array, a: Vector2, b: Vector2, normal: Vector2, passo: float) -> void:
	# Distribui pontos igualmente ao longo de UM lado do card, cada um
	# guardando a direção "pra fora" (normal) daquele lado — é a partir
	# desses pontos que cada língua de fogo nasce, sempre apontando
	# pra fora da borda, nunca pro miolo do card.
	var comprimento: float = a.distance_to(b)
	var n: int = max(2, int(comprimento / passo))
	for i in range(n):
		var t: float = float(i) / float(n)
		lista.append({"pos": a.lerp(b, t), "normal": normal})



func _desenhar_fogo_capsula_pontos(host: Control, cor_base: Color) -> void:
	if host == null or not is_instance_valid(host):
		return
	if not _record_booster_ativo:
		return

	var s: Vector2 = host.size
	if s.x <= 2.0 or s.y <= 2.0:
		return

	# Mesma faixa segura de antes (afastada do raio do canto arredondado
	# da cápsula), mas agora com UM cometa centralizado em vez de várias
	# chamas espalhadas pelos cantos.
	const _RAIO_CANTO_CAPSULA := _RAIO_CANTO_PADRAO
	var margem: float = min(s.x * 0.34, _RAIO_CANTO_CAPSULA + 4.0)
	var largura_base: float = max(6.0, s.x - margem * 2.0) * 0.62

	_desenhar_chama_cometa(host, s.x * 0.5, s.y * 0.98, s.y * 0.86, largura_base, _record_booster_pulso, 0.0)


func _desenhar_lingua_fogo_record(host: Control, base: Vector2, dir: Vector2, largura: float, altura: float, tempo: float, semente: float, intensidade: float = 1.0) -> void:
	dir = dir.normalized()
	if dir == Vector2.ZERO:
		return
	var perp := Vector2(-dir.y, dir.x)
	var balanco: float = sin(tempo * 4.7 + semente) * 0.34 + sin(tempo * 7.9 + semente * 0.43) * 0.16
	var ponta: Vector2 = base + dir * altura + perp * largura * balanco
	var meio_a: Vector2 = base + dir * altura * 0.45 - perp * largura * (0.38 + 0.06 * sin(tempo + semente))
	var meio_b: Vector2 = base + dir * altura * 0.58 + perp * largura * (0.34 + 0.05 * cos(tempo * 1.3 + semente))

	var externo := PackedVector2Array([
		base - perp * largura * 0.62,
		meio_a,
		ponta,
		meio_b,
		base + perp * largura * 0.62
	])
	host.draw_colored_polygon(externo, Color(1.0, 0.22, 0.015, 0.50 * intensidade))

	var ponta_in: Vector2 = base + dir * altura * 0.72 + perp * largura * balanco * 0.55
	var interno := PackedVector2Array([
		base - perp * largura * 0.28,
		base + dir * altura * 0.33 - perp * largura * 0.18,
		ponta_in,
		base + dir * altura * 0.36 + perp * largura * 0.18,
		base + perp * largura * 0.28
	])
	host.draw_colored_polygon(interno, Color(1.0, 0.76, 0.18, 0.58 * intensidade))

	var nucleo: Vector2 = base + dir * altura * 0.12
	var flicker: float = 0.72 + 0.28 * abs(sin(tempo * 8.0 + semente))
	host.draw_circle(nucleo, largura * 0.42, Color(1.0, 0.45, 0.04, 0.34 * intensidade * flicker))
	host.draw_circle(nucleo + dir * largura * 0.10, largura * 0.20, Color(1.0, 0.95, 0.52, 0.34 * intensidade * flicker))


func _desenhar_retangulo_arredondado_outline(host: Control, rect: Rect2, raio: float, cor: Color, largura: float) -> void:
	if rect.size.x <= 4.0 or rect.size.y <= 4.0:
		return
	raio = clampf(raio, 4.0, min(rect.size.x, rect.size.y) * 0.5)
	var x0: float = rect.position.x
	var y0: float = rect.position.y
	var x1: float = rect.position.x + rect.size.x
	var y1: float = rect.position.y + rect.size.y
	host.draw_line(Vector2(x0 + raio, y0), Vector2(x1 - raio, y0), cor, largura, true)
	host.draw_line(Vector2(x0 + raio, y1), Vector2(x1 - raio, y1), cor, largura, true)
	host.draw_line(Vector2(x0, y0 + raio), Vector2(x0, y1 - raio), cor, largura, true)
	host.draw_line(Vector2(x1, y0 + raio), Vector2(x1, y1 - raio), cor, largura, true)
	host.draw_arc(Vector2(x0 + raio, y0 + raio), raio, PI, PI * 1.5, 32, cor, largura, true)
	host.draw_arc(Vector2(x1 - raio, y0 + raio), raio, PI * 1.5, TAU, 32, cor, largura, true)
	host.draw_arc(Vector2(x1 - raio, y1 - raio), raio, 0.0, PI * 0.5, 32, cor, largura, true)
	host.draw_arc(Vector2(x0 + raio, y1 - raio), raio, PI * 0.5, PI, 32, cor, largura, true)


func _desenhar_chamas_record_card(host: Control) -> void:
	var s: Vector2 = host.size
	if s.x <= 8.0 or s.y <= 8.0:
		return

	var tempo: float = _record_booster_pulso
	var pulso: float = 0.80 + 0.20 * abs(sin(tempo * 2.45))

	# O host agora tem o MESMO tamanho do painel_current_score.
	# Esta margem é uniforme em todos os lados, então a chama encaixa
	# perfeitamente nas quatro bordas do card de PONTOS.
	var margem: float = max(4.0, min(s.x, s.y) * 0.035)
	var rect := Rect2(Vector2(margem, margem), s - Vector2(margem, margem) * 2.0)
	var raio: float = min(rect.size.y, rect.size.x) * 0.5
	var espessura_base: float = max(3.0, min(s.x, s.y) * 0.026)

	# Glow externo proporcional, sempre com a mesma expansão nos 4 lados.
	for camada in range(5):
		var exp: float = espessura_base * (1.4 + float(camada) * 1.25)
		var alpha: float = (0.30 - float(camada) * 0.045) * pulso
		var largura: float = max(2.0, espessura_base * (1.25 - float(camada) * 0.10))
		var r := rect.grow(exp)
		_desenhar_retangulo_arredondado_outline(
			host,
			r,
			raio + exp,
			Color(1.0, 0.34 + float(camada) * 0.06, 0.02, alpha),
			largura
		)

	# Contorno principal da borda, exatamente em cima da moldura do card.
	_desenhar_retangulo_arredondado_outline(host, rect, raio, Color(1.0, 0.90, 0.28, 0.82 * pulso), espessura_base)
	_desenhar_retangulo_arredondado_outline(host, rect.grow(espessura_base * 0.75), raio + espessura_base * 0.75, Color(1.0, 0.20, 0.02, 0.52 * pulso), espessura_base * 1.15)

	# Chamas exatamente presas às bordas. A quantidade usa o tamanho do
	# próprio card para manter proporção em qualquer resolução.
	var total_horizontal: int = clampi(int(rect.size.x / max(18.0, s.y * 0.16)), 7, 13)
	for i in range(total_horizontal):
		var f: float = float(i) / float(max(1, total_horizontal - 1))
		var x: float = lerpf(rect.position.x + raio * 0.55, rect.position.x + rect.size.x - raio * 0.55, f)
		var onda: float = abs(sin(tempo * 2.4 + float(i) * 0.73))
		var largura: float = s.y * (0.050 + 0.018 * onda)

		var altura_baixo: float = s.y * (0.125 + 0.055 * abs(cos(tempo * 2.0 + float(i) * 0.81)))
		_desenhar_lingua_fogo_record(host, Vector2(x, rect.position.y + rect.size.y), Vector2(0, 1), largura, altura_baixo, tempo, float(i) * 0.73, pulso)

		var altura_topo: float = s.y * (0.095 + 0.040 * abs(sin(tempo * 2.7 + float(i) * 0.69)))
		_desenhar_lingua_fogo_record(host, Vector2(x, rect.position.y), Vector2(0, -1), largura * 0.78, altura_topo, tempo, 5.0 + float(i) * 0.67, pulso * 0.78)

	var total_vertical: int = clampi(int(rect.size.y / max(14.0, s.y * 0.20)), 4, 7)
	for lado in [-1, 1]:
		var x_side: float = rect.position.x if lado < 0 else rect.position.x + rect.size.x
		var dir := Vector2(float(lado), 0.0)
		for i in range(total_vertical):
			var f: float = float(i) / float(max(1, total_vertical - 1))
			var y: float = lerpf(rect.position.y + raio * 0.55, rect.position.y + rect.size.y - raio * 0.55, f)
			var altura: float = s.x * (0.022 + 0.012 * abs(sin(tempo * 2.3 + float(i) + float(lado))))
			var largura: float = s.y * (0.034 + 0.010 * abs(cos(tempo * 1.8 + float(i))))
			_desenhar_lingua_fogo_record(host, Vector2(x_side, y), dir, largura, altura, tempo, 9.0 + float(i) * 0.81 + float(lado), pulso * 0.70)

	# Pequenos pontos quentes nos cantos para fechar visualmente a moldura.
	var cantos := [
		rect.position + Vector2(raio, raio),
		rect.position + Vector2(rect.size.x - raio, raio),
		rect.position + Vector2(rect.size.x - raio, rect.size.y - raio),
		rect.position + Vector2(raio, rect.size.y - raio)
	]
	for i in range(cantos.size()):
		var flicker: float = 0.72 + 0.28 * abs(sin(tempo * 6.0 + float(i) * 1.7))
		host.draw_circle(cantos[i], espessura_base * 2.3, Color(1.0, 0.30, 0.02, 0.22 * pulso * flicker))
		host.draw_circle(cantos[i], espessura_base * 1.1, Color(1.0, 0.88, 0.30, 0.30 * pulso * flicker))



func _desenhar_fogo_pontos_atuais(host: Control, cor_jogador: Color = Color(1.0, 0.55, 0.10)) -> void:
	if host == null or not is_instance_valid(host):
		return

	if host is Panel:
		var p: Panel = host as Panel
		p.clip_contents = true
		p.add_theme_stylebox_override("panel", _estilo_card_pontuacao_atual(cor_jogador, _record_booster_ativo))

	_desenhar_ondas_card_pontos(host)

	if not _record_booster_ativo:
		return

	var s: Vector2 = host.size
	if s.x <= 4.0 or s.y <= 4.0:
		return

	_desenhar_fogo_perimetro_card(host, s)



func _estilo_painel(cor_borda: Color, ativo: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.86)
	sb.border_color = cor_borda
	sb.set_border_width_all(5 if ativo else 3)
	sb.set_corner_radius_all(22)
	sb.corner_detail = 12
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(cor_borda.r, cor_borda.g, cor_borda.b, 0.55 if ativo else 0.22)
	sb.shadow_size = 20 if ativo else 8
	sb.anti_aliasing = true
	return sb


# =====================================================================
# ÁUDIO
# =====================================================================
func _iniciar_musica_fundo() -> void:
	if musica_fundo == null:
		return
	var s := load(caminho_musica_fundo) as AudioStream
	if s == null:
		push_warning("Game: música de fundo não encontrada em " + caminho_musica_fundo)
		return
	if s is AudioStreamMP3:
		s.loop = true
	elif s is AudioStreamOggVorbis:
		s.loop = true
	musica_fundo.stream = s
	musica_fundo.volume_db = volume_musica_db
	musica_fundo.play()



func _carregar_sons() -> void:
	if som_cesta:
		var sc := load(caminho_som_cesta) as AudioStream
		if sc:
			som_cesta.stream = sc
			som_cesta.volume_db = volume_cesta_db

	if som_apito:
		var sa := load(caminho_apito_inicio) as AudioStream
		if sa:
			som_apito.stream = sa

	if som_fim:
		var sf := load(caminho_end_bask) as AudioStream
		if sf:
			som_fim.stream = sf

	if som_good_player:
		var sg := load(caminho_song_good_player) as AudioStream
		if sg == null and caminho_song_good_player != "res://songs/good_player.mp3":
			sg = load("res://songs/good_player.mp3") as AudioStream
		if sg:
			som_good_player.stream = sg
			som_good_player.volume_db = volume_song_good_player_db
		else:
			push_warning("Pódio: song_good_player não encontrado em " + caminho_song_good_player)

	# Sons de combo 1 até 12.
	sons_combo.clear()

	var caminhos := [
		caminho_som_combo_1,
		caminho_som_combo_2,
		caminho_som_combo_3,
		caminho_som_combo_4,
		caminho_som_combo_5,
		caminho_som_combo_6,
		caminho_som_combo_7,
		caminho_som_combo_8,
		caminho_som_combo_9,
		caminho_som_combo_10,
		caminho_som_combo_11,
		caminho_som_combo_12
	]

	for i in range(caminhos.size()):
		var player := _garantir_audio("SomCombo%d" % (i + 1))
		player.volume_db = volume_combo_db

		var stream := load(caminhos[i]) as AudioStream
		if stream:
			player.stream = stream
		else:
			push_warning("Combo: som não encontrado em " + str(caminhos[i]))

		sons_combo.append(player)


func _criar_combo_ui() -> void:
	if combo_layer != null and is_instance_valid(combo_layer):
		return

	combo_layer = CanvasLayer.new()
	combo_layer.name = "ComboLayer"
	combo_layer.layer = 45
	add_child(combo_layer)

	lbl_combo = Label.new()
	lbl_combo.name = "LblCombo"
	lbl_combo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_combo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_combo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_combo.visible = false
	lbl_combo.modulate.a = 0.0
	lbl_combo.text = ""

	lbl_combo.add_theme_color_override("font_color", Color.WHITE)
	lbl_combo.add_theme_color_override("font_outline_color", Color(1.0, 0.38, 0.02))
	lbl_combo.add_theme_constant_override("outline_size", 14)

	_aplicar_fonte(lbl_combo)

	combo_layer.add_child(lbl_combo)
	_layout_combo_ui()



func _layout_combo_ui() -> void:
	if lbl_combo == null:
		return

	# Texto de combo mais baixo, sem sair da tela.
	_ancorar(lbl_combo, 0.04, 0.555, 0.96, 0.675)

	lbl_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_combo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_combo.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl_combo.clip_text = true

	lbl_combo.add_theme_font_size_override("font_size", _fs(0.043))
	lbl_combo.add_theme_constant_override("outline_size", 8)


func _criar_record_coroa_ui() -> void:
	return


func _desenhar_coroa_record() -> void:
	return


func _desenhar_segmento_piche(a: Vector2, b: Vector2, progresso: float, cor: Color, largura: float) -> void:
	return


func _desenhar_polyline_piche(pontos: Array, progresso: float, cor: Color, largura: float, jitter: Vector2 = Vector2.ZERO) -> void:
	return


func _desenhar_polyline_piche_offset(pontos: Array, progresso: float, cor: Color, largura: float, offset: Vector2) -> void:
	return


func _desenhar_gota_piche(inicio: Vector2, comprimento: float, progresso: float, cor: Color, largura: float) -> void:
	return



func _ativar_visual_record() -> void:
	_record_booster_ativo = true
	_record_booster_pulso = 0.0

	# Recorde domina o visual:
	# limpa ondas anteriores de combo para não misturar azul/roxo/vermelho.
	_grade_ondas.clear()
	_ondas_luz.clear()

	if grade_ctrl != null:
		grade_ctrl.queue_redraw()

	if luz_onda_ctrl != null:
		luz_onda_ctrl.queue_redraw()

	if record_coroa_ctrl != null:
		record_coroa_ctrl.visible = true
		record_coroa_ctrl.queue_redraw()

	_reconstruir_players()



func _desativar_visual_record() -> void:
	_record_booster_ativo = false
	_record_booster_pulso = 0.0

	if record_coroa_ctrl != null:
		record_coroa_ctrl.visible = false

	_reconstruir_players()



func _tocar(p: AudioStreamPlayer) -> void:
	if p and p.stream:
		p.play()



func _tocar_song_good_player_podio() -> void:
	# Chamada especial do resultado final: a música de fundo continua tocando
	# e este som entra por cima como celebração do pódio.
	if musica_fundo != null:
		musica_fundo.volume_db = volume_musica_db
		if musica_fundo.stream != null and not musica_fundo.playing:
			musica_fundo.play()

	if som_good_player == null or som_good_player.stream == null:
		return
	if som_good_player.playing:
		som_good_player.stop()
	som_good_player.volume_db = volume_song_good_player_db
	som_good_player.play()



func _tocar_som_cesta() -> void:
	_tocar(som_cesta)


# =====================================================================
# CONTAGEM / VAI
# =====================================================================
func _contagem_regressiva() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ContagemLayer"
	layer.layer = 28
	add_child(layer)
	var lbl := Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", _fs(0.17))
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", COR_AZUL)
	lbl.add_theme_constant_override("outline_size", 10)
	_aplicar_fonte(lbl)
	layer.add_child(lbl)
	for n in range(segundos_contagem, 0, -1):
		lbl.text = str(n)
		lbl.pivot_offset = get_viewport_rect().size * 0.5
		lbl.scale = Vector2(1.5, 1.5)
		lbl.modulate.a = 0.0

		# EFEITO INVERSO DA CESTA: das periferias para o centro, a cada segundo.
		# EFEITO INVERSO DA CESTA: das periferias para o centro, a cada segundo.
		# Usa a mesma origem do recorde/combo, para convergir exatamente
		# no ponto onde os outros efeitos de cesta nascem.
		var centro_tela := _record_origem_fx()
		var prog := float(segundos_contagem - n) / float(max(1, segundos_contagem - 1))
		var forca_count := lerpf(0.75, 1.45, prog)
		var cor_count := Color(1.0, 0.55, 0.08).lerp(COR_RECORDE, prog)
		_disparar_implosao(centro_tela, cor_count, forca_count)
		_disparar_onda_grade(centro_tela, true)

		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(lbl, "modulate:a", 1.0, 0.18)
		t.tween_property(lbl, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(0.7).timeout
		var t2 := create_tween()
		t2.tween_property(lbl, "modulate:a", 0.0, 0.18)
		await t2.finished
	layer.queue_free()



func _flash_vai() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FlashVaiLayer"
	layer.layer = 28
	add_child(layer)
	var lbl := Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.text = "VAI!"
	lbl.add_theme_font_size_override("font_size", _fs(0.12))
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 10)
	_aplicar_fonte(lbl)
	layer.add_child(lbl)
	lbl.pivot_offset = get_viewport_rect().size * 0.5
	lbl.scale = Vector2(0.6, 0.6)
	var t := create_tween()
	t.tween_property(lbl, "scale", Vector2(1.12, 1.12), 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.22)
	t.tween_property(lbl, "modulate:a", 0.0, 0.28)
	t.tween_callback(layer.queue_free)



# =====================================================================
# MODAL DE TURNO
# =====================================================================
func _mostrar_modal_turno(inicial: bool) -> void:
	if _shootout_ativo:
		_mostrar_modal_shootout(inicial)
		return

	_modal_turno_ativo = true
	_modal_turno_pronto = false
	_rodando = false
	if _modal_turno_layer != null:
		_modal_turno_layer.queue_free()
		_modal_turno_layer = null
	_modal_turno_layer = CanvasLayer.new()
	_modal_turno_layer.name = "ModalTurnoLayer"
	_modal_turno_layer.layer = 30
	add_child(_modal_turno_layer)

	var escuro := ColorRect.new()
	escuro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	escuro.color = Color(0, 0, 0, 0.82)
	escuro.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_turno_layer.add_child(escuro)

	var painel := Panel.new()
	painel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	painel.offset_left = -470; painel.offset_right = 470
	painel.offset_top = -300; painel.offset_bottom = 300
	painel.add_theme_stylebox_override("panel", _estilo_modal_turno())
	_modal_turno_layer.add_child(painel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 36; vbox.offset_right = -36; vbox.offset_top = 34; vbox.offset_bottom = -34
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	painel.add_child(vbox)

	var titulo := Label.new()
	titulo.text = "ORDEM DE JOGO" if inicial else "PRÓXIMO JOGADOR"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 50)
	titulo.add_theme_color_override("font_color", Color.WHITE)
	titulo.add_theme_color_override("font_outline_color", COR_VERDE_DISPLAY)
	titulo.add_theme_constant_override("outline_size", 8)
	_aplicar_fonte(titulo)
	vbox.add_child(titulo)

	var jogador := Label.new()
	jogador.text = "%s COMEÇA AGORA" % str(_nomes[_jogador_atual])
	jogador.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jogador.add_theme_font_size_override("font_size", 36)
	jogador.add_theme_color_override("font_color", CORES_PLAYERS[_jogador_atual])
	jogador.add_theme_color_override("font_outline_color", Color.BLACK)
	jogador.add_theme_constant_override("outline_size", 5)
	_aplicar_fonte(jogador)
	vbox.add_child(jogador)

	var linha := HBoxContainer.new()
	linha.alignment = BoxContainer.ALIGNMENT_CENTER
	linha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.add_theme_constant_override("separation", 14)
	vbox.add_child(linha)
	for i in range(num_jogadores):
		linha.add_child(_criar_card_ordem_modal(i))

	var info := Label.new()
	info.text = "CADA JOGADOR JOGA %d SEGUNDOS" % int(_duracao_turno_atual())
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 22)
	info.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_aplicar_fonte(info)
	vbox.add_child(info)

	var start := Label.new()
	start.text = "PRESSIONE START"
	start.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start.add_theme_font_size_override("font_size", 34)
	start.add_theme_color_override("font_color", Color.WHITE)
	start.add_theme_color_override("font_outline_color", COR_VERDE_DISPLAY)
	start.add_theme_constant_override("outline_size", 6)
	_aplicar_fonte(start)
	vbox.add_child(start)

	painel.pivot_offset = painel.size * 0.5
	painel.scale = Vector2(0.88, 0.88)
	painel.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(painel, "scale", Vector2(1, 1), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(painel, "modulate:a", 1.0, 0.25)
	var pisca := create_tween().set_loops()
	pisca.tween_property(start, "modulate:a", 0.25, 0.6)
	pisca.tween_property(start, "modulate:a", 1.0, 0.6)
	await get_tree().create_timer(0.45).timeout
	_modal_turno_pronto = true



func _mostrar_modal_shootout(inicial: bool) -> void:
	_modal_turno_ativo = true
	_modal_turno_pronto = false
	_rodando = false

	if _modal_turno_layer != null:
		_modal_turno_layer.queue_free()
		_modal_turno_layer = null

	_modal_turno_layer = CanvasLayer.new()
	_modal_turno_layer.name = "ModalShootoutLayer"
	_modal_turno_layer.layer = 30
	add_child(_modal_turno_layer)

	var escuro := ColorRect.new()
	escuro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	escuro.color = Color(0, 0, 0, 0.86)
	escuro.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_turno_layer.add_child(escuro)

	var painel := Panel.new()
	painel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	painel.offset_left = -520
	painel.offset_right = 520
	painel.offset_top = -315
	painel.offset_bottom = 315
	painel.add_theme_stylebox_override("panel", _estilo_modal_turno())
	_modal_turno_layer.add_child(painel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 36
	vbox.offset_right = -36
	vbox.offset_top = 32
	vbox.offset_bottom = -32
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 13)
	painel.add_child(vbox)

	var titulo := Label.new()
	titulo.text = nome_shootout_desempate
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 52)
	titulo.add_theme_color_override("font_color", Color.WHITE)
	titulo.add_theme_color_override("font_outline_color", COR_RECORDE)
	titulo.add_theme_constant_override("outline_size", 9)
	_aplicar_fonte(titulo)
	vbox.add_child(titulo)

	var sub := Label.new()
	sub.text = "EMPATE NO 1º LUGAR • RODADA %d" % max(1, _shootout_rodada)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", COR_AMBAR)
	sub.add_theme_color_override("font_outline_color", Color.BLACK)
	sub.add_theme_constant_override("outline_size", 4)
	_aplicar_fonte(sub)
	vbox.add_child(sub)

	var jogador := Label.new()
	jogador.text = "%s TEM %d SEGUNDOS" % [str(_nomes[_jogador_atual]), int(tempo_shootout_desempate)]
	jogador.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jogador.add_theme_font_size_override("font_size", 36)
	jogador.add_theme_color_override("font_color", CORES_PLAYERS[_jogador_atual % CORES_PLAYERS.size()])
	jogador.add_theme_color_override("font_outline_color", Color.BLACK)
	jogador.add_theme_constant_override("outline_size", 5)
	_aplicar_fonte(jogador)
	vbox.add_child(jogador)

	var linha := HBoxContainer.new()
	linha.alignment = BoxContainer.ALIGNMENT_CENTER
	linha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.add_theme_constant_override("separation", 14)
	vbox.add_child(linha)

	for idx in _shootout_participantes_rodada:
		linha.add_child(_criar_card_shootout_modal(int(idx)))

	var info := Label.new()
	info.text = "FAÇA O MÁXIMO DE CESTAS PARA DESEMPATAR"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 22)
	info.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	info.add_theme_color_override("font_outline_color", Color.BLACK)
	info.add_theme_constant_override("outline_size", 3)
	_aplicar_fonte(info)
	vbox.add_child(info)

	var start := Label.new()
	start.text = "PRESSIONE START PARA COMEÇAR"
	start.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start.add_theme_font_size_override("font_size", 34)
	start.add_theme_color_override("font_color", Color.WHITE)
	start.add_theme_color_override("font_outline_color", COR_VERDE_DISPLAY)
	start.add_theme_constant_override("outline_size", 6)
	_aplicar_fonte(start)
	vbox.add_child(start)

	painel.pivot_offset = painel.size * 0.5
	painel.scale = Vector2(0.88, 0.88)
	painel.modulate.a = 0.0

	var t := create_tween().set_parallel(true)
	t.tween_property(painel, "scale", Vector2(1, 1), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(painel, "modulate:a", 1.0, 0.25)

	var pisca := create_tween().set_loops()
	pisca.tween_property(start, "modulate:a", 0.25, 0.6)
	pisca.tween_property(start, "modulate:a", 1.0, 0.6)

	await get_tree().create_timer(0.45).timeout
	_modal_turno_pronto = true



func _criar_card_shootout_modal(idx: int) -> Panel:
	var cor: Color = CORES_PLAYERS[idx % CORES_PLAYERS.size()]
	var ativo := idx == _jogador_atual

	var card := Panel.new()
	card.custom_minimum_size = Vector2(215, 150)
	card.add_theme_stylebox_override("panel", _estilo_painel(cor, ativo))

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var nome := Label.new()
	nome.text = str(_nomes[idx])
	nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nome.add_theme_font_size_override("font_size", 22)
	nome.add_theme_color_override("font_color", Color.WHITE)
	nome.add_theme_color_override("font_outline_color", Color.BLACK)
	nome.add_theme_constant_override("outline_size", 3)
	_aplicar_fonte(nome)
	vbox.add_child(nome)

	var placar := Label.new()
	placar.text = "NORMAL %d" % int(_shootout_base_pontos[idx])
	placar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placar.add_theme_font_size_override("font_size", 18)
	placar.add_theme_color_override("font_color", Color(0.86, 0.90, 1.0))
	placar.add_theme_color_override("font_outline_color", Color.BLACK)
	placar.add_theme_constant_override("outline_size", 2)
	_aplicar_fonte(placar)
	vbox.add_child(placar)

	var extra := Label.new()
	extra.text = "SHOOTOUT +%d" % int(_shootout_pontos_total[idx])
	extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	extra.add_theme_font_size_override("font_size", 20)
	extra.add_theme_color_override("font_color", COR_AMBAR)
	extra.add_theme_color_override("font_outline_color", Color.BLACK)
	extra.add_theme_constant_override("outline_size", 3)
	_aplicar_fonte(extra)
	vbox.add_child(extra)

	var status := Label.new()
	if ativo:
		status.text = "AGORA"
		status.add_theme_color_override("font_color", Color.WHITE)
	elif int(_shootout_pontos_rodada[idx]) > 0:
		status.text = "RODADA +%d" % int(_shootout_pontos_rodada[idx])
		status.add_theme_color_override("font_color", COR_VERDE_DISPLAY)
	else:
		status.text = "AGUARDA"
		status.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 18)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 2)
	_aplicar_fonte(status)
	vbox.add_child(status)

	return card



func _criar_card_ordem_modal(i: int) -> Panel:
	var cor: Color = CORES_PLAYERS[i % CORES_PLAYERS.size()]
	var ativo := i == _jogador_atual
	var finalizado: bool = bool(_turnos_finalizados[i])
	var card := Panel.new()
	card.custom_minimum_size = Vector2(185, 150)
	card.add_theme_stylebox_override("panel", _estilo_painel(cor, ativo))
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)
	var ordem := Label.new()
	ordem.text = "%dº" % (i + 1)
	ordem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ordem.add_theme_font_size_override("font_size", 28)
	ordem.add_theme_color_override("font_color", cor)
	_aplicar_fonte(ordem)
	vbox.add_child(ordem)
	var nome := Label.new()
	nome.text = str(_nomes[i])
	nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nome.add_theme_font_size_override("font_size", 22)
	nome.add_theme_color_override("font_color", Color.WHITE)
	_aplicar_fonte(nome)
	vbox.add_child(nome)
	var status := Label.new()
	if finalizado:
		status.text = "OK"; status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	elif ativo:
		status.text = "AGORA"; status.add_theme_color_override("font_color", Color.WHITE)
	else:
		status.text = "DEPOIS"; status.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 18)
	_aplicar_fonte(status)
	vbox.add_child(status)
	return card



func _estilo_modal_turno() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.10, 0.98)
	sb.border_color = COR_AZUL
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(34)
	sb.set_content_margin_all(26)
	sb.shadow_color = Color(COR_AZUL.r, COR_AZUL.g, COR_AZUL.b, 0.55)
	sb.shadow_size = 28
	return sb



func _iniciar_turno_atual() -> void:
	if _shootout_ativo:
		_iniciar_turno_shootout_atual()
		return

	if _modal_turno_ativo and not _modal_turno_pronto:
		return
	_modal_turno_ativo = false
	_modal_turno_pronto = false
	if _modal_turno_layer != null:
		_modal_turno_layer.queue_free()
		_modal_turno_layer = null

	_atualizar_visao_turno()
	_ocultar_hud_para_contagem()
	await _contagem_regressiva()
	await _montar_hud_apos_contagem()
	_tocar(som_apito)
	_flash_vai()
	iniciar_partida(_duracao_turno_atual())



func _iniciar_turno_shootout_atual() -> void:
	if _modal_turno_ativo and not _modal_turno_pronto:
		return

	_modal_turno_ativo = false
	_modal_turno_pronto = false

	if _modal_turno_layer != null:
		_modal_turno_layer.queue_free()
		_modal_turno_layer = null

	_atualizar_visao_turno()
	_ocultar_hud_para_contagem()
	await _contagem_regressiva()
	await _montar_hud_apos_contagem()
	_tocar(som_apito)
	_flash_vai()
	iniciar_partida(tempo_shootout_desempate)



func _ocultar_hud_para_contagem() -> void:
	_tempo_restante = _duracao_turno_atual()
	_rodando = false
	_atualizar_tempo_label()

	# Durante a contagem regressiva a tela precisa ficar limpa:
	# sem cards, sem textos de HUD e sem logo no canto.
	for n in _nodes_hud_jogo():
		if n == null:
			continue

		n.visible = false
		n.modulate.a = 0.0

		if n is Control:
			var ctrl := n as Control
			ctrl.scale = Vector2.ONE

	# Garante que a logo nunca fique vazando por cima da contagem.
	if logo_canto_fx != null:
		logo_canto_fx.visible = false
		logo_canto_fx.modulate.a = 0.0

	if logo_canto_img != null:
		logo_canto_img.visible = false
		logo_canto_img.modulate.a = 0.0



func _montar_hud_apos_contagem() -> void:
	_atualizar_visao_turno()

	# A HUD monta em camadas para dar impacto moderno:
	# 1) recorde + pontos equilibram os cantos;
	# 2) cronômetro entra no centro;
	# 3) players fixos entram;
	# 4) logo entra por último, suave e premium.
	var ordem: Array = [
		painel_record,
		lbl_high_titulo,
		lbl_high_valor,
		painel_current_score,
		fx_fogo_pontos_atuais,
		lbl_atual_titulo,
		lbl_atual_pontos,
		crono_ring,
		lbl_crono,
		lbl_tempo_titulo,
		box_players_score,
		logo_canto_fx,
		logo_canto_img
	]

	var atraso: float = 0.0

	for n in ordem:
		if n == null:
			continue

		var atraso_node: float = atraso
		if n == logo_canto_fx or n == logo_canto_img:
			atraso_node += 0.14

		_animar_entrada_hud_node(n, atraso_node)
		atraso += 0.040

	await get_tree().create_timer(atraso + 0.62).timeout



func _encerrar_turno_atual() -> void:
	if _shootout_ativo:
		await _encerrar_turno_shootout_atual()
		return

	_rodando = false
	_record_booster_ativo = false
	_record_booster_pulso = 0.0

	# Fim do turno: os LEDs voltam para o modo de espera (IDLE), mas a
	# ponte com o Arduino continua ABERTA. Antes isso fechava a COM5 e
	# reabria no turno seguinte — dava um "flash"/reset visível no LED
	# bem no meio da modal do próximo jogador, exatamente quando ele
	# devia estar aceso e bonito esperando o START.
	_enviar_led_basket("IDLE")

	_tocar(som_fim)

	_turnos_finalizados[_jogador_atual] = true

	if _jogador_atual >= num_jogadores - 1:
		encerrar_partida()
		return

	_jogador_atual += 1
	_atualizar_visao_turno()

	await get_tree().create_timer(0.7).timeout
	_mostrar_modal_turno(false)



# =====================================================================
# DESEMPATE — SHOOTOUT BASKET
# =====================================================================
func _resetar_estado_shootout_total() -> void:
	_shootout_ativo = false
	_shootout_participantes.clear()
	_shootout_participantes_rodada.clear()
	_shootout_pos = 0
	_shootout_rodada = 0
	_shootout_pontos_rodada = [0, 0, 0, 0]
	_shootout_pontos_total = [0, 0, 0, 0]
	_shootout_base_pontos = [0, 0, 0, 0]
	_shootout_historico.clear()
	_partida_teve_shootout = false



func _indices_empate_primeiro() -> Array:
	var empatados: Array = []

	if num_jogadores <= 1:
		return empatados

	var maior: int = -999999
	for i in range(num_jogadores):
		maior = max(maior, int(_pontos[i]))

	for i in range(num_jogadores):
		if int(_pontos[i]) == maior:
			empatados.append(i)

	return empatados if empatados.size() >= 2 else []



func _iniciar_shootout_desempate(empatados: Array) -> void:
	if empatados.size() < 2:
		return

	_partida_teve_shootout = true
	_shootout_ativo = true
	_shootout_rodada = 1
	_shootout_participantes = empatados.duplicate()
	_shootout_participantes_rodada = empatados.duplicate()
	_shootout_pos = 0
	_shootout_base_pontos = _pontos.duplicate()
	_shootout_pontos_rodada = [0, 0, 0, 0]
	_shootout_pontos_total = [0, 0, 0, 0]
	_shootout_historico.clear()

	for i in range(4):
		_turnos_finalizados[i] = true
	for idx in _shootout_participantes_rodada:
		_turnos_finalizados[int(idx)] = false

	_jogador_atual = int(_shootout_participantes_rodada[0])
	_tempo_restante = tempo_shootout_desempate
	_rodando = false
	_modal_turno_ativo = false
	_modal_turno_pronto = false

	if lbl_combo != null:
		lbl_combo.visible = false

	_atualizar_visao_turno()
	_atualizar_tempo_label()
	_mostrar_modal_turno(true)



func _encerrar_turno_shootout_atual() -> void:
	_rodando = false
	_record_booster_ativo = false
	_record_booster_pulso = 0.0
	_enviar_led_basket("IDLE")
	_tocar(som_fim)

	var atual: int = _jogador_atual
	if atual >= 0 and atual < 4:
		_turnos_finalizados[atual] = true
		_shootout_historico.append({
			"rodada": _shootout_rodada,
			"jogador": atual,
			"pontos": int(_shootout_pontos_rodada[atual])
		})

	if _shootout_pos < _shootout_participantes_rodada.size() - 1:
		_shootout_pos += 1
		_jogador_atual = int(_shootout_participantes_rodada[_shootout_pos])
		_turnos_finalizados[_jogador_atual] = false
		_atualizar_visao_turno()
		await get_tree().create_timer(0.65).timeout
		_mostrar_modal_turno(false)
		return

	await _fechar_rodada_shootout()



func _fechar_rodada_shootout() -> void:
	var maior_rodada: int = -999999
	var empatados: Array = []

	for idx in _shootout_participantes_rodada:
		var i: int = int(idx)
		var pontos_rodada: int = int(_shootout_pontos_rodada[i])

		if pontos_rodada > maior_rodada:
			maior_rodada = pontos_rodada
			empatados = [i]
		elif pontos_rodada == maior_rodada:
			empatados.append(i)

	if empatados.size() == 1:
		_shootout_ativo = false
		_shootout_participantes_rodada = []
		_shootout_pos = 0
		_turnos_finalizados = [true, true, true, true]
		_jogador_atual = int(empatados[0])
		await get_tree().create_timer(0.45).timeout
		encerrar_partida()
		return

	_shootout_rodada += 1
	_shootout_participantes_rodada = empatados.duplicate()
	_shootout_pos = 0
	_shootout_pontos_rodada = [0, 0, 0, 0]

	for i in range(4):
		_turnos_finalizados[i] = true
	for idx in _shootout_participantes_rodada:
		_turnos_finalizados[int(idx)] = false

	_jogador_atual = int(_shootout_participantes_rodada[0])
	_tempo_restante = tempo_shootout_desempate
	_atualizar_visao_turno()
	_atualizar_tempo_label()

	await get_tree().create_timer(0.65).timeout
	_mostrar_modal_turno(false)


# =====================================================================
# API PÚBLICA / PONTOS
# =====================================================================
func definir_jogadores(qtd: int, nomes: Array = []) -> void:
	num_jogadores = clampi(qtd, 1, 4)
	_resetar_estado_shootout_total()
	for i in range(4):
		_pontos[i] = 0
		_turnos_finalizados[i] = false
		_nomes[i] = nomes[i] if i < nomes.size() else NOMES_PADRAO[i]
	_jogador_atual = 0
	_atualizar_visao_turno()



func adicionar_ponto_jogador_atual(valor: int = 1) -> void:
	adicionar_ponto(_jogador_atual, valor)



func adicionar_ponto(idx: int, valor: int = 1) -> void:
	if idx < 0 or idx >= num_jogadores:
		return

	_pontos[idx] += valor

	if _shootout_ativo and idx >= 0 and idx < 4:
		_shootout_pontos_rodada[idx] = int(_shootout_pontos_rodada[idx]) + valor
		_shootout_pontos_total[idx] = int(_shootout_pontos_total[idx]) + valor

	if idx == _jogador_atual:
		var combo_nivel: int = _registrar_combo_cesta()

		_atualizar_placar_labels()
		_reconstruir_players()

		var pts_atuais: int = int(_pontos[idx])
		var bateu_recorde_agora: bool = pts_atuais > record_maximo

		_verificar_recorde_atual()
		_pulso_placar()
		_disparar_onda_card_pontos()

		# Antes de bater recorde: efeito normal de combo.
		# Antes de bater recorde: efeito normal de combo.
		if not _record_booster_ativo and not bateu_recorde_agora:
			_enviar_led_basket("HIT")
			_efeito_cesta(combo_nivel)
			_disparar_shake(2.0 + min(float(combo_nivel), 13.0) * 0.9, 12.0)

		# Primeira vez que bate o recorde:
		# limpa combo e entra visual record dominante.
		elif bateu_recorde_agora and not _recorde_celebrado_turno:
			_recorde_celebrado_turno = true
			_ativar_visual_record()

			_enviar_led_basket("RECORD")
			_efeito_cesta_record(true)
			_flash_recorde()
			_disparar_shake(16.0, 6.0)

		# Depois do recorde:
		# continua só record, sem shader de combo.
		else:
			_enviar_led_basket("BOOST")
			_efeito_cesta_record(false)
			_disparar_shake(6.0, 9.0)

	else:
		_reconstruir_players()

	ponto_marcado.emit(idx, _pontos[idx])



func _registrar_combo_cesta() -> int:
	var agora: float = Time.get_ticks_msec() / 1000.0

	if agora - _combo_ultimo_t <= janela_combo_segundos:
		_combo_nivel += 1
	else:
		_combo_nivel = 1

	_combo_ultimo_t = agora

	_tocar_som_combo(_combo_nivel)
	_mostrar_texto_combo(_combo_nivel)

	return _combo_nivel



func _tocar_som_combo(nivel: int) -> void:
	if sons_combo.is_empty():
		_tocar_som_cesta()
		return

	var idx: int = clampi(nivel, 1, sons_combo.size()) - 1

	if idx >= 0 and idx < sons_combo.size():
		var p = sons_combo[idx]
		if p is AudioStreamPlayer and p.stream:
			p.stop()
			p.play()
			return

	_tocar_som_cesta()



# Bancos de frases por faixa de combo — sorteadas a cada acerto pra
# nunca repetir sempre a mesma. Muito mais vivo que "BLUE x6"/"NEON x9".
const _FRASES_COMBO_1 := ["BOA!", "ACERTOU!", "ISSO AÍ!", "NA MOSCA!"]
const _FRASES_COMBO_2 := ["EMBALOU x2!", "DOBROU A APOSTA!", "SEGUINDO FIRME!", "MAIS UMA!"]
const _FRASES_COMBO_3 := ["TRIPLE x3!", "SEM ERRAR!", "PEGANDO RITMO!", "IMPARÁVEL!"]
const _FRASES_COMBO_4 := ["SUPER x4!", "QUE MIRA!", "SEQUÊNCIA INSANA!", "ISSO É JOGO!"]
const _FRASES_COMBO_5 := ["MEGA x5!", "PEGANDO FOGO!", "SHOW DE BOLA!", "CINCO SEGUIDAS!"]
const _FRASES_COMBO_ALTA := ["ELÉTRICO x%d!", "LIGADO NO 220!", "SEM FREIO x%d!", "DOMINANDO A ARENA!"]
const _FRASES_COMBO_NEON := ["MODO NEON x%d!", "BRILHANDO DEMAIS!", "LENDÁRIO x%d!", "TÁ VOANDO!"]
const _FRASES_COMBO_MAX := ["MÁXIMO x%d!", "INSUPERÁVEL!", "LENDA VIVA x%d!", "RECORDE DE COMBO!"]


func _sortear_frase_combo(banco: Array, nivel: int) -> String:
	# Sorteia uma frase do banco garantindo que NUNCA seja igual à
	# última exibida (comparando o texto já formatado com o número do
	# combo, já que "ELÉTRICO x6!" e "ELÉTRICO x8!" contam como frases
	# diferentes mesmo vindo do mesmo molde).
	var opcoes: Array = banco.duplicate()
	opcoes.shuffle()

	for cand in opcoes:
		var formatada: String = (cand % nivel) if cand.contains("%d") else cand
		if formatada != _combo_ultima_frase:
			_combo_ultima_frase = formatada
			return formatada

	# Banco de 1 item só (ou todas coincidiram por acaso): usa mesmo assim.
	var cand0 = opcoes[0]
	var formatada0: String = (cand0 % nivel) if cand0.contains("%d") else cand0
	_combo_ultima_frase = formatada0
	return formatada0



func _mostrar_texto_combo(nivel: int) -> void:
	if lbl_combo == null:
		return

	# Se uma cesta nova chegou enquanto o texto anterior ainda estava
	# visível, ele "sai" rapidinho antes do próximo aparecer — em vez
	# de trocar de frase bruscamente no mesmo lugar.
	var interrompendo: bool = lbl_combo.visible and lbl_combo.modulate.a > 0.05

	if _combo_tween != null:
		_combo_tween.kill()
		_combo_tween = null

	if interrompendo:
		var saida := create_tween()
		saida.set_parallel(true)
		saida.tween_property(lbl_combo, "modulate:a", 0.0, 0.07)
		saida.tween_property(lbl_combo, "scale", Vector2(0.84, 0.84), 0.07)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await saida.finished

	var banco: Array
	match nivel:
		1:
			banco = _FRASES_COMBO_1
		2:
			banco = _FRASES_COMBO_2
		3:
			banco = _FRASES_COMBO_3
		4:
			banco = _FRASES_COMBO_4
		5:
			banco = _FRASES_COMBO_5
		6, 7, 8:
			banco = _FRASES_COMBO_ALTA
		9, 10, 11, 12:
			banco = _FRASES_COMBO_NEON
		_:
			banco = _FRASES_COMBO_MAX

	var txt: String = _sortear_frase_combo(banco, nivel)

	lbl_combo.text = txt
	lbl_combo.visible = true
	lbl_combo.modulate.a = 0.0
	lbl_combo.rotation = 0.0
	lbl_combo.pivot_offset = lbl_combo.size * 0.5

	# ESCALA DE IMPACTO — nasce encolhido e estoura pra fora (overshoot).
	# Cresce um pouco a cada faixa de combo pra dar sensação de "mais
	# força", mas NUNCA gira — então nunca balança de um lado pro outro.
	var escala_impacto: float = 1.10
	if nivel >= 13:
		escala_impacto = 1.30
	elif nivel >= 9:
		escala_impacto = 1.22
	elif nivel >= 6:
		escala_impacto = 1.16

	lbl_combo.scale = Vector2(0.72, 0.72)

	var cor_outline := Color(1.0, 0.38, 0.02)
	var cor_texto := Color.WHITE

	if nivel >= 13:
		cor_outline = Color(1.0, 0.02, 0.0)
		cor_texto = Color(1.0, 0.88, 0.84)
	elif nivel >= 9:
		cor_outline = Color(0.80, 0.20, 1.0)
		cor_texto = Color(0.96, 0.88, 1.0)
	elif nivel >= 6:
		cor_outline = Color(0.08, 0.42, 1.0)
		cor_texto = Color(0.88, 0.94, 1.0)
	elif nivel >= 4:
		cor_outline = COR_RECORDE
		cor_texto = COR_COMBO_LARANJA_CLARO

	# RECORDE ATIVO tem prioridade sobre a cor por nível de combo —
	# o texto vira amarelo/âmbar, deixando claro que cada acerto está
	# acontecendo DURANTE o recorde, não importa se é combo 2 ou 13.
	if _record_booster_ativo:
		cor_outline = Color(1.0, 0.62, 0.0)
		cor_texto = Color(1.0, 0.96, 0.65)

	lbl_combo.add_theme_color_override("font_color", cor_texto)
	lbl_combo.add_theme_color_override("font_outline_color", cor_outline)

	# TEMPO DE LEITURA FIXO — não depende mais de nenhuma animação extra.
	var tempo_leitura: float = 1.30 + min(nivel, 13) * 0.02

	_combo_tween = create_tween()

	# --- ENTRADA: soco de impacto, sem rotação ---
	_combo_tween.set_parallel(true)
	_combo_tween.tween_property(lbl_combo, "modulate:a", 1.0, 0.09)
	_combo_tween.tween_property(lbl_combo, "scale", Vector2(escala_impacto, escala_impacto), 0.16)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_combo_tween.chain()
	_combo_tween.tween_property(lbl_combo, "scale", Vector2.ONE, 0.12)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# --- SUSTENTAÇÃO: respiração leve só de ESCALA ---
	if nivel >= 6:
		var pulso_amp: float = 1.055 if nivel >= 13 else 1.035
		var pulso_dur: float = 0.34
		var pulsos: int = max(1, int(tempo_leitura / pulso_dur))
		for i in range(pulsos):
			_combo_tween.chain().tween_property(lbl_combo, "scale", Vector2(pulso_amp, pulso_amp), pulso_dur * 0.5)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_combo_tween.chain().tween_property(lbl_combo, "scale", Vector2.ONE, pulso_dur * 0.5)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_combo_tween.chain().tween_interval(tempo_leitura)

	# --- SAÍDA ---
	_combo_tween.chain()
	_combo_tween.set_parallel(true)
	_combo_tween.tween_property(lbl_combo, "scale", Vector2(0.88, 0.88), 0.18)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_combo_tween.tween_property(lbl_combo, "modulate:a", 0.0, 0.18)

	_combo_tween.chain()
	_combo_tween.tween_callback(func():
		if lbl_combo != null:
			lbl_combo.visible = false
	)


func _resetar_combo() -> void:
	_combo_nivel = 0
	_combo_ultimo_t = -999.0
	_combo_ultima_frase = ""

	if lbl_combo != null:
		lbl_combo.visible = false
		lbl_combo.modulate.a = 0.0
		lbl_combo.rotation = 0.0

	if _combo_tween != null:
		_combo_tween.kill()
		_combo_tween = null

	if lbl_combo != null:
		lbl_combo.visible = false
		lbl_combo.modulate.a = 0.0
		lbl_combo.rotation = 0.0
		lbl_combo.scale = Vector2.ONE



func _pulso_placar() -> void:
	if lbl_atual_pontos == null:
		return
	lbl_atual_pontos.pivot_offset = lbl_atual_pontos.size * 0.5
	var t := create_tween()
	t.tween_property(lbl_atual_pontos, "scale", Vector2(1.25, 1.25), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl_atual_pontos, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)



func _estilo_card_pontuacao_atual(cor: Color, em_recorde: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.040, 0.010, 0.95) if em_recorde else Color(0.020, 0.035, 0.075, 0.95)
	sb.border_color = COR_RECORDE if em_recorde else cor
	sb.set_border_width_all(5 if em_recorde else 4)
	sb.set_corner_radius_all(_RAIO_CANTO_PADRAO)
	sb.corner_detail = 6
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(COR_RECORDE.r, COR_RECORDE.g, COR_RECORDE.b, 0.75) if em_recorde else Color(cor.r, cor.g, cor.b, 0.55)
	sb.shadow_size = 30 if em_recorde else 18
	sb.anti_aliasing = true
	return sb

func _estilo_capsula(cor: Color, em_recorde: bool = false) -> StyleBoxFlat:
	# Mesmo raio de canto do card de pontuação/recorde (_RAIO_CANTO_PADRAO)
	# — antes a cápsula era bem mais arredondada (raio 16) que o card de
	# pontos (raio 10), então os dois pareciam de "famílias" diferentes
	# de UI. Agora seguem o mesmo padrão visual quadrado.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.040, 0.010, 0.95) if em_recorde else Color(0.045, 0.045, 0.065, 0.92)
	sb.border_color = COR_RECORDE if em_recorde else cor
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(_RAIO_CANTO_PADRAO)
	sb.corner_detail = 6
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(cor.r, cor.g, cor.b, 0.45)
	sb.shadow_size = 14
	sb.anti_aliasing = true
	return sb

func definir_pontos(idx: int, valor: int) -> void:
	if idx < 0 or idx >= num_jogadores:
		return
	_pontos[idx] = valor
	if idx == _jogador_atual:
		_atualizar_placar_labels()
	else:
		_reconstruir_players()



func iniciar_partida(segundos: float = -1.0) -> void:
	var duracao: float = tempo_partida
	if segundos > 0.0:
		duracao = segundos
		if not _shootout_ativo:
			tempo_partida = segundos

	_iniciar_ponte_leds_play()

	_tempo_restante = duracao
	_rodando = true

	_record_inicial_turno = record_maximo
	_recorde_celebrado_turno = false
	_desativar_visual_record()
	_resetar_combo()

	_enviar_led_basket("PLAY")
	_atualizar_tempo_label()



func pausar_partida() -> void:
	_rodando = false



func retomar_partida() -> void:
	if _tempo_restante > 0.0:
		_rodando = true



func encerrar_partida() -> void:
	_rodando = false
	_record_booster_ativo = false
	_record_booster_pulso = 0.0

	# Partida (todos os turnos) terminou: LEDs ficam em IDLE, ponte
	# continua aberta durante o pódio/confete. O desligamento de
	# verdade (OFF + fechar COM5) só acontece quando a TELA fecha de
	# fato — _fechar_tela_seguro() / _exit_tree() — ou quando o
	# jogador manda voltar ao menu.
	_enviar_led_basket("IDLE")

	# No pódio final a música da arena deve CONTINUAR tocando.
	# Antes ela era reduzida para -40 dB aqui, deixando o resultado sem energia.
	# Agora mantemos o loop de fundo e tocamos song_good_player por cima em _mostrar_podio().
	if musica_fundo != null:
		musica_fundo.volume_db = volume_musica_db
		if musica_fundo.stream != null and not musica_fundo.playing:
			musica_fundo.play()

	if usar_shootout_desempate and not _shootout_ativo and not _partida_teve_shootout:
		var empatados_primeiro: Array = _indices_empate_primeiro()
		if empatados_primeiro.size() >= 2:
			_iniciar_shootout_desempate(empatados_primeiro)
			return

	for n in [card_jogando, col_players]:
		if n != null:
			n.visible = false
	var finais: Array = []
	for i in range(num_jogadores):
		finais.append(_pontos[i])
	partida_encerrada.emit(finais)
	if mostrar_podio_automatico and _podio_layer == null:
		_mostrar_podio()



# =====================================================================
# GRADE DE TILES — efeito de fundo que afunda em ONDA na cesta
# =====================================================================
func _criar_grade_tiles() -> void:
	if grade_layer != null and is_instance_valid(grade_layer):
		return
	grade_layer = CanvasLayer.new()
	grade_layer.name = "GradeLayer"
	grade_layer.layer = 1   # entre o fundo (0) e o HUD (5)
	add_child(grade_layer)
	grade_ctrl = Control.new()
	grade_ctrl.name = "GradeCtrl"
	grade_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grade_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade_layer.add_child(grade_ctrl)
	if not grade_ctrl.draw.is_connected(_desenhar_grade):
		grade_ctrl.draw.connect(_desenhar_grade)
	_calcular_grade()



func _calcular_grade() -> void:
	var tela := get_viewport_rect().size
	_grade_passo = max(36.0, tela.y * 0.062)
	_grade_cols = int(ceil(tela.x / _grade_passo)) + 1
	_grade_rows = int(ceil(tela.y / _grade_passo)) + 1



func _disparar_onda_grade(origem: Vector2, inverso: bool = false, combo_nivel: int = 1, record_mode: bool = false, tipo: int = TipoOnda.RADIAL) -> void:
	var nivel: int = max(1, combo_nivel)

	var duracao: float = 1.10

	if record_mode:
		duracao = 1.28
	elif nivel >= 13:
		duracao = 1.34
	elif nivel >= 9:
		duracao = 1.26
	elif nivel >= 6:
		duracao = 1.18
	elif nivel >= 3:
		duracao = 0.84
	else:
		duracao = 1.12

	_grade_ondas.append({
		"origem": origem,
		"t": 0.0,
		"dur": duracao,
		"inverso": inverso,
		"combo": nivel,
		"ida_volta": nivel >= 6,
		"raio_extra": nivel >= 9,
		"raio_max": nivel >= 13,
		"record": record_mode,
		"tipo": tipo
	})



func _atualizar_grade(delta: float) -> void:
	if grade_ctrl == null:
		return
	if _grade_ondas.is_empty():
		# redesenha de leve mesmo parado (respiro do grid)
		grade_ctrl.queue_redraw()
		return
	var vivas: Array = []
	for o in _grade_ondas:
		o["t"] = float(o["t"]) + delta
		if float(o["t"]) < float(o["dur"]):
			vivas.append(o)
	_grade_ondas = vivas
	grade_ctrl.queue_redraw()



func _desenhar_grade() -> void:
	if grade_ctrl == null or _grade_passo <= 0.0:
		return

	var tela := get_viewport_rect().size
	var base_a := 0.024 + 0.010 * sin(_fx_tempo * 1.20)

	var origem_record := _record_origem_fx()
	var record_ciclo: float = 0.0
	var record_pulso: float = 0.0

	if _record_booster_ativo:
		record_ciclo = fposmod(_record_booster_pulso * 0.075, 1.0)
		record_pulso = 0.70 + 0.30 * abs(sin(_record_booster_pulso * 1.45))

	for gx in range(_grade_cols):
		for gy in range(_grade_rows):
			var p := Vector2(gx * _grade_passo, gy * _grade_passo)

			var afund := 0.0
			var acende := 0.0
			var combo_tile: int = 0

			# ============================================================
			# ONDAS NORMAIS / IMPACTO DE CESTA
			# ============================================================
			for o in _grade_ondas:
				var tipo_onda_tile: int = int(o.get("tipo", TipoOnda.RADIAL))
				var dist := _distancia_padrao_grade(p, o["origem"], tipo_onda_tile)
				var t := float(o["t"])
				var dur: float = max(0.01, float(o["dur"]))
				var combo_onda: int = int(o.get("combo", 1))
				var ida_volta: bool = bool(o.get("ida_volta", false))
				var raio_extra: bool = bool(o.get("raio_extra", false))
				var raio_max: bool = bool(o.get("raio_max", false))
				var record_onda: bool = bool(o.get("record", false))

				var prog: float = clampf(t / dur, 0.0, 1.0)

				var progs_raio: Array = []
				if ida_volta:
					var ping: float = p_ping_pong(prog)
					progs_raio.append(ping)

					if raio_extra:
						progs_raio.append(p_ping_pong(fposmod(prog + 0.24, 1.0)))
					if raio_max:
						progs_raio.append(p_ping_pong(fposmod(prog + 0.46, 1.0)))
				else:
					progs_raio.append(prog)

				for prog_raio in progs_raio:
					var raio := float(prog_raio) * (tela.x * 1.35)

					if bool(o.get("inverso", false)):
						raio = (1.0 - float(prog_raio)) * (tela.x * 1.35)

					var largura := tela.y * 0.105

					if record_onda:
						largura = tela.y * 0.090
					elif combo_onda >= 13:
						largura = tela.y * 0.155
					elif combo_onda >= 9:
						largura = tela.y * 0.145
					elif combo_onda >= 6:
						largura = tela.y * 0.135
					elif combo_onda >= 3:
						largura = tela.y * 0.118

					var d: float = abs(dist - raio)

					if d < largura:
						var k: float = 1.0 - (d / largura)
						k = pow(k, 1.85)

						var fade_tempo: float = 1.0 - prog
						if ida_volta:
							fade_tempo = 1.0 - abs(prog - 0.5) * 0.72

						k *= fade_tempo

						if k > acende:
							acende = k

							if record_onda:
								# Impacto da cesta no recorde:
								# linha amarela na frente e branca logo atrás.
								var faixa_idx: int = int(floor(raio / max(10.0, largura * 0.72))) % 2
								combo_tile = 1000 + faixa_idx
							else:
								combo_tile = combo_onda

						afund = max(afund, k)

			# ============================================================
			# RECORD ETERNO NA GRADE
			# Duas linhas de quadrados:
			# - frente amarela
			# - atrás branca
			# ============================================================
			if _record_booster_ativo:
				var dist_record: float = p.distance_to(origem_record)

				for w in range(2):
					var ciclo_w: float = fposmod(record_ciclo + float(w) * 0.50, 1.0)

					var raio_min: float = tela.y * 0.075
					var raio_max: float = max(tela.x, tela.y) * 0.590

					var raio_amarelo: float = lerpf(raio_min, raio_max, ciclo_w)
					var raio_branco: float = max(raio_min * 0.65, raio_amarelo - tela.y * 0.060)

					var envelope: float = sin(ciclo_w * PI)
					envelope = pow(max(0.0, envelope), 0.72)

					var largura_linha: float = max(_grade_passo * 0.42, tela.y * 0.022)

					# Linha branca atrás
					var d_branco: float = abs(dist_record - raio_branco)
					if d_branco < largura_linha:
						var kb: float = 1.0 - (d_branco / largura_linha)
						kb = pow(kb, 1.45) * envelope * record_pulso * 0.88

						if kb > acende:
							acende = kb
							combo_tile = 1001

						afund = max(afund, kb * 0.62)

					# Linha amarela na frente
					var d_amarelo: float = abs(dist_record - raio_amarelo)
					if d_amarelo < largura_linha:
						var ka: float = 1.0 - (d_amarelo / largura_linha)
						ka = pow(ka, 1.35) * envelope * record_pulso

						if ka > acende:
							acende = ka
							combo_tile = 1000

						afund = max(afund, ka * 0.80)

			var tam := _grade_passo * (0.38 + afund * 0.35)
			var off := afund * _grade_passo * 0.16
			var centro := p + Vector2(_grade_passo, _grade_passo) * 0.5 + Vector2(off, off)
			var meia := tam * 0.5
			var rect := Rect2(centro - Vector2(meia, meia), Vector2(tam, tam))

			var cor_base := COR_AZUL
			var cor_acende := Color.WHITE
			var extra_alpha: float = 0.0

			if combo_tile == 1000:
				# Linha da frente: AMARELA
				cor_base = Color(1.0, 0.78, 0.02)
				cor_acende = Color(1.0, 0.88, 0.14)
				extra_alpha = 0.12 * acende
			elif combo_tile == 1001:
				# Linha de trás: BRANCA
				cor_base = Color(1.0, 1.0, 1.0)
				cor_acende = Color(1.0, 1.0, 1.0)
				extra_alpha = 0.09 * acende
			elif combo_tile >= 13:
				cor_base = Color(0.62, 0.00, 0.00)
				cor_acende = Color(1.00, 0.03, 0.02)
				extra_alpha = 0.20 * abs(sin(_fx_tempo * 17.0))
			elif combo_tile >= 9:
				cor_base = Color(0.34, 0.05, 0.78)
				cor_acende = Color(0.82, 0.20, 1.00)
				extra_alpha = 0.17 * abs(sin(_fx_tempo * 14.0))
			elif combo_tile >= 6:
				cor_base = Color(0.02, 0.18, 0.85)
				cor_acende = Color(0.12, 0.55, 1.00)
				extra_alpha = 0.14 * abs(sin(_fx_tempo * 10.0))
			elif combo_tile >= 3:
				cor_base = Color(1.0, 0.30, 0.00)
				cor_acende = Color(1.0, 0.58, 0.04)
				extra_alpha = 0.11 * abs(sin(_fx_tempo * 7.0))
			elif combo_tile >= 1:
				cor_base = Color(0.75, 0.82, 1.0)
				cor_acende = Color.WHITE
				extra_alpha = 0.06 * abs(sin(_fx_tempo * 3.0))

			var a := base_a + acende * 0.46 + extra_alpha
			var cor := Color(cor_base.r, cor_base.g, cor_base.b, a)

			if acende > 0.18:
				var a_fx: float = clampf(a + acende * 0.36, 0.0, 0.95)
				cor = Color(cor_acende.r, cor_acende.g, cor_acende.b, a_fx)

			grade_ctrl.draw_rect(
				rect,
				cor,
				false,
				max(1.0, 1.0 + acende * 2.7),
				true
			)

			# Reforço interno somente nas linhas do recorde.
			if combo_tile >= 1000 and acende > 0.24:
				var inner_record := rect.grow(-max(3.0, _grade_passo * 0.16))
				if inner_record.size.x > 2.0 and inner_record.size.y > 2.0:
					grade_ctrl.draw_rect(
						inner_record,
						Color(cor_base.r, cor_base.g, cor_base.b, 0.08 + acende * 0.12),
						false,
						1.2,
						true
					)
			elif acende > 0.35:
				var inner := rect.grow(-max(2.0, _grade_passo * 0.11))
				if inner.size.x > 2.0 and inner.size.y > 2.0:
					grade_ctrl.draw_rect(
						inner,
						Color(cor.r, cor.g, cor.b, acende * 0.10),
						false,
						1.0,
						true
					)



func p_ping_pong(v: float) -> float:
	v = clampf(v, 0.0, 1.0)

	if v <= 0.5:
		return v * 2.0

	return (1.0 - v) * 2.0



# =====================================================================
# EFEITO DE CESTA (partículas + onda na grade)
# =====================================================================
func _efeito_cesta(combo_nivel: int = 1) -> void:
	var origem := _record_origem_fx()
	var tipo := _sortear_tipo_onda()

	_disparar_onda_grade(origem, false, combo_nivel, false, tipo)
	_disparar_luz_onda_cesta(origem, false, 1.0, combo_nivel, false, tipo)



func _efeito_cesta_record(grande: bool, combo_nivel: int = 4) -> void:
	# ANTES: com "grande" true, isso disparava onda de grade + onda de
	# luz DUAS VEZES cada (bloco comum + bloco "if grande") — o dobro
	# de tweens e desenho por frame bem no instante do recorde, causando
	# o engasgo. Agora dispara UMA vez cada, só com força maior.
	var origem := _record_origem_fx()
	var tipo := _sortear_tipo_onda()

	var forca_record: float = 1.85 if grande else 1.08

	_disparar_onda_grade(origem, false, 9, true, tipo)
	_disparar_luz_onda_cesta(origem, true, forca_record, 9, true, tipo)
	_disparar_particulas_cesta(origem, Color(1.0, 0.80, 0.20), 1.8 if grande else 1.3)

	if grande:
		_flash_bordas_record()


func _flash_recorde() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FlashRecordeLabel"
	layer.layer = 32
	add_child(layer)

	var raiz := Control.new()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(raiz)

	var painel := Panel.new()
	_ancorar(painel, 0.145, 0.325, 0.855, 0.405)
	painel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.025, 0.0, 0.88)
	sb.border_color = COR_RECORDE
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(22)
	sb.shadow_color = Color(COR_RECORDE.r, COR_RECORDE.g, COR_RECORDE.b, 0.82)
	sb.shadow_size = 30
	painel.add_theme_stylebox_override("panel", sb)

	raiz.add_child(painel)

	var lbl := Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.text = "RECORDE BATIDO!"
	lbl.add_theme_font_size_override("font_size", _fs(0.040))
	lbl.add_theme_color_override("font_color", COR_RECORDE_CLARO)
	lbl.add_theme_color_override("font_outline_color", Color(0.28, 0.08, 0.0))
	lbl.add_theme_constant_override("outline_size", 7)
	_aplicar_fonte(lbl)
	painel.add_child(lbl)

	painel.pivot_offset = painel.size * 0.5
	painel.scale = Vector2(0.72, 0.72)
	painel.modulate.a = 0.0

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(painel, "modulate:a", 1.0, 0.12)
	t.tween_property(painel, "scale", Vector2(1.0, 1.0), 0.30)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(0.80).timeout

	var t2 := create_tween()
	t2.set_parallel(true)
	t2.tween_property(painel, "scale", Vector2(1.08, 1.08), 0.22)
	t2.tween_property(painel, "modulate:a", 0.0, 0.28)
	await t2.finished

	if is_instance_valid(layer):
		layer.queue_free()



func _flash_bordas_record() -> void:
	# Moldura dourada que pisca uma vez nas bordas da tela.
	var layer := CanvasLayer.new()
	layer.name = "FlashRecordeBordas"
	layer.layer = 13
	add_child(layer)
	var moldura := Panel.new()
	moldura.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	moldura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(COR_RECORDE.r, COR_RECORDE.g, COR_RECORDE.b, 0.9)
	sb.set_border_width_all(10)
	sb.shadow_color = Color(1.0, 0.78, 0.14, 0.6)
	sb.shadow_size = 40
	moldura.add_theme_stylebox_override("panel", sb)
	layer.add_child(moldura)
	moldura.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(moldura, "modulate:a", 1.0, 0.12)
	t.tween_property(moldura, "modulate:a", 0.0, 0.5)
	t.tween_callback(layer.queue_free)



func _textura_brilho() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64; tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex



# =====================================================================
# INPUT
# =====================================================================
func _unhandled_input(evento: InputEvent) -> void:
	if evento is InputEventKey and evento.pressed and not evento.echo and evento.keycode == KEY_F10:
		_abrir_config_overlay()
		_input_handled_seguro()
		return

	if _config_overlay_ativo != null and is_instance_valid(_config_overlay_ativo):
		return
	
	# Alt+F4 fecha a tela com segurança.
	if evento is InputEventKey:
		if evento.pressed and not evento.echo and evento.keycode == KEY_F4 and evento.alt_pressed:
			_fechar_tela_seguro()
			_input_handled_seguro()
			return

	if _modal_turno_ativo:
		if _modal_turno_pronto and (_evento_start(evento) or _evento_tecla_1(evento)):
			_iniciar_turno_atual()
			_input_handled_seguro()
		return
	if _podio_ativo:
		if _evento_start(evento) or _evento_tecla_1(evento):
			_registrar_pulso_reinicio_podio()
			_input_handled_seguro()
		return
	if _rodando and _acao(evento, acao_cesta):
		if _trava_cesta_t > 0.0:
			_input_handled_seguro()
			return

		_trava_cesta_t = tempo_trava_cesta
		adicionar_ponto_jogador_atual(pontos_por_cesta)
		_input_handled_seguro()
		return



func _abrir_config_overlay() -> void:
	if _config_overlay_ativo != null and is_instance_valid(_config_overlay_ativo):
		return
	if _fechando_tela:
		return

	var script_config := load("res://scripts/config_overlay.gd")
	if script_config == null:
		push_warning("Play: config_overlay.gd não encontrado.")
		return

	_estava_rodando_antes_config = _rodando
	_rodando = false

	var camada := CanvasLayer.new()
	camada.name = "ConfigOverlayLayer"
	camada.layer = 500
	add_child(camada)

	var overlay: Control = script_config.new()
	overlay.name = "ConfigOverlay"
	overlay.modo_overlay = true
	overlay.fechado.connect(_ao_fechar_config_overlay.bind(camada))
	camada.add_child(overlay)

	_config_overlay_ativo = overlay



func _ao_fechar_config_overlay(salvou: bool, camada: CanvasLayer) -> void:
	_config_overlay_ativo = null

	if camada != null and is_instance_valid(camada):
		camada.queue_free()

	if salvou:
		# Aplica tempo/modo/delay-de-cesta e o LOGO escolhido na hora,
		# sem reiniciar a partida em andamento. O FUNDO da tela nunca
		# muda aqui — ele é fixo em caminho_fundo (back_basquet.png).
		_aplicar_config_basket()
		_carregar_logo_canto_inferior()
		_atualizar_tempo_label()

	if _estava_rodando_antes_config:
		_rodando = true



func _input_handled_seguro() -> void:
	if not is_inside_tree():
		return
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.set_input_as_handled()



func _acao(evento: InputEvent, nome: String) -> bool:
	return nome != "" and InputMap.has_action(nome) and evento.is_action_pressed(nome)



func _evento_start(evento: InputEvent) -> bool:
	if not evento.is_pressed():
		return false
	if evento is InputEventKey and evento.echo:
		return false
	return _acao(evento, acao_start)



func _evento_tecla_1(evento: InputEvent) -> bool:
	if evento is InputEventKey and evento.pressed and not evento.echo:
		return evento.keycode == KEY_1 or evento.keycode == KEY_KP_1
	return false



func _voltar_abertura() -> void:
	_podio_ativo = false
	await _transicao_saida("SAINDO DA ARENA", "VOLTANDO AO MENU")
	if cena_abertura != "":
		_trocar_cena(cena_abertura)
	else:
		var tela_node := get_node_or_null("/root/Tela")
		if tela_node != null and tela_node.has_method("recarregar"):
			tela_node.recarregar()
		else:
			get_tree().reload_current_scene()



# =====================================================================
# TEMPO / FUNDO / CONFIG
# =====================================================================
func _atualizar_tempo_label() -> void:
	if lbl_crono == null:
		return
	var total := int(ceil(_tempo_restante))
	lbl_crono.text = str(total)
	if _tempo_restante <= 10.0 and _rodando:
		lbl_crono.add_theme_color_override("font_color", Color(1, 0.4, 0.35))
	else:
		lbl_crono.add_theme_color_override("font_color", COR_VERDE_DISPLAY)



func _carregar_fundo() -> void:
	if fundo == null:
		return
	var tex := load(caminho_fundo) as Texture2D
	if tex:
		fundo.texture = tex
	else:
		push_warning("Game: fundo não encontrado em " + caminho_fundo)



func _aplicar_config_basket() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(caminho_config_basket)

	if not usar_config_tempo_partida:
		tempo_partida = 60.0
		modo_credito = false
	elif err == OK:
		tempo_partida = float(cfg.get_value("jogo", "tempo_partida", 60.0))
		modo_credito = bool(cfg.get_value("jogo", "modo_credito", false))
		var modo_txt: String = str(cfg.get_value("jogo", "modo_operacao", "livre")).to_lower()
		if modo_txt == "credito" or modo_txt == "crédito":
			modo_credito = true
	else:
		tempo_partida = 60.0
		modo_credito = false

	# Delay entre cestas e o LOGO da empresa são lidos do config
	# INDEPENDENTE de usar_config_tempo_partida — são ajustados numa
	# seção separada da tela de configuração (F10) e sempre devem
	# valer, mesmo que o tempo de partida esteja configurado para
	# ignorar o arquivo salvo.
	#
	# IMPORTANTE: o FUNDO da tela de jogo (caminho_fundo) NUNCA é lido
	# daqui — ele é sempre "res://images/back_basquet.png", fixo. O
	# único elemento visual configurável pela tela de configuração é
	# o LOGO da empresa no canto inferior esquerdo (_logo_empresa_config),
	# usado em _carregar_logo_canto_inferior().
	if err == OK:
		tempo_trava_cesta = float(cfg.get_value("jogo", "tempo_trava_cesta", tempo_trava_cesta))
		_logo_empresa_config = str(cfg.get_value("jogo", "logo_empresa", ""))
	else:
		# Ainda não existe config salva: grava os valores atuais (padrão
		# dos @export) para a tela de configuração já abrir com algo
		# coerente na primeira vez que for aberta.
		cfg.set_value("jogo", "tempo_partida", tempo_partida)
		cfg.set_value("jogo", "modo_credito", modo_credito)
		cfg.set_value("jogo", "modo_operacao", "credito" if modo_credito else "livre")
		cfg.set_value("jogo", "tempo_trava_cesta", tempo_trava_cesta)
		cfg.save(caminho_config_basket)
		_logo_empresa_config = ""

	tempo_partida = clampf(tempo_partida, 10.0, 600.0)
	tempo_trava_cesta = clampf(tempo_trava_cesta, 0.30, 3.00)



func _aplicar_shader_fundo_retrato() -> void:
	if fundo == null:
		return
	if not usar_shader_fundo:
		fundo.material = null
		return
	# Fundo "arcade china": azul-elétrico, raios laterais subindo, bloom suave,
	# grão fino anti-banding. Sem quadriculado pixelado.
	var shader := Shader.new()
	var s: String = ""
	s += "shader_type canvas_item;\n"
	s += "render_mode unshaded;\n"
	s += "uniform float intensidade = 0.40;\n"
	s += "float hash(vec2 p){ return fract(sin(dot(p, vec2(41.0,289.0)))*43758.5453); }\n"
	s += "float ruido(vec2 p){ vec2 i=floor(p); vec2 f=fract(p);\n"
	s += "  float a=hash(i); float b=hash(i+vec2(1.0,0.0));\n"
	s += "  float c=hash(i+vec2(0.0,1.0)); float d=hash(i+vec2(1.0,1.0));\n"
	s += "  vec2 u=f*f*(3.0-2.0*f);\n"
	s += "  return mix(mix(a,b,u.x),mix(c,d,u.x),u.y); }\n"
	s += "void fragment(){\n"
	s += "  vec2 uv=UV;\n"
	s += "  vec4 base=texture(TEXTURE,uv);\n"
	s += "  vec2 c=uv-vec2(0.5,0.42);\n"
	s += "  float d=length(c);\n"
	s += "  float vin=smoothstep(1.1,0.2,d);\n"
	s += "  base.rgb*=0.45+vin*0.55;\n"
	s += "  vec3 azul=vec3(0.12,0.45,1.0);\n"
	s += "  vec3 ciano=vec3(0.2,0.8,1.0);\n"
	s += "  base.rgb=mix(base.rgb, base.rgb*azul*1.3, 0.30);\n"
	# raios verticais nas laterais (descargas elétricas)
	# raios verticais nas laterais (descargas elétricas)
	s += "  float borda=smoothstep(0.30,0.0,uv.x)+smoothstep(0.70,1.0,uv.x);\n"
	s += "  float ray=ruido(vec2(uv.x*8.0, uv.y*3.0 - TIME*1.4));\n"
	s += "  ray=pow(ray,4.0)*borda;\n"
	s += "  base.rgb+=ciano*ray*intensidade*0.9;\n"
	# varredura horizontal — a tela agora é larga (paisagem), então um
	# feixe sutil cruzando de um lado a outro preenche melhor o espaço
	# que antes ficava vazio nas laterais em telas widescreen.
	s += "  float sweepH=sin(uv.x*2.4 - TIME*0.55);\n"
	s += "  sweepH=smoothstep(0.985,1.0,sweepH);\n"
	s += "  base.rgb+=ciano*sweepH*intensidade*0.55;\n"
	# brilho central pulsante (arena)
	# brilho central pulsante (arena)
	s += "  float pulso=0.85+0.15*sin(TIME*1.3);\n"
	s += "  float arena=smoothstep(0.65,0.0,d);\n"
	s += "  base.rgb+=azul*arena*intensidade*0.18*pulso;\n"
	# bloom fake
	s += "  float lum=dot(base.rgb,vec3(0.299,0.587,0.114));\n"
	s += "  float bloom=smoothstep(0.55,1.0,lum);\n"
	s += "  base.rgb+=base.rgb*bloom*0.45;\n"
	# grão anti-banding
	s += "  float n=ruido(uv*vec2(440.0,760.0)+TIME*0.6);\n"
	s += "  base.rgb+=(n-0.5)*0.015;\n"
	s += "  COLOR=base;\n"
	s += "}\n"
	shader.code = s
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("intensidade", intensidade_luz_fundo)
	fundo.material = mat



# =====================================================================
# FX AMBIENTE (bokeh suave)
# =====================================================================
func _criar_fx_ambiente() -> void:
	if not usar_fx_ambiente:
		return
	if fx_ambiente_layer != null and is_instance_valid(fx_ambiente_layer):
		return
	fx_ambiente_layer = CanvasLayer.new()
	fx_ambiente_layer.name = "FxAmbienteLayer"
	fx_ambiente_layer.layer = 2
	add_child(fx_ambiente_layer)
	fx_ambiente = Control.new()
	fx_ambiente.name = "FxAmbiente"
	fx_ambiente.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx_ambiente.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_ambiente_layer.add_child(fx_ambiente)
	if not fx_ambiente.draw.is_connected(_desenhar_fx_ambiente):
		fx_ambiente.draw.connect(_desenhar_fx_ambiente)



func _atualizar_fx_ambiente(delta: float) -> void:
	if fx_ambiente == null:
		return
	_fx_tempo += delta
	fx_ambiente.queue_redraw()



func _desenhar_fx_ambiente() -> void:
	if fx_ambiente == null:
		return
	var tela := get_viewport_rect().size
	var centro := Vector2(tela.x * 0.5, tela.y * 0.245)
	for a in range(5):
		var raio := 90.0 + a * 55.0 + sin(_fx_tempo * 1.2 + a) * 8.0
		fx_ambiente.draw_circle(centro, raio, Color(COR_AZUL.r, COR_AZUL.g, COR_AZUL.b, 0.014 - a * 0.0022))



# =====================================================================
# RECORDE
# =====================================================================
func _carregar_record_basket() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(caminho_record_basket)
	if err == OK:
		record_maximo = int(cfg.get_value("recorde", "maximo", 0))
	else:
		record_maximo = 0
		cfg.set_value("recorde", "maximo", record_maximo)
		cfg.save(caminho_record_basket)



func _salvar_record_basket() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("recorde", "maximo", record_maximo)
	cfg.save(caminho_record_basket)



func _verificar_recorde_atual() -> void:
	if _jogador_atual < 0 or _jogador_atual >= num_jogadores:
		return
	var pontos_atuais: int = int(_pontos[_jogador_atual])
	if pontos_atuais > record_maximo:
		record_maximo = pontos_atuais
		_salvar_record_basket()
		_atualizar_high_label()
		_atualizar_placar_labels()



# =====================================================================
# TRANSIÇÃO
# =====================================================================
func _criar_transicao_layer() -> void:
	if transicao_layer != null and is_instance_valid(transicao_layer):
		return
	transicao_layer = CanvasLayer.new()
	transicao_layer.name = "TransicaoLayer"
	transicao_layer.layer = 100
	add_child(transicao_layer)
	transicao_root = Control.new()
	transicao_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transicao_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transicao_layer.add_child(transicao_root)
	transicao_fundo = ColorRect.new()
	transicao_fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transicao_fundo.color = Color(0.0, 0.0, 0.0, 1.0)
	transicao_fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transicao_root.add_child(transicao_fundo)
	transicao_fx = Control.new()
	transicao_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transicao_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transicao_root.add_child(transicao_fx)
	if not transicao_fx.draw.is_connected(_desenhar_transicao_fx):
		transicao_fx.draw.connect(_desenhar_transicao_fx)
	transicao_titulo = Label.new()
	transicao_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	transicao_titulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	transicao_titulo.add_theme_font_size_override("font_size", _fs(0.052))
	transicao_titulo.add_theme_color_override("font_color", Color.WHITE)
	transicao_titulo.add_theme_color_override("font_outline_color", COR_VERDE_DISPLAY)
	transicao_titulo.add_theme_constant_override("outline_size", 9)
	_aplicar_fonte(transicao_titulo)
	transicao_root.add_child(transicao_titulo)
	transicao_subtitulo = Label.new()
	transicao_subtitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	transicao_subtitulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	transicao_subtitulo.add_theme_font_size_override("font_size", _fs(0.022))
	transicao_subtitulo.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	transicao_subtitulo.add_theme_color_override("font_outline_color", Color.BLACK)
	transicao_subtitulo.add_theme_constant_override("outline_size", 4)
	_aplicar_fonte(transicao_subtitulo)
	transicao_root.add_child(transicao_subtitulo)
	transicao_barra_fundo = Panel.new()
	transicao_barra_fundo.add_theme_stylebox_override("panel", _estilo_barra_transicao(false))
	transicao_root.add_child(transicao_barra_fundo)
	transicao_barra = ColorRect.new()
	transicao_barra.color = COR_VERDE_DISPLAY
	transicao_barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transicao_root.add_child(transicao_barra)
	_ajustar_transicao_layout()
	transicao_root.visible = false



func _ajustar_transicao_layout() -> void:
	if transicao_root == null:
		return
	var tela := get_viewport_rect().size
	transicao_root.position = Vector2.ZERO
	transicao_root.size = tela
	if transicao_fundo != null:
		transicao_fundo.position = Vector2.ZERO; transicao_fundo.size = tela
	if transicao_fx != null:
		transicao_fx.position = Vector2.ZERO; transicao_fx.size = tela
	if transicao_titulo != null:
		transicao_titulo.position = Vector2(0.0, tela.y * 0.395); transicao_titulo.size = Vector2(tela.x, tela.y * 0.105)
	if transicao_subtitulo != null:
		transicao_subtitulo.position = Vector2(0.0, tela.y * 0.505); transicao_subtitulo.size = Vector2(tela.x, tela.y * 0.060)
	var barra_w: float = tela.x * 0.66
	var barra_h: float = max(12.0, tela.y * 0.012)
	var barra_x: float = (tela.x - barra_w) * 0.5
	var barra_y: float = tela.y * 0.605
	if transicao_barra_fundo != null:
		transicao_barra_fundo.position = Vector2(barra_x, barra_y); transicao_barra_fundo.size = Vector2(barra_w, barra_h)
	if transicao_barra != null:
		transicao_barra.position = Vector2(barra_x + 3.0, barra_y + 3.0); transicao_barra.size = Vector2(1.0, max(2.0, barra_h - 6.0))



func _estilo_barra_transicao(ativo: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.10, 0.92)
	sb.border_color = COR_AZUL
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(20)
	sb.shadow_color = Color(COR_AZUL.r, COR_AZUL.g, COR_AZUL.b, 0.42)
	sb.shadow_size = 18 if ativo else 10
	return sb



func _transicao_entrada(titulo: String, subtitulo: String) -> void:
	if transicao_root == null:
		return
	_ajustar_transicao_layout()
	_transicao_ativa = true
	_transicao_t = 0.0
	transicao_root.visible = true
	transicao_root.modulate.a = 1.0
	transicao_titulo.text = titulo
	transicao_subtitulo.text = subtitulo
	var tela := get_viewport_rect().size
	var barra_w_final: float = max(1.0, tela.x * 0.66 - 6.0)
	transicao_barra.size.x = 1.0
	transicao_fx.queue_redraw()

	# Garante que a tela "CARREGANDO ARENA" já está desenhada e visível
	# ANTES de travar a thread principal conectando os LEDs — assim o
	# delay de abrir a COM5 acontece escondido atrás do loading, em vez
	# de travar o jogo bem no início da partida de verdade.
	await get_tree().process_frame

	_montar_arena_durante_loading()

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(transicao_barra, "size:x", barra_w_final, 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(transicao_root, "modulate:a", 0.0, 0.42).set_delay(0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	transicao_root.visible = false
	_transicao_ativa = false



func _montar_arena_durante_loading() -> void:
	# Conecta a ponte dos LEDs (abre a COM5) enquanto a tela de loading
	# ainda está por cima de tudo. Antes mandava OFF aqui e o LED ficava
	# apagado até apertar START — agora entra direto em modo de espera
	# (IDLE), então quando a modal "ORDEM DE JOGO" aparece os LEDs já
	# estão rodando, bem antes da contagem regressiva começar.
	_iniciar_ponte_leds_play()
	_enviar_led_basket("IDLE")

	if transicao_subtitulo != null:
		transicao_subtitulo.text = "PREPARE-SE PARA O DESAFIO"



func _transicao_saida(titulo: String, subtitulo: String) -> void:
	if transicao_root == null:
		return
	_ajustar_transicao_layout()
	_transicao_ativa = true
	_transicao_t = 0.0
	transicao_root.visible = true
	transicao_root.modulate.a = 0.0
	transicao_titulo.text = titulo
	transicao_subtitulo.text = subtitulo
	transicao_barra.size.x = 1.0
	transicao_fx.queue_redraw()
	var tela := get_viewport_rect().size
	var barra_w_final: float = max(1.0, tela.x * 0.66 - 6.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(transicao_root, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(transicao_barra, "size:x", barra_w_final, 0.56).set_delay(0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	_transicao_ativa = false



func _desenhar_transicao_fx() -> void:
	if transicao_fx == null:
		return
	var tela := get_viewport_rect().size
	var centro := Vector2(tela.x * 0.5, tela.y * 0.48)
	for i in range(7):
		var raio := 80.0 + float(i) * 52.0 + sin(_transicao_t * 2.2 + float(i)) * 8.0
		var alpha := 0.09 - float(i) * 0.010
		transicao_fx.draw_arc(centro, raio, _transicao_t + float(i) * 0.3,
			_transicao_t + TAU * 0.72 + float(i) * 0.3, 90,
			Color(COR_AZUL.r, COR_AZUL.g, COR_AZUL.b, alpha), 4.0, true)



# =====================================================================
# PÓDIO (mantido do anterior, cores ajustadas ao tema)
# =====================================================================
func _mostrar_podio() -> void:
	var ordem := _ranking()
	_tocar_song_good_player_podio()
	_podio_retorno_token += 1
	lbl_podio_timer = null
	lbl_podio_cta_principal = null
	lbl_podio_cta_sub = null
	_podio_reinicio_coletando = false
	_podio_reinicio_confirmando = false
	_podio_reinicio_pulsos = 0
	_podio_reinicio_deadline_ms = 0
	_podio_reinicio_hard_deadline_ms = 0
	_podio_ativo = false
	_podio_layer = CanvasLayer.new()
	_podio_layer.name = "PodioLayer"
	_podio_layer.layer = 20
	add_child(_podio_layer)
	var escuro := ColorRect.new()
	escuro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	escuro.color = Color(0.0, 0.0, 0.0, 0.0)
	escuro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_podio_layer.add_child(escuro)
	var raiz := Control.new()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.modulate.a = 0.0
	raiz.position.y = 90.0
	_podio_layer.add_child(raiz)

	var tela := get_viewport_rect().size

	var painel_fundo := Panel.new()
	_ancorar(painel_fundo, 0.040, 0.055, 0.960, 0.935)
	painel_fundo.add_theme_stylebox_override("panel", _estilo_painel_resultado())
	raiz.add_child(painel_fundo)

	var titulo := Label.new()
	titulo.text = "RESULTADO FINAL"
	_ancorar(titulo, 0.05, 0.072, 0.95, 0.132)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", _fs(0.050))
	titulo.add_theme_color_override("font_color", Color.WHITE)
	titulo.add_theme_color_override("font_outline_color", COR_AZUL)
	titulo.add_theme_constant_override("outline_size", 9)
	_aplicar_fonte(titulo)
	raiz.add_child(titulo)

	var subtitulo := Label.new()
	subtitulo.text = "RESULTADO NORMAL + SHOOTOUT" if _partida_teve_shootout else "COMPARATIVO DE CESTAS"
	_ancorar(subtitulo, 0.05, 0.132, 0.95, 0.174)
	subtitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitulo.add_theme_font_size_override("font_size", _fs(0.022))
	subtitulo.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	subtitulo.add_theme_color_override("font_outline_color", Color.BLACK)
	subtitulo.add_theme_constant_override("outline_size", 4)
	_aplicar_fonte(subtitulo)
	raiz.add_child(subtitulo)

	# ---------------------------------------------------------------
	# FAIXA DAS COLUNAS — âncoras isoladas, com respiro de verdade antes
	# do CTA abaixo (antes a faixa ia até 0.660 e o CTA começava em
	# 0.700 — só 4% de gap, insuficiente quando o card estourava por
	# usar altura fixa em pixels). Agora além do gap maior, a altura
	# do card é derivada desta MESMA faixa (ver altura_banda abaixo),
	# então é fisicamente impossível o card passar do que reservamos.
	# ---------------------------------------------------------------
	var linha := HBoxContainer.new()
	linha.alignment = BoxContainer.ALIGNMENT_CENTER
	linha.add_theme_constant_override("separation", 16)
	# Sem clip: o glow das medalhas e das animações não será cortado.
	# A largura fixa das colunas abaixo é que controla o enquadramento.
	linha.clip_contents = false
	_ancorar(linha, 0.065, 0.192, 0.935, 0.630)
	raiz.add_child(linha)

	_podio_linha_dif = Control.new()
	_podio_linha_dif.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ancorar(_podio_linha_dif, 0.0, 0.0, 1.0, 1.0)
	_podio_linha_dif.modulate.a = 0.0
	raiz.add_child(_podio_linha_dif)
	if not _podio_linha_dif.draw.is_connected(_desenhar_linha_diferenca):
		_podio_linha_dif.draw.connect(_desenhar_linha_diferenca)

	var altura_banda: float = (0.630 - 0.192) * tela.y

	var maior_ponto: int = 0
	for i in range(num_jogadores):
		maior_ponto = max(maior_ponto, int(_pontos[i]))
	var ordem_crescente: Array = ordem.duplicate()
	ordem_crescente.reverse()
	var cards_animar: Array = []
	_podio_cards_ref.clear()
	for idx in ordem_crescente:
		var lugar := ordem.find(idx) + 1
		var card_info: Dictionary = _criar_coluna_resultado(linha, idx, lugar, maior_ponto, altura_banda)
		card_info["cestas_real"] = int(_pontos[idx])
		cards_animar.append(card_info)
		_podio_cards_ref.append(card_info)

	# ---------------------------------------------------------------
	# CTA "APERTE START" — badge próprio, com espaço reservado e
	# separado das colunas, feito pra leitura a ~5m de distância.
	# ---------------------------------------------------------------
	var painel_cta := Panel.new()
	_ancorar(painel_cta, 0.180, 0.664, 0.820, 0.826)
	painel_cta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painel_cta.add_theme_stylebox_override("panel", _estilo_cta_podio())
	raiz.add_child(painel_cta)

	lbl_podio_cta_principal = Label.new()
	lbl_podio_cta_principal.text = _texto_podio_chamada_inicial()
	_ancorar(lbl_podio_cta_principal, 0.04, 0.04, 0.96, 0.60)
	lbl_podio_cta_principal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_podio_cta_principal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_podio_cta_principal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_podio_cta_principal.add_theme_font_size_override("font_size", _fs(0.058))
	lbl_podio_cta_principal.add_theme_color_override("font_color", Color.WHITE)
	lbl_podio_cta_principal.add_theme_color_override("font_outline_color", COR_VERDE_DISPLAY)
	lbl_podio_cta_principal.add_theme_constant_override("outline_size", 10)
	_aplicar_fonte(lbl_podio_cta_principal)
	painel_cta.add_child(lbl_podio_cta_principal)

	lbl_podio_cta_sub = Label.new()
	lbl_podio_cta_sub.text = _texto_podio_sub_inicial()
	_ancorar(lbl_podio_cta_sub, 0.04, 0.62, 0.96, 0.94)
	lbl_podio_cta_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_podio_cta_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_podio_cta_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_podio_cta_sub.add_theme_font_size_override("font_size", _fs(0.026))
	lbl_podio_cta_sub.add_theme_color_override("font_color", COR_AMBAR)
	lbl_podio_cta_sub.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl_podio_cta_sub.add_theme_constant_override("outline_size", 5)
	_aplicar_fonte(lbl_podio_cta_sub)
	painel_cta.add_child(lbl_podio_cta_sub)

	lbl_podio_timer = Label.new()
	lbl_podio_timer.text = "AGUARDE O RESULTADO..."
	_ancorar(lbl_podio_timer, 0.05, 0.848, 0.95, 0.892)
	lbl_podio_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_podio_timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_podio_timer.add_theme_font_size_override("font_size", _fs(0.026))
	lbl_podio_timer.add_theme_color_override("font_color", Color(0.86, 0.90, 1.0))
	lbl_podio_timer.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl_podio_timer.add_theme_constant_override("outline_size", 4)
	_aplicar_fonte(lbl_podio_timer)
	raiz.add_child(lbl_podio_timer)

	var t1 := create_tween()
	t1.tween_property(escuro, "color:a", 0.84, 0.40)
	var t2 := create_tween()
	t2.set_parallel(true)
	t2.tween_property(raiz, "modulate:a", 1.0, 0.42)
	t2.tween_property(raiz, "position:y", 0.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t2.finished
	for i in range(cards_animar.size()):
		await _animar_coluna_resultado(cards_animar[i], 0.0)
		await get_tree().create_timer(0.12).timeout
	if num_jogadores >= 2 and _podio_linha_dif != null:
		await get_tree().create_timer(0.10).timeout
		_podio_linha_dif.queue_redraw()
		var tl := create_tween()
		tl.tween_property(_podio_linha_dif, "modulate:a", 1.0, 0.45)
		await tl.finished
		await get_tree().create_timer(1.8).timeout
		var ts := create_tween()
		ts.tween_property(_podio_linha_dif, "modulate:a", 0.0, 0.55)
		await ts.finished
	await get_tree().create_timer(0.15).timeout
	_disparar_confete()
	await get_tree().create_timer(0.7).timeout
	lbl_podio_timer.text = "Volta ao menu em %ds" % segundos_retorno_opening_podio
	var pisca := create_tween().set_loops()
	if lbl_podio_cta_principal != null:
		pisca.tween_property(lbl_podio_cta_principal, "modulate:a", 0.35, 0.6)
		pisca.tween_property(lbl_podio_cta_principal, "modulate:a", 1.0, 0.6)
	_podio_ativo = true
	_contagem_retorno_opening_podio(_podio_retorno_token)



func _desenhar_linha_diferenca() -> void:
	if _podio_linha_dif == null or _podio_cards_ref.size() < 2:
		return
	var tela := get_viewport_rect().size
	var gap: float = tela.y * 0.045
	var inv := _podio_linha_dif.get_global_transform().affine_inverse()
	var col_tops: Array = []
	var marcadores: Array = []
	var valores: Array = []
	for info in _podio_cards_ref:
		var card: Panel = info.get("card", null)
		if card == null or not is_instance_valid(card):
			continue
		var topo_global: Vector2 = card.global_position + Vector2(card.size.x * 0.5, 0.0)
		var topo_local: Vector2 = inv * topo_global
		col_tops.append(topo_local)
		marcadores.append(topo_local - Vector2(0.0, gap))
		valores.append(int(info.get("cestas_real", info.get("cestas", 0))))
	if marcadores.size() < 2:
		return
	var cor_linha := Color(COR_AZUL.r, COR_AZUL.g, COR_AZUL.b, 0.95)
	for i in range(marcadores.size()):
		_podio_linha_dif.draw_line(col_tops[i], marcadores[i], Color(cor_linha.r, cor_linha.g, cor_linha.b, 0.30), 2.0, true)
	for i in range(marcadores.size() - 1):
		_desenhar_tracejado(marcadores[i], marcadores[i + 1], cor_linha, 3.0, 14.0, 8.0)
	for m in marcadores:
		_podio_linha_dif.draw_circle(m, 6.0, cor_linha)
		_podio_linha_dif.draw_circle(m, 3.0, Color(1, 1, 1, 0.95))
	var fonte := ThemeDB.fallback_font
	var tam := _fs(0.019)
	for i in range(marcadores.size() - 1):
		var dif: int = valores[i + 1] - valores[i]
		if dif == 0:
			continue
		var meio: Vector2 = (marcadores[i] + marcadores[i + 1]) * 0.5 + Vector2(0.0, -14.0)
		var txt := "+%d" % dif
		var largura := fonte.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
		_podio_linha_dif.draw_string(fonte, meio - Vector2(largura * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, COR_AMBAR)



func _desenhar_tracejado(de: Vector2, ate: Vector2, cor: Color, esp: float, traco: float, vao: float) -> void:
	var total: float = de.distance_to(ate)
	if total <= 0.0:
		return
	var dir: Vector2 = (ate - de) / total
	var pos: float = 0.0
	while pos < total:
		var ini: Vector2 = de + dir * pos
		var fim: Vector2 = de + dir * min(pos + traco, total)
		_podio_linha_dif.draw_line(ini, fim, cor, esp, true)
		pos += traco + vao



func _ranking() -> Array:
	var idxs: Array = []
	for i in range(num_jogadores):
		idxs.append(i)
	idxs.sort_custom(func(a, b):
		if int(_pontos[a]) == int(_pontos[b]):
			var sa: int = int(_shootout_pontos_total[a]) if _partida_teve_shootout else 0
			var sb: int = int(_shootout_pontos_total[b]) if _partida_teve_shootout else 0
			if sa == sb:
				return a < b
			return sa > sb
		return int(_pontos[a]) > int(_pontos[b])
	)
	return idxs



func _cor_medalha(lugar: int) -> Color:
	match lugar:
		1: return Color(1.0, 0.84, 0.0)
		2: return Color(0.75, 0.75, 0.8)
		3: return Color(0.8, 0.5, 0.2)
		_: return Color(0.6, 0.6, 0.6)



const _CORES_CONFETE := [
	Color(1.0, 0.46, 0.04),   # laranja principal (tema da arena)
	Color(1.0, 0.62, 0.08),   # âmbar
	Color(1.0, 0.30, 0.02),   # laranja queimado
	Color(1.0, 0.84, 0.30),   # dourado claro
	Color(1.0, 0.90, 0.74),   # quente quase-branco (brilho/contraste)
]


func _textura_confete_generico(cor: Color, larg: int, alt: int) -> Texture2D:
	# Faixa de brilho mais ESTREITA e com queda mais acentuada nas bordas
	# (efeito "folha metálica") em vez do degradê suave e lavado de antes
	# — lê muito mais definido a distância, sem virar um borrão de cor.
	var img := Image.create(larg, alt, false, Image.FORMAT_RGBA8)
	for y in range(alt):
		var fy: float = float(y) / float(max(1, alt - 1))
		var centro_dist: float = abs(fy - 0.5) * 2.0
		var brilho: float = 1.0 - pow(centro_dist, 1.6) * 0.78
		for x in range(larg):
			var a: float = 1.0
			if x == 0 or x == larg - 1 or y == 0 or y == alt - 1:
				a = 0.0
			img.set_pixel(x, y, Color(
				clampf(cor.r * brilho + 0.08, 0.0, 1.0),
				clampf(cor.g * brilho + 0.04, 0.0, 1.0),
				clampf(cor.b * brilho, 0.0, 1.0),
				a
			))
	return ImageTexture.create_from_image(img)


func _emissor_confete_chuva(tela: Vector2) -> void:
	for i in range(4):
		var cor: Color = _CORES_CONFETE[i % _CORES_CONFETE.size()]
		var p := CPUParticles2D.new()
		p.position = Vector2(tela.x * 0.5, -30.0)
		p.amount = 60
		# Antes: lifetime 3.6s com gravidade fraca e damping forte — o
		# confete quase flutuava, sem energia. Agora cai rápido do
		# início ao fim (mais gravidade, mais velocidade inicial, quase
		# sem damping) e some da tela bem mais cedo.
		p.lifetime = 2.2
		p.explosiveness = 0.08
		p.randomness = 0.55
		p.lifetime_randomness = 0.35
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(tela.x * 0.54, 6.0)
		p.direction = Vector2(0, 1)
		p.spread = 14.0
		p.gravity = Vector2(0, 340.0)
		p.initial_velocity_min = 160.0
		p.initial_velocity_max = 320.0
		p.angular_velocity_min = -420.0
		p.angular_velocity_max = 420.0
		p.damping_min = 6.0
		p.damping_max = 18.0
		p.scale_amount_min = 1.7
		p.scale_amount_max = 2.9
		p.split_scale = true
		p.scale_curve_x = _curva_flutter()
		p.scale_curve_y = _curva_flutter_inversa()
		p.hue_variation_min = -0.03
		p.hue_variation_max = 0.03
		p.texture = _textura_confete_generico(cor, 12, 20 if i % 2 == 0 else 26)
		_podio_layer.add_child(p)
		p.emitting = true


func _curva_flutter() -> Curve:
	# Comprime/estica a largura ao longo da vida do confete — simula
	# o papel virando de lado enquanto cai, dando peso e flutuação
	# reais em vez de um sprite plano descendo sem girar.
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.25, 0.25))
	c.add_point(Vector2(0.5, 1.0))
	c.add_point(Vector2(0.75, 0.30))
	c.add_point(Vector2(1.0, 1.0))
	return c


func _curva_flutter_inversa() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.25, 1.0))
	c.add_point(Vector2(0.5, 0.55))
	c.add_point(Vector2(0.75, 1.0))
	c.add_point(Vector2(1.0, 0.60))
	return c



func _emissor_confete_canhao(origem: Vector2, angulo_graus: float, espalhamento: float) -> void:
	var cor: Color = _CORES_CONFETE[randi() % _CORES_CONFETE.size()]
	var p := CPUParticles2D.new()
	p.position = origem
	p.amount = 34
	p.lifetime = 2.6
	p.one_shot = true
	p.explosiveness = 0.92
	p.randomness = 0.5
	p.lifetime_randomness = 0.35
	p.direction = Vector2(cos(deg_to_rad(angulo_graus)), sin(deg_to_rad(angulo_graus)))
	p.spread = espalhamento
	p.gravity = Vector2(0, 340.0)
	p.initial_velocity_min = 340.0
	p.initial_velocity_max = 620.0
	p.angular_velocity_min = -420.0
	p.angular_velocity_max = 420.0
	p.damping_min = 40.0
	p.damping_max = 90.0
	p.scale_amount_min = 1.6
	p.scale_amount_max = 2.8
	p.split_scale = true
	p.scale_curve_x = _curva_flutter()
	p.scale_curve_y = _curva_flutter_inversa()
	p.hue_variation_min = -0.08
	p.hue_variation_max = 0.08
	p.texture = _textura_confete_generico(cor, 12, 20)
	_podio_layer.add_child(p)
	p.emitting = true


func _disparar_confete() -> void:
	if _podio_layer == null:
		return

	var tela := get_viewport_rect().size

	# Chuva contínua vinda de cima (cobre a tela toda) + dois canhões
	# nas quinas inferiores estourando pra cima e pro centro — imita
	# canhão de confete de festa de verdade, em vez de uma chuva única
	# de quadradinhos saindo só do topo-centro.
	_emissor_confete_chuva(tela)
	_emissor_confete_canhao(Vector2(tela.x * 0.06, tela.y * 1.02), -70.0, 34.0)
	_emissor_confete_canhao(Vector2(tela.x * 0.94, tela.y * 1.02), -110.0, 34.0)



func _largura_coluna_resultado() -> float:
	# Usa a largura que caberia em 4 colunas, mesmo quando existem
	# menos jogadores. Assim 1 player fica centralizado sem virar
	# uma coluna gigante ocupando toda a faixa.
	var tela_x: float = get_viewport_rect().size.x
	var faixa_w: float = tela_x * 0.870
	var gap_total: float = 16.0 * 3.0
	return clampf((faixa_w - gap_total) / 4.0, 245.0, 430.0)


func _criar_coluna_resultado(linha: HBoxContainer, idx: int, lugar: int, maior_ponto: int, altura_banda: float) -> Dictionary:
	var cor: Color = CORES_PLAYERS[idx % CORES_PLAYERS.size()]
	var cestas: int = int(_pontos[idx])
	var pontos_normais: int = int(_shootout_base_pontos[idx]) if _partida_teve_shootout else cestas
	var pontos_shootout: int = int(_shootout_pontos_total[idx]) if _partida_teve_shootout else 0
	var participou_shootout: bool = _partida_teve_shootout and _shootout_participantes.has(idx)

	# Se ninguém fez ponto, não cria card minúsculo. Todos os players
	# aparecem com altura segura e idêntica, mantendo o pódio legível.
	var todos_sem_ponto: bool = maior_ponto <= 0
	var ratio: float = 0.62 if todos_sem_ponto else clampf(float(cestas) / float(max(1, maior_ponto)), 0.30, 1.0)
	var diferenca_vencedor: int = max(0, maior_ponto - cestas)

	var largura_coluna: float = _largura_coluna_resultado()
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(largura_coluna, 0.0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 8)
	linha.add_child(col)

	var espaco := Control.new()
	espaco.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(espaco)

	var card := Panel.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.size_flags_vertical = Control.SIZE_SHRINK_END

	# Altura segura: mesmo com 0 ponto o card continua grande o bastante
	# para comportar nome, pontuação e status sem quebrar o modal.
	var altura_card: float = lerpf(altura_banda * 0.48, altura_banda * 0.90, ratio)
	if todos_sem_ponto:
		altura_card = altura_banda * 0.62
	card.custom_minimum_size = Vector2(largura_coluna, altura_card)

	card.add_theme_stylebox_override("panel", _estilo_card_resultado(cor, lugar))
	card.modulate.a = 0.0
	card.scale = Vector2(1.0, 0.08)
	col.add_child(card)

	var dentro := VBoxContainer.new()
	dentro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dentro.offset_left = 12; dentro.offset_right = -12; dentro.offset_top = 12; dentro.offset_bottom = -12
	dentro.alignment = BoxContainer.ALIGNMENT_CENTER
	dentro.add_theme_constant_override("separation", 5)
	card.add_child(dentro)

	var lbl_lugar := Label.new()
	lbl_lugar.text = "%dº" % lugar
	lbl_lugar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_lugar.add_theme_font_size_override("font_size", _fs(0.034 if lugar == 1 else 0.029))
	lbl_lugar.add_theme_color_override("font_color", _cor_medalha(lugar))
	lbl_lugar.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl_lugar.add_theme_constant_override("outline_size", 5)
	_aplicar_fonte(lbl_lugar)
	dentro.add_child(lbl_lugar)

	var lbl_nome := Label.new()
	lbl_nome.text = str(_nomes[idx])
	lbl_nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_nome.add_theme_font_size_override("font_size", _fs(0.019))
	lbl_nome.add_theme_color_override("font_color", Color.WHITE)
	lbl_nome.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl_nome.add_theme_constant_override("outline_size", 4)
	_aplicar_fonte(lbl_nome)
	dentro.add_child(lbl_nome)

	var lbl_cestas := Label.new()
	lbl_cestas.text = "0"
	lbl_cestas.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_cestas.add_theme_font_size_override("font_size", _fs(0.078 if lugar == 1 else 0.062))
	lbl_cestas.add_theme_color_override("font_color", Color.WHITE)
	lbl_cestas.add_theme_color_override("font_outline_color", cor)
	lbl_cestas.add_theme_constant_override("outline_size", 8)
	_aplicar_fonte(lbl_cestas)
	dentro.add_child(lbl_cestas)

	var lbl_txt := Label.new()
	lbl_txt.text = "TOTAL" if _partida_teve_shootout else ("PONTOS" if cestas == 0 else "CESTAS")
	lbl_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_txt.add_theme_font_size_override("font_size", _fs(0.018))
	lbl_txt.add_theme_color_override("font_color", cor)
	lbl_txt.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl_txt.add_theme_constant_override("outline_size", 3)
	_aplicar_fonte(lbl_txt)
	dentro.add_child(lbl_txt)

	var lbl_dif := Label.new()
	if _partida_teve_shootout and participou_shootout:
		lbl_dif.text = "NORMAL %d  •  SHOOTOUT +%d" % [pontos_normais, pontos_shootout]
	elif todos_sem_ponto:
		lbl_dif.text = "SEM PONTOS"
	elif lugar == 1:
		lbl_dif.text = "MELHOR RESULTADO"
	else:
		lbl_dif.text = "-%d DO 1º LUGAR" % diferenca_vencedor
	lbl_dif.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_dif.add_theme_font_size_override("font_size", _fs(0.013 if _partida_teve_shootout and participou_shootout else 0.015))
	lbl_dif.add_theme_color_override("font_color", Color(0.86, 0.90, 1.0))
	lbl_dif.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl_dif.add_theme_constant_override("outline_size", 3)
	_aplicar_fonte(lbl_dif)
	dentro.add_child(lbl_dif)

	var barra_fundo := Panel.new()
	barra_fundo.custom_minimum_size = Vector2(0.0, 18.0)
	barra_fundo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	barra_fundo.clip_contents = true
	barra_fundo.add_theme_stylebox_override("panel", _estilo_barra_resultado(Color(0.10, 0.11, 0.16, 0.90)))
	dentro.add_child(barra_fundo)

	var trilho := Control.new()
	trilho.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trilho.offset_left = 3.0; trilho.offset_top = 3.0; trilho.offset_right = -3.0; trilho.offset_bottom = -3.0
	trilho.clip_contents = true
	trilho.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barra_fundo.add_child(trilho)

	var barra := Panel.new()
	barra.add_theme_stylebox_override("panel", _estilo_preenche_barra(cor))
	barra.anchor_left = 0.0; barra.anchor_top = 0.0; barra.anchor_right = 0.0; barra.anchor_bottom = 1.0
	barra.offset_left = 0.0; barra.offset_top = 0.0; barra.offset_right = 0.0; barra.offset_bottom = 0.0
	barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trilho.add_child(barra)

	return {"card": card, "label_cestas": lbl_cestas, "barra": barra, "ratio": ratio, "cestas": cestas, "cor": cor, "lugar": lugar, "todos_sem_ponto": todos_sem_ponto}



func _estilo_barra_resultado(cor: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = cor
	sb.border_color = Color(1.0, 1.0, 1.0, 0.16)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	sb.shadow_size = 8
	sb.anti_aliasing = true
	return sb



func _estilo_preenche_barra(cor: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(cor.r, cor.g, cor.b, 0.95)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.20)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(cor.r, cor.g, cor.b, 0.65)
	sb.shadow_size = 12
	sb.anti_aliasing = true
	return sb




func _texto_podio_chamada_inicial() -> String:
	return "INSIRA COIN" if modo_credito else "APERTE START"



func _texto_podio_sub_inicial() -> String:
	return "1 COIN = 1 PLAYER" if modo_credito else "1 START = 1 PLAYER"



func _nome_pulso_podio(qtd: int) -> String:
	if modo_credito:
		return "COIN" if qtd == 1 else "COINS"
	return "START" if qtd == 1 else "STARTS"



func _texto_players_podio(qtd: int) -> String:
	return "1 PLAYER" if qtd == 1 else "%d PLAYERS" % qtd



func _registrar_pulso_reinicio_podio() -> void:
	if not _podio_ativo or _podio_reinicio_confirmando:
		return

	var agora_ms: int = Time.get_ticks_msec()
	if agora_ms - _ultimo_pulso_reinicio_podio_ms < debounce_reinicio_podio_ms:
		return
	_ultimo_pulso_reinicio_podio_ms = agora_ms

	# Cancela a volta automática ao menu: agora o pódio está coletando
	# STARTS/COINS para montar a próxima partida.
	_podio_retorno_token += 1

	if not _podio_reinicio_coletando:
		_podio_reinicio_coletando = true
		_podio_reinicio_pulsos = 0
		_podio_reinicio_hard_deadline_ms = agora_ms + int(tempo_maximo_reinicio_podio * 1000.0)

	_podio_reinicio_pulsos = clampi(_podio_reinicio_pulsos + 1, 1, 4)

	if _podio_reinicio_pulsos >= 4:
		_podio_reinicio_deadline_ms = agora_ms + int(atraso_reinicio_apos_max_podio * 1000.0)
	else:
		_podio_reinicio_deadline_ms = min(
			agora_ms + int(tempo_para_confirmar_reinicio_podio * 1000.0),
			_podio_reinicio_hard_deadline_ms
		)

	_atualizar_cta_podio_reinicio()
	_pulsar_podio(lbl_podio_cta_principal)
	_pulsar_podio(lbl_podio_cta_sub)



func _atualizar_cta_podio_reinicio() -> void:
	if lbl_podio_cta_principal == null or lbl_podio_cta_sub == null:
		return

	if not _podio_reinicio_coletando:
		lbl_podio_cta_principal.text = _texto_podio_chamada_inicial()
		lbl_podio_cta_sub.text = _texto_podio_sub_inicial()
		return

	var qtd: int = clampi(_podio_reinicio_pulsos, 1, 4)
	lbl_podio_cta_principal.text = "%d %s" % [qtd, _nome_pulso_podio(qtd)]
	lbl_podio_cta_sub.text = "PRÓXIMA PARTIDA COM " + _texto_players_podio(qtd)

	if lbl_podio_timer != null and not _podio_reinicio_confirmando:
		var restante: float = max(0.0, float(_podio_reinicio_deadline_ms - Time.get_ticks_msec()) / 1000.0)
		lbl_podio_timer.text = "CONFIRMANDO EM %ds" % int(ceil(restante))



func _confirmar_reinicio_podio_com_pulsos() -> void:
	if not _podio_reinicio_coletando or _podio_reinicio_confirmando:
		return

	_podio_reinicio_confirmando = true
	var qtd: int = clampi(_podio_reinicio_pulsos, 1, 4)
	var nome_pulso: String = _nome_pulso_podio(qtd)

	if lbl_podio_cta_principal != null:
		lbl_podio_cta_principal.text = "%d %s CONFIRMADO" % [qtd, nome_pulso]
	if lbl_podio_cta_sub != null:
		lbl_podio_cta_sub.text = "INICIANDO " + _texto_players_podio(qtd)
	if lbl_podio_timer != null:
		lbl_podio_timer.text = "PREPARANDO PRÓXIMA PARTIDA..."

	await get_tree().create_timer(0.45).timeout
	_reiniciar_partida_do_podio(qtd)



func _pulsar_podio(no: Control) -> void:
	if no == null:
		return
	no.pivot_offset = no.size * 0.5
	var t := create_tween()
	t.tween_property(no, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(no, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)



func _contagem_retorno_opening_podio(token: int) -> void:
	var segundos: int = segundos_retorno_opening_podio
	while segundos >= 0:
		if token != _podio_retorno_token or not _podio_ativo:
			return
		if lbl_podio_timer != null:
			lbl_podio_timer.text = "Volta ao menu em %ds" % segundos
		await get_tree().create_timer(1.0).timeout
		segundos -= 1
	if token != _podio_retorno_token or not _podio_ativo:
		return
	_voltar_abertura()



func _reiniciar_partida_do_podio(qtd_nova: int = -1) -> void:
	_podio_retorno_token += 1
	_podio_ativo = false
	_podio_reinicio_coletando = false
	_podio_reinicio_confirmando = false
	_podio_reinicio_pulsos = 0
	_podio_reinicio_deadline_ms = 0
	_podio_reinicio_hard_deadline_ms = 0
	if qtd_nova > 0:
		num_jogadores = clampi(qtd_nova, 1, 4)
		get_tree().set_meta("num_jogadores", num_jogadores)
	if _podio_layer != null:
		_podio_layer.queue_free()
		_podio_layer = null
	if som_good_player != null and som_good_player.playing:
		som_good_player.stop()
	lbl_podio_timer = null
	lbl_podio_cta_principal = null
	lbl_podio_cta_sub = null
	_podio_linha_dif = null
	_podio_cards_ref.clear()
	_resetar_estado_shootout_total()
	_pontos = [0, 0, 0, 0]
	_turnos_finalizados = [false, false, false, false]
	_jogador_atual = 0
	_tempo_restante = 0.0
	_rodando = false
	_modal_turno_ativo = false
	_modal_turno_pronto = false
	for n in [card_jogando, col_players]:
		if n != null:
			n.visible = true
			n.modulate = Color(1, 1, 1, 1)
	if musica_fundo != null:
		musica_fundo.volume_db = volume_musica_db
		if musica_fundo.stream != null and not musica_fundo.playing:
			musica_fundo.play()
	_atualizar_visao_turno()
	_atualizar_tempo_label()
	await get_tree().create_timer(0.25).timeout
	_mostrar_modal_turno(true)



func _animar_coluna_resultado(info: Dictionary, atraso: float = 0.0) -> void:
	var card: Panel = info.get("card", null)
	var lbl_cestas: Label = info.get("label_cestas", null)
	var barra: Control = info.get("barra", null)
	var ratio: float = float(info.get("ratio", 0.0))
	var cestas: int = int(info.get("cestas", 0))
	var lugar: int = int(info.get("lugar", 0))
	if card == null:
		return
	card.pivot_offset = Vector2(card.size.x * 0.5, card.size.y)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.24).set_delay(atraso)
	tw.tween_property(card, "scale", Vector2.ONE, 0.38).set_delay(atraso).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if barra != null:
		var destino := clampf(ratio, 0.0, 1.0)
		barra.anchor_right = 0.0
		tw.tween_property(barra, "anchor_right", destino, 0.55).set_delay(atraso + 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if lbl_cestas != null:
		lbl_cestas.text = "0"
		tw.tween_method(Callable(self, "_atualizar_numero_resultado").bind(lbl_cestas), 0.0, float(cestas), 0.62).set_delay(atraso + 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	if lugar == 1 and card != null:
		var brilho := create_tween()
		brilho.tween_property(card, "scale", Vector2(1.04, 1.04), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		brilho.tween_property(card, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.04).timeout



func _atualizar_numero_resultado(valor: float, lbl: Label) -> void:
	if lbl == null:
		return
	lbl.text = str(int(round(valor)))



func _estilo_painel_resultado() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.012, 0.02, 0.04, 0.90)
	sb.border_color = Color(COR_AZUL.r, COR_AZUL.g, COR_AZUL.b, 0.78)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(40)
	sb.set_content_margin_all(22)
	sb.shadow_color = Color(COR_AZUL.r, COR_AZUL.g, COR_AZUL.b, 0.38)
	sb.shadow_size = 48
	return sb



func _estilo_card_resultado(cor: Color, lugar: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if lugar == 1:
		sb.bg_color = Color(0.10, 0.085, 0.02, 0.92)
		sb.border_color = Color(1.0, 0.84, 0.18, 1.0)
		sb.shadow_color = Color(1.0, 0.78, 0.16, 0.78)
		sb.shadow_size = 46
	else:
		sb.bg_color = Color(cor.r * 0.10, cor.g * 0.10, cor.b * 0.10, 0.82)
		sb.border_color = Color(cor.r, cor.g, cor.b, 0.78)
		sb.shadow_color = Color(cor.r, cor.g, cor.b, 0.34)
		sb.shadow_size = 26
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(30)
	sb.corner_detail = 24
	sb.set_content_margin_all(12)
	sb.anti_aliasing = true
	return sb



func _altura_card_player() -> float:
	var tela_y: float = get_viewport_rect().size.y

	match num_jogadores:
		1:
			return clampf(tela_y * 0.112, 88.0, 130.0)
		2:
			return clampf(tela_y * 0.106, 82.0, 122.0)
		3:
			return clampf(tela_y * 0.100, 76.0, 110.0)
		_:
			return clampf(tela_y * 0.094, 70.0, 100.0)



func _largura_min_card_player_rodape() -> float:
	var tela_x: float = get_viewport_rect().size.x

	match num_jogadores:
		1:
			return clampf(tela_x * 0.26, 220.0, 320.0)
		2:
			return clampf(tela_x * 0.22, 180.0, 270.0)
		3:
			return clampf(tela_x * 0.18, 145.0, 220.0)
		_:
			return clampf(tela_x * 0.155, 118.0, 182.0)



func _fonte_nome_card_player_rodape() -> int:
	match num_jogadores:
		1:
			return _fs(0.021)
		2:
			return _fs(0.019)
		3:
			return _fs(0.0175)
		_:
			return _fs(0.016)



func _fonte_pontos_card_player_rodape() -> int:
	match num_jogadores:
		1:
			return _fs(0.035)
		2:
			return _fs(0.032)
		3:
			return _fs(0.029)
		_:
			return _fs(0.027)



func _enviar_led_basket(cmd: String) -> void:
	if not usar_leds_arduino:
		return

	var f := FileAccess.open(caminho_fila_leds_basket, FileAccess.WRITE)
	if f == null:
		push_warning("Basket LEDs: não consegui escrever comando " + cmd)
		return

	# O número no final garante que HIT/BOOST repetido seja sempre um comando novo.
	var linha := "%s:%d" % [cmd, Time.get_ticks_msec()]
	f.store_line(linha)
	f.close()

	print("LED CMD -> ", linha)



func _iniciar_ponte_leds_play() -> void:
	if not usar_ponte_leds_no_play:
		return

	if not usar_leds_arduino:
		return

	if OS.get_name() != "Windows":
		return

	if _led_bridge_pid > 0:
		return

	var cmd_abs := ProjectSettings.globalize_path(caminho_fila_leds_basket)

	# Limpa comando antigo para não mandar coisa velha.
	if FileAccess.file_exists(caminho_fila_leds_basket):
		DirAccess.remove_absolute(cmd_abs)

	var f := FileAccess.open(_led_bridge_ps, FileAccess.WRITE)
	if f:
		f.store_string(_PS_BRIDGE_BASKET)
		f.close()

	var ps_abs := ProjectSettings.globalize_path(_led_bridge_ps)

	var args := [
		"-ExecutionPolicy", "Bypass",
		"-NoProfile",
		"-WindowStyle", "Hidden",
		"-File", ps_abs,
		"-Porta", porta_leds,
		"-Baud", str(baud_leds),
		"-Arquivo", cmd_abs
	]

	_led_bridge_pid = OS.create_process("powershell.exe", args)

	# Tempo maior para garantir que a COM5 abriu.
	OS.delay_msec(350)



func _fechar_ponte_leds_play(apagar: bool = true) -> void:
	if apagar:
		_enviar_led_basket("OFF")
		OS.delay_msec(120)

	if _led_bridge_pid > 0:
		OS.kill(_led_bridge_pid)
		_led_bridge_pid = -1



func _exit_tree() -> void:
	_fechar_ponte_leds_play(true)



func _record_origem_fx() -> Vector2:
	var tela := get_viewport_rect().size
	# ORIGEM PADRÃO de TODOS os efeitos de cesta (combo normal, recorde
	# e contagem regressiva). Antes cada efeito tinha seu próprio ponto
	# (0.365 no combo normal, 0.5 na contagem, 0.505 no recorde) e o
	# efeito "pulava" de lugar dependendo do que acontecia. Agora tudo
	# nasce exatamente daqui — o centro visual da tabela/cesta na arte.
	# Suba/desça aqui se a arte back_basquet mudar novamente.
	return Vector2(tela.x * 0.5, tela.y * 0.505)



func _atualizar_scores_players_hud() -> void:
	if box_players_score == null:
		return

	for c in box_players_score.get_children():
		c.queue_free()

	# Lista fixa de jogadores, sem ranking dinâmico.
	# Assim cada player ocupa sempre a mesma posição:
	# J1, J2, J3, J4. O destaque troca, o card não muda de lugar.
	for i in range(num_jogadores):
		var linha := _criar_linha_score_player(i, i + 1)
		box_players_score.add_child(linha)



func _cor_rank_score(lugar: int) -> Color:
	match lugar:
		1: return Color(1.0, 0.84, 0.20)   # ouro — líder
		2: return Color(0.80, 0.82, 0.86)  # prata
		3: return Color(0.80, 0.52, 0.28)  # bronze
		_: return Color(0.55, 0.60, 0.68)  # neutro



func _criar_linha_score_player(i: int, lugar: int) -> Panel:
	var cor: Color = CORES_PLAYERS[i % CORES_PLAYERS.size()]
	var eh_atual: bool = i == _jogador_atual
	var fin: bool = bool(_turnos_finalizados[i])
	var altura: float = _altura_linha_score_players()

	var wrap := Panel.new()
	wrap.name = "CardPlayerFixo%d" % i
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	wrap.custom_minimum_size = Vector2(0, altura)
	wrap.clip_contents = false

	var sb := StyleBoxFlat.new()

	if eh_atual:
		# Mesmo LED laranja dos PONTOS, aplicado ao player da vez.
		sb.bg_color = Color(0.018, 0.030, 0.060, 0.92)
		sb.border_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 1.0)
		sb.shadow_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.66)
		sb.shadow_size = 30
		sb.set_border_width_all(3)
	elif fin:
		sb.bg_color = Color(0.018, 0.030, 0.060, 0.18)
		sb.border_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.12)
		sb.shadow_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.03)
		sb.shadow_size = 2
		sb.set_border_width_all(2)
	else:
		sb.bg_color = Color(0.018, 0.030, 0.060, 0.32)
		sb.border_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.28)
		sb.shadow_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.12)
		sb.shadow_size = 8
		sb.set_border_width_all(2)

	sb.set_corner_radius_all(999)
	sb.corner_detail = 32
	sb.set_content_margin_all(10)
	sb.anti_aliasing = true
	wrap.add_theme_stylebox_override("panel", sb)

	wrap.modulate.a = 1.0 if eh_atual else (0.42 if not fin else 0.22)

	var linha := HBoxContainer.new()
	linha.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	linha.offset_left = 12
	linha.offset_right = -12
	linha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	linha.alignment = BoxContainer.ALIGNMENT_CENTER
	linha.add_theme_constant_override("separation", 8)
	wrap.add_child(linha)

	var dot_size: float = clampf(altura * 0.42, 10.0, 20.0)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(dot_size, dot_size)
	dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb_dot := StyleBoxFlat.new()
	sb_dot.bg_color = cor
	sb_dot.set_corner_radius_all(int(dot_size * 0.5))
	sb_dot.shadow_color = Color(cor.r, cor.g, cor.b, 0.78 if eh_atual else 0.16)
	sb_dot.shadow_size = 8 if eh_atual else 2
	sb_dot.anti_aliasing = true
	dot.add_theme_stylebox_override("panel", sb_dot)
	linha.add_child(dot)

	var nome := Label.new()
	nome.text = "JOGADOR %d" % (i + 1)
	nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nome.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nome.clip_text = true
	nome.add_theme_font_size_override("font_size", _fonte_score_players_nome())
	nome.add_theme_color_override("font_color", Color.WHITE if eh_atual else Color(0.82, 0.82, 0.82, 0.86))
	nome.add_theme_color_override("font_outline_color", Color.BLACK)
	nome.add_theme_constant_override("outline_size", 3)
	_aplicar_fonte(nome)
	linha.add_child(nome)

	var pts := Label.new()
	pts.text = "%02d" % int(_pontos[i])
	pts.custom_minimum_size = Vector2(max(34.0, altura * 1.10), 0)
	pts.size_flags_horizontal = Control.SIZE_SHRINK_END
	pts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pts.add_theme_font_size_override("font_size", _fonte_score_players_pontos())
	pts.add_theme_color_override("font_color", COR_RECORDE_CLARO if eh_atual else Color(0.82, 0.82, 0.82, 0.84))
	pts.add_theme_color_override("font_outline_color", Color.BLACK)
	pts.add_theme_constant_override("outline_size", 4)
	_aplicar_fonte(pts)
	linha.add_child(pts)

	return wrap



func _nome_curto_score(i: int) -> String:
	# Para 3 e 4 players, usa nome curto para não estourar o painel.
	if num_jogadores >= 3:
		return "P%d" % (i + 1)

	return str(_nomes[i])



func _altura_linha_score_players() -> float:
	var area_lista: float = get_viewport_rect().size.y * 0.685

	if box_players_score != null and box_players_score.size.y > 1.0:
		area_lista = box_players_score.size.y

	var separacao: float = clampf(get_viewport_rect().size.y * 0.009, 6.0, 9.0)
	var separacao_total: float = separacao * float(max(0, num_jogadores - 1))
	var altura: float = (area_lista - separacao_total) / float(max(1, num_jogadores))

	# Altura menor e firme para os 4 cards ficarem sempre dentro da tela.
	return clampf(altura, 48.0, 74.0)



func _fonte_score_players_nome() -> int:
	return max(15, int(_altura_linha_score_players() * 0.46))



func _fonte_score_players_pontos() -> int:
	return max(17, int(_altura_linha_score_players() * 0.60))


func _trocar_cena(caminho: String) -> void:
	if caminho == "":
		return
	var tela_node := get_node_or_null("/root/Tela")
	if tela_node != null and tela_node.has_method("trocar"):
		tela_node.trocar(caminho)
	else:
		# Sem o autoload Tela: comportamento antigo.
		if ResourceLoader.exists(caminho):
			get_tree().change_scene_to_file(caminho)



func _disparar_onda_card_pontos() -> void:
	_ondas_pontos_card.append({
		"t": 0.0,
		"dur": 0.72
	})

	if _ondas_pontos_card.size() > 6:
		_ondas_pontos_card.pop_front()

	if fx_fogo_pontos_atuais != null:
		fx_fogo_pontos_atuais.queue_redraw()


func _atualizar_ondas_card_pontos(delta: float) -> void:
	if _ondas_pontos_card.is_empty():
		return

	var vivas: Array = []
	for o in _ondas_pontos_card:
		o["t"] = float(o.get("t", 0.0)) + delta
		if float(o["t"]) < float(o.get("dur", 0.72)):
			vivas.append(o)

	_ondas_pontos_card = vivas

	if fx_fogo_pontos_atuais != null:
		fx_fogo_pontos_atuais.queue_redraw()


func _desenhar_capsula_outline_pontos(host: Control, margem: float, cor: Color, largura: float) -> void:
	var s: Vector2 = host.size
	if s.x <= 4.0 or s.y <= 4.0:
		return

	var rect := Rect2(Vector2(margem, margem), s - Vector2(margem * 2.0, margem * 2.0))
	if rect.size.x <= 4.0 or rect.size.y <= 4.0:
		return

	var raio: float = min(rect.size.y * 0.5, rect.size.x * 0.5)
	var y_top: float = rect.position.y
	var y_bot: float = rect.position.y + rect.size.y
	var x_left: float = rect.position.x + raio
	var x_right: float = rect.position.x + rect.size.x - raio
	var y_mid: float = rect.position.y + rect.size.y * 0.5

	host.draw_line(Vector2(x_left, y_top), Vector2(x_right, y_top), cor, largura, true)
	host.draw_line(Vector2(x_left, y_bot), Vector2(x_right, y_bot), cor, largura, true)
	host.draw_arc(Vector2(x_left, y_mid), raio, PI * 0.5, PI * 1.5, 36, cor, largura, true)
	host.draw_arc(Vector2(x_right, y_mid), raio, -PI * 0.5, PI * 0.5, 36, cor, largura, true)


func _desenhar_ondas_card_pontos(host: Control) -> void:
	if host == null or not is_instance_valid(host):
		return

	var s: Vector2 = host.size
	if s.x <= 4.0 or s.y <= 4.0:
		return

	for o in _ondas_pontos_card:
		var dur: float = float(o.get("dur", 0.72))
		var p: float = clampf(float(o.get("t", 0.0)) / max(0.01, dur), 0.0, 1.0)
		var envelope: float = sin(p * PI)
		var alpha: float = 0.62 * envelope
		var margem: float = lerpf(s.y * 0.060, -s.y * 0.185, p)
		var largura: float = max(2.0, s.y * lerpf(0.020, 0.006, p))

		_desenhar_capsula_outline_pontos(
			host,
			margem,
			Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, alpha),
			largura
		)

		_desenhar_capsula_outline_pontos(
			host,
			margem - s.y * 0.030,
			Color(1.0, 0.92, 0.58, alpha * 0.40),
			max(1.0, largura * 0.45)
		)


func _nodes_hud_jogo() -> Array:
	var nodes: Array = [
		painel_record,
		lbl_high_titulo,
		lbl_high_valor,
		painel_players_score,
		lbl_players_titulo,
		box_players_score,
		lbl_tempo_titulo,
		crono_ring,
		lbl_crono,
		painel_score_pass,
		lbl_meta_titulo,
		lbl_meta_valor,
		painel_current_score,
		fx_fogo_pontos_atuais,
		lbl_atual_titulo,
		lbl_atual_pontos,
		card_jogando,
		col_players,
		logo_canto_fx,
		logo_canto_img
	]

	var filtrados: Array = []
	for n in nodes:
		if n != null:
			filtrados.append(n)

	return filtrados

func _animar_entrada_hud_node(n: CanvasItem, atraso: float) -> void:
	if n == null:
		return

	if (n == logo_canto_img or n == logo_canto_fx) and (logo_canto_img == null or logo_canto_img.texture == null):
		n.visible = false
		return

	n.visible = true
	n.modulate.a = 0.0

	if n is Control:
		var c := n as Control
		var pos_original: Vector2 = c.position
		var escala_original: Vector2 = c.scale

		var deslocamento := Vector2.ZERO
		var dur_pos: float = 0.34
		var dur_alpha: float = 0.22
		var escala_inicio: Vector2 = escala_original * Vector2(0.96, 0.96)
		var trans_tipo = Tween.TRANS_CUBIC
		var ease_tipo = Tween.EASE_OUT

		if n == col_players:
			deslocamento = Vector2(0, 34)
		elif n == painel_record or n == lbl_high_titulo or n == lbl_high_valor:
			deslocamento = Vector2(-28, 0)
		elif n == painel_current_score or n == lbl_atual_titulo or n == lbl_atual_pontos or n == fx_fogo_pontos_atuais:
			deslocamento = Vector2(28, 0)
		elif n == painel_players_score or n == lbl_players_titulo or n == box_players_score:
			deslocamento = Vector2(26, 0)
		elif n == logo_canto_img or n == logo_canto_fx:
			# Entrada especial da marca: vem de baixo/esquerda com pop suave,
			# aparecendo só depois da contagem para não poluir a tela.
			deslocamento = Vector2(-44, 26)
			escala_inicio = escala_original * Vector2(0.86, 0.86)
			dur_pos = 0.56
			dur_alpha = 0.42
			trans_tipo = Tween.TRANS_QUINT
			ease_tipo = Tween.EASE_OUT
		elif n == lbl_tempo_titulo or n == crono_ring or n == lbl_crono:
			deslocamento = Vector2(0, -22)
		else:
			deslocamento = Vector2(0, -14)

		c.position = pos_original + deslocamento
		c.scale = escala_inicio

		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(c, "position", pos_original, dur_pos)\
			.set_delay(atraso)\
			.set_trans(trans_tipo)\
			.set_ease(ease_tipo)

		t.tween_property(c, "scale", escala_original, dur_pos)\
			.set_delay(atraso)\
			.set_trans(Tween.TRANS_BACK)\
			.set_ease(Tween.EASE_OUT)

		t.tween_property(c, "modulate:a", 1.0, dur_alpha)\
			.set_delay(atraso)
	else:
		var t_simple := create_tween()
		t_simple.tween_property(n, "modulate:a", 1.0, 0.22).set_delay(atraso)



func _estilo_cta_podio() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.020, 0.035, 0.075, 0.95)
	sb.border_color = COR_VERDE_DISPLAY
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(999)
	sb.corner_detail = 32
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(COR_VERDE_DISPLAY.r, COR_VERDE_DISPLAY.g, COR_VERDE_DISPLAY.b, 0.70)
	sb.shadow_size = 38
	sb.anti_aliasing = true
	return sb



# ---------- VARIEDADE DE PADRÕES DE ONDA ----------
# Antes, TODA onda (grade de tiles + luz) usava a mesma métrica de
# distância — distância euclidiana até a origem — e por isso SEMPRE
# formava um círculo se expandindo, não importa a cor. Agora cada
# cesta sorteia uma FORMA diferente (nunca repete a anterior): faixa
# de uma fileira só, diagonal, quadrado, losango, cruz, etc. Todas
# SEMPRE nascem do mesmo ponto central (_record_origem_fx) — só a
# geometria de como se espalham a partir dali é que varia.
enum TipoOnda { RADIAL, FAIXA_H, FAIXA_V, DIAGONAL_A, DIAGONAL_B, XIS, QUADRADO, LOSANGO, CRUZ }

var _ultimo_tipo_onda: int = -1
var _saco_tipos_onda: Array = []   # "bag" de padrões — consumido sem repetir até esvaziar
var _ciclo_cor_onda: int = 0       # incrementa a cada saco novo — usado pra variar o tom de cor


func _sortear_tipo_onda() -> int:
	# SISTEMA DE SACO (igual ao das peças do Tetris moderno): em vez de
	# só evitar repetir o ÚLTIMO tipo, garantimos que TODOS os 9
	# padrões apareçam exatamente uma vez antes de qualquer um se
	# repetir. Isso elimina a sensação de "sempre os mesmos 2-3
	# aparecendo" que a versão anterior (shuffle solto) permitia.
	if _saco_tipos_onda.is_empty():
		var novo_saco: Array = [
			TipoOnda.RADIAL, TipoOnda.FAIXA_H, TipoOnda.FAIXA_V,
			TipoOnda.DIAGONAL_A, TipoOnda.DIAGONAL_B, TipoOnda.XIS,
			TipoOnda.QUADRADO, TipoOnda.LOSANGO, TipoOnda.CRUZ
		]
		novo_saco.shuffle()

		# Evita que o ÚLTIMO tipo do saco anterior caia bem no PRIMEIRO
		# do saco novo (senão dá a impressão de repetição na costura
		# entre um ciclo e outro, mesmo o saco em si estando correto).
		if novo_saco.size() > 1 and novo_saco[0] == _ultimo_tipo_onda:
			var tmp = novo_saco[0]
			novo_saco[0] = novo_saco[1]
			novo_saco[1] = tmp

		_saco_tipos_onda = novo_saco
		_ciclo_cor_onda += 1

	var tipo: int = _saco_tipos_onda.pop_front()
	_ultimo_tipo_onda = tipo
	return tipo


func _cor_base_ciclica_para(ciclo: int) -> Color:
	# Cor "comum" (combo 1-5, fora do recorde) nasce BRANCA de verdade —
	# antes usava laranja (1.0, 0.48, 0.06) que, somado ao glow branco
	# por cima, resultava numa mistura amarelada. Amarelo/dourado agora
	# é EXCLUSIVO do recorde, então aqui ficamos sempre no branco, com
	# variação bem sutil e FRIA (leve azul, nunca amarelo/laranja) a
	# cada ciclo do saco de padrões.
	if ciclo <= 0:
		return Color(1.0, 1.0, 1.0)
	var fase: float = fmod(float(ciclo) * 0.14, 1.0)
	var sat: float = clampf(0.10 + 0.08 * sin(fase * TAU), 0.0, 0.22)
	var matiz: float = 0.56 + 0.05 * sin(fase * TAU * 0.5)  # faixa azul-ciano — nunca ~0.15 (amarelo) nem ~0.08 (laranja)
	return Color.from_hsv(matiz, sat, 1.0, 1.0)


func _cor_base_ciclica() -> Color:
	return _cor_base_ciclica_para(_ciclo_cor_onda)


func _distancia_padrao_grade(p: Vector2, origem: Vector2, tipo: int) -> float:
	# Isto é o coração da variedade: em vez de sempre medir "quão longe
	# em círculo", cada tipo mede a distância de um jeito diferente.
	# Uma onda de tiles acende quando essa distância bate com o raio
	# que está se expandindo — então a MESMA lógica de expansão que já
	# existia (raio crescendo, largura da faixa, ida-e-volta) passa a
	# desenhar formas diferentes automaticamente, sem duplicar código.
	var dx: float = p.x - origem.x
	var dy: float = p.y - origem.y
	var slab: float = _grade_passo * 0.62  # meia-espessura ≈ 1 fileira de tiles

	match tipo:
		TipoOnda.FAIXA_H:
			# Uma única fileira horizontal — a "onda deitada" que você pediu.
			if abs(dy) > slab:
				return 999999.0
			return abs(dx)

		TipoOnda.FAIXA_V:
			if abs(dx) > slab:
				return 999999.0
			return abs(dy)

		TipoOnda.DIAGONAL_A:
			var rot := Vector2(dx * 0.7071 - dy * 0.7071, dx * 0.7071 + dy * 0.7071)
			if abs(rot.y) > slab:
				return 999999.0
			return abs(rot.x)

		TipoOnda.DIAGONAL_B:
			var rot := Vector2(dx * 0.7071 + dy * 0.7071, -dx * 0.7071 + dy * 0.7071)
			if abs(rot.y) > slab:
				return 999999.0
			return abs(rot.x)

		TipoOnda.QUADRADO:
			return max(abs(dx), abs(dy))

		TipoOnda.LOSANGO:
			return abs(dx) + abs(dy)
			
		
		TipoOnda.XIS:
			var rot_a := Vector2(dx * 0.7071 - dy * 0.7071, dx * 0.7071 + dy * 0.7071)
			var rot_b := Vector2(dx * 0.7071 + dy * 0.7071, -dx * 0.7071 + dy * 0.7071)
			var d_a: float = abs(rot_a.x) if abs(rot_a.y) <= slab else 999999.0
			var d_b: float = abs(rot_b.x) if abs(rot_b.y) <= slab else 999999.0
			return min(d_a, d_b)


		TipoOnda.CRUZ:
			var d_h: float = abs(dx) if abs(dy) <= slab else 999999.0
			var d_v: float = abs(dy) if abs(dx) <= slab else 999999.0
			return min(d_h, d_v)

		_:
			return p.distance_to(origem)


func _ruido01(x: float) -> float:
	# Pseudo-aleatório ESTÁVEL (mesma entrada = mesma saída sempre).
	# Essencial pra "poeira" de quadrados não tremer entre frames —
	# nada de randi()/randf() aqui, senão cada redraw reembaralha tudo.
	var v: float = sin(x * 12.9898) * 43758.5453
	return v - floor(v)
