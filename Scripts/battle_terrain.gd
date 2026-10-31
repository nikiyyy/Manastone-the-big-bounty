class_name BattleTerrain
extends Resource
## One kind of battlefield. Save these as .tres files in res://terrain/ and the
## battle map picks one at random when a fight starts.
##
## There are only two generators. SCATTER drops seeds and grows them into their
## neighbours — wetland is that with the growth turned up, forest is the same
## thing with growth turned off, which is what makes trees read as scattered
## rather than clumped. RIVER lays a meandering band across the fighting axis
## and then scatters rocks on the banks.
 
const FOLDER := "res://terrain"
 
enum Kind { SCATTER, RIVER }
 
@export var display_name: String = "Wetland"
@export var kind: Kind = Kind.SCATTER
## Relative chance of being picked. 2.0 turns up twice as often as 1.0, and
## 0.0 keeps a map in the folder without it ever being chosen.
@export_range(0.0, 10.0) var weight: float = 1.0
 
@export_group("Obstacles")
## Fraction of the map that can't be walked through at all.
@export_range(0.0, 0.4) var obstacle_density: float = 0.05
## Chance a placed tile spreads to each neighbour. 0 gives single tiles.
@export_range(0.0, 1.0) var obstacle_spread: float = 0.2
@export var max_obstacle_cluster: int = 8
 
@export_group("Rough ground")
## Water, mud, scrub — passable, but costs 2 movement to enter.
@export_range(0.0, 0.4) var rough_density: float = 0.08
@export_range(0.0, 1.0) var rough_spread: float = 0.3
@export var max_rough_cluster: int = 12
 
@export_group("River")
## Only read when Kind is RIVER.
@export var river_min_width: int = 2
@export var river_max_width: int = 4
## How often the channel wanders sideways as it crosses the map.
@export_range(0.0, 1.0) var river_meander: float = 0.35
 
@export_group("Colours")
@export var obstacle_color: Color = Color(0.04, 0.04, 0.05)
@export var rough_color: Color = Color(0.18, 0.32, 0.58)
 
# ------------------------------------------------------------------ catalogue
 
static func all_terrains() -> Array:
	var out: Array = []
	var dir := DirAccess.open(FOLDER)
	if dir == null:
		push_warning("BattleTerrain: no folder at %s" % FOLDER)
		return out
 
	for file_name in dir.get_files():
		# exported projects rename .tres to .remap
		var clean: String = file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres") and not clean.ends_with(".res"):
			continue
		var res = load(FOLDER.path_join(clean))
		if res is BattleTerrain:
			out.append(res)
	return out
 
 
## Weighted pick across the folder. Null when the folder is empty, which the
## battle map reads as "use the built-in defaults".
static func random_from_folder() -> BattleTerrain:
	var all: Array = all_terrains()
	if all.is_empty():
		return null
 
	var total: float = 0.0
	for t in all:
		total += maxf(0.0, t.weight)
	if total <= 0.0:
		return null
 
	var roll: float = randf() * total
	for t in all:
		roll -= maxf(0.0, t.weight)
		if roll <= 0.0:
			return t
	return all.back()
 
