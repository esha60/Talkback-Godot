# Complete Implementation Guide: TalkBack + IMDF MapView System

## Overview

This guide covers the complete implementation of TalkBack gesture support with IMDF-based dynamic room building for Godot. The system provides:

1. **TalkBack Gesture Handler** - Screen reader gesture recognition
2. **IMDF Parser** - Indoor mapping data format support  
3. **Dynamic MapView** - Accessible visual room rendering

---

## Architecture

### Component Hierarchy

```
TalkBack + IMDF System
├── TalkBackGestureHandler (Gesture input processing)
│   ├── Screen reader detection
│   ├── Tap/swipe recognition
│   ├── Focus management
│   └── Accessibility announcements
├── IMDFParser (Data processing)
│   ├── JSON parsing
│   ├── Unit/POI extraction
│   ├── Navigation graph building
│   └── Route finding
└── DynamicMapView (Visual rendering)
	├── Room rendering
	├── Focus indicators
	├── POI display
	└── Gesture integration
```

---

## Gesture Control System

### Supported Gestures (TalkBack)

#### 1. Single Tap
- **Trigger**: Two-finger single tap or equivalent
- **Action**: Move focus to next control
- **Repeat**: Cycles through all controls
- **Announcement**: Automatically announces focused control name and type

#### 2. Double Tap
- **Trigger**: Two consecutive single taps within 0.3 seconds
- **Action**: Activate/execute current control
- **Effect**: 
  - Buttons: Emit pressed signal
  - Checkboxes: Toggle state
  - Text fields: Grab focus for input
- **Announcement**: Confirms action execution

#### 3. Swipe Left
- **Trigger**: Two-finger swipe from right to left
- **Action**: Navigate left in current room/area
- **Effect**: Moves focus to previous or left-adjacent control
- **Use case**: Room navigation, menu traversal

#### 4. Swipe Right
- **Trigger**: Two-finger swipe from left to right
- **Action**: Navigate right in current room/area
- **Effect**: Moves focus to next or right-adjacent control
- **Use case**: Room navigation, menu progression

### Gesture Detection Algorithm

```gdscript
# Detection flow in TalkBackGestureHandler

_input(event)
  │
  ├─ if InputEventScreenTouch
  │   └─ Track touch_down_position and touch_down_time
  │
  ├─ if InputEventScreenDrag
  │   ├─ Calculate relative motion
  │   └─ if distance > SWIPE_MIN_DISTANCE (50px)
  │       └─ Emit swipe_left or swipe_right
  │
  └─ if Touch Released
	  ├─ Calculate touch_duration
	  ├─ if duration < TAP_THRESHOLD (0.5s) AND distance < SWIPE_MIN_DISTANCE
	  │   └─ Handle tap
	  │       ├─ if time since last_tap < DOUBLE_TAP_THRESHOLD (0.3s)
	  │       │   └─ Emit double_tap_detected
	  │       └─ else
	  │           └─ Emit single_tap_detected
```

### Configuration

Adjust gesture sensitivity in TalkBackGestureHandler:

```gdscript
gesture_handler.set_gesture_sensitivity(
	double_tap_time = 0.3,      # seconds
	swipe_distance = 50.0,      # pixels
	swipe_time = 0.5            # seconds
)
```

---

## IMDF Data Format

### Structure Overview

IMDF (Indoor Mapping Data Format) is a JSON-based format for describing indoor spaces.

### Complete IMDF Schema

```json
{
  "id": "building_identifier",
  "name": "Building Name",
  "address": "Street Address",
  "version": "1.0",
  "coordinate_system": "mercator_wgs84",
  "anchor": {
	"latitude": 40.7128,
	"longitude": -74.0060
  },
  "units": [
	{
	  "id": "unit_001",
	  "name": "Room Name",
	  "unit_type": "room|corridor|area|zone",
	  "accessibility": "public|private|restricted",
	  "level": 0,
	  "address": "Room Address",
	  "geometry": [
		{"x": 0, "y": 0},
		{"x": 100, "y": 0},
		{"x": 100, "y": 100},
		{"x": 0, "y": 100}
	  ],
	  "pois": [
		{
		  "id": "poi_001",
		  "name": "POI Name",
		  "poi_type": "information|elevator|entrance|checkout|restroom|dining",
		  "position": {"x": 50, "y": 50},
		  "accessibility": "public|private|restricted"
		}
	  ]
	}
  ]
}
```

