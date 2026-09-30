extends Control

## PLACAR DE LED de 7 segmentos, como o painel das máquinas de basquete.
## Os segmentos apagados aparecem escuros (dá a cara de painel de verdade),
## os acesos têm brilho em volta. O número sobe contando até o valor novo e
## o painel dá um "flash" a cada mudança.
##
## LEVE PARA A TV BOX: só redesenha quando o número mostrado (ou a cor) muda.
## O flash e o pisca-pisca mudam o brilho do nó (self_modulate), sem refazer
## os segmentos.

export var digitos := 6
export var espaco_grupo := true        # "040 000": espaço a cada 3 dígitos
export var cor := Color(1.0, 0.48, 0.10) setget definir_cor
export var inclinacao := 0.10          # itálico dos dígitos
export var contar := true              # anima a contagem até o valor

var valor := 0 setget definir_valor
var _exibido := 0.0
var _flash := 0.0
var _piscar := false
var _t := 0.0
var _texto_desenhado := ""

const SEGMENTOS := {
	"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
	"5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", " ": "",
}


func definir_valor(v: int) -> void:
	if v == valor:
		return
	valor = v
	_flash = 1.0
	if not contar:
		_exibido = v
	set_process(true)


func definir_cor(c: Color) -> void:
	if c == cor:
		return
	cor = c
	update()


func mostrar_direto(v: int) -> void:
	valor = v
	_exibido = v
	update()


func piscar(ligado: bool) -> void:
	_piscar = ligado
	set_process(true)


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	var ativo := false
	if abs(_exibido - valor) > 0.01:
		# Sobe rápido quando falta muito, devagar no fim (efeito de contagem).
		var passo := max(1.0, abs(valor - _exibido) * 10.0 * delta)
		_exibido = move_toward(_exibido, valor, passo)
		ativo = true
	if _flash > 0.0:
		_flash = max(0.0, _flash - delta * 2.5)
		ativo = true
	if _texto() != _texto_desenhado:
		update()
	# flash e pisca-pisca pelo brilho do nó: não redesenha
	var b := 1.0 + _flash * 0.6
	if _piscar:
		ativo = true
		if fmod(_t, 0.5) < 0.2:
			b *= 0.35
	self_modulate = Color(b, b, b, 1.0)
	if not ativo:
		set_process(false)


func _texto() -> String:
	var texto := str(int(round(_exibido))).pad_zeros(digitos)
	if texto.length() > digitos:
		texto = texto.right(texto.length() - digitos)
	return texto


func _draw() -> void:
	var texto := _texto()
	_texto_desenhado = texto
	var grupos := int(ceil(digitos / 3.0)) - 1 if espaco_grupo else 0
	var larg_total := rect_size.x
	var alt := rect_size.y
	var larg_dig := larg_total / (digitos + grupos * 0.45)
	var w := larg_dig * 0.78
	var t := min(w * 0.19, alt * 0.11)
	var acesa := Color(cor.r, cor.g, cor.b)
	var apagada := Color(cor.r * 0.13, cor.g * 0.13, cor.b * 0.13, 0.9)
	var brilho_cor := Color(cor.r, cor.g, cor.b, 0.34)
	# Segmentos com a borda lisa e um brilho macio em volta dos acesos,
	# tudo num lote só de triângulos: UMA chamada de desenho por placar.
	_lote.preparar(self)
	var acesos := []
	var x := 0.0
	for i in range(digitos):
		if espaco_grupo and i > 0 and (digitos - i) % 3 == 0:
			x += larg_dig * 0.45
		var ch := texto[i]
		var ligados: String = SEGMENTOS.get(ch, "")
		for s in "abcdefg":
			var pts := _segmento(s, Vector2(x + (larg_dig - w) / 2, 0), w, alt, t)
			if s in ligados:
				acesos.append(pts)
				_lote.aura(pts, brilho_cor, t * 0.9)
			else:
				_lote.poligono(pts, apagada)
		x += larg_dig
	for pts in acesos:
		_lote.poligono(pts, acesa)
	_lote.desenhar(self)


var _lote = preload("res://scripts/traco_suave.gd").new()


func _segmento(s: String, o: Vector2, w: float, h: float, t: float) -> PoolVector2Array:
	var m := h / 2.0
	var g := t * 0.18   # folga entre segmentos
	var a: Vector2
	var b: Vector2
	match s:
		"a":
			a = Vector2(0, 0)
			b = Vector2(w, 0)
		"g":
			a = Vector2(0, m)
			b = Vector2(w, m)
		"d":
			a = Vector2(0, h)
			b = Vector2(w, h)
		"f":
			a = Vector2(0, 0)
			b = Vector2(0, m)
		"e":
			a = Vector2(0, m)
			b = Vector2(0, h)
		"b":
			a = Vector2(w, 0)
			b = Vector2(w, m)
		"c":
			a = Vector2(w, m)
			b = Vector2(w, h)
	var pts := PoolVector2Array()
	# Recuo para dentro da caixa (o traço não sai do dígito).
	var dentro := Vector2(t / 2, t / 2)
	var caixa := Vector2(w - t, h - t)
	a = Vector2(dentro.x + a.x / w * caixa.x, dentro.y + a.y / h * caixa.y)
	b = Vector2(dentro.x + b.x / w * caixa.x, dentro.y + b.y / h * caixa.y)
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var p0 := a + d * g
	var p1 := b - d * g
	var meio := t / 2
	for p in [p0, p0 + d * meio + n * meio, p1 - d * meio + n * meio, p1, p1 - d * meio - n * meio, p0 + d * meio - n * meio]:
		# itálico: quanto mais alto, mais para a direita
		pts.append(o + Vector2(p.x + (h - p.y) * inclinacao, p.y))
	return pts
