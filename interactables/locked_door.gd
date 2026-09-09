extends StaticBody3D
## ============================================================
##  LOCKED_DOOR.GD
##  A door (or gate, or anything else blocking the way) that only
##  opens if the player is carrying a specific item. This is a
##  separate script from interactable.gd rather than a flag on it --
##  the "does the player have the right item?" check and the open
##  animation are different enough behavior that keeping them apart
##  makes both scripts easier to read on their own.
##
##  It still plugs into the exact same system as interactable.gd
##  though: it adds itself to the "interactable" group and exposes
##  get_prompt() / interact(), which is all player.gd actually cares
##  about (see player.gd's _update_interaction). player.gd never
##  needs to know a door and a pickup orb are different scripts.
## ============================================================

@export var required_item_id: String = ""
@export var required_item_name: String = "the key"  # used in the locked message, e.g. "Locked -- need the Brass Key"
@export var open_prompt: String = "Press E to open"

# How far (in meters, along the door's own -Y) it slides down to look
# "open." Sliding into the floor is the simplest possible door
# animation -- no extra animation nodes needed -- and reads fine for
# a prototype.
@export var slide_distance: float = 3.0
@export var slide_duration: float = 0.6

var _is_open := false

@onready var collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group("interactable")


func get_prompt() -> String:
	if _is_open:
		return ""  # Once open, the raycast won't hit it anyway (see _open_door), but just in case.

	if Inventory.has_item(required_item_id):
		return open_prompt
	return "Locked -- need %s" % required_item_name


func interact() -> void:
	if _is_open:
		return

	# If the player doesn't have the key, do nothing. The HUD prompt
	# (from get_prompt above) already told them why, so there's
	# nothing more to say here -- pressing E on a locked door just
	# silently fails, like it would in real life.
	if not Inventory.has_item(required_item_id):
		return

	_is_open = true
	_open_door()


func _open_door() -> void:
	# Disabling the CollisionShape3D (rather than the whole body's
	# collision layers, like interactable.gd does) removes JUST the
	# physical solidity -- the player can now walk through -- and also
	# means the interact raycast stops detecting this body at all,
	# since a StaticBody3D with no enabled shape can't be hit by a
	# physics query. That's why get_prompt() above can safely assume
	# it won't be asked anything once _is_open is true.
	collision.disabled = true

	# create_tween() gives us a one-off animation without needing an
	# AnimationPlayer node. tween_property animates one property (this
	# door's Y position) from its current value to a target value over
	# slide_duration seconds. EASE_IN + TRANS_CUBIC makes it start slow
	# and accelerate, like something heavy grinding open.
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y - slide_distance, slide_duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
