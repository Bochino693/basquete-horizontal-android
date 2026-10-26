extends Panel

## CARTÃO DE VIDRO (abertura): fundo escuro translúcido, um reflexo claro na
## metade de cima (como vidro), borda fina na cor e um brilho suave em
## volta. De tempos em tempos uma faixa de luz atravessa o cartão (varrer).
## O que vai dentro fica em "conteudo", que corta na borda do cartão: as
## linhas entram deslizando de fora sem aparecer fora dele (nada de texto
## meio transparente).
## Leve: dois StyleBox desenhados uma vez; por quadro só anda a faixa de luz
## (e só enquanto ela passa).

var cor := Color(0.55, 0.24, 1.0) setget definir_cor
var conteudo: Control

var _estilo: StyleBoxFlat
var _reflexo: Panel
var _janela: Control
var _faixa: Sprite
var _t := -1.0
const DURACAO_FAIXA := 0.9


func _init(c := Color(0.55, 0.24, 1.0), raio := 20) -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_estilo = StyleBoxFlat.new()
	_estilo.bg_color = Color(0.03, 0.018, 0.075, 0.84)
	_estilo.set_border_width_all(2)
	_estilo.set_corner_radius_all(raio)
	_estilo.corner_detail = 8
	_estilo.shadow_size = 18
	_estilo.anti_aliasing = true
	add_stylebox_override("panel", _estilo)
	# o reflexo do vidro: claro em cima, só os cantos de cima redondos
	_reflexo = Panel.new()
	_reflexo.mouse_filter = MOUSE_FILTER_IGNORE
	var r := StyleBoxFlat.new()
	r.bg_color = Color(1, 1, 1, 0.055)
	r.corner_radius_top_left = raio - 2
	r.corner_radius_top_right = raio - 2
	r.corner_detail = 8
	r.anti_aliasing = true
	_reflexo.add_stylebox_override("panel", r)
	add_child(_reflexo)
	conteudo = Control.new()
	conteudo.mouse_filter = MOUSE_FILTER_IGNORE
	conteudo.rect_clip_content = true
	add_child(conteudo)
	# a faixa de luz (cortada no cartão)
	_janela = Control.new()
	_janela.mouse_filter = MOUSE_FILTER_IGNORE
	_janela.rect_clip_content = true
	add_child(_janela)
	_faixa = Sprite.new()
	_faixa.texture = load("res://imagens/brilho.png")
	var aditivo := CanvasItemMaterial.new()
	aditivo.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_faixa.material = aditivo
	_faixa.rotation_degrees = 22
	_faixa.visible = false
	_janela.add_child(_faixa)
	definir_cor(c)
	connect("resized", self, "_ajustar")
	set_process(false)


func definir_cor(c: Color) -> void:
	cor = c
	if _estilo == null:
		return
	_estilo.border_color = Color(c.r, c.g, c.b, 0.95)
	_estilo.shadow_color = Color(c.r, c.g, c.b, 0.30)


func _ajustar() -> void:
	_reflexo.rect_position = Vector2(2, 2)
	_reflexo.rect_size = Vector2(rect_size.x - 4, rect_size.y * 0.42)
	conteudo.rect_size = rect_size
	_janela.rect_position = Vector2(2, 2)
	_janela.rect_size = rect_size - Vector2(4, 4)
	# (brilho.png tem 256 px: faixa fina e mais alta que o cartão)
	_faixa.scale = Vector2(0.34, rect_size.y * 1.5 / 256.0)


## Uma faixa de luz atravessa o cartão.
func varrer() -> void:
	_t = 0.0
	_faixa.visible = true
	set_process(true)
	_process(0.0)


func _process(delta: float) -> void:
	_t += delta
	var k := _t / DURACAO_FAIXA
	if k >= 1.0:
		_faixa.visible = false
		set_process(false)
		return
	var e := k * k * (3.0 - 2.0 * k)
	_faixa.position = Vector2(lerp(-90.0, rect_size.x + 90.0, e), rect_size.y * 0.5)
	_faixa.modulate = Color(1, 1, 1, 0.20 * sin(k * PI))
