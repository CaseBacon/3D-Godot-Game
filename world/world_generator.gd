extends Node3D
## ============================================================
##  WORLD_GENERATOR.GD
##  Builds the entire outdoor environment at runtime: a rolling
##  heightmap terrain, a lake, a climbable ruined watchtower, and
##  scattered trees/rocks -- instead of hand-placing thousands of
##  vertices in the .tscn file, everything is generated in code from
##  a handful of tunable @export values (visible in the Inspector on
##  whichever node this script is attached to).
##
##  Why generate at runtime rather than author it by hand: every
##  other system in this file (the lake basin, the tower's footing,
##  what counts as "too close to plant a tree") all need to agree on
##  the SAME terrain height at a given (x, z). Computing that height
##  from one function (get_height, below) and reusing it everywhere
##  guarantees the lake actually sits in its hollow, the tower
##  actually stands on solid ground, and trees never float above or
##  clip into the hillside -- something that's easy to get subtly
##  wrong when hand-placing a Y coordinate and hoping it matches.
##
##  The existing indoor room (WallNorth, the vault, etc. -- see
##  world.tscn) keeps its original hand-authored coordinates, which
##  is why `flat_center`/`flat_half` below describes a flat
##  rectangle sized to match that room's footprint: the terrain
##  blends to dead-flat under and around it, so nothing has to move.
##
##  TERRAIN RENDERING: the ground itself is drawn by the Terrain3D
##  addon (see _build_terrain below) instead of a hand-built
##  ArrayMesh. get_height() is unchanged and still the single source
##  of truth -- _build_terrain just bakes it into a heightmap image
##  and hands it to Terrain3D, so the same terrain_seed still
##  reproduces the same landscape, and the lake/tower/vegetation
##  code below didn't need to change at all.
## ============================================================

@export_group("Terrain")
@export var terrain_size: float = 160.0
@export var height_scale: float = 5.5
@export var terrain_seed: int = 777

## --- "Hand-sculpted look" tuning ---
## These four values are the whole trick. Plain noise looks like
## noise -- regular bumps on an invisible grid. Real, hand-sculpted
## terrain doesn't: ridgelines bend, valleys wander, nothing lines
## up. We fake that with two techniques (both explained in detail
## right above get_height() below): DOMAIN WARPING (warp_frequency /
## warp_strength) bends the coordinates before we sample height, and
## RIDGED NOISE (ridge_frequency / ridge_strength / ridge_threshold)
## folds the noise into sharp creases on higher ground, like real
## mountain ridges rising out of smooth valleys.
@export var macro_frequency: float = 0.006     ## the big hills/valleys shape
@export var detail_frequency: float = 0.05     ## small surface bumps, underfoot roughness
@export var detail_strength: float = 0.35      ## how much those small bumps matter vs the big shape
@export var warp_frequency: float = 0.01
@export var warp_strength: float = 18.0        ## bigger = more bending/curving, 0 = off
@export var ridge_frequency: float = 0.02
@export var ridge_strength: float = 0.6        ## how strongly ridges override smooth hills, 0 = off
@export var ridge_threshold: float = 0.15      ## how high ground must be before ridges kick in

@export_group("Flatten (matches the indoor room's footprint)")
@export var flat_center: Vector2 = Vector2(0.0, -7.0)
@export var flat_half: Vector2 = Vector2(7.0, 16.0)
@export var flat_blend: float = 10.0
@export var flat_height: float = 0.5   # matches the old Floor mesh's top surface

@export_group("Lake")
@export var lake_center: Vector2 = Vector2(-26.0, -30.0)
@export var lake_radius: float = 11.0
@export var lake_blend: float = 7.0
@export var lake_depth: float = 3.2
@export var water_level: float = 0.05

@export_group("Ruined watchtower")
@export var tower_pos: Vector2 = Vector2(34.0, -46.0)
@export var tower_segments: int = 4
@export var tower_rise_per_segment: float = 3.0
@export var tower_radius: float = 4.4

@export_group("Vegetation")
@export var tree_count: int = 140
@export var rock_count: int = 55
@export var scatter_seed: int = 99

