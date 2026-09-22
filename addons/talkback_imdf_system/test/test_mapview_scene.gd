# MapView Test Scene Script
# Demonstrates IMDF parsing and DynamicMapView rendering with TalkBack support
#
# Features demonstrated:
# 1. Loading IMDF data from JSON
# 2. Rendering rooms with accessible controls
# 3. TalkBack gesture navigation
# 4. Route finding and announcements

extends Node2D

# Godot 4.7 Stable compatibility: there is no DisplayServer.tts_is_available() method
# (confirmed absent from doc/classes/DisplayServer.xml). The real, official way to check
# TTS support is DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH), whose
# raw ordinal is 19 (doc/classes/DisplayServer.xml:2740), referenced by number here so
# this script parses on engine builds that may not declare the named constant.
const TEXT_TO_SPEECH_FEATURE := 19

@onready var mapview: DynamicMapView = $DynamicMapView
@onready var status_panel = PanelContainer.new()
@onready var status_label = Label.new()
@onready var control_label = Label.new()

var imdf_data: IMDFParser.IMDFData = null
var current_route: Array[IMDFParser.IMDFUnit] = []

func _ready() -> void:
	# Create UI
	_setup_ui()
	
	# Load IMDF data
	var imdf_file = "res://addons/talkback_imdf_system/test/test_sample_imdf.json"
	print("Loading IMDF from: ", imdf_file)
	
	imdf_data = IMDFParser.parse_file(imdf_file)
	
	if imdf_data == null:
		status_label.text = "ERROR: Failed to load IMDF data"
		return
	
	print("IMDF loaded: ", imdf_data.name)
	print("Units: ", imdf_data.units.size())
	
	# Setup mapview
	if mapview:
		mapview.setup_from_imdf(imdf_data)
		mapview.room_selected.connect(_on_room_selected)
		mapview.navigation_started.connect(_on_navigation_started)
		mapview.navigation_completed.connect(_on_navigation_completed)
		mapview.enable_talkback(true)
	
	# Update status
	_update_status()
	
	# Print building info
	_print_building_info()

func _setup_ui() -> void:
	# Create panel
	status_panel.custom_minimum_size = Vector2(400, 150)
	status_panel.anchor_left = 1.0
	status_panel.anchor_top = 0.0
	status_panel.offset_left = -420
	status_panel.offset_top = 20
	add_child(status_panel)
	
	# Create labels
	var vbox = VBoxContainer.new()
	status_panel.add_child(vbox)
	
	status_label.text = "Status: Initializing..."
	status_label.custom_minimum_size = Vector2(380, 40)
	vbox.add_child(status_label)
	
	control_label.text = "Controls:\nClick rooms to navigate\nTalkBack gestures supported"
	control_label.custom_minimum_size = Vector2(380, 100)
	vbox.add_child(control_label)

func _on_room_selected(unit_id: String, unit: IMDFParser.IMDFUnit) -> void:
	print("Room selected: ", unit.name, " (", unit_id, ")")
	status_label.text = "Selected: " + unit.name
	
	# Announce room details
	var details = "Room type: " + unit.unit_type
	if unit.pois.size() > 0:
		details += ". Contains: "
		var poi_names = []
		for poi in unit.pois:
			poi_names.append(poi.name)
		details += ", ".join(poi_names)
	
	print(details)

func _on_navigation_started(from_unit: String, to_unit: String) -> void:
	print("Navigation started from ", from_unit, " to ", to_unit)
	status_label.text = "Navigating..."
	current_route = mapview.get_current_route()

func _on_navigation_completed(route: Array) -> void:
	print("Navigation completed with ", route.size(), " waypoints")
	status_label.text = "Navigation complete"

func _update_status() -> void:
	var info = "Building: " + imdf_data.name + "\n"
	info += "Units: " + str(imdf_data.units.size()) + "\n"
	
	# Count by type
	var room_count = 0
	var corridor_count = 0
	for unit in imdf_data.units:
		if unit.unit_type == "room":
			room_count += 1
		elif unit.unit_type == "corridor":
			corridor_count += 1
	
	info += "Rooms: " + str(room_count) + ", Corridors: " + str(corridor_count)
	status_label.text = info

func _print_building_info() -> void:
	print("\n=== Building Information ===")
	print("Name: ", imdf_data.name)
	print("Address: ", imdf_data.address)
	print("Version: ", imdf_data.version)
	print("\n=== Units ===")
	
	for unit in imdf_data.units:
		print("\nUnit: ", unit.name, " (", unit.unit_type, ")")
		print("  ID: ", unit.id)
		print("  Accessibility: ", unit.accessibility)
		print("  Level: ", unit.level)
		print("  Geometry points: ", unit.geometry.size())
		
		if unit.pois.size() > 0:
			print("  POIs:")
			for poi in unit.pois:
				print("    - ", poi.name, " (", poi.poi_type, ")")

func _input(event: InputEvent) -> void:
	# Keyboard shortcuts for testing
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			# Test screen reader announcement
			if DisplayServer.has_feature(TEXT_TO_SPEECH_FEATURE):
				DisplayServer.tts_speak("Test announcement", "", -1, 100, 1.0, 1.0)
		
		elif event.keycode == KEY_R:
			# Test route finding
			if imdf_data.units.size() >= 2:
				var route = IMDFParser.find_accessible_route(
					imdf_data,
					imdf_data.units[0].id,
					imdf_data.units[-1].id
				)
				if route.size() > 0:
					print("Route found with ", route.size(), " waypoints")
				else:
					print("No route found")
		
		elif event.keycode == KEY_Z:
			# Zoom in
			mapview.set_zoom(mapview._zoom_level * 1.2)
		
		elif event.keycode == KEY_X:
			# Zoom out
			mapview.set_zoom(mapview._zoom_level / 1.2)
