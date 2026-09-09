# 3D Godot Game

A first-person 3D exploration game built in Godot 4.7, made as a
hackathon-prep learning project — every script is heavily commented
so it doubles as a reference for how each system works.

## Controls

| Action              | Key / Input          |
|---------------------|-----------------------|
| Move                | `W` `A` `S` `D`       |
| Look around         | Mouse                 |
| Jump                | `Space`                |
| Sprint              | `Shift` (hold)         |
| Interact / pick up  | `E`                    |
| Release mouse cursor | `Esc` (press again to recapture) |

## Status

**Phase 1** (movement, interact system, inventory) — done.

**Phase 2** (indoor puzzle content) — done: locked doors, a readable
note, and a numeric combination-lock puzzle. On startup: find the
Brass Key near the crates to open the room's north door, then read
the note inside the room for a 3-digit code, enter it on the wall
panel to get the Vault Key, and use that on the chest.

**Phase 3** (outdoor exploration world) — done: the small indoor room
now sits inside a much larger valley, generated procedurally at
runtime by `world/world_generator.gd`:

- Rolling terrain (heightmap mesh, colored per-vertex by height and
  slope — grass, rock, sand) that blends to dead-flat under the
  original room so nothing there had to move.
- A lake with a translucent water surface, sunk into the terrain.
- Scattered trees (multimesh, visual only) and rocks (individually
  collidable, so they double as cover/obstacles).
- Fireflies drifting over the lake at all times.
- A climbable ruined watchtower on the far side of the valley — a
  stone pillar with a switchback ramp staircase — holding a
  collectible Sunstone and a lore note at the top.
- Tuned world environment for the bigger outdoor view: ACES
  tonemapping, glow, SSAO/SSIL, and light atmospheric/volumetric fog.
- `world/sun_cycle.gd` slowly drifts the sun's angle and color for a
  bit of passing-time atmosphere (purely cosmetic — toggle its
  `enabled` export off to freeze it).

Everything in `world/world_generator.gd` is driven by `@export`
values on the `WorldGenerator` node in `world/world.tscn` — terrain
size, lake position/size, tower position, tree/rock counts, etc. are
all tunable from the Inspector without touching code.

Next up: a proper objective/journal tracker and a defined win
condition once there's more content to tie together.
