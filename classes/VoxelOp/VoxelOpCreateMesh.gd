extends VoxelOperation


class_name VoxelOpCreateMesh 

var mesh_buffer
var material_table


func _init():
	super("VoxOpCreateMesh", VoxelOperation.CALCULATION_LEVEL.MESH)


# This code is executed in another thread so it can not access voxel_node variable!
func run_operation():
	#print("!!! VoxelOpCreateMesh executing!")
	var mesh_empty = false
	
	if voxel_instance.visibility_count == 0:
		mesh_empty = true
	else:
		match voxel_instance.configuration.mesh_mode:
			VoxelConfiguration.MESH_MODE.NONE:
				mesh_empty = true
			VoxelConfiguration.MESH_MODE.CUBES:
				construct_mesh_cubes(voxel_instance.voxel_data.data, voxel_instance.vis_buffer, voxel_instance.voxel_data.size)
			VoxelConfiguration.MESH_MODE.FACES:
				mesh_empty = true
				pass#construct_mesh_faces()
			VoxelConfiguration.MESH_MODE.FAST:
				mesh_empty = true
				pass#construct_mesh_fast()
			_:
				push_warning("VoxelOpCreateMesh: mesh mode unimplented -> cancelling")
				mesh_empty = true
		
	
	if mesh_empty:
		voxel_instance.call_deferred("set_mesh", null)
	else:
		# Assign right materials from configuration
		for j in range(material_table.size()):
			var si = material_table[j]
			if si >= voxel_instance.configuration.materials.size():
				si = 0
			mesh_buffer.surface_set_material(j, voxel_instance.configuration.materials[si])
		
		voxel_instance.call_deferred("set_mesh", mesh_buffer)
	
	voxel_instance.call_deferred("notify_mesh_calculated")



#Vertices of a cube
const cube_vertices = [[0,0,0],[1,0,0],[0,1,0],[1,0,0],[1,1,0],[0,1,0], #left -Z
				[1,0,1],[0,1,1],[1,1,1],[0,0,1],[0,1,1],[1,0,1], #right +Z
				[0,0,0],[0,0,1],[1,0,0],[1,0,1],[1,0,0],[0,0,1], #bottom -Y
				[0,1,0],[1,1,0],[0,1,1],[1,1,1],[0,1,1],[1,1,0], #top +Y
				[0,0,0],[0,1,0],[0,0,1],[0,1,0],[0,1,1],[0,0,1], #front -X
				[1,0,0],[1,0,1],[1,1,0],[1,0,1],[1,1,1],[1,1,0]] #back +X

const cube_normals = [[0,0,-1],[0,0,-1],[0,0,-1],[0,0,-1],[0,0,-1],[0,0,-1], #left -Z
				[0,0,1],[0,0,1],[0,0,1],[0,0,1],[0,0,1],[0,0,1], #right +Z
				[0,-1,0],[0,-1,0],[0,-1,0],[0,-1,0],[0,-1,0],[0,-1,0], #bottom -Y
				[0,1,0],[0,1,0],[0,1,0],[0,1,0],[0,1,0],[0,1,0], #top +Y
				[-1,0,0],[-1,0,0],[-1,0,0],[-1,0,0],[-1,0,0],[-1,0,0], #front -X
				[1,0,0],[1,0,0],[1,0,0],[1,0,0],[1,0,0],[1,0,0]] #back +X

const cube_uvs = [[0,0],[1,0],[0,1],[1,0],[1,1],[0,1], #left -Z
				[0,0],[1,1],[0,1],[1,0],[1,1],[0,0], #right +Z
				[0,0],[0,1],[1,0],[1,1],[1,0],[0,1], #bottom -Y !fix
				[0,0],[1,0],[0,1],[1,1],[0,1],[1,0], #top +Y
				[0,0],[1,0],[0,1],[1,0],[1,1],[0,1], #front -X !fix
				[0,0],[1,0],[0,1],[1,0],[1,1],[0,1]] #back +X

