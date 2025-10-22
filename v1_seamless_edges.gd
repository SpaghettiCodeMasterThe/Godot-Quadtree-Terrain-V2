@tool
extends Node3D

var terrain_size = 100000
var terrain_resolution = 8
var terrain_altitude = 8000
var terrain_noise = FastNoiseLite.new()
var terrain_shader = preload("res://shaders/terrain_auto.gdshader")

var quadtree_max_depth = 10
var current_quadtree = {}
var next_quadtree = {}
#var quadtree_root : QuadTreeChunk
var root_aabb = AABB(Vector3.ZERO, Vector3.ONE * terrain_size)

var camera : Camera3D
var camera_last_position : Vector3

class QuadtreeDatas :
	var aabb : AABB
	var depth : int
	var parent_datas : QuadtreeDatas
	var mesh : MeshInstance3D
	var heightmap : Array
	var steps : float
	var local_position : Array
	
	func _init(_aabb : AABB, _parent_datas : QuadtreeDatas, _depth : int, _local_position : Array) -> void:
		aabb = _aabb
		depth = _depth
		local_position = _local_position
		parent_datas = _parent_datas

func _ready() -> void:
	for child in get_children():
		child.free()
	
	camera = EditorInterface.get_editor_viewport_3d().get_camera_3d()
	camera_last_position = camera.position
	
	terrain_noise.seed = 100
	terrain_noise.frequency = 0.00001
	terrain_noise.fractal_octaves = 20
	
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
	
	var root_datas = QuadtreeDatas.new(root_aabb, null, 0, [])
	subdivide_quadtree(root_datas)
	
	for aabb in next_quadtree:
		var datas = next_quadtree[aabb]
		generate_heightmap(datas)
		
	for aabb in next_quadtree:
		var datas = next_quadtree[aabb]
		modify_heightmap(datas)
		
	for aabb in next_quadtree:
		var datas = next_quadtree[aabb]
		generate_mesh(datas)
	
func subdivide_quadtree(quadtree_datas: QuadtreeDatas):
	var aabb = quadtree_datas.aabb
	var depth = quadtree_datas.depth
	
	if depth >= quadtree_max_depth:
		next_quadtree[aabb] = quadtree_datas
		return
		
	var half_size = aabb.size.x * 0.5
	var half_extend = Vector3(half_size,half_size,half_size)
	var children = [
		[AABB(aabb.position, half_extend),["top", "left"]],
		[AABB(aabb.position + Vector3(half_size,0,0), half_extend),["top", "right"]],
		[AABB(aabb.position + Vector3(0,0,half_size), half_extend),["bottom", "left"]],
		[AABB(aabb.position + Vector3(half_size,0,half_size), half_extend),["bottom", "right"]]
	]
		
	for child in children:
		var child_aabb = child[0]
		var child_local_position = child[1]
		
		var child_datas = QuadtreeDatas.new(child_aabb, quadtree_datas, depth + 1, child_local_position)
		
		var center_point = child_aabb.get_center()
		center_point.y = terrain_noise.get_noise_2d(center_point.x, center_point.z)
		#var distance = center_position.distance_to(camera.position)
		var distance = Vector2(center_point.x, center_point.z).distance_to(Vector2(camera.position.x, camera.position.z))
		if distance < aabb.size.x * 0.5:
			subdivide_quadtree(child_datas)
		else:
			next_quadtree[child_aabb] = child_datas
	
func generate_heightmap(datas: QuadtreeDatas):
	var aabb = datas.aabb
	var steps = aabb.size.x / float(terrain_resolution-1)
	var heightmap = []
	heightmap.resize(terrain_resolution)
	for z in range(terrain_resolution):
		heightmap[z] = []
		heightmap[z].resize(terrain_resolution)
		for x in range(terrain_resolution):
			var vertex = Vector3(x * steps, 0, z * steps)
			vertex.y = terrain_noise.get_noise_2d(aabb.position.x + vertex.x, aabb.position.z + vertex.z) * terrain_altitude
			heightmap[z][x] = vertex.y
	datas.heightmap = heightmap
	datas.steps = steps
	
