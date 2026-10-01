extends Node2D

## LETREIRO DE LED DA ARENA (a faixa atrás da tabela): SWISH ARENA, SHOW YOUR
## GAME e LAZER & SPORT GAMES correndo da direita para a esquerda, um LED por
## vez como os letreiros de verdade. O texto passa por TRÁS da tabela de vidro
## (some de um lado e reaparece do outro), então nunca fica letra por cima de
## letra. A faixa já vem desenhada em alta definição (imagens/letreiro.png e
## a _720 para TV em 720p, feitas por tools/gerar_arena.py); aqui só muda o
## pedaço mostrado: quase nada de CPU e de GPU.
## Fica no espaço da arte 1920x1080 (o fundo_animado acerta posição/escala).

const PASSO_ARTE := 6.0                  # um LED na arte 1920x1080
const Y_FAIXA := 730.0                   # topo da faixa escura na arte
# janelas visíveis (x na arte, múltiplos do LED): entre as lâmpadas das
# laterais e a tabela, dos dois lados
const JANELAS := [[76.0, 628.0], [1294.0, 1846.0]]

var velocidade := 24.0                   # LEDs por segundo
var _tex: Texture
var _passo_tex := 6.0
var _sprites := []
var _andado := 0.0
var _coluna := -1


func _ready() -> void:
	var arq := "res://imagens/letreiro.png"
	if OS.window_size.y < 900 and ResourceLoader.exists("res://imagens/letreiro_720.png"):
		arq = "res://imagens/letreiro_720.png"
		_passo_tex = 4.0
	_tex = load(arq)
	var k := PASSO_ARTE / _passo_tex          # pixels da arte por pixel da faixa
	for j in JANELAS:
		var s := Sprite.new()
		s.texture = _tex
		s.centered = false
		s.region_enabled = true
		s.position = Vector2(j[0], Y_FAIXA)
		s.scale = Vector2(k, k)
		add_child(s)
		_sprites.append([s, j[0], j[1]])
	_mostrar(0)


func _process(delta: float) -> void:
	var colunas := _tex.get_width() / _passo_tex
	_andado = fmod(_andado + delta * velocidade, colunas)
	var c := int(_andado)
	if c != _coluna:
		_mostrar(c)


func _mostrar(c: int) -> void:
	_coluna = c
	var colunas := int(_tex.get_width() / _passo_tex)
	for it in _sprites:
		var s: Sprite = it[0]
		var x0: float = it[1]
		var x1: float = it[2]
		# a coluna que aparece na borda esquerda desta janela: a faixa é uma
		# só, passando por trás da tabela de uma janela para a outra
		var inicio := (c + int((x0 - JANELAS[0][0]) / PASSO_ARTE)) % colunas
		var largura := (x1 - x0) / PASSO_ARTE * _passo_tex
		s.region_rect = Rect2(inicio * _passo_tex, 0, largura, _tex.get_height())
