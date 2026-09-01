# suika-brainrot-like

A physics merge game for mobile: top-down table, slingshot-aimed shots, 12 tiers of object that
fuse when two of the same tier collide. Godot 4.6, 2D, portrait, fully offline.

## Read this first

**[GAME_DESIGN.md](GAME_DESIGN.md) is the build spec.** Read it before writing any code. It holds
the locked design decisions, the physics and input model, the tier table, the file layout, and a
feature-by-feature roadmap.

Working loop for a session:

1. Read `GAME_DESIGN.md`.
2. Take the next unticked feature in **§12 Build Roadmap** — they are ordered, and each ends in
   something runnable.
3. Build it against that feature's acceptance criteria.
4. Tick the box and note anything you changed or tuned.

Don't jump ahead in the roadmap or build deferred items (audio, haptics, settings, themed art,
extra modes, anything online) unless asked.

## Ground rules

- **§3 of the design doc is locked.** Those 15 decisions were made with the project owner. If one
  looks wrong while implementing, say so and ask — don't quietly change it.
- **The design doc is the source of truth.** If the code and the doc disagree, that's a bug in one
  of them; surface it rather than picking a side silently.
- **All constants live in `res://scripts/config/tuning.gd`.** No magic numbers in scene scripts.
  Anything a designer would want to tweak goes there or on a resource.
- **Placeholder art stays placeholder.** Flat colored circles with tier numbers, drawn in `_draw()`.
  The tier resource has a `texture` field for the eventual swap; leave it null.
- **Offline means offline.** No HTTP, no analytics, no plugins that phone home.

## Conventions

- GDScript with static types everywhere (`var speed: float = 0.0`).
- `snake_case` for files and members, `PascalCase` for classes.
- Signals upward, direct calls downward. UI never reaches into physics nodes.
- Autoloads are exactly three: `Tuning`, `GameState`, `SaveManager`. `SaveManager` is the only
  thing that touches the filesystem.
- Physics callbacks never free or spawn bodies — queue the work and resolve it between steps.

## Running it

Press **F5** (Run Project). It boots to the title screen. Mouse-to-touch emulation is on, so the
full place → drag → release gesture works with a mouse.

To skip the menu, open `res://scenes/game/game.tscn` and press **F6** (Run Current Scene).

Each feature also has a dev harness under `scenes/game/*_test.tscn` that runs its checks on start
and prints to Output. Run those windowed, not headless: the ones driving synthetic touches need a
real 1080x1920 viewport.
