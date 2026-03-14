extends CharacterBody2D
class_name BossBase

## Base class for all bosses. Provides health, phases, hit flash, and death.

signal defeated
signal health_changed(current: int, maximum: int)
signal phase_changed(phase: int)

@export var max_health: int = 500
@export var gravity: float = 980.0
@export var move_speed: float = 80.0

var health: int
var current_phase: int = 1  # 1 = full, 2 = below 50%, 3 = below 25%
var is_dead := false
var facing_left := true

var _flash_timer := 0.0
var _attack_timer := 0.0
var _attack_cooldown := 2.0
var _original_modulate := Color.WHITE

const HEALTH_BAR_SCENE := preload("res://scenes/ui/health_bar.tscn")

@onready var sprite: Sprite2D = $Sprite
@onready var collision_shape: CollisionShape2D = $CollisionShape

var _health_bar: Node2D = null


func _ready() -> void:
	health = max_health
	_original_modulate = modulate
	_setup_boss()
	health_changed.emit(health, max_health)
	AudioManager.play("boss_roar")
	_health_bar = HEALTH_BAR_SCENE.instantiate()
	_health_bar.bar_width = 48.0
	_health_bar.bar_height = 4.0
	_health_bar.bar_offset = Vector2(0, -44)
	_health_bar.fill_color = Color(0.9, 0.1, 0.1)
	add_child(_health_bar)
	_health_bar.set_health(health, max_health)


## Override in subclasses to configure sprite, collision, and attacks.
func _setup_boss() -> void:
	pass


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Gravity
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0

	# Hit flash countdown
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			modulate = _original_modulate

	# Attack timer
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = _attack_cooldown
		_choose_attack()

	_boss_process(delta)
	move_and_slide()


## Override for custom per-frame logic.
func _boss_process(_delta: float) -> void:
	pass


## Override to select and execute attacks based on current_phase.
func _choose_attack() -> void:
	pass


# -- Health System -------------------------------------------------------------

func take_damage(amount: int, _source_index: int = -1) -> void:
	if is_dead:
		return

	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	if _health_bar:
		_health_bar.set_health(health, max_health)
	AudioManager.play("enemy_hit", -2.0, 0.7)
	_hit_flash()
	_check_phase()

	if health <= 0:
		_die()


func _hit_flash() -> void:
	modulate = Color.WHITE * 3.0  # Bright white flash
	_flash_timer = 0.12


func _check_phase() -> void:
	var health_pct: float = float(health) / float(max_health)
	var new_phase := 1
	if health_pct <= 0.25:
		new_phase = 3
	elif health_pct <= 0.50:
		new_phase = 2

	if new_phase != current_phase:
		current_phase = new_phase
		phase_changed.emit(current_phase)
		_on_phase_change(new_phase)


## Override for phase-transition behaviour.
func _on_phase_change(_phase: int) -> void:
	pass


# -- Death ---------------------------------------------------------------------

func _die() -> void:
	is_dead = true
	_play_death_animation()


func _play_death_animation() -> void:
	# Flash rapidly, scale down, then emit defeated
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_property(self, "modulate:a", 1.0, 0.1)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_property(self, "modulate:a", 1.0, 0.1)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.4).set_ease(Tween.EASE_IN)
	tween.tween_callback(_on_death_complete)


func _on_death_complete() -> void:
	AudioManager.play("boss_defeat")
	defeated.emit()
	queue_free()


# -- Helpers -------------------------------------------------------------------

func face_target(target_pos: Vector2) -> void:
	facing_left = target_pos.x < global_position.x
	sprite.flip_h = !facing_left  # Assumes sprite default faces left


func get_nearest_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("players")
	var nearest: Node2D = null
	var nearest_dist := INF
	for p in players:
		if not p is Node2D:
			continue
		if p.has_method("is_alive") and not p.is_alive():
			continue
		var dist: float = global_position.distance_to(p.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = p as Node2D
	return nearest


func spawn_projectile(target_dir: Vector2, speed: float, damage: int,
		color: Color = Color.WHITE, leave_puddle: bool = false) -> void:
	var proj_scene := preload("res://scenes/bosses/boss_projectile.tscn")
	var proj: Node2D = proj_scene.instantiate()
	proj.global_position = global_position
	proj.direction = target_dir.normalized()
	proj.speed = speed
	proj.damage = damage
	proj.color = color
	proj.leave_puddle = leave_puddle
	get_tree().current_scene.add_child(proj)
