# Test 3D Accessibility Scene
# Programmatically sets up a 3D scene with multiple rooms and verifies the 3D Accessibility Bridge.

extends Node3D

var bridge: Dynamic3DAccessibilityBridge
var camera: Camera3D
var label: Label
var log_label: Label
var orbit_angle: float = 0.0

func _ready() -> void:
	# 1. Setup 3D Environment
	var light := DirectionalLight3D.new()
	light.position = Vector3(5, 10, 5)
	light.look_at(Vector3.ZERO)
	add_child(light)
	
	camera = Camera3D.new()
	camera.position = Vector3(0, 5, 8)
	camera.look_at(Vector3.ZERO)
	add_child(camera)
	
	# 2. Setup 3D Rooms (Boxes)
	var room_materials = {
		"living_room": _create_material(Color(0.2, 0.6, 1.0)),
		"kitchen": _create_material(Color(1.0, 0.4, 0.4)),
		"bedroom": _create_material(Color(0.4, 0.8, 0.4))
	}
	
	var living_room := _create_box("Living Room", Vector3(-2.5, 0, -1), room_materials["living_room"])
	var kitchen := _create_box("Kitchen", Vector3(0, 0.5, -3), room_materials["kitchen"])
	var bedroom := _create_box("Bedroom", Vector3(2.5, -0.5, 1), room_materials["bedroom"])
	
	# 3. Setup UI info panel
	var ui_canvas := CanvasLayer.new()
	ui_canvas.layer = 10
	add_child(ui_canvas)
	
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	ui_canvas.add_child(panel)
	
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	
	label = Label.new()
	label.text = "3D TalkBack Accessibility test\nSwipe or use keyboard focus to navigate rooms."
	vbox.add_child(label)
	
	log_label = Label.new()
	log_label.text = "Events: None"
	log_label.modulate = Color(1.0, 1.0, 0.0)
	vbox.add_child(log_label)
	
	# 4. Initialize and configure the 3D Accessibility Bridge
	bridge = Dynamic3DAccessibilityBridge.new()
	bridge.camera = camera
	add_child(bridge)
	
	# Register 3D objects as targets
	bridge.register_target("living_room", living_room, "Living Room (3D Model)")
	bridge.register_target("kitchen", kitchen, "Kitchen (3D Model)")
	bridge.register_target("bedroom", bedroom, "Bedroom (3D Model)")
	
	# Connect events
	bridge.target_focused.connect(_on_target_focused)
	bridge.target_pressed.connect(_on_target_pressed)
	
func _create_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.5
	return mat

func _create_box(box_name: String, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = box_name
	
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.5, 1.0, 1.5)
	mesh_inst.mesh = box_mesh
	mesh_inst.material_override = mat
	mesh_inst.position = pos
	add_child(mesh_inst)
	
	# Add a simple text label floating above the 3D box
	var label3d := Label3D.new()
	label3d.text = box_name
	label3d.position = Vector3(0, 0.8, 0)
	label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mesh_inst.add_child(label3d)
	
	return mesh_inst

func _process(delta: float) -> void:
	# Slowly orbit camera to show continuous screen space projection tracking
	orbit_angle += delta * 0.2
	var radius := 9.0
	camera.position = Vector3(sin(orbit_angle) * radius, 4.0, cos(orbit_angle) * radius)
	camera.look_at(Vector3.ZERO)

func _on_target_focused(unit_id: String) -> void:
	log_label.text = "Events: Focused on " + unit_id
	print("TalkBack Focus entered: " + unit_id)

func _on_target_pressed(unit_id: String) -> void:
	log_label.text = "Events: Activated/Clicked " + unit_id
	print("TalkBack Action clicked: " + unit_id)
