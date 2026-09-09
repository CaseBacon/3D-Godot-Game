extends Node
## ============================================================
##  INVENTORY.GD  (Autoload / Singleton)
##  Tracks which items the player has picked up. Also registered as
##  an Autoload (see game_manager.gd for what that means) so any
##  script can just say "Inventory.has_item(\"brass_key\")" without
##  needing a reference to the player or the HUD.
##
##  Items are tracked by a simple String ID (e.g. "brass_key",
##  "gear_1") rather than a whole class/resource. For a jam-scale
##  puzzle game this keeps things easy to read -- a locked door just
##  needs to ask "do you have the ID that unlocks me?"
## ============================================================

# Fired whenever an item is added, carrying both the ID (for game
# logic, e.g. "does this unlock the door") and a display name (for
# UI, e.g. showing "Picked up: Brass Key" in the HUD).
signal item_added(item_id: String, display_name: String)

# A Dictionary used purely as a "set" -- we only ever care whether a
# key EXISTS in it, not what its value is. This gives us O(1)
# has_item() checks instead of scanning an Array every time.
var _held_items: Dictionary = {}


func add_item(item_id: String, display_name: String = "") -> void:
	if _held_items.has(item_id):
		return  # Already have it -- don't fire the signal twice.

	_held_items[item_id] = true
	item_added.emit(item_id, display_name)


func has_item(item_id: String) -> bool:
	return _held_items.has(item_id)


func get_all_items() -> Array:
	# .keys() returns the Dictionary's keys as an Array -- since we
	# only ever store item IDs as keys, this gives us a plain list
	# of everything the player is carrying (handy for the HUD/journal
	# to loop over and display).
	return _held_items.keys()