func modify_heightmap(datas: QuadtreeDatas):
	# Skip depth 0 and 1
	if datas.depth == 0 or datas.depth == 1:
		return
	
	var aabb = datas.aabb
	var steps = datas.steps
	var heightmap = datas.heightmap
	
	# Get neighbors with the least depth
	var neighbors = get_neighbors(datas)
	
	for z in range(terrain_resolution):
		for x in range(terrain_resolution):
			var vertex_pos = Vector3(x * steps, 0, z * steps)
			var vertex_world = vertex_pos + aabb.position
			var new_height = heightmap[z][x]
			var height_assigned = false
			
			# Handle corners first
			# Top-left corner (x == 0, z == 0)
			if x == 0 and z == 0 and neighbors.has("left") and neighbors.has("top"):
				var left_datas = next_quadtree[neighbors["left"]]
				var top_datas = next_quadtree[neighbors["top"]]
				var left_depth = left_datas.depth
				var top_depth = top_datas.depth
				if top_depth < left_depth:
					# Use top neighbor
					var neighbor_aabb = neighbors["top"]
					var neighbor_datas = top_datas
					var neighbor_steps = neighbor_datas.steps
					var neighbor_heightmap = neighbor_datas.heightmap
					var neighbor_z = terrain_resolution - 1
					var border_points = []
					for neighbor_x in range(terrain_resolution):
						var neighbor_vertex = Vector3(neighbor_x * neighbor_steps, neighbor_heightmap[neighbor_z][neighbor_x], neighbor_z * neighbor_steps) + neighbor_aabb.position
						border_points.append(neighbor_vertex)
					var closest_pair = closest_pair(vertex_world, border_points, false)
					new_height = interpolate_height(vertex_world, closest_pair[0], closest_pair[1], false)
					height_assigned = true
				# Else, fall through to use left neighbor
			
			# Top-right corner (x == terrain_resolution-1, z == 0)
			elif x == terrain_resolution-1 and z == 0 and neighbors.has("right") and neighbors.has("top"):
				var right_datas = next_quadtree[neighbors["right"]]
				var top_datas = next_quadtree[neighbors["top"]]
				var right_depth = right_datas.depth
				var top_depth = top_datas.depth
				if top_depth < right_depth:
					# Use top neighbor
					var neighbor_aabb = neighbors["top"]
					var neighbor_datas = top_datas
					var neighbor_steps = neighbor_datas.steps
					var neighbor_heightmap = neighbor_datas.heightmap
					var neighbor_z = terrain_resolution - 1
					var border_points = []
					for neighbor_x in range(terrain_resolution):
						var neighbor_vertex = Vector3(neighbor_x * neighbor_steps, neighbor_heightmap[neighbor_z][neighbor_x], neighbor_z * neighbor_steps) + neighbor_aabb.position
						border_points.append(neighbor_vertex)
					var closest_pair = closest_pair(vertex_world, border_points, false)
					new_height = interpolate_height(vertex_world, closest_pair[0], closest_pair[1], false)
					height_assigned = true
				# Else, fall through to use right neighbor
			
			# Bottom-left corner (x == 0, z == terrain_resolution-1)
			elif x == 0 and z == terrain_resolution-1 and neighbors.has("left") and neighbors.has("bottom"):
				var left_datas = next_quadtree[neighbors["left"]]
				var bottom_datas = next_quadtree[neighbors["bottom"]]
				var left_depth = left_datas.depth
				var bottom_depth = bottom_datas.depth
				if bottom_depth < left_depth:
					# Use bottom neighbor
					var neighbor_aabb = neighbors["bottom"]
					var neighbor_datas = bottom_datas
					var neighbor_steps = neighbor_datas.steps
					var neighbor_heightmap = neighbor_datas.heightmap
					var neighbor_z = 0
					var border_points = []
					for neighbor_x in range(terrain_resolution):
						var neighbor_vertex = Vector3(neighbor_x * neighbor_steps, neighbor_heightmap[neighbor_z][neighbor_x], neighbor_z * neighbor_steps) + neighbor_aabb.position
						border_points.append(neighbor_vertex)
					var closest_pair = closest_pair(vertex_world, border_points, false)
					new_height = interpolate_height(vertex_world, closest_pair[0], closest_pair[1], false)
					height_assigned = true
				# Else, fall through to use left neighbor
			
			# Bottom-right corner (x == terrain_resolution-1, z == terrain_resolution-1)
			elif x == terrain_resolution-1 and z == terrain_resolution-1 and neighbors.has("right") and neighbors.has("bottom"):
				var right_datas = next_quadtree[neighbors["right"]]
				var bottom_datas = next_quadtree[neighbors["bottom"]]
				var right_depth = right_datas.depth
				var bottom_depth = bottom_datas.depth
				if bottom_depth < right_depth:
					# Use bottom neighbor
					var neighbor_aabb = neighbors["bottom"]
					var neighbor_datas = bottom_datas
					var neighbor_steps = neighbor_datas.steps
					var neighbor_heightmap = neighbor_datas.heightmap
					var neighbor_z = 0
					var border_points = []
					for neighbor_x in range(terrain_resolution):
						var neighbor_vertex = Vector3(neighbor_x * neighbor_steps, neighbor_heightmap[neighbor_z][neighbor_x], neighbor_z * neighbor_steps) + neighbor_aabb.position
						border_points.append(neighbor_vertex)
					var closest_pair = closest_pair(vertex_world, border_points, false)
					new_height = interpolate_height(vertex_world, closest_pair[0], closest_pair[1], false)
					height_assigned = true
				# Else, fall through to use right neighbor
			
			if height_assigned:
				heightmap[z][x] = new_height
				continue
			
			# Handle non-corner borders
			# Left border (x == 0)
			if x == 0 and neighbors.has("left"):
				var neighbor_aabb = neighbors["left"]
				var neighbor_datas = next_quadtree[neighbor_aabb]
				var neighbor_steps = neighbor_datas.steps
				var neighbor_heightmap = neighbor_datas.heightmap
				var neighbor_x = terrain_resolution - 1
				var border_points = []
				for neighbor_z in range(terrain_resolution):
					var neighbor_vertex = Vector3(neighbor_x * neighbor_steps, neighbor_heightmap[neighbor_z][neighbor_x], neighbor_z * neighbor_steps) + neighbor_aabb.position
					border_points.append(neighbor_vertex)
				var closest_pair = closest_pair(vertex_world, border_points, true)
				new_height = interpolate_height(vertex_world, closest_pair[0], closest_pair[1], true)
			
			# Right border (x == terrain_resolution-1)
			elif x == terrain_resolution-1 and neighbors.has("right"):
				var neighbor_aabb = neighbors["right"]
				var neighbor_datas = next_quadtree[neighbor_aabb]
				var neighbor_steps = neighbor_datas.steps
				var neighbor_heightmap = neighbor_datas.heightmap
				var neighbor_x = 0
				var border_points = []
				for neighbor_z in range(terrain_resolution):
					var neighbor_vertex = Vector3(neighbor_x * neighbor_steps, neighbor_heightmap[neighbor_z][neighbor_x], neighbor_z * neighbor_steps) + neighbor_aabb.position
					border_points.append(neighbor_vertex)
				var closest_pair = closest_pair(vertex_world, border_points, true)
				new_height = interpolate_height(vertex_world, closest_pair[0], closest_pair[1], true)
			
			# Top border (z == 0)
			elif z == 0 and neighbors.has("top"):
				var neighbor_aabb = neighbors["top"]
				var neighbor_datas = next_quadtree[neighbor_aabb]
				var neighbor_steps = neighbor_datas.steps
				var neighbor_heightmap = neighbor_datas.heightmap
				var neighbor_z = terrain_resolution - 1
				var border_points = []
				for neighbor_x in range(terrain_resolution):
					var neighbor_vertex = Vector3(neighbor_x * neighbor_steps, neighbor_heightmap[neighbor_z][neighbor_x], neighbor_z * neighbor_steps) + neighbor_aabb.position
					border_points.append(neighbor_vertex)
				var closest_pair = closest_pair(vertex_world, border_points, false)
				new_height = interpolate_height(vertex_world, closest_pair[0], closest_pair[1], false)
			
			# Bottom border (z == terrain_resolution-1)
			elif z == terrain_resolution-1 and neighbors.has("bottom"):
				var neighbor_aabb = neighbors["bottom"]
				var neighbor_datas = next_quadtree[neighbor_aabb]
				var neighbor_steps = neighbor_datas.steps
				var neighbor_heightmap = neighbor_datas.heightmap
				var neighbor_z = 0
				var border_points = []
				for neighbor_x in range(terrain_resolution):
					var neighbor_vertex = Vector3(neighbor_x * neighbor_steps, neighbor_heightmap[neighbor_z][neighbor_x], neighbor_z * neighbor_steps) + neighbor_aabb.position
					border_points.append(neighbor_vertex)
				var closest_pair = closest_pair(vertex_world, border_points, false)
				new_height = interpolate_height(vertex_world, closest_pair[0], closest_pair[1], false)
			
			heightmap[z][x] = new_height
	
	datas.heightmap = heightmap
	
