extends Control

@onready var moves_label = $TopBar/MovesLabel
@onready var score_label = $TopBar/ScoreLabel

func _ready():
	# 确保标签有初始文本
	if moves_label:
		moves_label.text = "剩余步数: 10"
	if score_label:
		score_label.text = "分数: 0"

func update_moves(moves: int):
	if moves_label:
		moves_label.text = "剩余步数: %d" % moves

func update_score(score: int):
	if score_label:
		score_label.text = "分数: %d" % score 
