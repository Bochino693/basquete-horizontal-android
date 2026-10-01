extends Control

## Relógio circular: anel neon que esvazia com o tempo, muda de cor
## (verde -> amarelo -> vermelho) e pulsa nos segundos finais. Os segundos
## ficam no meio em LED.

var total := 40.0
var restante := 40.0
var alerta := 10.0
var _t := 0.0
var _led: Control
var _lote = preload("res://scripts/traco_suave.gd").new()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_led = preload("res://scripts/placar_led.gd").new()
	_led.digitos = 2
	_led.espaco_grupo = false
	_led.contar = false
	_led.cor = Jogo.VERDE
	add_child(_led)
	_halo = Control.new()
	_halo.mouse_filter = MOUSE_FILTER_IGNORE
	_halo.show_behind_parent = true
	_halo.anchor_right = 1
	_halo.anchor_bottom = 1
	add_child(_halo)
	move_child(_halo, 0)
	_halo.connect("draw", self, "_desenhar_halo")
	connect("resized", self, "_ajustar")
	_ajustar()


func _ajustar() -> void:
	var r := min(rect_size.x, rect_size.y) * 0.5
	var w := r * 0.95
	var h := r * 0.70
	_led.rect_position = rect_size / 2 - Vector2(w, h) / 2
	_led.rect_size = Vector2(w, h)


func _cor() -> Color:
	var k := restante / max(total, 0.001)
	if restante <= alerta:
		return Jogo.VERMELHO
	if k < 0.5:
		return Jogo.AMARELO
	return Jogo.VERDE


func _process(delta: float) -> void:
	_t += delta
	var seg := int(ceil(max(restante, 0.0)))
	if _led.valor != seg:
		_led.valor = seg
	_led.cor = _cor()
	_led.piscar(restante <= 5.0 and restante > 0.0)
	# Só redesenha quando o arco anda um "passo" visível (240 por volta) ou
	# muda de cor; o pulso dos segundos finais é o brilho do nó do halo.
	var k := clamp(restante / max(total, 0.001), 0.0, 1.0)
	var passo := int(ceil(k * PASSOS))
	var cor := _cor()
	if passo != _passo_desenhado or cor != _cor_desenhada:
		_passo_desenhado = passo
		_cor_desenhada = cor
		update()
		_halo.update()
	var pulso := 1.0
	if restante <= alerta and restante > 0:
		pulso = 1.0 + abs(sin(_t * 6.0)) * 0.6
	_halo.self_modulate = Color(pulso, pulso, pulso, 1.0)


const PASSOS := 240
var _passo_desenhado := -1
var _cor_desenhada := Color(0, 0, 0, 0)
var _halo: Control
var _lote_fundo = preload("res://scripts/traco_suave.gd").new()
var _lote_halo = preload("res://scripts/traco_suave.gd").new()
var _tamanho_fundo := Vector2.ZERO


func _geometria() -> Array:
	var c := rect_size / 2
	var r := min(rect_size.x, rect_size.y) * 0.5 - 12
	var k := float(_passo_desenhado) / PASSOS
	var a0 := -PI / 2
	var a1 := a0 + TAU * k
	return [c, r, k, a0, a1]


func _draw() -> void:
	var g := _geometria()
	var c: Vector2 = g[0]
	var r: float = g[1]
	var k: float = g[2]
	var a1: float = g[4]
	# anel de fundo: montado uma vez (só de novo se o tamanho mudar)
	if _tamanho_fundo != rect_size:
		_tamanho_fundo = rect_size
		_lote_fundo.preparar(self)
		_lote_fundo.linha(_lote_fundo.arco(c, r, 0, TAU, 72, false), Color(1, 1, 1, 0.08), 12.0, true)
	_lote_fundo.desenhar(self)
	if k > 0.0:
		var cor := _cor_desenhada
		_lote.preparar(self)
		_lote.linha(_lote.arco(c, r, g[3], a1, int(max(4, 72 * k))), cor, 10.0)
		_lote.circulo(c + Vector2(cos(a1), sin(a1)) * r, 8.0, Color(1, 1, 1, 0.92))
		_lote.desenhar(self)


## Halo do arco (fica atrás do anel e pulsa pelo brilho do nó).
func _desenhar_halo() -> void:
	var g := _geometria()
	var k: float = g[2]
	if k <= 0.0:
		return
	var c: Vector2 = g[0]
	var r: float = g[1]
	var a1: float = g[4]
	var cor := _cor_desenhada
	_lote_halo.preparar(_halo)
	_lote_halo.linha_brilho(_lote_halo.arco(c, r, g[3], a1, int(max(4, 72 * k))), Color(cor.r, cor.g, cor.b, 0.35), 26.0)
	_lote_halo.brilho_redondo(c + Vector2(cos(a1), sin(a1)) * r, 18.0, Color(cor.r, cor.g, cor.b, 0.5))
	_lote_halo.desenhar(_halo)
