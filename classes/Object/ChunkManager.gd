@tool

extends Node

class_name ChunkManager

## Manages a persistent state of loaded chunks
##
## - Keeps a target amount of loaded chunks in memory
## - Keeps a target amount of active chunks around hotspots
## - Signals state changes for all chunks
## ! Does not know and does not need to know about chunk contents


## Completely new chunk is being generated
signal new_chunk_created
## Chunk has been loaded into memory, but not yet active
signal chunk_loaded
## Chunk is added to the active world area
signal chunk_activated
## Chunk is removed from the active world area, but not unloaded
signal chunk_deactivated
## Chunk data completely removed from memory and potentially written to disk
signal chunk_unloaded


signal hotspot_added
signal hotspot_removed


## Empty unloaded chunk has been initialized and thus search area has been expanded, for debug purposes
signal chunk_initialized
## Chunk has been copletely removed and thus search area has been contracted, for debug purposes
signal chunk_deleted
## Chunk distance value to closest hotspot has been updated, for debug purposes
signal shortest_distance_updated


@export var chunk_size : int = 16:
	set(nv):
		chunk_size = nv
		half_chunk = Vector3i(nv/2,nv/2,nv/2)
@export var half_chunk : Vector3i


@export_group("Database File")
## database base folder, usually "user://somefolder"
@export var database_folder : String = ""
## unique id to distinguish for different saves/users, even if they use same database name
@export var database_uid : String = ""
## Human readable part of database name
@export var database_name : String = ""
## Savefile format, currently supported tscn and scn
@export var database_format : String = ""

## Create database folder if it does not exist
## Note to not try: this could be made to happen automatically when any database_* variables changes, but in editor this will create all folders from editing the prompts like : "d", "da", "dat", "data" ... as godot refreshes variable after every edit
@export var create_database_folder : bool = false:
	set(nv): rebuild_database_folder()

@export_group("Chunk generation")
## How many unloaded chunks to keep in search area
@export var max_chunks : int = 200:
	set(nv):
		max_chunks = nv
		if max_loaded > max_chunks: max_loaded = max_chunks
		if max_active > max_chunks: max_active = max_chunks
		_update_all_hotspots()

## How many chunks to keep in memory, even if some of them are not active. This can mitigate unneeded disk trashing
@export var max_loaded : int = 50:
	set(nv):
		max_loaded = nv
		if max_chunks < max_loaded: max_chunks = max_loaded
		if max_active > max_loaded: max_active = max_loaded
		_update_all_hotspots()

## Maximum active chunks. This can be interpreted as chunks that are drawn and receive _process signals f.ex. Proper activvation logic needs to be implemented by listening to chunk_activated / chunk_deactivated signals
@export var max_active : int = 20:
	set(nv):
		max_active = nv
		if max_chunks < max_active: max_chunks = max_active
		if max_loaded < max_active: max_loaded = max_active
		_update_all_hotspots()

## Wether to utilize threading for chunk logic and file read/write
@export var thread_mode : VoxelConfiguration.THREAD_MODE = VoxelConfiguration.THREAD_MODE.NONE:
	set(nv):
		if nv != VoxelConfiguration.THREAD_MODE.NONE:
			push_warning("Only THREAD_MODE.NONE is implemented.")


## Dictionary of key:value as Vector3i:Chunk
var chunks : Dictionary = {}
## Dictionary of key:value as Vector3i:Chunk
var loaded_chunks : Dictionary = {}
## Dictionary of key:value as Vector3i:Chunk
var active_chunks : Dictionary = {}


class HotspotData:
	var radius : float = 0


## Hotspots keep chunks active around them
## Format in key:value as Node3D:HotSpotData
var hotspots : Dictionary = Dictionary()


## How often should chunks be saved to disk automatically while chunkmanager is active
enum BACKUP_STRATEGY {
	NONE,			## Do not write automatically to disk
	AT_EXIT, 		## Save only to disk when ChunkManager receives _exit_tree, this is always active for all other strategies
	CONSTANT_RR,	## Constant saving of changed chunks to disk as soon as possible in round robin fashion one chunk per frame
	INTERVAL_RR, 	## Save periodically, defined by backup_interval_seconds in a round robin fashion one chunk at every interval
	INTERVAL, 		## Save all chunks periodically, defined by backup_interval_seconds, all chunks at same time
}