@export_group("Terrain source")
## Once you've added a Terrain3D node in the editor (sibling of this
## node, named "Terrain3D") and sculpted it by hand, leave this ON --
## get_height() below will read real heights straight off it, so the
## lake/tower/vegetation placement always matches whatever you've
## sculpted. Turn it OFF only if you want to go back to the old
## fully-procedural noise-based ground with no Terrain3D node at all.
@export var use_hand_placed_terrain: bool = true

var _terrain: Terrain3D = null

## Five separate noise fields, each with ONE job (see get_height()
## below for how they combine). Using different seeds (terrain_seed
## + 1, +2, etc.) for each means they're all different-looking noise
## patterns even though they're all driven by the single
## terrain_seed value -- so changing terrain_seed still regenerates
## the *entire* landscape as one consistent, reproducible package.
var _macro_noise := FastNoiseLite.new()    ## the big hills and valleys
var _detail_noise := FastNoiseLite.new()   ## small surface bumps
var _warp_noise_x := FastNoiseLite.new()   ## domain warp, x-direction nudge
var _warp_noise_z := FastNoiseLite.new()   ## domain warp, z-direction nudge
var _ridge_noise := FastNoiseLite.new()    ## folded noise for mountain ridges
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_macro_noise.seed = terrain_seed
	_macro_noise.frequency = macro_frequency
	_macro_noise.fractal_octaves = 3

	_detail_noise.seed = terrain_seed + 1
	_detail_noise.frequency = detail_frequency
	_detail_noise.fractal_octaves = 3

	_warp_noise_x.seed = terrain_seed + 2
	_warp_noise_x.frequency = warp_frequency
	_warp_noise_z.seed = terrain_seed + 3
	_warp_noise_z.frequency = warp_frequency

	_ridge_noise.seed = terrain_seed + 4
	_ridge_noise.frequency = ridge_frequency
	_ridge_noise.fractal_octaves = 4

	_rng.seed = scatter_seed

	if use_hand_placed_terrain:
		_terrain = get_parent().get_node_or_null("Terrain3D") as Terrain3D
		if _terrain == null:
			push_warning("WorldGenerator: use_hand_placed_terrain is on but no sibling " +
				"\"Terrain3D\" node was found -- falling back to the procedural noise " +
				"ground until you add one. See README_TERRAIN3D_SETUP.md.")

	if _terrain == null:
		_build_terrain()

	_build_lake()
	_build_tower()
	_scatter_trees()
	_scatter_rocks()
	_spawn_fireflies()


