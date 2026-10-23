extends Node2D

## A CESTA NA TELA: aro neon e rede desenhados por código, bola caindo pelo
## aro a cada ponto, rede esticando (mola), faíscas, onda de choque e fogo
## no modo EM CHAMAS. A origem deste nó é o centro do aro.
##
## LEVE PARA A TV BOX: aro e rede são desenhados UMA vez. A cor do aro muda
## pelo modulate do nó; o balanço e a esticada da rede são feitos pela placa
## de vídeo (shader rede_mola). As bolas, as ondas de choque e a explosão de
## raios são peças prontas, reaproveitadas (nada é criado nem redesenhado
## durante a partida).
##
## A bola que cai é a bola desenhada (bola3d, a mesma do arremesso): quando
## ela vem do ARREMESSO (arremesso.gd), entra no aro de onde chegou.

signal swish(cor)                   # a bola passou pelo aro (rede, ondas, raios)

export var raio_x := 96.0
export var raio_y := 15.0
export var altura_rede := 104.0

var em_chamas := false setget _set_chamas

var _atras: Node2D
var _rede: Node2D
var _aro: Node2D
var _aro_brilho: Node2D
var _raios: Sprite
var _raios_t := 9.0
var _raios_giro := 0.0
var _mat_rede: ShaderMaterial
var _bolas: Node2D
var _faiscas: CPUParticles2D
var _estrelas: CPUParticles2D
var _fogo: CPUParticles2D
var _halo: Sprite
var _t := 0.0
var _estica := 0.0        # rede esticada (mola)
var _estica_vel := 0.0
var _ondas := []          # ondas de choque: sprites prontos [{no, t}]
var _onda_prox := 0
var _pool_bolas := []
var _bola_prox := 0
const TracoSuave = preload("res://scripts/traco_suave.gd")
const Bola3D = preload("res://scripts/bola3d.gd")
var _lote_atras = TracoSuave.new()
var _lote_rede = TracoSuave.new()
var _lote_aro = TracoSuave.new()
var _lote_aro_brilho = TracoSuave.new()


func _ready() -> void:
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
	for i in 3:
		var b = Bola3D.new()
		b.tamanho(raio_x * 1.18)
		b.velocidade = 9.0
		b.visible = false
		b.set_process(false)
		_bolas.add_child(b)
		_pool_bolas.append(b)
	_rede = _camada("_desenhar_rede")
	_mat_rede = ShaderMaterial.new()
	_mat_rede.shader = load("res://shaders/rede_mola.shader")
	_mat_rede.set_shader_param("altura", altura_rede)
	_mat_rede.set_shader_param("topo", raio_y)
	_rede.material = _mat_rede
	_aro = _camada("_desenhar_aro")
	_aro_brilho = _camada("_desenhar_aro_brilho")
	# ondas de choque (elipses que crescem) e a explosão de raios: prontas
	var tex_anel := load("res://imagens/anel_onda.png")
	for i in 4:
		var o := Sprite.new()
		o.texture = tex_anel
		o.material = aditivo
		o.visible = false
		add_child(o)
		_ondas.append({"no": o, "t": 9.0})
	_raios = Sprite.new()
	_raios.texture = load("res://imagens/raios.png")
	_raios.material = aditivo
	_raios.position = Vector2(0, -6)
	_raios.visible = false
	add_child(_raios)

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
## "entrada" (local ao aro): de onde a bola do ARREMESSO chega; sem ela, a
## bola cai de cima (apresentação).
func anotar(cor: Color = Color(1.0, 0.6, 0.15), entrada = null) -> void:
	var b = _pool_bolas[_bola_prox]
	_bola_prox = (_bola_prox + 1) % _pool_bolas.size()
	b.visible = true
	b.set_process(true)
	b.modulate.a = 1.0
	b.rotation = randf() * TAU
	var tw := create_tween()
	var queda := Vector2(0, altura_rede + 80)
	if entrada == null:
		var x0 := rand_range(-raio_x * 0.45, raio_x * 0.45)
		b.position = Vector2(x0, -300)
		# desce acelerando até o aro, passa pela rede e some embaixo
		tw.tween_property(b, "position", Vector2(x0 * 0.3, 0), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(self, "_passou_no_aro", [cor])
	else:
		var e: Vector2 = entrada
		b.position = e
		tw.tween_property(b, "position", Vector2(e.x * 0.3, 0), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(self, "_passou_no_aro", [cor])
	tw.tween_property(b, "position", queda, 0.30)
	tw.parallel().tween_property(b, "modulate:a", 0.0, 0.14).set_delay(0.18)
	tw.tween_callback(self, "_guardar_bola", [b])


func _guardar_bola(b) -> void:
	b.visible = false
	b.set_process(false)


func _passou_no_aro(cor: Color) -> void:
	_estica_vel = 9.0
	var o: Dictionary = _ondas[_onda_prox]
	_onda_prox = (_onda_prox + 1) % _ondas.size()
	o.t = 0.0
	o.no.visible = true
	o.no.modulate = cor
	var rampa: Gradient = _faiscas.color_ramp
	rampa.set_offset(1, 1.0)
	rampa.set_color(1, Color(cor.r, cor.g, cor.b, 0.0))
	_faiscas.restart()
	_estrelas.restart()
	# explosão de raios de luz no aro (o "SWISH!")
	_raios_t = 0.0
	_raios_giro = rand_range(-0.5, 0.5)
	_raios.visible = true
	_raios.modulate = cor.linear_interpolate(Color(1, 1, 1), 0.45)
	emit_signal("swish", cor)


func _process(delta: float) -> void:
	_t += delta
	# mola da rede
	_estica_vel += (-_estica * 60.0 - _estica_vel * 7.0) * delta
	_estica += _estica_vel * delta
	# ondas de choque: elipses do aro crescendo e sumindo (só sprites)
	for o in _ondas:
		if not o.no.visible:
			continue
		o.t += delta
		var k: float = o.t / 0.6
		if k >= 1.0:
			o.no.visible = false
			continue
		var cresce := 1.0 + k * 1.6
		o.no.scale = Vector2(raio_x * cresce / 110.0, raio_y * cresce / 110.0)
		o.no.modulate.a = (1.0 - k) * 0.95
	if _raios.visible:
		_raios_t += delta
		var kr := _raios_t / 0.5
		if kr >= 1.0:
			_raios.visible = false
		else:
			var s: float = lerp(0.5, 2.3, 1.0 - pow(1.0 - kr, 3.0))
			_raios.scale = Vector2(s * 1.25, s * 0.85)
			_raios.rotation = _raios_giro * kr
			_raios.modulate.a = (1.0 - kr) * (1.0 - kr)
	var pulso := 0.30 + sin(_t * 3.0) * 0.08
	_halo.modulate = Color(1.0, 0.25, 0.05, pulso + 0.25) if em_chamas else Color(1.0, 0.45, 0.1, pulso)
	var c := _cor_aro()
	_atras.modulate = c
	_aro.modulate = c
	# a rede balança e estica na placa de vídeo: só 2 números por quadro
	_mat_rede.set_shader_param("estica", _estica)
	_mat_rede.set_shader_param("balanco", sin(_t * 2.2) * 3.0)


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
