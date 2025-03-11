extends Node2D

func _ready():
	# 设置为解谜模式
	$Disk.game_mode = $Disk.PUZZLE_MODE 
