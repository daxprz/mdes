extends CharacterBody2D

## Attack Dummy — a test entity that actively attacks enemies.
## Placeable via RCON, configurable to target specific enemies and body parts.
## Fires weapons (bow, balloon) at a target on a cooldown.
## Does NOT take damage and is NOT in the "players" group (monster ignores it).

const GRAVITY := 600.0

# Weapon configs
const BOW_PROJECTILE_SPEED := 400.0
const BOW_DAMAGE := 15
const BOW_COOLDOWN := 1.5
const BALLOON_COOLDOWN := 2.0
const TETHER_COOLDOWN := 3.0

var _target: Node2D = null
var _target_part: String = ""  # "" = body center, "head", "eye", "tail", etc.
var _weapon: String = "bow"    # "bow" or "balloon" or "tether"
var _attack_rate: float = BOW_COOLDOWN
var _attack_timer: float = 0.0
var _attacking: bool = true
var _shots_fired: int = 0
var _hits_landed: int = 0

# Tether weapon config
var _tether_length: float = 100.0         # Target tether length
var _tether_target_b: String = "floor"    # "floor" or body part name for second anchor
var _tether_target_b_enemy: Node2D = null # Second anchor enemy (if not floor)
var _tether_target_b_part: String = ""    # Second anchor body part


func _ready() -> void:
	add_to_group("attack_dummies")
	collision_layer = 0   # Invisible to physics queries
	collision_mask = 1    # Stands on world

	# Collision shape so we stand on platforms
	var col := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 8.0
	shape.height = 30.0
	col.shape = shape
	add_child(col)


func _physics_process(delta: float) -> void:
	velocity.y += GRAVITY * delta
	move_and_slide()

	if not _attacking or not is_instance_valid(_target):
		queue_redraw()
		return

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = _attack_rate
		_fire()

	queue_redraw()


func set_target(enemy: Node2D) -> void:
	_target = enemy


func set_target_part(part_name: String) -> void:
	_target_part = part_name


func set_weapon(weapon_name: String) -> void:
	_weapon = weapon_name
	if weapon_name == "bow":
		_attack_rate = BOW_COOLDOWN
	elif weapon_name == "balloon":
		_attack_rate = BALLOON_COOLDOWN
	elif weapon_name == "tether":
		_attack_rate = TETHER_COOLDOWN


func set_tether_length(length: float) -> void:
	_tether_length = length


func set_tether_target_b(target_type: String, enemy: Node2D = null, part: String = "") -> void:
	_tether_target_b = target_type  # "floor" or "enemy"
	_tether_target_b_enemy = enemy
	_tether_target_b_part = part


func set_rate(seconds: float) -> void:
	_attack_rate = seconds


func get_aim_position() -> Vector2:
	## Returns the world position we're aiming at.
	if not is_instance_valid(_target):
		return global_position + Vector2(100, 0)

	# Try to aim at a specific body part hitbox
	if _target_part != "":
		# Check for hitbox Area2D nodes on the target
		var hitbox_name := "Hitbox_" + _target_part
		var hitbox: Node2D = _target.get_node_or_null(hitbox_name)
		if hitbox:
			return _target.global_position + hitbox.position

		# Check for skeleton positions directly
		if _target_part == "eye" and "_skull" in _target:
			# Eye is slightly offset from skull
			var skull: Vector2 = _target._skull
			var facing: float = _target._facing if "_facing" in _target else 1.0
			return _target.global_position + skull + Vector2(facing * 6.0, -3.0)
		if _target_part == "head" and "_skull" in _target:
			return _target.global_position + _target._skull
		if _target_part == "torso" and "_spine" in _target:
			return _target.global_position + _target._spine[1]
		if _target_part == "shoulders" and "_spine" in _target:
			return _target.global_position + _target._spine[0]
		if _target_part == "waist" and "_spine" in _target:
			return _target.global_position + _target._spine[2]
		if _target_part == "tail" and "_tail" in _target:
			return _target.global_position + _target._tail[2]
		if _target_part == "tail_tip" and "_tail" in _target:
			return _target.global_position + _target._tail[4]
		if _target_part.begins_with("leg") and "_legs" in _target:
			var idx: int = int(_target_part.replace("leg", ""))
			if idx >= 0 and idx < _target._legs.size():
				return _target.global_position + _target._legs[idx][1]  # Knee

	# Default: aim at target center
	return _target.global_position


