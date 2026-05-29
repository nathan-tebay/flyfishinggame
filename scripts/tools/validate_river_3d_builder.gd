extends SceneTree

const LowerMadisonReachScript = preload("res://scripts/river/lower_madison_reach.gd")
const River3DBuilderScript = preload("res://scripts/river/river_3d_builder.gd")


func _init() -> void:
	var builder := River3DBuilderScript.new()
	var reach := LowerMadisonReachScript.new()
	builder.force_headless_build = true
	root.add_child(builder)
	builder.build(reach, 12345)
	print("River3DBuilder validation built %d child nodes and %d fish hold entries." % [builder.get_child_count(), builder.fish_hold_entries.size()])
	builder.queue_free()
	quit()
