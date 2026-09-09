extends StaticBody3D
class_name CombinationLock
## ============================================================
##  COMBINATION_LOCK.GD
##  A wall panel the player enters a numeric code into. Deliberately
##  reuses the systems already built rather than inventing new ones:
##  a correct guess just calls Inventory.add_item(...), exactly like
##  picking up a key -- so whatever this unlocks can be a completely
##  ordinary locked_door.gd checking for that item. The lock doesn't
##  need to know or care what it opens.
##
##  Unlike interactable.gd and locked_door.gd, interact() here
##  doesn't resolve anything by itself -- it opens a UI panel (see
##  hud.gd's open_code_entry) and waits for the player to type digits
##  and submit. _on_code_submitted is the callback the HUD calls once
##  they do.
##
##  "class_name CombinationLock" registers this script as a proper
##  type Godot knows about project-wide, not just "some script
##  attached to a StaticBody3D." That's what lets hud.gd declare
##  "var _active_lock: CombinationLock" and call
##  _active_lock._on_code_submitted(...) with full static type
##  checking, instead of an untyped Node reference.
## ============================================================

@export var correct_code: String = "482"
@export var prompt_text: String = "Press E to enter code"

# --- What a correct guess grants ---
@export var unlock_item_id: String = ""
@export var unlock_item_name: String = ""
@export var objective_on_unlock: String = ""

var _solved := false
var _hud: Node = null


func _ready() -> void:
	add_to_group("interactable")
	_hud = get_tree().get_first_node_in_group("hud")


func get_prompt() -> String:
	if _solved:
		return ""  # Nothing left to do here; the raycast can still see us, but there's no prompt to show.
	return prompt_text


func interact() -> void:
	if _solved or _hud == null:
		return
	# Hand control over to the HUD's code-entry panel. We pass `self`
	# so the HUD knows which lock to report back to once the player
	# submits a code -- see _on_code_submitted below.
	_hud.open_code_entry(self)


func _on_code_submitted(entered_code: String) -> bool:
	# Called by hud.gd when the player presses Enter on the keypad.
	# Returns true/false so the HUD knows whether to show a "correct"
	# or "wrong code" reaction -- the lock decides correctness, the
	# HUD just displays the result.
	if entered_code != correct_code:
		return false

	_solved = true
	if unlock_item_id != "":
		Inventory.add_item(unlock_item_id, unlock_item_name)
	if objective_on_unlock != "":
		GameManager.set_objective(objective_on_unlock)
	return true
