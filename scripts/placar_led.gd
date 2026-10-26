extends Control

## PLACAR DE LED de 7 segmentos, como o painel das máquinas de basquete.
## Os segmentos apagados aparecem escuros (dá a cara de painel de verdade),
## os acesos têm o miolo quase branco (o LED quente) e brilho em volta. O
## número sobe contando até o valor novo e o painel dá um "flash" a cada
## mudança.
##
## NÍTIDO NA MALI E LEVE: cada caractere (0-9 e o vazio) é UMA malha de
## triângulos com a borda lisa (franja de 1 pixel da tela, traco_suave.gd -
## só cor nos vértices: a Mali desenha liso, sem textura nem conta por
## pixel), montada uma vez para o tamanho do placar e guardada. Mudar o
## número (a contagem anda a cada quadro) só troca a malha de cada casa.
## As malhas são brancas: a cor do placar é o modulate de cada casa (o
## miolo quente tem a camada dele), então mudar a cor também não refaz
## nada. O flash e o pisca-pisca mudam o brilho do nó (modulate).

const TracoSuave = preload("res://scripts/traco_suave.gd")
const CARACTERES := "0123456789 "
const SEGMENTOS := {
	"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
	"5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", " ": "",
}

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
var _mostrado := ""
var _casas := []                       # [base, quente] de cada casa
var _malhas := {}                      # caractere -> [malha base, malha quente]


func definir_valor(v: int) -> void:
	if v == valor:
		return
	valor = v
	_flash = 1.0
	if not contar:
		_exibido = v
	set_process(true)


func definir_cor(c: Color) -> void:
	cor = c
	_pintar()


func mostrar_direto(v: int) -> void:
	valor = v
	_exibido = v
	_mostrar()


func piscar(ligado: bool) -> void:
	_piscar = ligado
	set_process(true)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	connect("resized", self, "_montar")
	_montar()
	set_process(true)


## As casas e as malhas dos caracteres (refeitas só se o tamanho mudar;
## a mesma medida em outro placar ou na próxima partida já vem pronta).
func _montar() -> void:
	for c in _casas:
		c[0].get_parent().queue_free()
	_casas = []
	_malhas = {}
	if rect_size.x < 1.0 or rect_size.y < 1.0:
		return
	var grupos := int(ceil(digitos / 3.0)) - 1 if espaco_grupo else 0
	var larg_dig := rect_size.x / (digitos + grupos * 0.45)
	var alt := rect_size.y
	var w := larg_dig * 0.78
	var t := min(w * 0.19, alt * 0.11)
	var esc := _escala_tela()
	var chave := "placar:%d:%d:%d:%d" % [int(w * 100), int(alt * 100), int(inclinacao * 1000), int(esc * 100)]
	if not Jogo.malhas.has(chave):
		Jogo.malhas[chave] = _construir(w, alt, t, esc)
	_malhas = Jogo.malhas[chave]
	var x := 0.0
	for i in range(digitos):
		if espaco_grupo and i > 0 and (digitos - i) % 3 == 0:
			x += larg_dig * 0.45
		var casa := Node2D.new()
		casa.position = Vector2(x + (larg_dig - w) / 2.0, 0)
		add_child(casa)
		var base := MeshInstance2D.new()
		var quente := MeshInstance2D.new()
		casa.add_child(base)
		casa.add_child(quente)
		_casas.append([base, quente])
		x += larg_dig
	_pintar()
	_mostrado = ""
	_mostrar()


## A borda tem 1 pixel DA TELA: só a escala da tela conta (720p ou 1080p);
## os painéis que pulam/crescem por um instante não mudam a borda.
func _escala_tela() -> float:
	var vp := get_viewport()
	if vp == null:
		return 1.0
	return abs(vp.get_final_transform().get_scale().x * vp.canvas_transform.get_scale().x)


