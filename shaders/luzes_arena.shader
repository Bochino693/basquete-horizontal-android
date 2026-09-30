// LUZES DA ARENA (Godot 3, GLES2): a arte é fixa; a máscara diz onde tem luz.
//   R = tubos de neon e faixa de LED: uma onda de luz corre por eles
//   G = lâmpadas da moldura; B = ordem de cada lâmpada na volta
// Fora da máscara (quase toda a tela) o pixel sai direto, sem conta.
shader_type canvas_item;

uniform sampler2D mascara;
uniform vec4 cor_neon : hint_color = vec4(1.0, 0.78, 0.22, 1.0);
uniform vec4 cor_lampada : hint_color = vec4(1.0, 0.86, 0.45, 1.0);
uniform float velocidade = 1.0;
uniform float intensidade = 1.0;
uniform float lampadas = 54.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 m = texture(mascara, UV).rgb;
	COLOR = tex;
	if (m.r + m.g > 0.01) {
		float t = TIME * velocidade;
		float onda = 0.5 + 0.5 * sin((UV.x * 5.0 + UV.y * 3.0) * 6.2832 - t * 3.5);
		vec3 luz = cor_neon.rgb * m.r * (0.15 + 0.85 * onda * onda * onda) * 0.6 * intensidade;
		float seq = fract(m.b * lampadas / 3.0 - t * 1.6);
		float acesa = step(0.62, seq);
		luz += cor_lampada.rgb * m.g * (0.12 + 1.3 * acesa) * intensidade;
		COLOR.rgb = tex.rgb + luz;
	}
}
