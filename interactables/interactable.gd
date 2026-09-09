extends StaticBody3D
## ============================================================
##  INTERACTABLE.GD
##  Attach this script to any StaticBody3D you want the player to be
##  able to walk up to, look at, and press E on. It doesn't care what
##  the object LOOKS like -- a crate, an avocado, a glowing orb -- it
##  only handles the "can be interacted with" behavior.
## ============================================================

# @export means these show up in the Inspector for whichever object you
# attach this script to, so each object can have its own message
# without editing this file.
@export var prompt_text: String = "Press E to interact"
@export var interact_once: bool = true  # if true, it "disappears" after one use

# --- Collectible settings ---
# If is_collectible is on, pressing E adds this item to the player's
# Inventory (see systems/inventory.gd) instead of just vanishing with
# no lasting effect. Leave item_id blank on objects that are just
# decoration/flavor interactions with nothing to collect.
@export var is_collectible: bool = false
@export var item_id: String = ""       # e.g. "brass_key" -- must match whatever a locked door checks for
@export var item_display_name: String = ""  # e.g. "Brass Key" -- shown in HUD pickup messages

# --- Objective hook ---
# Optional: if set, picking this item up updates GameManager's current
# objective (see systems/game_manager.gd), which the HUD displays.
# Leave blank for items that shouldn't change what the player is
# currently trying to do.
@export var objective_on_pickup: String = ""

var _used := false


func _ready() -> void:
	# Groups are like tags. The player's script (see player.gd,
	# _update_interaction) asks "is whatever I'm looking at tagged
	# interactable?" instead of needing to know about every single
	# interactable object individually.
	add_to_group("interactable")


func get_prompt() -> String:
	# Called by the player/HUD to know what text to display, e.g.
	# "Press E to pick up".
	return prompt_text


func interact() -> void:
	# Called by the player when they press E while looking at this
	# object. Override or expand this in a copy of the script if you
	# want an object to do something more specific than "disappear."
	if _used and interact_once:
		return
	_used = true
	print("Interacted with: ", name)

	# If this object is set up as a collectible, hand it off to the
	# global Inventory autoload rather than just printing a message.
	# We use item_display_name if one was set, otherwise fall back to
	# the node's own name so we're never showing a blank label.
	if is_collectible:
		# Explicit ": String" (rather than ":=") because "name" is a
		# StringName, not a String -- mixing the two in a ternary makes
		# Godot's type inference give up and fall back to Variant,
		# which this project's strict-typing settings treat as an
		# error. Spelling out the type -- and wrapping name in
		# String(...) -- tells Godot exactly what we mean.
		var label: String = item_display_name if item_display_name != "" else String(name)
		Inventory.add_item(item_id, label)

		if objective_on_pickup != "":
			GameManager.set_objective(objective_on_pickup)

	if interact_once:
		# Hide it and turn off its collision, so it looks/feels
		# "picked up" instead of just becoming invisible but still
		# solid (which would be confusing to walk into).
		visible = false
		set_collision_layer_value(1, false)
		set_collision_mask_value(1, false)
