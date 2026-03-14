extends Area2D

## A collectible mini-muffin that sparkles and increments the player's count.

signal collected(player_index: int)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var _collected := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("sparkle"):
		sprite.play("sparkle")


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	# Check if the body is a player (has player_index property).
	if not body.has_meta("player_index") and not "player_index" in body:
		return

	_collected = true
	var player_index: int = body.get("player_index") if "player_index" in body else body.get_meta("player_index")

	# Add muffin via managers.
	GameManager.add_mini_muffins(player_index, 1)
	if PlayerManager.players.has(player_index):
		PlayerManager.players[player_index]["muffin_count"] += 1

	AudioManager.play("muffin_collect", -5.0)
	collected.emit(player_index)
	_play_collect_effect()


func _play_collect_effect() -> void:
	# Disable collision immediately so no double-collect.
	collision.set_deferred("disabled", true)

	# Scale-up + fade-out tween as collect animation.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.25)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(queue_free)