## ------------------------------------------------------------
##  HEIGHT FIELD
##  The single source of truth for "how tall is the ground at this
##  (x, z)?". Everything else in this file calls this instead of
##  sampling noise directly, so the whole world agrees on the same
##  ground. When a hand-placed, hand-sculpted Terrain3D node is
##  present (see use_hand_placed_terrain above), this reads real
##  heights straight off it -- so the lake basin, tower footing, and
##  tree/rock scatter all automatically follow whatever you sculpt in
##  the editor, with no need to touch this script again. Without one,
##  it falls back to the original noise formula.
## ------------------------------------------------------------
func get_height(x: float, z: float) -> float:
	if _terrain != null:
		return _terrain.data.get_height(Vector3(x, 0.0, z))

	# ---- STEP 1: Domain warp --------------------------------------
	# Before we even ask "how tall is the ground at (x, z)?", we
	# sneakily change what (x, z) means. Two low-frequency noise
	# fields (_warp_noise_x/_warp_noise_z) tell us "shift this point
	# a bit this way, a bit that way" -- a different, smoothly-
	# varying shift at every location. Sample the SAME macro noise
	# at this wobbled position instead of the real one, and straight
	# lines/grids in the noise pattern turn into curves and bends,
	# the same way a river bends instead of running dead straight.
	# This is the single biggest reason hand-painted terrain looks
	# "designed" and raw noise looks "generated."
	var warp_x: float = _warp_noise_x.get_noise_2d(x, z) * warp_strength
	var warp_z: float = _warp_noise_z.get_noise_2d(x, z) * warp_strength
	var wx: float = x + warp_x
	var wz: float = z + warp_z

	# ---- STEP 2: Macro shape (the big hills and valleys) ----------
	var macro: float = _macro_noise.get_noise_2d(wx, wz)  # -1..1

	# ---- STEP 3: Ridged noise (mountain-y ridgelines) --------------
	# Ordinary noise gives smooth rolling bumps everywhere -- fine
	# for gentle hills, but real high ground usually has sharper
	# creases and ridgelines. Trick: take the absolute value of a
	# noise field (folding negative bumps up to positive, like
	# creasing a piece of paper in half) and flip it, so what used to
	# be smooth peaks and valleys becomes sharp ridges and grooves.
	# smoothstep() below only blends this in once the macro terrain
	# is already above ridge_threshold, so low valley floors stay
	# smooth and only the higher hills sprout craggy ridges -- just
	# like a real mountain range rising out of a flat valley.
	var ridge_raw: float = 1.0 - abs(_ridge_noise.get_noise_2d(wx, wz))  # 0..1, creased
	var ridged_signed: float = ridge_raw * 2.0 - 1.0                    # back to -1..1
	var ridge_amount: float = smoothstep(ridge_threshold, ridge_threshold + 0.3, macro)
	var shaped: float = lerp(macro, ridged_signed, ridge_amount * ridge_strength)

	# ---- STEP 4: Fine detail (small bumps underfoot) ---------------
	# Sampled WITHOUT the warp and at a much higher frequency than
	# the macro shape -- this is just texture, small enough that it
	# adds roughness without fighting the big hills/valleys/ridges
	# already decided above.
	var detail: float = _detail_noise.get_noise_2d(x, z)
	var combined: float = shaped + detail * detail_strength

	var rolling: float = flat_height + combined * height_scale

	# Blend down to dead-flat inside the room's footprint rectangle.
	var rect_d: float = _rounded_rect_sdf(Vector2(x, z), flat_center, flat_half)
	var flat_t: float = smoothstep(0.0, 1.0, clamp(rect_d / flat_blend, 0.0, 1.0))
	var h: float = lerp(flat_height, rolling, flat_t)

	# Carve the lake basin into whatever height we ended up with.
	var lake_d: float = Vector2(x, z).distance_to(lake_center) - lake_radius
	var lake_t: float = smoothstep(0.0, 1.0, clamp(lake_d / lake_blend, 0.0, 1.0))
	h = lerp(h - lake_depth, h, lake_t)

	return h


func _rounded_rect_sdf(p: Vector2, center: Vector2, half: Vector2) -> float:
	var d: Vector2 = (p - center).abs() - half
	var outside := Vector2(max(d.x, 0.0), max(d.y, 0.0))
	return outside.length() + min(max(d.x, d.y), 0.0)


