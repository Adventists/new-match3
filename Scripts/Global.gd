extends Node

# 当前解谜模式的关卡号
var current_puzzle_level: int = 1

# 获取当前关卡号
func get_current_puzzle_level() -> int:
	return current_puzzle_level

# 设置当前关卡号
func set_current_puzzle_level(level: int):
	current_puzzle_level = level

# 在初始化时自动注册为自动加载单例
func _ready():
	pass 