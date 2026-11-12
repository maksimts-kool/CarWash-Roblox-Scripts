# CarWash

Scripts for `Workspace.CarWash` in the **Car Wash Testing** place (placeId 6972290608),
kept in two-way sync with Roblox Studio using [Argon](https://argon.wiki).

```
default.project.json   Rojo-compatible project file: maps the folders below into the place
argon.toml             workspace config for Argon
src/server/            -> ServerScriptService.CarWash               (everything server-side)
src/client/            -> StarterPlayer.StarterPlayerScripts.CarWash (visuals, per player)
```

`Workspace.CarWash` holds only the build: parts, models, sounds and GUIs. No scripts
live inside it. The server finds what it drives by name from `ServerScriptService`,
and the clients do the same from `StarterPlayerScripts`.

Files ending in `.server.luau` are Scripts, `.client.luau` are LocalScripts and plain
`.luau` files are ModuleScripts (`init.luau` / `init.server.luau` make the folder itself
that script).

The project maps code only. Never add Workspace instances (parts, models) to
`default.project.json` or as files: on a Server-priority sync Argon resets any instance
it has a file for to default properties, which moves parts to the origin and resets
model scale. Everything not in the project stays exactly as saved in the place.
The services in the project (`ServerScriptService`, `StarterPlayer`) get the same
treatment, so any `StarterPlayer` setting you change in Studio must also go into its
`$properties` in `default.project.json`, or the next Server-priority connect resets it.

**Build things in the place, not in scripts.** Anything that can be made in Studio
(parts, models, GUIs, sounds, lights) is made there and saved in the place, and the
scripts only find it by name, fill it in and animate it, like the pay terminal
(`Selections`) and the `ControlBooth`. Scripts don't build parts or lay out GUIs at
runtime. A list that can grow (one row per machine, per program, per log line) gets a
saved row for each entry plus a hidden template in the GUI that the script copies for
anything new.

## Code

Server (`src/server`), started by `init.server.luau` in this order:

| Module | Does |
|---|---|
| `Config` | Every tunable number: wash programs (name, price, arch speed, which arches), conveyor speeds, timings, cash, gate angles |
| `Joints` | Runs first. Replaces the machines' physics with scripted joints: welds each moving part into a rigid assembly (`Welds`), turns every legacy `Rotate` joint (the wheel blaster heads) and every `HingeConstraint` into a `Motor6D` (named `Joint`, or the hinge's own name), gives each dryer `FanMotor` a `Joint` instead of its surface motor, removes every other constraint / body mover and anchors anything left loose. Moving parts stop colliding, except the gate arms. `Joints.servo(joint, angle, speed?)` / `Joints.spin(joint, speed)` set the joint's attributes (degrees, degrees/s; the old hinge angles still apply) |
| `Welds` | Welds a model into one rigid assembly; used by `Joints` for the gate arms, brushes, wheel blaster heads and dryer fans, which are saved unanchored and unwelded |
| `Cash` | leaderstats `Cash`: start with 15, +10 every 120 s. `Cash.charge(player, price)` |
| `WashLine` | The customer flow: kiosk payment → entry gate opens when the wash is free → car drives in → wash runs. Also sets the entrance `ProgressScreen` (Select / Good / Occupied). |
| `Kiosk` | The pay terminal (`Selections`): menu, confirm, tap a "Debit Card" on the EFT reader. Fills the screen's texts from `Config` and sets the payment `State` |
| `Gates` | Entry (`GateEN`) and exit (`GateEX`) barrier arms |
| `Wash` | The wash timeline (`Wash.run(program)`): pickup → tunnel → dryers → exit, phases and countdowns |
| `Wash/Car` | Finding, measuring and towing the car; publishes `CarFront` / `CarLength` |
| `Wash/Conveyor` | Belts, `moveCarTo` with position triggers |
| `Wash/Arches` | The seven arches in `New`: jets, sounds, `LightMode` / `LightSince` |
| `Wash/Brushes` | Wrap-around and rocker brushes |
| `Wash/Blasters` | Rotary wheel blasters (`RotaryWheelBlasters`): three spinning heads per side; the `Sensor` beam remembers where the car's wheels are, and the nozzles fire while a wheel is in front of the heads |
| `Wash/Dryers` | The KWS Storm Dryers. Each starts only when the car's nose is right under its first `AirOutlet` (`Config.DryerLead`), one at a time (`Config.DryerStagger` apart): Startup sound (cut after `DryerStartupSeconds`), then the hum; on stop the hum fades under the Stop sound. Volume and hearing distance are in `Config` |
| `Wash/Screens` | Attributes for the Wash Time / Dry Time screens |
| `Wash/Stop` | The emergency stop flag. Every long wait in the wash timeline (conveyor moves, pickup, drying, exit gate) errors out while it is set. On an emergency stop `WashLine` switches every machine off, lets go of the car, closes the entry gate and opens the exit so the driver can drive out. Only once the car is past the exit sensor (or gone) can an operator reset, which closes the exit and frees the line |
| `ControlPanel` | The operator console on `CarWash.ControlBooth` (parts saved in the place, beside the entry gate: a `Screen`, an `EStop` mushroom button and a `Green` / `Amber` / `Red` stack light the script lights). It publishes machine, gate, conveyor, settings, stats and log state on `ReplicatedStorage.CarWashPanel` and takes commands through `CarWashRemotes.ControlPanel`. Only operators can use it: the place owner, `Config.ControlPanel.Admins`, and everyone in Studio |

