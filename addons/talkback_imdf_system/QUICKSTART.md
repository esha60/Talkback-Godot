# Quick Start Guide

## Installation

1. Copy the `addons/talkback_imdf_system` folder to your Godot project's `addons/` directory
2. Restart Godot Editor
3. Go to **Project → Project Settings → Plugins**
4. Search for "TalkBack + IMDF System"
5. Click the checkbox to enable the plugin

## Your First MapView

### Step 1: Create a Scene

Create a new 2D scene with a script:

```gdscript
extends Node2D

func _ready():
    # Create mapview
    var mapview = DynamicMapView.new()
    add_child(mapview)
    
    # Load IMDF data
    var imdf = IMDFParser.parse_file("res://data/building.imdf")
    mapview.setup_from_imdf(imdf)
    
    # Enable TalkBack
    mapview.enable_talkback(true)
```

### Step 2: Prepare IMDF Data

Create `res://data/building.imdf`:

```json
{
  "id": "my_building",
  "name": "My Building",
  "units": [
    {
      "id": "room_1",
      "name": "Entrance",
      "unit_type": "room",
      "accessibility": "public",
      "geometry": [
        {"x": 0, "y": 0},
        {"x": 100, "y": 0},
        {"x": 100, "y": 100},
        {"x": 0, "y": 100}
      ],
      "pois": []
    }
  ]
}
```

### Step 3: Test Gestures

On Android with TalkBack enabled:
- Two-finger single tap: Focus next room
- Two-finger double tap: Select room
- Two-finger swipe right: Navigate
- Two-finger swipe left: Go back

## Common Tasks

### Load Multiple Floors

```gdscript
var imdf = IMDFParser.parse_file("res://data/building.imdf")

# Filter units by level
var ground_floor = imdf.units.filter(func(u): return u.level == 0)
var first_floor = imdf.units.filter(func(u): return u.level == 1)
```

### Find Route Between Rooms

```gdscript
var route = IMDFParser.find_accessible_route(
    imdf,
    "entrance",
    "conference_room"
)

if route.size() > 0:
    print("Route found: ", route.map(func(u): return u.name))
else:
    print("No accessible route")
```

### Custom Announcement

```gdscript
DisplayServer.tts_speak(
    "Welcome to the building",  # text
    "",                         # voice (empty = default)
    -1,                        # utterance_id
    100,                       # volume (0-100)
    1.0,                       # pitch (0.5-2.0)
    1.0                        # rate (0.1-10.0)
)
```

### Handle Room Selection

```gdscript
@onready var mapview = $DynamicMapView

func _ready():
    mapview.room_selected.connect(_on_room_selected)

func _on_room_selected(unit_id: String, unit: IMDFParser.IMDFUnit):
    print("User selected: ", unit.name)
```

## Testing Without Device

Use the test scenes to verify functionality:

1. **MapView Test**: Open `test_mapview_scene.gd`
   - Click rooms to test selection
   - Press R to test pathfinding
   - Press Z/X to test zoom

2. **Gesture Test**: Open `test_talkback_scene.gd`
   - Test with mouse clicks (simulates taps)
   - Verify focus transitions work

## Next Steps

- Review [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md) for detailed API
- Check sample IMDF format in `test/test_sample_imdf.json`
- Enable screen reader on your test device
- Integrate with your game UI

## Need Help?

- Check the error console for detailed messages
- Verify IMDF JSON structure with validator
- Test on actual device with screen reader enabled
- Review sample scenes for reference
