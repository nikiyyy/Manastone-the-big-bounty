class_name TerrainProp
extends Resource
## One model that can stand on an obstacle tile — a tree, a boulder, a stump.
## A terrain holds a list of these and picks one per obstacle, so a forest
## grows trees and a river bank grows rocks without either knowing about the
## other.
 
## The model. Drag a .glb or a .tscn straight in.
@export var scene: PackedScene
## Relative chance against the other props that fit this tile.
@export_range(0.0, 10.0) var weight: float = 1.0
 
@export_group("Variation")
## Each copy is scaled somewhere in this range, so they don't look stamped.
## The range runs wide because an imported model's native size is whatever
## the program that made it decided — fix a badly-sized one on import and
## leave these near 1.0, or just dial in the number that looks right here.
@export_range(0.1, 50.0, 0.05) var min_scale: float = 0.85
@export_range(0.1, 50.0, 0.05) var max_scale: float = 1.15
## Spin each copy to a random angle. Turn it off for anything with a front.
@export var random_yaw: bool = true
## Raise or sink the model, for when its origin isn't at its base. Measured
## in the model's own units and multiplied by the scale, so one value holds
## however large a copy comes out. Start at half the model's native height.
@export var y_offset: float = 0.0
 
@export_group("Where it grows")
## How many of the six neighbouring tiles must also be obstacles. The defaults
## let a prop appear anywhere; narrow them to tell a lone boulder apart from
## the middle of a thicket.
@export_range(0, 6) var min_neighbors: int = 0
@export_range(0, 6) var max_neighbors: int = 6
 
 
func fits(neighbors: int) -> bool:
	return scene != null and neighbors >= min_neighbors and neighbors <= max_neighbors
 
 
func random_scale() -> float:
	return randf_range(minf(min_scale, max_scale), maxf(min_scale, max_scale))
 
