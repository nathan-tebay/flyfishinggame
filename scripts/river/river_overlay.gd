extends Node2D
# Overlay drawn on top of all RiverRenderer TileMapLayer children.
# RiverRenderer adds this as a child with z_index=1 so it renders above tiles.

var renderer: RiverRenderer = null

func _draw() -> void:
	if renderer:
		renderer._draw_overlays_on(self)
