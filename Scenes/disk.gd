extends Node2D

enum {wait, move} #state 变量用于存储当前游戏的状态，可能用于控制玩家何时可以操作棋盘，例如：wait 状态：等待玩家输入或动画结束。move 状态：正在执行消除或填充动画时，不允许新的输入
enum {puzzle_mode, endless_mode} #游戏模式
enum {ring_mode, diameter_mode} # 选择模式

var state
var game_mode = endless_mode #默认无尽模式
var remaining_moves = 10 #剩余步数
var score = 0 #分数

@export var num_angles: int = 8  # 角度切分数量，例如 8 份
@export var num_radii: int = 5   # 圆盘的层数（半径方向），改为5圈
var center = Vector2(400, 400)   # 圆盘起始位置。圆盘的中心点（假设窗口大小 800x800）

@export var empty_spaces: PackedVector2Array  # 网格中空白不可放置元素的位置  (angle_index, radius_index)

@onready var possible_dots = [
	preload("res://Scenes/Dots/blue_dot.tscn"),
	preload("res://Scenes/Dots/green_dot.tscn"),
	preload("res://Scenes/Dots/pink_dot.tscn"),
	preload("res://Scenes/Dots/red_dot.tscn"),
	preload("res://Scenes/Dots/yellow_dot.tscn"),
] #是一个数组，存储了游戏中可用的点块（棋子）。这些棋子会被实例化并放置在网格上。

@export var spacing: float = 10.0     # 控制圈与圈之间的间距
@export var base_radius: float = 100.0 # 最内圈的半径

#三个 Timer 计时器用于控制三消的不同阶段：destroy_timer：消除匹配的棋子时启动。collapse_timer：棋子掉落动画时启动。refill_timer：填充新棋子时启动。
var destroy_timer = Timer.new()
var collapse_timer = Timer.new()
var refill_timer = Timer.new()

#存储所有棋子的数组
var all_dots = []
#交换操作的临时存储
var dot_one = null
var dot_two = null

#记录上一次操作
var last_place = Vector2(0,0)
var last_direction = Vector2(0,0)
var move_checked = false

#触摸控制，记录手势输入（适用于移动设备）
var first_touch = Vector2(0,0)
var final_touch = Vector2(0,0)
var controlling = false

# 旋转相关变量
var current_rotation = 0.0  # 当前旋转角度
var target_rotation = 0.0   # 目标旋转角度
var rotation_speed = 15.0   # 增加旋转速度
var is_rotating = false     # 是否正在旋转

# 环选择相关变量
var selected_ring = -1  # 当前选中的环（-1表示未选中）
var ring_highlights = []  # 存储环的高亮节点
var ring_rotations = []  # 存储每个环的独立旋转角度

# 直径选择相关变量
var current_mode = ring_mode  # 当前选择模式
var selected_diameter = -1  # 当前选中的直径（-1表示未选中）

@onready var ui = get_node("/root/Game/UI")

func _ready():
	state = move
	setup_timers()
	randomize()
	# 获取视口大小并设置中心点
	var viewport_size = get_viewport_rect().size
	center = viewport_size / 2
	# 初始化每个环的旋转角度
	ring_rotations.resize(num_radii)
	for i in range(num_radii):
		ring_rotations[i] = 0.0
	all_dots = make_polar_array()
	spawn_dots()
	create_ring_highlights()  # 创建环的高亮
	# 等待一帧确保UI已经准备好
	await get_tree().process_frame
	update_ui()

func _process(delta):
	if is_rotating:
		# 计算旋转插值
		var rotation_diff = target_rotation - current_rotation
		if abs(rotation_diff) > 0.05:  # 减小阈值，使动画更平滑
			# 使用线性插值，但确保方向正确
			var step = rotation_diff * delta * rotation_speed
			current_rotation += step
			# 更新选中环的旋转角度
			if selected_ring != -1:
				ring_rotations[selected_ring] = current_rotation
			update_all_dots_positions()
		else:
			# 确保最终角度是精确的45度倍数
			var angle_step = 2 * PI / num_angles
			current_rotation = round(target_rotation / angle_step) * angle_step
			if selected_ring != -1:
				ring_rotations[selected_ring] = current_rotation
			is_rotating = false
			state = move  # 旋转结束后恢复移动状态

