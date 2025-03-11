extends CanvasLayer

@onready var moves_label = $MovesLabel
@onready var score_label = $ScoreLabel
@onready var level_complete_panel = $LevelCompletePanel
@onready var next_level_button = $LevelCompletePanel/NextLevelButton

func _ready():
	level_complete_panel.hide()
	next_level_button.pressed.connect(_on_next_level_pressed)

func update_moves(moves: int):
	moves_label.text = "Moves: %d" % moves

func update_score(score: int):
	score_label.text = "Score: %d" % score

func show_level_complete():
	level_complete_panel.show()

func _on_next_level_pressed():
	level_complete_panel.hide()
	# 重新加载当前场景以开始新关卡
	get_tree().reload_current_scene() 