## ------------------------------------------------------------
##  TERRAIN (Terrain3D)
##  Bakes get_height() into a heightmap image and hands it to the
##  Terrain3D addon, which then owns rendering (a proper clipmap
##  mesh with real LOD, not one giant fixed-resolution grid),
##  texture blending, and collision. terrain_seed still fully
##  determines the shape -- this is still 100% runtime-generated,
##  just rendered by a much better renderer than a raw ArrayMesh.
##
##  Texturing: two small procedurally-speckled swatches (grass,
##  rock) are registered and, via a uniform control map (see
##  _encode_control below), handed to Terrain3D's autoshader, which
##  blends them by slope -- the same "flat = grass, steep = rock"
##  logic the old per-vertex coloring used. A third "Sand" slot is
##  registered but not wired up: the autoshader only blends 2
##  textures at a time, so the old waterline sand band isn't
##  reproduced automatically. To get sand at the shoreline, open the
##  Terrain3D dock in the editor (bottom panel, after selecting the
##  Terrain3D node) and paint texture id 2 along the lake edge with
##  the Spray Texture tool -- painting there disables the autoshader
##  only in the area you paint.
## ------------------------------------------------------------
func _build_terrain() -> void:
	# Rendered as a plain hand-built ArrayMesh -- no Terrain3D addon
	# involved. Terrain3D expects its material/asset/data resources to
	# be saved to disk and edited in the editor; built purely from a
	# script with nothing ever saved to a file, it crashed trying to
	# auto-load a resource the moment it entered the tree (and, before
	# that crash, was falling back to a flat gray "material failed to
	# load" placeholder). A plain mesh with per-vertex slope-based
	# coloring (green = flat/grass, gray = steep/rock, sandy near the
	# waterline) sidesteps all of that -- same visual idea, zero addon
	# dependency. Collision is unrelated and handled separately in
	# _build_terrain_collision, using the same height field.
	var half: float = terrain_size / 2.0
	var row: int = int(terrain_size) + 1

	var heights := PackedFloat32Array()
	heights.resize(row * row)
	for j in range(row):
		for i in range(row):
			heights[j * row + i] = get_height(-half + i, -half + j)

	var grass := Color(0.30, 0.46, 0.20)
	var rock := Color(0.5, 0.49, 0.47)
	var sand := Color(0.78, 0.72, 0.54)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(row * row)
	normals.resize(row * row)
	colors.resize(row * row)

	for j in range(row):
		for i in range(row):
			var idx: int = j * row + i
			var x: float = -half + i
			var z: float = -half + j
			var h: float = heights[idx]

			# Central-difference normal from neighboring samples --
			# steeper slopes (lower normal.y) shift the vertex color
			# from grass toward rock, same logic the old per-vertex
			# terrain coloring used before the Terrain3D detour.
			var hl: float = heights[j * row + max(i - 1, 0)]
			var hr: float = heights[j * row + min(i + 1, row - 1)]
			var hd: float = heights[max(j - 1, 0) * row + i]
			var hu: float = heights[min(j + 1, row - 1) * row + i]
			var normal := Vector3(hl - hr, 2.0, hd - hu).normalized()

			var slope: float = 1.0 - normal.y
			var col: Color = grass.lerp(rock, clamp(slope * 2.5, 0.0, 1.0))
			if h < water_level + 0.35:
				col = col.lerp(sand, 0.6)

			verts[idx] = Vector3(x, h, z)
			normals[idx] = normal
			colors[idx] = col

	var indices := PackedInt32Array()
	indices.resize((row - 1) * (row - 1) * 6)
	var ii: int = 0
	for j in range(row - 1):
		for i in range(row - 1):
			var a: int = j * row + i
			var b: int = j * row + i + 1
			var c: int = (j + 1) * row + i
			var d: int = (j + 1) * row + i + 1
			indices[ii] = a; ii += 1
			indices[ii] = b; ii += 1
			indices[ii] = c; ii += 1
			indices[ii] = b; ii += 1
			indices[ii] = d; ii += 1
			indices[ii] = c; ii += 1

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	add_child(mi)

	_build_terrain_collision(row, half)


## ------------------------------------------------------------
##  TERRAIN COLLISION
##  A plain StaticBody3D + HeightMapShape3D built straight from
##  get_height() -- a built-in Godot physics shape, unrelated to the
##  mesh above, so collision keeps working no matter what the visuals
##  are doing. map_data is row-major (index = z_index * map_width +
##  x_index) and the shape is centered on its body's origin, spanning
##  map_width-1 units in X and map_depth-1 units in Z -- exactly the
##  -half..+half range get_height() was sampled over above, so it
##  lines up with the rendered terrain with no extra offset needed.
## ------------------------------------------------------------
func _build_terrain_collision(row: int, half: float) -> void:
	var map_data := PackedFloat32Array()
	map_data.resize(row * row)
	for j in range(row):
		for i in range(row):
			var x: float = -half + i
			var z: float = -half + j
			map_data[j * row + i] = get_height(x, z)

	var shape := HeightMapShape3D.new()
	shape.map_width = row
	shape.map_depth = row
	shape.map_data = map_data

	var body := StaticBody3D.new()
	body.name = "TerrainCollision"

	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)

	add_child(body)


