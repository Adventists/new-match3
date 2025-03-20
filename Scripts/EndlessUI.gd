extends Control

@onready var moves_label = $MainInfo/MovesLabel
@onready var score_label = $MainInfo/ScoreLabel
@onready var level_label = $TopInfo/LevelLabel
@onready var target_label = $TopInfo/TargetLabel
@onready var progress_bar = $TopInfo/ProgressBar
@onready var game_over_panel = $GameOverPanel
@onready var level_complete_panel = $LevelCompletePanel
@onready var moves_exhausted_panel = $MovesExhaustedPanel
@onready var restart_level_button = $MovesExhaustedPanel/VBoxContainer/RestartLevelButton
@onready var return_to_menu_button = $MovesExhaustedPanel/VBoxContainer/ReturnToMenuButton


# 缓存关卡信息
var current_level = 1
var current_target = 0
var next_target = 0

func _ready():
	# 隐藏所有面板
	if game_over_panel:
		game_over_panel.hide()
		# 连接游戏结束面板的按钮信号
		var restart_button = game_over_panel.get_node("VBoxContainer/RestartButton")
		var quit_button = game_over_panel.get_node("VBoxContainer/QuitButton")
		if restart_button:
			restart_button.pressed.connect(_on_restart_button_pressed)
		if quit_button:
			quit_button.pressed.connect(_on_quit_button_pressed)
	
	if level_complete_panel:
		level_complete_panel.hide()
		# 连接关卡完成面板的按钮信号
		var next_button = level_complete_panel.get_node("VBoxContainer/NextButton")
		var buff_buttons = []
		for i in range(1, 4):
			buff_buttons.append(level_complete_panel.get_node("VBoxContainer/BuffContainer/Buff%dButton" % i))
		
		if next_button:
			next_button.pressed.connect(_on_next_button_pressed)
		for button in buff_buttons:
			if button:
				button.pressed.connect(func(): _on_buff_selected(button.get_meta("buff_id") if button.has_meta("buff_id") else 0))
	
	if restart_level_button:
		restart_level_button.pressed.connect(_on_restart_level_button_pressed)
	if return_to_menu_button:
		return_to_menu_button.pressed.connect(_on_quit_button_pressed)
	
	# 连接主菜单按钮
	var main_menu_button = $MainMenuButton
	if main_menu_button:
		main_menu_button.pressed.connect(_on_quit_button_pressed)

func update_moves(moves: int):
	if moves_label:
		moves_label.text = "剩余步数: %d" % moves
		
	# 当步数耗尽时显示弹窗
	if moves <= 0:
		show_moves_exhausted()

func update_score(score: int):
	if score_label:
		score_label.text = "分数: %d" % score
	
	# 更新进度条
	if progress_bar and current_target > 0:
		progress_bar.max_value = next_target
		progress_bar.value = min(score, next_target)

# 更新关卡信息
func update_level_info(level: int, target_score: int, next_level_target: int):
	current_level = level
	current_target = target_score
	next_target = next_level_target
	
	if level_label:
		level_label.text = "关卡: %d" % level
	
	if target_label:
		target_label.text = "目标: %d" % target_score
	
	if progress_bar:
		progress_bar.max_value = next_level_target
		progress_bar.value = 0

# 显示关卡完成面板
func show_level_complete(score: int, buffs: Array):
	if level_complete_panel:
		level_complete_panel.show()
		
		# 更新分数显示
		var score_label = level_complete_panel.get_node("VBoxContainer/ScoreLabel")
		if score_label:
			score_label.text = "得分: %d" % score
		
		# 更新BUFF选项
		var buff_container = level_complete_panel.get_node("VBoxContainer/BuffContainer")
		if buff_container:
			for i in range(min(3, buffs.size())):
				var buff_button = buff_container.get_node("Buff%dButton" % (i+1))
				if buff_button:
					buff_button.text = buffs[i].name
					buff_button.set_meta("buff_id", buffs[i].id)

# 显示游戏结束面板
func show_game_over(score: int):
	if game_over_panel:
		game_over_panel.show()
		var label = game_over_panel.get_node("VBoxContainer/Label")
		if label:
			label.text = "游戏结束！\n你的得分: %d" % score

# 按钮回调
func _on_next_button_pressed():
	level_complete_panel.hide()
	# 游戏逻辑会在用户选择buff后自动处理下一关

func _on_buff_selected(buff_id):
	level_complete_panel.hide()
	get_parent().get_node("Disk").apply_buff(buff_id)

# 重新开始游戏
func _on_restart_button_pressed():
	get_tree().reload_current_scene()

# 返回主菜单
func _on_quit_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

# 显示步数耗尽面板
func show_moves_exhausted():
	if moves_exhausted_panel:
		moves_exhausted_panel.show()

# 重新开始当前关卡
func _on_restart_level_button_pressed():
	get_tree().reload_current_scene()