func _fire() -> void:
	var aim_pos: Vector2 = get_aim_position()
	var direction: Vector2 = (aim_pos - global_position).normalized()

	match _weapon:
		"bow":
			_fire_bow(direction, aim_pos)
		"balloon":
			_fire_balloon(direction)
		"tether":
			_fire_tether(aim_pos)

	_shots_fired += 1


func _fire_bow(direction: Vector2, aim_pos: Vector2) -> void:
	## Fire an arrow projectile toward the aim position.
	## Uses a simple physics arc to hit the target.
	var arrow := Area2D.new()
	arrow.name = "AttackDummyArrow"
	arrow.add_to_group("loose_items")
	arrow.collision_layer = 2  # Player attack layer
	arrow.collision_mask = 0

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 4.0
	col.shape = shape
	arrow.add_child(col)

	arrow.global_position = global_position + Vector2(0, -10)

	# Calculate arc velocity to hit the target
	var start: Vector2 = arrow.global_position
	var dx: float = aim_pos.x - start.x
	var dy: float = aim_pos.y - start.y
	var t: float = absf(dx) / BOW_PROJECTILE_SPEED
	if t < 0.1:
		t = 0.3
	var vx: float = dx / t
	var vy: float = (dy - 0.5 * GRAVITY * t * t) / t

	var damage: int = BOW_DAMAGE
	var target_ref: Node2D = _target
	var target_part: String = _target_part
	var dummy_ref: Node2D = self

	# Inline script for the arrow
	var script := GDScript.new()
	script.source_code = """extends Area2D

var vel: Vector2
var gravity: float = 600.0
var damage: int = 15
var age: float = 0.0
var target_ref: Node2D = null
var target_part: String = ""
var dummy_ref: Node2D = null
var _hit := false

func _ready() -> void:
	body_entered.connect(_on_body)

func _physics_process(delta: float) -> void:
	age += delta
	if age > 4.0:
		queue_free()
		return
	vel.y += gravity * delta
	position += vel * delta
	rotation = vel.angle()

	# Check proximity to target hitboxes (Area2D detection)
	if not _hit and is_instance_valid(target_ref):
		var check_pos: Vector2 = global_position
		# Check against hitbox areas on target
		for child in target_ref.get_children():
			if child is Area2D and child.name.begins_with("Hitbox_"):
				var part_name: String = child.get_meta("part_name", "")
				var hitbox_world: Vector2 = target_ref.global_position + child.position
				var dist: float = check_pos.distance_to(hitbox_world)
				var hit_radius: float = 12.0
				# Specific part targeting: only count if we hit the right part
				if target_part != "" and part_name != target_part:
					# For eye targeting, check eye proximity on skull
					if target_part == "eye" and part_name == "head" and dist < 5.0:
						_on_hit_part(target_ref, "eye")
						return
					continue
				if dist < hit_radius:
					_on_hit_part(target_ref, part_name)
					return

func _on_body(body: Node2D) -> void:
	if body == target_ref:
		_on_hit_part(body, target_part if target_part != "" else "body")
	elif body.collision_layer & 1:
		# Hit world geometry
		queue_free()

func _on_hit_part(enemy: Node2D, part: String) -> void:
	if _hit:
		return
	_hit = true
	if enemy.has_method("take_part_damage"):
		enemy.take_part_damage(part, damage)
	elif enemy.has_method("take_damage"):
		enemy.take_damage(damage)
	if is_instance_valid(dummy_ref) and "_hits_landed" in dummy_ref:
		dummy_ref._hits_landed += 1
	queue_free()
"""
	script.reload()
	arrow.set_script(script)
	arrow.set("vel", Vector2(vx, vy))
	arrow.set("damage", damage)
	arrow.set("target_ref", target_ref)
	arrow.set("target_part", target_part)
	arrow.set("dummy_ref", dummy_ref)

	get_parent().add_child(arrow)


