extends Node

## Registers all known debug aspects at startup.
## Add new aspects here as debug capabilities are added to the codebase.


func _ready() -> void:
	_register_all()


func _register_all() -> void:
	var r := DebugOverlay.register

	# -- Platform Detection --
	r.call("platform_detection/platform_indicators", "Platform location bars and labels")
	r.call("platform_detection/ball_drop_buckets", "Ball-drop simulation bucket positions")
	r.call("platform_detection/ball_drop_final_spots", "Ball-drop final landing dots")
	r.call("platform_detection/edge_adjustment", "Platform edge refinement indicators")

	# -- Leap Attack --
	r.call("leap_attack/spots_considered", "Arrival point dots on strike circle")
	r.call("leap_attack/rays_cast", "Arc clearance raycasts")
	r.call("leap_attack/lateral_clearance", "Lateral body-width clearance probes at each arc point")
	r.call("leap_attack/attack_zone", "Strike zone circle and range")
	r.call("leap_attack/arc_trajectories", "All planned arc paths (heavy)")
	r.call("leap_attack/chosen_arc", "Chosen launch arc (highlighted)")
	r.call("leap_attack/launch_point", "Launch position marker")

	# -- Pathing --
	r.call("pathing/waypoints", "Waypoint target marker and line")
	r.call("pathing/way_platform", "Current platform assignment")
	r.call("pathing/walk_run_path", "Walk/run path to waypoint")
	r.call("pathing/platform_leap_path", "Trajectory between platforms")
	r.call("pathing/leap_attack_choice", "Leap attack target selection")

	# -- Precog --
	r.call("precog/platform_list", "Detected platforms with bars and labels")
	r.call("precog/graph_edges", "All graph edges between platforms (heavy)")
	r.call("precog/current_path", "Chosen path through platform graph")
	r.call("precog/attach_points", "Chain/tether attachment point circles")
	r.call("precog/ball_landings", "Ball simulation landing dots")
	r.call("precog/status_text", "Precog phase/state text overlay")

	# -- Testing --
	r.call("testing/etz_daz_zones", "ETZ/DAZ zone circles and labels")
	r.call("testing/planned_leaps", "Planned hop arcs: launch/landing dots, center arc, bounding arcs")
	r.call("testing/bounded_leap_checks", "Bounded leap constraint shapes (A/B circles, START/END/DISALLOW) with results")
	r.call("testing/violations", "Leap constraint violations: pulsing red circles at breach points on failed arcs")

	# -- Body Mechanics --
	r.call("body_mechanics/collision_shapes", "Body collision sphere (belly)")
	r.call("body_mechanics/ik_plant_marks", "Foot plant/step indicators and ideal positions")
	r.call("body_mechanics/spine_debug", "Spine point positions and labels")
	r.call("body_mechanics/neck_skull", "Neck chain and skull position")
	r.call("body_mechanics/jaw", "Jaw point")
	r.call("body_mechanics/tail_segments", "Tail segment positions")
	r.call("body_mechanics/leg_debug", "Leg joints: hip, knee, foot with labels")
	r.call("body_mechanics/origin_marker", "Origin crosshair at (0,0)")
	r.call("body_mechanics/floor_line", "Floor raycast line and label")

	# -- Monster State Machine --
	r.call("monster/state", "State transition log (old → new)")
	r.call("monster/blend", "Movement blend: facing turns, speed ramps, landing recovery")
	r.call("monster/player_input", "Player controller input: direction, attacks, state")

	# -- Input Debug --
	r.call("input/mouse_clicks", "Log mouse click positions and targets")
	r.call("input/mouse_motion", "Log mouse motion during drag (verbose)")

	# -- Factions --
	r.call("factions/labels", "Faction label above each entity")

	# -- Attack Zones (visual area-of-effect indicators) --
	r.call("attack_zones/bite", "Bite attack hit zone (circle at skull)")
	r.call("attack_zones/swipe", "Swipe attack hit zone (circle at claw)")
	r.call("attack_zones/tail", "Tail whip hit zone (circles at tail tip)")
	r.call("attack_zones/lunge", "Lunge hit zone (circle at body center)")
	r.call("attack_zones/grab", "Grab damage zone (circle at grab center)")

	# -- State Info --
	r.call("state_info/state_text_panel", "State, HP, velocity, IK metrics text")
	r.call("state_info/selection_indicator", "TAB-selected entity pulsing ring")
	r.call("state_info/ik_metrics", "IK score, average, peak display")
	r.call("state_info/target_indicator", "Crosshair on hunted player")
	r.call("state_info/sleep_standdown", "ZZZ and STANDDOWN flags")

	# -- Chain --
	r.call("chain/tether_arc", "Chain reach barrier candy-stripe circle")
	r.call("chain/chain_barrier", "Chain constraint visualization during precog")
	r.call("chain/link_state", "Chain link positions, taut/slack state, tension (throttled log)")

	# -- Splay Poses --
	r.call("splay_poses/pre_physics_pose", "Splay pose before physics solve")
	r.call("splay_poses/post_physics_pose", "Splay pose after physics solve")
	r.call("splay_poses/chain_points", "On-body chain attachment points")
	r.call("splay_poses/anchor_points", "On-wall anchor points")

	# -- Scaling --
	r.call("scaling/active_scale", "Current creature_scale factor overlay")
	r.call("scaling/effective_radii", "Body radius circle, leap radius, hitbox extents")
	r.call("scaling/speed_info", "Effective speed vs base speed tiers")

	# -- Hitboxes --
	r.call("hitboxes/monster_parts", "Monster damageable part hitboxes (head, body, legs, tail, eye)")
	r.call("hitboxes/player_attack", "Player attack area when active")

	# -- Player --
	r.call("player/velocity_arrows", "Current velocity (green) and predicted jump (red) arrows")
	r.call("player/jump_tracers", "Lingering jump impulse snapshots: pre-vel, impulse, post-vel")
	r.call("player/archer_arcs", "Archer aim arc trajectory and debug trails")
	r.call("player/archer_triggers", "L2/R2 trigger state, aim mode, reticle position")
	r.call("player/archer_fire", "Arrow fire events: velocity, reticle, position")
	r.call("player/projectiles", "Projectile position, velocity, lifetime each frame")
	r.call("player/reticle_info", "Reticle position text overlay")
	r.call("player/button_state", "Controller/keyboard button state labels on HUD")

	# -- Executioner --
	r.call("executioner/throw", "Ball/shackle throw mode toggle, windup, and release")
	r.call("executioner/ball", "Spike ball hit, stick, wall drag, platform drag")
	r.call("executioner/chain_radius", "Chain reach radius circle around player")
	r.call("executioner/swing", "Swing slam: hold time, spin speed, damage, dust")
	r.call("executioner/cleave", "Charged cleave: charge time, damage, knockback")

	# -- Game Config --
	r.call("game/multiple_players_same_class", "Allow multiple players to pick the same class")

	# -- Entity Effects --
	r.call("effects/applied", "Effect applied to entity (name, duration, value)")
	r.call("effects/expired", "Effect expired on entity")
	r.call("effects/active", "Currently active effects overlay per entity")

	# -- Performance --
	r.call("perf/fps", "FPS counter and rolling graph overlay")

	# -- Music --
	r.call("music/status", "Music system state changes (play, stop, driver init)")
	r.call("music/layers", "Layer activation/deactivation and variant switches")
	r.call("music/beats", "Beat and timer tick events (verbose)")
	r.call("music/events", "Game event hooks triggering intensity changes")
	r.call("music/effects", "Audio bus effects: lpf, hpf, reverb, delay, distortion, pan")
	r.call("music/cps_ramp", "CPS ramp: start, progress, completion, cancel events")

	# -- Samples --
	r.call("music/samples", "Sample library: load, play, pool, cache, drum kit synthesis")

	# -- Strudel --
	r.call("strudel/trigger", "Note trigger events: note number, duration, value")
	r.call("music/batch", "MML batch compilation: compile, sequence_on, track lifecycle")
	r.call("strudel/scheduler", "Cyclist tick, query window, CPS changes")
	r.call("strudel/parse", "Mini-notation parse: AST, leaf locations, errors")
	r.call("strudel/pattern", "Pattern evaluation: hap count, first cycle dump")
