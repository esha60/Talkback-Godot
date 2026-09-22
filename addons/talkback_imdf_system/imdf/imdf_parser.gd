# IMDF (Indoor Mapping Data Format) Parser
# Parses IMDF JSON files and builds room/navigation data structures
#
# IMDF is a standard format for indoor mapping data published by Apple
# Reference: https://register.apple.com/resources/imdf/

extends Object

class_name IMDFParser

## IMDF Data Structure
class IMDFData:
	var id: String
	var name: String
	var address: String
	var version: String
	var units: Array[IMDFUnit] = []
	var anchor: Vector2
	var coordinate_system: String

## Unit represents a logical area (room, corridor, etc.)
class IMDFUnit:
	var id: String
	var name: String
	var unit_type: String  # "room", "corridor", "area", "zone"
	var accessibility: String
	var geometry: PackedVector2Array = []
	var level: int
	var pois: Array[IMDFDOI] = []
	var address: String

## Point of Interest
class IMDFDOI:
	var id: String
	var name: String
	var poi_type: String
	var position: Vector2
	var accessibility: String

## Navigation path between units
class NavigationPath:
	var from_unit: String
	var to_unit: String
	var waypoints: PackedVector2Array = []
	var accessible: bool

## Parse IMDF from file
static func parse_file(file_path: String) -> IMDFData:
	if not ResourceLoader.exists(file_path):
		push_error("IMDF file not found: " + file_path)
		return null
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open IMDF file: " + file_path)
		return null
	
	var json_string = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(json_string)
	
	if error != OK:
		push_error("Failed to parse IMDF JSON: " + json.get_error_message())
		return null
	
	return parse_data(json.data)

## Parse IMDF from Dictionary
static func parse_data(data: Dictionary) -> IMDFData:
	if not _validate_imdf_structure(data):
		push_warning("IMDF structure validation failed, attempting to parse anyway")
	
	var imdf = IMDFData.new()
	imdf.id = data.get("id", "unknown")
	imdf.name = data.get("name", "Building")
	imdf.address = data.get("address", "")
	imdf.version = data.get("version", "1.0")
	imdf.coordinate_system = data.get("coordinate_system", "mercator_wgs84")
	
	# Parse anchor point
	if data.has("anchor"):
		var anchor_data = data["anchor"]
		imdf.anchor = Vector2(anchor_data.get("latitude", 0.0), anchor_data.get("longitude", 0.0))
	
	# Parse units
	if data.has("units"):
		for unit_data in data["units"]:
			var unit = _parse_unit(unit_data)
			if unit:
				imdf.units.append(unit)
	
	return imdf

## Parse a single unit
static func _parse_unit(data: Dictionary) -> IMDFUnit:
	var unit = IMDFUnit.new()
	unit.id = data.get("id", "")
	unit.name = data.get("name", "Unnamed")
	unit.unit_type = data.get("unit_type", "room")
	unit.accessibility = data.get("accessibility", "public")
	unit.level = data.get("level", 0)
	unit.address = data.get("address", "")
	
	# Parse geometry (polygon)
	if data.has("geometry") and data["geometry"] is Array:
		var geometry_array = data["geometry"]
		for point_data in geometry_array:
			if point_data is Dictionary:
				var x = float(point_data.get("x", 0))
				var y = float(point_data.get("y", 0))
				unit.geometry.append(Vector2(x, y))
	
	# Parse POIs (Points of Interest)
	if data.has("pois"):
		for poi_data in data["pois"]:
			var poi = _parse_poi(poi_data)
			if poi:
				unit.pois.append(poi)
	
	return unit

## Parse a Point of Interest
static func _parse_poi(data: Dictionary) -> IMDFDOI:
	var poi = IMDFDOI.new()
	poi.id = data.get("id", "")
	poi.name = data.get("name", "POI")
	poi.poi_type = data.get("poi_type", "generic")
	poi.accessibility = data.get("accessibility", "public")
	
	if data.has("position"):
		var pos = data["position"]
		poi.position = Vector2(pos.get("x", 0), pos.get("y", 0))
	
	return poi

