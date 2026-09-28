extends Node
# =====================================================================
# REDE — MULTIPLAYER LAN (SWISH ARENA / SLAM ARENA)
# Autoload responsável por toda a comunicação em rede entre as
# TV Boxes/PCs. Cada máquina física = 1 estação = 1 jogador jogando
# AO MESMO TEMPO (simultâneo, diferente do modo por turnos que já
# existe hoje em play.gd).
#
# ARQUITETURA: Host-Cliente com o multiplayer de alto nível da Godot
# (ENetMultiplayerPeer). A máquina que aperta "HOSPEDAR" vira o
# servidor E também joga (é o Jogador 1). As demais entram digitando
# o IP do host e viram os outros jogadores (2, 3, 4...).
#
# TOPOLOGIA IMPORTANTE: um CLIENTE só enxerga o HOST na rede (nunca
# outro cliente direto). Por isso, quando um cliente marca ponto, a
# mensagem vai primeiro pro host, e o HOST é quem retransmite pra
# todo mundo.
#
# ESTE ARQUIVO NÃO TEM NENHUMA UI (Button/Label/Control). Ele é só
# lógica de rede. A tela fica em network_lobby.gd (extends Control).
# =====================================================================

signal peer_conectado(id_peer: int, indice_jogador: int)
signal peer_desconectado(id_peer: int, indice_jogador: int)
signal lista_jogadores_atualizada(jogadores: Dictionary)
signal todos_prontos()
signal comeca_partida(duracao_segundos: float)
signal ponto_remoto_marcado(indice_jogador: int, total: int)
signal partida_remota_encerrada(indice_jogador: int, total_final: int)
signal falha_conexao(motivo: String)
signal desconectado_do_host()

const PORTA_PADRAO := 7777
const MAX_JOGADORES := 4

var peer: ENetMultiplayerPeer = null
var sou_host: bool = false
var conectado: bool = false

var jogadores: Dictionary = {}

var meu_indice_jogador: int = -1
var meu_nome_jogador: String = "JOGADOR"


func _ready() -> void:
	multiplayer.peer_connected.connect(_ao_peer_conectar)
	multiplayer.peer_disconnected.connect(_ao_peer_desconectar)
	multiplayer.connected_to_server.connect(_ao_conectar_no_host)
	multiplayer.connection_failed.connect(_ao_falhar_conexao)
	multiplayer.server_disconnected.connect(_ao_host_cair)


func hospedar(nome_jogador: String = "JOGADOR 1", porta: int = PORTA_PADRAO) -> int:
	encerrar_conexao()

	peer = ENetMultiplayerPeer.new()
	var erro: int = peer.create_server(porta, MAX_JOGADORES - 1)
	if erro != OK:
		falha_conexao.emit("Não consegui abrir a porta %d (erro %d)" % [porta, erro])
		return erro

	multiplayer.multiplayer_peer = peer
	sou_host = true
	conectado = true
	meu_indice_jogador = 0
	meu_nome_jogador = nome_jogador

	jogadores.clear()
	jogadores[1] = {"indice": 0, "nome": nome_jogador, "pronto": false}
	lista_jogadores_atualizada.emit(jogadores)

	print("Rede: hospedando na porta ", porta)
	return OK


func conectar_a(ip: String, nome_jogador: String = "JOGADOR 2", porta: int = PORTA_PADRAO) -> int:
	encerrar_conexao()

	peer = ENetMultiplayerPeer.new()
	var erro: int = peer.create_client(ip, porta)
	if erro != OK:
		falha_conexao.emit("Não consegui iniciar o cliente (erro %d)" % erro)
		return erro

	multiplayer.multiplayer_peer = peer
	sou_host = false
	meu_nome_jogador = nome_jogador

	print("Rede: conectando a ", ip, ":", porta)
	return OK


func encerrar_conexao() -> void:
	if peer != null:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = null
	conectado = false
	sou_host = false
	meu_indice_jogador = -1
	jogadores.clear()


func _ao_peer_conectar(id_peer: int) -> void:
	print("Rede: peer conectou -> ", id_peer)
	if not sou_host:
		return

	var proximo_indice: int = jogadores.size()
	if proximo_indice >= MAX_JOGADORES:
		return

	jogadores[id_peer] = {"indice": proximo_indice, "nome": "JOGADOR %d" % (proximo_indice + 1), "pronto": false}
	_sincronizar_roster_para_todos()


func _ao_peer_desconectar(id_peer: int) -> void:
	print("Rede: peer desconectou -> ", id_peer)
	if not jogadores.has(id_peer):
		return

	var indice: int = int(jogadores[id_peer]["indice"])
	jogadores.erase(id_peer)
	peer_desconectado.emit(id_peer, indice)

	if sou_host:
		_sincronizar_roster_para_todos()


