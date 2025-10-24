# file_manager.gd
extends Node

var painting_coordinator: Node = null

func initialize(coordinator: Node):
	painting_coordinator = coordinator

# Create new canvas with specified dimensions
func new_canvas(width: int, height: int):
	if not is_instance_valid(painting_coordinator):
		printerr("file_manager: painting_coordinator not valid!")
		return false

	print("Creating new canvas: ", width, "×", height)

	# Call coordinator to reinitialize with new dimensions
	if painting_coordinator.has_method("reinitialize_canvas"):
		# Optional: extra guard to prevent stray strokes during reinit
		var bm = painting_coordinator.get_node_or_null(painting_coordinator.brush_manager_path)
		if bm and bm.has_method("_set_eat_clicks_frames"):
			bm._set_eat_clicks_frames(3)  # eat clicks for 3 frames

		painting_coordinator.reinitialize_canvas(width, height)
		return true
	else:
		printerr("file_manager: painting_coordinator missing 'reinitialize_canvas' method!")
		return false

# Export as PNG (composite all visible layers)
func export_png(filepath: String) -> bool:
	if not is_instance_valid(painting_coordinator):
		printerr("file_manager: painting_coordinator not valid!")
		return false

	print("Exporting PNG to: ", filepath)

	# Get composite image from coordinator (synchronous CPU compositing)
	var composite = painting_coordinator.get_composite_image()
	if composite:
		var err = composite.save_png(filepath)
		if err == OK:
			print("PNG exported successfully!")
			return true
		else:
			printerr("file_manager: Failed to save PNG: ", err)
			return false

	printerr("file_manager: get_composite_image() returned null")
	return false
