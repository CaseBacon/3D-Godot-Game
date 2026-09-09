extends CharacterBody3D
## ============================================================
##  PLAYER.GD
##  Controls player movement, mouse look, jumping, sprinting, a bit
##  of camera "head bob" while walking, and interacting with objects
##  (like picking things up) via a forward raycast + the E key.
## ============================================================

# --- TUNABLE SETTINGS ---
# These show up in the Inspector panel when you click the Player node,
# so you can tweak how the character feels to control without touching code.

@export var move_speed: float = 5.0          # Normal walking speed (m/s)
@export var sprint_speed: float = 8.0        # Speed while holding Shift (m/s)
@export var jump_velocity: float = 4.5       # Upward "push" a jump gives
@export var mouse_sensitivity: float = 0.003 # How fast the camera turns with the mouse

# --- Head bob settings ---
# "Head bob" is the subtle up/down camera sway you see in most first-
# person games while walking -- it's what makes standing still feel
# different from moving.
@export var bob_frequency: float = 2.4   # How fast the bob cycles (higher = quicker wobble)
@export var bob_amplitude: float = 0.05  # How far up/down the camera moves, in meters

# --- Interaction settings ---
@export var interact_range: float = 3.0  # Max distance (meters) to interact with something

# Godot has a built-in gravity value set in Project Settings > Physics.
# We look it up once here so we don't have to fetch it every single frame.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# @onready shortcuts so we don't have to type get_node(...) repeatedly.
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay

# The "Body" node (see player.tscn) is an instanced copy of the whole
# animation library mini-scene, which brings its own AnimationPlayer
# along with it, containing clips like "Idle_Loop", "Walk_Loop",
# "Sprint_Loop", "Jump_Start", "Jump_Loop", "Jump_Land", etc. We
# don't know its exact node path in advance (Godot names it based on
# how the .glb was authored), so find_child() searches the whole
# Body sub-tree for a node literally named "AnimationPlayer" instead
# of hardcoding a path that could silently break if the import ever
# changes. `true` = search recursively into grandchildren too,
# `false` = don't require it to be an "owned" scene node.
@onready var body_anim: AnimationPlayer = find_child("AnimationPlayer", true, false) as AnimationPlayer

var _bob_time := 0.0
var _camera_base_y: float          # the camera's normal resting height
var _hud: Node = null              # reference to the HUD (found via group, see below)
var _current_target: Node = null   # whatever interactable object we're currently looking at

# --- Body animation state machine ---
# Jumping needs to play three DIFFERENT clips in sequence (takeoff,
# then an airborne loop, then landing) rather than just switching
# instantly, so it gets its own small state machine instead of being
# decided fresh every single frame like idle/walk/sprint are.
enum BodyState { GROUNDED, JUMP_START, JUMP_LOOP, JUMP_LAND }
var _body_state: BodyState = BodyState.GROUNDED


func _ready() -> void:
	# Lock and hide the mouse cursor, just like most first-person games.
	# Press Escape to free it again (see _unhandled_input below).
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Remember where the camera normally sits, so head bob has a
	# baseline to bob around instead of drifting away over time.
	_camera_base_y = camera.position.y

	# Groups are like tags you can stick on any node. hud.gd tags its
	# root node with "hud" in ITS _ready(). Here we ask the whole scene
	# tree "give me the first node tagged hud" instead of hardcoding a
	# path like get_node("../HUD") that would break if we ever moved
	# things around in the scene tree.
	_hud = get_tree().get_first_node_in_group("hud")

	if body_anim == null:
		push_warning("Player: no AnimationPlayer found under Body -- " +
			"the character will stay in its default T-pose. Check that " +
			"the animation library scene instanced correctly.")

	# Hide the Body model from this player's own camera, and make sure
	# it casts shadows. The camera sits inside Body's head/torso
	# (that's just where a first-person camera has to live), so
	# without the layer change you'd be staring at the backfaces of
	# your own mannequin's geometry -- "the inside of my head".
	# Camera3D.cull_mask in player.tscn is set to ignore render layer
	# 2, so putting every mesh under Body on layer 2 makes them
	# invisible to THIS camera while staying fully visible to any
	# other camera (a mirror, a future third-person view, etc) --
	# including the world's SunLight, whose shadow_enabled shadow pass
	# isn't affected by cull_mask at all, so the model still throws a
	# shadow onto the ground even though you can't see it directly.
	_set_layer_recursive($Body, 2)


