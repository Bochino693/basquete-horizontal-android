extends Control

## Anel que enche enquanto o botão é segurado (ex.: SELECT para abrir a
## configuração).

var progresso := 0.0
var texto := "CONFIGURAÇÃO"
var _fonte: Font


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_fonte = Jogo.fonte("bungee", 20, 2)


func _process(_delta: float) -> void:
	update()


func _draw() -> void:
	var c := rect_size / 2
	var r := min(rect_size.x, rect_size.y) * 0.4
	draw_circle(c, r + 18, Color(0.03, 0.01, 0.08, 0.8))
	draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.12), 12.0, true)
	var k := clamp(progresso, 0.0, 1.0)
	if k > 0.0:
		draw_arc(c, r, -PI / 2, -PI / 2 + TAU * k, 64, Jogo.CIANO, 12.0, true)
	var tam := _fonte.get_string_size(texto)
	draw_string(_fonte, Vector2(c.x - tam.x / 2, c.y + 7), texto, Color(1, 1, 1))
