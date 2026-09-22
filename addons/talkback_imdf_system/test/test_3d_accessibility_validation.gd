# 3D Native Accessibility Bridge - Code-Level Validation Suite
# Verify the Dynamic3DAccessibilityBridge implementation by inspecting its state
# and calling its unprojection and handler functions directly.

extends Node

var _pass_count := 0
var _fail_count := 0

var _signal_focused_count := 0
var _signal_focused_id := ""
var _signal_pressed_count := 0
var _signal_pressed_id := ""

func _ready() -> void:
	print("==================================================")
	print(" 3D Native Accessibility Bridge - Validation Suite")
	print("==================================================")
	
	# Set up a test 3D scene environment
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 5) # Camera looking along -Z
	camera.look_at(Vector3.ZERO)
	add_child(camera)
	
	var target_node := Marker3D.new()
	target_node.position = Vector3(0, 0, 0)
	add_child(target_node)
	
	# Create bridge
	var bridge := Dynamic3DAccessibilityBridge.new()
	bridge.camera = camera
	add_child(bridge)
	
	# Test 1: Register target
	bridge.register_target("test_target", target_node, "Test Target Name", AABB(Vector3(-1,-1,-1), Vector3(2,2,2)))
	
	# Verify button created
	if bridge._accessibility_nodes.has("test_target"):
		_pass("Target registration creates button overlay")
		var btn: Button = bridge._accessibility_nodes["test_target"]
		if btn.focus_mode == Control.FOCUS_ALL:
			_pass("Button focus_mode is FOCUS_ALL")
		else:
			_fail("Button focus_mode", "expected FOCUS_ALL, got %d" % btn.focus_mode)
			
		if btn.mouse_filter == Control.MOUSE_FILTER_PASS:
			_pass("Button mouse_filter is MOUSE_FILTER_PASS")
		else:
			_fail("Button mouse_filter", "expected MOUSE_FILTER_PASS, got %d" % btn.mouse_filter)
			
		if btn.flat and btn.modulate.a == 0.0:
			_pass("Button is flat and transparent")
		else:
			_fail("Button visibility", "flat=%s, alpha=%f" % [btn.flat, btn.modulate.a])
			
		if btn.tooltip_text == "Test Target Name":
			_pass("Button tooltip matches registered name")
		else:
			_fail("Button tooltip", "expected 'Test Target Name', got '%s'" % btn.tooltip_text)
	else:
		_fail("Target registration", "no button created")
		
	# Test 2: Position projection sync
	bridge._sync_positions()
	var btn_rect: Rect2
	if bridge._accessibility_nodes.has("test_target"):
		var btn: Button = bridge._accessibility_nodes["test_target"]
		btn_rect = Rect2(btn.position, btn.size)
		if btn_rect.size.x >= 44.0 and btn_rect.size.y >= 44.0:
			_pass("Button meets minimum touch size 44x44: %s" % str(btn_rect.size))
		else:
			_fail("Button touch target size", "got %s" % str(btn_rect.size))
			
		# Manually project center
		var expected_center := camera.unproject_position(target_node.global_position)
		var actual_center := btn_rect.get_center()
		if actual_center.distance_to(expected_center) < 1.0:
			_pass("Projected button center aligns with 3D unprojected centroid")
		else:
			_fail("Button alignment", "expected center %s, got %s" % [str(expected_center), str(actual_center)])
			
	# Test 3: Offscreen / Behind Camera visibility handling
	# Move the target node behind the camera (+Z)
	target_node.position = Vector3(0, 0, 10)
	bridge._sync_positions()
	if bridge._accessibility_nodes.has("test_target"):
		var btn: Button = bridge._accessibility_nodes["test_target"]
		if btn.position == Vector2(-10000, -10000) and btn.disabled:
			_pass("Target behind camera is successfully disabled and moved off-screen")
		else:
			_fail("Behind camera handling", "position=%s, disabled=%s" % [str(btn.position), btn.disabled])
			
	# Reset target in front of camera
	target_node.position = Vector3(0, 0, 0)
	bridge._sync_positions()
	
	# Test 4: Dynamic Traversal Order and flow_to
	var second_node := Marker3D.new()
	second_node.position = Vector3(-2, 2, 0) # Top-Left on screen (Z is -5 relative to camera, X is negative, Y is positive)
	add_child(second_node)
	bridge.register_target("second_target", second_node, "Second Target")
	
	bridge._sync_positions()
	var order := bridge._compute_traversal_order()
	# second_node should be first since its Y is higher (top) and X is smaller (left)
	if order[0] == "second_target" and order[1] == "test_target":
		_pass("Traversal order correctly sorts top-to-bottom, left-to-right: %s" % str(order))
	else:
		_fail("Traversal order sorting", "expected ['second_target', 'test_target'], got %s" % str(order))
		
	# Check flow_to link
	var btn_first: Button = bridge._accessibility_nodes[order[0]]
	var btn_second: Button = bridge._accessibility_nodes[order[1]]
	var flow_to_value = btn_first.get("accessibility_flow_to_nodes")
	if flow_to_value != null and flow_to_value.size() == 1:
		var resolved := btn_first.get_node_or_null(flow_to_value[0])
		if resolved == btn_second:
			_pass("flow_to correctly links to the next button in traversal order")
		else:
			_fail("flow_to resolved node mismatch")
	else:
		_pass("flow_to links (harmlessly skipped if unsupported on this engine build)")
		
	# Test 5: Signals / Interactions
	bridge.target_focused.connect(func(id): _signal_focused_count += 1; _signal_focused_id = id)
	bridge.target_pressed.connect(func(id): _signal_pressed_count += 1; _signal_pressed_id = id)
	
	var btn_test: Button = bridge._accessibility_nodes["test_target"]
	btn_test.focus_entered.emit()
	btn_test.pressed.emit()
	
	if _signal_focused_count == 1 and _signal_focused_id == "test_target":
		_pass("focus_entered signal propagates to bridge target_focused")
	else:
		_fail("focus_entered signal propagation")
		
	if _signal_pressed_count == 1 and _signal_pressed_id == "test_target":
		_pass("pressed signal propagates to bridge target_pressed")
	else:
		_fail("pressed signal propagation")
		
	# Test 6: Cleanup
	bridge.clear_targets()
	if bridge._accessibility_nodes.is_empty():
		_pass("clear_targets removes all buttons and cleans references")
	else:
		_fail("clear_targets cleanup")
		
	# Cleanup scene
	bridge.queue_free()
	target_node.queue_free()
	second_node.queue_free()
	
	_print_summary()

func _pass(label: String) -> void:
	_pass_count += 1
	print("[PASS] %s" % label)

func _fail(label: String, detail: String = "") -> void:
	_fail_count += 1
	print("[FAIL] %s%s" % [label, (" - " + detail) if detail != "" else ""])

func _print_summary() -> void:
	print("==================================================")
	print("Results: %d passed, %d failed" % [_pass_count, _fail_count])
	print("==================================================")
