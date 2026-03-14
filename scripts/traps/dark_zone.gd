extends Area2D

## Dark zone that obscures the screen except near player positions.
## Uses a CanvasLayer with a dark overlay and additive light sprites.

@export var zone_width: float = 320.0
@export var zone_height: float = 240.0
@export var darkness_opacity: float = 0.85
@export var light_radius: float = 48.0

var _canvas_layer: CanvasLayer
var _dark_overlay: ColorRect
var _players_inside: Array[Node2D] = []
var _light_sprites: Dictionary = {}

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2

	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(zone_width, zone_height)
	col.shape = shape
	col.position = Vector2(zone_width / 2.0, zone_height / 2.0)
	add_child(col)

	# Create CanvasLayer for the darkness overlay
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 10
	_canvas_layer.visible = false
	add_child(_canvas_layer)

	# Create dark overlay covering the full viewport
	_dark_overlay = ColorRect.new()
	_dark_overlay.color = Color(0.0, 0.0, 0.0, darkness_opacity)
	_dark_overlay.anchors_preset = 15  # Full rect
	_dark_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas_layer.add_child(_dark_overlay)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	if _players_inside.is_empty():
		return

	# Update light sprite positions to follow players
	var camera: Camera2D = get_viewport().get_camera_2d()
	var viewport_size: Vector2 = get_viewport_rect().size

	for body: Node2D in _players_inside:
		if not is_instance_valid(body):
			continue
		var id: int = body.get_instance_id()
		if not _light_sprites.has(id):
			continue

		var light_node: Node2D = _light_sprites[id] as Node2D

		# Convert player world position to screen position
		if camera != null:
			var screen_pos: Vector2 = body.global_position - camera.global_position + viewport_size / 2.0
			light_node.position = screen_pos
		else:
			light_node.position = body.global_position


func _on_body_entered(body: Node2D) -> void:
	_players_inside.append(body)
	_canvas_layer.visible = true
	_add_light_for_player(body)


func _on_body_exited(body: Node2D) -> void:
	_remove_light_for_player(body)
	_players_inside.erase(body)
	if _players_inside.is_empty():
		_canvas_layer.visible = false


func _add_light_for_player(body: Node2D) -> void:
	var id: int = body.get_instance_id()
	if _light_sprites.has(id):
		return

	# Create a light circle sprite using _draw via a custom Node2D
	var light: Node2D = _LightCircle.new()
	light.set("radius", light_radius)
	# Use subtractive blend via modulate to punch through darkness
	# Actually: use a SubViewport approach or just draw a white circle with BLEND_SUB
	_dark_overlay.add_child(light)
	_light_sprites[id] = light


func _remove_light_for_player(body: Node2D) -> void:
	var id: int = body.get_instance_id()
	if not _light_sprites.has(id):
		return
	var light: Node2D = _light_sprites[id] as Node2D
	if is_instance_valid(light):
		light.queue_free()
	_light_sprites.erase(id)


## Inner class for the light circle that subtracts from the dark overlay.
class _LightCircle extends Node2D:
	var radius: float = 48.0

	func _ready() -> void:
		# Use blend subtract so the white circle cuts through the black overlay
		material = CanvasItemMaterial.new()
		(material as CanvasItemMaterial).blend_mode = CanvasItemMaterial.BLEND_MODE_SUB

	func _draw() -> void:
		# Draw a gradient circle: fully opaque in center, transparent at edges
		var steps: int = 12
		for i: int in range(steps, 0, -1):
			var t: float = float(i) / float(steps)
			var r: float = radius * t
			var alpha: float = 1.0 - t  # Brighter toward center
			alpha = alpha * alpha  # Quadratic falloff for smoother edge
			draw_circle(Vector2.ZERO, r, Color(1.0, 1.0, 1.0, alpha))

	func _process(_delta: float) -> void:
		queue_redraw()
