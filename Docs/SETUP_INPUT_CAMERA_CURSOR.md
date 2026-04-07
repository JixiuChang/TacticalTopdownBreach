# Setup guide: input, cameras, cursor, UI (Godot 4.x)

All **in-game / UI copy should be English** at authoring time. Use `gettext` / CSV or Godot **Internationalization** later (`Project → Project Settings → Localization`).

This repo already wires **Autoloads**: `PlayerKeybind`, `InputRouter`, `GameStateManager`, `TimeSimulator`. The Test Scene shows a **briefing overlay** (group `briefing_blocks_input`) and a bottom-right **Start execution / Pause to planning** button.

---

## Recommended implementation order

1. **Phase & briefing** — Per-level `@export` strings on the level root (see `Scenes/test_scene.gd`: `briefing_title`, `briefing_body`). Briefing blocks gameplay input via group `briefing_blocks_input`.
2. **Floor / blueprint plane** — A `FloorManager` (or level script) holds an array of floor heights; **Q / E** change active index. Planning raycasts use **camera ray ∩ plane(y = floor_height)** for cursor position (not only physics Ground).
3. **World cursor (planning only)** — Small `MeshInstance3D` (flat cylinder) or `Decal` at the hit point; hide in **EXECUTING** (normal mouse only), keep free / top-down camera working.
4. **Hover → hand cursor** — When ray hits a unit layer, `Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)`; else `CURSOR_ARROW`. Run from `_process` or after input.
5. **Dual camera controller** — One `Camera3D` (or swap two nodes). **Tab** toggles mode. Shared: **WASD = horizontal move along camera forward/right** (same `move_speed` in both modes). **Free cam** add: RMB drag pan, MMB drag orbit, wheel dolly. **Top-down**: lock pitch to straight down (`rotation_degrees.x = -90`), optional orthographic; **Q/E** = floors.
6. **Input layering** — Use `_unhandled_input` for camera if UI should eat events first. UI on `CanvasLayer`; set `mouse_filter` on full-screen overlays to `Stop` when blocking the world.

Execution phase: **hide floor cursor**, only system cursor (per your design).

---

## UI & visuals (clean baseline)

| Topic | Godot docs | TL;DR |
|-------|----------------|-----|
| **Control anchors** | [Using Containers](https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_containers.html) | Put HUD in `MarginContainer` + `CanvasLayer`; pin with presets Bottom-Right, Full Rect. |
| **Theme / StyleBox** | [GUI skinning](https://docs.godotengine.org/en/stable/tutorials/ui/gui_skinning.html) | One project `Theme` resource: fonts, `StyleBoxFlat` for buttons/panels. |
| **Icons** | Import PNG/SVG into `Assets/UI/`; set on `Button.icon` or `TextureRect`. | Keep sizes consistent (e.g. 24² toolbar, 48² briefing). |
| **9-slice** | [NinePatchRect](https://docs.godotengine.org/en/stable/classes/class_ninepatchrect.html) | Panels and speech bubbles scale without blurry corners. |

**Polish tips:** limit palette (1 accent + neutrals), use consistent spacing (8/16 px), avoid pure black—use dark blue-gray for backgrounds (#05060a style) as in the test HUD.

---

## Cursor: world dot vs OS cursor

- **OS cursor**: `Input.set_default_cursor_shape(...)` — good for “hover unit = hand”.
- **World “dot”**: a `Node3D` child under a `PlanningCursor` node; update `global_position` from ray–plane intersection each frame while in **PLANNING** and when not in briefing.

---

## Cameras

| Task | Docs | TL;DR |
|------|------|--------|
| Basis / vectors | [Basis](https://docs.godotengine.org/en/stable/tutorials/math/introduction_to_transforms.html) | `global_transform.basis.x` = camera right; flatten Y for top-down WASD: use `(basis.z.x, 0, basis.z.z).normalized()` for “forward on floor”. |
| Spring / orbit | Community patterns | Store `pivot`, orbit with yaw/pitch; dolly with `position` along `-transform.basis.z`. |
| Orthographic top-down | `Camera3D.projection = PROJECTION_ORTHOGONAL`, tune `size`. | Eliminates perspective drift for blueprint feel. |

---

## Input map

Add actions in **Project → Project Settings → Input Map**: e.g. `toggle_camera_mode` (Tab), `floor_up` (E), `floor_down` (Q). Read them via `InputMap` / `Input.is_action_*` in your camera script. Keep **toggle execution** on Space and mirror it with the HUD button (already calls `GameStateManager`).

---

## Automated tests vs play mode

In **Inspector** on `TestScene`: set `run_automated_tests` to **true** to run console-only GameState/time tests on load; **false** (default) runs the playable briefing + HUD flow.

---

## External tutorials (curated)

- **UI overview**: [Overview of UI design](https://docs.godotengine.org/en/stable/tutorials/ui/gui_introduction_to_the_ui_system.html) — scene tree, `Control`, anchors.
- **3D mouse picking**: [Raycasting](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html) — `project_ray_origin` / `project_ray_normal`.
- **Navigation (paths)**: [Navigation introduction](https://docs.godotengine.org/en/stable/tutorials/navigation/index.html) — bake `NavigationRegion3D` on walkable mesh; agents query paths.

---

## File reference in this project

- Briefing + execution button: `Scenes/test_scene.gd`
- Input blocked while briefing: group `briefing_blocks_input`, checked in `Gameplay/Input/input_router.gd`
- Keybind defaults: `Gameplay/Input/player_keybind.gd`
