class_name BattleLog
extends RefCounted
## Per-battle statistics. The battle map owns one and reports events to it.

var damage_dealt: Dictionary = {}      # unit -> total
var damage_taken: Dictionary = {}
var kills: Dictionary = {}
var healing_done: Dictionary = {}
var names: Dictionary = {}             # unit -> display name, kept for the dead

var rounds: int = 0
var xp_awarded: int = 0
var gold_looted: int = 0


func note_name(unit) -> void:
	if unit != null and not names.has(unit):
		names[unit] = unit.display_name if "display_name" in unit else "Unit"


func record_damage(attacker, target, amount: int) -> void:
	if amount <= 0:
		return
	note_name(attacker)
	note_name(target)
	if attacker != null:
		damage_dealt[attacker] = damage_dealt.get(attacker, 0) + amount
	if target != null:
		damage_taken[target] = damage_taken.get(target, 0) + amount


func record_healing(healer, amount: int) -> void:
	if amount <= 0 or healer == null:
		return
	note_name(healer)
	healing_done[healer] = healing_done.get(healer, 0) + amount


func record_kill(killer) -> void:
	if killer == null:
		return
	note_name(killer)
	kills[killer] = kills.get(killer, 0) + 1


func name_of(unit) -> String:
	return names.get(unit, "Unit")


## The unit with the highest value in a tally, as { unit, name, value }.
## Returns null when nobody scored.
func leader(tally: Dictionary, among: Array = []):
	var best = null
	var best_value: int = 0
	for unit in tally.keys():
		if not among.is_empty() and not among.has(unit):
			continue
		var value: int = tally[unit]
		if value > best_value:
			best_value = value
			best = unit
	if best == null:
		return null
	return {"unit": best, "name": name_of(best), "value": best_value}


## Every participant's totals, sorted by damage dealt.
func rows_for(units: Array) -> Array:
	var out: Array = []
	for unit in units:
		out.append({
			"name": name_of(unit),
			"dealt": damage_dealt.get(unit, 0),
			"taken": damage_taken.get(unit, 0),
			"kills": kills.get(unit, 0),
			"alive": unit != null and is_instance_valid(unit)
				and (not unit.has_method("is_alive") or unit.is_alive()),
		})
	out.sort_custom(func(a, b): return a["dealt"] > b["dealt"])
	return out
