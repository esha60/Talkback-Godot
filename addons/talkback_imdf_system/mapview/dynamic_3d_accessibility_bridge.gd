# Dynamic 3D Accessibility Bridge
# Projects 3D object positions/bounds onto a 2D screen overlay as invisible Buttons
# for Android AccessKit/TalkBack interaction.

extends Node

class_name Dynamic3DAccessibilityBridge

# Ordinals for Godot 4.7 compatibility
const ACCESSIBILITY_SCREEN_READER_FEATURE := 34
const TEXT_TO_SPEECH_FEATURE := 19

signal target_focused(unit_id: String)
signal target_pressed(unit_id: String)

# Configuration
var camera: Camera3D = null
var accessibility_enabled: bool = true

# Tracking data
var _targets: Dictionary = {}        # unit_id -> Dictionary { "node": Node3D, "aabb": AABB, "tooltip": String }
var _accessibility_nodes: Dictionary = {}  # unit_id -> Button
var _canvas: CanvasLayer = null
var _overlay_container: Control = null
var _focused_unit: String = ""

func _ready() -> void:
	# Create overlay UI container
	_canvas = CanvasLayer.new()
	_canvas.layer = 100 # Draw on top of everything
	add_child(_canvas)
	
	_overlay_container = Control.new()
	_overlay_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.add_child(_overlay_container)

func register_target(unit_id: String, node: Node3D, tooltip: String = "", custom_aabb: AABB = AABB()) -> void:
	var target_data = {
		"node": node,
		"aabb": custom_aabb,
		"tooltip": tooltip if tooltip != "" else unit_id
	}
	_targets[unit_id] = target_data
	_rebuild_overlay()

func unregister_target(unit_id: String) -> void:
	_targets.erase(unit_id)
	_rebuild_overlay()

func clear_targets() -> void:
	_targets.clear()
	_rebuild_overlay()

func _rebuild_overlay() -> void:
	# Clear old buttons
	for unit_id in _accessibility_nodes:
		var btn = _accessibility_nodes[unit_id]
		if is_instance_valid(btn):
			btn.queue_free()
	_accessibility_nodes.clear()
	
	# Determine traversal order (can sort by screen position or depth)
	var traversal_order := _compute_traversal_order()
	
	for unit_id in traversal_order:
		var data = _targets[unit_id]
		var btn = Button.new()
		btn.name = "A11y3DObject_%s" % unit_id
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.flat = true
		btn.text = ""
		btn.tooltip_text = data["tooltip"]
		btn.modulate.a = 0.0
		
		btn.focus_entered.connect(_on_node_focus_entered.bind(unit_id))
		btn.pressed.connect(_on_node_pressed.bind(unit_id))
		
		_overlay_container.add_child(btn)
		_accessibility_nodes[unit_id] = btn
		
	_assign_flow_to_order(traversal_order)
	_sync_positions()

func _process(_delta: float) -> void:
	if not accessibility_enabled or not is_instance_valid(camera):
		# Hide all buttons
		for unit_id in _accessibility_nodes:
			var btn = _accessibility_nodes[unit_id]
			if is_instance_valid(btn):
				btn.position = Vector2(-10000, -10000)
				btn.disabled = true
		return
		
	_sync_positions()
	
	# Update traversal order dynamically if screen layout changes
	var current_order := _compute_traversal_order()
	# Reorder buttons in the scene tree to match traversal order
	for i in range(current_order.size()):
		var unit_id = current_order[i]
		if _accessibility_nodes.has(unit_id):
			var btn = _accessibility_nodes[unit_id]
			if is_instance_valid(btn):
				_overlay_container.move_child(btn, i)
	
	_assign_flow_to_order(current_order)

func _sync_positions() -> void:
	if not is_instance_valid(camera):
		return
		
	for unit_id in _accessibility_nodes:
		var btn = _accessibility_nodes[unit_id]
		if not is_instance_valid(btn):
			continue
			
		var data = _targets[unit_id]
		var node: Node3D = data["node"]
		if not is_instance_valid(node) or not node.is_inside_tree():
			btn.position = Vector2(-10000, -10000)
			btn.disabled = true
			continue
			
		var transformed_rect = _project_node_bounds(node, data["aabb"])
		if transformed_rect == Rect2():
			# Behind camera or invalid bounds
			btn.position = Vector2(-10000, -10000)
			btn.disabled = true
		else:
			btn.position = transformed_rect.position
			btn.size = transformed_rect.size
			btn.disabled = false