### Key Fields Explained

| Field | Type | Description |
|-------|------|-------------|
| `id` | String | Unique building identifier |
| `name` | String | Display name for screen readers |
| `unit_type` | String | Category: room, corridor, area, zone |
| `accessibility` | String | Access level: public (accessible), private, restricted |
| `geometry` | Array | Polygon vertices as {x, y} coordinates |
| `pois` | Array | Points of Interest within unit |
| `poi_type` | String | Category of POI for navigation |

---

## DynamicMapView Component

### Usage Example

```gdscript
extends Node2D

@onready var mapview = $DynamicMapView

func _ready():
	# Load IMDF data
	var imdf_data = IMDFParser.parse_file("res://data/building.imdf")
	
	# Setup map with TalkBack support
	mapview.setup_from_imdf(imdf_data)
	mapview.enable_talkback(true)
	
	# Connect signals
	mapview.room_selected.connect(_on_room_selected)
	mapview.navigation_started.connect(_on_navigation_started)

func _on_room_selected(unit_id: String, unit: IMDFParser.IMDFUnit):
	print("Selected: ", unit.name)
```

### API Reference

#### DynamicMapView Methods

```gdscript
# Setup and configuration
setup_from_imdf(imdf_data: IMDFParser.IMDFData) -> void
enable_talkback(enabled: bool) -> void

# Navigation
navigate_to_room(from_unit_id: String, to_unit_id: String) -> bool
set_focused_room(unit_id: String) -> void
get_current_route() -> Array[IMDFParser.IMDFUnit]

# View control
set_zoom(zoom: float) -> void
set_pan(offset: Vector2) -> void

# State queries
get_focused_unit() -> String
```

#### DynamicMapView Signals

```gdscript
signal room_selected(unit_id: String, unit: IMDFParser.IMDFUnit)
signal navigation_started(from_unit: String, to_unit: String)
signal navigation_completed(route: Array)
```

### Visual Customization

```gdscript
# Access private members for customization
mapview._room_color = Color(0.2, 0.6, 1.0, 0.7)
mapview._room_border_color = Color(0.1, 0.3, 0.8, 1.0)
mapview._room_border_width = 2.0
mapview._focused_color = Color(1.0, 1.0, 0.0, 0.9)
mapview._focused_border_width = 4.0
mapview._poi_radius = 10.0
```

---

## IMDFParser Reference

### Static Methods

```gdscript
# File parsing
static parse_file(file_path: String) -> IMDFData
static parse_data(data: Dictionary) -> IMDFData

# Navigation
static build_navigation_graph(imdf: IMDFData) -> Array[NavigationPath]
static find_accessible_route(
	imdf: IMDFData, 
	from_unit_id: String, 
	to_unit_id: String
) -> Array[IMDFUnit]
```

### Data Classes

```gdscript
class IMDFData:
	var id: String
	var name: String
	var address: String
	var version: String
	var units: Array[IMDFUnit]
	var anchor: Vector2
	var coordinate_system: String

class IMDFUnit:
	var id: String
	var name: String
	var unit_type: String
	var accessibility: String
	var geometry: PackedVector2Array
	var level: int
	var pois: Array[IMDFDOI]
	var address: String

class IMDFDOI:
	var id: String
	var name: String
	var poi_type: String
	var position: Vector2
	var accessibility: String

class NavigationPath:
	var from_unit: String
	var to_unit: String
	var waypoints: PackedVector2Array
	var accessible: bool
```

---

## Accessibility Integration

### Screen Reader Support

The system automatically detects screen reader status:

```gdscript
# Check screen reader state
if gesture_handler.is_screen_reader_active():
	gesture_handler.enable_talkback(true)
```

### Platform Detection

