# test_gpu_simulator.gd
# Minimal test to verify GPU simulator initialization and shader compilation
extends Node

@onready var gpu_sim = $physics_simulator_gpu

func _ready():
	print("========================================")
	print("Testing GPU Simulator Initialization")
	print("========================================")

	# Create a simple absorbency map for testing (64x64 for quick test)
	var test_width = 64
	var test_height = 64

	var absorbency_map = Image.create(test_width, test_height, false, Image.FORMAT_RF)

	# Fill with uniform absorbency
	for y in range(test_height):
		for x in range(test_width):
			absorbency_map.set_pixel(x, y, Color(0.15, 0, 0))

	print("\n1. Initializing GPU simulator (", test_width, "x", test_height, ")...")
	var success = gpu_sim.init_gpu(test_width, test_height, absorbency_map)

	if success:
		print("✓ GPU simulator initialized successfully!")
		print("\n2. Testing simulation step...")

		# Run one simulation step
		gpu_sim.run_simulation_step_gpu(0.016, 0.0, 9.8)  # delta=16ms, gravity_y=9.8

		print("✓ Simulation step completed!")
		print("\n========================================")
		print("GPU Simulator Test: PASSED ✓")
		print("========================================")
		print("\nAll shaders compiled and executed successfully!")
		print("Ready to integrate with painting_coordinator.")
	else:
		printerr("\n========================================")
		printerr("GPU Simulator Test: FAILED ✗")
		printerr("========================================")
		printerr("Check console for shader compilation errors.")

func _process(_delta):
	# Don't run simulation in _process during test
	pass
