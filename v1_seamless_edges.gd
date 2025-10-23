@tool
extends Node3D

var terrain_size = 100000
var terrain_altitude = 8000
var terrain_noise = FastNoiseLite.new()
var terrain_shader = preload("res://shaders/terrain_auto.gdshader")
var terrain_resolution = 4

var next_quadtree = {}
var quadtree_pool = {}
var quadtree_depth = 4
var root_aabb = AABB(Vector3.ZERO, Vector3.ONE * terrain_size)#
var aabb_parent = {}

var camera : Camera3D
var camera_last_position : Vector3

class QuadtreeData:
	var aabb : AABB
	var depth : int
	var parent_data : QuadtreeData
	var local_position : Array
	var original_heightmap : Array
	var modified_heightmap : Array
	var steps : float
	var neighbors : Dictionary
	var meshinstance : MeshInstance3D
	
	func _init(_aabb : AABB, _depth : int, _parent_data : QuadtreeData, _local_position : Array) -> void:
		aabb = _aabb
		depth = _depth
		parent_data = _parent_data
		local_position = _local_position

func _ready() -> void:
	#for child in get_children():
	#	child.free()
	quadtree_pool.clear()
		
	camera = EditorInterface.get_editor_viewport_3d().get_camera_3d()
	camera_last_position = camera.position
	
	terrain_noise.frequency = 0.00001
	terrain_noise.fractal_octaves = 10
	
	update_quadtree()
	
func _process(_delta: float) -> void:
	if camera == null:
		return
	if camera_last_position.distance_to(camera.position) > 100:
		camera_last_position = camera.position
		update_quadtree()
	
func update_quadtree():
	for child in get_children():
		child.free()
		
	next_quadtree.clear()
	aabb_parent.clear()
	# quadtree_pool.clear()
	
	# Create quadtree an place all futur chunks in next_quadtree
	var root_data = QuadtreeData.new(root_aabb, 0, null, [])
	subdivide_quadtree(root_data)
	
	for aabb in next_quadtree:
		var data = next_quadtree[aabb]
		data.original_heightmap = generate_heightmap(data)
	
	var sorted_aabbs =[] # Sort by depth
	for aabb in next_quadtree:
		sorted_aabbs.append([aabb, next_quadtree[aabb].depth])
	sorted_aabbs.sort_custom(func(a, b): return a[1] < b[1])
	
	for aabb_depth in sorted_aabbs: # Process lowest depth first
		var aabb = aabb_depth[0]
		var data = next_quadtree[aabb]
		print("depth ", data.depth)
		data.modified_heightmap = modify_heightmap(data)
		
	for aabb in next_quadtree:
		var data = next_quadtree[aabb]
		data.meshinstance = generate_mesh(data)
		
		quadtree_pool[aabb] = data
	
func subdivide_quadtree(data: QuadtreeData):
	var depth = data.depth
	var aabb = data.aabb
	
	if depth >= quadtree_depth:
		next_quadtree[aabb] = data
		return
	
	var half_size = aabb.size.x * 0.5
	var half_extend = Vector3(half_size, half_size, half_size)
	
	var children = [
		[AABB(aabb.position, half_extend), ["top", "left"]],
		[AABB(aabb.position + Vector3(half_size, 0, 0), half_extend), ["top", "right"]],
		[AABB(aabb.position + Vector3(0, 0, half_size), half_extend), ["bottom", "left"]],
		[AABB(aabb.position + Vector3(half_size, 0, half_size), half_extend), ["bottom", "right"]]
	]
	
	for child in children:
		var child_aabb = child[0]
		var child_location = child[1]
		var child_data = QuadtreeData.new(child_aabb, depth+1, data, child_location)
		var center_point = child_aabb.get_center()
		# center_point.y = terrain_noise.get_noise_2d(center_point.x, center_point.z) * terrain_altitude
		var distance = Vector2(camera.position.x, camera.position.z).distance_to(Vector2(center_point.x, center_point.z))
		if distance < child_aabb.size.x * 1.0:
			subdivide_quadtree(child_data)
		else:
			next_quadtree[child_aabb] = child_data

func generate_heightmap(data: QuadtreeData) -> Array:
	var aabb = data.aabb
	data.steps = aabb.size.x / float(terrain_resolution - 1)
	var heightmap = []
	heightmap.resize(terrain_resolution)
	for z in range(terrain_resolution):
		heightmap[z] = []
		heightmap[z].resize(terrain_resolution)
		for x in range(terrain_resolution):
			var vertex = Vector3(x * data.steps, 0, z * data.steps)
			heightmap[z][x] = terrain_noise.get_noise_2d(vertex.x + aabb.position.x, vertex.z + aabb.position.z) * terrain_altitude
	
	return heightmap

