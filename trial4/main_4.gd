extends Node2D

@onready var physics_settings_window = $PhysicsSettingsWindow
@onready var painting_coordinator = $painting_coordinator
@onready var physics_simulator = $painting_coordinator/physics_simulator

func _ready():
	# Initialize physics settings window with references
	if is_instance_valid(physics_settings_window):
		physics_settings_window.initialize(painting_coordinator, physics_simulator)

func _input(event : InputEvent):
	if event.is_action("Quit") :
		get_tree().quit()

func _on_settings_button_pressed():
	if is_instance_valid(physics_settings_window):
		# Get settings button position
		var settings_button = get_node_or_null("CanvasLayer/SettingsButton")
		if settings_button:
			# Position window just below the settings button (top-left corner)
			var button_rect = settings_button.get_global_rect()
			var window_pos = Vector2i(int(button_rect.position.x), int(button_rect.end.y + 40))  # px gap below button

			# Show the window at the specific position
			physics_settings_window.popup(Rect2i(window_pos, physics_settings_window.size))
		else:
			# Fallback to centered if button not found
			physics_settings_window.popup_centered()

		# Reload current values when opening
		physics_settings_window._load_current_values()
