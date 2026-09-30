extends Reference

## Peças de interface e animações prontas usadas em todas as telas.


static func label(texto: String, fonte: Font, cor: Color, alinhar := Label.ALIGN_CENTER) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_font_override("font", fonte)
	l.add_color_override("font_color", cor)
	l.align = alinhar
	l.valign = Label.VALIGN_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Painel neon: fundo escuro translúcido, borda colorida e brilho em volta.
static func painel(cor: Color, fundo := Color(0.04, 0.02, 0.10, 0.82), raio := 18, borda := 3, brilho := 18) -> Panel:
	var p := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = fundo
	s.border_color = cor
	s.set_border_width_all(borda)
	s.set_corner_radius_all(raio)
	s.shadow_color = Color(cor.r, cor.g, cor.b, 0.45)
	s.shadow_size = brilho
	s.anti_aliasing = true
	p.add_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func cor_painel(p: Panel, cor: Color) -> void:
	var s: StyleBoxFlat = p.get_stylebox("panel")
	s.border_color = cor
	s.shadow_color = Color(cor.r, cor.g, cor.b, 0.45)


static func colocar(no: Control, x: float, y: float, w: float, h: float) -> void:
	no.rect_position = Vector2(x, y)
	no.rect_size = Vector2(w, h)
	no.rect_pivot_offset = Vector2(w, h) / 2


static func _tween(no: Node) -> Tween:
	var tw := Tween.new()
	no.add_child(tw)
	tw.connect("tween_all_completed", tw, "queue_free")
	return tw


## Entra "pulando": cresce do pequeno com um leve exagero.
static func pop(no: CanvasItem, atraso := 0.0, dur := 0.45, de := 0.2) -> void:
	var tw := _tween(no)
	no.modulate.a = 0.0
	tw.interpolate_property(no, "modulate:a", 0.0, 1.0, dur * 0.5, Tween.TRANS_SINE, Tween.EASE_OUT, atraso)
	if no is Control:
		tw.interpolate_property(no, "rect_scale", Vector2(de, de), Vector2.ONE, dur, Tween.TRANS_BACK, Tween.EASE_OUT, atraso)
	else:
		tw.interpolate_property(no, "scale", Vector2(de, de), Vector2.ONE, dur, Tween.TRANS_BACK, Tween.EASE_OUT, atraso)
	tw.start()


## Entra deslizando de um lado.
static func deslizar(no: Control, de: Vector2, atraso := 0.0, dur := 0.5) -> void:
	var tw := _tween(no)
	var ate := no.rect_position
	no.rect_position = ate + de
	no.modulate.a = 0.0
	tw.interpolate_property(no, "rect_position", ate + de, ate, dur, Tween.TRANS_QUINT, Tween.EASE_OUT, atraso)
	tw.interpolate_property(no, "modulate:a", 0.0, 1.0, dur * 0.6, Tween.TRANS_SINE, Tween.EASE_OUT, atraso)
	tw.start()


## Um "soco" de escala (pontos mudando, combo).
static func pulsar(no: Control, forca := 0.18, dur := 0.3) -> void:
	var tw := _tween(no)
	tw.interpolate_property(no, "rect_scale", Vector2.ONE * (1.0 + forca), Vector2.ONE, dur, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw.start()


## Some (e se apaga da árvore depois).
static func sumir(no: CanvasItem, atraso := 0.0, dur := 0.35, apagar := true) -> void:
	var tw := _tween(no)
	tw.interpolate_property(no, "modulate:a", no.modulate.a, 0.0, dur, Tween.TRANS_SINE, Tween.EASE_IN, atraso)
	if apagar:
		tw.interpolate_callback(no, atraso + dur, "queue_free")
	tw.start()


## Texto que sobe e some ("+2", "COMBO x3"...). Vai de "de" para "ate".
static func flutuar(pai: Node, texto: String, fonte: Font, cor: Color, de: Vector2, ate: Vector2, dur := 0.9) -> Label:
	var l := label(texto, fonte, cor)
	l.rect_size = Vector2(400, 120)
	l.rect_pivot_offset = l.rect_size / 2
	l.rect_position = de - l.rect_size / 2
	pai.add_child(l)
	var tw := _tween(l)
	tw.interpolate_property(l, "rect_scale", Vector2(0.3, 0.3), Vector2(1.25, 1.25), 0.22, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw.interpolate_property(l, "rect_scale", Vector2(1.25, 1.25), Vector2(0.8, 0.8), dur - 0.22, Tween.TRANS_SINE, Tween.EASE_IN, 0.22)
	tw.interpolate_property(l, "rect_position", l.rect_position, ate - l.rect_size / 2, dur, Tween.TRANS_QUAD, Tween.EASE_IN)
	tw.interpolate_property(l, "modulate:a", 1.0, 0.0, 0.25, Tween.TRANS_SINE, Tween.EASE_IN, dur - 0.25)
	tw.interpolate_callback(l, dur, "queue_free")
	tw.start()
	return l
