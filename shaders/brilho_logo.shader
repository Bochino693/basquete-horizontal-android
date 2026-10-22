// REFLEXO NO LOGO (Godot 3, GLES2): uma faixa de luz dourada atravessa o
// logo na diagonal. Só pinta onde o próprio logo tem cor (a transparência
// dele é a máscara). Uma leitura de textura e meia dúzia de contas: leve
// para a Mali-450. "pos" vem do script (0 = esquerda, 1.4 = já passou).
shader_type canvas_item;

uniform float pos = -1.0;
uniform float forca = 0.0;
uniform vec4 cor_reflexo : hint_color = vec4(1.0, 0.86, 0.5, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float d = abs(UV.x + UV.y * 0.35 - pos);
	float faixa = (1.0 - smoothstep(0.0, 0.08, d)) * forca;
	// (o modulate do nó - aparecer/sumir - o Godot aplica depois)
	COLOR = vec4(mix(tex.rgb, cor_reflexo.rgb, faixa * 0.65) + cor_reflexo.rgb * faixa * 0.25, tex.a);
}
