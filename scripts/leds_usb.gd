extends Node

## LEDS DA MÁQUINA pelo USB da TV Box (autoload Leds).
##
## Os mesmos comandos do jogo antigo, uma linha por comando, a 9600 baud,
## para o Arduino dos LEDs que já está na máquina continuar servindo:
##   IDLE    abertura (esperando jogador)
##   PLAY    partida começou
##   HIT     cesta
##   BOOST   entrou EM CHAMAS
##   RECORD  novo recorde
##   OFF     apaga
## Usa o plugin DragonUsbSerial (android/plugins). Procura o Arduino a cada
## 2 s e reconecta sozinho se o cabo sair. No PC só mostra no console.

const BAUD := 9600
const PROCURAR_MS := 2000

var conectado := false
var status := "Procurando o Arduino dos LEDs..."

var _plugin: Object = null
var _ultima_procura := -100000
var _estado := "IDLE"   # reenviado quando o Arduino reconecta


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	if OS.get_name() != "Android":
		status = "PC: LEDs só no console"
		return
	if not Engine.has_singleton("DragonUsbSerial"):
		status = "Plugin USB ausente no APK"
		return
	_plugin = Engine.get_singleton("DragonUsbSerial")


func _process(_delta: float) -> void:
	if _plugin == null:
		return
	if bool(_plugin.call("isOpen")):
		# Descarta o que o Arduino mandar (não precisamos ler nada).
		_plugin.call("pollLines")
		return
	if conectado:
		conectado = false
		status = "Arduino dos LEDs desconectado"
	var agora := OS.get_ticks_msec()
	if agora - _ultima_procura < PROCURAR_MS:
		return
	_ultima_procura = agora
	var portas := str(_plugin.call("listPorts")).split("\n", false)
	if portas.empty():
		status = "Arduino dos LEDs não encontrado"
		return
	for porta in portas:
		if bool(_plugin.call("openPort", porta, BAUD)):
			conectado = true
			status = "LEDs conectados"
			# O Arduino reinicia ao abrir a porta; manda o estado depois.
			get_tree().create_timer(2.0).connect("timeout", self, "_reenviar_estado")
			return
	status = str(_plugin.call("getLastError"))


func _reenviar_estado() -> void:
	enviar(_estado)


func enviar(comando: String) -> void:
	if comando in ["IDLE", "PLAY", "OFF"]:
		_estado = comando
	if _plugin == null:
		print("LED -> ", comando)
		return
	if bool(_plugin.call("isOpen")):
		_plugin.call("writeLine", comando)


func _exit_tree() -> void:
	if _plugin != null and bool(_plugin.call("isOpen")):
		_plugin.call("writeLine", "OFF")
		_plugin.call("closePort")
