class_name DriftController
extends Node

# Tracks drag accumulation during fly drift.
# drag_factor: 0.0 = natural drift, 1.0 = fully dragged.
# Receives mend events to reset drag; accumulation resumes automatically.

signal drag_changed(drag_factor: float)

const DRAG_RATE  := 0.07   # drag added per second during active drift
const MEND_RESET := 0.65   # drag removed per mend action

var drag_factor: float = 0.0

var _drifting: bool = false


func _process(delta: float) -> void:
	if not _drifting:
		return
	drag_factor = minf(drag_factor + DRAG_RATE * delta, 1.0)
	drag_changed.emit(drag_factor)


func on_drift_started() -> void:
	_drifting   = true
	drag_factor = 0.0
	drag_changed.emit(drag_factor)
	if OS.is_debug_build():
		print("DriftController: drift started")


func on_drift_ended() -> void:
	_drifting   = false
	drag_factor = 0.0


func on_mend(direction: int) -> void:
	drag_factor = maxf(0.0, drag_factor - MEND_RESET)
	drag_changed.emit(drag_factor)
	if OS.is_debug_build():
		var dir_name := "upstream" if direction < 0 else "downstream"
		print("DriftController: mend %s | drag=%.2f" % [dir_name, drag_factor])
