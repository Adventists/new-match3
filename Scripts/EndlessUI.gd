extends Control

@onready var moves_label = $MainInfo/MovesLabel
@onready var score_label = $MainInfo/ScoreLabel
@onready var level_label = $TopInfo/LevelLabel
@onready var progress_bar = $TopInfo/ProgressBar
@onready var frenzy_panel = $FrenzyPanel
@onready var frenzy_timer_label = $FrenzyPanel/TimerLabel
@onready var level_up_panel = $LevelUpPanel
@onready var game_over_panel = $GameOverPanel

func _ready():
	# 隐藏所有面板
	if frenzy_panel:
		frenzy_panel.hide()
	if level_up_panel:
		level_up_panel.hide()
	if game_over_panel:
		game_over_panel.hide()
		# 连接游戏结束面板的按钮信号
		var restart_button = game_over_panel.get_node("VBoxContainer/RestartButton")
		var quit_button = game_over_panel.get_node("VBoxContainer/QuitButton")
		if restart_button:
			restart_button.pressed.connect(_on_restart_button_pressed)
		if quit_button:
			quit_button.pressed.connect(_on_quit_button_pressed)

func update_moves(moves: int):
	if moves_label:
		moves_label.text = "剩余步数: %d" % moves

func update_score(score: int):
	if score_label:
		score_label.text = "分数: %d" % score

# 更新等级和进度条
func update_endless_level(level: int, current_score: int, next_threshold: int):
	if level_label:
		level_label.text = "等级: %d" % level
	if progress_bar:
		if next_threshold != -1:
			progress_bar.max_value = next_threshold
			progress_bar.value = current_score
		else:
			progress_bar.value = progress_bar.max_value

# 更新狂热状态
func update_frenzy_state(is_active: bool, time_left: float):
	if frenzy_panel:
		if is_active:
			frenzy_panel.show()
			update_frenzy_timer(time_left)
		else:
			frenzy_panel.hide()

# 更新狂热状态计时器
func update_frenzy_timer(time_left: float):
	if frenzy_timer_label:
		frenzy_timer_label.text = "狂热状态: %.1f秒" % time_left

# 显示升级提示
func show_level_up(level: int):
	if level_up_panel:
		level_up_panel.show()
		var label = level_up_panel.get_node("Label")
		if label:
			label.text = "升级！\n当前等级：%d" % level
		var tween = create_tween()
		tween.tween_interval(2.0)
		tween.tween_callback(func(): level_up_panel.hide())

# 显示游戏结束
func show_game_over():
	if game_over_panel:
		game_over_panel.show()
		var label = game_over_panel.get_node("VBoxContainer/Label")
		if label:
			label.text = "游戏结束！\n步数用完了！"

# 重新开始游戏
func _on_restart_button_pressed():
	get_tree().reload_current_scene()

# 返回主菜单
func _on_quit_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
