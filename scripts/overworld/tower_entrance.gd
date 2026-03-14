extends Area2D

## Detects when players walk into a tower entrance and emits a signal.

signal player_entered_tower(tower_id: int, body: Node2D)
signal all_players_at_tower(tower_id: int)

@export var tower_id: int = 1

var _players_in_area: Dictionary = {}
var _triggered := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Make sure monitoring is on
	monitoring = true


func _physics_process(_delta: float) -> void:
	# Also check overlapping bodies every frame as backup
	if _triggered:
		return
	for body in get_overlapping_bodies():
		if _is_player(body) and not _players_in_area.has(_get_player_index(body)):
			_on_body_entered(body)


func _on_body_entered(body: Node2D) -> void:
	if _triggered:
		return
	if not _is_player(body):
		return
	var player_index: int = _get_player_index(body)
	_players_in_area[player_index] = body
	player_entered_tower.emit(tower_id, body)
	# Any player entering triggers the tower
	_triggered = true
	all_players_at_tower.emit(tower_id)


func _on_body_exited(body: Node2D) -> void:
	if not _is_player(body):
		return
	var player_index: int = _get_player_index(body)
	_players_in_area.erase(player_index)


func _is_player(body: Node2D) -> bool:
	return "player_index" in body or body.has_meta("player_index")


func _get_player_index(body: Node2D) -> int:
	if "player_index" in body:
		return body.get("player_index")
	return body.get_meta("player_index")
