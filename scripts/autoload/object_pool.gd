extends Node

## Object pool autoload — recycles short-lived nodes (VFX, projectiles, chains).
## Acquire a node instead of .new(), release instead of queue_free().
## Every pooled node MUST implement reset_pooled() to prevent stale state.

const MAX_PER_TYPE := 64

## Pool storage: { type_key: [inactive_nodes] }
var _pools: Dictionary = {}

## Stats for debug overlay
var _acquire_count: Dictionary = {}  ## { type_key: int }
var _release_count: Dictionary = {}
var _miss_count: Dictionary = {}     ## Acquires that created new (pool empty)


func acquire(type_key: String, factory: Callable) -> Node:
	## Get a node from the pool, or create one via factory if pool is empty.
	## The node is NOT automatically reset — caller must call reset_pooled().
	_acquire_count[type_key] = _acquire_count.get(type_key, 0) + 1

	if _pools.has(type_key) and not _pools[type_key].is_empty():
		var node: Node = _pools[type_key].pop_back()
		if is_instance_valid(node):
			node.visible = true
			node.set_physics_process(true)
			node.set_process(true)
			return node
		# Node was freed externally — fall through to create new

	# Pool empty — create new
	_miss_count[type_key] = _miss_count.get(type_key, 0) + 1
	return factory.call()


func release(type_key: String, node: Node) -> void:
	## Return a node to the pool instead of queue_free().
	## The node is hidden and disabled immediately.
	if not is_instance_valid(node):
		return
	_release_count[type_key] = _release_count.get(type_key, 0) + 1

	node.visible = false
	node.set_physics_process(false)
	node.set_process(false)

	# Reparent to pool to keep clean hierarchy
	if node.get_parent() != self:
		if node.get_parent():
			node.get_parent().remove_child(node)
		add_child(node)

	if not _pools.has(type_key):
		_pools[type_key] = []

	# Enforce cap
	if _pools[type_key].size() >= MAX_PER_TYPE:
		node.queue_free()
		return

	_pools[type_key].append(node)


func get_pool_stats() -> Dictionary:
	## For debug overlay: { type_key: { pool_size, acquires, releases, misses } }
	var stats: Dictionary = {}
	var all_keys: Dictionary = {}
	for k in _pools:
		all_keys[k] = true
	for k in _acquire_count:
		all_keys[k] = true
	for key in all_keys:
		stats[key] = {
			"pool_size": _pools[key].size() if _pools.has(key) else 0,
			"acquires": _acquire_count.get(key, 0),
			"releases": _release_count.get(key, 0),
			"misses": _miss_count.get(key, 0),
		}
	return stats


func clear_all() -> void:
	## Free all pooled nodes. Called on level transitions.
	for key in _pools:
		for node in _pools[key]:
			if is_instance_valid(node):
				node.queue_free()
	_pools.clear()
	_acquire_count.clear()
	_release_count.clear()
	_miss_count.clear()
