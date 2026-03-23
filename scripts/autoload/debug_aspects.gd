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

	# -- State Info --
	r.call("state_info/state_text_panel", "State, HP, velocity, IK metrics text")
	r.call("state_info/selection_indicator", "TAB-selected entity pulsing ring")
	r.call("state_info/ik_metrics", "IK score, average, peak display")
	r.call("state_info/target_indicator", "Crosshair on hunted player")
	r.call("state_info/sleep_standdown", "ZZZ and STANDDOWN flags")

	# -- Chain --
	r.call("chain/tether_arc", "Chain reach barrier candy-stripe circle")
	r.call("chain/chain_barrier", "Chain constraint visualization during precog")

	# -- Splay Poses --
	r.call("splay_poses/pre_physics_pose", "Splay pose before physics solve")
	r.call("splay_poses/post_physics_pose", "Splay pose after physics solve")
	r.call("splay_poses/chain_points", "On-body chain attachment points")
	r.call("splay_poses/anchor_points", "On-wall anchor points")