func _input(event):
	if event is InputEventKey:
		if event.pressed:
			if event.keycode == KEY_TAB:  # 使用Tab键切换模式
				toggle_selection_mode()
			elif event.keycode == KEY_LEFT:
				if current_mode == ring_mode:
					rotate_counter_clockwise()
				else:
					move_diameter_counter_clockwise()
			elif event.keycode == KEY_RIGHT:
				if current_mode == ring_mode:
					rotate_clockwise()
				else:
					move_diameter_clockwise()
			elif event.keycode == KEY_UP:
				if current_mode == ring_mode:
					select_previous_ring()
				else:
					select_previous_diameter()
			elif event.keycode == KEY_DOWN:
				if current_mode == ring_mode:
					select_next_ring()
				else:
					select_next_diameter()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				first_touch = event.position
				controlling = true
				# 检查是否点击了某个环
				var clicked_ring = get_ring_at_position(event.position)
				if clicked_ring != -1:
					select_ring(clicked_ring)
			elif controlling:
				final_touch = event.position
				controlling = false
				handle_rotation_gesture()

func handle_rotation_gesture():
	var gesture = final_touch - first_touch
	var center_to_first = first_touch - center
	var center_to_final = final_touch - center
	
	# 计算旋转方向
	var angle1 = atan2(center_to_first.y, center_to_first.x)
	var angle2 = atan2(center_to_final.y, center_to_final.x)
	var rotation_direction = angle2 - angle1
	
	# 处理角度跨越360度的情况
	if rotation_direction > PI:
		rotation_direction -= 2 * PI
	elif rotation_direction < -PI:
		rotation_direction += 2 * PI
	
	# 根据旋转方向决定是顺时针还是逆时针旋转
	if rotation_direction > 0:
		rotate_clockwise()
	else:
		rotate_counter_clockwise()

func rotate_clockwise():
	if state != move or is_rotating or selected_ring == -1:
		return
		
	state = wait
	is_rotating = true
	var angle_step = 2 * PI / num_angles
	target_rotation = current_rotation + angle_step
	remaining_moves -= 1
	update_ui()

func rotate_counter_clockwise():
	if state != move or is_rotating or selected_ring == -1:
		return
		
	state = wait
	is_rotating = true
	var angle_step = 2 * PI / num_angles
	target_rotation = current_rotation - angle_step
	remaining_moves -= 1
	update_ui()

func update_all_dots_positions():
	for angle_index in num_angles:
		for radius_index in num_radii:
			if all_dots[angle_index][radius_index] != null:
				var dot = all_dots[angle_index][radius_index]
				# 计算点的位置，考虑每个环的独立旋转
				var angle_step = 2 * PI / num_angles
				var angle = angle_index * angle_step + ring_rotations[radius_index]
				var radius = base_radius + (radius_index * spacing)
				var x = cos(angle) * radius
				var y = sin(angle) * radius
				dot.position = Vector2(x, y) + center
				# 更新高亮位置
				if radius_index == selected_ring:
					ring_highlights[radius_index].rotation = ring_rotations[radius_index]

func setup_timers():
	destroy_timer.connect("timeout", Callable(self, "destroy_matches"))
	destroy_timer.set_one_shot(true)
	destroy_timer.set_wait_time(0.2)
	add_child(destroy_timer)
	
	collapse_timer.connect("timeout", Callable(self, "collapse_columns"))
	collapse_timer.set_one_shot(true)
	collapse_timer.set_wait_time(0.2)
	add_child(collapse_timer)

	refill_timer.connect("timeout", Callable(self, "refill_columns"))
	refill_timer.set_one_shot(true)
	refill_timer.set_wait_time(0.2)
	add_child(refill_timer)

#生成棋子
func make_polar_array():
	var array = []
	for angle_index in num_angles:  # 遍历所有角度
		array.append([])
		for radius_index in num_radii:  # 遍历所有半径
			array[angle_index].append(null)  # 初始化为空
	return array


#生成棋子
func spawn_dots():
	for angle_index in num_angles:  # 遍历所有角度
		for radius_index in num_radii:  # 遍历所有半径
			if !restricted_fill(Vector2(angle_index, radius_index)):  # 这里用极坐标
				var rand = floor(randf_range(0, possible_dots.size()))
				var dot = possible_dots[rand].instantiate()
				var loops = 0

				# 防止初始生成就有匹配
				while (match_at(angle_index, radius_index, dot.color) && loops < 100):
					rand = floor(randf_range(0, possible_dots.size()))
					loops += 1
					dot = possible_dots[rand].instantiate()

				add_child(dot)
				# 初始化时设置正确的位置，不应用旋转
				dot.position = grid_to_pixel(angle_index, radius_index, false)
				all_dots[angle_index][radius_index] = dot


