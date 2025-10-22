# physics_settings_window.gd
extends PopupPanel

# References to coordinator and physics simulator
var painting_coordinator: Node = null
var physics_simulator: Node = null

# Called when the panel is ready
func _ready():
	pass

# Initialize with references to coordinator and simulator
func initialize(coordinator: Node, simulator: Node):
	painting_coordinator = coordinator
	physics_simulator = simulator
	# Load current values into sliders
	_load_current_values()

# Load current parameter values from physics simulator and coordinator
func _load_current_values():
	if not is_instance_valid(physics_simulator) or not is_instance_valid(painting_coordinator):
		return

	# Canvas Orientation
	var vertical_slider = $MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/CanvasOrientationSection/VerticalTilt/Slider
	var horizontal_slider = $MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/CanvasOrientationSection/HorizontalTilt/Slider
	vertical_slider.value = painting_coordinator.vertical_theta
	horizontal_slider.value = painting_coordinator.horizontal_theta

	# Water Parameters
	var s_slider = $MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/WaterSection/SurfaceTension/Slider
	var sp_slider = $MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/WaterSection/SpreadForce/Slider
	var cancel_slider = $MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/WaterSection/CancelingPower/Slider
	var accel_slider = $MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/WaterSection/AccelerationPower/Slider
	var evap_slider = $MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/WaterSection/EvaporationConst/Slider
	var hold_slider = $MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/WaterSection/HoldThreshold/Slider

	s_slider.value = physics_simulator.S
	sp_slider.value = physics_simulator.SP
	cancel_slider.value = physics_simulator.canceling_power
	accel_slider.value = physics_simulator.acceleration_power
	evap_slider.value = physics_simulator.EVAPORATION_CONST
	hold_slider.value = physics_simulator.HOLD_THRESHOLD

	# Diffusion Parameters
	var diff_rate_slider = $MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/DiffusionSection/DiffusionRate/Slider
	var diff_lim_slider = $MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/DiffusionSection/DiffusionLimiter/Slider
	var deposit_slider = $MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/DiffusionSection/DepositBase/Slider
	var wscale_slider = $MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/DiffusionSection/WScale/Slider

	diff_rate_slider.value = physics_simulator.DIFFUSION_RATE
	diff_lim_slider.value = physics_simulator.diffusion_limiter
	deposit_slider.value = physics_simulator.k_deposit_base
	wscale_slider.value = physics_simulator.w_scale

# Update value labels with proper formatting
func _update_label(path: String, value: float, suffix: String = ""):
	var label = get_node_or_null(path)
	if label:
		label.text = "%.2f%s" % [value, suffix]

# Canvas Orientation handlers
func _on_vertical_tilt_changed(value: float):
	if is_instance_valid(painting_coordinator):
		painting_coordinator.set_vertical_tilt(value)
	_update_label("MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/CanvasOrientationSection/VerticalTilt/ValueLabel", value, "°")

func _on_horizontal_tilt_changed(value: float):
	if is_instance_valid(painting_coordinator):
		painting_coordinator.set_horizontal_tilt(value)
	_update_label("MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/CanvasOrientationSection/HorizontalTilt/ValueLabel", value, "°")

# Water parameter handlers
func _on_surface_tension_changed(value: float):
	if is_instance_valid(physics_simulator):
		physics_simulator.S = value
	_update_label("MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/WaterSection/SurfaceTension/ValueLabel", value)

func _on_spread_force_changed(value: float):
	if is_instance_valid(physics_simulator):
		physics_simulator.SP = value
	_update_label("MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/WaterSection/SpreadForce/ValueLabel", value)

func _on_canceling_power_changed(value: float):
	if is_instance_valid(physics_simulator):
		physics_simulator.canceling_power = value
	_update_label("MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/WaterSection/CancelingPower/ValueLabel", value)

func _on_acceleration_power_changed(value: float):
	if is_instance_valid(physics_simulator):
		physics_simulator.acceleration_power = value
	_update_label("MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/WaterSection/AccelerationPower/ValueLabel", value)

func _on_evaporation_const_changed(value: float):
	if is_instance_valid(physics_simulator):
		physics_simulator.EVAPORATION_CONST = value
	_update_label("MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/WaterSection/EvaporationConst/ValueLabel", value)

func _on_hold_threshold_changed(value: float):
	if is_instance_valid(physics_simulator):
		physics_simulator.HOLD_THRESHOLD = value
	_update_label("MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/WaterSection/HoldThreshold/ValueLabel", value)

# Diffusion parameter handlers
func _on_diffusion_rate_changed(value: float):
	if is_instance_valid(physics_simulator):
		physics_simulator.DIFFUSION_RATE = value
	_update_label("MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/DiffusionSection/DiffusionRate/ValueLabel", value)

func _on_diffusion_limiter_changed(value: float):
	if is_instance_valid(physics_simulator):
		physics_simulator.diffusion_limiter = value
	_update_label("MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/DiffusionSection/DiffusionLimiter/ValueLabel", value)

func _on_deposit_base_changed(value: float):
	if is_instance_valid(physics_simulator):
		physics_simulator.k_deposit_base = value
	_update_label("MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/DiffusionSection/DepositBase/ValueLabel", value)

func _on_w_scale_changed(value: float):
	if is_instance_valid(physics_simulator):
		physics_simulator.w_scale = value
	_update_label("MarginContainer/VBoxContainer/ScrollContainer/ParametersVBox/DiffusionSection/WScale/ValueLabel", value)
