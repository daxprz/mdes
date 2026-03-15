extends Area2D

## A collectible mini-muffin that sparkles and increments the player's count.

signal collected(player_index: int)

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var _collected := false
var _anim_timer: float = 0.0
const ANIM_FPS := 6.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Randomize starting frame so not all muffins sparkle in sync
	if sprite:
		sprite.frame = randi() % 4


func _process(delta: float) -> void:
	if _collected:
		return
	# Animate sparkle: cycle through 4 frames
	_anim_timer += delta
	if _anim_timer >= 1.0 / ANIM_FPS:
		_anim_timer -= 1.0 / ANIM_FPS
		if sprite:
			sprite.frame = (sprite.frame + 1) % 4


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	if not body.has_meta("player_index") and not "player_index" in body:
		return

	_collected = true
	var player_index: int = body.get("player_index") if "player_index" in body else body.get_meta("player_index")

	GameManager.add_mini_muffins(player_index, 1)
	if PlayerManager.players.has(player_index):
		PlayerManager.players[player_index]["muffin_count"] += 1

	AudioManager.play("muffin_collect", -5.0)
	collected.emit(player_index)
	_play_collect_effect()


func _play_collect_effect() -> void:
	collision.set_deferred("disabled", true)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.25)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(queue_free)
