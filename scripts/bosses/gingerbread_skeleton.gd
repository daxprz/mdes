extends BossBase

## Boss 1 - Gingerbread Skeleton
## Attacks: bone throw, ground slam, summon mini skeletons (phase 2+).

const BONE_SPEED := 250.0
const BONE_DAMAGE := 15
const SLAM_DAMAGE := 25
const SLAM_RADIUS := 80.0

var _mini_skeleton_scene: PackedScene = null


func _setup_boss() -> void:
	max_health = 500
	health = max_health
	_attack_cooldown = 2.2
	_attack_timer = 1.5  # Short delay before first attack

	# Sprite setup - 256x64 sheet, 4 frames at 64x64
	var texture := load("res://assets/sprites/bosses/gingerbread_skeleton.png")
	if texture:
		sprite.texture = texture
		sprite.hframes = 4
		sprite.frame = 0
		sprite.scale = Vector2(2.0, 2.0)

	# Collision
	var shape := RectangleShape2D.new()
	shape.size = Vector2(48, 56)
	collision_shape.shape = shape
	collision_shape.position = Vector2(0, -4)

	# Try to load mini skeleton enemy scene
	if ResourceLoader.exists("res://scenes/enemies/skeleton_basic.tscn"):
		_mini_skeleton_scene = load("res://scenes/enemies/skeleton_basic.tscn")

	add_to_group("bosses")


func _boss_process(_delta: float) -> void:
	# Simple walk toward nearest player
	var target := get_nearest_player()
	if target:
		face_target(target.global_position)
		var dir: float = signf(target.global_position.x - global_position.x)
		velocity.x = dir * move_speed

		# Animate walk
		var frame_time: int = Time.get_ticks_msec() / 200
		sprite.frame = frame_time % 4
	else:
		velocity.x = 0.0


func _choose_attack() -> void:
	var target := get_nearest_player()
	if not target:
		return

	var dist := global_position.distance_to(target.global_position)

	# Phase 2+: chance to summon skeletons
	if current_phase >= 2 and randf() < 0.3:
		_summon_mini_skeletons()
		return

	# Close range: ground slam
	if dist < SLAM_RADIUS + 20.0:
		_ground_slam()
	else:
		_bone_throw(target)


func _bone_throw(target: Node2D) -> void:
	var dir := (target.global_position - global_position).normalized()
	spawn_projectile(dir, BONE_SPEED, BONE_DAMAGE, Color(0.85, 0.75, 0.55))

	# Phase 3: throw two extra bones at slight angles
	if current_phase >= 3:
		spawn_projectile(dir.rotated(0.25), BONE_SPEED, BONE_DAMAGE, Color(0.85, 0.75, 0.55))
		spawn_projectile(dir.rotated(-0.25), BONE_SPEED, BONE_DAMAGE, Color(0.85, 0.75, 0.55))


func _ground_slam() -> void:
	# Visual: quick jump up then slam
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y - 30, 0.2)
	tween.tween_property(self, "position:y", position.y, 0.15)
	tween.tween_callback(_apply_slam_damage)


func _apply_slam_damage() -> void:
	var players := get_tree().get_nodes_in_group("players")
	for p in players:
		if not p is Node2D:
			continue
		if global_position.distance_to(p.global_position) <= SLAM_RADIUS:
			if p.has_method("take_damage"):
				p.take_damage(SLAM_DAMAGE)
			elif p.has_meta("player_index"):
				PlayerManager.damage_player(p.get_meta("player_index"), SLAM_DAMAGE)


func _summon_mini_skeletons() -> void:
	var count := 2 if current_phase == 2 else 3
	for i in range(count):
		var skeleton: Node2D
		if _mini_skeleton_scene:
			skeleton = _mini_skeleton_scene.instantiate()
		else:
			# Fallback: create a simple enemy placeholder
			skeleton = _create_placeholder_skeleton()

		var offset_x := (i - count / 2.0) * 60.0
		skeleton.global_position = global_position + Vector2(offset_x, -20)
		get_tree().current_scene.add_child(skeleton)


func _create_placeholder_skeleton() -> CharacterBody2D:
	var enemy := CharacterBody2D.new()
	enemy.add_to_group("enemies")

	var rect := ColorRect.new()
	rect.size = Vector2(16, 24)
	rect.position = Vector2(-8, -12)
	rect.color = Color(0.85, 0.75, 0.55, 0.8)
	enemy.add_child(rect)

	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(16, 24)
	shape.shape = box
	enemy.add_child(shape)

	return enemy
