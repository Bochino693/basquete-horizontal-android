extends Control

## Barra de progresso da META da fase: enche animada, tem um brilho que
## corre por dentro e pulsa verde quando a meta é batida. Na final (meta 0)
## fica cheia, trocando de cor.

var meta := 30
var valor := 0
var _exibido := 0.0
var _t := 0.0
var _fonte: Font


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_fonte = Jogo.fonte("bungee", 18, 2)


func _process(delta: float) -> void:
	_t += delta
	var alvo := 1.0 if meta <= 0 else clamp(float(valor) / meta, 0.0, 1.0)
	_exibido = lerp(_exibido, alvo, min(1.0, delta * 8.0))
	update()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, rect_size)
	draw_rect(r, Color(0, 0, 0, 0.55))
	var cheio := meta > 0 and valor >= meta
	var cor := Jogo.CIANO
	if meta <= 0:
		cor = Color.from_hsv(fmod(_t * 0.25, 1.0), 0.8, 1.0)
	elif cheio:
		cor = Jogo.VERDE
	var w := rect_size.x * _exibido
	if w > 1.0:
		draw_rect(Rect2(0, 0, w, rect_size.y), cor.darkened(0.25))
		draw_rect(Rect2(0, 0, w, rect_size.y * 0.45), cor.lightened(0.15))
		# brilho que corre
		var x := fmod(_t * 160.0, rect_size.x + 80) - 40
		if x < w:
			draw_rect(Rect2(max(0, x - 18), 0, min(36, w - max(0, x - 18)), rect_size.y), Color(1, 1, 1, 0.35))
	var borda := cor if not cheio else Color(cor.r, cor.g, cor.b, 0.6 + abs(sin(_t * 5.0)) * 0.4)
	draw_rect(r, borda, false, 2.0)
	var texto := "FINAL" if meta <= 0 else "%d / %d" % [min(valor, 9999), meta]
	var tam := _fonte.get_string_size(texto)
	draw_string(_fonte, Vector2((rect_size.x - tam.x) / 2, (rect_size.y + _fonte.get_ascent() - _fonte.get_descent()) / 2), texto, Color(1, 1, 1))
