extends Control

## Barra de progresso da META da fase: enche animada, tem um brilho que
## corre por dentro e pulsa verde quando a meta é batida. Na final (meta 0)
## fica cheia, trocando de cor.
##
## LEVE PARA A TV BOX: só redesenha quando o enchimento anda (ou, na final,
## 10 vezes por segundo para trocar a cor). O brilho que corre é um
## retângulo que só anda e o pulso da meta batida é o brilho do nó.

var meta := 30 setget _set_meta
var valor := 0 setget _set_valor
var _exibido := 0.0
var _desenhado := -1.0
var _t := 0.0
var _t_cor := 0.0
var _fonte: Font
var _brilho: ColorRect


func _set_meta(v: int) -> void:
	meta = v
	update()


func _set_valor(v: int) -> void:
	valor = v
	update()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	rect_clip_content = true
	_fonte = Jogo.fonte("bungee", 18, 2)
	_brilho = ColorRect.new()
	_brilho.color = Color(1, 1, 1, 0.35)
	_brilho.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_brilho)


func _process(delta: float) -> void:
	_t += delta
	var alvo := 1.0 if meta <= 0 else clamp(float(valor) / meta, 0.0, 1.0)
	_exibido = lerp(_exibido, alvo, min(1.0, delta * 8.0))
	if abs(_exibido - _desenhado) > 0.002:
		update()
	elif meta <= 0:
		_t_cor += delta
		if _t_cor > 0.1:
			_t_cor = 0.0
			update()
	# o brilho que corre por dentro do enchimento
	var w := rect_size.x * _exibido
	var x := fmod(_t * 160.0, rect_size.x + 80) - 40
	_brilho.visible = x < w and w > 1.0
	if _brilho.visible:
		_brilho.rect_position = Vector2(max(0, x - 18), 0)
		_brilho.rect_size = Vector2(min(36, w - max(0, x - 18)), rect_size.y)
	# meta batida: pulsa pelo brilho do nó (sem redesenhar)
	var cheio := meta > 0 and valor >= meta
	var b := 1.0 + (abs(sin(_t * 5.0)) * 0.35 if cheio else 0.0)
	self_modulate = Color(b, b, b, 1.0)


func _draw() -> void:
	_desenhado = _exibido
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
	draw_rect(r, cor, false, 2.0)
	var texto := "FINAL" if meta <= 0 else "%d / %d" % [min(valor, 9999), meta]
	var tam := _fonte.get_string_size(texto)
	draw_string(_fonte, Vector2((rect_size.x - tam.x) / 2, (rect_size.y + _fonte.get_ascent() - _fonte.get_descent()) / 2), texto, Color(1, 1, 1))
