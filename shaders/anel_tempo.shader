// ANEL DO RELÓGIO (anel_tempo.gd): a malha da faixa é montada uma vez;
// cada ponto sabe a sua fração do círculo (UV.x, do topo, no sentido do
// relógio) e o lado da faixa (UV.y, -1 a 1). O script só passa a fração do
// tempo que resta e a cor: nada é redesenhado.
//   macio = 0: faixa com borda lisa de 1 pixel da tela; 1: brilho macio.
shader_type canvas_item;

uniform float frac = 1.0;
uniform vec4 cor : hint_color = vec4(0.22, 1.0, 0.42, 1.0);
uniform float largura_px = 10.0;   // largura da faixa em pixels da tela
uniform float macio = 0.0;
uniform float forca = 1.0;

void fragment() {
	float lado = abs(UV.y);
	float faixa = clamp((1.0 - lado) * largura_px * 0.5 + 0.5, 0.0, 1.0);
	float brilho = (1.0 - lado) * (1.0 - lado);
	float a = mix(faixa, brilho, macio);
	// a ponta do arco também é lisa (fração -> pixels pelo perímetro)
	float aceso = clamp((frac - UV.x) * 900.0 + 0.5, 0.0, 1.0);
	COLOR = vec4(cor.rgb, cor.a * a * aceso * forca);
}
