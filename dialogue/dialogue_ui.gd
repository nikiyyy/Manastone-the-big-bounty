extends CanvasLayer
## Runs DialogueTrees. An NPC without one gets a default tree built in code,
## so existing characters keep working and the default doubles as a worked
## example of the data format.
##
## Scene layout is unchanged: Panel/Margin/VBox/{NameLabel, TextLabel, Options}.
## The affinity line is added in code.

signal closed

@export_file("*.tscn") var battle_scene_path: String = "res://scenes/worlds/battle_field.tscn"
## Hide the affinity readout once you'd rather players infer it from tone.
@export var show_affinity: bool = true

@onready var name_label: Label = $Panel/Margin/VBox/NameLabel
@onready var text_label: Label = $Panel/Margin/VBox/TextLabel
@onready var options: VBoxContainer = $Panel/Margin/VBox/Options

var player: Node = null
var current_npc = null

var _tree: DialogueTree = null
var _node: DialogueNode = null
var _affinity_label: Label
## Set by actions while a choice's list is running, acted on once it finishes.
var _pending: String = ""


func _ready() -> void:
	add_to_group("dialogue_ui")
	_build_affinity_label()
	hide_dialogue()
	Game.player_spawned.connect(_on_player_spawned)
	if Game.player != null:
		_on_player_spawned(Game.player)


func is_open() -> bool:
	return $Panel.visible


func _on_player_spawned(new_player: Node) -> void:
	player = new_player
	if not player.interacted.is_connected(open):
		player.interacted.connect(open)
	# a world change always closes any open conversation
	current_npc = null
	hide_dialogue()


func _build_affinity_label() -> void:
	_affinity_label = Label.new()
	_affinity_label.add_theme_font_size_override("font_size", 11)
	_affinity_label.modulate = Color(1, 1, 1, 0.6)
	var box := $Panel/Margin/VBox
	box.add_child(_affinity_label)
	box.move_child(_affinity_label, 1)      # just under the name

# --------------------------------------------------------------- the runner

func open(npc) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	current_npc = npc
	_tree = _tree_for(npc)
	_pending = ""
	_goto(_tree.start_id)
	$Panel.show()


func hide_dialogue() -> void:
	$Panel.hide()


## An NPC's own tree, or the stock one if it hasn't been given a script.
func _tree_for(npc) -> DialogueTree:
	if "dialogue" in npc and npc.dialogue != null:
		return npc.dialogue
	return _default_tree(npc)


func _goto(id: StringName) -> void:
	var next: DialogueNode = _tree.node(id)
	if next == null:
		push_warning("Dialogue: no node '%s'" % id)
		_close()
		return

	_node = next
	_run_actions(_node.on_enter)
	if _resolve_pending():
		return          # on_enter ended the conversation

	_refresh_header()
	text_label.text = _node.text
	_build_options()


func _refresh_header() -> void:
	var who: String = _node.speaker
	if who.is_empty():
		who = current_npc.display_name if "display_name" in current_npc else "..."
	name_label.text = who

	if not show_affinity or not current_npc.has_method("unique_id"):
		_affinity_label.hide()
		return
	var id: StringName = current_npc.unique_id()
	_affinity_label.text = "%s  (%d)" % [Story.affinity_tier(id), Story.get_affinity(id)]
	_affinity_label.show()


func _build_options() -> void:
	for child in options.get_children():
		child.queue_free()

	var number: int = 1
	var offered: int = 0

	for choice in _node.choices:
		if choice == null:
			continue
		var available: bool = choice.is_available(current_npc, player)
		var locked: bool = not available and choice.is_locked_but_visible(current_npc, player)
		if not available and not locked:
			continue

		var button := Button.new()
		button.text = "%d. %s" % [number, choice.text]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = locked
		if locked:
			button.tooltip_text = choice.lock_reason(current_npc, player)
			button.modulate = Color(1, 1, 1, 0.5)
		else:
			button.pressed.connect(_on_choice.bind(choice))
		options.add_child(button)
		number += 1
		if not locked:
			offered += 1

	# never strand the player in a node they can't leave
	if offered == 0:
		var out := Button.new()
		out.text = "%d. Leave" % number
		out.alignment = HORIZONTAL_ALIGNMENT_LEFT
		out.pressed.connect(_close)
		options.add_child(out)


