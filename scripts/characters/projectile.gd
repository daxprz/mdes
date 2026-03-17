extends Area2D

## A simple projectile that travels in a direction and deals damage on hit.
## Used for crossbow bolts, magic bolts, muffin grenades, etc.

@export var speed: float = 300.0
@export var damage: int = 10
@export var direction: Vector2 = Vector2.RIGHT
@export var lifetime: float = 3.0
@export var owner_index: int = -1

## "crossbow_bolt", "magic_bolt", "muffin_grenade"
var projectile_type: String = "crossbow_bolt"

var _age: float = 0.0

@onready var sprite: Sprite2D = $Sprite
@onready var collision_shape: CollisionShape2D = $CollisionShape


func _ready() -> void:
	add_to_group("loose_items")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	# Flip sprite if going left
	if direction.x < 0:
		sprite.flip_h = true


var _arc_vel := Vector2.ZERO
var _arc_gravity: float = 0.0
var _is_arc: bool = false


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	if _is_arc:
		# Physics-based parabolic arc
		_arc_vel.y += _arc_gravity * delta
		position += _arc_vel * delta
		rotation = _arc_vel.angle()
	else:
		position += direction * speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage, owner_index)

	if projectile_type == "muffin_grenade":
		_explode()
	else:
		queue_free()


func _on_area_entered(_area: Area2D) -> void:
	# Hitting a wall or obstacle
	if projectile_type == "muffin_grenade":
		_explode()
	else:
		queue_free()


func _explode() -> void:
	# Deal area damage to nearby enemies
	var explosion_radius := 48.0
	var bodies := get_tree().get_nodes_in_group("enemies")
	for body in bodies:
		if body is Node2D:
			var dist: float = global_position.distance_to(body.global_position)
			if dist <= explosion_radius and body.has_method("take_damage"):
				body.take_damage(damage, owner_index)
	queue_free()