Client (`src/client`), one LocalScript each, all driven by attributes the server sets
and by server time, so every player sees the same thing with no remotes:
`Joints` (moves the gate arms, brushes, wheel blaster heads, dryer fans
by setting each joint's `Transform`, with smooth easing), `LightShow` (ceiling lights and wall hexagons), `ArchLights` (arch LEDs),
`TimerScreens` (Wash Time / Dry Time screens), `ProgressScreen` (entrance screen
animations), `KioskScreen` (pay terminal screen animations), `EmergencyScreens` (shows and
animates the saved `Emergency` frame on the three tunnel screens and the entrance screen while
the wash is stopped).
`ControlPanel` fills in the operator console, the SurfaceGui `ControlBooth.Screen.Panel` saved
in the place in the pay terminal's style (white cards, navy text, blue accents, Montserrat).
Each client fills its own copy and sends button presses to the server, which checks
who pressed them. It shows line status, the e-stop, the car's position in the tunnel, a lamp per machine and four
tabs: Manual (machine tests while idle, gates, all off, cancel admission), Washes (free
operator washes), Lights (ceiling lights and wall hexagons Auto / On / Off, arch LEDs
Auto / Off; set as `LightsCeiling` / `LightsHexagons` / `LightsArches` on `CarWash`, which
`LightShow` and `ArchLights` follow, and the emergency stop overrides) and Stats & Log.
Non-operators see the `Lock` screen.
The booth and its GUI are ordinary instances: move or restyle them in Studio, keeping the
names the script looks for (listed at the top of `client/ControlPanel.client.luau`).

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
   - **Initial Sync Priority**: **Server**, so the files are the source of truth.
     (**Client** pulls Studio's scripts into the files instead; only use it on purpose.)
3. Click **Connect**.

Every level of `default.project.json` sets `$keepUnknowns`, so Argon never deletes
instances that have no files. Argon reads the project tree only
when the server starts: after changing `default.project.json`, restart `argon serve`
and reconnect.

## Layout of Workspace.CarWash

- `ConveyorPart` (`Conveyor1`–`Conveyor4`) pulls the car through in one pass:
  `RotaryWheelBlasters` → `WrapArounds` → `RockerBrushes` → the arches in `New` → the dryers.
  Speeds are in `Config`: `TunnelSpeed` (1.2 studs/s) through the
  blasters and brushes, each program's `archSpeed` through the arches (Small 0.9, Middle 0.75,
  Full 0.6, so bigger washes give each stage more time), and `ConveyorSpeed` (2)
  into the dryers and out. The car eases between speeds. A Full wash takes about
  2 minutes of washing, then 60 s of drying.
- `New` holds the arches that replaced the old gantry (`Machine`, `Arm`, `Arm2`, the
  wheels, limits and rails, now parked in `ServerStorage.RemovedGantry`). In tunnel
  order they do the gantry's seven stages:
  `KWS Dyna Arch (DoublePresoak)` presoak, `(HighPressure)` the arms' HP jets,
  `(TripleFoam)` foam bars plus the gantry's `T1` / `T2` foam cannons,
  `(SingleRinse)` second high-pressure pass, `(RainOff)` clear coat,
  `Lava Wax Arch` hot wax, `(RainBar)` spot-free rinse. `KWS Dyna Arch (Mapping)` at
  the entrance is decoration. The arches have no scripts of their own: `Wash/Arches`
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
  pack's `bubbles` texture (16694595394) doesn't load in this place. The client `ArchLights` script reads
  those and animates each arch's `Rope` (the Lava arch's `LED` bar) every frame from
  server time, so all arches and players stay in sync. The look is kept calm: a faint
  blue idle glow that rolls down the tunnel, one colour per stage that breathes
  slowly, and soft fades in and out. The constants at the top of the script set the
  brightness and timing. Each program's
  `arches` list in `Config` picks the arches per wash: Small runs presoak, both HP passes,
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
  `dryer_stop.ogg` is the dryers' spin-down (uploaded as 101218008415689, set in
  `Config.DryerStopSoundId`).
  `sounds/generate.py` makes them from scratch (needs `numpy`, `scipy` and `ffmpeg`);
  loops are seamless and starts end at loop level. Run
  `python sounds/generate.py [arch ... | dryer]` to re-render.
