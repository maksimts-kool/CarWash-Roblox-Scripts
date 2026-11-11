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
- `New` holds the arches that replaced the old gantry (`Machine`, `Arm`, `Arm2`, the
  wheels, limits and rails, now parked in `ServerStorage.RemovedGantry`). In tunnel
  order they do the gantry's seven stages:
  `KWS Dyna Arch (DoublePresoak)` presoak, `(HighPressure)` the arms' HP jets,
  `(TripleFoam)` foam bars plus the gantry's `T1` / `T2` foam cannons,
  `(SingleRinse)` second high-pressure pass, `(RainOff)` clear coat,
  `Lava Wax Arch` hot wax, `(RainBar)` spot-free rinse. `KWS Dyna Arch (Mapping)` at
  the entrance is decoration. The arches have no scripts: `WashController` turns each
  one's jets, rope light and `Speaker` sounds (`Start` / `Loop` / `Stop`) on as the
  car's nose reaches it and off once the tail clears it. `PROGRAMS` in
  `WashController` picks the arches per wash: Small runs presoak, both HP passes,
  foam and spot free; Middle adds clear coat; Full adds hot wax.
  Arch sounds use IDs this game can play: the spray loop is `ssss` (10487832846, the
  same hiss as the brushes) pitched per arch, and the start is the wrap-arounds' `Air`
  burst (1115758787). The foam arch keeps its own start/stop, and the lava arch keeps
  its own three sounds. The old gantry's sound IDs fail with "Requester does not have
  permission".
- `KWS Storm Dryer 1` and `2`, `DuraBlasters` and `Heaxgonsystem` used to sit loose
  in Workspace.
- `Lights` holds the 16 ceiling lights. `Building` holds the walls, roof and grading.
- `Selections_Old` is the old kiosk. Its scripts expect parts that this wash doesn't
  have.

Names under `CarWash` must stay unique among siblings. Argon maps instances to files by
name, so a duplicated script or model needs a new name.
