# Dynamic MapView Component
# Renders IMDF data with accessible controls for TalkBack navigation
#
# Features:
# - Renders rooms/units from IMDF data
# - TalkBack gesture integration
# - Focus indicators and accessibility labels
# - Dynamic room selection and navigation

extends Control

class_name DynamicMapView

# Godot 4.7 Stable compatibility: DisplayServer.Feature.FEATURE_ACCESSIBILITY_SCREEN_READER's
# raw ordinal value (34), referenced by number instead of by name so this script parses
# correctly on engine builds that may not declare that symbol (mirrors the same fix in
# talkback_gesture_handler.gd). has_feature() only needs the ordinal.
const ACCESSIBILITY_SCREEN_READER_FEATURE := 34

# Godot 4.7 Stable compatibility: there is no DisplayServer.tts_is_available() method
# (confirmed absent from doc/classes/DisplayServer.xml). The real, official way to check
# TTS support is DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH), whose
# raw ordinal is 19 (doc/classes/DisplayServer.xml:2740). Referenced by ordinal, same
# reasoning as ACCESSIBILITY_SCREEN_READER_FEATURE above.
const TEXT_TO_SPEECH_FEATURE := 19

## Emitted when a room/unit is selected
signal room_selected(unit_id: String, unit: IMDFParser.IMDFUnit)

## Emitted when navigation starts
signal navigation_started(from_unit: String, to_unit: String)

## Emitted when navigation completes
signal navigation_completed(route: Array)

# IMDF data
var _imdf_data: IMDFParser.IMDFData = null
var _navigation_graph: Array[IMDFParser.NavigationPath] = []

# Visualization
var _room_rects: Dictionary = {}  # unit_id -> Rect2
var _poi_positions: Dictionary = {}  # poi_id -> Vector2
var _canvas: CanvasLayer = null

# State
var _focused_unit: String = ""
var _current_route: Array[IMDFParser.IMDFUnit] = []
var _zoom_level: float = 1.0
var _pan_offset: Vector2 = Vector2.ZERO

# Configuration
var _room_color: Color = Color(0.2, 0.6, 1.0, 0.7)
var _room_border_color: Color = Color(0.1, 0.3, 0.8, 1.0)
var _room_border_width: float = 2.0
var _focused_color: Color = Color(1.0, 1.0, 0.0, 0.9)
var _focused_border_width: float = 4.0
var _poi_radius: float = 10.0

# Components
var _gesture_handler: TalkBackGestureHandler = null
var _accessibility_enabled: bool = true

# Native accessibility overlay (Native UI Bridge) - one invisible Button per room,
# kept in sync with _room_rects/_zoom_level/_pan_offset so AccessKit/TalkBack can
# expose and activate rooms without duplicating rendering or selection logic.
var _accessibility_nodes: Dictionary = {}  # unit_id -> Button

func _ready() -> void:
	custom_minimum_size = Vector2(800, 600)
	clip_contents = true
	
	# Setup gesture handler
	_gesture_handler = TalkBackGestureHandler.new()
	add_child(_gesture_handler)
	
	# Connect signals
	_gesture_handler.single_tap_detected.connect(_on_single_tap)
	_gesture_handler.double_tap_detected.connect(_on_double_tap)
	_gesture_handler.swipe_left_detected.connect(_on_swipe_left)
	_gesture_handler.swipe_right_detected.connect(_on_swipe_right)

	# Keep the accessibility overlay aligned whenever this control's own rect changes
	resized.connect(_sync_accessibility_positions)

	# Enable input
	set_process_input(true)
	set_process_unhandled_input(true)

func setup_from_imdf(imdf_data: IMDFParser.IMDFData) -> void:
	_imdf_data = imdf_data
	_navigation_graph = IMDFParser.build_navigation_graph(imdf_data)
	
	# Calculate room positions
	_calculate_room_positions()
	
	# Focus first room if available
	if _imdf_data.units.size() > 0:
		set_focused_room(_imdf_data.units[0].id)
	
	queue_redraw()
	_update_accessibility_tree()

func _calculate_room_positions() -> void:
	for unit in _imdf_data.units:
		if unit.geometry.size() == 0:
			continue
		
		# Calculate bounding box for unit geometry
		var min_x = INF
		var min_y = INF
		var max_x = -INF
		var max_y = -INF
		
		for point in unit.geometry:
			min_x = min(min_x, point.x)
			min_y = min(min_y, point.y)
			max_x = max(max_x, point.x)
			max_y = max(max_y, point.y)
		
		var rect = Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
		_room_rects[unit.id] = rect
		
		# Store POI positions
		for poi in unit.pois:
			_poi_positions[poi.id] = poi.position

