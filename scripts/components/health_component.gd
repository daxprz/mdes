class_name HealthComponent extends Node

## Health, damage, death, and revival. Decoupled from character specifics.
## Reads max_health from StatsComponent via context.

signal health_changed(current: float, max_val: float)
signal damage_taken(amount: int, source_index: int)
signal died()
signal revived()

var ctx: CharacterContext

var current_health: float = 100.0
var max_health: float = 100.0
var is_dead: bool = false

# Invincibility frames
var _iframes_timer: float = 0.0
var _iframes_duration: float = 0.5


func inject_context(c: CharacterContext) -> void:
	ctx = c
	max_health = ctx.stats.cfg("max_health", 100.0)
	current_health = max_health


func _physics_process(delta: float) -> void:
	if _iframes_timer > 0.0:
		_iframes_timer -= delta


func take_damage(amount: int, source_index: int = -1) -> void:
	if is_dead or _iframes_timer > 0.0:
		return
	var actual: int = amount  # Future: defense reduction via ctx.stats
	current_health = maxf(current_health - actual, 0.0)
	_iframes_timer = _iframes_duration
	damage_taken.emit(actual, source_index)
	health_changed.emit(current_health, max_health)
	DebugOverlay.log("character/health", ctx.body if ctx else null,
		"DAMAGE: %d (hp=%.0f/%.0f)", [actual, current_health, max_health])
	if current_health <= 0.0:
		_die()


func heal(amount: float) -> void:
	if is_dead:
		return
	var old: float = current_health
	current_health = minf(current_health + amount, max_health)
	if current_health != old:
		health_changed.emit(current_health, max_health)


func _die() -> void:
	is_dead = true
	died.emit()
	DebugOverlay.log("character/health", ctx.body if ctx else null, "DIED")


func revive(health_pct: float = 1.0) -> void:
	is_dead = false
	current_health = max_health * health_pct
	health_changed.emit(current_health, max_health)
	revived.emit()
	DebugOverlay.log("character/health", ctx.body if ctx else null,
		"REVIVED at %.0f%%", [health_pct * 100])