@export_group("Backup")
## How often should chunks be saved to disk automatically while chunkmanager is active
@export var backup_strategy : BACKUP_STRATEGY = BACKUP_STRATEGY.CONSTANT_RR
## Interval for Interval Rr and Interval strategies
@export var backup_interval_seconds = 60.0


func _ready():
	if database_folder == "":
		database_folder = "user://chunkdata"
	if database_uid == "":
		var rando = RandomNumberGenerator.new()
		rando.randomize()
		database_uid = str(str(rando.randi())+OS.get_unique_id()).sha256_text().left(10)
	if database_name == "":
		database_name = "UnNamed"
	if database_format == "":
		database_format = "tscn"
	rebuild_database_folder()


func rebuild_database_folder():
	var global_path = ProjectSettings.globalize_path(database_folder)
	var full_path = global_path+"/"+database_name+"-"+database_uid+"/"
	if not DirAccess.dir_exists_absolute(full_path):
		print("%s:Creating FOLDER %s at %s" % [self, database_folder, full_path])
		var error = DirAccess.make_dir_absolute(full_path)
		if error:
			push_error("%s: CANT CREATE FOLDER %s %s : %s" % [self, database_folder, full_path, error_string(error)])
	else:
		print("%s: Found chunkdata %s at %s" % [self, database_folder, full_path])


func _exit_tree():
	if backup_strategy >= BACKUP_STRATEGY.AT_EXIT:
		save_all_chunks_to_disk()


func save_all_chunks_to_disk():
	for loaded_chunk in loaded_chunks.values():
		if loaded_chunk.data_changed:
			loaded_chunk.save_to_disk(get_globalpath(loaded_chunk.position))


var frame = 0
func _process(delta):	
	if frame < 1:
		_round_robin_add_potential_chunks()
	#if frame < 2:
	#	_round_robin_keep_hotspots_active()
	elif frame < 3:
		_round_robin_calculate_distances(3) # 0.05 - 0.1 ms operation. can calculate several iterations per frame
	elif frame < 4:
		_round_robin_load_and_activate()
	elif frame < 5:
		_round_robin_deactivate_unload_and_contract()
	#elif frame < 6:
	#	_round_robin_save_chunks_to_disk()
		
	frame += 1
	if frame > 7:
		frame = 0


# Add empty unloaded chunks around hotspots to track their distance
var apc_iterator = 0
func _round_robin_add_potential_chunks(iterations : int = 1):
	if hotspots.is_empty(): return
	
	for it in range(iterations):
		apc_iterator += 1
		if apc_iterator >= hotspots.size():
			apc_iterator = 0
		
		var hotspot_node : Node3D = hotspots.keys()[apc_iterator]
		var hotspot = hotspots[hotspot_node]
		
		var half_offset = Vector3(hotspot.radius,hotspot.radius,hotspot.radius)*chunk_size/2.0
		
		# get array of iterations needed for one side of cube
		var side_iterables = range(ceili(hotspot.radius))
		
		for x in side_iterables:
			for y in side_iterables:
				for z in side_iterables:
					var probe_position = hotspot_node.global_position + Vector3(x*chunk_size,y*chunk_size,z*chunk_size)
					var found_chunk = get_chunk_at(probe_position)


# Ensure most important chunks are kept in active state
var kha_iterator = 0
func _round_robin_keep_hotspots_active():
	if hotspots.is_empty(): return
	
	kha_iterator += 1
	if kha_iterator >= hotspots.size():
		kha_iterator = 0
		
	var hotspot_node : Node3D = hotspots.keys()[kha_iterator]
	
	var found_chunk = get_chunk_at(hotspot_node.global_position)
	if not found_chunk:
		push_error("%s: Can't find chunk at hotspot %s" % [self, hotspot_node])
		return
	
	if not found_chunk.active:
		activate_chunk(found_chunk)


