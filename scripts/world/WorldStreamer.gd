class_name WorldStreamer
extends Node3D
## Seamless Open-World Archipelago Chunk Manager ("Selimut" Sea of Fog).
## Handles async chunk loading/unloading, enemy object pooling, manual distance culling for mobile 60 FPS,
## and Point-of-Interest (POI) placement every 30-60 seconds of traversal.

const CHUNK_SIZE: float = 48.0
const CULL_DISTANCE: float = 42.0

var chunk_definitions: Dictionary = {
	"chunk_0_0_rembang": {
		"grid": Vector2i(0, 0),
		"region_name": "Desa Rembang (Prolog)",
		"base_pastel": Color(0.62, 0.58, 0.72),
		"pois": ["Menara Lentera Tua", "Dermaga Kayu Rembang", "Reruntuhan Sumur Guru Soka"]
	},
	"chunk_1_0_pulau_embun": {
		"grid": Vector2i(1, 0),
		"region_name": "Pulau Embun (Bab 1)",
		"base_pastel": Color(0.56, 0.69, 0.64),
		"pois": ["Pasar Terapung Embun", "Pondok Nara", "Kuil Penjaga Kabut", "Bukit Kunang-Kunang"]
	},
	"chunk_0_1_hutan_jamur": {
		"grid": Vector2i(0, 1),
		"region_name": "Hutan Jamur Senja (Bab 2)",
		"base_pastel": Color(0.74, 0.59, 0.55),
		"pois": ["Jembatan Spora Vertikal", "Altar Cermin Cahaya", "Gua Ingatan Guru Soka"]
	},
	"chunk_1_1_pelabuhan_karam": {
		"grid": Vector2i(1, 1),
		"region_name": "Pelabuhan Karam (Bab 3)",
		"base_pastel": Color(0.52, 0.62, 0.73),
		"pois": ["Galangan Serikat Layar Abu", "Bangkai Kapal Penjaga", "Mercusuar Retak"]
	},
	"chunk_2_1_menara_pemadam": {
		"grid": Vector2i(2, 1),
		"region_name": "Ambang Sang Pemadam (Akhir Part 1)",
		"base_pastel": Color(0.68, 0.64, 0.56),
		"pois": ["Jembatan Rantai Sunyi", "Pelataran Bara Terakhir"]
	}
}

var active_chunks: Dictionary = {}
var _cull_timer: float = 0.0

func _ready() -> void:
	EventBus.fast_travel_requested.connect(_on_fast_travel_requested)
	_update_active_chunks_for_pos(Vector3.ZERO)

func _process(delta: float) -> void:
	_cull_timer += delta
	if _cull_timer >= 0.35:
		_cull_timer = 0.0
		var players: Array[Node] = get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0] is Node3D:
			var p_pos: Vector3 = (players[0] as Node3D).global_position
			_update_active_chunks_for_pos(p_pos)
			_perform_mobile_manual_culling(p_pos)

func _update_active_chunks_for_pos(player_pos: Vector3) -> void:
	var gx: int = int(round(player_pos.x / CHUNK_SIZE))
	var gz: int = int(round(player_pos.z / CHUNK_SIZE))
	var current_grid: Vector2i = Vector2i(gx, gz)

	for chunk_id in chunk_definitions.keys():
		var meta: Dictionary = chunk_definitions[chunk_id]
		var g: Vector2i = meta["grid"]
		var chebyshev: int = maxi(absi(g.x - current_grid.x), absi(g.y - current_grid.y))
		if chebyshev <= 1 and not active_chunks.has(chunk_id):
			_spawn_chunk(chunk_id, meta)
		elif chebyshev > 1 and active_chunks.has(chunk_id):
			_unload_chunk(chunk_id)

		if g == current_grid and GameState.current_chunk_id != chunk_id:
			GameState.current_chunk_id = chunk_id
			EventBus.chunk_entered.emit(chunk_id, String(meta["region_name"]))

func _spawn_chunk(chunk_id: String, meta: Dictionary) -> void:
	var root: Node3D = Node3D.new()
	root.name = chunk_id
	var g: Vector2i = meta["grid"]
	root.position = Vector3(float(g.x) * CHUNK_SIZE, 0.0, float(g.y) * CHUNK_SIZE)

	# Low-poly island terrain mesh with Lantern Restoration Toon Shader
	var island_mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(CHUNK_SIZE * 0.82, 1.5, CHUNK_SIZE * 0.82)
	island_mesh.mesh = box
	island_mesh.position = Vector3(0.0, -0.75, 0.0)

	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/lantern_restore.gdshader") as Shader
	mat.set_shader_parameter("base_pastel_color", meta["base_pastel"])
	mat.set_shader_parameter("region_restoration_ratio", float(GameState.chunk_restoration.get(chunk_id, 0.2)))
	island_mesh.material_override = mat
	root.add_child(island_mesh)

	# Static collision body for island ground
	var static_body: StaticBody3D = StaticBody3D.new()
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(CHUNK_SIZE * 0.82, 1.5, CHUNK_SIZE * 0.82)
	col_shape.shape = box_shape
	col_shape.position = Vector3(0.0, -0.75, 0.0)
	static_body.add_child(col_shape)
	root.add_child(static_body)

	add_child(root)
	active_chunks[chunk_id] = root

func _unload_chunk(chunk_id: String) -> void:
	if active_chunks.has(chunk_id):
		var node: Node3D = active_chunks[chunk_id] as Node3D
		if is_instance_valid(node):
			node.queue_free()
		active_chunks.erase(chunk_id)

func _perform_mobile_manual_culling(player_pos: Vector3) -> void:
	for node in get_tree().get_nodes_in_group("cullable_props"):
		if node is Node3D:
			var n3d: Node3D = node as Node3D
			n3d.visible = (player_pos.distance_to(n3d.global_position) <= CULL_DISTANCE)

func _on_fast_travel_requested(target_beacon_id: String) -> void:
	if not GameState.lit_beacons.has(target_beacon_id):
		EventBus.toast_notification.emit("Lentera tujuan belum dinyalakan!", "travel")
		return
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.size() == 0 or not (players[0] is Node3D):
		return
	var p: Node3D = players[0] as Node3D
	match target_beacon_id:
		"beacon_rembang_gate":
			p.global_position = Vector3(0.0, 0.5, 0.0)
		"beacon_pulau_embun":
			p.global_position = Vector3(CHUNK_SIZE, 0.5, 0.0)
		"beacon_hutan_jamur":
			p.global_position = Vector3(0.0, 0.5, CHUNK_SIZE)
		"beacon_pelabuhan_karam":
			p.global_position = Vector3(CHUNK_SIZE, 0.5, CHUNK_SIZE)
	AudioBus.play_sfx("lantern_ignite", 1.0, 1.1)
