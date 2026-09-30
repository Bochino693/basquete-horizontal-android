extends Node

## O "cérebro" do Swish Arena (autoload Jogo): configuração da máquina,
## recorde e ranking salvos na TV Box, fontes, sons e troca de tela.

const CAMINHO_CONFIG := "user://swish_config.cfg"
const CAMINHO_RANKING := "user://swish_ranking.json"
const TAMANHO_RANKING := 10

## Cores vivas do jogo (as mesmas da arte SWISH ARENA).
const LARANJA := Color(1.0, 0.48, 0.10)
const AMARELO := Color(1.0, 0.84, 0.12)
const ROSA := Color(1.0, 0.18, 0.55)
const ROXO := Color(0.55, 0.24, 1.0)
const CIANO := Color(0.13, 0.88, 1.0)
const VERDE := Color(0.22, 1.0, 0.42)
const VERMELHO := Color(1.0, 0.16, 0.16)
const BRANCO := Color(1, 1, 1)
const FUNDO := Color(0.03, 0.02, 0.08)

## Configuração padrão (a tela de configuração muda e salva).
var config := {
	"tempo_fase_1": 40,
	"tempo_fase_2": 35,
	"tempo_fase_3": 30,
	"meta_fase_1": 30,
	"meta_fase_2": 40,
	"pontos_cesta": 2,
	"pontos_sprint": 3,
	"segundos_sprint": 10,
	"trava_sensor": 1.2,
	"cestas_fogo": 4,
	"janela_fogo": 3.0,
	"duracao_fogo": 8.0,
	"volume_musica": 70,
	"volume_efeitos": 100,
}

var ranking := []   # [{pontos, fase, cestas, data}], do maior para o menor

var _fontes := {}
var _sons := {}
var _canais := []
var _proximo_canal := 0
var _musica: AudioStreamPlayer
var _musica_nome := ""
var _tween: Tween
var _cortina: ColorRect
var _trocando := false


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	randomize()
	_carregar_config()
	_carregar_ranking()
	for _i in range(10):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_canais.append(p)
	_musica = AudioStreamPlayer.new()
	add_child(_musica)
	_tween = Tween.new()
	add_child(_tween)
	var camada := CanvasLayer.new()
	camada.layer = 120
	add_child(camada)
	_cortina = ColorRect.new()
	_cortina.color = FUNDO
	_cortina.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cortina.anchor_right = 1
	_cortina.anchor_bottom = 1
	_cortina.modulate.a = 0
	camada.add_child(_cortina)
	# Pré-carrega os efeitos: tocar um som nunca espera o disco.
	var d := Directory.new()
	if d.open("res://sons") == OK:
		d.list_dir_begin(true, true)
		var f := d.get_next()
		while f != "":
			var nome := f.replace(".import", "")
			if nome.ends_with(".wav") and not _sons.has(nome.get_basename()):
				_sons[nome.get_basename()] = load("res://sons/" + nome)
			f = d.get_next()


# --------------------------------------------------------------- config
func valor(chave: String):
	return config[chave]


func _carregar_config() -> void:
	var c := ConfigFile.new()
	if c.load(CAMINHO_CONFIG) != OK:
		return
	for k in config.keys():
		config[k] = c.get_value("jogo", k, config[k])


func salvar_config() -> void:
	var c := ConfigFile.new()
	for k in config.keys():
		c.set_value("jogo", k, config[k])
	c.save(CAMINHO_CONFIG)
	aplicar_volumes()


## Fases da partida: [{tempo, meta}] (a última não tem meta: é a final).
func fases() -> Array:
	return [
		{"tempo": int(config.tempo_fase_1), "meta": int(config.meta_fase_1)},
		{"tempo": int(config.tempo_fase_2), "meta": int(config.meta_fase_2)},
		{"tempo": int(config.tempo_fase_3), "meta": 0},
	]


# -------------------------------------------------------------- ranking
func _carregar_ranking() -> void:
	var f := File.new()
	if not f.file_exists(CAMINHO_RANKING) or f.open(CAMINHO_RANKING, File.READ) != OK:
		return
	var r := JSON.parse(f.get_as_text())
	f.close()
	if r.error == OK and r.result is Array:
		ranking = r.result


func recorde() -> int:
	return int(ranking[0].pontos) if ranking.size() > 0 else 0


