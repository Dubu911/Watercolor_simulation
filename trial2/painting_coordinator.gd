# painting_coordinator.gd
extends Node

# --- Canvas Properties ---
const CANVAS_WIDTH := 2000
const CANVAS_HEIGHT := 2000

# --- Layer NodePaths (Assign these in the Inspector) ---
@export var watercolor_layer_node_path: NodePath
@export var pencil_layer_node_path: NodePath

# --- Brush NodePaths (Assign these in the Inspector) ---
@export var watercolor_brush_node_path: NodePath
@export var pencil_brush_node_path: NodePath
@export var eraser_brush_node_path: NodePath

# --- Internal Layer Sprite References ---
var watercolor_layer_sprite: Sprite2D
var pencil_layer_sprite: Sprite2D

# --- Image Data & Textures ---
var watercolor_image: Image
var watercolor_texture: ImageTexture
var _dirty_watercolor_image: bool = false

var pencil_image: Image
var pencil_texture: ImageTexture
var _dirty_pencil_image: bool = false

# --- Brush Management ---
var watercolor_brush_node: Node # Should ideally be typed to a base Brush class
var pencil_brush_node: Node
var eraser_brush_node: Node
var active_brush_node: Node = null
var last_selected_color: Color = Color(0.1, 0.2, 0.8, 0.3) # Stores the last color from the color picker



func _ready():
	# 1. Get Layer Sprite2D Nodes
	if watercolor_layer_node_path.is_empty():
		print("Watercolor layer node path is empty")
		return
	watercolor_layer_sprite = get_node_or_null(watercolor_layer_node_path) as Sprite2D
	if not watercolor_layer_sprite:
		print("Watercolor layer sprite is Null")
		return

	if pencil_layer_node_path.is_empty():
		print("Pencil layer node path is empty")
		return
	pencil_layer_sprite = get_node_or_null(pencil_layer_node_path) as Sprite2D
	if not pencil_layer_sprite:
		print("Pencil layer sprite is Null")
		return

	# 2. Initialize Images & Textures
	watercolor_image = Image.create_empty(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBA8)
	watercolor_image.fill(Color.WHITE)
	watercolor_texture = ImageTexture.create_from_image(watercolor_image)
	watercolor_layer_sprite.texture = watercolor_texture
	watercolor_layer_sprite.centered = false
	mark_watercolor_dirty()

	pencil_image = Image.create_empty(CANVAS_WIDTH, CANVAS_HEIGHT, false, Image.FORMAT_RGBA8)
	pencil_image.fill(Color(0,0,0,0))
	pencil_texture = ImageTexture.create_from_image(pencil_image)
	pencil_layer_sprite.texture = pencil_texture
	pencil_layer_sprite.centered = false
	mark_pencil_dirty()

	# 3. Get Brush Nodes
	if not watercolor_brush_node_path.is_empty():
		watercolor_brush_node = get_node_or_null(watercolor_brush_node_path)
	
	if not pencil_brush_node_path.is_empty():
		pencil_brush_node = get_node_or_null(pencil_brush_node_path)

	if not eraser_brush_node_path.is_empty():
		eraser_brush_node = get_node_or_null(eraser_brush_node_path)
	
	# 4. Set a default active brush
	if watercolor_brush_node:
		_set_active_brush(watercolor_brush_node)


func _unhandled_input(event: InputEvent):
	if not active_brush_node:
		return

	if not watercolor_layer_sprite: # Should be valid if _ready completed
		return

	var global_mouse_pos = watercolor_layer_sprite.get_global_mouse_position() 
	var mouse_pos_image_space = watercolor_layer_sprite.to_local(global_mouse_pos)

	var target_image: Image = null
	if active_brush_node == watercolor_brush_node:
		target_image = watercolor_image
	elif active_brush_node == pencil_brush_node or active_brush_node == eraser_brush_node:
		target_image = pencil_image

	if not is_instance_valid(target_image):
		return 

	if active_brush_node.has_method("handle_input"):
		active_brush_node.handle_input(event, mouse_pos_image_space, target_image, self)


func _process(_delta: float):
	if _dirty_watercolor_image:
		if watercolor_texture and watercolor_image:
			watercolor_texture.update(watercolor_image)
		_dirty_watercolor_image = false
	
	if _dirty_pencil_image:
		if pencil_texture and pencil_image:
			pencil_texture.update(pencil_image)
		_dirty_pencil_image = false

func mark_watercolor_dirty():
	_dirty_watercolor_image = true

func mark_pencil_dirty():
	_dirty_pencil_image = true

func _set_active_brush(new_brush_node: Node):
	if not is_instance_valid(new_brush_node):
		printerr("PaintingCoordinator: Attempted to set an invalid new_brush_node.")
		return
		
	if active_brush_node == new_brush_node:
		return

	if active_brush_node and active_brush_node.has_method("deactivate"):
		active_brush_node.deactivate()

	active_brush_node = new_brush_node

	# Activate new brush and set its color if applicable
	if is_instance_valid(active_brush_node):
		if active_brush_node.has_method("activate"):
			active_brush_node.activate(self) # Pass self as coordinator reference
		
		# If the new brush is not the eraser and can have its color set, apply the last selected color
		if active_brush_node != eraser_brush_node and active_brush_node.has_method("set_active_color"):
			active_brush_node.set_active_color(last_selected_color)

# Called when the ColorPickerButton's color changes
func _update_brush_color_from_picker(new_color: Color):
	last_selected_color = new_color # Store the latest color picked
	print("PaintingCoordinator: Color picker changed to: ", last_selected_color)

	# If there's an active brush, it's not the eraser, and it can accept a color, update it
	if is_instance_valid(active_brush_node) and \
		active_brush_node != eraser_brush_node and \
		active_brush_node.has_method("set_active_color"):
		active_brush_node.set_active_color(last_selected_color)

func _on_watercolor_button_pressed():
	print("watercolor brush selected")
	if watercolor_brush_node:
		_set_active_brush(watercolor_brush_node)

func _on_pencil_button_pressed():
	print("Pencil brush selected")
	if pencil_brush_node:
		_set_active_brush(pencil_brush_node)

func _on_eraser_button_pressed():
	print("Eraser brush selected")
	if eraser_brush_node:
		_set_active_brush(eraser_brush_node)

func _on_color_picker_button_color_changed(new_color: Color):
	_update_brush_color_from_picker(new_color)
