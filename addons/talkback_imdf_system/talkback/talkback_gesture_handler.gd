# TalkBack Gesture Handler for Godot
# Handles screen reader gestures: single tap, double tap, swipe left/right
# 
# This component integrates with Godot's accessibility server to provide
# TalkBack-compatible gesture input handling.

extends Node

class_name TalkBackGestureHandler

# Godot 4.7 Stable compatibility: DisplayServer.Feature.FEATURE_ACCESSIBILITY_SCREEN_READER's
# raw ordinal value (34), referenced by number instead of by name so this script parses
# correctly on engine builds that may not declare that symbol. has_feature() only needs
# the ordinal, and the check still degrades safely to "false" on builds where the engine
# does not implement this specific feature flag.
const ACCESSIBILITY_SCREEN_READER_FEATURE := 34

# Godot 4.7 Stable compatibility: there is no DisplayServer.tts_is_available() method
# (confirmed absent from doc/classes/DisplayServer.xml). The real, official way to check
# TTS support is DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH), whose
# raw ordinal is 19 (doc/classes/DisplayServer.xml:2740). Referenced by ordinal, same
# reasoning as ACCESSIBILITY_SCREEN_READER_FEATURE above.
const TEXT_TO_SPEECH_FEATURE := 19

## Emitted when a single tap gesture is detected
signal single_tap_detected()

## Emitted when a double tap gesture is detected
signal double_tap_detected()

## Emitted when a swipe left gesture is detected
signal swipe_left_detected()

## Emitted when a swipe right gesture is detected
signal swipe_right_detected()

## Emitted when focus changes
signal focus_changed(control: Control)

# Gesture detection thresholds
var _double_tap_time_threshold: float = 0.3
var _swipe_min_distance: float = 50.0
var _swipe_time_threshold: float = 0.5

# Touch tracking
var _touch_down_position: Vector2 = Vector2.ZERO
var _touch_down_time: float = 0.0
var _last_tap_time: float = 0.0
var _is_double_tap_pending: bool = false
var _double_tap_timer: float = 0.0

# Screen reader state
var _screen_reader_active: bool = false
var _accessibility_enabled: bool = true
var _current_focused_control: Control = null

func _ready() -> void:
	# Check if screen reader is active
	_update_screen_reader_state()
	
	# Request input events
	set_process_input(true)
	set_process(_accessibility_enabled)

func _process(delta: float) -> void:
	if not _accessibility_enabled:
		return
	
	# Update double tap timer
	if _is_double_tap_pending:
		_double_tap_timer += delta
		if _double_tap_timer >= _double_tap_time_threshold:
			_is_double_tap_pending = false
			_double_tap_timer = 0.0

func _input(event: InputEvent) -> void:
	if not _accessibility_enabled or not _screen_reader_active:
		return
	
	# Handle touch events
	if event is InputEventScreenTouch:
		var touch_event = event as InputEventScreenTouch
		_handle_touch_event(touch_event)
		get_tree().root.set_input_as_handled()
	
	elif event is InputEventScreenDrag:
		var drag_event = event as InputEventScreenDrag
		_handle_drag_event(drag_event)
		get_tree().root.set_input_as_handled()

