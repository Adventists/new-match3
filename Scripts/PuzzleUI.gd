extends Control

@onready var moves_label = $MainInfo/MovesLabel
@onready var score_label = $MainInfo/ScoreLabel
@onready var level_label = $MainInfo/LevelLabel
@onready var level_goal = $LevelGoal
@onready var description_label = $LevelGoal/Goal
@onready var level_complete_panel = $LevelCompletePanel
@onready var next_level_button = $LevelCompletePanel/VBoxContainer/NextLevelButton
@onready var quit_button = $LevelCompletePanel/VBoxContainer/QuitButton
@onready var score_label_complete = $LevelCompletePanel/VBoxContainer/ScoreLabel
@onready var stars_label = $LevelCompletePanel/VBoxContainer/StarsLabel
@onready var instruction_label = $ControlsPanel/VBoxContainer/ControlsText
@onready var main_info_panel = $MainInfoPanel
@onready var controls_panel = $ControlsPanel
@onready var key_mechanism_panel = $KeyMechanismPanel
@onready var key_mechanism_label = $KeyMechanismPanel/KeyMechanismText
@onready var moves_exhausted_panel = $MovesExhaustedPanel
@onready var restart_level_button = $MovesExhaustedPanel/VBoxContainer/RestartLevelButton
@onready var return_to_menu_button = $MovesExhaustedPanel/VBoxContainer/ReturnToMenuButton
@onready var restart_button2 = $RestartLevelButton
@onready var main_menu_button = $MainMenuButton

func _ready():
	# 连接按钮信号
	if next_level_button:
		next_level_button.pressed.connect(_on_next_level_button_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_button_pressed)
	if restart_level_button:
		restart_level_button.pressed.connect(_on_restart_level_button_pressed)
	if return_to_menu_button:
		return_to_menu_button.pressed.connect(_on_quit_button_pressed)
	if restart_button2:
		restart_button2.pressed.connect(_on_restart_level_button_pressed)
	if main_menu_button:
		main_menu_button.pressed.connect(_on_quit_button_pressed)
	
	# 隐藏关卡完成面板和步数耗尽面板
	if level_complete_panel:
		level_complete_panel.hide()
	if moves_exhausted_panel:
		moves_exhausted_panel.hide()
		
	# 应用美化样式
	apply_ui_styles()

func update_moves(moves: int):
	if moves_label:
		moves_label.text = "剩余步数: %d" % moves
	
	# 当步数耗尽时显示弹窗
	if moves <= 0:
		show_moves_exhausted()

func update_score(score: int):
	if score_label:
		score_label.text = "分数: %d" % score

func update_level(level: int):
	if level_label:
		level_label.text = "关卡: %d" % level
	
	# 更新关卡描述
	update_description(level)

# 更新关卡描述
func update_description(level: int):
	if description_label:
		var description = ""
		var file = FileAccess.open("res://Resources/puzzle_levels.json", FileAccess.READ)
		if file:
			var json = JSON.new()
			var error = json.parse(file.get_as_text())
			var data = json.get_data()
			if error == OK:
				for level_data in data["levels"]:
					if level_data["level"] == level:
						description = level_data["description"]
						# 同时更新操作说明
						update_instruction(level_data)
						# 更新关键机制
						update_key_mechanism(level_data)
						break
			file.close()
		
		description_label.text = description

# 更新关卡操作说明
func update_instruction(level_data: Dictionary):
	if instruction_label and level_data.has("instruction"):
		instruction_label.text = level_data["instruction"]

# 更新关键机制面板
func update_key_mechanism(level_data: Dictionary):
	if key_mechanism_label and level_data.has("key_mechanism"):
		key_mechanism_label.text = level_data["key_mechanism"]

func show_level_complete():
	if level_complete_panel:
		level_complete_panel.show()
		# 更新分数和星星显示
		if score_label_complete:
			score_label_complete.text = "得分：%d" % get_parent().get_node("Disk").score
		if stars_label:
			var stars = calculate_stars()
			stars_label.text = "星星：%d" % stars

# 显示步数耗尽面板
func show_moves_exhausted():
	if moves_exhausted_panel:
		moves_exhausted_panel.show()

func calculate_stars() -> int:
	var disk = get_parent().get_node("Disk")
	if disk.remaining_moves >= disk.level_data.moves * 0.8:
		return 3
	elif disk.remaining_moves >= disk.level_data.moves * 0.5:
		return 2
	else:
		return 1

func _on_next_level_button_pressed():
	var disk = get_parent().get_node("Disk")
	var next_level = disk.current_level + 1
	
	# 读取关卡数据以确定最大关卡数
	var file = FileAccess.open("res://Resources/puzzle_levels.json", FileAccess.READ)
	var max_level = 1
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		var data = json.get_data()
		if error == OK:
			max_level = data["levels"].size()
		file.close()
	
	# 如果还有下一关，加载下一关；否则返回主菜单
	if next_level <= max_level:
		# 更新Global中的关卡号
		var global = get_node("/root/Global")
		if global:
			global.set_current_puzzle_level(next_level)
			print("Setting next level to: ", next_level)
		# 重新加载场景以开始新关卡
		get_tree().reload_current_scene()
	else:
		# 所有关卡都完成，返回主菜单
		get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

func _on_quit_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

# 重新开始当前关卡
func _on_restart_level_button_pressed():
	get_tree().reload_current_scene()

# 应用UI样式
func apply_ui_styles():
	
	return
	# 主信息面板样式
	if main_info_panel:
		var style = StyleBoxFlat.new()
		#style.bg_color = Color(0.1, 0.1, 0.3, 0.7)  # 深蓝色半透明
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		style.corner_radius_bottom_left = 10
		style.corner_radius_bottom_right = 10
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		#style.border_color = Color(0.5, 0.5, 1.0, 0.8)  # 浅蓝色边框
		main_info_panel.add_theme_stylebox_override("panel", style)
	
	# 关卡目标样式
	if level_goal:
		var style = StyleBoxFlat.new()
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		style.corner_radius_bottom_left = 10
		style.corner_radius_bottom_right = 10
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		level_goal.add_theme_stylebox_override("panel", style)
	
	
	# 控制面板样式
	if controls_panel:
		var style = StyleBoxFlat.new()
		#style.bg_color = Color(0.1, 0.1, 0.3, 0.8)  # 深蓝色
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		controls_panel.add_theme_stylebox_override("panel", style)
	
	# 关卡完成面板样式
	if level_complete_panel:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.4, 0.9)  # 深紫色
		style.corner_radius_top_left = 15
		style.corner_radius_top_right = 15
		style.corner_radius_bottom_left = 15
		style.corner_radius_bottom_right = 15
		style.border_width_left = 3
		style.border_width_top = 3
		style.border_width_right = 3
		style.border_width_bottom = 3
		style.border_color = Color(0.8, 0.7, 1.0)  # 金色边框
		style.shadow_color = Color(0, 0, 0, 0.5)
		style.shadow_size = 10
		level_complete_panel.add_theme_stylebox_override("panel", style)
		
	# 调整标签颜色
	#if moves_label:
		#moves_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))  # 金黄色
	#if score_label:
		#score_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))  # 绿色
	#if level_label:
		#level_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5))  # 红色
	#if description_label:
		#description_label.add_theme_color_override("font_color", Color(1, 1, 1))  # 白色
	