func _draw() -> void:
	if not _imdf_data:
		return
	
	# Draw rooms
	for unit in _imdf_data.units:
		if unit.id not in _room_rects:
			continue
		
		var rect = _room_rects[unit.id]
		var is_focused = unit.id == _focused_unit
		
		# Transform for zoom and pan
		var transformed_rect = Rect2(
			(rect.position + _pan_offset) * _zoom_level,
			rect.size * _zoom_level
		)
		
		# Draw room background
		var room_color = _focused_color if is_focused else _room_color
		draw_rect(transformed_rect, room_color)
		
		# Draw room border
		var border_width = _focused_border_width if is_focused else _room_border_width
		draw_rect(transformed_rect, _room_border_color, false, border_width)
		
		# Draw room label
		var label_pos = transformed_rect.get_center()
		draw_string(ThemeDB.fallback_font, label_pos, unit.name, HORIZONTAL_ALIGNMENT_CENTER)
		
		# Draw geometry if available
		if unit.geometry.size() > 1:
			var points = PackedVector2Array()
			for point in unit.geometry:
				var transformed_point = (point + _pan_offset) * _zoom_level
				points.append(transformed_point)
			
			draw_colored_polygon(points, room_color)
	
	# Draw POIs
	for poi in _get_all_pois():
		var pos = (poi.position + _pan_offset) * _zoom_level
		draw_circle(pos, _poi_radius * _zoom_level, Color.RED)
		draw_string(ThemeDB.fallback_font, pos, poi.name, HORIZONTAL_ALIGNMENT_CENTER)

func _input(event: InputEvent) -> void:
	if not _accessibility_enabled or not _imdf_data:
		return
	
	# Handle mouse clicks for testing
	if event is InputEventMouseButton and event.pressed:
		var click_pos = get_local_mouse_position()
		_handle_click(click_pos)
		get_tree().root.set_input_as_handled()

func _handle_click(position: Vector2) -> void:
	# Find which room was clicked
	for unit_id in _room_rects:
		var rect = _room_rects[unit_id]
		var transformed_rect = Rect2(
			(rect.position + _pan_offset) * _zoom_level,
			rect.size * _zoom_level
		)
		
		if transformed_rect.has_point(position):
			set_focused_room(unit_id)
			break

func _on_single_tap() -> void:
	# Move focus to next room
	if _focused_unit == "":
		if _imdf_data.units.size() > 0:
			set_focused_room(_imdf_data.units[0].id)
	else:
		var current_index = -1
		for i in range(_imdf_data.units.size()):
			if _imdf_data.units[i].id == _focused_unit:
				current_index = i
				break
		
		var next_index = (current_index + 1) % _imdf_data.units.size()
		set_focused_room(_imdf_data.units[next_index].id)

func _on_double_tap() -> void:
	# Activate current room
	if _focused_unit != "":
		_activate_room(_focused_unit)

func _activate_room(unit_id: String) -> void:
	for unit in _imdf_data.units:
		if unit.id == unit_id:
			room_selected.emit(unit_id, unit)
			_announce("Selected " + unit.name)
			break

func _on_swipe_left() -> void:
	# Navigate left in room
	_announce("Navigating left")

func _on_swipe_right() -> void:
	# Navigate right in room
	_announce("Navigating right")

func set_focused_room(unit_id: String, announce: bool = true) -> void:
	if _focused_unit != unit_id:
		_focused_unit = unit_id
		queue_redraw()

		# Find the unit and announce it
		if announce:
			for unit in _imdf_data.units:
				if unit.id == unit_id:
					_announce("Focused on " + unit.name + ". " + _get_unit_description(unit))
					break

	# Keep native Control focus (and therefore the AccessKit/TalkBack focus ring)
	# in sync with the logical room focus, regardless of what triggered it.
	# The has_focus() guard prevents grab_focus() -> focus_entered -> set_focused_room()
	# from recursing more than one level deep.
	if _accessibility_nodes.has(unit_id):
		var node: Button = _accessibility_nodes[unit_id]
		if is_instance_valid(node) and not node.has_focus():
			node.grab_focus()

