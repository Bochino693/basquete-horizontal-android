extends Node2D

## Luz feita de triângulos com a cor nos vértices (sem imagem): só pinta a
## área onde tem luz, e é desenhada UMA vez. Cor, brilho, posição e giro
## mudam pelo nó (modulate/rotation), sem redesenhar.
##   FEIXE: faixa macia e comprida (luz que varre a tela)
##   FACHO: cone de refletor saindo do topo (ponta na origem, para baixo)

enum { FEIXE, FACHO }
var forma := FEIXE

# (Pool*Array no Godot 3 é passado por cópia: por isso ficam no nó)
var pontos := PoolVector2Array()
var cores := PoolColorArray()
var indices := PoolIntArray()


func _draw() -> void:
	if indices.size() == 0:
		if forma == FEIXE:
			_feixe()
		else:
			_facho()
	VisualServer.canvas_item_add_triangle_array(get_canvas_item(), indices, pontos, cores)


## Elipse macia 1792 x 256 (igual ao brilho.png esticado de antes).
func _feixe() -> void:
	var rx := 896.0
	var ry := 128.0
	var aneis := [0.0, 0.3, 0.6, 1.0]
	var lados := 20
	for r in aneis:
		var a := pow(1.0 - r, 2.2)
		if r == 0.0:
			pontos.append(Vector2.ZERO)
			cores.append(Color(1, 1, 1, 1))
			continue
		for i in range(lados):
			var ang := TAU * i / lados
			pontos.append(Vector2(cos(ang) * rx * r, sin(ang) * ry * r))
			cores.append(Color(1, 1, 1, a))
	# miolo (leque) e anéis
	for i in range(lados):
		indices.append_array(PoolIntArray([0, 1 + i, 1 + (i + 1) % lados]))
	for k in range(aneis.size() - 2):
		var b0 := 1 + k * lados
		var b1 := b0 + lados
		for i in range(lados):
			var j := (i + 1) % lados
			indices.append_array(PoolIntArray([b0 + i, b1 + i, b1 + j, b0 + i, b1 + j, b0 + j]))


## Cone de 384 x 832 (igual ao feixe.png com escala 1.5 x 1.3 de antes).
func _facho() -> void:
	var comp := 832.0
	var meia := 192.0
	var linhas := [0.0, 0.06, 0.2, 0.4, 0.65, 1.0]
	var colunas := [-1.0, -0.6, -0.3, 0.0, 0.3, 0.6, 1.0]
	for v in linhas:
		var larg: float = meia * (0.06 + 0.94 * v) + 6.0
		for u in colunas:
			var a: float = pow(1.0 - abs(u), 1.8) * pow(1.0 - v, 1.3) * clamp(v * 16.0, 0.0, 1.0)
			pontos.append(Vector2(u * larg, v * comp))
			cores.append(Color(1, 1, 1, a))
	var nc := colunas.size()
	for l in range(linhas.size() - 1):
		for c in range(nc - 1):
			var i := l * nc + c
			indices.append_array(PoolIntArray([i, i + 1, i + nc + 1, i, i + nc + 1, i + nc]))