# Projects a Node3D's AABB to 2D screen coordinates
func _project_node_bounds(node: Node3D, custom_aabb: AABB) -> Rect2:
	var aabb := custom_aabb
	if aabb == AABB():
		# Try to get AABB from VisualInstance3D or CollisionShape3D
		if node is VisualInstance3D:
			aabb = node.get_aabb()
		elif node.has_method("get_aabb"):
			aabb = node.call("get_aabb")
		else:
			# Fallback to a default small bounds centered at the node's position
			aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1.0, 1.0, 1.0))
			
	var corners = _get_aabb_corners(aabb)
	var global_transform = node.global_transform
	
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	var any_visible := false
	
	for corner in corners:
		var world_pos = global_transform * corner
		if not camera.is_position_behind(world_pos):
			var screen_pos = camera.unproject_position(world_pos)
			min_x = min(min_x, screen_pos.x)
			min_y = min(min_y, screen_pos.y)
			max_x = max(max_x, screen_pos.x)
			max_y = max(max_y, screen_pos.y)
			any_visible = true
			
	if not any_visible:
		return Rect2()
		
	# Pad the bounding box slightly for easier touch target sizing
	var width = max_x - min_x
	var height = max_y - min_y
	
	# Minimum touch target size (44x44 pixels)
	if width < 44.0:
		var diff = 44.0 - width
		min_x -= diff / 2.0
		width = 44.0
	if height < 44.0:
		var diff = 44.0 - height
		min_y -= diff / 2.0
		height = 44.0
		
	return Rect2(Vector2(min_x, min_y), Vector2(width, height))

func _get_aabb_corners(aabb: AABB) -> Array[Vector3]:
	var corners: Array[Vector3] = []
	var pos = aabb.position
	var size = aabb.size
	corners.append(pos)
	corners.append(pos + Vector3(size.x, 0, 0))
	corners.append(pos + Vector3(0, size.y, 0))
	corners.append(pos + Vector3(0, 0, size.z))
	corners.append(pos + Vector3(size.x, size.y, 0))
	corners.append(pos + Vector3(size.x, 0, size.z))
	corners.append(pos + Vector3(0, size.y, size.z))
	corners.append(pos + size)
	return corners

# Sorts targets for swipe navigation: Top-to-Bottom, then Left-to-Right
# in 2D screen coordinates, which is highly intuitive for screen readers.
func _compute_traversal_order() -> Array:
	var order = _targets.keys()
	if not is_instance_valid(camera):
		return order
		
	# Cache screen positions for sorting
	var screen_positions = {}
	for unit_id in order:
		var data = _targets[unit_id]
		var node = data["node"]
		if is_instance_valid(node) and node.is_inside_tree():
			var world_pos = node.global_position
			if not camera.is_position_behind(world_pos):
				screen_positions[unit_id] = camera.unproject_position(world_pos)
			else:
				# Place behind-camera nodes far away/last
				screen_positions[unit_id] = Vector2(99999, 99999)
		else:
			screen_positions[unit_id] = Vector2(99999, 99999)
			
	order.sort_custom(func(a, b):
		var pos_a = screen_positions[a]
		var pos_b = screen_positions[b]
		if abs(pos_a.y - pos_b.y) > 1.0: # 1 pixel tolerance
			return pos_a.y < pos_b.y
		return pos_a.x < pos_b.x
	)
	
	return order

func _assign_flow_to_order(order: Array) -> void:
	for i in range(order.size() - 1):
		if not _accessibility_nodes.has(order[i]) or not _accessibility_nodes.has(order[i + 1]):
			continue
		var node: Button = _accessibility_nodes[order[i]]
		var next_node: Button = _accessibility_nodes[order[i + 1]]
		node.set("accessibility_flow_to_nodes", [node.get_path_to(next_node)])

func _on_node_focus_entered(unit_id: String) -> void:
	_focused_unit = unit_id
	target_focused.emit(unit_id)
	
func _on_node_pressed(unit_id: String) -> void:
	target_pressed.emit(unit_id)

func set_focused_unit(unit_id: String) -> void:
	if _focused_unit != unit_id:
		_focused_unit = unit_id
	if _accessibility_nodes.has(unit_id):
		var node: Button = _accessibility_nodes[unit_id]
		if is_instance_valid(node) and not node.has_focus():
			node.grab_focus()
