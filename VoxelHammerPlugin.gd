@tool

extends EditorPlugin

var ed_sel

var dock

func _enter_tree():
	print("VoxelHammer plugin loading...")
	add_custom_type("VoxelConfiguration", "Resource", preload("./classes/Resource/VoxelConfiguration.gd"), preload("./res/icon_vh.png"))
	add_custom_type("VoxelData", "Resource", preload("./classes/Resource/VoxelData.gd"), preload("./res/icon_vh.png"))
	add_custom_type("VoxelInstance3D", "Node3D", preload("./classes/Node3D/VoxelInstance3D.gd"), preload("./res/icon_vh.png"))
	name = "VoxelHammerPlugin"
	
	ed_sel = get_editor_interface().get_selection()
	ed_sel.connect("selection_changed", _on_selection_changed)
	
	var dock_vh = preload("./classes/EditorUI/VoxelHammerDock.tscn")
	dock_vh.resource_local_to_scene = true
	dock = dock_vh.instantiate()
	dock.editor_interface = get_editor_interface()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)
	
	add_autoload_singleton("VoxelHammer", "res://addons/TallDwarf/VoxelHammer/VoxelHammer.gd")


func _exit_tree():
	print("VoxelHammer plugin unloading...")
	remove_custom_type("VoxelConfiguration")
	remove_custom_type("VoxelData")
	remove_custom_type("VoxelInstance3D")
	#remove_custom_type("VoxelPaintStack")
	#remove_custom_type("VoxelTerrain")
	#remove_custom_type("VoxelThing")

	if dock:
		remove_control_from_docks(dock)
		dock.free()
	
	remove_autoload_singleton("VoxelHammer")


func _handles(object: Variant):
	#print("_handles? : %s" % str(object))
	if object is VoxelInstance3D:
		return true

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent):
	return dock._forward_3d_gui_input(viewport_camera,event)

func _on_selection_changed():
	#print("VoxelHammerPlugin: selection changed")
	
	# Returns an array of selected nodes
	var selected : Array[Node] = ed_sel.get_selected_nodes() 
	
	if not selected.is_empty():
		# Always pick first node in selection
		if dock:
			dock.selection = selected[0]
	else:
		if dock:
			dock.selection = null