func _handle_touch_event(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# Touch down
		_touch_down_position = event.position
		_touch_down_time = Time.get_ticks_msec() / 1000.0
	else:
		# Touch up
		var touch_duration = Time.get_ticks_msec() / 1000.0 - _touch_down_time
		var touch_distance = _touch_down_position.distance_to(event.position)
		
		# Check if it's a tap (minimal movement)
		if touch_distance < _swipe_min_distance and touch_duration < _swipe_time_threshold:
			_handle_tap(event.position)

func _handle_drag_event(event: InputEventScreenDrag) -> void:
	var drag_distance = event.relative.length()
	
	if drag_distance > _swipe_min_distance:
		# Swipe detected
		if abs(event.relative.x) > abs(event.relative.y):
			# Horizontal swipe
			if event.relative.x > 0:
				_handle_swipe_right()
			else:
				_handle_swipe_left()

func _handle_tap(position: Vector2) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_last_tap = current_time - _last_tap_time
	
	if time_since_last_tap < _double_tap_time_threshold:
		# Double tap detected
		_is_double_tap_pending = false
		_last_tap_time = 0.0
		double_tap_detected.emit()
		_handle_double_tap(position)
	else:
		# Single tap detected (or first tap of double tap)
		_last_tap_time = current_time
		_is_double_tap_pending = true
		_double_tap_timer = 0.0
		single_tap_detected.emit()
		_handle_single_tap(position)

func _handle_single_tap(_position: Vector2) -> void:
	# Move focus to next control in accessibility tree
	if _current_focused_control:
		var next_control = _get_next_focusable_control(_current_focused_control)
		if next_control:
			set_focus(next_control)
			_announce_control(next_control)

func _handle_double_tap(_position: Vector2) -> void:
	# Activate current control
	if _current_focused_control:
		if _current_focused_control is Button:
			_current_focused_control.pressed.emit()
		elif _current_focused_control is CheckBox:
			_current_focused_control.toggled.emit(not _current_focused_control.button_pressed)
		elif _current_focused_control is LineEdit:
			_current_focused_control.grab_focus()
		
		# Announce action
		_announce("Activated control")

func _handle_swipe_left() -> void:
	swipe_left_detected.emit()
	_announce("Swiped left")

func _handle_swipe_right() -> void:
	swipe_right_detected.emit()
	_announce("Swiped right")

func _get_next_focusable_control(current: Control) -> Control:
	var root = get_tree().root
	var all_controls = _get_all_focusable_controls(root)
	
	var current_index = all_controls.find(current)
	if current_index == -1:
		return all_controls[0] if all_controls.size() > 0 else null
	
	var next_index = (current_index + 1) % all_controls.size()
	return all_controls[next_index]

func _get_all_focusable_controls(node: Node) -> Array[Control]:
	var controls: Array[Control] = []
	
	if node is Control and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		if node.focus_mode == Control.FOCUS_ALL or node.focus_mode == Control.FOCUS_CLICK:
			controls.append(node)
	
	for child in node.get_children():
		controls.append_array(_get_all_focusable_controls(child))
	
	return controls

func set_focus(control: Control) -> void:
	_current_focused_control = control
	if control:
		control.grab_focus()
		focus_changed.emit(control)

func _announce_control(control: Control) -> void:
	var text = ""
	
	if control is Button:
		text = "Button: " + control.text
	elif control is CheckBox:
		text = "Checkbox: " + control.text + (", checked" if control.button_pressed else ", unchecked")
	elif control is LineEdit:
		text = "Text field: " + control.placeholder_text
	elif control is Label:
		text = "Label: " + control.text
	elif control.tooltip_text:
		text = control.tooltip_text
	else:
		text = control.name
	
	_announce(text)

func _announce(message: String) -> void:
	if DisplayServer.has_feature(TEXT_TO_SPEECH_FEATURE):
		DisplayServer.tts_speak(message, "", -1, 100, 1.0, 1.0)

func _update_screen_reader_state() -> void:
	# Check if screen reader is active
	if OS.get_name() == "Android":
		_screen_reader_active = _check_android_screen_reader()
	elif OS.get_name() == "Windows":
		_screen_reader_active = _check_windows_screen_reader()
	elif OS.get_name() in ["X11", "Linux"]:
		_screen_reader_active = _check_linux_screen_reader()
	else:
		_screen_reader_active = false

func _check_android_screen_reader() -> bool:
	# This would use JNI to check Java side - for now return true if A11y server is active
	if DisplayServer.has_feature(ACCESSIBILITY_SCREEN_READER_FEATURE):
		return true
	return false

func _check_windows_screen_reader() -> bool:
	if DisplayServer.has_feature(ACCESSIBILITY_SCREEN_READER_FEATURE):
		return true
	return false

func _check_linux_screen_reader() -> bool:
	if DisplayServer.has_feature(ACCESSIBILITY_SCREEN_READER_FEATURE):
		return true
	return false

func is_screen_reader_active() -> bool:
	return _screen_reader_active

func enable_talkback(enabled: bool) -> void:
	_accessibility_enabled = enabled
	set_process(enabled)

func set_gesture_sensitivity(double_tap_time: float, swipe_distance: float, swipe_time: float) -> void:
	_double_tap_time_threshold = double_tap_time
	_swipe_min_distance = swipe_distance
	_swipe_time_threshold = swipe_time
