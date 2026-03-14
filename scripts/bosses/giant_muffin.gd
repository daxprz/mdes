extends BossBase

## Boss 4 - Giant Muffin (Final Boss)
## Attacks: muffin slam (shockwave), crumb burst (360), summon mini-muffins.
## At 25%: berserk mode with faster attacks and spawns previous boss minions.

const SLAM_DAMAGE := 35
const SLAM_RADIUS := 100.0
const CRUMB_SPEED := 220.0
const CRUMB_DAMAGE := 12
const CRUMB_COUNT := 12

var _berserk := false


func _setup_boss() -> void:
	max_health = 1200
	health = max_health
	_attack_cooldown = 2.5
	_attack_timer = 2.0
	move_speed = 50.0

	var texture := load("res://assets/sprites/bosses/giant_muffin.png")
	if texture:
		sprite.texture = texture
		sprite.hframes = 4
		sprite.frame = 0
		sprite.scale = Vector2(3.0, 3.0)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(72, 72)
	collision_shape.shape = shape

	add_to_group("bosses")


func _boss_process(_delta: float) -> void:
	var target := get_nearest_player()
	if target:
		face_target(target.global_position)
		var dir: float = signf(target.global_position.x - global_position.x)
		velocity.x = dir * move_speed

		var frame_time: int = Time.get_ticks_msec() / 300
		sprite.frame = frame_time % 4
	else:
		velocity.x = 0.0


func _choose_attack() -> void:
	var target := get_nearest_player()
	if not target:
		return

	var dist := global_position.distance_to(target.global_position)
	var roll := randf()

	if _berserk:
		# Berserk: cycle through attacks rapidly
		if roll < 0.3:
			_muffin_slam()
		elif roll < 0.6:
			_crumb_burst()
		elif roll < 0.8:
			_summon_mini_muffins()
		else:
			_summon_previous_boss_minions()
		return

	# Normal patterns
	if dist < SLAM_RADIUS + 20.0 and roll < 0.5:
		_muffin_slam()
	elif roll < 0.7:
		_crumb_burst()
	else:
		_summon_mini_muffins()


func _muffin_slam() -> void:
	# Jump high, slam down, create shockwave
	var start_y := position.y
	var tween := create_tween()
	tween.tween_property(self, "position:y", start_y - 80, 0.35).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", start_y, 0.2).set_ease(Tween.EASE_IN)
	tween.tween_callback(_apply_slam_shockwave)


func _apply_slam_shockwave() -> void:
	# Damage nearby players
	var players := get_tree().get_nodes_in_group("players")
	for p in players:
		if not p is Node2D:
			continue
		if global_position.distance_to(p.global_position) <= SLAM_RADIUS:
			if p.has_method("take_damage"):
				p.take_damage(SLAM_DAMAGE)
			elif p.has_meta("player_index"):
				PlayerManager.damage_player(p.get_meta("player_index"), SLAM_DAMAGE)

	# Shockwave visual: expanding ring
	_create_shockwave_visual()

	# Shockwave projectiles traveling outward along ground
	spawn_projectile(Vector2.LEFT, 150, 15, Color(0.8, 0.6, 0.3))
	spawn_projectile(Vector2.RIGHT, 150, 15, Color(0.8, 0.6, 0.3))


func _create_shockwave_visual() -> void:
	var ring := ColorRect.new()
	ring.size = Vector2(20, 20)
	ring.position = global_position - Vector2(10, 10)
	ring.color = Color(0.9, 0.7, 0.4, 0.7)
	get_tree().current_scene.add_child(ring)

	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "size", Vector2(SLAM_RADIUS * 2, 20), 0.3)
	tween.tween_property(ring, "position:x", global_position.x - SLAM_RADIUS, 0.3)
	tween.tween_property(ring, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(ring.queue_free)


func _crumb_burst() -> void:
	# 360 degree burst of crumb projectiles
	var count := CRUMB_COUNT if not _berserk else CRUMB_COUNT * 2
	for i in range(count):
		var angle := (TAU / count) * i
		var dir := Vector2.from_angle(angle)
		spawn_projectile(dir, CRUMB_SPEED, CRUMB_DAMAGE, Color(0.75, 0.55, 0.3))


func _summon_mini_muffins() -> void:
	var count := 2 if current_phase < 3 else 4
	for i in range(count):
		var muffin := _create_mini_muffin_enemy()
		var offset_x := (i - count / 2.0) * 50.0
		muffin.global_position = global_position + Vector2(offset_x, -30)
		get_tree().current_scene.add_child(muffin)


func _summon_previous_boss_minions() -> void:
	# Berserk mode: summon minions from previous bosses
	var scenes_to_try: Array[String] = [
		"res://scenes/enemies/skeleton_basic.tscn",
	]

	for scene_path in scenes_to_try:
		if ResourceLoader.exists(scene_path):
			var scene: PackedScene = load(scene_path)
			var enemy: Node2D = scene.instantiate()
			enemy.global_position = global_position + Vector2(randf_range(-80, 80), -20)
			get_tree().current_scene.add_child(enemy)

	# Also spawn a couple placeholder minions
	for i in range(2):
		var minion := _create_mini_muffin_enemy()
		minion.global_position = global_position + Vector2(randf_range(-100, 100), -20)
		get_tree().current_scene.add_child(minion)


func _create_mini_muffin_enemy() -> CharacterBody2D:
	var enemy := CharacterBody2D.new()
	enemy.collision_layer = 8  # Enemy layer - won't collide with boss (also layer 8)
	enemy.collision_mask = 1   # Only collide with world/floor
	enemy.add_to_group("enemies")

	var rect := ColorRect.new()
	rect.size = Vector2(18, 18)
	rect.position = Vector2(-9, -9)
	rect.color = Color(0.8, 0.6, 0.35)
	enemy.add_child(rect)

	# Muffin top
	var top := ColorRect.new()
	top.size = Vector2(22, 10)
	top.position = Vector2(-11, -19)
	top.color = Color(0.9, 0.7, 0.4)
	enemy.add_child(top)

	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(18, 18)
	shape.shape = box
	enemy.add_child(shape)

	return enemy


func _on_phase_change(phase: int) -> void:
	if phase == 2:
		_attack_cooldown = 2.0
		move_speed = 65.0
	elif phase == 3:
		_berserk = true
		_attack_cooldown = 1.2
		move_speed = 90.0
		# Visual: red tint for berserk
		_original_modulate = Color(1.2, 0.7, 0.7)
		modulate = _original_modulate