var cd_iterator = 0
func _round_robin_calculate_distances(iterations : int = 1):
	if chunks.is_empty(): return
	for it in range(min(iterations, chunks.size())):
		cd_iterator += 1
		if cd_iterator >= chunks.size():
			cd_iterator = 0
		
		if not hotspots.is_empty():
			var chunk : Chunk = chunks.values()[cd_iterator]
			_calculate_distance_to_closest_hotspot_for(chunk)


func _round_robin_load_and_activate():
	if chunks.is_empty(): return
	
	if loaded_chunks.size() < max_loaded:
		var closest_unloaded = null
		for candidate in chunks.values():
			if not closest_unloaded or candidate.dist_to_closest_hotspot > closest_unloaded.dist_to_closest_hotspot:
				if not candidate.loaded:
					closest_unloaded = candidate
		
		if closest_unloaded:
			load_chunk(closest_unloaded)
	
	if active_chunks.size() < max_active:
		var closest_loaded = null
		for candidate in chunks.values():
			if not closest_loaded or candidate.dist_to_closest_hotspot > closest_loaded.dist_to_closest_hotspot:
				if candidate.loaded and not candidate.active:
					closest_loaded = candidate
		
		if closest_loaded:
			activate_chunk(closest_loaded)


func _round_robin_deactivate_unload_and_contract():
	if chunks.is_empty(): return
	
	if chunks.size() > max_chunks:
		var furthest_away = null
		for candidate in chunks.values():
			if not furthest_away or candidate.dist_to_closest_hotspot > furthest_away.dist_to_closest_hotspot:
				if not candidate.loaded:
					furthest_away = candidate
		
		if furthest_away:
			delete_chunk(furthest_away)
	
	if loaded_chunks.size() > max_loaded:
		var furthest_away = null
		for candidate in loaded_chunks.values():
			if not furthest_away or candidate.dist_to_closest_hotspot > furthest_away.dist_to_closest_hotspot:
				if not candidate.active:
					furthest_away = candidate
		
		if furthest_away:
			unload_chunk(furthest_away)
	
	if active_chunks.size() > max_active:
		var furthest_away = null
		for candidate in active_chunks.values():
			if not furthest_away or candidate.dist_to_closest_hotspot > furthest_away.dist_to_closest_hotspot:
				if candidate.active:
					furthest_away = candidate
		
		if furthest_away:
			deactivate_chunk(furthest_away)


var sctd_iterator = 0
func _round_robin_save_chunks_to_disk():
	if backup_strategy <= BACKUP_STRATEGY.CONSTANT_RR: return
	if chunks.is_empty(): return
	
	sctd_iterator += 1
	if sctd_iterator >= chunks.size():
		sctd_iterator = 0
	
	var chunk : Chunk = chunks.values()[sctd_iterator]
	if chunk.data_changed:
		print("changed data found")
		chunk.save_to_disk(get_globalpath(chunk.position))


func add_hotspot(hotspot : Node3D):
	#print("ChunkManager: Adding hotspot")
	if hotspots.get(hotspot):
		push_warning("ChunkManager: Hotspot already exists")
		return
	hotspots[hotspot] = HotspotData.new()
	hotspot.connect("tree_exiting", _on_hotspot_deleted.bind(hotspot))
	
	emit_signal("hotspot_added", hotspot)
	_update_all_hotspots()


func remove_hotspot(hotspot : Node3D):
	#print("ChunkManager: Removing hotspot")
	var found_hotspot = hotspots.get(hotspot)
	if not found_hotspot:
		push_warning("ChunkManager: Hotspot not found")
		return
	hotspots.erase(hotspot)
	hotspot.disconnect("tree_exiting", _on_hotspot_deleted)
	
	emit_signal("hotspot_removed", hotspot)
	_update_all_hotspots()


func _update_all_hotspots():
	if hotspots.is_empty(): return
	
	# Allocate all hotspot radiuses from the max_active variable
	# Calculates a single side lenght of a cube so that the total volume of all hotspots equals max_active volume
	var radius_portion = pow(float(max_active) / float(hotspots.size()), 1.0/3.0)
	for hotspot in hotspots.values():
		hotspot.radius = radius_portion