func modify_heightmap(data: QuadtreeData) -> Array:
	var aabb = data.aabb
	var steps = data.steps
	var heightmap = data.original_heightmap
	var depth = data.depth
	var local_position = data.local_position
	
	if depth <= 1 :
		return heightmap
		
	var neighbors = get_neighbors(data)
	
	if neighbors.size() == 0 :
		return heightmap
		
	var border_points = {}
	
	for direction in neighbors:
		var n_data = next_quadtree[neighbors[direction]]
		var n_heightmap = n_data.modified_heightmap # Use modified heightmap !
		var n_steps = n_data.steps
		border_points[direction] = []
		
		if direction == "top":
			var z = terrain_resolution - 1
			for x in range(terrain_resolution):
				var vertex = Vector3(x * n_steps, n_heightmap[z][x], z * n_steps) + n_data.aabb.position
				border_points[direction].append(vertex)
			#draw_line(border_points[direction])
				
		if direction == "bottom":
			var z = 0
			for x in range(terrain_resolution):
				var vertex = Vector3(x * n_steps, n_heightmap[z][x], z * n_steps) + n_data.aabb.position
				border_points[direction].append(vertex)
				
		if direction == "left":
			var x = terrain_resolution - 1
			for z in range(terrain_resolution):
				var vertex = Vector3(x * n_steps, n_heightmap[z][x], z * n_steps) + n_data.aabb.position
				border_points[direction].append(vertex)
				
		if direction == "right":
			var x = 0
			for z in range(terrain_resolution):
				var vertex = Vector3(x * n_steps, n_heightmap[z][x], z * n_steps) + n_data.aabb.position
				border_points[direction].append(vertex)
		
	
	#print(" ")
	#print("aabb ", aabb)
	#print("local position, ", local_position)
	#print("neigbors, ", neighbors)
	
	var new_heightmap = []
	new_heightmap.resize(terrain_resolution)
	
	for z in range(terrain_resolution):
		new_heightmap[z] = []
		new_heightmap[z].resize(terrain_resolution)
		for x in range(terrain_resolution):
			var vertex = Vector3(x * steps, heightmap[z][x], z * steps)
			var new_height = heightmap[z][x]
			var vertex_world = vertex + aabb.position
			var is_border = false #( x == 0 and z == 0 or x == 0 and z == terrain_resolution - 1 or x == terrain_resolution - 1 and z == 0 or x == terrain_resolution - 1 and z == terrain_resolution - 1 )
			
			if x == 0 and neighbors.has("left") and not is_border:
				var closest_pair = get_two_closest_points_2d(vertex_world, border_points["left"])
				new_height = interpolate_height_2d(vertex_world, closest_pair)
				
			if x == terrain_resolution-1 and neighbors.has("right") and not is_border:
				var closest_pair = get_two_closest_points_2d(vertex_world, border_points["right"])
				new_height = interpolate_height_2d(vertex_world, closest_pair)
				
			if z == 0 and neighbors.has("top") and not is_border:
				var closest_pair = get_two_closest_points_2d(vertex_world, border_points["top"])
				new_height = interpolate_height_2d(vertex_world, closest_pair)
				
			if z == terrain_resolution-1 and neighbors.has("bottom") and not is_border:
				var closest_pair = get_two_closest_points_2d(vertex_world, border_points["bottom"])
				new_height = interpolate_height_2d(vertex_world, closest_pair)
			
			new_heightmap[z][x] = new_height
	
	return new_heightmap
	
func get_neighbors(data) -> Dictionary:
	var aabb = data.aabb
	var depth = data.depth
	var local_position = data.local_position
	var max_try = 10
	var neighbors = {}
	var current_data = data.parent_data
	var current_aabb = current_data.aabb
	var current_depth = current_data.depth
	
	while current_depth > 0 and max_try > 0 and neighbors.size() <= 2: # 2 possible neighbors max
		max_try -= 1
		var neighbors_offset = {
			"top" : Vector3(0,0,-current_aabb.size.z),
			"bottom" : Vector3(0,0,current_aabb.size.z),
			"left" : Vector3(-current_aabb.size.x,0,0),
			"right" : Vector3(current_aabb.size.x,0,0)
		}
		for direction in neighbors_offset:
			if neighbors.has(direction):
				continue
			if not local_position.has(direction):
				continue
				
			var offset = neighbors_offset[direction]
			var neighbor_aabb = AABB(current_aabb.position + offset, current_aabb.size)
			
			if not next_quadtree.has(neighbor_aabb):
				continue
			# Check for contact of aabb
			if direction == "top": # offset.z is negative, + operation
				if is_equal_approx(aabb.position.z , neighbor_aabb.position.z + neighbor_aabb.size.z):
					neighbors[direction] = neighbor_aabb
			if direction == "bottom":
				if is_equal_approx(aabb.position.z + aabb.size.z, neighbor_aabb.position.z):
					neighbors[direction] = neighbor_aabb
			if direction == "left": # offset.x is negative, + operation
				if is_equal_approx(aabb.position.x , neighbor_aabb.position.x + neighbor_aabb.size.x):
					neighbors[direction] = neighbor_aabb
			if direction == "right": 
				if is_equal_approx(aabb.position.x + aabb.size.x, neighbor_aabb.position.x):
					neighbors[direction] = neighbor_aabb
					
		current_data = current_data.parent_data
		current_depth = current_data.depth
		current_aabb = current_data.aabb

	return neighbors
	
