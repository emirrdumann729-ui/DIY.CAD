// CAD çizgileri: kenarlar ve taslaklar. Yüzeylerle çakışmaması için görüş uzayında kameraya doğru kaydırılır.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform float depth_bias = 0.0;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.z += depth_bias;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
}