## Build navigation graph from units
static func build_navigation_graph(imdf: IMDFData) -> Array[NavigationPath]:
	var paths: Array[NavigationPath] = []
	
	# For each pair of units on the same level, create potential paths
	for i in range(imdf.units.size()):
		for j in range(i + 1, imdf.units.size()):
			var unit_a = imdf.units[i]
			var unit_b = imdf.units[j]
			
			if unit_a.level != unit_b.level:
				continue
			
			# Check if units are adjacent (share geometry boundaries or close proximity)
			if _units_are_adjacent(unit_a, unit_b):
				var path = NavigationPath.new()
				path.from_unit = unit_a.id
				path.to_unit = unit_b.id
				path.accessible = (unit_a.accessibility == "public" and unit_b.accessibility == "public")
				path.waypoints = _calculate_path_waypoints(unit_a, unit_b)
				paths.append(path)
	
	return paths

## Check if two units are adjacent
static func _units_are_adjacent(unit_a: IMDFUnit, unit_b: IMDFUnit) -> bool:
	if unit_a.geometry.size() == 0 or unit_b.geometry.size() == 0:
		return false
	
	# Simple proximity check - if any point from unit_a is close to unit_b geometry
	var max_distance = 100.0  # meters
	
	for point_a in unit_a.geometry:
		var min_dist = _point_to_polygon_distance(point_a, unit_b.geometry)
		if min_dist < max_distance:
			return true
	
	return false

## Calculate distance from point to polygon
static func _point_to_polygon_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	if polygon.size() == 0:
		return INF
	
	var min_distance = INF
	
	# Distance to vertices
	for vertex in polygon:
		var dist = point.distance_to(vertex)
		min_distance = min(min_distance, dist)
	
	# Distance to edges
	for i in range(polygon.size()):
		var p1 = polygon[i]
		var p2 = polygon[(i + 1) % polygon.size()]
		var edge_dist = _point_to_segment_distance(point, p1, p2)
		min_distance = min(min_distance, edge_dist)
	
	return min_distance

## Calculate distance from point to line segment
static func _point_to_segment_distance(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float:
	var t = max(0.0, min(1.0, (point - seg_start).dot(seg_end - seg_start) / (seg_end - seg_start).length_squared()))
	var closest_point = seg_start + (seg_end - seg_start) * t
	return point.distance_to(closest_point)

## Calculate waypoints between two units
static func _calculate_path_waypoints(unit_a: IMDFUnit, unit_b: IMDFUnit) -> PackedVector2Array:
	var waypoints = PackedVector2Array()
	
	# Use centroid of each unit as waypoints
	var centroid_a = _calculate_centroid(unit_a.geometry)
	var centroid_b = _calculate_centroid(unit_b.geometry)
	
	waypoints.append(centroid_a)
	waypoints.append(centroid_b)
	
	return waypoints

## Calculate centroid of polygon
static func _calculate_centroid(polygon: PackedVector2Array) -> Vector2:
	if polygon.size() == 0:
		return Vector2.ZERO
	
	var sum = Vector2.ZERO
	for point in polygon:
		sum += point
	
	return sum / polygon.size()

## Validate IMDF structure
static func _validate_imdf_structure(data: Dictionary) -> bool:
	if not data.has("id"):
		push_warning("IMDF missing 'id' field")
		return false
	
	if not data.has("units"):
		push_warning("IMDF missing 'units' array")
		return false
	
	return true

## Create accessible route between two units
static func find_accessible_route(imdf: IMDFData, from_unit_id: String, to_unit_id: String) -> Array[IMDFUnit]:
	var routes: Array[IMDFUnit] = []
	
	# Simple BFS pathfinding for accessible units
	var queue = [from_unit_id]
	var visited = {}
	var parent_map = {}
	
	while queue.size() > 0:
		var current_id = queue.pop_front()
		
		if current_id in visited:
			continue
		
		visited[current_id] = true
		
		if current_id == to_unit_id:
			# Reconstruct path
			var path_id = to_unit_id
			while path_id != null:
				for unit in imdf.units:
					if unit.id == path_id:
						routes.insert(0, unit)
						break
				path_id = parent_map.get(path_id)
			return routes
		
		# Find adjacent accessible units
		for unit in imdf.units:
			if unit.accessibility != "public":
				continue
			
			if unit.id in visited:
				continue
			
			# Check if connected to current unit
			var connected = false
			for potential_unit in imdf.units:
				if potential_unit.id == current_id and _units_are_adjacent(potential_unit, unit):
					connected = true
					break
			
			if connected and unit.id not in visited:
				queue.append(unit.id)
				parent_map[unit.id] = current_id
	
	return routes  # Empty if no path found
