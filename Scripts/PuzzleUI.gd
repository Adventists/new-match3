extends CanvasLayer

@onready var moves_label = $MovesLabel
@onready var score_label = $ScoreLabel
@onready var level_label = $LevelLabel
@onready var level_complete_panel = $LevelCompletePanel
@onready var next_level_button = $LevelCompletePanel/VBoxContainer/NextLevelButton

func _ready():
	level_complete_panel.hide()
	next_level_button.pressed.connect(_on_next_level_pressed)

func update_moves(moves: int):
	if moves_label:
		moves_label.text = "剩余步数: " + str(moves)

func update_score(score: int):
	if score_label:
		score_label.text = "分数: " + str(score)

func update_level(level: int):
	if level_label:
		level_label.text = "第 " + str(level) + " 关"

func show_level_complete():
	if level_complete_panel:
		level_complete_panel.show()
		var label = $LevelCompletePanel/VBoxContainer/Label
		var button = $LevelCompletePanel/VBoxContainer/NextLevelButton
		if label:
			label.text = "通关啦！"
		if button:
			button.text = "下一关"

func _on_next_level_pressed():
	if level_complete_panel:
		level_complete_panel.hide()
	get_tree().reload_current_scene() 
