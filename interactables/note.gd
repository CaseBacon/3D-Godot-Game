extends StaticBody3D
## ============================================================
##  NOTE.GD
##  A readable note/sign. Simplest interactable in the project --
##  worth starting here if you're reading through the codebase for
##  the first time, before interactable.gd and locked_door.gd which
##  do more. Pressing E just shows a block of text via the HUD; there
##  is no state to track beyond that, unlike a collectible or a lock.
## ============================================================

@export var prompt_text: String = "Press E to read"
@export_multiline var note_text: String = "A note."

var _hud: Node = null


func _ready() -> void:
	add_to_group("interactable")
	_hud = get_tree().get_first_node_in_group("hud")


func get_prompt() -> String:
	return prompt_text


func interact() -> void:
	if _hud:
		_hud.show_note(note_text)
