extends Reference

## DESENHO COM BORDA LISA para a TV Box.
## No GLES2 do Android o "antialiased" de draw_line/draw_arc/draw_polyline
## não faz nada e os polígonos saem com a borda em escadinha (serrilhada).
## Aqui cada forma ganha uma franja de ~1 pixel da tela que vai do opaco ao
## transparente: a borda fica lisa em qualquer resolução, sem MSAA.
## Tudo vai para um lote só de triângulos: UMA chamada de desenho por nó.
##
##   var lote = TracoSuave.new()
##   lote.preparar(self)            # mede quantos pixels da tela vale 1 unidade
##   lote.linha(pontos, cor, 6.0)
##   lote.desenhar(self)

var pontos := PoolVector2Array()
var cores := PoolColorArray()
var indices := PoolIntArray()
var franja := 1.0          # largura da borda macia, em unidades locais (= 1 px da tela)

const MITRA_MAX := 3.0


## Calcula a franja pela escala real na tela (estica da janela + pais).
func preparar(no: CanvasItem) -> void:
	pontos.resize(0)
	cores.resize(0)
	indices.resize(0)
	var esc := no.get_global_transform_with_canvas().get_scale().x
	var vp := no.get_viewport()
	if vp != null:
		esc *= vp.get_final_transform().get_scale().x
	franja = 1.15 / max(abs(esc), 0.05)


func desenhar(no: CanvasItem) -> void:
	if indices.size() > 0:
		VisualServer.canvas_item_add_triangle_array(no.get_canvas_item(), indices, pontos, cores)


func _v(p: Vector2, c: Color) -> int:
	pontos.append(p)
	cores.append(c)
	return pontos.size() - 1


