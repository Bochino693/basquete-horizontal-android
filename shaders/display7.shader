// PLACAR DE LED (placar_led.gd). Cada caractere é um quadrado com
// a textura de CAMPO DE DISTÂNCIA dele (tools/gerar_efeitos.py, d7_*.png):
//   R = distância até os segmentos acesos, G = até o "8" (os apagados).
// Daqui sai tudo, por pixel e liso em qualquer tamanho:
//   * a borda do segmento com 1 pixel da tela de transição (nada de
//     "escadinha", nem de perto);
//   * o miolo quente (quase branco) no meio de cada segmento, como o LED;
//   * o brilho em volta, que some suave (exponencial) e é um só para o
//     dígito inteiro (sem as emendas de um segmento sobre o outro);
//   * os segmentos apagados: vidro escuro da mesma cor.
// Uma leitura de textura e poucas contas por pixel: leve para a Mali-450
// (16 bits por conta bastam: as distâncias são pequenas).
shader_type canvas_item;

uniform vec4 cor : hint_color = vec4(1.0, 0.46, 0.04, 1.0);
uniform float altura_px = 120.0;   // altura do dígito em pixels DA TELA
uniform float apagado = 0.40;      // força dos segmentos apagados (0..1)
uniform float brilho = 0.075;      // alcance do brilho (fração da altura)
uniform float forca_brilho = 0.62;

const float DMIN = -0.10;          // a mesma faixa do gerar_texturas.py
const float DMAX = 0.30;

void fragment() {
	vec4 s = texture(TEXTURE, UV);
	float d = DMAX - s.r * (DMAX - DMIN);
	float d8 = DMAX - s.g * (DMAX - DMIN);
	// cobertura com borda de 1 pixel da tela
	float aceso = clamp(0.5 - d * altura_px, 0.0, 1.0);
	float todos = clamp(0.5 - d8 * altura_px, 0.0, 1.0);
	float ap = clamp(todos - aceso, 0.0, 1.0) * apagado;
	// miolo quente: o meio do segmento (meia espessura = 0,0675)
	float miolo = clamp((-d - 0.010) / 0.050, 0.0, 1.0);
	vec3 c_aceso = mix(cor.rgb * 1.06, vec3(1.0, 0.97, 0.90), miolo * miolo * 0.78);
	// um toque de luz por cima (o vidro do LED reflete a luz da sala)
	c_aceso += vec3(0.10) * clamp(1.0 - UV.y * 2.2, 0.0, 1.0) * aceso;
	vec3 c_apagado = cor.rgb * 0.20 + vec3(0.015);
	float g = forca_brilho * exp(-max(d, 0.0) / brilho);
	// camadas (alfa pré-multiplicado): brilho, apagados, acesos
	vec3 pm = cor.rgb * g;
	float a = g;
	pm = c_apagado * ap + pm * (1.0 - ap);
	a = ap + a * (1.0 - ap);
	pm = c_aceso * aceso + pm * (1.0 - aceso);
	a = aceso + a * (1.0 - aceso);
	COLOR = vec4(pm / max(a, 0.002), a);
}
