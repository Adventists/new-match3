extends Node2D

func _ready():
	# 获取disk节点并设置为无限模式
	if has_node("disk"):
		$disk.game_mode = $disk.ENDLESS_MODE
	elif has_node("Disk"):
		$Disk.game_mode = $Disk.ENDLESS_MODE 