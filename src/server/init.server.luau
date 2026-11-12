-- Server entry point for Workspace.CarWash. Everything that runs the wash on
-- the server lives in this script's ModuleScripts; Workspace.CarWash itself
-- holds no scripts.

-- Set up the machines' joints first, before anything reads machine positions:
-- their moving parts are saved unanchored on hinges, which this replaces.
require(script.Joints).setup()

-- Dirt / soap / water / shine on every car; the wash line feeds it.
require(script.CarCondition).start()

require(script.Cash).start()
require(script.WashLine).start()
require(script.ControlPanel).start()
