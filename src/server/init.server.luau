-- Server entry point for Workspace.CarWash. Everything that runs the wash on
-- the server lives in this script's ModuleScripts; Workspace.CarWash itself
-- holds no scripts.

-- Weld first, before anything reads machine positions: the machines' moving
-- parts are saved unanchored.
require(script.Welds).weldAll()

require(script.Cash).start()
require(script.WashLine).start()