func _fire_balloon(direction: Vector2) -> void:
	## Fire a balloon dart toward the target.
	var dart_scene := load("res://scripts/characters/balloon_dart.gd")
	if not dart_scene:
		return

	var dart := Node2D.new()
	dart.set_script(dart_scene)
	dart.global_position = global_position + Vector2(0, -10)
	dart.dart_direction = direction
	dart.owner_index = -1  # Not a real player

	get_parent().add_child(dart)


func _fire_tether(aim_pos: Vector2) -> void:
	## Create a tether directly between the target attachment point and a second anchor.
	if not is_instance_valid(_target):
		return

	var TetherScript: GDScript = load("res://scripts/systems/tether.gd")
	if not TetherScript:
		return

	# Anchor A: target enemy, specific body part
	var ap_a: String = ""
	if _target_part != "" and "_attach_points" in _target and _target._attach_points.has(_target_part):
		ap_a = _target_part
	var anchor_a: Dictionary = TetherScript.make_anchor_body(_target, ap_a)

	# Anchor B: floor below target, or another enemy/part
	var anchor_b: Dictionary
	if _tether_target_b == "floor":
		var anchor_a_pos: Vector2 = TetherScript.get_anchor_world_pos(anchor_a)
		# Raycast to find floor below
		var floor_pos: Vector2 = Vector2(anchor_a_pos.x, anchor_a_pos.y + _tether_length + 200)
		var space := _target.get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(anchor_a_pos, floor_pos, 1)
		var result: Dictionary = space.intersect_ray(query)
		if result:
			floor_pos = result["position"]
		anchor_b = TetherScript.make_anchor_wall(floor_pos)
	elif _tether_target_b == "enemy" and is_instance_valid(_tether_target_b_enemy):
		var ap_b: String = ""
		if _tether_target_b_part != "" and "_attach_points" in _tether_target_b_enemy:
			if _tether_target_b_enemy._attach_points.has(_tether_target_b_part):
				ap_b = _tether_target_b_part
		anchor_b = TetherScript.make_anchor_body(_tether_target_b_enemy, ap_b)
	else:
		# Default: floor
		var pos_a: Vector2 = TetherScript.get_anchor_world_pos(anchor_a)
		anchor_b = TetherScript.make_anchor_wall(Vector2(pos_a.x, pos_a.y + _tether_length))

	var tether := Node2D.new()
	tether.set_script(TetherScript)
	tether.setup(anchor_a, anchor_b, _tether_length)
	get_parent().add_child(tether)
	_hits_landed += 1


func _draw() -> void:
	# Body: orange circle
	draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.6, 0.2, 0.8))
	# Head
	draw_circle(Vector2(0, -14), 7.0, Color(1.0, 0.6, 0.2, 0.8))

	# Weapon indicator
	var weapon_color: Color
	var weapon_label: String
	match _weapon:
		"bow":
			weapon_color = Color(0.8, 0.4, 0.2)
			weapon_label = "BOW"
		"balloon":
			weapon_color = Color(0.4, 0.8, 1.0)
			weapon_label = "BLN"
		"tether":
			weapon_color = Color(0.5, 0.4, 0.3)
			weapon_label = "TTH"
		_:
			weapon_color = Color.WHITE
			weapon_label = "?"

	# Draw weapon icon (small rectangle to the right)
	draw_rect(Rect2(8, -8, 12, 6), weapon_color)
	draw_string(ThemeDB.fallback_font, Vector2(-14, -26), weapon_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, weapon_color)

	# Status text
	var status_text: String = "ATK" if _attacking else "IDLE"
	if _target_part != "":
		status_text += " [%s]" % _target_part
	draw_string(ThemeDB.fallback_font, Vector2(-20, 24), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.8, 0.4))

	# Stats
	var stats_text: String = "%d/%d" % [_hits_landed, _shots_fired]
	draw_string(ThemeDB.fallback_font, Vector2(-20, 34), stats_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.7, 0.7))

	# Aim line (if attacking and has target)
	if _attacking and is_instance_valid(_target):
		var aim_pos: Vector2 = get_aim_position() - global_position
		draw_line(Vector2(0, -10), aim_pos, Color(1.0, 0.3, 0.3, 0.4), 1.0)
		draw_circle(aim_pos, 3.0, Color(1.0, 0.3, 0.3, 0.6))
