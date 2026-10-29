extends SceneTree

var engine: LoopPhysicsEngine
var _pass_count := 0
var _fail_count := 0

func _fail(message: String) -> void:
	printerr("loop_physics_check: FAIL - %s" % message)
	_fail_count += 1

func _pass(message: String) -> void:
	print("loop_physics_check: PASS - %s" % message)
	_pass_count += 1

func _initialize() -> void:
	engine = LoopPhysicsEngine.new()
	engine.rod_bend_speed_scale = 2.0
	engine.rod_accel_scale = 100.0
	engine.line_base_speed = 10.0
	engine.base_loop_width = 0.08

	test_bend_from_elevation_velocity()
	test_bend_from_mouse_acceleration()
	test_loop_speed_increases_with_bend()
	test_loop_width_contracts_with_speed()
	test_loop_position_advances()
	test_loop_position_clamped_to_range()
	test_delivery_flag_sets_at_end()
	test_reset_clears_state()
	test_width_stays_within_bounds()
	test_physics_consistency_over_time()

	print("\n=== SUMMARY ===")
	print("Passed: %d" % _pass_count)
	print("Failed: %d" % _fail_count)

	if _fail_count > 0:
		quit(1)
	else:
		quit(0)


func test_bend_from_elevation_velocity() -> void:
	engine = LoopPhysicsEngine.new()
	var state1 = engine.update(0.016, 0.0, 0.0)
	if state1.bend_amount != 0.0:
		_fail("No motion should give 0 bend")
		return

	var state2 = engine.update(0.016, 1.0, 0.0)
	if state2.bend_amount <= 0.0:
		_fail("Fast elevation should increase bend")
		return
	if state2.bend_amount > 1.0:
		_fail("Bend should be clamped to [0, 1]")
		return

	_pass("Bend increases with elevation velocity")


func test_bend_from_mouse_acceleration() -> void:
	engine = LoopPhysicsEngine.new()
	var state1 = engine.update(0.016, 0.0, 0.0)
	var state2 = engine.update(0.016, 0.0, 50.0)
	if state2.bend_amount <= state1.bend_amount:
		_fail("Mouse motion should increase bend")
		return
	_pass("Bend increases with mouse acceleration")


func test_loop_speed_increases_with_bend() -> void:
	engine = LoopPhysicsEngine.new()
	var state1 = engine.update(0.016, 0.1, 0.0)
	var speed1 = state1.travel_speed

	var state2 = engine.update(0.016, 0.5, 0.0)
	var speed2 = state2.travel_speed

	if speed2 <= speed1:
		_fail("Higher bend should increase loop speed")
		return
	_pass("Loop speed increases with bend amount")


func test_loop_width_contracts_with_speed() -> void:
	engine = LoopPhysicsEngine.new()
	var state1 = engine.update(0.016, 0.1, 0.0)
	var width1 = state1.width

	var state2 = engine.update(0.016, 0.8, 0.0)
	var width2 = state2.width

	if width2 >= width1:
		_fail("Higher speed should tighten loop (shrink width)")
		return
	_pass("Loop width contracts with higher speed")


func test_loop_position_advances() -> void:
	engine = LoopPhysicsEngine.new()
	var prev_pos = 0.0

	for i in range(5):
		var state = engine.update(0.016, 0.5, 25.0)
		if state.position_along_line <= prev_pos:
			_fail("Loop position should advance monotonically (frame %d)" % i)
			return
		prev_pos = state.position_along_line

	_pass("Loop position advances over time")


func test_loop_position_clamped_to_range() -> void:
	engine = LoopPhysicsEngine.new()
	for i in range(50):
		var state = engine.update(0.016, 1.0, 100.0)
		if state.position_along_line < 0.0 or state.position_along_line > 1.0:
			_fail("Position out of bounds at frame %d: %f" % [i, state.position_along_line])
			return

	_pass("Loop position stays within [0, 1]")


func test_delivery_flag_sets_at_end() -> void:
	engine = LoopPhysicsEngine.new()
	var state = engine.update(0.016, 0.0, 0.0)
	if state.has_delivered:
		_fail("Should not be delivered at start")
		return

	for i in range(100):
		state = engine.update(0.016, 1.0, 50.0)
		if state.position_along_line >= 0.99:
			if not state.has_delivered:
				_fail("Should be delivered when position >= 0.99")
				return
			_pass("Delivery flag sets at position >= 0.99")
			return

	_fail("Loop never reached delivery position after 100 frames")


func test_reset_clears_state() -> void:
	engine = LoopPhysicsEngine.new()
	for i in range(10):
		engine.update(0.016, 0.5, 50.0)

	var state_before = engine.get_loop_state()
	if state_before.position_along_line <= 0.0:
		_fail("Position should advance before reset")
		return

	engine.reset_loop()
	var state_after = engine.get_loop_state()

	if state_after.position_along_line != 0.0:
		_fail("Reset should set position to 0")
		return
	if state_after.bend_amount != 0.0:
		_fail("Reset should set bend to 0")
		return
	if state_after.has_delivered:
		_fail("Reset should clear delivered flag")
		return

	_pass("Reset clears all state correctly")


func test_width_stays_within_bounds() -> void:
	engine = LoopPhysicsEngine.new()
	for i in range(100):
		var state = engine.update(0.016, randf() * 1.0, randf() * 100.0)
		if state.width < 0.02 or state.width > 0.15:
			_fail("Width out of bounds: %f at frame %d" % [state.width, i])
			return

	_pass("Loop width stays within [0.02, 0.15]")


func test_physics_consistency_over_time() -> void:
	engine = LoopPhysicsEngine.new()
	var prev_pos = 0.0
	var prev_width = 0.0

	for i in range(20):
		var state = engine.update(0.016, 0.3, 20.0)

		if state.position_along_line < prev_pos:
			_fail("Position should be monotonic at frame %d" % i)
			return
		prev_pos = state.position_along_line

		if i > 0:
			var width_delta = absf(state.width - prev_width)
			if width_delta > 0.02:
				_fail("Width oscillation too large at frame %d: delta=%f" % [i, width_delta])
				return
		prev_width = state.width

	_pass("Physics output is smooth and consistent")
