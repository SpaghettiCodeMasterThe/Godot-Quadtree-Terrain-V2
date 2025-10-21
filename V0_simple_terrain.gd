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
	#var children = []
	var parent : AABB
	var datas : QuadtreeDatas
	var mesh : MeshInstance3D
	var heightmap : Array
	var steps : float
	var neighbors : Array
	var local_position : Array
	
	func _init(_aabb : AABB, _depth : int, _local_position : Array) -> void:
		aabb = _aabb
		depth = _depth
		local_position = _local_position

func _ready() -> void:
	for child in get_children():
		child.free()
	
	camera = EditorInterface.get_editor_viewport_3d().get_camera_3d()
	camera_last_position = camera.position
	
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
	
	var root_datas = QuadtreeDatas.new(root_aabb, 0, [])
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
		[AABB(aabb.position + Vector3(0,0,half_size), half_extend),["top", "left"]],
		[AABB(aabb.position + Vector3(half_size,0,half_size), half_extend),["top", "right"]]
	]
		
	for child in children:
		var child_aabb = child[0]
		var child_local_position = child[1]
		var child_datas = QuadtreeDatas.new(child_aabb, depth + 1, child_local_position)
		
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
	pass
	
func generate_mesh(datas: QuadtreeDatas):
	var steps = datas.steps
	var heightmap = datas.heightmap
	var aabb = datas.aabb
	
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
