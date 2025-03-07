extends Control

@onready var endless_mode_button = $ModeContainer/EndlessModeButton
@onready var puzzle_mode_button = $ModeContainer/PuzzleModeButton

func _ready():
	# 连接按钮信号
	endless_mode_button.pressed.connect(_on_endless_mode_pressed)
	puzzle_mode_button.pressed.connect(_on_puzzle_mode_pressed)

func _on_endless_mode_pressed():
	# 切换到无限模式场景
	get_tree().change_scene_to_file("res://Scenes/Game.tscn")

func _on_puzzle_mode_pressed():
	# 切换到解谜模式场景
	get_tree().change_scene_to_file("res://Scenes/PuzzleGame.tscn") 