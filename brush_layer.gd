extends Node2D

func draw_dot(pos: Vector2):
	var ci = get_canvas_item()
	var radius = 8.0
	var color = Color(0, 0, 0)
	RenderingServer.canvas_item_add_circle(ci, pos, radius, color)
