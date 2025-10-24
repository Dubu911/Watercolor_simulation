extends Node2D

@onready var physics_settings_window = $PhysicsSettingsWindow
@onready var painting_coordinator = $painting_coordinator
@onready var physics_simulator = $painting_coordinator/physics_simulator
@onready var file_menu_button = $CanvasLayer/FileMenuButton
@onready var new_canvas_dialog = $NewCanvasDialog
@onready var export_file_dialog = $ExportFileDialog
@onready var file_manager = $file_manager

func _ready():
	# Initialize physics settings window with references
	if is_instance_valid(physics_settings_window):
		physics_settings_window.initialize(painting_coordinator, physics_simulator)

	# Initialize file manager
	if is_instance_valid(file_manager):
		file_manager.initialize(painting_coordinator)

	# Setup File menu
	if is_instance_valid(file_menu_button):
		var popup = file_menu_button.get_popup()
		popup.clear()
		popup.add_item("New Canvas (Ctrl+N)", 0)
		popup.add_separator()
		popup.add_item("Export PNG (Ctrl+E)", 1)
		if not popup.id_pressed.is_connected(_on_file_menu_id_pressed):
			popup.id_pressed.connect(_on_file_menu_id_pressed)

	# Connect New Canvas dialog
	if is_instance_valid(new_canvas_dialog):
		if not new_canvas_dialog.confirmed.is_connected(_on_new_canvas_confirmed):
			new_canvas_dialog.confirmed.connect(_on_new_canvas_confirmed)

func _input(event : InputEvent):
	if event.is_action("Quit") :
		get_tree().quit()

func _on_settings_button_pressed():
	if is_instance_valid(physics_settings_window):
		# Show/hide settings panel
		if physics_settings_window.visible:
			physics_settings_window.hide()
		else:
			physics_settings_window.popup_centered(Vector2i(500, 700))
			physics_settings_window._load_current_values()

# File menu item handler
func _on_file_menu_id_pressed(id: int):
	match id:
		0:  # New Canvas
			if is_instance_valid(new_canvas_dialog):
				new_canvas_dialog.popup_centered()
		1:  # Export PNG
			if is_instance_valid(export_file_dialog):
				export_file_dialog.popup_centered()

# New Canvas confirmed
func _on_new_canvas_confirmed():
	if is_instance_valid(new_canvas_dialog) and is_instance_valid(file_manager):
		var width_spinbox = new_canvas_dialog.get_node("VBoxContainer/WidthRow/WidthSpinBox")
		var height_spinbox = new_canvas_dialog.get_node("VBoxContainer/HeightRow/HeightSpinBox")

		if width_spinbox and height_spinbox:
			var width = int(width_spinbox.value)
			var height = int(height_spinbox.value)
			# Hide dialog first to prevent click fall-through
			new_canvas_dialog.hide()
			file_manager.new_canvas(width, height)

# Export PNG file selected
func _on_export_file_selected(path: String):
	if is_instance_valid(file_manager):
		# Ensure .png extension
		if not path.ends_with(".png"):
			path += ".png"
		file_manager.export_png(path)
