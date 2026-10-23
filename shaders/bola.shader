// BOLA DE BASQUETE DESENHADA À MÃO (sem imagem): esfera com luz, gomos e
// as costuras que giram. "giro" vem do script (já dentro de 0..2pi: na
// Mali-400/450 o pixel só tem precisão média).
shader_type canvas_item;

uniform float giro = 0.0;
uniform float inclina = 0.45;
uniform vec4 cor_bola : hint_color = vec4(0.96, 0.45, 0.10, 1.0);
uniform vec4 cor_costura : hint_color = vec4(0.10, 0.03, 0.01, 1.0);
uniform float ouro = 0.0;          // 1 = bola de ouro

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	float borda = clamp((1.0 - sqrt(r2)) * 30.0, 0.0, 1.0);
	vec3 n = vec3(p, sqrt(max(0.0, 1.0 - r2)));
	float c = cos(giro);
	float s = sin(giro);
	vec3 q = vec3(c * n.x + s * n.z, n.y, -s * n.x + c * n.z);
	float ci = cos(inclina);
	float si = sin(inclina);
	q = vec3(q.x, ci * q.y - si * q.z, si * q.y + ci * q.z);
	float w = 0.045;
	float linha = 1.0 - clamp(abs(q.x) / w - 0.4, 0.0, 1.0);
	linha = max(linha, 1.0 - clamp(abs(q.y) / w - 0.4, 0.0, 1.0));
	linha = max(linha, 1.0 - clamp(abs(abs(q.z) - 0.70) / w - 0.4, 0.0, 1.0));
	float luz = 0.32 + 0.68 * max(0.0, dot(n, vec3(-0.45, -0.55, 0.70)));
	float brilho = pow(max(0.0, dot(n, vec3(-0.35, -0.45, 0.82))), 18.0) * 0.55;
	vec3 base = mix(cor_bola.rgb, vec3(1.0, 0.78, 0.18), ouro);
	vec3 col = mix(base, cor_costura.rgb, linha * 0.92) * luz + vec3(brilho);
	float aro = clamp((sqrt(r2) - 0.86) * 7.0, 0.0, 1.0);
	col += mix(vec3(1.0, 0.45, 0.1), vec3(1.0, 0.9, 0.4), ouro) * aro * 0.35;
	COLOR = vec4(col, borda);
}