func restricted_fill(place):
	if is_in_array(empty_spaces, place):
		return true
	return false
	
func is_in_array(array, item):
	for i in array.size():
		if array[i] == item:
			return true
	return false

func match_at(angle_index, radius_index, color):
	# 角度方向匹配（检查左右相邻的角度）
	if angle_index > 1:
		if all_dots[angle_index - 1][radius_index] != null && all_dots[angle_index - 2][radius_index] != null:
			if all_dots[angle_index - 1][radius_index].color == color && all_dots[angle_index - 2][radius_index].color == color:
				return true

	# 半径方向匹配（检查内圈和外圈）
	if radius_index > 1:
		if all_dots[angle_index][radius_index - 1] != null && all_dots[angle_index][radius_index - 2] != null:
			if all_dots[angle_index][radius_index - 1].color == color && all_dots[angle_index][radius_index - 2].color == color:
				return true

	return false


func grid_to_pixel(angle_index, radius_index, apply_rotation: bool = true):
	var angle_step = 2 * PI / num_angles  # 每个角度片段的弧度
	var angle = angle_index * angle_step
	var radius = base_radius + (radius_index * spacing)  # 基础半径加上间距

	var x = cos(angle) * radius
	var y = sin(angle) * radius
	return Vector2(x, y) + center

func update_ui():
	if ui and ui.is_inside_tree():
		ui.update_moves(remaining_moves)
		ui.update_score(score)

func create_ring_highlights():
	# 为每个环创建高亮节点
	for ring in range(num_radii):
		var highlight = Node2D.new()
		highlight.position = center
		highlight.z_index = -1
		add_child(highlight)
		ring_highlights.append(highlight)
		
		var circle = Polygon2D.new()
		highlight.add_child(circle)
		circle.color = Color(1, 1, 0, 0.2)
		
		var points = PackedVector2Array()
		var inner_radius = base_radius + (ring * spacing) -35
		var outer_radius = base_radius + ((ring + 1) * spacing) -40
		
		for i in range(360):
			var angle = deg_to_rad(i)
			points.push_back(Vector2(
				cos(angle) * inner_radius,
				sin(angle) * inner_radius
			))
		for i in range(360, -1, -1):
			var angle = deg_to_rad(i)
			points.push_back(Vector2(
				cos(angle) * outer_radius,
				sin(angle) * outer_radius
			))
		
		circle.polygon = points
		highlight.visible = false
	
	# 为每个直径创建高亮节点
	for diameter in range(num_angles / 2):
		var highlight = Node2D.new()
		highlight.position = center
		highlight.z_index = -1
		add_child(highlight)
		ring_highlights.append(highlight)  # 使用同一个数组存储
		
		var line = Line2D.new()
		highlight.add_child(line)
		line.default_color = Color(1, 1, 0, 0.2)
		line.width = 20  # 增加线宽
		
		var angle = diameter * (2 * PI / num_angles)
		var start_point = Vector2(
			cos(angle) * (base_radius - 50),  # 延长起点
			sin(angle) * (base_radius - 50)
		)
		var end_point = Vector2(
			cos(angle) * (base_radius + (num_radii - 1) * spacing + 50),  # 延长终点
			sin(angle) * (base_radius + (num_radii - 1) * spacing + 50)
		)
		
		line.add_point(start_point)
		line.add_point(end_point)
		highlight.visible = false

func get_ring_at_position(pos: Vector2) -> int:
	var local_pos = pos - center
	var distance = local_pos.length()
	
	# 检查是否在圆盘范围内
	if distance < base_radius or distance > base_radius + (num_radii * spacing):
		return -1
	
	# 计算点击位置对应的环
	var ring = floor((distance - base_radius) / spacing)
	return clamp(ring, 0, num_radii - 1)

func select_ring(ring: int):
	if ring == selected_ring:
		return
	
	# 取消之前的高亮
	if selected_ring != -1:
		ring_highlights[selected_ring].visible = false
	
	# 设置新的高亮
	selected_ring = ring
	ring_highlights[selected_ring].visible = true

