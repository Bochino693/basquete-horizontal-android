extends Control

## Relógio circular: anel neon que esvazia com o tempo, muda de cor
## (verde -> amarelo -> vermelho) e pulsa nos segundos finais. Os segundos
## ficam no meio em LED.
##
## NÍTIDO NA MALI E LEVE: o anel é geometria com a borda lisa (franja de 1
## pixel da tela, só cor nos vértices - a Mali desenha liso, sem conta por
## pixel), montado UMA vez com a volta inteira em passos; o arco do tempo
## que resta é só o começo da lista de triângulos (nada é refeito no
## GDScript: muda quantos passos entram). A cor é o modulate. Na ponta do
## arco, o PONTEIRO: um ponto branco liso com o brilho da cor em volta
## (também geometria pronta, que só anda).

const TracoSuave = preload("res://scripts/traco_suave.gd")
const PASSOS := 180

var total := 40.0
var restante := 40.0
var alerta := 10.0
var _t := 0.0
var _led: Control
var _fundo: MeshInstance2D
var _arco: Node2D
var _halo: Node2D
var _ponta: MeshInstance2D
var _ponta_brilho: MeshInstance2D
var _raio := 1.0
var _centro := Vector2.ZERO
# o anel inteiro (pontos, cores, índices) do arco e do brilho
var _arco_pts := PoolVector2Array()
var _arco_cores := PoolColorArray()
var _arco_idx := PoolIntArray()
var _halo_pts := PoolVector2Array()
var _halo_cores := PoolColorArray()
var _halo_idx := PoolIntArray()
var _passos_desenhados := -1


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_halo = Node2D.new()
	add_child(_halo)
	_fundo = MeshInstance2D.new()
	add_child(_fundo)
	_arco = Node2D.new()
	add_child(_arco)
	var aditivo := CanvasItemMaterial.new()
	aditivo.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_ponta_brilho = MeshInstance2D.new()
	_ponta_brilho.material = aditivo
	add_child(_ponta_brilho)
	_ponta = MeshInstance2D.new()
	add_child(_ponta)
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
	_centro = rect_size / 2
	_raio = r - 12.0
	for n in [_fundo, _arco, _halo, _ponta, _ponta_brilho]:
		n.position = _centro
	var esc := 1.0
	var vp := get_viewport()
	if vp != null:
		esc = abs(vp.get_final_transform().get_scale().x * vp.canvas_transform.get_scale().x)
	# (a geometria pronta fica guardada: a próxima partida já a encontra)
	var chave := "anel:%d:%d" % [int(_raio * 100), int(esc * 100)]
	if not Jogo.malhas.has(chave):
		Jogo.malhas[chave] = _construir(esc)
	var g: Dictionary = Jogo.malhas[chave]
	_fundo.mesh = g.fundo
	_ponta.mesh = g.ponta
	_ponta_brilho.mesh = g.ponta_brilho
	_arco_pts = g.arco[0]
	_arco_cores = g.arco[1]
	_arco_idx = g.arco[2]
	_halo_pts = g.halo[0]
	_halo_cores = g.halo[1]
	_halo_idx = g.halo[2]
	_passos_desenhados = -1


func _construir(esc: float) -> Dictionary:
	var g := {}
	var lote = TracoSuave.new()
	# o fundo: a volta inteira, clarinha
	lote.preparar_escala(esc)
	lote.linha(TracoSuave.arco(Vector2.ZERO, _raio, 0.0, TAU, 96, false), Color(1, 1, 1, 0.08), 12.0, true)
	g.fundo = lote.malha()
	# o arco e o brilho dele: a volta inteira em passos (começa no topo)
	_faixa(lote, esc, 10.0, false)
	g.arco = [lote.pontos, lote.cores, lote.indices]
	_faixa(lote, esc, 30.0, true)
	g.halo = [lote.pontos, lote.cores, lote.indices]
	# o ponteiro: ponto branco liso e o brilho em volta
	lote.preparar_escala(esc)
	lote.circulo(Vector2.ZERO, 6.0, Color(1, 1, 1), 20)
	g.ponta = lote.malha()
	lote.preparar_escala(esc)
	lote.brilho_redondo(Vector2.ZERO, 22.0, Color(1, 1, 1, 0.9))
	g.ponta_brilho = lote.malha()
	return g


