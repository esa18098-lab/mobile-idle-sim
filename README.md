# Mobile Idle Sim

2D pixel-art idle sim for Android. Win your home planet region by region, then your solar system, then join a shared galaxy.

- **Engine:** Godot 4.7.2 (standard build, GDScript). Portrait 360×640 with integer scaling.
- **Design source of truth:** the balance spreadsheet. Its numbers reach the game only through `balance/*.csv`.
- **Build plan:** milestones 1–9 live in the "Godot build plan" doc in the claude.ai project *Mobile Idle Sim*.

## Status

| Milestone | State |
|---|---|
| 1. Setup, repo, CSV pipeline, Android preset | Done in code. You still need to install it on a phone once (steps below). |
| 2. Headless sim core matching the Timeline tab within 5% | Done. A cautious playthrough takes 5.08 h vs the sheet's 5.106 h, and every step is within 5%. An attentive player takes 3.84 h. |
| 3. Region map and building slots | Done. Planet and region views, build, upgrade, demolish, the queue, and the resource bar. Tests check that every building type can be placed through the buttons and that the screen's rates equal the sim's. |
| 4. Combat and conquest | Done. Borders from the map grid, the attack screen with a live outcome preview, occupy or raze, timed battles, survivors coming home, the Army screen's standing training order, and capture pop-ups. Tests take the whole planet by force (3.83 h attentive). |
| 5. NPC behaviour | Next. |

### What the two playthroughs mean

- **Cautious** plays the way the Timeline assumes: build, train, attack, wait for the battle, repeat. It is the check that the sim follows the sheet's rules.
- **Attentive** trains for the next region, or opens annexation talks, while the current battle runs. Battles are about half of the sheet's time, so this is about 25% faster. The sheet's timing is therefore the slow, cautious path, not the typical one.

### Paths through the home planet (`tools/paths.gd`)

| Path | Cautious | Attentive |
|---|---|---|
| Default: conquer Kharn and Ostrel, annex Veyra | 5.08 h | 3.84 h |
| Conquer everyone | 5.23 h | 3.83 h |
| Conquer everyone, raze Kharn | 5.15 h | 3.69 h |
| Annex Veyra, raze Kharn | 5.18 h | 3.99 h |
| Conquer everyone, raze all | 5.16 h | 3.78 h |

All paths are within about 8% of each other. Razing is a little faster but slows annexation for the rest of the planet.

## Layout

```
balance/        CSVs exported from the sheet (one per tab). The game reads these and nothing else for numbers.
scripts/data/   balance_data.gd: loads the CSVs and looks values up by key.
scripts/sim/    The sim core. Pure GDScript, no scenes, no clock of its own.
                  sim.gd: home-planet state, commands, 1-second ticks. combat.gd: battle math.
                  autoplayer.gd: plays the default path for tests (cautious or attentive).
scripts/game/   game.gd (autoload Game): the only code that reads the clock. Feeds the sim real time and passes UI commands to it.
scripts/ui/     main_screen.gd (resource bar, views, queue, sheets), planet_view.gd, region_view.gd,
                  look.gd (placeholder colours, labels, theme), icon.gd (placeholder 16×16 icons).
assets/fonts/   Silkscreen (SIL OFL), an 8 px pixel font: use sizes 8 or 16 only.
data/maps/      home_planet.csv: where each region sits on the map grid. Regions that sit side by side share a border.
tools/          playthrough.gd: prints a region-by-region playthrough next to the sheet.
                paths.gd: compares the paths through the home planet.
                shots.gd: renders every screen to PNGs (needs a display; xvfb-run on a server).
scripts/autoload/  Balance: the one loaded copy of the balance data.
scripts/ui/     Presentation. It reads the sim and sends it commands; it holds no game rules.
scenes/         main.tscn: a build-check screen for now.
tests/          Headless tests and golden numbers copied from the sheet.
```

## Rules the code follows

1. **No balance number in code.** Code asks for a value by its key, e.g. `b.num("def_advantage")`. Keys live in the sheet's grey "Key (used by code)" column (Inputs tab, column D; Buildings tab, column E). If the sheet loses a key, loading fails and the app shows the error.
2. **The sim core does not touch scenes or the wall clock.** Time is handed in. That is what makes offline catch-up and headless tests possible.
3. **Golden tests are the contract with the sheet.** If you change a formula on the sheet, the matching golden file changes too. A failing test then means the code is out of date, not that the test is wrong.

## Changing balance

1. Edit the sheet.
2. Ask Claude to "sync balance from the sheet". This regenerates `balance/*.csv`, and `tests/golden/*` if the Timeline or Combat tab changed.
3. Run the tests. Commit.

You can also edit a CSV directly to try something on the device, then copy the change back to the sheet. The sheet stays the source of truth.

## Running a playthrough

```
godot --headless --path . --script res://tools/playthrough.gd
```

## Running tests

```
GODOT=/path/to/godot tests/run.sh
```

The run fails on any failed check **or** any script error. Godot keeps running after script errors, so the wrapper looks for them in the output.

## First install on an Android phone (one-time setup)

1. Install Godot **4.7.2 standard** (not .NET). Open this folder with it.
2. Go to **Editor → Manage Export Templates → Download and Install**.
3. Install **OpenJDK 17** and the **Android SDK** (command-line tools, platform-tools, plus the build-tools and platform versions listed on Godot's "Exporting for Android" docs page). Android Studio's SDK Manager is the easiest way to get these.
4. Open **Editor → Editor Settings → Export → Android** and set *Java SDK Path* and *Android SDK Path*. Godot creates a debug keystore on its own.
5. On the phone, turn on **Developer options → USB debugging** and plug the phone in.
6. Click the Android **Remote Deploy** button in the top-right of the editor. That one click builds and installs the app from then on.

What you should see: the home planet map. Tap the capital to see its 8 buildings. The **Dev** button (debug builds only) has game speed up to ×600, free resources, and "take the next enemy region", which gives you empty slots to build in until conquest exists. Dev → "Build check screen" opens the milestone 1–2 screen with the CSV reload and the sim run.

Signing keys (`*.keystore`, `*.jks`) are git-ignored. Keep the release keystore somewhere safe outside the repo; losing it means you can't update the app on the Play Store.

## Art

16×16 pixel art. Textures use nearest filtering. Art and audio go through Git LFS (see `.gitattributes`), so run `git lfs install` once.