```gdscript
# Automatic platform detection
if OS.get_name() == "Android":
	# Use Android A11y framework
elif OS.get_name() == "Windows":
	# Use Windows accessibility
elif OS.get_name() in ["X11", "Linux"]:
	# Use DBus accessibility
```

### Text-to-Speech Announcements

```gdscript
# Automatic announcements for:
# - Control focus changes
# - Gesture actions (single tap, double tap, swipes)
# - Room selection and navigation
# - POI descriptions

# Manual announcement
DisplayServer.tts_speak("Custom announcement", "", -1, 100, 1.0, 1.0)
```

---

## Testing

### Test Scene: TalkBack Gestures

**File**: `test_talkback_scene.gd`

Controls:
- Single tap (2 fingers): Focus next button
- Double tap (2 fingers): Activate button
- Swipe left/right: Navigate buttons

Run on device with screen reader enabled for full testing.

### Test Scene: MapView

**File**: `test_mapview_scene.gd`

Features:
- Loads sample IMDF data
- Renders building layout
- Interactive room selection
- Route finding
- Keyboard shortcuts:
  - `SPACE`: Test TTS announcement
  - `R`: Test route finding
  - `Z`: Zoom in
  - `X`: Zoom out

---

## Implementation Examples

### Example 1: Basic MapView

```gdscript
extends Node2D

func _ready():
	var mapview = DynamicMapView.new()
	add_child(mapview)
	
	var imdf = IMDFParser.parse_file("res://data/mall.imdf")
	mapview.setup_from_imdf(imdf)
```

### Example 2: Custom Route Navigation

```gdscript
func navigate_between_rooms():
	var route = IMDFParser.find_accessible_route(
		imdf_data,
		"entrance_room",
        "target_room"
	)
	
	if route.size() > 0:
		mapview.navigate_to_room("entrance_room", "target_room")
		announce_route(route)

func announce_route(route: Array):
	var names = []
	for unit in route:
		names.append(unit.name)
	var message = "Route: " + ", ".join(names)
	DisplayServer.tts_speak(message)
```

### Example 3: Custom Gesture Handling

```gdscript
extends Node2D

@onready var handler = TalkBackGestureHandler.new()

func _ready():
	add_child(handler)
	handler.single_tap_detected.connect(_on_tap)
	handler.swipe_right_detected.connect(_on_swipe_right)

func _on_tap():
	print("User tapped - focus changed")

func _on_swipe_right():
	print("User swiped right - navigate right")
```

---

## Troubleshooting

### Screen Reader Not Detected

- Ensure screen reader app is active on device
- Check `DisplayServer.FEATURE_ACCESSIBILITY_SCREEN_READER` support
- Verify platform-specific accessibility permissions

### Gestures Not Working

- Verify two-finger input is being sent
- Check gesture thresholds:
  - Double tap: < 0.3 seconds between taps
  - Swipe: > 50 pixels movement within 0.5 seconds
- Adjust sensitivity with `set_gesture_sensitivity()`

### IMDF Not Loading

- Validate JSON format with online JSON validator
- Check file path is accessible (use `res://` prefix)
- Ensure geometry has at least 3 points (valid polygon)
- Verify unit accessibility field is valid

### Announcements Not Playing

- Check `DisplayServer.tts_is_available()` returns true
- Verify device volume is not muted
- Ensure text-to-speech engine is installed on device
- Check TTS permissions in Android manifest

---

## Performance Considerations

- **Units**: Optimize for < 500 units per building
- **Geometry**: Keep polygons simple (< 20 vertices each)
- **Rendering**: Use custom draw optimization for large maps
- **Pathfinding**: Cache navigation graphs for repeated queries
- **Memory**: Pre-load only needed levels in multi-level buildings

---

## Security Notes

- IMDF files may contain sensitive building information
- Consider encrypting IMDF data in production
- Validate all coordinate data before rendering
- Sanitize POI names for text-to-speech

---

## Credits & References

- IMDF Specification: https://register.apple.com/resources/imdf/
- Godot Accessibility: https://docs.godotengine.org/
- TalkBack Guide: https://support.google.com/accessibility
- AccessKit: https://accesskit.dev/
