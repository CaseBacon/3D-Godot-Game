extends CanvasLayer
## ============================================================
##  HUD.GD
##  Controls the on-screen UI: the crosshair, the "Press E to..."
##  prompt, pickup/objective messages, and two full-panel overlays --
##  a numeric code-entry keypad and a readable-note display -- that
##  take over player input while they're open (see GameManager's
##  input_locked and player.gd's checks on it).
## ============================================================

# @onready grabs a reference to the PromptLabel node once the scene is
# ready, so we don't have to look it up by path every time we use it.
@onready var prompt_label: Label = $PromptLabel
@onready var pickup_label: Label = $PickupLabel
@onready var objective_label: Label = $ObjectiveLabel

@onready var code_panel: Panel = $CodePanel
@onready var code_display: Label = $CodePanel/CodeDisplay
@onready var code_feedback: Label = $CodePanel/CodeFeedback

@onready var note_panel: Panel = $NotePanel
@onready var note_text_label: Label = $NotePanel/NoteText

# How many seconds a "Picked up: X" message stays on screen before
# hiding itself again. Counts down in _process below.
const PICKUP_MESSAGE_DURATION := 2.0
var _pickup_timer := 0.0

# --- Code entry state ---
var _entered_code: String = ""
var _active_lock: CombinationLock = null  # whichever lock opened the panel; see open_code_entry. Typed as CombinationLock (not Node) so the call in _submit_code below is fully type-checked.


func _ready() -> void:
	# Tag ourselves as "hud" so the player script can find us with
	# get_tree().get_first_node_in_group("hud") without needing to know
	# exactly where in the scene tree we live.
	add_to_group("hud")

	# The prompt starts hidden -- it only appears when the player is
	# actually looking at something interactable.
	prompt_label.visible = false
	pickup_label.visible = false
	code_panel.visible = false
	note_panel.visible = false

	# Unlike the prompt/pickup labels, the objective label is ALWAYS
	# visible -- it's a permanent reminder of the current goal, not a
	# momentary popup. Set it once here from whatever GameManager's
	# objective already is (it has a default even before anything
	# happens -- see game_manager.gd), then keep it in sync via the
	# objective_changed signal below.
	objective_label.text = "Objective: %s" % GameManager.current_objective

	# Inventory and GameManager are Autoloads (see systems/) so they
	# already exist and are safe to connect to as soon as the HUD is
	# ready -- we don't need to go find them or wait for them to load.
	Inventory.item_added.connect(_on_item_added)
	GameManager.objective_changed.connect(_on_objective_changed)


func _process(delta: float) -> void:
	# Simple countdown timer: once a pickup message has been showing
	# for PICKUP_MESSAGE_DURATION seconds, hide it again. Using
	# _process + a float timer avoids needing a whole Timer node for
	# something this small.
	if pickup_label.visible:
		_pickup_timer -= delta
		if _pickup_timer <= 0.0:
			pickup_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	# Only ever look at key events here, and only while one of our
	# panels actually owns input -- otherwise this would double-handle
	# every keypress in the game alongside player.gd.
	if not (event is InputEventKey and event.pressed):
		return

	if note_panel.visible:
		# Any key dismisses a note -- it's just text, there's nothing
		# to input, so we don't need to be picky about which key.
		_close_note()
		return

	if code_panel.visible:
		_handle_code_key(event.keycode)


func _handle_code_key(keycode: int) -> void:
	# KEY_0..KEY_9 are consecutive constants in Godot, so subtracting
	# KEY_0 from any of them gives the actual digit (0-9) as an int,
	# which we then turn into the matching character with str().
	if keycode >= KEY_0 and keycode <= KEY_9:
		_entered_code += str(keycode - KEY_0)
		code_display.text = _entered_code
	elif keycode == KEY_BACKSPACE:
		_entered_code = _entered_code.substr(0, _entered_code.length() - 1)
		code_display.text = _entered_code
	elif keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		_submit_code()
	elif keycode == KEY_ESCAPE:
		_close_code_entry()


func _submit_code() -> void:
	# _active_lock is whatever CombinationLock called open_code_entry
	# below -- it owns the "is this code correct?" logic (see
	# combination_lock.gd's _on_code_submitted), the HUD only cares
	# about displaying the result.
	var correct: bool = _active_lock._on_code_submitted(_entered_code)
	if correct:
		code_feedback.text = "Correct!"
		# A short pause so the player actually sees "Correct!" before
		# the panel closes, rather than it vanishing instantly.
		await get_tree().create_timer(0.6).timeout
		_close_code_entry()
	else:
		code_feedback.text = "Wrong code -- try again"
		_entered_code = ""
		code_display.text = ""


func open_code_entry(lock: CombinationLock) -> void:
	_active_lock = lock
	_entered_code = ""
	code_display.text = ""
	code_feedback.text = ""
	code_panel.visible = true
	GameManager.lock_input()


func _close_code_entry() -> void:
	code_panel.visible = false
	_active_lock = null
	GameManager.unlock_input()


func show_note(text: String) -> void:
	note_text_label.text = text
	note_panel.visible = true
	GameManager.lock_input()


func _close_note() -> void:
	note_panel.visible = false
	GameManager.unlock_input()


func _on_item_added(_item_id: String, display_name: String) -> void:
	pickup_label.text = "Picked up: %s" % display_name
	pickup_label.visible = true
	_pickup_timer = PICKUP_MESSAGE_DURATION


func _on_objective_changed(new_objective: String) -> void:
	objective_label.text = "Objective: %s" % new_objective


func show_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = true


func hide_prompt() -> void:
	prompt_label.visible = false