func generate_mesh(data: QuadtreeData) -> MeshInstance3D:
	var aabb = data.aabb
	var steps = data.steps
	var heighmap = data.modified_heightmap
	
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for z in range(terrain_resolution):
		for x in range(terrain_resolution):
			var vertex = Vector3(x * steps, 0, z * steps)
			vertex.y = heighmap[z][x]
			surface_tool.add_vertex(vertex)
			
	for z in range(terrain_resolution-1):
		for x in range(terrain_resolution-1):
			var index = z * terrain_resolution + x
			surface_tool.add_index(index + 1)
			surface_tool.add_index(index + terrain_resolution)
			surface_tool.add_index(index)
			surface_tool.add_index(index + terrain_resolution + 1)
			surface_tool.add_index(index + terrain_resolution)
			surface_tool.add_index(index + 1)
			
	surface_tool.generate_normals()
	var mesh_instance = MeshInstance3D.new()
	var material = ShaderMaterial.new()
	material.shader = terrain_shader
	surface_tool.set_material(material)
	mesh_instance.mesh = surface_tool.commit()
	mesh_instance.position = aabb.position
	add_child(mesh_instance)
	mesh_instance.owner = get_tree().edited_scene_root
	
	return mesh_instance
	
func get_two_closest_points_2d(point: Vector3, points: Array) -> Array:
	if points.size() < 2:
		push_error("Array must contain at least 2 points.")
		return []
		
	var px = point.x
	var pz = point.z

	var closest = [null, null]
	var distances = [INF, INF]

	for p in points:
		var d = Vector2(px, pz).distance_to(Vector2(p.x, p.z))
		if d < distances[0]:
			distances[1] = distances[0]
			closest[1] = closest[0]
			distances[0] = d
			closest[0] = p
		elif d < distances[1]:
			distances[1] = d
			closest[1] = p

	return closest
	
func interpolate_height_2d(point: Vector3, neighbor_points: Array) -> float:
	# neighbor_points: array of Vector3 world positions
	# We'll do inverse-distance weighting in XZ plane.

	# find two closest in XZ
	var closest = get_two_closest_points_2d(point, neighbor_points)
	if closest.size() < 2:
		return point.y

	var p1 = closest[0]
	var p2 = closest[1]

	var d1 = Vector2(point.x, point.z).distance_to(Vector2(p1.x, p1.z))
	var d2 = Vector2(point.x, point.z).distance_to(Vector2(p2.x, p2.z))

	# if we are exactly on a sample horizontally, return that sample's Y
	if is_equal_approx(d1, 0.0):
		return p1.y
	if is_equal_approx(d2, 0.0):
		return p2.y

	# inverse-distance weighting (XZ)
	var w1 = 1.0 / d1
	var w2 = 1.0 / d2
	return (p1.y * w1 + p2.y * w2) / (w1 + w2)
	
func draw_line(points: Array, color = Color.RED):
	# Create an ImmediateMesh
	var mesh = ImmediateMesh.new()
	
	# Create a MeshInstance3D to display the mesh
	var mesh_instance = MeshInstance3D.new()
	#mesh_instance.position.y += 10
	mesh_instance.mesh = mesh
	mesh_instance.position.y += 50
	add_child(mesh_instance)
	
	# Create a simple material for the line
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.flags_unshaded = true # Disable lighting for visibility
	
	# Begin drawing the mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	
	# Define line start and end points
	for i in range(points.size()-1):
		var segment_start = points[i]
		var segment_stop = points[i+1]
		mesh.surface_add_vertex(segment_start)
		mesh.surface_add_vertex(segment_stop)

	# End the surface
	mesh.surface_end()

func draw_box (position: Vector3, color: Color = Color.RED, size = Vector3.ONE * 100):
	var mesh_instance = MeshInstance3D.new()
	var material = ShaderMaterial.new()
	material.shader = preload("res://shaders/wireframe.gdshader")
	material.set_shader_parameter("wire_color", color)
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = material
	mesh_instance.mesh = box_mesh
	mesh_instance.position = position
	add_child(mesh_instance)
