// REDE DA CESTA: desenhada uma vez em repouso; aqui a placa de vídeo estica
// (mola depois da cesta) e balança os fios. Abaixo de "topo" (a linha do aro)
// nada se mexe, então a rede não descola do aro.
shader_type canvas_item;

uniform float altura = 104.0;
uniform float topo = 15.0;
uniform float estica = 0.0;
uniform float balanco = 0.0;

void vertex() {
	float k = clamp((VERTEX.y - topo) / (altura - topo), 0.0, 1.3);
	// a boca de baixo estreita quando estica (0.55 -> 0.55 - 0.12 * estica)
	VERTEX.x = VERTEX.x * (1.0 - k * 0.218 * estica) + balanco * k;
	VERTEX.y = VERTEX.y + max(VERTEX.y - topo, 0.0) * 0.35 * estica;
}
