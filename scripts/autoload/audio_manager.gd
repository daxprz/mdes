extends Node

## Global audio manager. Call AudioManager.play("sound_name") from anywhere.

var _players: Dictionary = {}  # name -> AudioStreamPlayer
var _sounds: Dictionary = {}   # name -> AudioStream

const SOUND_DIR := "res://assets/sounds/"

const SOUND_FILES := {
	"sword_slash": "sword_slash.wav",
	"crossbow_shoot": "crossbow_shoot.wav",
	"magic_bolt": "magic_bolt.wav",
	"staff_bonk": "staff_bonk.wav",
	"dagger_stab": "dagger_stab.wav",
	"shield_charge": "shield_charge.wav",
	"explosion": "explosion.wav",
	"freeze": "freeze.wav",
	"summon": "summon.wav",
	"shadow_dash": "shadow_dash.wav",
	"muffin_collect": "muffin_collect.wav",
	"player_hurt": "player_hurt.wav",
	"player_die": "player_die.wav",
	"player_revive": "player_revive.wav",
	"enemy_hit": "enemy_hit.wav",
	"enemy_die": "enemy_die.wav",
	"boss_roar": "boss_roar.wav",
	"boss_defeat": "boss_defeat.wav",
	"jump": "jump.wav",
	"menu_select": "menu_select.wav",
	"menu_confirm": "menu_confirm.wav",
	"pause": "pause.wav",
}

# How many simultaneous instances of each sound
const MAX_POLYPHONY := 4


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for sname in SOUND_FILES:
		var path: String = SOUND_DIR + SOUND_FILES[sname]
		var stream := load(path) as AudioStream
		if stream:
			_sounds[sname] = stream


func play(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _sounds.has(sound_name):
		return

	# Find or create an available AudioStreamPlayer
	var player := _get_available_player(sound_name)
	if not player:
		return

	player.stream = _sounds[sound_name]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _get_available_player(sound_name: String) -> AudioStreamPlayer:
	# Pool of players per sound
	var key := sound_name
	if not _players.has(key):
		_players[key] = []

	# Find one that's not playing
	var pool: Array = _players[key]
	for p in pool:
		if p is AudioStreamPlayer and not p.playing:
			return p

	# Create new if under limit
	if pool.size() < MAX_POLYPHONY:
		var new_player := AudioStreamPlayer.new()
		add_child(new_player)
		pool.append(new_player)
		return new_player

	# All busy, steal the oldest
	return pool[0]