func construct_mesh_cubes(data : PackedInt64Array, vis_buffer : PackedByteArray, size : Vector3i):
	print("Constructing CUBES mesh...")
	# Creates cubes mesh from voxel data
	
	# Create one SurfaceTool per material
	var surface_tools = {}
	
	var sx :int = size.x
	var sy :int = size.y
	var sz :int = size.z
	
	var material_at_index= 0
	var visible_at_index = false
	mesh_buffer = ArrayMesh.new()
	
	# Loop trough all indices (once only)
	for z in range(sz):
		for y in range(sy):
			for x in range(sx):
				var ci : int = x + y*sx + z*sx*sy
				material_at_index = data[ci]
				visible_at_index = vis_buffer[ci]
				
				if vis_buffer[ci] and material_at_index:
					if not material_at_index in surface_tools:
						#print("added surface tool %s" % material_at_index)
						surface_tools[material_at_index] = SurfaceTool.new()
						surface_tools[material_at_index].begin(Mesh.PRIMITIVE_TRIANGLES)
						#surface_tools[material_at_index].set_smooth_group(1)
					var st = surface_tools[material_at_index]
					
					# TODO: implement as check from configuration materials
#					if smooth_buffer[ci]:
#						surface_tools[material_at_index].set_smooth_group(1)
#					else:
#						surface_tools[material_at_index].set_smooth_group(0)
							
					#var subtimer = DebugTimer.new("Sub")
					for i in cube_vertices.size():
						st.set_uv(Vector2(1-cube_uvs[i][0],1-cube_uvs[i][1]))
						st.set_normal(Vector3(cube_normals[i][0],cube_normals[i][1],cube_normals[i][2]))
						st.add_vertex(Vector3(cube_vertices[i][0]+x,cube_vertices[i][1]+y,cube_vertices[i][2]+z))
					
					#subtimer.end()
	
	# Add all surfaces to mesh
	var i = 0
	material_table = {}
	for key in surface_tools.keys():
		#surface_tools[key].index()
		#surface_tools[key].generate_normals()
		surface_tools[key].generate_tangents()
		mesh_buffer.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_tools[key].commit_to_arrays())
		material_table[i] = key
		i = i+1
	


## Faces of a cube
#const cube_face_left = [[0,0,0],[1,0,0],[0,1,0],[1,0,0],[1,1,0],[0,1,0]]   # -x
#const cube_face_right = [[1,0,1],[0,1,1],[1,1,1],[0,0,1],[0,1,1],[1,0,1]]  # x
#const cube_face_bottom = [[0,0,0],[0,0,1],[1,0,0],[1,0,1],[1,0,0],[0,0,1]] # -y
#const cube_face_top = [[0,1,0],[1,1,0],[0,1,1],[1,1,1],[0,1,1],[1,1,0]]    # y
#const cube_face_front = [[0,0,0],[0,1,0],[0,0,1],[0,1,0],[0,1,1],[0,0,1]]  # -z
#const cube_face_back = [[1,0,0],[1,0,1],[1,1,0],[1,0,1],[1,1,1],[1,1,0]]   # z

