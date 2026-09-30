extends Control

## PLACAR DE LED de 7 segmentos, como o painel das máquinas de basquete.
## Os segmentos apagados aparecem escuros (dá a cara de painel de verdade),
## os acesos têm brilho em volta. O número sobe contando até o valor novo e
## o painel dá um "flash" a cada mudança.

export var digitos := 6
export var espaco_grupo := true        # "040 000": espaço a cada 3 dígitos
export var cor := Color(1.0, 0.48, 0.10)
export var inclinacao := 0.10          # itálico dos dígitos
export var contar := true              # anima a contagem até o valor

var valor := 0 setget definir_valor
var _exibido := 0.0
var _flash := 0.0
var _piscar := false
var _t := 0.0

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
	if _piscar:
		ativo = true
	update()
	if not ativo:
		set_process(false)


func _draw() -> void:
	var texto := str(int(round(_exibido))).pad_zeros(digitos)
	if texto.length() > digitos:
		texto = texto.right(texto.length() - digitos)
	var grupos := int(ceil(digitos / 3.0)) - 1 if espaco_grupo else 0
	var larg_total := rect_size.x
	var alt := rect_size.y
	var larg_dig := larg_total / (digitos + grupos * 0.45)
	var w := larg_dig * 0.78
	var t := min(w * 0.19, alt * 0.11)
	var brilho := 1.0 + _flash * 0.6
	if _piscar and fmod(_t, 0.5) < 0.2:
		brilho *= 0.35
	var acesa := Color(min(cor.r * brilho, 1.0), min(cor.g * brilho, 1.0), min(cor.b * brilho, 1.0))
	var apagada := Color(cor.r * 0.13, cor.g * 0.13, cor.b * 0.13, 0.9)
	var brilho_cor := Color(cor.r, cor.g, cor.b, 0.22 + _flash * 0.25)
	_pontos = PoolVector2Array()
	_cores = PoolColorArray()
	_indices = PoolIntArray()
	var x := 0.0
	for i in range(digitos):
		if espaco_grupo and i > 0 and (digitos - i) % 3 == 0:
			x += larg_dig * 0.45
		var ch := texto[i]
		var ligados: String = SEGMENTOS.get(ch, "")
		for s in "abcdefg":
			var pts := _segmento(s, Vector2(x + (larg_dig - w) / 2, 0), w, alt, t)
			if s in ligados:
				_hexagono(_engordar(pts, t * 0.55), brilho_cor)
				_hexagono(pts, acesa)
			else:
				_hexagono(pts, apagada)
		x += larg_dig
	# Tudo num lote só de triângulos: UMA chamada de desenho por placar
	# (antes eram até 84; a GPU da TV Box 7.1 sente cada uma).
	VisualServer.canvas_item_add_triangle_array(get_canvas_item(), _indices, _pontos, _cores)


var _pontos := PoolVector2Array()
var _cores := PoolColorArray()
var _indices := PoolIntArray()


## Hexágono do segmento em 4 triângulos, acrescentado ao lote.
func _hexagono(pts: PoolVector2Array, cor: Color) -> void:
	var b := _pontos.size()
	for p in pts:
		_pontos.append(p)
		_cores.append(cor)
	for tri in [[0, 1, 5], [1, 2, 4], [1, 4, 5], [2, 3, 4]]:
		_indices.append(b + tri[0])
		_indices.append(b + tri[1])
		_indices.append(b + tri[2])


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


func _engordar(pts: PoolVector2Array, quanto: float) -> PoolVector2Array:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var r := PoolVector2Array()
	for p in pts:
		var v: Vector2 = p - c
		r.append(c + v + v.normalized() * quanto)
	return r
