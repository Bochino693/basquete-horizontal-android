extends Control

## Anel que enche enquanto o botão é segurado (ex.: SELECT para abrir a
## configuração).

var progresso := 0.0
var texto := "CONFIGURAÇÃO"
var _fonte: Font
var _lote = preload("res://scripts/traco_suave.gd").new()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_fonte = Jogo.fonte("bungee", 20, 2)


func _process(_delta: float) -> void:
	update()


func _draw() -> void:
	var c := rect_size / 2
	var r := min(rect_size.x, rect_size.y) * 0.4
	_lote.preparar(self)
	_lote.circulo(c, r + 18, Color(0.03, 0.01, 0.08, 0.8), 64)
	_lote.linha(_lote.arco(c, r, 0, TAU, 72, false), Color(1, 1, 1, 0.12), 12.0, true)
	var k := clamp(progresso, 0.0, 1.0)
	if k > 0.0:
		_lote.linha(_lote.arco(c, r, -PI / 2, -PI / 2 + TAU * k, int(max(4, 72 * k))), Jogo.CIANO, 12.0)
	_lote.desenhar(self)
	var tam := _fonte.get_string_size(texto)
	draw_string(_fonte, Vector2(c.x - tam.x / 2, c.y + 7), texto, Color(1, 1, 1))
