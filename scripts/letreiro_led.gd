extends Node2D

## LETREIRO DA ARENA (a faixa atrás da tabela): SWISH ARENA, SHOW YOUR GAME
## e LAZER & SPORT GAMES correndo da direita para a esquerda em letras de
## NEON LISAS (fonte de verdade, com o brilho da cor em volta - nada de
## pontinhos, nada quadriculado), andando liso. O texto passa por TRÁS da
## tabela de vidro (some de um lado e reaparece do outro), então nunca fica
## letra por cima de letra.
## As letras são desenhadas no tamanho certo da tela (a fonte é feita para
## os pixels de verdade, sem ampliar). Fica no espaço da arte 1920x1080 (o
## fundo_animado acerta posição/escala); quase nada de CPU: por quadro só
## andam duas tiras.

const Y_FAIXA := 730.0                   # a faixa escura na arte (730..776)
const ALTURA_FAIXA := 46.0
const ALTURA_LETRA := 28.0               # na arte (1080 linhas)
# janelas visíveis (x na arte): entre as lâmpadas das laterais e a tabela,
# dos dois lados
const JANELAS := [[76.0, 628.0], [1294.0, 1846.0]]
const FRASES := [
	["SWISH ARENA", Color(1.0, 0.63, 0.16)],
	["SHOW YOUR GAME", Color(0.78, 0.47, 1.0)],
	["LAZER & SPORT GAMES", Color(0.16, 0.86, 1.0)],
]
const COR_PONTO := Color(1.0, 0.9, 0.59)
const VOLTA := 1830.0                    # uma volta das frases (px da arte)

var velocidade := 24.0                   # (o ritmo de antes: x 6 px da arte por segundo)
var _k := -1.0                           # a escala em que as tiras foram montadas
var _tiras := []                         # [janela x0, nó da tira] (cada tira com 2 cópias)
var _comprimento := 1.0                  # uma volta das frases (unidades da tira)
var _andado := 0.0


func _process(delta: float) -> void:
	if abs(scale.x - _k) > 0.0001:
		_montar(scale.x)
	_andado = fmod(_andado + delta * velocidade * 6.0 * _k, _comprimento)
	for t in _tiras:
		var x0: float = t[0]
		var tira: Node2D = t[1]
		# a mesma faixa para as duas janelas (some atrás da tabela de uma e
		# volta na outra): começa na borda direita da janela da direita
		var inicio: float = (JANELAS[1][1] - x0) * _k - _andado
		tira.position.x = (fposmod(inicio, _comprimento) - _comprimento) / _k


## As duas janelas com a tira das frases (duas cópias em fila). Dentro de
## cada tira as unidades são as da tela do jogo (a fonte nasce no tamanho
## em que aparece).
func _montar(k: float) -> void:
	_k = max(k, 0.05)
	for c in get_children():
		c.queue_free()
	_tiras = []
	var tam := int(round(ALTURA_LETRA * _k))
	var contorno := int(max(2, round(5.0 * _k)))
	# uma volta das frases com ~1830 px da arte (como a faixa de antes): as
	# duas janelas (1218 px uma da outra) mostram frases diferentes
	var soma := 0.0
	for fr in FRASES:
		for t in [fr[0], "•"]:
			soma += Jogo.fonte("bungee", tam, contorno).get_string_size(t).x
	var espaco: float = max(30.0 * _k, (VOLTA * _k - soma) / (FRASES.size() * 2))
	for j in JANELAS:
		var janela := Control.new()
		janela.mouse_filter = Control.MOUSE_FILTER_IGNORE
		janela.rect_clip_content = true
		janela.rect_position = Vector2(j[0], Y_FAIXA)
		janela.rect_size = Vector2(j[1] - j[0], ALTURA_FAIXA)
		add_child(janela)
		var tira := Node2D.new()
		tira.scale = Vector2.ONE / _k
		janela.add_child(tira)
		var x := 0.0
		for copia in 2:
			for fr in FRASES:
				for parte in [[fr[0], fr[1]], ["•", COR_PONTO]]:
					var cor: Color = parte[1]
					var f: Font = Jogo.fonte("bungee", tam, contorno, Color(cor.r * 0.8, cor.g * 0.8, cor.b * 0.8, 0.38))
					var l := Label.new()
					l.text = parte[0]
					l.add_font_override("font", f)
					l.add_color_override("font_color", cor.lightened(0.18))
					l.mouse_filter = Control.MOUSE_FILTER_IGNORE
					var w: float = f.get_string_size(l.text).x
					l.rect_position = Vector2(x, (ALTURA_FAIXA * _k - f.get_height()) * 0.5)
					tira.add_child(l)
					x += w + espaco
			if copia == 0:
				_comprimento = x
		_tiras.append([j[0], tira])
