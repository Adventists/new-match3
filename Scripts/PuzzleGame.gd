extends Node2D

func _ready():
	# 设置为解谜模式
	$Disk.game_mode = $Disk.PUZZLE_MODE

func _on_next_level_pressed():
	# 重新加载当前场景以开始新关卡
	get_tree().reload_current_scene() 
