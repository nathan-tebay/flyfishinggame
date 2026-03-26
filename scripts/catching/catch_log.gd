class_name CatchLog
extends RefCounted

# Session catch data. Persisted immediately to DB via DatabaseManager.
# LogbookPanel reads from catches[] and sorted_catches().

var catches: Array = []
var _sort_mode: int = 0   # 0 = order caught, 1 = by size desc, 2 = by species asc


func record_catch(fish: FishAI, fly_name: String, fly_stage: String) -> void:
	var species_str: String = FishAI.SPECIES_NAMES[fish.species] as String
	var size_cm := _size_cm(fish.size_class, fish.variant_seed)

	var entry := {
		"species":           species_str,
		"species_int":       fish.species,
		"size_class":        fish.size_class,
		"size_cm":           size_cm,
		"fly_name":          fly_name,
		"fly_stage":         fly_stage,
		"hatch_state":       HatchManager.hatch_state_name(),
		"time_of_day":       TimeOfDay.period_name(),
		"position_x":        fish.position.x,
		"fish_variant_seed": fish.variant_seed,
		"photo":             _photo_data(fish),
	}
	catches.append(entry)

	print("CatchLog: %s %.0f cm on %s | %s | %s" % [
		species_str, size_cm, fly_name,
		entry["hatch_state"], entry["time_of_day"],
	])

	if GameManager.session_id >= 0:
		DatabaseManager.save_catch(GameManager.session_id, {
			"species":           species_str,
			"size_cm":           size_cm,
			"fly_name":          fly_name,
			"fly_stage":         fly_stage,
			"hatch_state":       entry["hatch_state"],
			"time_of_day":       entry["time_of_day"],
			"section_index":     0,
			"position_x":        fish.position.x,
			"fish_variant_seed": fish.variant_seed,
		})


func sorted_catches() -> Array:
	var result := catches.duplicate()
	if _sort_mode == 1:
		result.sort_custom(_sort_by_size)
	elif _sort_mode == 2:
		result.sort_custom(_sort_by_species)
	return result


func cycle_sort() -> void:
	_sort_mode = (_sort_mode + 1) % 3


func sort_mode_name() -> String:
	match _sort_mode:
		1:  return "SIZE"
		2:  return "SPECIES"
		_:  return "CAUGHT"


func _size_cm(size_class: int, variant_seed: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed + 55555
	match size_class:
		0:   return rng.randf_range(18.0, 28.0)   # SMALL
		1:   return rng.randf_range(30.0, 45.0)   # MEDIUM
		_:   return rng.randf_range(48.0, 65.0)   # LARGE


func _photo_data(fish: FishAI) -> Dictionary:
	var renderer := fish.get_node_or_null("FishRenderer") as FishRenderer
	if renderer == null:
		return {}
	return {
		"body_w":     renderer._body_w,
		"body_h":     renderer._body_h,
		"base_color": renderer._base_color,
		"species":    fish.species,
		"size_class": fish.size_class,
	}


static func _sort_by_size(a: Dictionary, b: Dictionary) -> bool:
	return (a["size_cm"] as float) > (b["size_cm"] as float)


static func _sort_by_species(a: Dictionary, b: Dictionary) -> bool:
	return (a["species"] as String) < (b["species"] as String)