func get_neighbors(datas: QuadtreeDatas) -> Dictionary:
	var aabb = datas.aabb
	var local_position = datas.local_position
	var neighbors = {}
	
	var current_datas = datas.parent_datas
	var current_aabb = current_datas.aabb
	
	var max_try = 10
	while max_try > 0 and neighbors.size() < 4 and current_datas.depth > 0:
		max_try -= 1 # to remove
		var neighbors_offset = {
			"left" : Vector3(-current_aabb.size.x, 0, 0),
			"right" : Vector3(current_aabb.size.x, 0, 0),
			"top" : Vector3(0, 0, -current_aabb.size.z),
			"bottom" : Vector3(0, 0, current_aabb.size.z)
		}
		for direction in neighbors_offset:
			var offset = neighbors_offset[direction]
			var neighbor_aabb = AABB(current_aabb.position + offset, current_aabb.size)
			# Direction found ?
			if neighbors.has(direction):
				continue
			# AABB exist ?
			if not next_quadtree.has(neighbor_aabb):
				continue
			# Direction match ?
			if not local_position.has(direction):
				continue
			# Neighbor touch aabb ?
			if direction == "left":
				if is_equal_approx(aabb.position.x, neighbor_aabb.position.x + neighbor_aabb.size.x):
					neighbors[direction] = neighbor_aabb
			if direction == "right":
				if is_equal_approx(aabb.position.x + aabb.size.x, neighbor_aabb.position.x):
					neighbors[direction] = neighbor_aabb
			if direction == "top":
				if is_equal_approx(aabb.position.z, neighbor_aabb.position.z + neighbor_aabb.size.z):
					neighbors[direction] = neighbor_aabb
			if direction == "bottom":
				if is_equal_approx(aabb.position.z + aabb.size.z, neighbor_aabb.position.z):
					neighbors[direction] = neighbor_aabb
		
		current_datas = current_datas.parent_datas
		current_aabb = current_datas.aabb
		
	return neighbors
