# TalkBack Test Scene Setup Script
# Demonstrates TalkBack gesture handling and accessibility features
#
# Instructions for testing:
# 1. Run this scene on an Android device with TalkBack enabled
# 2. Single tap with 2 fingers: focus next button
# 3. Double tap with 2 fingers: activate button
# 4. Swipe right with 2 fingers: move right
# 5. Swipe left with 2 fingers: move left

extends Node2D

# Godot 4.7 Stable compatibility: there is no DisplayServer.tts_is_available() method
# (confirmed absent from doc/classes/DisplayServer.xml). The real, official way to check
# TTS support is DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH), whose
# raw ordinal is 19 (doc/classes/DisplayServer.xml:2740), referenced by number here so
# this script parses on engine builds that may not declare the named constant.
const TEXT_TO_SPEECH_FEATURE := 19

@onready var gesture_handler = TalkBackGestureHandler.new()
@onready var info_label = Label.new()
@onready var status_label = Label.new()
@onready var button_container = VBoxContainer.new()

var test_buttons: Array[Button] = []
var current_button_index: int = 0

func _ready() -> void:
	# Setup scene structure
	var control_node = Control.new()
	control_node.anchor_right = 1.0
	control_node.anchor_bottom = 1.0
	add_child(control_node)
	
	# Add gesture handler
	add_child(gesture_handler)
	
	# Setup info label
	info_label.text = "TalkBack Gesture Handler Test"
	info_label.custom_minimum_size = Vector2(400, 60)
	control_node.add_child(info_label)
	
	# Setup status label
	status_label.text = "Status: Initializing..."
	status_label.custom_minimum_size = Vector2(400, 40)
	control_node.add_child(status_label)
	
	# Setup button container
	button_container.custom_minimum_size = Vector2(400, 300)
	control_node.add_child(button_container)
	
	# Create test buttons
	_create_test_buttons()
	
	# Connect gesture signals
	gesture_handler.single_tap_detected.connect(_on_single_tap)
	gesture_handler.double_tap_detected.connect(_on_double_tap)
	gesture_handler.swipe_left_detected.connect(_on_swipe_left)
	gesture_handler.swipe_right_detected.connect(_on_swipe_right)
	gesture_handler.focus_changed.connect(_on_focus_changed)
	
	# Check screen reader state
	_update_status()
	
	# Enable TalkBack
	gesture_handler.enable_talkback(true)

func _create_test_buttons() -> void:
	var button_names = ["Play", "Settings", "About", "Exit"]
	
	for i in range(button_names.size()):
		var button = Button.new()
		button.text = button_names[i]
		button.custom_minimum_size = Vector2(300, 50)
		button.pressed.connect(_on_button_pressed.bindv([button.text]))
		button_container.add_child(button)
		test_buttons.append(button)
	
	# Focus first button
	if test_buttons.size() > 0:
		gesture_handler.set_focus(test_buttons[0])
		current_button_index = 0

func _on_single_tap() -> void:
	status_label.text = "Status: Single tap detected"
	_focus_next_button()

func _on_double_tap() -> void:
	status_label.text = "Status: Double tap detected - Button activated"
	if current_button_index < test_buttons.size():
		test_buttons[current_button_index].pressed.emit()

func _on_swipe_left() -> void:
	status_label.text = "Status: Swiped left"
	_focus_previous_button()

func _on_swipe_right() -> void:
	status_label.text = "Status: Swiped right"
	_focus_next_button()

func _on_focus_changed(control: Control) -> void:
	if control in test_buttons:
		current_button_index = test_buttons.find(control)

func _on_button_pressed(button_name: String) -> void:
	print("Button pressed: " + button_name)
	info_label.text = "Last Action: " + button_name + " pressed"

func _focus_next_button() -> void:
	if test_buttons.size() == 0:
		return
	
	current_button_index = (current_button_index + 1) % test_buttons.size()
	gesture_handler.set_focus(test_buttons[current_button_index])

func _focus_previous_button() -> void:
	if test_buttons.size() == 0:
		return
	
	current_button_index = (current_button_index - 1 + test_buttons.size()) % test_buttons.size()
	gesture_handler.set_focus(test_buttons[current_button_index])

func _update_status() -> void:
	if gesture_handler.is_screen_reader_active():
		status_label.text += " | Screen reader: ACTIVE"
	else:
		status_label.text += " | Screen reader: INACTIVE"
	
	if DisplayServer.has_feature(TEXT_TO_SPEECH_FEATURE):
		status_label.text += " | TTS: AVAILABLE"
	else:
		status_label.text += " | TTS: NOT AVAILABLE"
