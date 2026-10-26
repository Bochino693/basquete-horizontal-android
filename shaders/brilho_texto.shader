// BRILHO QUE ATRAVESSA UM TEXTO (a chamada da abertura): uma faixa
// inclinada de luz passa pelas letras, pela posição de cada ponto da letra
// (a mesma faixa para o contorno e para o miolo). Fora da passagem é o
// texto normal. Uma leitura de textura por ponto (a da própria letra).
shader_type canvas_item;

uniform float pos = -1000.0;      // onde a faixa está (unidades do texto)
uniform float largura = 70.0;
uniform float forca = 0.0;

varying vec2 p;

void vertex() {
	p = VERTEX;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float d = abs(p.x + p.y * 0.45 - pos) / largura;
	float k = clamp(1.0 - d, 0.0, 1.0);
	c.rgb = mix(c.rgb, vec3(1.0, 0.98, 0.9), k * k * forca);
	COLOR = c;
}