func navigate_to_room(from_unit_id: String, to_unit_id: String) -> bool:
	_current_route = IMDFParser.find_accessible_route(_imdf_data, from_unit_id, to_unit_id)
	
	if _current_route.size() == 0:
		_announce("No accessible route found")
		return false
	
	navigation_started.emit(from_unit_id, to_unit_id)
	var route_names = []
	for unit in _current_route:
		route_names.append(unit.name)
	
	_announce("Navigation path: " + ", ".join(route_names))
	return true

func _get_unit_description(unit: IMDFParser.IMDFUnit) -> String:
	var description = "Type: " + unit.unit_type
	
	if unit.pois.size() > 0:
		description += ". Points of interest: "
		var poi_names = []
		for poi in unit.pois:
			poi_names.append(poi.name)
		description += ", ".join(poi_names)
	
	return description

func _get_all_pois() -> Array[IMDFParser.IMDFDOI]:
	var all_pois: Array[IMDFParser.IMDFDOI] = []
	
	for unit in _imdf_data.units:
		for poi in unit.pois:
			all_pois.append(poi)
	
	return all_pois

func _update_accessibility_tree() -> void:
	# Build/rebuild the native accessibility overlay (see Native UI Bridge section below).
	_build_accessibility_overlay()

func _announce(message: String) -> void:
	if DisplayServer.has_feature(TEXT_TO_SPEECH_FEATURE):
		DisplayServer.tts_speak(message, "", -1, 100, 1.0, 1.0)

func enable_talkback(enabled: bool) -> void:
	_accessibility_enabled = enabled
	if _gesture_handler:
		# Real Android TalkBack intercepts touches before Godot ever sees them and drives
		# the map through the native accessibility overlay below, so the gesture-based
		# simulator must stand down whenever a real screen reader is active, regardless of
		# the caller's request. On platforms/editors with no screen reader (the existing
		# test scenes), this condition is false and behavior is unchanged.
		var native_screen_reader_active := DisplayServer.has_feature(ACCESSIBILITY_SCREEN_READER_FEATURE)
		_gesture_handler.enable_talkback(enabled and not native_screen_reader_active)

func set_zoom(zoom: float) -> void:
	_zoom_level = max(0.5, min(3.0, zoom))
	queue_redraw()
	_sync_accessibility_positions()

func set_pan(offset: Vector2) -> void:
	_pan_offset = offset
	queue_redraw()
	_sync_accessibility_positions()

func get_current_route() -> Array[IMDFParser.IMDFUnit]:
	return _current_route

# ---------------------------------------------------------------------------
# Native UI Bridge
#
# Rendering stays exclusively in _draw(). These invisible Button overlays exist
# only so the Android accessibility tree (exposed by the Phase 1 AccessKit
# engine changes) has a real, focusable Control per room. All interaction is
# delegated back into the existing room-selection/highlighting logic above -
# no application logic is duplicated here.
# ---------------------------------------------------------------------------

func _build_accessibility_overlay() -> void:
	_clear_accessibility_overlay()

	if not _imdf_data:
		return

	var units_by_id: Dictionary = {}  # unit_id -> IMDFParser.IMDFUnit
	for unit in _imdf_data.units:
		units_by_id[unit.id] = unit

	# Android TalkBack's swipe traversal follows the scene-tree order Buttons
	# are added in (verified: Node::_notification forwards get_child(i) order
	# into AccessKit unmodified), NOT focus_neighbor_*. So the creation order
	# below - not just the focus_neighbor_* assignment - is what has to encode
	# logical navigation order.
	var traversal_order: Array = _compute_traversal_order()

	for unit_id in traversal_order:
		var unit: IMDFParser.IMDFUnit = units_by_id[unit_id]

		var node := Button.new()
		node.name = "A11yRoom_%s" % unit.id
		node.focus_mode = Control.FOCUS_ALL
		node.mouse_filter = Control.MOUSE_FILTER_PASS
		node.flat = true
		node.text = ""
		# Button falls back to tooltip_text for its AccessKit-announced name
		# whenever text and accessibility_name are both empty (see button.cpp),
		# so this is what TalkBack actually reads out for the room.
		node.tooltip_text = unit.name
		node.modulate.a = 0.0

		node.focus_entered.connect(_on_accessibility_node_focus_entered.bind(unit.id))
		node.pressed.connect(_on_accessibility_node_pressed.bind(unit.id))

		add_child(node)
		_accessibility_nodes[unit.id] = node

	# Kept for keyboard/gamepad/editor d-pad navigation (ui_left/ui_right/etc.).
	# Verified NOT to affect TalkBack; the creation order above is the real fix.
	_assign_focus_neighbors()
	# Additive semantic hint only (see class-level note in _assign_flow_to_order).
	_assign_flow_to_order(traversal_order)
	_sync_accessibility_positions()

	# setup_from_imdf() sets _focused_unit before this overlay exists, so the
	# initial native accessibility focus needs to be applied retroactively here.
	if _focused_unit != "" and _accessibility_nodes.has(_focused_unit):
		_accessibility_nodes[_focused_unit].grab_focus()

