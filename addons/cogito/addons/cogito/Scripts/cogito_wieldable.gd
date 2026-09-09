extends Node3D
class_name CogitoWieldable

@export_group("General Wieldable Settings")
## Item resource that this wieldable refers to.
var item_reference : WieldableItemPD
## Visible parts of the wieldable. Used to hide/show on equip/unequip.
@export var wieldable_mesh : Node3D
## Which ammo type the Wieldable is currently using. Set by the WieldableItemPD
@export var current_ammo_type : int = 0
@export var audio_stream_player_3d: AudioStreamPlayer3D
@export var show_debug: bool = false

@export_group("Animations")
@export var animation_player: AnimationPlayer
@export var anim_equip: String = "equip"
@export var anim_unequip: String = "unequip"
@export var anim_action_primary: String = "action_primary"
@export var anim_action_secondary: String = "action_secondary"
@export var anim_reload: String = "reload"

var player_interaction_component : PlayerInteractionComponent

### Every wieldable needs the following functions:
### equip(_player_interaction_component), unequip(), action_primary(), action_secondary(), reload()

func _ready():
	if !audio_stream_player_3d:
		var players: Array[Node] = find_children("", "AudioStreamPlayer3D")
		if len(players): audio_stream_player_3d = players[0]
	
	if !animation_player:
		var anim_players: Array[Node] = find_children("", "AnimationPlayer")
		if len(anim_players): animation_player = anim_players[0]
		
	if wieldable_mesh:
		wieldable_mesh.hide()


# Function called when wieldable is unequipped.
func equip(_player_interaction_component: PlayerInteractionComponent):
	animation_player.play(anim_equip)
	player_interaction_component = _player_interaction_component


# Function called when wieldable is unequipped.
func unequip():
	animation_player.play(anim_unequip)


# Primary action called by the Player Interaction Component when flashlight is wielded.
func action_primary(_passed_item_reference:InventoryItemPD, _is_released: bool):
	pass


# Secondary action called by the Player Interaction Component when flashlight is wielded.
func action_secondary(_is_released: bool):
	pass


# Function called when wieldable reload is attempted
func reload():
	pass

# Function called when wieldable ammo change is attempted
func change_ammo(index: int):
	pass
	
# Override this with your debug stats
func debug(id, data):
	if player_interaction_component:
		player_interaction_component.player.debug(id, data)
