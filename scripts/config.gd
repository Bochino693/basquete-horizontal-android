extends Control

const UI = preload("res://scripts/ui.gd")

## CONFIGURAÇÃO DA MÁQUINA. Só com os botões da máquina:
##   SELECT = próximo item    START = muda o valor / executa
## Tem teste do sensor da cesta (conta os sinais ao vivo), teste dos LEDs e
## zerar ranking (pede confirmação). "SALVAR E SAIR" volta à abertura.

var itens := [
	{"chave": "tempo_fase_1", "nome": "TEMPO DA FASE 1", "opcoes": [30, 35, 40, 45, 50, 60], "fmt": "%d s"},
	{"chave": "tempo_fase_2", "nome": "TEMPO DA FASE 2", "opcoes": [25, 30, 35, 40, 45, 50], "fmt": "%d s"},
	{"chave": "tempo_fase_3", "nome": "TEMPO DA FINAL", "opcoes": [20, 25, 30, 35, 40, 45], "fmt": "%d s"},
	{"chave": "meta_fase_1", "nome": "META DA FASE 1", "opcoes": [10, 15, 20, 25, 30, 35, 40, 50, 60], "fmt": "%d pts"},
	{"chave": "meta_fase_2", "nome": "META DA FASE 2", "opcoes": [15, 20, 25, 30, 40, 50, 60, 70, 80], "fmt": "%d pts"},
	{"chave": "pontos_cesta", "nome": "PONTOS POR CESTA", "opcoes": [1, 2, 3], "fmt": "%d"},
	{"chave": "pontos_sprint", "nome": "PONTOS NOS ÚLTIMOS SEGUNDOS", "opcoes": [2, 3, 4, 5], "fmt": "%d"},
	{"chave": "segundos_sprint", "nome": "ÚLTIMOS SEGUNDOS VALENDO MAIS", "opcoes": [0, 5, 10, 15], "fmt": "%d s"},
	{"chave": "trava_sensor", "nome": "TRAVA DO SENSOR (ENTRE CESTAS)", "opcoes": [0.3, 0.4, 0.5, 0.6, 0.8, 1.0, 1.2, 1.5], "fmt": "%.1f s"},
	{"chave": "cestas_fogo", "nome": "CESTAS SEGUIDAS P/ EM CHAMAS", "opcoes": [3, 4, 5, 6, 8], "fmt": "%d"},
	{"chave": "volume_musica", "nome": "VOLUME DA MÚSICA", "opcoes": [0, 20, 40, 60, 70, 80, 100], "fmt": "%d%%"},
	{"chave": "volume_efeitos", "nome": "VOLUME DOS EFEITOS", "opcoes": [0, 20, 40, 60, 80, 100], "fmt": "%d%%"},
	{"acao": "leds", "nome": "TESTAR LEDS"},
	{"acao": "zerar", "nome": "ZERAR RANKING"},
	{"acao": "sair", "nome": "SALVAR E SAIR"},
]

const TOPO := 118
const ALTURA := 36

var _sel := 0
var _linhas := []
var _valores := []
var _destaque: Panel
var _sensor_n := 0
var _lbl_sensor: Label
var _lbl_leds: Label
var _confirmar_zerar := false
var _t := 0.0
var _saindo := false
var _barra_titulo: ColorRect