## As malhas de todos os caracteres. A GEOMETRIA é uma só (o "8": o brilho
## dos 7 segmentos, os 7 segmentos e os 7 miolos quentes); cada caractere só
## muda as CORES (aceso, apagado ou transparente) - montar é rápido.
func _construir(w: float, h: float, t: float, esc: float) -> Dictionary:
	var lote = TracoSuave.new()
	var segs := []
	for s in "abcdefg":
		segs.append(_segmento(s, w, h, t))
	# camada de base: os 7 brilhos e depois os 7 segmentos
	lote.preparar_escala(esc)
	var blocos_brilho := []
	for pts in segs:
		var de: int = lote.pontos.size()
		lote.aura(pts, Color(1, 1, 1, 0.34), t * 0.9)
		blocos_brilho.append(_blocos(lote.cores, de, lote.pontos.size(), Color(0.13, 0.13, 0.13, 0.0)))
	var blocos_corpo := []
	for pts in segs:
		var de: int = lote.pontos.size()
		lote.poligono(pts, Color(1, 1, 1))
		blocos_corpo.append(_blocos(lote.cores, de, lote.pontos.size(), Color(0.13, 0.13, 0.13, 0.9)))
	var base_pts: PoolVector2Array = lote.pontos
	var base_idx: PoolIntArray = lote.indices
	# camada do miolo quente
	lote.preparar_escala(esc)
	var blocos_miolo := []
	for s in "abcdefg":
		var de: int = lote.pontos.size()
		lote.poligono(_segmento(s, w, h, t, 0.36), Color(1, 1, 1))
		blocos_miolo.append(_blocos(lote.cores, de, lote.pontos.size(), Color(1, 1, 1, 0.0)))
	var miolo_pts: PoolVector2Array = lote.pontos
	var miolo_idx: PoolIntArray = lote.indices
	var r := {}
	for ch in CARACTERES:
		var ligados: String = SEGMENTOS.get(ch, "")
		var cb := PoolColorArray()
		var cm := PoolColorArray()
		for k in 7:
			var aceso := "abcdefg"[k] in ligados
			cb.append_array(blocos_brilho[k][0 if aceso else 1])
		for k in 7:
			var aceso := "abcdefg"[k] in ligados
			cb.append_array(blocos_corpo[k][0 if aceso else 1])
			cm.append_array(blocos_miolo[k][0 if aceso else 1])
		r[ch] = [_malha(base_pts, cb, base_idx), _malha(miolo_pts, cm, miolo_idx)]
	return r


## As cores de um pedaço do lote: [aceso (como foi feito), apagado (a cor
## "apagada", com a mesma transparência relativa)].
static func _blocos(cores: PoolColorArray, de: int, ate: int, apagada: Color) -> Array:
	var aceso := PoolColorArray()
	var apagado := PoolColorArray()
	for i in range(de, ate):
		var c: Color = cores[i]
		aceso.append(c)
		apagado.append(Color(apagada.r, apagada.g, apagada.b, apagada.a * c.a))
	return [aceso, apagado]


static func _malha(pts: PoolVector2Array, cores: PoolColorArray, idx: PoolIntArray) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	arr[Mesh.ARRAY_COLOR] = cores
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## A cor: a base na cor do placar, o miolo quase branco (puxado para ela).
func _pintar() -> void:
	var quente := Color(lerp(cor.r, 1.0, 0.62), lerp(cor.g, 1.0, 0.62), lerp(cor.b, 1.0, 0.55))
	for c in _casas:
		c[0].modulate = Color(cor.r, cor.g, cor.b)
		c[1].modulate = quente


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
	_mostrar()
	# flash e pisca-pisca pelo brilho do nó
	var b := 1.0 + _flash * 0.6
	if _piscar:
		ativo = true
		if fmod(_t, 0.5) < 0.2:
			b *= 0.35
	modulate = Color(b, b, b, 1.0)
	if not ativo:
		set_process(false)


func _texto() -> String:
	var texto := str(int(round(_exibido))).pad_zeros(digitos)
	if texto.length() > digitos:
		texto = texto.right(texto.length() - digitos)
	return texto


## Troca só as malhas das casas que mudaram.
func _mostrar() -> void:
	if _casas.empty():
		return
	var texto := _texto()
	if texto == _mostrado:
		return
	for i in range(digitos):
		if _mostrado.length() == digitos and _mostrado[i] == texto[i]:
			continue
		var m: Array = _malhas.get(texto[i], _malhas[" "])
		_casas[i][0].mesh = m[0]
		_casas[i][1].mesh = m[1]
	_mostrado = texto


## Um segmento (hexágono alongado) de um dígito de largura w e altura h.
## "fino" < 1: o miolo quente do segmento (mais fino e um pouco mais curto).
func _segmento(s: String, w: float, h: float, t: float, fino := 1.0) -> PoolVector2Array:
	var m := h / 2.0
	var g := t * 0.12   # folga entre segmentos
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
	if fino < 1.0:
		p0 += d * meio * 0.9
		p1 -= d * meio * 0.9
		meio *= fino
	for p in [p0, p0 + d * meio + n * meio, p1 - d * meio + n * meio, p1, p1 - d * meio - n * meio, p0 + d * meio - n * meio]:
		# itálico: quanto mais alto, mais para a direita
		pts.append(Vector2(p.x + (h - p.y) * inclinacao, p.y))
	return pts
