extends Node2D

## O ARREMESSO EM PERSPECTIVA (a marca do Swish Arena): a cada cesta, a bola
## GRANDE sai da frente da tela (de onde o jogador arremessa), sobe num arco
## e vai diminuindo até o aro (perspectiva: longe = pequena), girando, com o
## rastro de luz da cor do momento (laranja; ouro nos últimos segundos; FOGO
## no EM CHAMAS). No aro ela entra na cesta (cesta.anotar, de onde chegou) e
## a rede faz o SWISH.
##
## Leve para a TV Box: 3 voos prontos, reaproveitados (nada é criado durante
## a partida); por quadro só mudam posição, tamanho e brilho. A bola é a
## bola desenhada (bola3d): nítida do tamanho da tela ao tamanho do aro.

const Bola3D = preload("res://scripts/bola3d.gd")
const DURACAO := 0.72
const ESCALA_FRENTE := 4.2        # tamanho na frente da tela (x o tamanho no aro)
const SOBE := 620.0               # quanto o arco sobe (controle da curva)

enum { NORMAL, OURO, FOGO }

var cesta: Node2D                 # o aro (partida.gd liga)
var altura_tela := 720.0
var _voos := []


func _ready() -> void:
	var aditivo := CanvasItemMaterial.new()
	aditivo.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var tex_brilho := load("res://imagens/brilho.png")
	var tex_rastro := load("res://imagens/rastro.png")
	for i in 3:
		var v := {"ativo": false, "t": 0.0}
		var rastro := Sprite.new()
		rastro.texture = tex_rastro
		rastro.material = aditivo
		rastro.offset = Vector2(0, tex_rastro.get_height() * 0.5)
		rastro.visible = false
		add_child(rastro)
		v.rastro = rastro
		var fogo := CPUParticles2D.new()
		fogo.texture = tex_brilho
		fogo.material = aditivo
		fogo.local_coords = false
		fogo.amount = 34
		fogo.lifetime = 0.42
		fogo.direction = Vector2(0, -1)
		fogo.spread = 40
		fogo.gravity = Vector2(0, -320)
		fogo.initial_velocity = 60
		fogo.initial_velocity_random = 0.6
		fogo.scale_amount = 0.3
		fogo.scale_amount_random = 0.5
		var rampa := Gradient.new()
		rampa.set_color(0, Color(1, 0.95, 0.55, 0.9))
		rampa.set_color(1, Color(0.8, 0.05, 0.05, 0.0))
		rampa.add_point(0.35, Color(1, 0.5, 0.08, 0.8))
		fogo.color_ramp = rampa
		fogo.emitting = false
		add_child(fogo)
		v.fogo = fogo
		var halo := Sprite.new()
		halo.texture = tex_brilho
		halo.material = aditivo
		halo.visible = false
		add_child(halo)
		v.halo = halo
		var bola = Bola3D.new()
		bola.velocidade = 15.0
		bola.visible = false
		bola.set_process(false)
		add_child(bola)
		v.bola = bola
		_voos.append(v)
	set_process(false)


## Lança a bola da frente da tela até o aro. tipo: NORMAL, OURO, FOGO.
func lancar(cor: Color, tipo := NORMAL) -> void:
	var v: Dictionary = _voos[0]
	for w in _voos:
		if not w.ativo:
			v = w
			break
		if w.t > v.t:
			v = w
	var aro: Vector2 = cesta.position
	var raio_x: float = cesta.raio_x
	v.xe = rand_range(-0.3, 0.3) * raio_x
	v.p2 = aro + Vector2(v.xe, -46)
	var x0 := aro.x + rand_range(-250.0, 250.0)
	v.p0 = Vector2(x0, altura_tela + 150.0)
	v.p1 = Vector2(lerp(x0, v.p2.x, 0.55) + rand_range(-80.0, 80.0), aro.y - SOBE + rand_range(-50.0, 50.0))
	v.d_bola = raio_x * 1.18
	v.t = 0.0
	v.cor = cor
	v.tipo = tipo
	v.ativo = true
	var bola = v.bola
	bola.visible = true
	bola.set_process(true)
	bola.ouro(1.0 if tipo == OURO else 0.0)
	bola.rotation = randf() * TAU
	v.rastro.visible = true
	v.halo.visible = true
	v.fogo.emitting = tipo == FOGO
	set_process(true)
	_mover(v, 0.0)


func _process(delta: float) -> void:
	var algum := false
	for v in _voos:
		if not v.ativo:
			continue
		algum = true
		v.t += delta
		var u: float = v.t / DURACAO
		if u >= 1.0:
			_chegar(v)
		else:
			_mover(v, u)
	if not algum:
		set_process(false)


func _mover(v: Dictionary, u: float) -> void:
	var a := 1.0 - u
	var p: Vector2 = v.p0 * a * a + v.p1 * 2.0 * a * u + v.p2 * u * u
	var dp: Vector2 = (v.p1 - v.p0) * 2.0 * a + (v.p2 - v.p1) * 2.0 * u
	# perspectiva: a distância cresce reto, o tamanho cai como 1 / distância
	var s: float = 1.0 / lerp(1.0 / ESCALA_FRENTE, 1.0, u)
	var px: float = v.d_bola * s
	var bola = v.bola
	bola.position = p
	bola.tamanho(px)
	bola.rotation += 0.05
	var cor: Color = v.cor
	var entra := clamp(u * 8.0, 0.0, 1.0)
	# rastro: o cone de luz atrás da bola, do tamanho da velocidade
	var vel := dp.length() / DURACAO
	var rastro: Sprite = v.rastro
	if vel > 1.0:
		var d := dp / dp.length()
		rastro.rotation = atan2(d.x, -d.y)
	rastro.position = p
	var comp := clamp(vel * 0.11, px * 0.8, px * 3.2)
	rastro.scale = Vector2(px * 0.95 / 64.0, comp / 256.0)
	rastro.modulate = Color(min(cor.r * 1.3, 1.0), min(cor.g * 1.3, 1.0), min(cor.b * 1.3 + 0.1, 1.0), entra)
	var halo: Sprite = v.halo
	halo.position = p
	halo.scale = Vector2.ONE * px * 2.1 / 256.0
	halo.modulate = Color(cor.r, cor.g, cor.b, 0.32 * entra)
	var fogo: CPUParticles2D = v.fogo
	fogo.position = p
	fogo.scale_amount = 0.16 * s
	fogo.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	fogo.emission_sphere_radius = px * 0.35


func _chegar(v: Dictionary) -> void:
	v.ativo = false
	v.bola.visible = false
	v.bola.set_process(false)
	v.rastro.visible = false
	v.halo.visible = false
	v.fogo.emitting = false
	cesta.anotar(v.cor, Vector2(v.xe, -46))
