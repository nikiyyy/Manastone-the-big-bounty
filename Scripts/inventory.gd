class_name Inventory
extends Resource
## Backpack plus three equipment slots. Owned by any unit that can carry things.

signal inventory_changed

const SLOT_LABELS := {
	Item.Slot.MAIN_HAND: "Main hand",
	Item.Slot.OFF_HAND: "Off hand",
	Item.Slot.HELMET: "Helmet",
	Item.Slot.NECKLACE: "Necklace",
	Item.Slot.TORSO: "Torso",
	Item.Slot.RING_1: "Ring",
	Item.Slot.RING_2: "Ring",
	Item.Slot.HANDS: "Hands",
	Item.Slot.FEET: "Feet",
	Item.Slot.CHARM_1: "Charm",
	Item.Slot.CHARM_2: "Charm",
}

const SLOT_ORDER := [
	Item.Slot.HELMET, Item.Slot.NECKLACE, Item.Slot.TORSO,
	Item.Slot.HANDS, Item.Slot.FEET,
	Item.Slot.MAIN_HAND, Item.Slot.OFF_HAND,
	Item.Slot.RING_1, Item.Slot.RING_2,
	Item.Slot.CHARM_1, Item.Slot.CHARM_2,
]

## Slots an item can go into besides its own — paired slots accept each other.
const SLOT_ALIASES := {
	Item.Slot.RING_1: [Item.Slot.RING_1, Item.Slot.RING_2],
	Item.Slot.RING_2: [Item.Slot.RING_1, Item.Slot.RING_2],
	Item.Slot.CHARM_1: [Item.Slot.CHARM_1, Item.Slot.CHARM_2],
	Item.Slot.CHARM_2: [Item.Slot.CHARM_1, Item.Slot.CHARM_2],
}

@export var capacity: int = 18
@export var items: Array[Item] = []
@export var equipped: Dictionary = {}      # Item.Slot -> Item


func is_full() -> bool:
	return items.size() >= capacity


func add(item: Item) -> bool:
	if item == null or is_full():
		return false
	items.append(item)
	changed.emit()
	return true


func remove(item: Item) -> bool:
	var i: int = items.find(item)
	if i < 0:
		return false
	items.remove_at(i)
	changed.emit()
	return true


## Equip into the item's own slot, or the first free slot of its pair.
func equip(item: Item) -> bool:
	if item == null or item.slot == Item.Slot.NONE:
		return false
	var candidates: Array = SLOT_ALIASES.get(item.slot, [item.slot])
	for slot in candidates:
		if equipped.get(slot) == null and can_equip(item, slot):
			return equip_to(item, slot)
	return equip_to(item, candidates[0])


func unequip(slot: int) -> bool:
	var current = equipped.get(slot)
	if current == null:
		return false
	equipped.erase(slot)
	if not is_full():
		items.append(current)
	changed.emit()
	return true


func get_equipped(slot: int) -> Item:
	return equipped.get(slot)


func total_armor() -> int:
	var total: int = 0
	for item in equipped.values():
		total += item.armor_bonus
	return total


func total_damage_bonus() -> int:
	var total: int = 0
	for item in equipped.values():
		total += item.damage_bonus
	return total
	
## Equip into an explicit slot, rejecting items that don't fit it.
func equip_to(item: Item, slot: int) -> bool:
	if not can_equip(item, slot):
		return false
	unequip(slot)
	items.erase(item)
	equipped[slot] = item
	if slot == Item.Slot.MAIN_HAND and item.hands == Item.Hands.TWO_HANDED:
		unequip(Item.Slot.OFF_HAND)
	inventory_changed.emit()
	return true


func swap_items(a: int, b: int) -> void:
	if a == b or a < 0 or a >= items.size():
		return
	if b >= items.size():
		var moved: Item = items[a]
		items.remove_at(a)
		items.append(moved)
	else:
		var tmp: Item = items[a]
		items[a] = items[b]
		items[b] = tmp
	inventory_changed.emit()

## Take an item out of another inventory's backpack and wear it here.
func equip_from(source: Inventory, item: Item, slot: int) -> bool:
	if source == null or not can_equip(item, slot):
		return false
	unequip_to(source, slot)
	source.items.erase(item)
	equipped[slot] = item
	if slot == Item.Slot.MAIN_HAND and item.hands == Item.Hands.TWO_HANDED:
		unequip_to(source, Item.Slot.OFF_HAND)
	inventory_changed.emit()
	source.inventory_changed.emit()
	return true


## A two-handed weapon in the main hand blocks the off hand entirely.
func off_hand_blocked() -> bool:
	var main: Item = equipped.get(Item.Slot.MAIN_HAND)
	return main != null and main.hands == Item.Hands.TWO_HANDED


## Does this item fit that slot? Rings and charms fit either of their pair.
func fits(item: Item, slot: int) -> bool:
	if item == null or item.slot == Item.Slot.NONE:
		return false
	if item.slot == slot:
		return true
	return SLOT_ALIASES.get(item.slot, []).has(slot)


func can_equip(item: Item, slot: int) -> bool:
	if not fits(item, slot):
		return false
	if slot == Item.Slot.OFF_HAND and off_hand_blocked():
		return false
	return true

## Remove what's worn in a slot and drop it into another inventory's backpack.
func unequip_to(target: Inventory, slot: int) -> bool:
	var current = equipped.get(slot)
	if current == null:
		return false
	equipped.erase(slot)
	if target != null and not target.is_full():
		target.items.append(current)
	inventory_changed.emit()
	return true
	
## Total elemental resistance from everything worn.
func total_resistances() -> Resistances:
	var out := Resistances.new()
	for item in equipped.values():
		if item.resistances == null:
			continue
		for element in DamageType.ELEMENTS:
			out.add_for(element, item.resistances.get_for(element))
	return out

## Total flat stat bonus from everything worn.
func total_stat_bonus(stat_name: String) -> int:
	var total: int = 0
	for item in equipped.values():
		if item.stat_bonus != null:
			total += item.stat_bonus.get_for(stat_name)
	return total
