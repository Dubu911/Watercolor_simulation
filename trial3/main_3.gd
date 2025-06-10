extends Node2D

func _input(event : InputEvent):
	if event.is_action("Quit") :
		get_tree().quit()
