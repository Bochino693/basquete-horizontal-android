extends Node2D

## A CESTA NA TELA: aro neon e rede desenhados por código, bola caindo pelo
## aro a cada ponto, rede esticando (mola), faíscas, onda de choque e fogo
## no modo EM CHAMAS. A origem deste nó é o centro do aro.
##
## LEVE PARA A TV BOX: aro e rede são desenhados UMA vez. A cor do aro muda
## pelo modulate do nó; o balanço e a esticada da rede são feitos pela placa
## de vídeo (shader rede_mola). Só as ondas de choque redesenham, e só
## enquanto existem.

export var raio_x := 96.0
export var raio_y := 15.0
export var altura_rede := 104.0

var em_chamas := false setget _set_chamas

var _atras: Node2D
var _rede: Node2D
var _aro: Node2D
var _aro_brilho: Node2D
var _ondas_no: Node2D
var _mat_rede: ShaderMaterial
var _bolas: Node2D
var _faiscas: CPUParticles2D
var _estrelas: CPUParticles2D
var _fogo: CPUParticles2D
var _halo: Sprite
var _t := 0.0
var _estica := 0.0        # rede esticada (mola)
var _estica_vel := 0.0
var _ondas := []          # ondas de choque [{t, cor}]
var _tex_bola: Texture
const TracoSuave = preload("res://scripts/traco_suave.gd")
var _lote_atras = TracoSuave.new()
var _lote_rede = TracoSuave.new()
var _lote_aro = TracoSuave.new()
var _lote_aro_brilho = TracoSuave.new()
var _lote_ondas = TracoSuave.new()
var _tinha_ondas := false


func _ready() -> void:
	_tex_bola = load("res://imagens/bola.png")
	var aditivo := CanvasItemMaterial.new()
	aditivo.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_halo = Sprite.new()
	_halo.texture = load("res://imagens/brilho.png")
	_halo.material = aditivo
	_halo.scale = Vector2(1.7, 0.65)
	_halo.position = Vector2(0, 10)
	_halo.modulate = Color(1.0, 0.45, 0.1, 0.35)
	add_child(_halo)

	_atras = _camada("_desenhar_atras")
	_bolas = Node2D.new()
	add_child(_bolas)
	_rede = _camada("_desenhar_rede")
	_mat_rede = ShaderMaterial.new()
	_mat_rede.shader = load("res://shaders/rede_mola.shader")
	_mat_rede.set_shader_param("altura", altura_rede)
	_mat_rede.set_shader_param("topo", raio_y)
	_rede.material = _mat_rede
	_aro = _camada("_desenhar_aro")
	_aro_brilho = _camada("_desenhar_aro_brilho")
	_ondas_no = _camada("_desenhar_ondas")

	_faiscas = _criar_explosao(load("res://imagens/faisca.png"), 34, aditivo)
	_estrelas = _criar_explosao(load("res://imagens/estrela.png"), 10, aditivo)
	_estrelas.scale_amount = 0.35

	_fogo = CPUParticles2D.new()
	_fogo.texture = load("res://imagens/brilho.png")
	_fogo.material = aditivo
	_fogo.amount = 42
	_fogo.lifetime = 0.7
	_fogo.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_fogo.emission_rect_extents = Vector2(raio_x, raio_y)
	_fogo.direction = Vector2(0, -1)
	_fogo.spread = 12
	_fogo.gravity = Vector2(0, -260)
	_fogo.initial_velocity = 90
	_fogo.initial_velocity_random = 0.5
	_fogo.scale_amount = 0.275
	_fogo.scale_amount_random = 0.5
	var rampa := Gradient.new()
	rampa.set_color(0, Color(1, 0.95, 0.5, 0.9))
	rampa.set_color(1, Color(0.8, 0.05, 0.1, 0.0))
	rampa.add_point(0.35, Color(1, 0.55, 0.1, 0.8))
	_fogo.color_ramp = rampa
	var curva := Curve.new()
	curva.add_point(Vector2(0, 0.6))
	curva.add_point(Vector2(0.4, 1.0))
	curva.add_point(Vector2(1, 0.2))
	_fogo.scale_amount_curve = curva
	_fogo.emitting = false
	add_child(_fogo)
	move_child(_fogo, 1)