func generate_mesh(datas: QuadtreeDatas):
	var aabb = datas.aabb
	var steps = datas.steps
	var heightmap = datas.heightmap
	
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for z in range(terrain_resolution):
		for x in range(terrain_resolution):
			var vertex = Vector3(x * steps, 0, z * steps)
			vertex.y = heightmap[z][x]
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

func closest_pair(current_point : Vector3, points: Array, is_x_axis : bool):
	if points.size() < 2:
		print("not enough points")
		return []
	var distances = []
	var current_point_x_or_z = current_point.z if is_x_axis else current_point.x
	for point in points:
		var point_x_or_z = point.z if is_x_axis else point.x
		distances.append({
			"point" : point,
			"distance" : abs(current_point_x_or_z - point_x_or_z)
		})
	distances.sort_custom(func(a,b): return a.distance < b.distance)
	return [distances[0].point, distances[1].point]

func interpolate_height(current_point: Vector3, p1: Vector3, p2: Vector3, is_x_axis : bool) -> float:
	var p1_x_or_z = p1.z if is_x_axis else p1.x
	var p2_x_or_z = p2.z if is_x_axis else p2.x
	var current_point_x_or_z = current_point.z if is_x_axis else current_point.x
	var t = (current_point_x_or_z - p1_x_or_z) / (p2_x_or_z - p1_x_or_z)
	var height = p1.y + t * (p2.y - p1.y)
	return height

func draw_line(points: Array, color = Color.RED):
	# Create an ImmediateMesh
	var mesh = ImmediateMesh.new()
	
	# Create a MeshInstance3D to display the mesh
	var mesh_instance = MeshInstance3D.new()
	#mesh_instance.position.y += 10
	mesh_instance.mesh = mesh
	mesh_instance.position.y += 10
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
