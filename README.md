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
| 5. NPC behaviour | Done. Attacks launch only while the app is open, about once an hour of play, from an enemy region on your border at your weakest region (never the capital), sending half that region's garrison. A warning comes first. Standing order: soldiers at home auto-reinforce. Repelling pays 0.75 gold per attacker; losing gives the region and its buildings back. At most one region lost per absence. Trade partners and civilizations in talks don't attack. |
| 6. Diplomacy and market | Done. Free trade rights, annexation of any civilization (one talk per civilization at a time), and a market whose price moves with your trades and recovers 10% an hour, with manual buy and sell. The conquer-everyone and annex-Veyra paths match the sheet's maths within 5% at every region. |
| 7. Offline progress and saves | Done. Saves are JSON plus a checksum, written safely and loaded at start, on resume and every 30 s. Offline catch-up uses 60 s steps that stop at battle and annexation ends: 8 h away matches 8 h live within 1%, and a week catches up in about 0.1 s. A "while you were away" summary, notification timing (delivery needs an Android plugin), and the server stubs. Storage caps are built but off until the sheet has a `storage_cap_hours` key. |
| 8. Automation | Done. The Automate sheet sets standing orders that keep running while you're away. Auto-build follows the sheet's Build Plan. Focus (balanced, military, industry, food) decides which buildings get upgraded first. Auto-attack takes the weakest region on your border. With only these switched on and raids running, the planet falls in about 3.8 h without opening a region view. |
| 9. Playtest build | The game side is ready: conquest timestamps, a "Home planet won" screen, and **Copy playtest log**. The Play export preset is set up. Your steps are below. |

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

### NPC raids (`tools/paths.gd`, 20 seeds, default path)

| | No raids | With raids |
|---|---|---|
| Cautious | 5.07 h | 4.48 h (about 3 attacks, 1.4 regions lost and retaken) |
| Attentive | 3.84 h | 3.50 h (about 2 attacks, all repelled) |

Raids make the planet faster. A repelled attack has thinned the source region's garrison, so it's cheaper to take next. Without that thinning, raids cost attentive players nothing and cautious players about 13%. The repel payout barely matters (about 0.1 h).

All paths are within about 8% of each other. Razing is a little faster but slows annexation for the rest of the planet.

`tools/sheet_model.py` is the Timeline tab rebuilt formula for formula in Python. It reproduces the sheet's default path exactly (`--check`), and it computes the other paths, which the sheet can only show one at a time. `--golden` writes them to `tests/golden/sheet_paths.csv`.

| Path | Sheet's maths | Sim, cautious |
|---|---|---|
| Default | 5.106 h | 5.078 h |
| Conquer everyone | 5.260 h | 5.23 h |
| Conquer everyone, raze Kharn | 5.185 h | 5.15 h |
| Annex Veyra, raze Kharn | 5.299 h | 5.18 h |

On the raze paths, single regions can drift up to 6%. Razing slows annexation talks; the sim banks resources during those waits, while the sheet starts every step from empty stockpiles.

## Layout

```
balance/        CSVs exported from the sheet (one per tab). The game reads these and nothing else for numbers.
scripts/data/   balance_data.gd: loads the CSVs and looks values up by key.
scripts/sim/    The sim core. Pure GDScript, no scenes, no clock of its own.
                  map_gen.gd: the procedural map and its geography (seeded; a save keeps only the seed).
                  planet_factory.gd: new games, balance-checked. region_names.gd: names that fit the biome.
                  sim.gd: home-planet state, commands, 1-second ticks. combat.gd: battle math.
                  autoplayer.gd: plays the default path for tests (cautious or attentive).
scripts/game/   game.gd (autoload Game): the only code that reads the clock. Feeds the sim real time, passes UI
                  commands to it, saves, and catches up time away. save_system.gd (JSON + checksum),
                  server.gd (stubs for the galaxy stage), notifier.gd (local notifications via a plugin).
scripts/ui/     main_screen.gd (resource bar, views, queue, sheets), planet_view.gd, region_view.gd,
                  look.gd (placeholder colours, labels, theme), icon.gd (placeholder 16×16 icons).
assets/fonts/   Silkscreen (SIL OFL), an 8 px pixel font: use sizes 8 or 16 only.
tools/          playthrough.gd: prints a region-by-region playthrough next to the sheet.
                sheet_model.py: the Timeline tab in Python (exact), for any path; --golden writes tests/golden.
                paths.gd: compares the paths through the home planet.
                shots.gd: renders every screen to PNGs (needs a display; xvfb-run on a server).
scripts/autoload/  Balance: the one loaded copy of the balance data.
scripts/ui/     Presentation. It reads the sim and sends it commands; it holds no game rules.
scenes/         main.tscn: a build-check screen for now.
tests/          Headless tests and golden numbers copied from the sheet.
```

