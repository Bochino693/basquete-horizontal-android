extends Node2D

## FOGOS DE ARTIFÍCIO (meta batida, recorde batido na partida, EM CHAMAS):
## estouros de faíscas coloridas com um clarão no meio, em pontos da parte
## de cima da arena, um depois do outro. Estouros prontos, reaproveitados.

var _estouros := []
var _prox := 0


func _ready() -> void:
	var aditivo := CanvasItemMaterial.new()
	aditivo.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var tex_faisca := load("res://imagens/faisca.png")
	var tex_brilho := load("res://imagens/brilho.png")
	for i in 6:
		var p := CPUParticles2D.new()
		p.texture = tex_faisca
		p.material = aditivo
		p.amount = 46
		p.one_shot = true
		p.explosiveness = 0.95
		p.lifetime = 1.25
		p.emitting = false
		p.direction = Vector2(0, -1)
		p.spread = 180
		p.initial_velocity = 290
		p.initial_velocity_random = 0.35
		p.gravity = Vector2(0, 230)
		p.damping = 70
		p.scale_amount = 0.55
		p.scale_amount_random = 0.4
		var rampa := Gradient.new()
		rampa.set_color(0, Color(1, 1, 1, 1))
		rampa.set_color(1, Color(1, 1, 1, 0))
		rampa.add_point(0.25, Color(1, 0.8, 0.3, 1))
		p.color_ramp = rampa
		add_child(p)
		var clarao := Sprite.new()
		clarao.texture = tex_brilho
		clarao.material = aditivo
		clarao.visible = false
		add_child(clarao)
		_estouros.append({"p": p, "clarao": clarao, "t": 9.0})
	set_process(false)


## "n" estouros nas cores dadas, dentro da área (um depois do outro).
func soltar(n: int, cores: Array, area := Rect2(160, 60, 960, 260)) -> void:
	for k in n:
		var pos := area.position + Vector2(randf() * area.size.x, randf() * area.size.y)
		var cor: Color = cores[k % cores.size()]
		if k == 0:
			_estourar(pos, cor)
		else:
			get_tree().create_timer(k * 0.22).connect("timeout", self, "_estourar", [pos, cor])


func _estourar(pos: Vector2, cor: Color) -> void:
	var e: Dictionary = _estouros[_prox]
	_prox = (_prox + 1) % _estouros.size()
	var p: CPUParticles2D = e.p
	p.position = pos
	# a cor do estouro: começa claro (não branco puro: as faíscas juntas no
	# primeiro instante somam luz e virariam uma mancha branca), o meio do
	# caminho na cor, o fim sumindo nela
	var rampa: Gradient = p.color_ramp
	for i in rampa.get_point_count():
		var o := rampa.get_offset(i)
		if o > 0.99:
			rampa.set_color(i, Color(cor.r, cor.g, cor.b, 0.0))
		elif o > 0.01:
			rampa.set_color(i, cor.linear_interpolate(Color(1, 1, 1), 0.3))
		else:
			var claro := cor.linear_interpolate(Color(1, 1, 1), 0.55)
			rampa.set_color(i, Color(claro.r, claro.g, claro.b, 0.7))
	p.restart()
	var c: Sprite = e.clarao
	c.position = pos
	c.modulate = Color(cor.r, cor.g, cor.b, 0.6)
	c.visible = true
	e.t = 0.0
	Jogo.tocar("fogos", -5.0, rand_range(0.9, 1.15))
	set_process(true)


func _process(delta: float) -> void:
	var algum := false
	for e in _estouros:
		var c: Sprite = e.clarao
		if not c.visible:
			continue
		e.t += delta
		var k: float = e.t / 0.35
		if k >= 1.0:
			c.visible = false
			continue
		algum = true
		c.scale = Vector2.ONE * lerp(0.4, 1.4, k)
		c.modulate.a = (1.0 - k) * 0.6
	if not algum:
		set_process(false)
