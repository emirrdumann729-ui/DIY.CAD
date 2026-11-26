// Seçili yüz vurgusu (yarı saydam, kameraya doğru kaydırılmış).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(0.25, 0.65, 1.0, 0.45);
uniform float depth_bias = 0.0;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.z += depth_bias;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
