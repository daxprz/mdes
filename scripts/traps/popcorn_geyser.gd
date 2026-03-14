extends Node2D

## Periodic popcorn geyser that launches players and enemies upward.

@export var damage: int = 5
@export var launch_velocity: float = -500.0
@export var eruption_interval: float = 4.0
@export var eruption_duration: float = 0.5
@export var warning_time: float = 0.5
@export var blast_width: float = 30.0
@export var blast_height: float = 80.0

enum State { IDLE, WARNING, ERUPTING, COOLDOWN }

var _state: int = State.IDLE
var _timer: float = 0.0
var _time: float = 0.0
var _cycle_timer: float = 0.0
var _blast_area: Area2D
var _hit_bodies: Array[int] = []

func _ready() -> void:
	_blast_area = Area2D.new()
	_blast_area.collision_layer = 0
	_blast_area.collision_mask = 2  # Players
	add_child(_blast_area)

	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(blast_width, blast_height)
	col.shape = shape
	col.position = Vector2(0.0, -blast_height / 2.0)
	_blast_area.add_child(col)

	# Start disabled
	_blast_area.monitoring = false

	_cycle_timer = eruption_interval
	_state = State.IDLE

	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_cycle_timer -= delta

	match _state:
		State.IDLE:
			if _cycle_timer <= warning_time:
				_state = State.WARNING
				queue_redraw()
		State.WARNING:
			if _cycle_timer <= 0.0:
				_state = State.ERUPTING
				_timer = eruption_duration
				_blast_area.monitoring = true
				_hit_bodies.clear()
				AudioManager.play("explosion")
				queue_redraw()
		State.ERUPTING:
			_timer -= delta
			# Launch bodies in the blast zone
			for body: Node2D in _blast_area.get_overlapping_bodies():
				var id: int = body.get_instance_id()
				if id in _hit_bodies:
					continue
				_hit_bodies.append(id)
				if body is CharacterBody2D:
					var char_body: CharacterBody2D = body as CharacterBody2D
					char_body.velocity.y = launch_velocity
				if body.has_method("take_damage"):
					body.take_damage(damage)

			if _timer <= 0.0:
				_state = State.COOLDOWN
				_blast_area.monitoring = false
				_cycle_timer = eruption_interval
				queue_redraw()
		State.COOLDOWN:
			_state = State.IDLE

	queue_redraw()


func _draw() -> void:
	var vent_color: Color = Color(0.3, 0.3, 0.35, 1.0)
	var vent_inner: Color = Color(0.15, 0.15, 0.2, 1.0)

	# Vent base
	draw_rect(Rect2(-blast_width / 2.0, -4.0, blast_width, 8.0), vent_color)
	draw_rect(Rect2(-blast_width / 4.0, -2.0, blast_width / 2.0, 4.0), vent_inner)

	# Warning puffs
	if _state == State.WARNING:
		var puff_alpha: float = 0.3 + sin(_time * 15.0) * 0.2
		for i: int in range(3):
			var px: float = randf_range(-6.0, 6.0)
			var py: float = -8.0 - float(i) * 5.0
			draw_circle(Vector2(px, py), 3.0, Color(1.0, 1.0, 0.8, puff_alpha))

	# Eruption: popcorn kernels spraying upward
	if _state == State.ERUPTING:
		var kernel_white: Color = Color(1.0, 1.0, 0.9, 0.9)
		var kernel_yellow: Color = Color(1.0, 0.9, 0.5, 0.85)
		var progress: float = 1.0 - (_timer / eruption_duration)

		for i: int in range(12):
			var seed_val: float = float(i) * 7.3 + _time * 80.0
			var kx: float = sin(seed_val * 0.3) * blast_width * 0.4
			var ky: float = -10.0 - fmod(seed_val * 0.5, blast_height * progress)
			var kr: float = 2.0 + sin(seed_val) * 1.0
			var kcolor: Color = kernel_white if i % 2 == 0 else kernel_yellow
			draw_circle(Vector2(kx, ky), kr, kcolor)
