shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Draws each hex as an outline rather than a disc: the middle is as
// transparent as the instance colour says, and a band around the rim is
// painted in edge_color. The band is measured with a distance field instead
// of a texture, so it stays one pixel-crisp line at any zoom and needs no
// UVs — which matters, because the tiles are a MultiMesh sharing one mesh.

uniform vec4 edge_color : source_color = vec4(0.45, 0.85, 0.25, 0.85);
// Circumradius of the tile mesh. The battle map sets this to match hex_size.
uniform float hex_radius = 0.94;
// Thickness of the line, in the same units as hex_radius.
uniform float edge_width = 0.07;
// Only needed if the outline comes out as a six-pointed star instead of a
// hexagon, which means the field is 30 degrees out of step with the mesh.
uniform float edge_rotation_degrees = 0.0;

varying vec4 inst_color;
varying vec3 local_pos;


void vertex() {
	inst_color = COLOR;
	local_pos = VERTEX;
}


// Signed distance to a hexagon's boundary: negative inside, zero on the edge.
// `inradius` is the centre-to-flat-side distance.
float hex_distance(vec2 p, float inradius) {
	const vec3 k = vec3(-0.8660254, 0.5, 0.57735027);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	return length(p - vec2(clamp(p.x, -k.z * inradius, k.z * inradius), inradius)) * sign(p.y - inradius);
}


void fragment() {
	// The mesh's points run along Z, the distance field's along X, so the
	// two axes are swapped on the way in.
	vec2 p = vec2(local_pos.z, local_pos.x);

	float a = radians(edge_rotation_degrees);
	float cs = cos(a);
	float sn = sin(a);
	p = vec2(p.x * cs - p.y * sn, p.x * sn + p.y * cs);

	float inradius = hex_radius * 0.8660254;
	float d = hex_distance(p, inradius);

	// fwidth keeps the line one screen-pixel soft however close the camera is
	float w = max(fwidth(d) * 1.5, 0.0001);
	float line = smoothstep(-edge_width - w, -edge_width + w, d);

	// A tile the game has highlighted lends its colour to its own outline, so
	// a reachable area reads as a block rather than a wash behind green wire.
	float highlighted = smoothstep(0.02, 0.40, inst_color.a);
	vec3 line_rgb = mix(edge_color.rgb, inst_color.rgb, highlighted);

	ALBEDO = mix(inst_color.rgb, line_rgb, line);
	ALPHA = mix(inst_color.a, edge_color.a, line);
}
