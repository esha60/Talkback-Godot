# TalkBack + IMDF Dynamic MapView System for Godot

A comprehensive addon for Godot that implements:
1. **TalkBack Support** - Screen reader accessibility with gesture controls
2. **IMDF Parser** - Indoor Mapping Data Format support
3. **Dynamic MapView** - Interactive accessible room visualization

## Features

### TalkBack Gesture Support (Android)
- **Single Tap**: Focus next control
- **Double Tap**: Activate/execute current control
- **Swipe Left**: Navigate left in room/area
- **Swipe Right**: Navigate right in room/area
- Full integration with Godot's accessibility server

### IMDF Support
- Parse standard IMDF JSON format
- Build navigation graphs
- Support for rooms, corridors, zones, and points of interest
- Accessibility metadata for each area

### Dynamic MapView
- Render rooms/areas with accessible outlines
- Real-time focus indicators for TalkBack
- Touch-enabled navigation
- Responsive to accessibility settings

## Installation

1. Copy this addon to your project's `addons/` folder
2. Enable it in Project → Project Settings → Plugins
3. Use the components in your scenes

## Quick Start

### Basic MapView Usage

```gdscript
extends Node2D

@onready var mapview = $DynamicMapView

func _ready():
	# Load IMDF data
	var imdf_data = IMDFParser.parse_file("res://data/building.imdf")
	
	# Setup map view
	mapview.setup_from_imdf(imdf_data)
	mapview.enable_talkback(true)

func _on_room_selected(room_id: String):
	print("Room selected: ", room_id)
```

## Components

### TalkBack Gesture Handler
- Detects screen reader state
- Captures and interprets gestures
- Manages focus and navigation
- Posts accessibility events

### IMDF Parser
- Validates IMDF structure
- Builds room and path data
- Extracts accessibility information
- Creates navigation graphs

### Dynamic MapView
- Renders IMDF data visually
- Handles touch/mouse input
- Manages focus state
- Updates accessibility tree

## Configuration

See `config.json` for customization options:
- Gesture sensitivity
- Color schemes
- Navigation speed
- Accessibility announcement settings

## Testing

Use the included test scenes:
- `test_talkback_scene.tscn` - TalkBack gesture testing
- `test_mapview_scene.tscn` - MapView rendering and interaction
- `test_sample_imdf.json` - Sample building data

## License

Same as Godot Engine