## A faixa do anel (do topo, no sentido do relógio), em PASSOS pedaços: a
## tampa lisa do começo vem primeiro na lista de índices e cada passo
## depois (3 quadrados: franja de fora, miolo, franja de dentro); o arco de
## k passos é o começo da lista. "macio": brilho que some (sem miolo).
func _faixa(lote, esc: float, largura: float, macio: bool) -> void:
	lote.preparar_escala(esc)
	var f: float = lote.franja
	var nucleo := 0.0 if macio else max(largura * 0.5 - f * 0.5, 0.0)
	var ext := largura * 0.5 if macio else nucleo + f
	var cheio := Color(1, 1, 1)
	var vazio := Color(1, 1, 1, 0.0)
	# (listas locais: num PoolArray de outro objeto o append não ficaria)
	var pts := PoolVector2Array()
	var cores := PoolColorArray()
	var bloco := PoolColorArray([vazio, cheio, cheio, vazio])
	var r0 := _raio + ext
	var r1 := _raio + nucleo
	var r2 := _raio - nucleo
	var r3 := _raio - ext
	for k in range(PASSOS + 1):
		var a := -PI / 2 + TAU * float(k) / PASSOS
		var d := Vector2(cos(a), sin(a))
		pts.append_array(PoolVector2Array([d * r0, d * r1, d * r2, d * r3]))
		cores.append_array(bloco)
	# a tampa do começo (lisa): some para trás do topo
	var base := pts.size()
	var tras := Vector2(-f, 0)
	pts.append_array(PoolVector2Array([Vector2(0, -(_raio + nucleo)), Vector2(0, -(_raio - nucleo)),
		Vector2(0, -(_raio + ext)) + tras, Vector2(0, -(_raio - ext)) + tras]))
	cores.append_array(PoolColorArray([cheio, cheio, vazio, vazio]))
	var idx := PoolIntArray([base, base + 1, base + 3, base, base + 3, base + 2])
	for k in range(PASSOS):
		var a0 := k * 4
		var b0 := a0 + 4
		for j in range(3):
			idx.append_array(PoolIntArray([a0 + j, b0 + j, b0 + j + 1, a0 + j, b0 + j + 1, a0 + j + 1]))
	lote.pontos = pts
	lote.cores = cores
	lote.indices = idx


func _cor() -> Color:
	var k := restante / max(total, 0.001)
	if restante <= alerta:
		return Jogo.VERMELHO
	if k < 0.5:
		return Jogo.AMARELO
	return Jogo.VERDE


## Desenha o arco de k passos (só quando k muda).
func _desenhar_arco(k: int) -> void:
	_passos_desenhados = k
	for par in [[_arco, _arco_pts, _arco_cores, _arco_idx], [_halo, _halo_pts, _halo_cores, _halo_idx]]:
		var no: Node2D = par[0]
		var item := no.get_canvas_item()
		VisualServer.canvas_item_clear(item)
		if k <= 0:
			continue
		# o começo da lista (cópia encurtada: o PoolIntArray copia no C++)
		var idx: PoolIntArray = par[3]
		idx.resize(6 + k * 18)
		VisualServer.canvas_item_add_triangle_array(item, idx, par[1], par[2])


func _process(delta: float) -> void:
	_t += delta
	var seg := int(ceil(max(restante, 0.0)))
	if _led.valor != seg:
		_led.valor = seg
	var cor := _cor()
	_led.cor = cor
	_led.piscar(restante <= 5.0 and restante > 0.0)
	var k := clamp(restante / max(total, 0.001), 0.0, 1.0)
	var passos := int(ceil(k * PASSOS))
	if passos != _passos_desenhados:
		_desenhar_arco(passos)
	var pulso := 1.0
	if restante <= alerta and restante > 0:
		pulso = 1.0 + abs(sin(_t * 6.0)) * 0.6
	_arco.modulate = Color(cor.r, cor.g, cor.b)
	_halo.modulate = Color(cor.r, cor.g, cor.b, 0.35 * pulso)
	# o ponteiro anda com a ponta do arco (o fim do último passo)
	var a := -PI / 2 + TAU * float(passos) / PASSOS
	var p := _centro + Vector2(cos(a), sin(a)) * _raio
	_ponta.position = p
	_ponta_brilho.position = p
	_ponta.visible = passos > 0
	_ponta_brilho.visible = passos > 0
	_ponta_brilho.modulate = Color(cor.r, cor.g, cor.b, 0.6 * pulso)