func _camada(metodo: String) -> Node2D:
	var n := Node2D.new()
	add_child(n)
	n.connect("draw", self, metodo, [n])
	return n


func _criar_explosao(tex: Texture, qtd: int, mat: Material) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.material = mat
	p.amount = qtd
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.9
	p.emitting = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(raio_x * 0.8, 4)
	p.direction = Vector2(0, -1)
	p.spread = 70
	p.gravity = Vector2(0, 520)
	p.initial_velocity = 360
	p.initial_velocity_random = 0.5
	p.scale_amount = 0.45
	p.scale_amount_random = 0.6
	var rampa := Gradient.new()
	rampa.set_color(0, Color(1, 1, 0.8, 1))
	rampa.set_color(1, Color(1, 0.2, 0.6, 0))
	rampa.add_point(0.4, Color(1, 0.65, 0.15, 1))
	p.color_ramp = rampa
	add_child(p)
	return p


func _set_chamas(v: bool) -> void:
	em_chamas = v
	_fogo.emitting = v


## Uma cesta: a bola cai pelo aro. cor = cor do destaque (onda e faíscas).
func anotar(cor: Color = Color(1.0, 0.6, 0.15)) -> void:
	var b := Sprite.new()
	b.texture = _tex_bola
	var escala := (raio_x * 1.18) / _tex_bola.get_width()
	b.scale = Vector2(escala, escala)
	var x0 := rand_range(-raio_x * 0.45, raio_x * 0.45)
	b.position = Vector2(x0, -300)
	b.rotation = randf() * TAU
	_bolas.add_child(b)
	var tw := Tween.new()
	b.add_child(tw)
	# desce acelerando até o aro, passa pela rede e some embaixo
	tw.interpolate_property(b, "position", Vector2(x0, -300), Vector2(x0 * 0.3, 0), 0.32, Tween.TRANS_QUAD, Tween.EASE_IN)
	tw.interpolate_property(b, "position", Vector2(x0 * 0.3, 0), Vector2(0, altura_rede + 80), 0.30, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.32)
	tw.interpolate_property(b, "rotation", b.rotation, b.rotation + 5.0, 0.62)
	tw.interpolate_property(b, "modulate:a", 1.0, 0.0, 0.14, Tween.TRANS_LINEAR, Tween.EASE_IN, 0.50)
	tw.interpolate_callback(self, 0.30, "_passou_no_aro", cor)
	tw.interpolate_callback(b, 0.66, "queue_free")
	tw.start()


func _passou_no_aro(cor: Color) -> void:
	_estica_vel = 9.0
	_ondas.append({"t": 0.0, "cor": cor})
	var rampa: Gradient = _faiscas.color_ramp
	rampa.set_offset(1, 1.0)
	rampa.set_color(1, Color(cor.r, cor.g, cor.b, 0.0))
	_faiscas.restart()
	_estrelas.restart()


func _process(delta: float) -> void:
	_t += delta
	# mola da rede
	_estica_vel += (-_estica * 60.0 - _estica_vel * 7.0) * delta
	_estica += _estica_vel * delta
	for o in _ondas:
		o.t += delta
	while not _ondas.empty() and _ondas[0].t > 0.6:
		_ondas.pop_front()
	var pulso := 0.30 + sin(_t * 3.0) * 0.08
	_halo.modulate = Color(1.0, 0.25, 0.05, pulso + 0.25) if em_chamas else Color(1.0, 0.45, 0.1, pulso)
	var c := _cor_aro()
	_atras.modulate = c
	_aro.modulate = c
	# a rede balança e estica na placa de vídeo: só 2 números por quadro
	_mat_rede.set_shader_param("estica", _estica)
	_mat_rede.set_shader_param("balanco", sin(_t * 2.2) * 3.0)
	if not _ondas.empty() or _tinha_ondas:
		_ondas_no.update()
	_tinha_ondas = not _ondas.empty()