func _set_layer_recursive(node: Node, layer_bit: int) -> void:
	# Imported .glb scenes can nest meshes arbitrarily deep (under a
	# Skeleton3D, inside sub-groups, etc.) and we don't want this to
	# break if the mannequin model is ever swapped out, so we walk
	# every descendant instead of hardcoding a path.
	if node is VisualInstance3D:
		node.layers = layer_bit
		# Imported skinned meshes sometimes come through from glTF
		# with shadow casting switched off (or set to "double sided"
		# shadow modes that can look wrong), so force it on explicitly
		# rather than trusting whatever the .glb import settings did.
		if node is GeometryInstance3D:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in node.get_children():
		_set_layer_recursive(child, layer_bit)


func _unhandled_input(event: InputEvent) -> void:
	# While a UI panel (code entry, a readable note) has focus,
	# GameManager.input_locked is true (see game_manager.gd) -- the
	# panel itself handles its own input via the HUD, so the player
	# should completely ignore look/interact/escape input until it
	# closes. Without this, typing a code's digits or reading a note
	# would also spin the camera or (worse) trigger another interact.
	if GameManager.input_locked:
		return

	# --- Mouse look ---
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, -PI / 2, PI / 2)

	# --- Escape key frees the mouse (handy for testing/debugging) ---
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# --- Interacting ---
	# If we press E while something interactable is in front of us
	# (tracked each physics frame in _update_interaction below), tell
	# that object to run its own interact() logic.
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		if _current_target != null:
			_current_target.interact()

			# interact() might open a HUD panel (a note, a code entry
			# keypad -- see note.gd/combination_lock.gd) whose own
			# _unhandled_input ALSO runs for this same physical
			# keypress, later in the same input dispatch, since
			# Godot doesn't stop an event from propagating just
			# because one node acted on it. Without this line, the
			# panel's own "any key closes it" logic (see hud.gd)
			# would see this very same E and instantly close
			# whatever interact() just opened -- which is exactly
			# why the note appeared to do nothing. Marking the event
			# handled stops it from reaching any other node.
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	# Same idea as the input_locked check above, but for continuous
	# per-frame movement: freeze the player in place (no walking,
	# jumping, gravity, or head bob) while a UI panel owns input.
	# Returning early here is simpler than threading an "if not
	# locked" check through every line below.
	if GameManager.input_locked:
		velocity = Vector3.ZERO
		return

	# --- Gravity ---
	if not is_on_floor():
		velocity.y -= gravity * delta

	# --- Jumping ---
	if Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = jump_velocity

	# --- Walking (W/A/S/D) ---
	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_physical_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	# --- Sprinting ---
	# Holding Shift just swaps which top speed we're aiming for; the
	# rest of the movement code below doesn't need to know or care.
	var target_speed := move_speed
	if Input.is_physical_key_pressed(KEY_SHIFT):
		target_speed = sprint_speed

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * target_speed
		velocity.z = direction.z * target_speed
	else:
		velocity.x = move_toward(velocity.x, 0, target_speed)
		velocity.z = move_toward(velocity.z, 0, target_speed)

	move_and_slide()

	_update_head_bob(delta)
	_update_interaction()
	_update_body_animation()


func _update_head_bob(delta: float) -> void:
	# How fast we're moving ALONG THE GROUND (ignoring vertical speed,
	# so jumping/falling doesn't make the camera bob).
	var ground_speed := Vector2(velocity.x, velocity.z).length()

	if is_on_floor() and ground_speed > 0.1:
		# Advance the bob timer faster the faster we're moving relative
		# to our normal walk speed, so sprinting bobs quicker than
		# walking. TAU is a full circle in radians (2 * PI); sin() of
		# that gives us a smooth up-down-up-down wave over time.
		_bob_time += delta * bob_frequency * (ground_speed / move_speed)
		camera.position.y = _camera_base_y + sin(_bob_time * TAU) * bob_amplitude
	else:
		# Not moving: smoothly settle back to resting height instead of
		# snapping instantly, which would look jarring.
		_bob_time = 0.0
		camera.position.y = lerp(camera.position.y, _camera_base_y, delta * 8.0)