#func construct_mesh_faces():
#	#print("Constructing FACE mesh")
#	# Creates face mesh from voxel data
#
#	# Create one SurfaceTool per material
#	var surface_tools = {}
#
#	var sx :int = voxel_data.voxel_count.x
#	var sy :int = voxel_data.voxel_count.y
#	var sz :int = voxel_data.voxel_count.z
#
#	var largest_count : float = max(max(sx,sy),sz)
#	var total : int = sx*sy*sz
#	var smooth_group_active = false
#	mesh_buffer = ArrayMesh.new()
##
##	# Loop trough all indices (once only)
#	for x in range(sx):
#		for y in range(sy):
#			for z in range(sz):
#				var ci : int = x + y*sx + z*sx*sy
#				var material_at_index = material_buffer[ci]
#				var visible_at_index = vis_buffer[ci]
#
#				if material_at_index and visible_at_index:
#					if not material_at_index in surface_tools:
#						surface_tools[material_at_index] = SurfaceTool.new()
#						surface_tools[material_at_index].begin(Mesh.PRIMITIVE_TRIANGLES)
#					var st = surface_tools[material_at_index]
#
#					if smooth_buffer[ci]:
#						if not smooth_group_active:
#							surface_tools[material_at_index].add_smooth_group(true)
#							smooth_group_active = true
#					else:
#						surface_tools[material_at_index].add_smooth_group(false)
#						smooth_group_active = false
#
#					if x == 0 or not material_buffer[ci-1]:
#						for vert in cube_face_front:
#							#st.add_uv(Vector2((vert[2]+z)/largest_count,1-(vert[1]+y)/largest_count))
#							#st.add_uv(Vector2(0,0))
#							st.add_vertex(Vector3(vert[0]+x,vert[1]+y,vert[2]+z))
#					if x == sx-1 or not material_buffer[ci+1]:
#						for vert in cube_face_back:
#							#st.add_uv(Vector2(1-(vert[2]+z)/largest_count,1-(vert[1]+y)/largest_count))
#							#st.add_uv(Vector2(0,0))
#							st.add_vertex(Vector3(vert[0]+x,vert[1]+y,vert[2]+z))
#					if y == 0 or not material_buffer[ci-sx]:
#						for vert in cube_face_bottom:
#							#st.add_uv(Vector2(1-(vert[0]+x)/largest_count,(vert[2]+z)/largest_count))
#							#st.add_uv(Vector2(0,0))
#							st.add_vertex(Vector3(vert[0]+x,vert[1]+y,vert[2]+z))
#					if y == sy-1 or not material_buffer[ci+sx]:
#						for vert in cube_face_top:
#							#st.add_uv(Vector2(1-(vert[0]+x)/largest_count,1-(vert[2]+z)/largest_count))
#							#st.add_uv(Vector2(0,0))
#							st.add_vertex(Vector3(vert[0]+x,vert[1]+y,vert[2]+z))
#					if z == 0 or not material_buffer[ci-sx*sy]:
#						for vert in cube_face_left:
#							#st.add_uv(Vector2(1-(vert[0]+x)/largest_count,1-(vert[1]+y)/largest_count))
#							#st.add_uv(Vector2(0,0))
#							st.add_vertex(Vector3(vert[0]+x,vert[1]+y,vert[2]+z))
#					if z == sz-1 or not material_buffer[ci+sx*sy]:
#						for vert in cube_face_right:
#							#st.add_uv(Vector2((vert[0]+x)/largest_count,1-(vert[1]+y)/largest_count))
#							#st.add_uv(Vector2(0,0))
#							st.add_vertex(Vector3(vert[0]+x,vert[1]+y,vert[2]+z))
#
#
#	# Convert all surfaces to meshes
#	var i = 0
#	material_table = {}
#	for key in surface_tools.keys():
#		surface_tools[key].generate_normals()
#		#surface_tools[key].generate_tangents()
#
#		mesh_buffer.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_tools[key].commit_to_arrays())
#
#		material_table[i] = key
#		i = i+1
#
#	for j in range(material_table.size()):
#		var si = material_table[j]
#		if si >= voxel_configuration.materials.size():
#			si = 0
#		mesh_buffer.surface_set_material(j, voxel_configuration.materials[si])
#
#
#func construct_mesh_fast():
#	if cancel:
#		return
#
#	match voxel_configuration.accel_mode:
#		VoxelConfiguration.ACCEL_MODE.NONE:
#			construct_mesh_fast_gdscript()
#		VoxelConfiguration.ACCEL_MODE.NATIVE:
#			construct_mesh_fast_native()
#		_:
#			push_warning("VoxelOpCreateMesh: accel mode unimplented -> falling back to none")
#			construct_mesh_fast_gdscript()
#
#
#func construct_mesh_fast_gdscript():
#	#print("Constructing FACE mesh")
#	# Creates face mesh from voxel data
#
#	# Create one SurfaceTool per material
#	var surface_tools = {}
#
#	var sx :int = voxel_data.voxel_count.x
#	var sy :int = voxel_data.voxel_count.y
#	var sz :int = voxel_data.voxel_count.z
#
#	var largest_count = voxel_data.largest_count
#
#	var smooth_group_active = false
#	mesh_buffer = ArrayMesh.new()
##
##	# Loop trough all indices (once only)
#	for x in range(sx):
#		for y in range(sy):
#			for z in range(sz):
#
#				if cancel:
#					return
#
#				var ci : int = x + y*sx + z*sx*sy
#				var material_at_index = material_buffer[ci]
#				var visible_at_index = vis_buffer[ci]
#
#				if material_at_index and visible_at_index:
#					if not material_at_index in surface_tools:
#						surface_tools[material_at_index] = SurfaceTool.new()
#						surface_tools[material_at_index].begin(Mesh.PRIMITIVE_TRIANGLES)
#					var st = surface_tools[material_at_index]
#
#					if smooth_buffer[ci]:
#						if not smooth_group_active:
#							surface_tools[material_at_index].add_smooth_group(true)
#							smooth_group_active = true
#					elif smooth_group_active:
#						surface_tools[material_at_index].add_smooth_group(false)
#						smooth_group_active = false
#
#					if x == 0 or not material_buffer[ci-1]:
#						for vert in cube_face_front:
#							st.add_uv(Vector2((vert[2]+z)/largest_count,1-(vert[1]+y)/largest_count))
#							st.add_vertex(Vector3(vert[0]+x,vert[1]+y,vert[2]+z))
#					if x == sx-1 or not material_buffer[ci+1]:
#						for vert in cube_face_back:
#							st.add_uv(Vector2(1-(vert[2]+z)/largest_count,1-(vert[1]+y)/largest_count))
#							st.add_vertex(Vector3(vert[0]+x,vert[1]+y,vert[2]+z))
#					if y == 0 or not material_buffer[ci-sx]:
#						for vert in cube_face_bottom:
#							st.add_uv(Vector2(1-(vert[0]+x)/largest_count,(vert[2]+z)/largest_count))
#							st.add_vertex(Vector3(vert[0]+x,vert[1]+y,vert[2]+z))
#					if y == sy-1 or not material_buffer[ci+sx]:
#						for vert in cube_face_top:
#							st.add_uv(Vector2(1-(vert[0]+x)/largest_count,1-(vert[2]+z)/largest_count))
#							st.add_vertex(Vector3(vert[0]+x,vert[1]+y,vert[2]+z))
#					if z == 0 or not material_buffer[ci-sx*sy]:
#						for vert in cube_face_left:
#							st.add_uv(Vector2(1-(vert[0]+x)/largest_count,1-(vert[1]+y)/largest_count))
#							st.add_vertex(Vector3(vert[0]+x,vert[1]+y,vert[2]+z))
#					if z == sz-1 or not material_buffer[ci+sx*sy]:
#						for vert in cube_face_right:
#							st.add_uv(Vector2((vert[0]+x)/largest_count,1-(vert[1]+y)/largest_count))
#							st.add_vertex(Vector3(vert[0]+x,vert[1]+y,vert[2]+z))
#
#
#	# Convert all surfaces to meshes
#	var i = 0
#	material_table = {}
#	for key in surface_tools.keys():
#		surface_tools[key].generate_normals()
#		surface_tools[key].generate_tangents()
#
#		mesh_buffer.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_tools[key].commit_to_arrays())
#
#		material_table[i] = key
#		i = i+1
#
#	for j in range(material_table.size()):
#		var si = material_table[j]
#		if si >= voxel_configuration.materials.size():
#			si = 0
#		mesh_buffer.surface_set_material(j, voxel_configuration.materials[si])
#
#
#
#func construct_mesh_fast_native():
#	if cancel:
#		return
#
#	var native_worker = VoxelHammer.native_worker
#	if not native_worker:
#		push_warning("VoxelOpCreateMesh: Native worker not found. Falling back to ACCEL_MODE.NONE")
#		construct_mesh_fast()
#		return
#
#	var retarray = native_worker.create_mesh(voxel_data.voxel_count,material_buffer, smooth_buffer, vis_buffer)
#	mesh_buffer = retarray[0]
#	material_table = retarray[1]
#	#print("Got material_table: %s" % material_table)
#
#	for j in range(material_table.size()):
#		var si = material_table[j]
#		if si >= voxel_configuration.materials.size():
#			si = 0
#		mesh_buffer.surface_set_material(j, voxel_configuration.materials[si])
	