func select_previous_ring():
	if selected_ring <= 0:
		select_ring(num_radii - 1)
	else:
		select_ring(selected_ring - 1)

func select_next_ring():
	if selected_ring >= num_radii - 1:
		select_ring(0)
	else:
		select_ring(selected_ring + 1)

func toggle_selection_mode():
	current_mode = diameter_mode if current_mode == ring_mode else ring_mode
	# 重置选择状态
	if current_mode == ring_mode:
		selected_diameter = -1
		update_diameter_highlights()
	else:
		selected_ring = -1
		update_ring_highlights()
		select_diameter(0)  # 默认选择第一条直径

func select_diameter(diameter_index: int):
	if diameter_index == selected_diameter:
		return
	
	selected_diameter = diameter_index
	update_diameter_highlights()
	remaining_moves -= 1
	update_ui()

func select_previous_diameter():
	if selected_diameter <= 0:
		select_diameter(num_angles / 2 - 1)
	else:
		select_diameter(selected_diameter - 1)

func select_next_diameter():
	if selected_diameter >= num_angles / 2 - 1:
		select_diameter(0)
	else:
		select_diameter(selected_diameter + 1)

func move_diameter_clockwise():
	if state != move or selected_diameter == -1:
		return
		
	state = wait
	# 保存直径上的所有点
	var dots_to_move = []
	for radius_index in range(num_radii):
		var angle_index = (selected_diameter + radius_index * (num_angles / 2)) % num_angles
		if all_dots[angle_index][radius_index] != null:
			dots_to_move.append(all_dots[angle_index][radius_index])
	
	# 移动点
	if dots_to_move.size() > 0:
		var last_dot = dots_to_move.back()
		for i in range(dots_to_move.size() - 1, 0, -1):
			var current_angle = get_dot_angle(dots_to_move[i])
			var next_angle = get_dot_angle(dots_to_move[i-1])
			all_dots[current_angle][get_dot_radius(dots_to_move[i])] = dots_to_move[i-1]
			all_dots[next_angle][get_dot_radius(dots_to_move[i-1])] = dots_to_move[i]
		
		# 移动最后一个点
		var first_angle = get_dot_angle(dots_to_move[0])
		var last_angle = get_dot_angle(last_dot)
		all_dots[first_angle][get_dot_radius(dots_to_move[0])] = last_dot
		all_dots[last_angle][get_dot_radius(last_dot)] = dots_to_move[0]
		
		update_all_dots_positions()
		state = move

func move_diameter_counter_clockwise():
	if state != move or selected_diameter == -1:
		return
		
	state = wait
	# 保存直径上的所有点
	var dots_to_move = []
	for radius_index in range(num_radii):
		var angle_index = (selected_diameter + radius_index * (num_angles / 2)) % num_angles
		if all_dots[angle_index][radius_index] != null:
			dots_to_move.append(all_dots[angle_index][radius_index])
	
	# 移动点
	if dots_to_move.size() > 0:
		var first_dot = dots_to_move[0]
		for i in range(0, dots_to_move.size() - 1):
			var current_angle = get_dot_angle(dots_to_move[i])
			var next_angle = get_dot_angle(dots_to_move[i+1])
			all_dots[current_angle][get_dot_radius(dots_to_move[i])] = dots_to_move[i+1]
			all_dots[next_angle][get_dot_radius(dots_to_move[i+1])] = dots_to_move[i]
		
		# 移动最后一个点
		var last_angle = get_dot_angle(dots_to_move.back())
		var first_angle = get_dot_angle(first_dot)
		all_dots[last_angle][get_dot_radius(dots_to_move.back())] = first_dot
		all_dots[first_angle][get_dot_radius(first_dot)] = dots_to_move.back()
		
		update_all_dots_positions()
		state = move

func get_dot_angle(dot) -> int:
	for angle_index in range(num_angles):
		for radius_index in range(num_radii):
			if all_dots[angle_index][radius_index] == dot:
				return angle_index
	return -1

func get_dot_radius(dot) -> int:
	for angle_index in range(num_angles):
		for radius_index in range(num_radii):
			if all_dots[angle_index][radius_index] == dot:
				return radius_index
	return -1

func update_ring_highlights():
	for i in range(num_radii):
		ring_highlights[i].visible = (i == selected_ring)

func update_diameter_highlights():
	for i in range(num_radii, ring_highlights.size()):
		ring_highlights[i].visible = (i - num_radii == selected_diameter)