- `KWS Storm Dryer 1` and `2`, the old `DuraBlasters` and `Heaxgonsystem` used to sit loose
  in Workspace.
- Machine particles: each `RotaryWheelBlasters` head fires from five nozzles (`hp1`–`hp5`),
  each with a `BlasterJet` (the water pack's `shards`), `BlasterMist` (`mist`) and
  `BlasterDrops` (`dots`), cloned from `ReplicatedStorage["Particle templates"]` and scaled
  down so the jets reach just past the wheel tracks. They fire across the lane along the spin
  axis, so they spiral as the heads turn.
  Their legacy `Rotate` joints become scripted spin joints and their old `Weld` scripts
  are removed at startup. Each wrap-around and rocker brush has a
  soapy nozzle spray plus a `FlingFx` ring (welded to the brush, cylinder-shaped
  emitters named `Fling`) that throws water and suds off the spinning brush;
  `Wash/Brushes` toggles every emitter under a brush with it. Each dryer spout has
  an `AirOutlet` part aimed along the spout with faint air wisps and haze (`DryerAir`),
  switched with the fans. Particles on the moving brushes and blaster heads only
  animate properly in play mode, not in Studio's edit view.
- `ControlBooth` is the operator console (see `ControlPanel`); its `Screen` part carries the panel.
- `Lights` holds the 16 ceiling lights. `Building` holds the walls, roof and grading.
- `Selections` is the pay terminal. Its `Screen.SurfaceGui` (fixed 800 x 610 canvas) has a
  `Header` with a Choose / Confirm / Pay stepper, a `Footer` hint line and three `Pages`:
  `Select` (one card per program in `Cards`, each with an `Accent` colour attribute),
  `Confirm` (summary and the `Confirm` / `Cancel` buttons) and `Process` (the step list and
  payment status; its `State` attribute drives the client animations). The old screen is
  kept in `ServerStorage.RemovedKioskScreen`.
- `ProgressScreen` is the status screen at the entrance,
  `TimerWash` / `TimerWashScreen2` / `TimerDryer` the Wash Time and Dry Time screens.

Names under `CarWash` must stay unique among siblings. Argon maps instances to files by
name, so a duplicated model needs a new name.