## Produces a deterministic room order for accessibility-node creation, since
## that scene-tree order is what Android TalkBack actually uses for swipe
## traversal (focus_neighbor_* does not reach AccessKit - see comments above).
## Priority: walk the existing _navigation_graph (no re-parsing, no rebuilding)
## with a stable (original IMDF array order) tie-break per step, so the result
## is reproducible across runs. Rooms unreachable via the graph (an
## incomplete/absent graph, or disconnected islands) fall back to geometric
## reading order (top-to-bottom, then left-to-right) using the already-cached
## _room_rects centroids.
func _compute_traversal_order() -> Array:
	var adjacency: Dictionary = {}  # unit_id -> Array[String]
	for path in _navigation_graph:
		if not path.accessible:
			continue
		if not adjacency.has(path.from_unit):
			adjacency[path.from_unit] = []
		if not adjacency.has(path.to_unit):
			adjacency[path.to_unit] = []
		adjacency[path.from_unit].append(path.to_unit)
		adjacency[path.to_unit].append(path.from_unit)

	var unit_index: Dictionary = {}  # unit_id -> original array index, for stable tie-breaks
	for i in range(_imdf_data.units.size()):
		unit_index[_imdf_data.units[i].id] = i

	var order: Array = []
	var visited: Dictionary = {}

	if not adjacency.is_empty():
		# Graph-based traversal: BFS from each not-yet-visited unit (in original
		# array order), expanding neighbors in stable index order at each step.
		for start_unit in _imdf_data.units:
			if visited.has(start_unit.id) or not _room_rects.has(start_unit.id):
				continue

			var queue: Array = [start_unit.id]
			visited[start_unit.id] = true
			while not queue.is_empty():
				var current_id: String = queue.pop_front()
				order.append(current_id)

				var neighbors: Array = adjacency.get(current_id, []).duplicate()
				neighbors.sort_custom(func(a, b): return unit_index.get(a, 0) < unit_index.get(b, 0))
				for neighbor_id in neighbors:
					if not visited.has(neighbor_id) and _room_rects.has(neighbor_id):
						visited[neighbor_id] = true
						queue.append(neighbor_id)

	# Fallback for rooms the graph never reached (graph absent/empty entirely,
	# or a disconnected room with no accessible adjacency at all): geometric
	# reading order by room center, top-to-bottom then left-to-right.
	var remaining: Array = []
	for unit in _imdf_data.units:
		if unit.id in _room_rects and not visited.has(unit.id):
			remaining.append(unit.id)

	remaining.sort_custom(func(a, b):
		var center_a: Vector2 = _room_rects[a].get_center()
		var center_b: Vector2 = _room_rects[b].get_center()
		if abs(center_a.y - center_b.y) > 0.001:
			return center_a.y < center_b.y
		return center_a.x < center_b.x
	)

	order.append_array(remaining)
	return order

## Additive enhancement only: hints AccessKit's flow_to relationship with the
## same order used for scene-tree creation above. Whether the Android AccessKit
## adapter actually translates flow_to into a native traversal hint cannot be
## verified from the available source (the adapter is a precompiled external
## library, not present in this repository), so this must not be relied on as
## the primary mechanism - the creation order in _build_accessibility_overlay()
## is the verified one. The last room in the order is left without a flow_to
## target rather than wrapping back to the first, to avoid an artificial cycle.
##
## Godot 4.7 Stable compatibility: uses Object.set() (a runtime, string-keyed
## property setter) instead of a direct "node.accessibility_flow_to_nodes = ..."
## assignment. Engine builds that don't declare this Control property would
## fail to parse a direct assignment; set() defers the lookup to runtime and
## silently no-ops if the property isn't present, so this stays a harmless,
## purely additive no-op on such builds instead of a compile error.
func _assign_flow_to_order(order: Array) -> void:
	for i in range(order.size() - 1):
		if not _accessibility_nodes.has(order[i]) or not _accessibility_nodes.has(order[i + 1]):
			continue
		var node: Button = _accessibility_nodes[order[i]]
		var next_node: Button = _accessibility_nodes[order[i + 1]]
		node.set("accessibility_flow_to_nodes", [node.get_path_to(next_node)])

