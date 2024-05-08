@tool
extends EditorPlugin

var current_mainscreen:String = "3D"

func _enter_tree():
	main_screen_changed.connect(store_active_main_screen)

	if get_editor_interface().get_edited_scene_root() is Node2D:
		current_mainscreen = "2D"

func _exit_tree():
	main_screen_changed.disconnect(store_active_main_screen)

func store_active_main_screen(m_name):
	#print("Changed to ", m_name)
	current_mainscreen = m_name


## Recenter focus

func _input(event):
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.alt_pressed:
				#print("Alt+middle")
				center_camera_at_mouse_point()
	if event is InputEventKey:
		if event.alt_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
			return
		if event.pressed and event.keycode == KEY_Q:
			#print("Q")
			center_camera_at_mouse_point()

func center_camera_at_mouse_point():
	if current_mainscreen == "3D":
		get_mouse_point_3D()
	elif current_mainscreen == "2D":
		get_mouse_point_2D()

## 2D world
func get_mouse_point_2D():
	var mouse_position := get_editor_interface().get_editor_viewport_2d().get_mouse_position()

	## Hacky way to change focus
	var editor_selection:EditorSelection = get_editor_interface().get_selection()
	var previous_selection := editor_selection.get_selected_nodes()

	editor_selection.clear()
	var new_node := Node2D.new()
	new_node.name = "placeholder"
	new_node.position = mouse_position
	get_tree().edited_scene_root.add_child(new_node)
	editor_selection.add_node(new_node)

	simulate_key(KEY_F)
	call_deferred("restore_selection", previous_selection, new_node)

## 3D world

func raycast_mouse_collision_3D(camera:Camera3D, ray_origin:Vector3, ray_end:Vector3) -> Dictionary:
	var world_3d := get_tree().root.get_world_3d()
	var space_state := world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var raycast = space_state.intersect_ray(query)
	#print(raycast)
	#if not raycast:
		#print("Can't find floor")
	#print(raycast)
	return raycast

func raycast_mouse_aabb(camera:Camera3D, ray_origin:Vector3, ray_end:Vector3) -> Dictionary:
	var bodies_hit = RenderingServer.instances_cull_ray(ray_origin, ray_end, get_tree().root.world_3d.scenario)

	if not bodies_hit: return {}

	var closest_dist = 1e20
	var closest_node
	var final_pos = null
	#print("cull_ray: ", bodies_hit)
	for m_body in bodies_hit:
		var node_mesh:VisualInstance3D = instance_from_id(m_body) as VisualInstance3D

		#print("Checking: ", m_body, " - ", node_mesh)
		if not node_mesh: continue

		var hit_position := node_mesh.get_aabb().intersects_segment(ray_origin, ray_end)
		#print(hit_position)

		if not hit_position: continue

		var dist := node_mesh.position.distance_to(ray_origin)
		if dist < closest_dist:
			#print("NEW_closest: ", dist, " - ", node_mesh)
			closest_dist = dist
			final_pos = hit_position

	#print("\nFOUND closest: ", final_pos)
	if final_pos == null:
		return {}
	return { "position" : final_pos}

func get_mouse_point_3D():
	var mouse_position := get_editor_interface().get_editor_viewport_3d().get_mouse_position()
	var camera := get_editor_interface().get_editor_viewport_3d().get_camera_3d()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_end := ray_origin + camera.project_ray_normal(mouse_position) * 1000

	var raycast := raycast_mouse_collision_3D(camera, ray_origin, ray_end)
	if not raycast:
		raycast = raycast_mouse_aabb(camera, ray_origin, ray_end)
		if not raycast or raycast == null:
			#print("No aabb ray-hit found")
			return

	## Hacky way to change focus
	var editor_selection:EditorSelection = get_editor_interface().get_selection()
	var previous_selection := editor_selection.get_selected_nodes()

	editor_selection.clear()
	var new_node := Node3D.new()
	new_node.name = "placeholder"
	new_node.position = raycast['position']
	get_tree().edited_scene_root.add_child(new_node)
	editor_selection.add_node(new_node)

	simulate_key(KEY_F)
	call_deferred("restore_selection", previous_selection, new_node)

## Hacky stuff - Thanks to dreadpon's SpatialGardener
## https://github.com/dreadpon/godot_spatial_gardener/blob/d8f4ec90ca44e5167fd2b410264cbf08fe2f0a73/addons/dreadpon.spatial_gardener/plugin.gd#L249-L270

func simulate_key(keycode:Key):
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)

func restore_selection(selected_nodes, old_node):
	var editor_selection:EditorSelection = get_editor_interface().get_selection()
	editor_selection.clear()
	for node in selected_nodes:
		editor_selection.add_node(node)

	old_node.queue_free()