func _cor_aro() -> Color:
	if em_chamas:
		return Color(1.0, 0.75 + sin(_t * 20.0) * 0.2, 0.2)
	return Color(1.0, 0.45, 0.08)


func _elipse(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, n: int) -> PoolVector2Array:
	var pts := PoolVector2Array()
	for i in range(n + 1):
		var a: float = lerp(a0, a1, float(i) / n)
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts


# Aro e rede em branco: a cor vem do modulate do nó (muda sem redesenhar).
func _desenhar_atras(no: Node2D) -> void:
	if _lote_atras.indices.size() == 0:
		# metade de trás do aro (em cima na tela)
		var tras := _elipse(0, 0, raio_x, raio_y, PI, TAU, 32)
		_lote_atras.preparar(no)
		_lote_atras.linha_brilho(tras, Color(1, 1, 1, 0.4), 18.0)
		_lote_atras.linha(tras, Color(0.75, 0.75, 0.75), 6.0)
	_lote_atras.desenhar(no)


## Rede em repouso; o shader rede_mola estica e balança.
func _desenhar_rede(no: Node2D) -> void:
	if _lote_rede.indices.size() == 0:
		var n := 12
		var comp := altura_rede
		var estreita := 0.55
		var cor_rede := Color(1, 1, 1, 0.85)
		var topo := []
		var meio := []
		var base := []
		for i in range(n + 1):
			var a: float = lerp(0.0, PI, float(i) / n)   # só a frente (metade de baixo)
			topo.append(Vector2(cos(a) * raio_x, sin(a) * raio_y))
			meio.append(Vector2(cos(a) * raio_x * lerp(1.0, estreita, 0.55), comp * 0.5 + sin(a) * raio_y * 0.7))
			base.append(Vector2(cos(a) * raio_x * estreita, comp + sin(a) * raio_y * 0.5))
		var lote = _lote_rede
		lote.preparar(no)
		for i in range(n + 1):
			lote.linha(PoolVector2Array([topo[i], meio[i], base[i]]), cor_rede, 2.0)
		# trama cruzada
		var trama := PoolVector2Array()
		for i in range(n):
			trama.append_array(PoolVector2Array([topo[i], meio[i + 1], topo[i + 1], meio[i], meio[i], base[i + 1], meio[i + 1], base[i]]))
		lote.segmentos(trama, Color(1, 1, 1, 0.55), 1.5)
		lote.linha(PoolVector2Array(base), cor_rede, 2.0)
	_lote_rede.desenhar(no)


## Metade da frente do aro (branca; cor pelo modulate).
func _desenhar_aro(no: Node2D) -> void:
	if _lote_aro.indices.size() == 0:
		var frente := _elipse(0, 0, raio_x, raio_y, 0, PI, 32)
		_lote_aro.preparar(no)
		_lote_aro.linha_brilho(frente, Color(1, 1, 1, 0.5), 22.0)
		_lote_aro.linha(frente, Color(1, 1, 1), 7.0)
	_lote_aro.desenhar(no)


## Reflexo claro em cima do aro (não muda de cor).
func _desenhar_aro_brilho(no: Node2D) -> void:
	if _lote_aro_brilho.indices.size() == 0:
		_lote_aro_brilho.preparar(no)
		_lote_aro_brilho.linha(_elipse(0, -1.5, raio_x, raio_y, 0.15, PI - 0.15, 24), Color(1, 0.95, 0.8, 0.8), 2.0)
	_lote_aro_brilho.desenhar(no)


## Ondas de choque: só redesenham enquanto existem.
func _desenhar_ondas(no: Node2D) -> void:
	if _ondas.empty():
		return
	var lote = _lote_ondas
	lote.preparar(no)
	for o in _ondas:
		var k: float = o.t / 0.6
		var cor_o: Color = o.cor
		cor_o.a = (1.0 - k) * 0.9
		var anel := _elipse(0, 0, raio_x * (1.0 + k * 1.6), raio_y * (1.0 + k * 1.6), 0, TAU, 40)
		anel.remove(anel.size() - 1)
		lote.linha(anel, cor_o, 5.0 * (1.0 - k) + 1.0, true)
	lote.desenhar(no)