## Registra a partida. Retorna a posição no ranking (1 = recorde) ou 0.
func registrar_partida(pontos: int, fase: int, cestas: int) -> int:
	if pontos <= 0:
		return 0
	var d := OS.get_datetime()
	var item := {"pontos": pontos, "fase": fase, "cestas": cestas,
		"data": "%02d/%02d" % [d.day, d.month]}
	var pos := ranking.size()
	for i in range(ranking.size()):
		if pontos > int(ranking[i].pontos):
			pos = i
			break
	if pos >= TAMANHO_RANKING:
		return 0
	ranking.insert(pos, item)
	while ranking.size() > TAMANHO_RANKING:
		ranking.pop_back()
	var f := File.new()
	if f.open(CAMINHO_RANKING, File.WRITE) == OK:
		f.store_string(JSON.print(ranking))
		f.close()
	return pos + 1


func zerar_ranking() -> void:
	ranking.clear()
	var d := Directory.new()
	if d.file_exists(CAMINHO_RANKING):
		d.remove(CAMINHO_RANKING)


# --------------------------------------------------------------- fontes
## Fonte em cache. nome: "titan" (títulos), "bungee" (painéis), "texto".
func fonte(nome: String, tamanho: int, contorno: int = 0, cor_contorno: Color = Color(0, 0, 0, 0.85)) -> DynamicFont:
	var chave := "%s_%d_%d_%s" % [nome, tamanho, contorno, cor_contorno.to_html()]
	if _fontes.has(chave):
		return _fontes[chave]
	var f := DynamicFont.new()
	var arquivos := {"titan": "res://fontes/titan.ttf", "bungee": "res://fontes/bungee.ttf", "texto": "res://fontes/opensans.ttf"}
	f.font_data = load(arquivos.get(nome, arquivos.texto))
	if nome != "texto":
		f.add_fallback(load(arquivos.texto))
	f.size = tamanho
	f.use_filter = true
	f.use_mipmaps = false
	if contorno > 0:
		f.outline_size = contorno
		f.outline_color = cor_contorno
	_fontes[chave] = f
	return f


## Desenha as letras de uma fonte antes de aparecerem (no Android, a
## primeira vez de cada letra grande custa um tempinho).
func preaquecer(f: Font, texto: String) -> void:
	f.get_string_size(texto)


# ----------------------------------------------------------------- sons
func tocar(nome: String, volume_db: float = 0.0, tom: float = 1.0) -> void:
	if not _sons.has(nome):
		return
	var p: AudioStreamPlayer = _canais[_proximo_canal]
	_proximo_canal = (_proximo_canal + 1) % _canais.size()
	p.stream = _sons[nome]
	p.volume_db = volume_db + _db(config.volume_efeitos)
	p.pitch_scale = tom
	p.play()


func musica(nome: String, volume_db: float = 0.0) -> void:
	if nome == _musica_nome and _musica.playing:
		return
	_musica_nome = nome
	var st: AudioStream = load("res://musicas/%s.ogg" % nome)
	if st is AudioStreamOGGVorbis:
		st.loop = true
	_musica.stream = st
	_musica.volume_db = -40.0
	_musica.play()
	_tween.interpolate_property(_musica, "volume_db", -40.0, volume_db + _db(config.volume_musica), 0.8, Tween.TRANS_SINE, Tween.EASE_OUT)
	_tween.start()


func parar_musica(tempo: float = 0.6) -> void:
	_musica_nome = ""
	_tween.interpolate_property(_musica, "volume_db", _musica.volume_db, -50.0, tempo)
	_tween.interpolate_callback(_musica, tempo, "stop")
	_tween.start()


func aplicar_volumes() -> void:
	if _musica.playing:
		_musica.volume_db = _db(config.volume_musica)


func _db(porcento) -> float:
	var p := clamp(float(porcento) / 100.0, 0.0, 1.0)
	return -80.0 if p <= 0.001 else linear2db(p)


# ---------------------------------------------------------- troca de tela
## Escurece, troca a cena por baixo e clareia de novo.
func ir_para(cena: String) -> void:
	if _trocando:
		return
	_trocando = true
	_tween.interpolate_property(_cortina, "modulate:a", _cortina.modulate.a, 1.0, 0.28, Tween.TRANS_SINE, Tween.EASE_IN)
	_tween.start()
	yield(_tween, "tween_all_completed")
	get_tree().change_scene(cena)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	_tween.interpolate_property(_cortina, "modulate:a", 1.0, 0.0, 0.45, Tween.TRANS_SINE, Tween.EASE_OUT)
	_tween.start()
	_trocando = false


func trocando() -> bool:
	return _trocando