func _ao_conectar_no_host() -> void:
	conectado = true
	print("Rede: conectado ao host com sucesso.")
	rpc_id(1, "_rpc_registrar_nome", meu_nome_jogador)


func _ao_falhar_conexao() -> void:
	conectado = false
	falha_conexao.emit("Falha ao conectar no host. Verifique o IP e a rede.")


func _ao_host_cair() -> void:
	conectado = false
	desconectado_do_host.emit()
	encerrar_conexao()


@rpc("any_peer", "reliable")
func _rpc_registrar_nome(nome: String) -> void:
	if not sou_host:
		return
	var id_peer: int = multiplayer.get_remote_sender_id()
	if jogadores.has(id_peer):
		jogadores[id_peer]["nome"] = nome
		_sincronizar_roster_para_todos()


func _sincronizar_roster_para_todos() -> void:
	var lista: Array = []
	for id_peer in jogadores.keys():
		var info: Dictionary = jogadores[id_peer]
		lista.append({"id_peer": id_peer, "indice": info["indice"], "nome": info["nome"], "pronto": info["pronto"]})

	rpc("_rpc_receber_roster", lista)


@rpc("authority", "reliable", "call_local")
func _rpc_receber_roster(lista: Array) -> void:
	jogadores.clear()
	for item in lista:
		var id_peer: int = int(item["id_peer"])
		jogadores[id_peer] = {"indice": int(item["indice"]), "nome": str(item["nome"]), "pronto": bool(item["pronto"])}
		if id_peer == multiplayer.get_unique_id():
			meu_indice_jogador = int(item["indice"])
			peer_conectado.emit(id_peer, meu_indice_jogador)

	lista_jogadores_atualizada.emit(jogadores)


func marcar_pronto() -> void:
	if not conectado:
		return
	if sou_host:
		_marcar_pronto_interno(1)
	else:
		rpc_id(1, "_rpc_marcar_pronto")


@rpc("any_peer", "reliable")
func _rpc_marcar_pronto() -> void:
	if not sou_host:
		return
	_marcar_pronto_interno(multiplayer.get_remote_sender_id())


func _marcar_pronto_interno(id_peer: int) -> void:
	if jogadores.has(id_peer):
		jogadores[id_peer]["pronto"] = true

	_sincronizar_roster_para_todos()

	var todos_ok: bool = jogadores.size() >= 2
	for info in jogadores.values():
		if not bool(info["pronto"]):
			todos_ok = false
			break

	if todos_ok:
		todos_prontos.emit()


func resetar_prontos() -> void:
	if not sou_host:
		return
	for id_peer in jogadores.keys():
		jogadores[id_peer]["pronto"] = false
	_sincronizar_roster_para_todos()


func iniciar_partida_para_todos(duracao_segundos: float) -> void:
	if not sou_host:
		return
	rpc("_rpc_comeca_partida", duracao_segundos)


@rpc("authority", "reliable", "call_local")
func _rpc_comeca_partida(duracao_segundos: float) -> void:
	comeca_partida.emit(duracao_segundos)


func notificar_ponto(indice_jogador: int, total: int) -> void:
	if not conectado:
		return
	if sou_host:
		rpc("_rpc_ponto_marcado", indice_jogador, total)
	else:
		rpc_id(1, "_rpc_retransmitir_ponto", indice_jogador, total)


@rpc("any_peer", "reliable")
func _rpc_retransmitir_ponto(indice_jogador: int, total: int) -> void:
	if not sou_host:
		return
	rpc("_rpc_ponto_marcado", indice_jogador, total)


@rpc("authority", "reliable", "call_local")
func _rpc_ponto_marcado(indice_jogador: int, total: int) -> void:
	ponto_remoto_marcado.emit(indice_jogador, total)


func notificar_fim_partida(indice_jogador: int, total_final: int) -> void:
	if not conectado:
		return
	if sou_host:
		rpc("_rpc_partida_encerrada", indice_jogador, total_final)
	else:
		rpc_id(1, "_rpc_retransmitir_fim", indice_jogador, total_final)


@rpc("any_peer", "reliable")
func _rpc_retransmitir_fim(indice_jogador: int, total_final: int) -> void:
	if not sou_host:
		return
	rpc("_rpc_partida_encerrada", indice_jogador, total_final)


@rpc("authority", "reliable", "call_local")
func _rpc_partida_encerrada(indice_jogador: int, total_final: int) -> void:
	partida_remota_encerrada.emit(indice_jogador, total_final)


func meu_ip_local() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"


func numero_de_jogadores_conectados() -> int:
	return jogadores.size()
