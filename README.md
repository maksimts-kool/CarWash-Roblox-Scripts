# CarWash

Scripts for `Workspace.CarWash` in the **Car Wash Testing** place (placeId 6972290608),
kept in two-way sync with Roblox Studio using [Argon](https://argon.wiki).

```
default.project.json   maps src/CarWash -> Workspace.CarWash (Rojo-compatible format)
argon.toml             workspace config for Argon
src/CarWash/...        scripts, mirroring the Explorer tree
```

Files ending in `.server.luau` are Scripts, `.client.luau` are LocalScripts and plain
`.luau` files are ModuleScripts. Folders hold `.data.json` files that record the class of
the Models and Parts that contain scripts.

## Sync

1. Start the server: in VS Code, run **Argon: Open Menu → Serve → default.project.json**,
   or run `argon serve` in a terminal. Run only one server at a time.
   Argon is installed at `~/.local/bin/argon` (linked into `~/.argon/bin`). The VS Code
   setting `argon.autoUpdate` is off, because Argon's self-updater doesn't support Linux.
   Studio under Vinegar loads local plugins from the Wine prefix, so to install or
   update the Studio plugin, run:
   `argon plugin install ~/.var/app/org.vinegarhq.Vinegar/data/vinegar/prefixes/studio/drive_c/users/maksim/AppData/Local/Roblox/Plugins`
2. In Studio, open the Argon plugin settings (gear icon) and set:
   - **Keep Unknowns**: on. Parts and models have no files, and this keeps them.
   - **Two-Way Sync**: on.
   - **Only Code Mode**: on (the default).
   - **Initial Sync Priority**: **Client** for the first connect, which pulls every
     script out of Studio. After that, either **Client** or **Server** works.
3. Click **Connect**.

Every level of `default.project.json` sets `$keepUnknowns`, so Argon never deletes
instances that have no files (parts, sounds, models).

## Layout of Workspace.CarWash

- `MainModule` (with `MainScreenModule` and `WashController`) runs the pay terminal
  and the wash timeline. `Script` starts it.
- `CashSystem` creates the leaderstats `Cash` value: you start with 10 and get +10
  every 120 s. The pay terminal charges from it.
- `ConveyorPart` (`Conveyor1`–`Conveyor4`) pulls the car through in one pass:
  `DuraBlasters` → `WrapArounds` → `RockerBrushes` → the arches in `New` → the dryers.
  Speeds are at the top of `WashController`: `TUNNEL_SPEED` (1.2 studs/s) through the
  blasters and brushes, `ARCH_SPEED` through the arches (Small 0.9, Middle 0.75,
  Full 0.6, so bigger washes give each stage more time), and `CONVEYOR_SPEED` (2)
  into the dryers and out. The car eases between speeds. A Full wash takes about
  2 minutes of washing, then 60 s of drying.
- `New` holds the arches that replaced the old gantry (`Machine`, `Arm`, `Arm2`, the
  wheels, limits and rails, now parked in `ServerStorage.RemovedGantry`). In tunnel
  order they do the gantry's seven stages:
  `KWS Dyna Arch (DoublePresoak)` presoak, `(HighPressure)` the arms' HP jets,
  `(TripleFoam)` foam bars plus the gantry's `T1` / `T2` foam cannons,
  `(SingleRinse)` second high-pressure pass, `(RainOff)` clear coat,
  `Lava Wax Arch` hot wax, `(RainBar)` spot-free rinse. `KWS Dyna Arch (Mapping)` at
  the entrance is decoration. The arches have no scripts of their own: `WashController`
  turns each one's jets and `Speaker` sounds (`Start` / `Loop` / `Stop`) on as the
  car's nose reaches it and off once the tail clears it, and sets the arch's
  `LightMode` / `LightSince` attributes. Each nozzle's spray is layered from
  emitters sharing the stage's name (so the controller toggles them together):
  streaky jets, a thin mist (`Layer` attribute) and, for high pressure, falling
  droplets. Textures come from the two packs in Workspace. From
  `Particle Pack (Water Based)`: `shards` (16171607099) for the water jets, rain and
  wax drips, `dots` (16171528032) for droplets, the animated `mist` (16172858603)
  for spray mist and the clear-coat cloud, and the `water 9` splash (14261754295) on
  the opening blasts (`HPStart`, `Rinse2`; marked `Splash`). From `Particle effects`:
  the animated gas cloud (10034873151) for the foam, the bubble (1084955488), the
  star glints (8611887703) and the flame flipbook for the hot-wax haze. The water
  pack's `bubbles` texture (16694595394) doesn't load in this place. `New.ArchLights` (RunContext Client) reads
  those and animates each arch's `Rope` (the Lava arch's `LED` bar) every frame from
  server time, so all arches and players stay in sync. The look is kept calm: a faint
  blue idle glow that rolls down the tunnel, one colour per stage that breathes
  slowly, and soft fades in and out. The constants at the top of the script set the
  brightness and timing. `PROGRAMS` in
  `WashController` picks the arches per wash: Small runs presoak, both HP passes,
  foam and spot free; Middle adds clear coat; Full adds hot wax.
  Each arch's `Speaker` plays the generated sounds from `sounds/` (uploaded assets):

  | Arch | Start | Loop | Stop |
  |---|---|---|---|
  | DoublePresoak | 78449761318939 | 83406885321749 | 126211593873197 |
  | HighPressure, SingleRinse | 101465800375105 | 130128502941075 | 140142245336534 |
  | TripleFoam | 123247818847372 | 104061137028834 | 73416226262067 |
  | RainOff | 95918102327272 | 78696893509273 | 117294059102337 |
  | RainBar | 80078750451926 | 76377020923201 | 135672204909546 |

  The Lava Wax Arch keeps the old gantry's hot wax sounds (6980328128 / 6980328902 /
  6980329506).
- `sounds/` holds generated replacements, one `<arch>_start/loop/stop.ogg` set for
  presoak, highpressure (also used by SingleRinse), foam, clearcoat and spotfree.
  `sounds/generate.py` makes them from scratch (needs `numpy`, `scipy` and `ffmpeg`);
  loops are seamless and starts end at loop level. Run
  `python sounds/generate.py [arch ...]` to re-render.
- `KWS Storm Dryer 1` and `2`, `DuraBlasters` and `Heaxgonsystem` used to sit loose
  in Workspace.
- Machine particles: `DuraBlasters` nozzles use the same jet / mist / droplet set as
  the High Pressure arch (all named `HP`). Each wrap-around and rocker brush has a
  soapy nozzle spray plus a `FlingFx` ring (welded to the brush, cylinder-shaped
  emitters named `Fling`) that throws water and suds off the spinning brush;
  `WashController` toggles every emitter under a brush with it. Each dryer spout has
  an `AirOutlet` part aimed along the spout with faint air wisps and haze (`DryerAir`),
  switched with the fans. Particles on the moving brushes and blaster heads only
  animate properly in play mode, not in Studio's edit view.
- `Lights` holds the 16 ceiling lights. `Building` holds the walls, roof and grading.
- `Selections_Old` is the old kiosk. Its scripts expect parts that this wash doesn't
  have.

Names under `CarWash` must stay unique among siblings. Argon maps instances to files by
name, so a duplicated script or model needs a new name.
