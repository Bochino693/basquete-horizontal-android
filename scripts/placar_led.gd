extends Control

## PLACAR DE LED de 7 segmentos, como o painel das máquinas de basquete.
## Os segmentos apagados aparecem escuros (dá a cara de painel de verdade),
## os acesos têm o miolo quase branco (o LED quente) e brilho em volta. O
## número sobe contando até o valor novo e o painel dá um "flash" a cada
## mudança.
##
## NÍTIDO E LEVE PARA A TV BOX: cada dígito é um quadrado com a textura de
## CAMPO DE DISTÂNCIA dele (imagens/d7_*.png, tools/gerar_efeitos.py); o
## shaders/display7.shader calcula por pixel a borda (1 pixel da tela), o
## miolo quente e o brilho. Mudar o número (a contagem anda a cada quadro)
## só troca a textura de cada casa: nada de geometria refeita no GDScript.
## O flash e o pisca-pisca mudam o brilho do nó (modulate).

export var digitos := 6
export var espaco_grupo := true        # "040 000": espaço a cada 3 dígitos
export var cor := Color(1.0, 0.48, 0.10) setget definir_cor
export var inclinacao := 0.10          # (os dígitos já vêm inclinados nas texturas)
export var contar := true              # anima a contagem até o valor

var valor := 0 setget definir_valor
var _exibido := 0.0
var _flash := 0.0
var _piscar := false
var _t := 0.0
var _mostrado := ""
var _casas := []
var _altura := 1.0
var _mat: ShaderMaterial
var _tex := {}


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
	if _mat != null:
		_mat.set_shader_param("cor", c)


func mostrar_direto(v: int) -> void:
	valor = v
	_exibido = v
	_mostrar()


func piscar(ligado: bool) -> void:
	_piscar = ligado
	set_process(true)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/display7.shader")
	_mat.set_shader_param("cor", cor)
	_mat.set_shader_param("apagado", 0.75)
	for ch in "0123456789":
		_tex[ch] = load("res://imagens/d7_%s.png" % ch)
	_tex[" "] = load("res://imagens/d7_vazio.png")
	connect("resized", self, "_montar")
	_montar()
	set_process(true)


## As casas dos dígitos (refeitas só se o tamanho do placar mudar).
func _montar() -> void:
	for m in _casas:
		m.queue_free()
	_casas = []
	if rect_size.x < 1.0 or rect_size.y < 1.0:
		return
	var grupos := int(ceil(digitos / 3.0)) - 1 if espaco_grupo else 0
	var larg_dig := rect_size.x / (digitos + grupos * 0.45)
	# a altura da caixa, ou menos se a casa for estreita (o dígito tem 0,56 h)
	_altura = min(rect_size.y, larg_dig * 0.84 / 0.56)
	var quad := _quadrado(_altura)
	var x := 0.0
	for i in range(digitos):
		if espaco_grupo and i > 0 and (digitos - i) % 3 == 0:
			x += larg_dig * 0.45
		var m := MeshInstance2D.new()
		m.mesh = quad
		m.material = _mat
		m.position = Vector2(x + (larg_dig - _altura * 0.56) * 0.5, (rect_size.y - _altura) * 0.5)
		add_child(m)
		_casas.append(m)
		x += larg_dig
	_ajustar_nitidez()
	_mostrado = ""
	_mostrar()


## A borda tem 1 pixel DA TELA: o shader precisa da altura do dígito em
## pixels de verdade (a janela em 720p ou 1080p). Só a escala da tela conta:
## os painéis que pulam/crescem por um instante não mudam a borda.
func _ajustar_nitidez() -> void:
	var esc := 1.0
	var vp := get_viewport()
	if vp != null:
		esc = vp.get_final_transform().get_scale().x * vp.canvas_transform.get_scale().x
	_mat.set_shader_param("altura_px", _altura * max(abs(esc), 0.05))


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


## Troca só as texturas das casas que mudaram.
func _mostrar() -> void:
	if _casas.empty():
		return
	var texto := _texto()
	if texto == _mostrado:
		return
	_mostrado = texto
	for i in range(digitos):
		_casas[i].texture = _tex.get(texto[i], _tex[" "])


## O quadrado de um dígito de altura "h": cobre o dígito inclinado e o
## brilho em volta; o UV aponta para a textura de 256 px (160 px por altura).
func _quadrado(h: float) -> ArrayMesh:
	var pts := PoolVector2Array()
	var uvs := PoolVector2Array()
	for p in [Vector2(-0.35, -0.30), Vector2(0.91, -0.30), Vector2(0.91, 1.30), Vector2(-0.35, 1.30)]:
		pts.append(p * h)
		uvs.append(Vector2((p.x - 0.28) * 160.0 / 256.0 + 0.5, (p.y - 0.5) * 160.0 / 256.0 + 0.5))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = PoolIntArray([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