## The map

Every new game draws its own home-planet map with real geography:

- **Elevation, temperature and moisture.** Cold in the north, hot in the south. Together they give every cell a biome: Plains, Forest, Hills, Mountains, Tundra, Coast or **Desert**. Desert is new: fuel-rich, little food, and harder to attack into.
- **Lakes** sit in low basins. They are water, so regions on opposite shores don't share a border, which creates choke points.
- **Rivers** run downhill from the highlands to the sea or a lake. Territories grow slowly across rivers and up ridges, so those tend to become borders.
- **River crossings** give the defender `river_crossing_defense` (+20%) when every border you hold with a region is a river. One dry border removes the bonus. NPC raids across a river face it too. With terrain, that makes two combat modifiers, inside the design's limit of three.

A region's biome (the one most of its land has) is its terrain: defense and production come from the sheet's terrain table. Names fit the biome. Garrisons, slots and owners still come from the sheet. The capital is always Plains.

The generator keeps these rules, and draws again with the next seed when a map can't meet them:

- every region on the default path borders one you'd already hold
- each civilization's land is connected
- regions are placed outward from a southern capital, Ostrel never borders the capital, and the Citadel is as far from home as any region
- at least four biomes, at most three mountain regions, and no slivers or giant regions

**Balance check:** `scripts/sim/planet_factory.gd` plays each new map once with the cautious autoplayer, in fast-forward, and redraws it if the time falls outside `map_cautious_hours_min` to `map_cautious_hours_max` (4.6–5.6 h). Over 60 maps the spread was 4.67–5.32 h, with a mean of 4.91 h, so almost every map passes on the first try. The check takes about 0.4 s per new game on a desktop.

**Sheet layout:** `Sim.new_home_planet(data, seed, false)` keeps the sheet's own terrain and names and ignores rivers. Every test that compares against the sheet uses it.

`scripts/ui/map_view.gd` draws the map in true pixels: tileable terrain patterns, dunes, trees, lakes, rivers, owner-coloured frontiers, names and garrisons, marching arrows for battles and raids, and a flash when a region changes hands.

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

**Notifications** need an Android local-notification plugin; see `scripts/game/notifier.gd`. Until one is installed the game still works out when to notify; it just can't deliver.

Signing keys (`*.keystore`, `*.jks`) are git-ignored. Keep the release keystore somewhere safe outside the repo; losing it means you can't update the app on the Play Store.

## Playtest release on Google Play (milestone 9)

1. In the editor: **Project → Install Android Build Template**. Play needs an app bundle (.aab), and that needs Godot's Gradle build.
2. Make an upload key and keep it outside the repo. Losing it means you can't update the app.
   `keytool -genkey -v -keystore upload.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000`
3. **Project → Export → "Android (Play)"**: set *Keystore → Release* to that file, alias and password. Godot keeps these in `export_credentials.cfg`, which is git-ignored. Then export the .aab.
4. In Play Console: create the app, then **Testing → Internal testing → Create release**. Upload the .aab, add your testers' emails, and send them the opt-in link.
5. Testers play to the end. The "Home planet won" screen has **Copy playtest log**, and they paste it to you. Give the logs to Claude to set against `tools/sheet_model.py`.

Internal testing is available straight away. To publish publicly later, a personal developer account made after 13 Nov 2023 must first run a **closed** test with at least 12 testers opted in for 14 days in a row. Internal testing doesn't count toward that.

## Art

16×16 pixel art. Textures use nearest filtering. Art and audio go through Git LFS (see `.gitattributes`), so run `git lfs install` once.