func _on_choice(choice: DialogueChoice) -> void:
	if not choice.once_flag.is_empty():
		Story.set_flag(choice.once_flag, true)

	_run_actions(choice.actions)
	if _resolve_pending():
		return

	if choice.next.is_empty():
		_close()
	else:
		_goto(choice.next)


func _run_actions(list: Array) -> void:
	for action in list:
		if action != null:
			action.run(current_npc, player, self)

# ------------------------------------------------- what actions ask us to do

func request_trade() -> void:
	_pending = "trade"


func request_combat() -> void:
	_pending = "combat"


func request_flee() -> void:
	_pending = "flee"


func request_end() -> void:
	_pending = "end"


## Returns true when the conversation is over and the caller should stop.
func _resolve_pending() -> bool:
	if _pending.is_empty():
		return false

	var what: String = _pending
	var npc = current_npc
	_pending = ""

	match what:
		"trade":
			_close()
			var window = get_tree().get_first_node_in_group("trade_window")
			if window != null:
				window.open(npc, player)
		"combat":
			_close()
			Game.start_battle(battle_scene_path, npc)
		"flee":
			_close()
			Game.end_battle.call_deferred()
		_:
			_close()
	return true


func _close() -> void:
	current_npc = null
	_tree = null
	_node = null
	hide_dialogue()
	if player != null and is_instance_valid(player):
		player.dialogue_open = false
	closed.emit()

# ------------------------------------------------------------- default tree

## The old hardcoded options, expressed as a tree. Any NPC without a dialogue
## resource gets this, so nothing breaks and the format has a worked example.
func _default_tree(npc) -> DialogueTree:
	var tree := DialogueTree.new()
	tree.start_id = &"start"

	var start := DialogueNode.new()
	start.id = &"start"
	start.text = npc.greeting if "greeting" in npc else "..."

	var hi := DialogueChoice.new()
	hi.text = "Hi"
	hi.next = &"chat"
	hi.actions = [_action(DialogueAction.Kind.CHANGE_AFFINITY, &"", 1)]
	start.choices.append(hi)

	_append_shared_choices(start, npc)
	tree.nodes.append(start)

	var chat := DialogueNode.new()
	chat.id = &"chat"
	chat.text = npc.response if "response" in npc else "..."
	_append_shared_choices(chat, npc)
	tree.nodes.append(chat)

	return tree


## Follow / wait / trade / fight / leave — the options that depend on what the
## NPC is rather than on what's been said.
func _append_shared_choices(node: DialogueNode, npc) -> void:
	if npc.has_method("is_ally") and npc.is_ally():
		var following: bool = npc.has_method("is_following") and npc.is_following()
		var follow := DialogueChoice.new()
		follow.text = "Wait here" if following else "Follow me"
		follow.next = &"chat"
		follow.actions = [_action(
			DialogueAction.Kind.STOP_FOLLOWING if following else DialogueAction.Kind.START_FOLLOWING
		)]
		node.choices.append(follow)

	if "is_merchant" in npc and npc.is_merchant:
		var trade := DialogueChoice.new()
		trade.text = "Trade"
		trade.actions = [_action(DialogueAction.Kind.OPEN_TRADE)]
		node.choices.append(trade)

	if npc.has_method("is_enemy") and npc.is_enemy() and not Game.in_battle():
		var fight := DialogueChoice.new()
		fight.text = "Fight!"
		fight.actions = [_action(DialogueAction.Kind.START_COMBAT)]
		node.choices.append(fight)

	if Game.in_battle():
		var flee := DialogueChoice.new()
		flee.text = "Flee the battle"
		flee.actions = [_action(DialogueAction.Kind.FLEE_BATTLE)]
		node.choices.append(flee)

	var leave := DialogueChoice.new()
	leave.text = "Exit"
	node.choices.append(leave)


func _action(kind: DialogueAction.Kind, key: StringName = &"", amount: int = 0) -> DialogueAction:
	var action := DialogueAction.new()
	action.kind = kind
	action.key = key
	action.amount = amount
	return action