func _update_interaction() -> void:
	# RayCast3D is a node that checks "what's the first solid thing in
	# a straight line from here?" -- basically a virtual laser pointer
	# aimed wherever the camera is looking (set up in player.tscn).
	# force_raycast_update() makes it check RIGHT NOW instead of
	# waiting for the next physics step, so the prompt feels instant.
	interact_ray.force_raycast_update()

	var new_target: Node = null
	if interact_ray.is_colliding():
		var collider := interact_ray.get_collider()
		# is_in_group checks the "interactable" tag every interactable
		# object wears (see interactable.gd). The distance check stops
		# you from "seeing" something interactable from clear across
		# the level, even if the ray happens to line up with it.
		if collider and collider.is_in_group("interactable"):
			if global_position.distance_to(collider.global_position) <= interact_range:
				new_target = collider

	_current_target = new_target

	# Tell the HUD what to show, if we found one back in _ready().
	if _hud:
		if _current_target:
			_hud.show_prompt(_current_target.get_prompt())
		else:
			_hud.hide_prompt()


## ------------------------------------------------------------
##  BODY ANIMATION
##  Decides which animation clip the visible character (Body, in
##  player.tscn) should be playing right now, based on movement --
##  idle standing still, walking, sprinting, or one of three jump
##  clips in sequence. This runs every physics frame, but calling
##  .play() on a clip that's ALREADY playing would restart it from
##  frame zero over and over (looking like it never moves), so
##  _play_body_anim() below only actually restarts a clip when it's
##  genuinely different from whatever's already playing.
## ------------------------------------------------------------
func _update_body_animation() -> void:
	if body_anim == null:
		return  # no AnimationPlayer was found -- nothing to drive.

	match _body_state:
		BodyState.GROUNDED:
			if not is_on_floor():
				# Just left the ground (jumped, or walked off a ledge).
				_body_state = BodyState.JUMP_START
				_play_body_anim("Jump_Start")
			else:
				_play_grounded_anim()

		BodyState.JUMP_START:
			if is_on_floor():
				# Left the ground and landed again before Jump_Start
				# even finished (e.g. a tiny step) -- skip straight to
				# the landing clip instead of waiting.
				_body_state = BodyState.JUMP_LAND
				_play_body_anim("Jump_Land")
			elif not body_anim.is_playing():
				# Takeoff clip finished naturally -- move on to the
				# looping airborne clip for however long we're falling.
				_body_state = BodyState.JUMP_LOOP
				_play_body_anim("Jump_Loop")

		BodyState.JUMP_LOOP:
			if is_on_floor():
				_body_state = BodyState.JUMP_LAND
				_play_body_anim("Jump_Land")

		BodyState.JUMP_LAND:
			if not body_anim.is_playing():
				# Landing clip finished -- back to normal ground rules.
				_body_state = BodyState.GROUNDED


func _play_grounded_anim() -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()

	if ground_speed < 0.1:
		_play_body_anim("Idle_Loop")
	elif Input.is_physical_key_pressed(KEY_SHIFT):
		_play_body_anim("Sprint_Loop")
	else:
		_play_body_anim("Walk_Loop")


func _play_body_anim(anim_name: String) -> void:
	if not body_anim.has_animation(anim_name):
		# Clip name doesn't exist in the library (typo, or the library
		# changed) -- warn once instead of silently doing nothing, and
		# don't touch playback so we don't stop whatever WAS playing.
		push_warning("Player: animation \"%s\" not found in the library." % anim_name)
		return

	if body_anim.current_animation == anim_name and body_anim.is_playing():
		return  # already playing this exact clip -- don't restart it.

	body_anim.play(anim_name)
