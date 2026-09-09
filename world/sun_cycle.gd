extends DirectionalLight3D
## ============================================================
##  SUN_CYCLE.GD
##  Purely cosmetic: slowly drifts the sun's pitch back and forth
##  between two angles (never below the horizon, so lighting never
##  goes to full night -- there's no star field or night sky to swap
##  to) and gently shifts its color between warm and cool. Gives the
##  outdoor scene a slow "passing of time" feel without needing a
##  real day/night system.
##
##  Purely additive: set `enabled = false` in the Inspector to freeze
##  the sun at whatever angle you left it at in the editor.
## ============================================================

@export var enabled: bool = true
@export var cycle_seconds: float = 240.0   # time for one full back-and-forth sweep
@export var min_pitch_deg: float = -20.0   # sun high overhead
@export var max_pitch_deg: float = -68.0   # sun low, long shadows
@export var warm_color: Color = Color(1.0, 0.95, 0.85)
@export var cool_color: Color = Color(0.82, 0.88, 1.0)

var _t: float = 0.0


func _process(delta: float) -> void:
	if not enabled:
		return

	_t += delta
	# (sin(...) + 1) / 2 rescales the wave from [-1, 1] to [0, 1], which
	# is a nicer range to lerp() with than raw sine.
	var f: float = (sin(_t * TAU / cycle_seconds) + 1.0) / 2.0

	rotation_degrees.x = lerp(min_pitch_deg, max_pitch_deg, f)
	light_color = warm_color.lerp(cool_color, f)
