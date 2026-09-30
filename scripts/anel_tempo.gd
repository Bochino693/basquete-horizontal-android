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
	update()


func _draw() -> void:
	var c := rect_size / 2
	var r := min(rect_size.x, rect_size.y) * 0.5 - 12
	var cor := _cor()
	var k := clamp(restante / max(total, 0.001), 0.0, 1.0)
	var pulso := 1.0
	if restante <= alerta and restante > 0:
		pulso = 1.0 + abs(sin(_t * 6.0)) * 0.6
	# Bordas lisas feitas à mão (o "antialiased" do draw_arc não vale no GLES2).
	_lote.preparar(self)
	_lote.linha(_lote.arco(c, r, 0, TAU, 72, false), Color(1, 1, 1, 0.08), 12.0, true)
	if k > 0.0:
		var a0 := -PI / 2
		var a1 := a0 + TAU * k
		var lados := int(max(4, 72 * k))
		var arco: PoolVector2Array = _lote.arco(c, r, a0, a1, lados)
		_lote.linha_brilho(arco, Color(cor.r, cor.g, cor.b, 0.35 * pulso), 26.0)
		_lote.linha(arco, cor, 10.0)
		# pontinha brilhante do anel
		var ponta := c + Vector2(cos(a1), sin(a1)) * r
		_lote.brilho_redondo(ponta, 18.0, Color(cor.r, cor.g, cor.b, 0.5))
		_lote.circulo(ponta, 8.0, Color(1, 1, 1, 0.92))
	_lote.desenhar(self)