func _clear_accessibility_overlay() -> void:
	for unit_id in _accessibility_nodes:
		var node = _accessibility_nodes[unit_id]
		if is_instance_valid(node):
			node.queue_free()
	_accessibility_nodes.clear()

## Reuses the exact same zoom/pan transform as _draw() and _handle_click().
## Kept as its own helper (rather than refactoring _draw()) since _draw() is
## explicitly off-limits for modification in this phase.
func _get_transformed_rect(unit_id: String) -> Rect2:
	var rect: Rect2 = _room_rects.get(unit_id, Rect2())
	return Rect2(
		(rect.position + _pan_offset) * _zoom_level,
		rect.size * _zoom_level
	)

func _sync_accessibility_positions() -> void:
	for unit_id in _accessibility_nodes:
		var node: Button = _accessibility_nodes[unit_id]
		if not is_instance_valid(node):
			continue
		var transformed_rect := _get_transformed_rect(unit_id)
		node.position = transformed_rect.position
		node.size = transformed_rect.size

## Derives left/right/top/bottom focus neighbors from the room adjacency the
## IMDF parser already computed (_navigation_graph) plus room centroid geometry,
## rather than re-implementing graph traversal here. Directions with no adjacent
## room are left unset so Godot's built-in spatial focus search can fill the gap;
## this deterministic approach is a documented simplification versus a full
## shortest-path-aware traversal.
func _assign_focus_neighbors() -> void:
	var adjacency: Dictionary = {}  # unit_id -> Array[String]
	for path in _navigation_graph:
		if not path.accessible:
			continue
		if not adjacency.has(path.from_unit):
			adjacency[path.from_unit] = []
		if not adjacency.has(path.to_unit):
			adjacency[path.to_unit] = []
		adjacency[path.from_unit].append(path.to_unit)
		adjacency[path.to_unit].append(path.from_unit)

	for unit_id in _accessibility_nodes:
		var node: Button = _accessibility_nodes[unit_id]
		var origin_center: Vector2 = _room_rects.get(unit_id, Rect2()).get_center()

		var best_id := {"left": "", "right": "", "top": "", "bottom": ""}
		var best_dist := {"left": INF, "right": INF, "top": INF, "bottom": INF}

		for neighbor_id in adjacency.get(unit_id, []):
			if neighbor_id == unit_id or not _room_rects.has(neighbor_id):
				continue

			var delta: Vector2 = _room_rects[neighbor_id].get_center() - origin_center
			var dist: float = delta.length()
			var direction: String
			if abs(delta.x) >= abs(delta.y):
				direction = "right" if delta.x > 0 else "left"
			else:
				direction = "bottom" if delta.y > 0 else "top"

			if dist < best_dist[direction]:
				best_dist[direction] = dist
				best_id[direction] = neighbor_id

		node.focus_neighbor_left = node.get_path_to(_accessibility_nodes[best_id["left"]]) if best_id["left"] != "" else NodePath()
		node.focus_neighbor_right = node.get_path_to(_accessibility_nodes[best_id["right"]]) if best_id["right"] != "" else NodePath()
		node.focus_neighbor_top = node.get_path_to(_accessibility_nodes[best_id["top"]]) if best_id["top"] != "" else NodePath()
		node.focus_neighbor_bottom = node.get_path_to(_accessibility_nodes[best_id["bottom"]]) if best_id["bottom"] != "" else NodePath()

func _on_accessibility_node_focus_entered(unit_id: String) -> void:
	# Native accessibility focus arriving here means TalkBack (or another screen
	# reader) already announces tooltip_text itself, so skip the redundant TTS call.
	set_focused_room(unit_id, false)

func _on_accessibility_node_pressed(unit_id: String) -> void:
	# Android translates a TalkBack double-tap into a single "pressed" action on
	# the focused node, which is why no double-tap detection happens here.
	set_focused_room(unit_id, false)
	_activate_room(unit_id)
