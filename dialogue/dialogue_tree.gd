class_name DialogueTree
extends Resource
## A whole conversation. Nodes are a flat list linked by id rather than nested
## resources — nesting is miserable to edit in the Inspector and hides the
## branching. The cost is that a typo in a `next` id fails at runtime, which
## `validate()` exists to catch.

@export var start_id: StringName = "start"
@export var nodes: Array[DialogueNode] = []

var _index: Dictionary = {}      # StringName -> DialogueNode
var _indexed: bool = false


func node(id: StringName) -> DialogueNode:
	_build_index()
	return _index.get(id)


func start_node() -> DialogueNode:
	var first: DialogueNode = node(start_id)
	if first != null:
		return first
	return nodes[0] if not nodes.is_empty() else null


func _build_index() -> void:
	if _indexed:
		return
	_indexed = true
	_index.clear()
	for n in nodes:
		if n != null and not n.id.is_empty():
			_index[n.id] = n


## Call this from a tool script or a test if a tree misbehaves. Returns the
## problems as readable lines; empty means the tree is sound.
func validate() -> Array:
	_build_index()
	var problems: Array = []

	if start_node() == null:
		problems.append("No node with start_id '%s'." % start_id)

	var seen: Dictionary = {}
	for n in nodes:
		if n == null:
			problems.append("Empty slot in the nodes array.")
			continue
		if n.id.is_empty():
			problems.append("A node has no id.")
			continue
		if seen.has(n.id):
			problems.append("Duplicate node id '%s'." % n.id)
		seen[n.id] = true

		for choice in n.choices:
			if choice == null:
				problems.append("Node '%s' has an empty choice slot." % n.id)
				continue
			if not choice.next.is_empty() and not _index.has(choice.next):
				problems.append("Node '%s' points at missing node '%s'." % [n.id, choice.next])

	return problems
