extends Node
## ============================================================
##  GAME_MANAGER.GD  (Autoload / Singleton)
##  This script is registered as an "Autoload" in Project Settings,
##  which means Godot creates ONE instance of it automatically when
##  the game starts, and it stays alive for the entire game -- even
##  when you change scenes. Any script anywhere can talk to it just
##  by typing "GameManager", no need to find or reference it first.
##
##  This is the standard pattern for "global" game state: things
##  every system might care about, like whether you've won yet, or
##  what the player's current objective is. Keeping this in one
##  place avoids scattering the same state across a dozen scripts.
## ============================================================

# --- SIGNALS ---
# A signal is Godot's way of saying "something happened" without the
# thing that happened needing to know who's listening. Any script
# can do `GameManager.objective_changed.connect(my_function)` and
# my_function will run automatically whenever this signal fires.
signal objective_changed(new_objective: String)
signal game_won()

# --- STATE ---
# current_objective is just plain text shown in the HUD/journal to
# remind the player what they're meant to be doing right now.
var current_objective: String = "Explore the valley."

# When true, the player should ignore movement/look/interact input --
# used while a full-screen UI (a code-entry keypad, a readable note)
# is open, so the player doesn't walk into a wall or spin the camera
# while trying to type a code or read text. See player.gd's
# _unhandled_input and _physics_process, which both check this.
var input_locked: bool = false

# Tracks whether the player has already won, so we don't accidentally
# trigger the win sequence twice if the final door fires interact()
# more than once.
var _has_won: bool = false


func lock_input() -> void:
	input_locked = true


func unlock_input() -> void:
	input_locked = false


func set_objective(text: String) -> void:
	# Centralising this in one function (instead of every script
	# directly writing to current_objective) means anything that
	# needs to react to objective changes only has to listen to the
	# signal below -- it doesn't need to know WHO changed it or WHY.
	current_objective = text
	objective_changed.emit(text)


func win_game() -> void:
	if _has_won:
		return
	_has_won = true
	game_won.emit()
	print("You win!")