## ------------------------------------------------------------
##  LAKE
##  A circular disc (not a square plane) sized to match the lake
##  basin's rounded shape, with a small animated shader instead of a
##  static material -- vertex.y gets a gentle sine-wave ripple over
##  time, and a fresnel term brightens/lightens the color toward the
##  shoreline edge (deep-water color in the middle, lighter at
##  grazing angles), which reads as real water instead of a flat
##  colored square. cull_disabled since it's a thin single-sided
##  disc and could plausibly be seen from slightly below (e.g. at the
##  shoreline) as well as above.
## ------------------------------------------------------------
func _build_lake() -> void:
	var radius: float = lake_radius + lake_blend * 0.6
	var segments: int = 48

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))
	for s in range(segments + 1):
		var a: float = s * TAU / segments
		verts.append(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))

	var indices := PackedInt32Array()
	for s in range(segments):
		indices.append(0)
		indices.append(s + 1)
		indices.append(s + 2)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.16, 0.42, 0.5, 0.82);
uniform vec4 deep_color : source_color = vec4(0.05, 0.16, 0.22, 0.9);
uniform float wave_speed = 0.6;
uniform float wave_height = 0.05;
uniform float wave_scale = 1.2;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(world_pos.x * wave_scale + TIME * wave_speed)
		* cos(world_pos.z * wave_scale * 0.8 + TIME * wave_speed * 0.7);
	VERTEX.y += wave * wave_height;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep_color.rgb, water_color.rgb, fresnel);
	ALPHA = mix(deep_color.a, water_color.a, fresnel);
	ROUGHNESS = 0.05;
	METALLIC = 0.3;
	EMISSION = deep_color.rgb * 0.15;
}
"""

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("water_color", Color(0.16, 0.42, 0.5, 0.82))
	mat.set_shader_parameter("deep_color", Color(0.05, 0.16, 0.22, 0.9))

	var mi := MeshInstance3D.new()
	mi.name = "Lake"
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(lake_center.x, water_level, lake_center.y)
	add_child(mi)


## ------------------------------------------------------------
##  RUINED WATCHTOWER
##  A climbable landmark: a stone pillar core with a switchback ramp
##  staircase winding around it (each segment inclined well under
##  the player's floor_max_angle, so it's walkable, not a wall to
##  bump into). A collectible + lore note wait at the top as an
##  exploration reward.
## ------------------------------------------------------------
func _build_tower() -> void:
	var base_h: float = get_height(tower_pos.x, tower_pos.y)

	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.55, 0.53, 0.49)
	stone_mat.roughness = 0.92

	var tower_root := Node3D.new()
	tower_root.name = "RuinedTower"
	add_child(tower_root)

	# Central pillar, purely decorative mass -- narrower than
	# tower_radius so it never blocks the ramp path around it.
	var pillar_h: float = tower_segments * tower_rise_per_segment + 2.5
	var pillar := StaticBody3D.new()
	pillar.position = Vector3(tower_pos.x, base_h + pillar_h / 2.0, tower_pos.y)
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 1.3
	pillar_mesh.bottom_radius = 1.6
	pillar_mesh.height = pillar_h
	pillar_mesh.radial_segments = 8
	var pillar_mi := MeshInstance3D.new()
	pillar_mi.mesh = pillar_mesh
	pillar_mi.material_override = stone_mat
	var pillar_cs := CollisionShape3D.new()
	var pillar_shape := CylinderShape3D.new()
	pillar_shape.radius = 1.6
	pillar_shape.height = pillar_h
	pillar_cs.shape = pillar_shape
	pillar.add_child(pillar_mi)
	pillar.add_child(pillar_cs)
	tower_root.add_child(pillar)

	# Switchback ramps: each one rotates 90 degrees further around
	# the pillar and climbs tower_rise_per_segment meters, connected
	# by small square landings at each turn.
	var pts: Array[Vector3] = []
	for i in range(tower_segments + 1):
		var ang: float = i * (PI / 2.0)
		pts.append(Vector3(
			tower_pos.x + cos(ang) * tower_radius,
			base_h + i * tower_rise_per_segment,
			tower_pos.y + sin(ang) * tower_radius
		))

	for i in range(tower_segments):
		_add_ramp(pts[i], pts[i + 1], 2.0, 0.35, stone_mat, tower_root)
		var landing_size: float = 3.0 if i < tower_segments - 1 else 5.0
		_add_landing(pts[i + 1], landing_size, 0.35, stone_mat, tower_root)

	# Reward at the top: a collectible and a note, reusing the exact
	# same scripts every other pickup/note in the game uses.
	var top: Vector3 = pts[pts.size() - 1]
	_spawn_collectible(
		top + Vector3(0.0, 0.5, 0.0),
		"sunstone",
		"Sunstone",
		"Press E to pick up the Sunstone",
		"You've reached the old watchtower. The valley is yours to explore."
	)
	_spawn_note(
		top + Vector3(1.4, 0.9, 0.0),
		"Press E to read the weathered inscription",
		"\"Here the watchers stood, counting travelers on the road below.\n" \
		+ "The road is gone now. Only the valley remains.\""
	)


func _add_ramp(a: Vector3, b: Vector3, width: float, thickness: float, mat: Material, parent: Node3D) -> void:
	var forward: Vector3 = (b - a).normalized()
	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	var up: Vector3 = right.cross(forward).normalized()

	var mid: Vector3 = (a + b) / 2.0
	var length: float = a.distance_to(b)

	var body := StaticBody3D.new()
	body.transform = Transform3D(Basis(right, up, forward), mid)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, thickness, length)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	cs.shape = shape
	body.add_child(cs)

	parent.add_child(body)


func _add_landing(center: Vector3, size: float, thickness: float, mat: Material, parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.position = center - Vector3(0.0, thickness / 2.0, 0.0)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(size, thickness, size)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	cs.shape = shape
	body.add_child(cs)

	parent.add_child(body)


## ------------------------------------------------------------
##  COLLECTIBLE / NOTE HELPERS
##  Both reuse the project's existing interactable.gd / note.gd
##  scripts (the same ones the indoor puzzle room uses) so they get
##  the exact same tested pickup/read behavior for free.
## ------------------------------------------------------------
const InteractableScript := preload("res://interactables/interactable.gd")
const NoteScript := preload("res://interactables/note.gd")


func _spawn_collectible(pos: Vector3, item_id: String, display_name: String, prompt: String, objective: String) -> void:
	var body := StaticBody3D.new()
	body.name = display_name.replace(" ", "")
	body.set_script(InteractableScript)
	body.prompt_text = prompt
	body.is_collectible = true
	body.item_id = item_id
	body.item_display_name = display_name
	body.objective_on_pickup = objective
	body.position = pos

	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.72, 0.18)
	mat.metallic = 0.7
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.65, 0.1)
	mat.emission_energy_multiplier = 1.3
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.28
	cs.shape = shape
	body.add_child(cs)

	add_child(body)


func _spawn_note(pos: Vector3, prompt: String, text: String) -> void:
	var body := StaticBody3D.new()
	body.name = "Note"
	body.set_script(NoteScript)
	body.prompt_text = prompt
	body.note_text = text
	body.position = pos
	body.rotation_degrees = Vector3(-15.0, -90.0, 0.0)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.35, 0.05)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.89, 0.75)
	mat.roughness = 0.9
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	cs.shape = shape
	body.add_child(cs)

	add_child(body)


## ------------------------------------------------------------
##  VEGETATION
##  Trees are rendered via two MultiMeshInstance3D nodes (trunks +
##  foliage sharing the same per-instance transforms, foliage offset
##  upward) -- visual-only, no per-tree collision, since a forest of
##  a hundred-plus individual physics bodies would be overkill for
##  what's meant to be scenery. Rocks are few enough (dozens, not
##  hundreds) that they get real collision, so they can double as
##  waist-high obstacles/cover while exploring.
## ------------------------------------------------------------
func _scatter_trees() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.14
	trunk_mesh.bottom_radius = 0.22
	trunk_mesh.height = 2.2
	trunk_mesh.radial_segments = 6
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.36, 0.25, 0.16)
	trunk_mat.roughness = 0.95
	trunk_mesh.material = trunk_mat

	var foliage_mesh := CylinderMesh.new()
	foliage_mesh.top_radius = 0.0
	foliage_mesh.bottom_radius = 1.5
	foliage_mesh.height = 2.8
	foliage_mesh.radial_segments = 7
	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.albedo_color = Color(0.16, 0.4, 0.19)
	foliage_mat.roughness = 0.85
	foliage_mesh.material = foliage_mat

	var placements: Array[Transform3D] = []
	var attempts: int = 0
	var half: float = terrain_size / 2.0 - 4.0
	while placements.size() < tree_count and attempts < tree_count * 15:
		attempts += 1
		var x: float = _rng.randf_range(-half, half)
		var z: float = _rng.randf_range(-half, half)
		if _blocked(x, z, 3.0):
			continue
		var h: float = get_height(x, z)
		if h < water_level + 1.0:
			continue
		var s: float = _rng.randf_range(0.8, 1.4)
		var rot: float = _rng.randf_range(0.0, TAU)
		placements.append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), Vector3(x, h, z)))

	var trunk_mm := MultiMesh.new()
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	trunk_mm.mesh = trunk_mesh
	trunk_mm.instance_count = placements.size()

	var foliage_mm := MultiMesh.new()
	foliage_mm.transform_format = MultiMesh.TRANSFORM_3D
	foliage_mm.mesh = foliage_mesh
	foliage_mm.instance_count = placements.size()

	for i in placements.size():
		var t: Transform3D = placements[i]
		trunk_mm.set_instance_transform(i, t.translated_local(Vector3(0.0, trunk_mesh.height / 2.0, 0.0)))
		var foliage_y: float = trunk_mesh.height + foliage_mesh.height / 2.0 - 0.3
		foliage_mm.set_instance_transform(i, t.translated_local(Vector3(0.0, foliage_y, 0.0)))

	var trunk_inst := MultiMeshInstance3D.new()
	trunk_inst.name = "TreeTrunks"
	trunk_inst.multimesh = trunk_mm
	add_child(trunk_inst)

	var foliage_inst := MultiMeshInstance3D.new()
	foliage_inst.name = "TreeFoliage"
	foliage_inst.multimesh = foliage_mm
	add_child(foliage_inst)


func _scatter_rocks() -> void:
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.52, 0.5, 0.47)
	rock_mat.roughness = 0.9

	var rocks_root := Node3D.new()
	rocks_root.name = "Rocks"
	add_child(rocks_root)

	var half: float = terrain_size / 2.0 - 4.0
	var placed: int = 0
	var attempts: int = 0
	while placed < rock_count and attempts < rock_count * 15:
		attempts += 1
		var x: float = _rng.randf_range(-half, half)
		var z: float = _rng.randf_range(-half, half)
		if _blocked(x, z, 2.5):
			continue
		var h: float = get_height(x, z)

		var sx: float = _rng.randf_range(0.4, 1.1)
		var sy: float = _rng.randf_range(0.3, 0.8)
		var sz: float = _rng.randf_range(0.4, 1.1)
		var rot: float = _rng.randf_range(0.0, TAU)

		var body := StaticBody3D.new()
		body.transform = Transform3D(Basis(Vector3.UP, rot), Vector3(x, h + sy / 2.0, z))

		var mesh := BoxMesh.new()
		mesh.size = Vector3(sx, sy, sz)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = rock_mat
		body.add_child(mi)

		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = mesh.size
		cs.shape = shape
		body.add_child(cs)

		rocks_root.add_child(body)
		placed += 1


func _blocked(x: float, z: float, margin: float) -> bool:
	if _rounded_rect_sdf(Vector2(x, z), flat_center, flat_half) < margin + 2.0:
		return true
	if Vector2(x, z).distance_to(lake_center) < lake_radius + lake_blend * 0.6 + margin:
		return true
	if Vector2(x, z).distance_to(tower_pos) < tower_radius + 6.0:
		return true
	return false


## ------------------------------------------------------------
##  FIREFLIES
##  A little bit of magic near the lake -- small glowing particles
##  drifting slowly, always on (not tied to sun_cycle.gd's angle)
##  so the lakeside always has a bit of sparkle.
## ------------------------------------------------------------
func _spawn_fireflies() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "Fireflies"
	particles.amount = 40
	particles.lifetime = 5.0
	particles.preprocess = 5.0
	particles.position = Vector3(lake_center.x, water_level + 1.4, lake_center.y)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18.0, 2.2, 18.0)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.angular_velocity_min = -20.0
	pm.angular_velocity_max = 20.0
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	particles.process_material = pm

	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.4)
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	particles.draw_pass_1 = mesh

	add_child(particles)
