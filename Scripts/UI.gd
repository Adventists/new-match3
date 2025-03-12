extends CanvasLayer

@onready var moves_label = $MovesLabel
@onready var score_label = $ScoreLabel

func update_moves(moves: int):
	if moves_label:
		moves_label.text = "剩余步数: " + str(moves)

func update_score(score: int):
	if score_label:
		score_label.text = "分数: " + str(score)