## Get the chunk that contains the given point
func get_chunk_at(point : Vector3i, create_missing = true) -> Chunk:
	#print("ChunkManager: getting chunk at %s" % point)
	point -= Vector3i(chunk_size/2,chunk_size/2,chunk_size/2)
	var snapped_position = point.snapped(Vector3i(chunk_size,chunk_size,chunk_size))
	
	var found_chunk = chunks.get(snapped_position)
	if found_chunk:
		return found_chunk
	
	if not create_missing:
		return null
		
	var new_chunk = Chunk.new()
	new_chunk.name = Chunk.get_filename(chunk_size,snapped_position)
	new_chunk.position = snapped_position
	new_chunk.size = chunk_size
	chunks[new_chunk.position] = new_chunk
	_calculate_distance_to_closest_hotspot_for(new_chunk)
	emit_signal("chunk_initialized", new_chunk)
	return new_chunk


## Swap a placeholder chunk to real chunk data
func load_chunk(chunk : Chunk):
	if chunk.loaded:
		push_error("%s: Trying to load already loaded chunk %s" % [self, chunk])
		return
	
	if FileAccess.file_exists(get_globalpath(chunk.position)):
		var disk_chunk = Chunk.load_from_disk(get_globalpath(chunk.position))
		chunks[chunk.position] = disk_chunk
		chunk = disk_chunk
	else:
		emit_signal("new_chunk_created", chunk)
		
	loaded_chunks[chunk.position] = chunk
	chunk.loaded = true
	_calculate_distance_to_closest_hotspot_for(chunk)
	emit_signal("chunk_loaded", chunk)


func activate_chunk(chunk : Chunk):
	if chunk.active:
		push_error("%s: Trying to activate already active chunk %s" % [self, chunk])
		return
	
	if not chunk.loaded:
		load_chunk(chunk)
	
	active_chunks[chunk.position] = chunk
	chunk.active = true
	emit_signal("chunk_activated", chunk)


func deactivate_chunk(chunk : Chunk):
	if not chunk.active:
		push_error("%s: Trying to activate already active chunk %s" % [self, chunk])
		return
	
	active_chunks.erase(chunk.position)
	chunk.active = false
	emit_signal("chunk_deactivated", chunk)


func unload_chunk(chunk : Chunk):
	if not chunk.loaded:
		push_error("%s: Trying to unload already unloaded chunk %s" % [self, chunk])
		return
	
	#print("ChunkManager: unloading chunk %s" % chunk)
	if chunk.active:
		deactivate_chunk(chunk)
	
	loaded_chunks.erase(chunk.position)
	chunk.loaded = false
	emit_signal("chunk_unloaded", chunk)
	chunk.persistent_data.clear()
	chunk.transient_data.clear()


func delete_chunk(chunk : Chunk):
	if chunk.active:
		push_error("%s: Trying to remove active chunk %s\n Please deactivate first." % [self, chunk])
	if chunk.loaded:
		push_error("%s: Trying to remove loaded chunk %s\n Please unload first." % [self, chunk])
	
	emit_signal("chunk_deleted", chunk)
	chunks.erase(chunk.position)
	chunk.queue_free()


func _on_hotspot_deleted(hotspot):
	#print("ChunkManager: Received 'hotspot deleted' for %s" % hotspot)
	_update_all_hotspots()


## Gets the minimum axis length to closest hotspot and stores it to the chunk dist_to_closest_hotspot variable
func _calculate_distance_to_closest_hotspot_for(chunk):
	var first_iteration = true
	for hotspot in hotspots.keys():
		var dist_to_hotspot = Vector3( Vector3(chunk.position) - hotspot.global_position + Vector3(half_chunk) ).abs()
		var cubic_dist = max(dist_to_hotspot.x, dist_to_hotspot.y, dist_to_hotspot.z)
		if first_iteration or chunk.dist_to_closest_hotspot > cubic_dist:
			chunk.dist_to_closest_hotspot = cubic_dist
		first_iteration = false
	emit_signal("shortest_distance_updated",chunk)


func get_globalpath(pos : Vector3i) -> String:
	return "%s/%s-%s/%s.%s" % [database_folder, database_name, database_uid, Chunk.get_filename(chunk_size, pos), database_format]