func _tri(a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(b)
	indices.append(c)


func _quad(a: int, b: int, c: int, d: int) -> void:
	# a-b de um lado, d-c do outro (a,b,c,d em volta)
	_tri(a, b, c)
	_tri(a, c, d)


## Normais "de canto" de um polígono fechado (para fora, com mitra).
func _normais_fechadas(pts: PoolVector2Array, limite := MITRA_MAX) -> PoolVector2Array:
	var n := pts.size()
	var area := 0.0
	for i in range(n):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var sentido: float = 1.0 if area > 0.0 else -1.0
	var r := PoolVector2Array()
	for i in range(n):
		var ant: Vector2 = pts[(i - 1 + n) % n]
		var p: Vector2 = pts[i]
		var prox: Vector2 = pts[(i + 1) % n]
		var n1 := (p - ant).normalized()
		var n2 := (prox - p).normalized()
		n1 = Vector2(n1.y, -n1.x) * sentido
		n2 = Vector2(n2.y, -n2.x) * sentido
		r.append(_mitra(n1, n2, limite))
	return r


func _mitra(n1: Vector2, n2: Vector2, limite := MITRA_MAX) -> Vector2:
	var m := n1 + n2
	if m.length_squared() < 0.0001:
		return n1
	m = m.normalized()
	var d := m.dot(n1)
	return m / max(d, 1.0 / limite)


## Polígono convexo preenchido com a borda lisa.
func poligono(pts: PoolVector2Array, cor: Color) -> void:
	var n := pts.size()
	if n < 3:
		return
	var nr := _normais_fechadas(pts)
	var transp := Color(cor.r, cor.g, cor.b, 0.0)
	var meio := franja * 0.5
	var dentro := []
	var fora := []
	for i in range(n):
		dentro.append(_v(pts[i] - nr[i] * meio, cor))
		fora.append(_v(pts[i] + nr[i] * meio, transp))
	for i in range(1, n - 1):
		_tri(dentro[0], dentro[i], dentro[i + 1])
	for i in range(n):
		var j := (i + 1) % n
		_quad(dentro[i], dentro[j], fora[j], fora[i])


## Aura macia em volta de um polígono convexo (cor na borda -> 0 em "largura").
func aura(pts: PoolVector2Array, cor: Color, largura: float) -> void:
	var n := pts.size()
	if n < 3:
		return
	# mitra curta: nas pontas finas do segmento a aura não vira espinho
	var nr := _normais_fechadas(pts, 1.0)
	var transp := Color(cor.r, cor.g, cor.b, 0.0)
	var borda := []
	var fora := []
	for i in range(n):
		borda.append(_v(pts[i], cor))
		fora.append(_v(pts[i] + nr[i] * largura, transp))
	for i in range(1, n - 1):
		_tri(borda[0], borda[i], borda[i + 1])
	for i in range(n):
		var j := (i + 1) % n
		_quad(borda[i], borda[j], fora[j], fora[i])


## Linha grossa com cantos em mitra e bordas lisas.
func linha(pts: PoolVector2Array, cor: Color, largura: float, fechada := false, pontas := true) -> void:
	var n := pts.size()
	if n < 2:
		return
	var c := cor
	var nucleo := largura * 0.5 - franja * 0.5
	if nucleo < 0.0:
		# linha mais fina que a franja: fica só a franja, mais transparente
		c.a *= clamp(largura / franja, 0.15, 1.0)
		nucleo = 0.0
	var ext := nucleo + franja
	var transp := Color(c.r, c.g, c.b, 0.0)
	var normais := PoolVector2Array()
	for i in range(n):
		var ant: Vector2
		var prox: Vector2
		var p: Vector2 = pts[i]
		if fechada:
			ant = pts[(i - 1 + n) % n]
			prox = pts[(i + 1) % n]
		else:
			ant = pts[i - 1] if i > 0 else p
			prox = pts[i + 1] if i < n - 1 else p
		var d1: Vector2 = (p - ant).normalized() if p != ant else (prox - p).normalized()
		var d2: Vector2 = (prox - p).normalized() if prox != p else d1
		normais.append(_mitra(Vector2(-d1.y, d1.x), Vector2(-d2.y, d2.x)))
	var ult := n if fechada else n - 1
	var base := pontos.size()
	for i in range(n):
		var p: Vector2 = pts[i]
		var nm: Vector2 = normais[i]
		_v(p + nm * ext, transp)
		_v(p + nm * nucleo, c)
		_v(p - nm * nucleo, c)
		_v(p - nm * ext, transp)
	for i in range(ult):
		var a := base + i * 4
		var b := base + ((i + 1) % n) * 4
		_quad(a, b, b + 1, a + 1)
		_quad(a + 1, b + 1, b + 2, a + 2)
		_quad(a + 2, b + 2, b + 3, a + 3)
	if pontas and not fechada:
		_ponta(pts[0], pts[0] - pts[1], normais[0], nucleo, ext, c, transp)
		_ponta(pts[n - 1], pts[n - 1] - pts[n - 2], normais[n - 1], nucleo, ext, c, transp)


## Franja na ponta da linha (senão a ponta fica serrilhada).
func _ponta(p: Vector2, dir: Vector2, nm: Vector2, nucleo: float, ext: float, c: Color, transp: Color) -> void:
	if dir.length_squared() < 0.0001:
		return
	var d := dir.normalized() * franja
	var a := _v(p + nm * nucleo, c)
	var b := _v(p - nm * nucleo, c)
	var a2 := _v(p + nm * ext + d, transp)
	var b2 := _v(p - nm * ext + d, transp)
	_quad(a, b, b2, a2)


## Brilho macio ao longo de uma linha: forte no meio, some até "largura".
func linha_brilho(pts: PoolVector2Array, cor: Color, largura: float, fechada := false) -> void:
	var f := franja
	franja = largura * 0.5
	linha(pts, cor, largura * 0.5, fechada, false)
	franja = f


## Ponto de luz redondo e macio.
func brilho_redondo(c: Vector2, raio: float, cor: Color) -> void:
	aura(arco(c, raio * 0.25, 0.0, TAU, 16, false), cor, raio * 0.75)


## Vários segmentos soltos (pares de pontos), como draw_multiline.
func segmentos(pares: PoolVector2Array, cor: Color, largura: float) -> void:
	var i := 0
	while i + 1 < pares.size():
		linha(PoolVector2Array([pares[i], pares[i + 1]]), cor, largura)
		i += 2


## Círculo cheio.
func circulo(c: Vector2, raio: float, cor: Color, lados := 32) -> void:
	poligono(arco(c, raio, 0.0, TAU, lados, false), cor)


## Pontos de um arco (sem repetir o primeiro quando é volta inteira).
static func arco(c: Vector2, raio: float, a0: float, a1: float, lados: int, incluir_fim := true) -> PoolVector2Array:
	var r := PoolVector2Array()
	var qtd := lados + (1 if incluir_fim else 0)
	for i in range(qtd):
		var a := a0 + (a1 - a0) * float(i) / lados
		r.append(c + Vector2(cos(a), sin(a)) * raio)
	return r