func _ready() -> void:
	var fundo = preload("res://scripts/fundo_animado.gd").new()
	fundo.imagem = "res://imagens/fundo_arena.png"
	fundo.escurecer = 0.45
	fundo.qtd_feixes = 2
	add_child(fundo)

	var titulo := UI.label("CONFIGURAÇÃO", Jogo.fonte("titan", 56, 5), Jogo.AMARELO)
	UI.colocar(titulo, 0, 14, 1280, 70)
	add_child(titulo)
	UI.pop(titulo, 0.1)
	_barra_titulo = ColorRect.new()
	UI.colocar(_barra_titulo, 440, 88, 400, 5)
	add_child(_barra_titulo)

	var lista := UI.painel(Jogo.ROXO, Color(0.04, 0.02, 0.10, 0.88), 18, 3, 16)
	UI.colocar(lista, 60, TOPO - 14, 800, ALTURA * itens.size() + 28)
	add_child(lista)
	UI.deslizar(lista, Vector2(-900, 0), 0.1)

	_destaque = UI.painel(Jogo.CIANO, Color(0.13, 0.88, 1.0, 0.18), 10, 2, 10)
	UI.colocar(_destaque, 10, 14, 780, ALTURA)
	lista.add_child(_destaque)

	var f_nome := Jogo.fonte("bungee", 19, 2)
	var f_valor := Jogo.fonte("titan", 24, 2)
	for i in range(itens.size()):
		var it: Dictionary = itens[i]
		var n := UI.label(it.nome, f_nome, Jogo.BRANCO, Label.ALIGN_LEFT)
		UI.colocar(n, 30, 14 + i * ALTURA, 520, ALTURA)
		lista.add_child(n)
		var v := UI.label("", f_valor, Jogo.AMARELO, Label.ALIGN_RIGHT)
		UI.colocar(v, 540, 14 + i * ALTURA, 230, ALTURA)
		lista.add_child(v)
		_linhas.append(n)
		_valores.append(v)
		UI.deslizar(n, Vector2(-60, 0), 0.25 + i * 0.03, 0.35)
	_atualizar_valores()

	var info := UI.painel(Jogo.LARANJA, Color(0.04, 0.02, 0.10, 0.88), 18, 3, 16)
	UI.colocar(info, 890, TOPO - 14, 340, 420)
	add_child(info)
	UI.deslizar(info, Vector2(400, 0), 0.2)
	var ajuda := UI.label("SELECT  próximo\nSTART  muda / confirma", Jogo.fonte("bungee", 18, 2), Jogo.CIANO)
	UI.colocar(ajuda, 0, 16, 340, 70)
	info.add_child(ajuda)
	var ts := UI.label("TESTE DO SENSOR", Jogo.fonte("bungee", 18, 2), Jogo.LARANJA)
	UI.colocar(ts, 0, 110, 340, 30)
	info.add_child(ts)
	_lbl_sensor = UI.label("JOGUE UMA BOLA\nNA CESTA", Jogo.fonte("titan", 30, 3), Jogo.BRANCO)
	UI.colocar(_lbl_sensor, 0, 146, 340, 110)
	info.add_child(_lbl_sensor)
	var tl := UI.label("LEDS (USB)", Jogo.fonte("bungee", 18, 2), Jogo.LARANJA)
	UI.colocar(tl, 0, 290, 340, 30)
	info.add_child(tl)
	_lbl_leds = UI.label("", Jogo.fonte("texto", 18, 1), Jogo.BRANCO)
	UI.colocar(_lbl_leds, 16, 322, 308, 80)
	info.add_child(_lbl_leds)
	_mover_destaque(false)


func _atualizar_valores() -> void:
	for i in range(itens.size()):
		var it: Dictionary = itens[i]
		var v: Label = _valores[i]
		if it.has("chave"):
			var x = Jogo.config[it.chave]
			v.text = it.fmt % x
		elif it.acao == "zerar" and _confirmar_zerar and i == _sel:
			v.text = "START DE NOVO!"
		else:
			v.text = ""


func _mover_destaque(animar := true) -> void:
	var y := 14 + _sel * ALTURA
	if animar:
		var tw := Tween.new()
		_destaque.add_child(tw)
		tw.connect("tween_all_completed", tw, "queue_free")
		tw.interpolate_property(_destaque, "rect_position:y", _destaque.rect_position.y, y, 0.18, Tween.TRANS_QUINT, Tween.EASE_OUT)
		tw.start()
	else:
		_destaque.rect_position.y = y
	for i in range(_linhas.size()):
		_linhas[i].add_color_override("font_color", Jogo.CIANO if i == _sel else Jogo.BRANCO)


func _process(delta: float) -> void:
	_t += delta
	_barra_titulo.color = Color.from_hsv(fmod(_t * 0.2, 1.0), 0.85, 1.0)
	_lbl_leds.text = Leds.status


func _input(ev: InputEvent) -> void:
	if _saindo or ev.is_echo():
		return
	if ev.is_action_pressed("input_pointer"):
		_sensor_n += 1
		_lbl_sensor.text = "SENSOR OK!\n%d SINAIS" % _sensor_n
		UI.pulsar(_lbl_sensor, 0.35)
		Jogo.tocar("swish")
	elif ev.is_action_pressed("input_select"):
		_confirmar_zerar = false
		_sel = (_sel + 1) % itens.size()
		Jogo.tocar("tique")
		_mover_destaque()
		_atualizar_valores()
	elif ev.is_action_pressed("input_start"):
		_executar()


func _executar() -> void:
	var it: Dictionary = itens[_sel]
	if it.has("chave"):
		var ops: Array = it.opcoes
		var atual = Jogo.config[it.chave]
		var idx := 0
		for i in range(ops.size()):
			if abs(float(ops[i]) - float(atual)) < 0.001:
				idx = (i + 1) % ops.size()
				break
		Jogo.config[it.chave] = ops[idx]
		Jogo.tocar("ponto", -4.0)
		UI.pulsar(_valores[_sel], 0.35)
		if it.chave.begins_with("volume"):
			Jogo.salvar_config()
	elif it.acao == "leds":
		Leds.enviar("HIT")
		Jogo.tocar("fase")
		_valores[_sel].text = "ENVIADO!"
		UI.pulsar(_valores[_sel], 0.35)
		return
	elif it.acao == "zerar":
		if _confirmar_zerar:
			Jogo.zerar_ranking()
			Jogo.tocar("alerta")
			_confirmar_zerar = false
			_atualizar_valores()
			_valores[_sel].text = "ZERADO!"
			return
		_confirmar_zerar = true
	elif it.acao == "sair":
		_saindo = true
		Jogo.salvar_config()
		Jogo.tocar("selecao")
		Jogo.ir_para("res://cenas/abertura.tscn")
		return
	_atualizar_valores()
