extends Node

enum Period { DAWN, MORNING, MIDDAY, AFTERNOON, DUSK, NIGHT }

signal dawn
signal period_changed(new_period: Period)

# Real seconds per in-game hour. Default: 60s = 1 hr (full day in ~24 min).
# Set to 3600.0 for real-time (1:1).
var seconds_per_hour: float = 60.0

var current_hour: float = 6.0   # 0.0–24.0
var current_period: Period = Period.DAWN
var light_level: float = 0.0    # 0.0 (night) → 1.0 (midday)
var sun_angle: float = 0.0      # degrees: 0 = east/dawn, 180 = west/dusk

var _previous_period: Period = Period.DAWN


func _ready() -> void:
	var saved_scale := DatabaseManager.get_setting("time_scale_seconds_per_hour", "60.0")
	seconds_per_hour = float(saved_scale)

	var saved_hour := DatabaseManager.get_setting("session_start_hour", "6.0")
	current_hour = float(saved_hour)

	_recalculate()


func _process(delta: float) -> void:
	current_hour = fmod(current_hour + delta / seconds_per_hour, 24.0)
	_recalculate()


func _recalculate() -> void:
	_update_light_level()
	_update_sun_angle()
	_check_period()


func _check_period() -> void:
	var new_period := _hour_to_period(current_hour)
	if new_period == current_period:
		return
	var was_night := current_period == Period.NIGHT
	_previous_period = current_period
	current_period = new_period
	period_changed.emit(current_period)
	if current_period == Period.DAWN and was_night:
		dawn.emit()


func _hour_to_period(hour: float) -> Period:
	if   hour >= 5.0  and hour < 7.0:  return Period.DAWN
	elif hour >= 7.0  and hour < 11.0: return Period.MORNING
	elif hour >= 11.0 and hour < 14.0: return Period.MIDDAY
	elif hour >= 14.0 and hour < 17.0: return Period.AFTERNOON
	elif hour >= 17.0 and hour < 20.0: return Period.DUSK
	else:                               return Period.NIGHT


func _update_light_level() -> void:
	# Sine arc from hour 6 (sunrise) to hour 18 (sunset), zero outside
	if current_hour >= 6.0 and current_hour <= 18.0:
		var t := (current_hour - 6.0) / 12.0  # 0.0 → 1.0 → 0.0
		light_level = sin(t * PI)
	else:
		light_level = 0.0


func _update_sun_angle() -> void:
	# 0° at dawn (east/right), 180° at dusk (west/left)
	sun_angle = clampf((current_hour - 6.0) / 12.0, 0.0, 1.0) * 180.0


# --- Public API ---

func set_start_hour(hour: float) -> void:
	current_hour = clampf(hour, 0.0, 23.99)
	_recalculate()


func set_time_scale(real_seconds_per_hour: float) -> void:
	seconds_per_hour = maxf(real_seconds_per_hour, 1.0)


func period_name() -> String:
	return Period.keys()[current_period]


func is_feeding_window() -> bool:
	return current_period == Period.DAWN or current_period == Period.DUSK
