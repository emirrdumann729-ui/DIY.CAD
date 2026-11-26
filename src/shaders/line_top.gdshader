// Her zaman üstte çizilen çizgiler (düzenlenen taslak, önizleme).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_test_disabled;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

void fragment() {
	ALBEDO = srgb_to_linear(COLOR.rgb);
	ALPHA = COLOR.a;
}
