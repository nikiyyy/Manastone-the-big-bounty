class_name TalentTree
extends Resource
## A class's talent layout. Nodes place themselves by column and row.

@export var display_name: String = "Talents"
@export var talents: Array[Talent] = []


func columns_used() -> int:
	var most: int = 1
	for t in talents:
		if t != null:
			most = maxi(most, t.column + 1)
	return most


func rows_used() -> int:
	var most: int = 1
	for t in talents:
		if t != null:
			most = maxi(most, t.row + 1)
	return most
