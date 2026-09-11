shader_type canvas_item;
render_mode unshaded, blend_add;

void vertex() {
	// Centerline radius and compensated native line width vary independently.
	VERTEX = VERTEX * (INSTANCE_CUSTOM.x + INSTANCE_CUSTOM.z)
		+ UV * (INSTANCE_CUSTOM.y + INSTANCE_CUSTOM.w);
}
