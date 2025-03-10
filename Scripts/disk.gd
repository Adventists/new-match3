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
@export var match_count: int = 4  # 需要多少个相同颜色的点才会消除
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
var current_angle_index = 0  # 当前角度索引
var target_angle_index = 0   # 目标角度索引
var rotation_speed = 15.0    # 旋转速度
var is_rotating = false      # 是否正在旋转
var rotation_progress = 0.0  # 动画进度

# 环选择相关变量
var selected_ring = -1       # 当前选中的环（-1表示未选中）
var ring_highlights = []     # 存储环的高亮节点
var ring_angle_indices = []  # 存储每个环的角度索引

# 直径选择相关变量
var current_mode = ring_mode  # 当前选择模式
var selected_diameter = -1  # 当前选中的直径（-1表示未选中）

# 在文件开头的变量声明部分添加新的变量
var is_diameter_moving = false
var diameter_move_progress = 0.0
var diameter_move_speed = 5.0  # 调整这个值可以改变移动速度
var diameter_dots_movement = {}  # 存储点的起始位置和目标位置

@onready var ui = get_node("/root/Game/UI")

func _ready():
	state = move
	setup_timers()
	randomize()
	var viewport_size = get_viewport_rect().size
	center = viewport_size / 2
	# 初始化角度索引数组
	ring_angle_indices.resize(num_radii)
	for i in range(num_radii):
		ring_angle_indices[i] = 0
	all_dots = make_polar_array()
	spawn_dots()
	create_ring_highlights()  # 创建环的高亮
	# 等待一帧确保UI已经准备好
	await get_tree().process_frame
	update_ui()
	# 默认选中第一个环
	select_ring(0)

func _process(delta):
	if is_rotating:
		rotation_progress += delta * rotation_speed
		if rotation_progress >= 1.0:
			# 动画结束，直接设置到目标位置
			if selected_ring != -1:
				ring_angle_indices[selected_ring] = target_angle_index
				# 强制更新所有点到最终位置
				update_all_dots_positions(true)
			is_rotating = false
			rotation_progress = 0.0
			find_matches()
			if !destroy_timer.is_stopped():
				state = wait
			else:
				state = move
		else:
			# 动画过程中只更新点的位置
			update_all_dots_positions(false)
	
	if is_diameter_moving:
		# 直径移动动画
		diameter_move_progress += delta * diameter_move_speed
		if diameter_move_progress >= 1.0:
			# 动画结束，设置最终位置
			for dot in diameter_dots_movement:
				dot.position = diameter_dots_movement[dot]["end"]
			diameter_dots_movement.clear()
			is_diameter_moving = false
			diameter_move_progress = 0.0
			# 检查是否有可消除的点
			find_matches()
			if !destroy_timer.is_stopped():
				state = wait
			else:
				state = move
		else:
			# 更新动画中的点位置
			for dot in diameter_dots_movement:
				var start_pos = diameter_dots_movement[dot]["start"]
				var end_pos = diameter_dots_movement[dot]["end"]
				dot.position = start_pos.lerp(end_pos, diameter_move_progress)

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
	current_angle_index = ring_angle_indices[selected_ring]
	target_angle_index = (current_angle_index + 1) % num_angles
	rotation_progress = 0.0
	remaining_moves -= 1
	update_ui()

func rotate_counter_clockwise():
	if state != move or is_rotating or selected_ring == -1:
		return
		
	state = wait
	is_rotating = true
	current_angle_index = ring_angle_indices[selected_ring]
	target_angle_index = (current_angle_index - 1 + num_angles) % num_angles
	rotation_progress = 0.0
	remaining_moves -= 1
	update_ui()

func update_all_dots_positions(force_final_position: bool = false):
	for angle_index in num_angles:
		for radius_index in num_radii:
			if all_dots[angle_index][radius_index] != null:
				var dot = all_dots[angle_index][radius_index]
				var angle_step = 2 * PI / num_angles
				
				# 计算实际角度
				var actual_angle = angle_index * angle_step
				if current_mode == ring_mode:
					if is_rotating and radius_index == selected_ring and not force_final_position:
						# 在动画过程中，使用 rotation_progress 插值
						var start_angle = (angle_index + current_angle_index) * angle_step
						var end_angle = (angle_index + target_angle_index) * angle_step
						actual_angle = lerp_angle(start_angle, end_angle, ease(rotation_progress, 0.5))
					else:
						# 使用精确的索引位置
						var final_index = (angle_index + ring_angle_indices[radius_index]) % num_angles
						actual_angle = final_index * angle_step
				
				var radius = base_radius + (radius_index * spacing)
				var x = cos(actual_angle) * radius
				var y = sin(actual_angle) * radius
				dot.position = Vector2(x, y) + center
				
				# 更新高亮环的旋转
				if current_mode == ring_mode and radius_index == selected_ring:
					if is_rotating and not force_final_position:
						var start_angle = current_angle_index * angle_step
						var end_angle = target_angle_index * angle_step
						ring_highlights[radius_index].rotation = lerp_angle(start_angle, end_angle, ease(rotation_progress, 0.5))
					else:
						ring_highlights[radius_index].rotation = ring_angle_indices[radius_index] * angle_step

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
				while (match_at(angle_index, radius_index, dot.color) and loops < 100):
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
	# 半径方向匹配（检查内圈的点）
	if radius_index > match_count - 1:
		var is_match = true
		for i in range(1, match_count):
			if all_dots[angle_index][radius_index - i] == null or all_dots[angle_index][radius_index - i].color != color:
				is_match = false
				break
		if is_match:
			return true

	# 环方向匹配（检查相邻的点）
	var count = 1
	var i = angle_index - 1
	# 向左检查连续相同颜色的点
	while i >= 0:
		if all_dots[i][radius_index] != null and all_dots[i][radius_index].color == color:
			count += 1
			i -= 1
		else:
			break
	
	i = angle_index + 1
	# 向右检查连续相同颜色的点
	while i < num_angles:
		if all_dots[i][radius_index] != null and all_dots[i][radius_index].color == color:
			count += 1
			i += 1
		else:
			break
	
	# 处理环形边界情况
	if angle_index == 0 or angle_index == num_angles - 1:
		var left_count = 0
		var right_count = 0
		i = num_angles - 1
		# 从最右边检查到左边
		while i >= 0:
			if all_dots[i][radius_index] != null and all_dots[i][radius_index].color == color:
				left_count += 1
				i -= 1
			else:
				break
		
		i = 0
		# 从最左边检查到右边
		while i < num_angles:
			if all_dots[i][radius_index] != null and all_dots[i][radius_index].color == color:
				right_count += 1
				i += 1
			else:
				break
		
		count = max(count, left_count + right_count)
	
	return count >= match_count

func find_matches():
	var was_matched = false
	var matched_dots = []
	
	# 检查半径方向的匹配
	for angle_index in num_angles:
		var current_color = null
		var count = 0
		var current_matched = []
		
		for radius_index in range(num_radii - 1, -1, -1):  # 从外向内检查
			if all_dots[angle_index][radius_index] != null:
				var dot = all_dots[angle_index][radius_index]
				if current_color == null:
					current_color = dot.color
					count = 1
					current_matched = [dot]
				elif dot.color == current_color:
					count += 1
					current_matched.append(dot)
					if count >= match_count:
						was_matched = true
						matched_dots.append_array(current_matched)
				else:
					current_color = dot.color
					count = 1
					current_matched = [dot]
	
	# 检查环方向的匹配
	for radius_index in num_radii:
		var current_color = null
		var count = 0
		var current_matched = []
		var first_dot = null
		var first_color = null
		
		# 先检查普通的连续匹配
		for angle_index in num_angles:
			if all_dots[angle_index][radius_index] != null:
				var dot = all_dots[angle_index][radius_index]
				if angle_index == 0:
					first_dot = dot
					first_color = dot.color
				
				if current_color == null:
					current_color = dot.color
					count = 1
					current_matched = [dot]
				elif dot.color == current_color:
					count += 1
					current_matched.append(dot)
					if count >= match_count:
						was_matched = true
						matched_dots.append_array(current_matched)
				else:
					current_color = dot.color
					count = 1
					current_matched = [dot]
		
		# 检查跨越边界的匹配
		if first_dot != null and first_color == current_color:
			var wrap_count = 0
			var wrap_matched = []
			# 从末尾向前检查
			for i in range(num_angles - 1, -1, -1):
				if all_dots[i][radius_index] != null and all_dots[i][radius_index].color == first_color:
					wrap_count += 1
					wrap_matched.append(all_dots[i][radius_index])
				else:
					break
			# 从开头向后检查
			for i in range(0, num_angles):
				if all_dots[i][radius_index] != null and all_dots[i][radius_index].color == first_color:
					wrap_count += 1
					wrap_matched.append(all_dots[i][radius_index])
				else:
					break
			
			if wrap_count >= match_count:
				was_matched = true
				matched_dots.append_array(wrap_matched)
	
	# 标记所有匹配的点
	for dot in matched_dots:
		dot.matched = true
		dot.dim()
		score += 1
	
	if was_matched:
		destroy_timer.start()
	
	return was_matched

func collapse_columns():
	var moved = false
	
	# 从外圈向内圈遍历
	for angle_index in num_angles:
		for radius_index in range(num_radii - 1, 0, -1):  # 从外向内
			if all_dots[angle_index][radius_index] == null:
				# 找到内圈最近的非空点
				for inner_radius in range(radius_index - 1, -1, -1):
					if all_dots[angle_index][inner_radius] != null:
						# 移动点到外圈
						var dot = all_dots[angle_index][inner_radius]
						all_dots[angle_index][inner_radius] = null
						all_dots[angle_index][radius_index] = dot
						dot.move(grid_to_pixel(angle_index, radius_index))
						moved = true
						break
	
	if moved:
		collapse_timer.start()
	else:
		refill_timer.start()

func refill_columns():
	var refilled = false
	
	for angle_index in num_angles:
		for radius_index in num_radii:
			if all_dots[angle_index][radius_index] == null and !restricted_fill(Vector2(angle_index, radius_index)):
				var rand = floor(randf_range(0, possible_dots.size()))
				var dot = possible_dots[rand].instantiate()
				var loops = 0
				
				while (match_at(angle_index, radius_index, dot.color) and loops < 100):
					rand = floor(randf_range(0, possible_dots.size()))
					loops += 1
					dot = possible_dots[rand].instantiate()
				
				add_child(dot)
				# 设置初始位置在圆心
				dot.position = center
				# 移动到目标位置
				dot.move(grid_to_pixel(angle_index, radius_index))
				all_dots[angle_index][radius_index] = dot
				refilled = true
	
	if refilled:
		await get_tree().create_timer(0.3).timeout
		# 检查新填充的点是否形成匹配
		if find_matches():
			destroy_timer.start()
		else:
			state = move
	else:
		state = move

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
		# 计算直径的两个端点（从一端到另一端）
		var start_point = Vector2(
			cos(angle) * (base_radius + (num_radii - 1) * spacing + 50),
			sin(angle) * (base_radius + (num_radii - 1) * spacing + 50)
		)
		var end_point = Vector2(
			cos(angle + PI) * (base_radius + (num_radii - 1) * spacing + 50),
			sin(angle + PI) * (base_radius + (num_radii - 1) * spacing + 50)
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
	
	# 使用当前环的角度索引
	current_angle_index = ring_angle_indices[ring]
	target_angle_index = current_angle_index
	rotation_progress = 0.0
	is_rotating = false

func select_previous_ring():
	if selected_ring >= num_radii - 1:
		select_ring(0)  # 如果是最外圈，跳到最内圈
	else:
		select_ring(selected_ring + 1)  # 否则向外移动一圈

func select_next_ring():
	if selected_ring <= 0:
		select_ring(num_radii - 1)  # 如果是最内圈，跳到最外圈
	else:
		select_ring(selected_ring - 1)  # 否则向内移动一圈

func toggle_selection_mode():
	if current_mode == ring_mode:
		var temp_array = make_polar_array()
		for angle_index in num_angles:
			for radius_index in num_radii:
				if all_dots[angle_index][radius_index] != null:
					var dot = all_dots[angle_index][radius_index]
					var actual_angle_index = (angle_index + ring_angle_indices[radius_index]) % num_angles
					if actual_angle_index < 0:
						actual_angle_index += num_angles
					temp_array[actual_angle_index][radius_index] = dot
		all_dots = temp_array
	
	current_mode = diameter_mode if current_mode == ring_mode else ring_mode
	
	if current_mode == ring_mode:
		selected_diameter = -1
		update_diameter_highlights()
		select_ring(0)
	else:
		selected_ring = -1
		update_ring_highlights()
		select_diameter(0)
	
	# 重置旋转状态
	current_angle_index = 0
	target_angle_index = 0
	is_rotating = false
	rotation_progress = 0.0
	
	# 重置所有环的角度索引
	for i in range(num_radii):
		ring_angle_indices[i] = 0
	
	update_all_dots_positions()
	
	if find_matches():
		state = wait
		destroy_timer.start()
	else:
		state = move

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
	# 获取选中直径的角度
	var angle1 = selected_diameter * (2 * PI / num_angles)  # 一端
	var angle2 = angle1 + PI  # 另一端（相差180度）
	
	# 将弧度转换为角度索引
	var angle_index1 = selected_diameter
	var angle_index2 = (selected_diameter + num_angles / 2) % num_angles
	
	var first_side_dots = []  # angle1方向的点
	var second_side_dots = []  # angle2方向的点
	
	# 收集两端的点
	for radius_index in range(num_radii):
		if all_dots[angle_index1][radius_index] != null:
			first_side_dots.append({"dot": all_dots[angle_index1][radius_index], "radius": radius_index, "angle": angle_index1})
		if all_dots[angle_index2][radius_index] != null:
			second_side_dots.append({"dot": all_dots[angle_index2][radius_index], "radius": radius_index, "angle": angle_index2})
	
	# 创建临时数组来存储新的位置
	var new_positions = {}
	diameter_dots_movement.clear()  # 清除之前的动画数据
	
	# 检查是否是45度角的直径（第1个或第3个直径）
	var is_45_degree = selected_diameter == 1 or selected_diameter == 3
	
	if is_45_degree:
		# 45度角的直径反转移动方向
		# 计算angle1方向的点的新位置（环数-1）
		for dot_info in first_side_dots:
			var current_radius = dot_info["radius"]
			var current_angle = dot_info["angle"]
			var dot = dot_info["dot"]
			
			if current_radius == 0:
				# 如果是最内圈，移到对面的最内圈
				new_positions[dot] = {"angle": angle_index2, "radius": current_radius}
			else:
				# 否则环数-1
				new_positions[dot] = {"angle": current_angle, "radius": current_radius - 1}
		
		# 计算angle2方向的点的新位置（环数+1）
		for dot_info in second_side_dots:
			var current_radius = dot_info["radius"]
			var current_angle = dot_info["angle"]
			var dot = dot_info["dot"]
			
			if current_radius == num_radii - 1:
				# 如果是最外圈，移到对面的最外圈
				new_positions[dot] = {"angle": angle_index1, "radius": current_radius}
			else:
				# 否则环数+1
				new_positions[dot] = {"angle": current_angle, "radius": current_radius + 1}
	else:
		# 其他角度的直径保持原有的移动方向
		# 计算angle1方向的点的新位置（环数+1）
		for dot_info in first_side_dots:
			var current_radius = dot_info["radius"]
			var current_angle = dot_info["angle"]
			var dot = dot_info["dot"]
			
			if current_radius == num_radii - 1:
				# 如果是最外圈，移到对面的最外圈
				new_positions[dot] = {"angle": angle_index2, "radius": current_radius}
			else:
				# 否则环数+1
				new_positions[dot] = {"angle": current_angle, "radius": current_radius + 1}
		
		# 计算angle2方向的点的新位置（环数-1）
		for dot_info in second_side_dots:
			var current_radius = dot_info["radius"]
			var current_angle = dot_info["angle"]
			var dot = dot_info["dot"]
			
			if current_radius == 0:
				# 如果是最内圈，移到对面的最内圈
				new_positions[dot] = {"angle": angle_index1, "radius": current_radius}
			else:
				# 否则环数-1
				new_positions[dot] = {"angle": current_angle, "radius": current_radius - 1}
	
	# 保存所有点的起始和目标位置用于动画
	for dot in new_positions:
		var new_pos = new_positions[dot]
		var target_angle = new_pos["angle"] * (2 * PI / num_angles)
		var target_radius = base_radius + (new_pos["radius"] * spacing)
		var target_x = cos(target_angle) * target_radius
		var target_y = sin(target_angle) * target_radius
		var target_position = Vector2(target_x, target_y) + center
		
		diameter_dots_movement[dot] = {
			"start": dot.position,
			"end": target_position
		}
	
	# 清除所有涉及的点的原位置
	for dot_info in first_side_dots + second_side_dots:
		all_dots[dot_info["angle"]][dot_info["radius"]] = null
	
	# 将点移动到新位置（在数组中）
	for dot in new_positions:
		var new_pos = new_positions[dot]
		all_dots[new_pos["angle"]][new_pos["radius"]] = dot
	
	# 开始动画
	is_diameter_moving = true
	diameter_move_progress = 0.0

func move_diameter_counter_clockwise():
	if state != move or selected_diameter == -1:
		return
		
	state = wait
	# 获取选中直径的角度
	var angle1 = selected_diameter * (2 * PI / num_angles)  # 一端
	var angle2 = angle1 + PI  # 另一端（相差180度）
	
	# 将弧度转换为角度索引
	var angle_index1 = selected_diameter
	var angle_index2 = (selected_diameter + num_angles / 2) % num_angles
	
	var first_side_dots = []  # angle1方向的点
	var second_side_dots = []  # angle2方向的点
	
	# 收集两端的点
	for radius_index in range(num_radii):
		if all_dots[angle_index1][radius_index] != null:
			first_side_dots.append({"dot": all_dots[angle_index1][radius_index], "radius": radius_index, "angle": angle_index1})
		if all_dots[angle_index2][radius_index] != null:
			second_side_dots.append({"dot": all_dots[angle_index2][radius_index], "radius": radius_index, "angle": angle_index2})
	
	# 创建临时数组来存储新的位置
	var new_positions = {}
	diameter_dots_movement.clear()  # 清除之前的动画数据
	
	# 检查是否是45度角的直径（第1个或第3个直径）
	var is_45_degree = selected_diameter == 1 or selected_diameter == 3
	
	if is_45_degree:
		# 45度角的直径反转移动方向
		# 计算angle1方向的点的新位置（环数+1）
		for dot_info in first_side_dots:
			var current_radius = dot_info["radius"]
			var current_angle = dot_info["angle"]
			var dot = dot_info["dot"]
			
			if current_radius == num_radii - 1:
				# 如果是最外圈，移到对面的最外圈
				new_positions[dot] = {"angle": angle_index2, "radius": current_radius}
			else:
				# 否则环数+1
				new_positions[dot] = {"angle": current_angle, "radius": current_radius + 1}
		
		# 计算angle2方向的点的新位置（环数-1）
		for dot_info in second_side_dots:
			var current_radius = dot_info["radius"]
			var current_angle = dot_info["angle"]
			var dot = dot_info["dot"]
			
			if current_radius == 0:
				# 如果是最内圈，移到对面的最内圈
				new_positions[dot] = {"angle": angle_index1, "radius": current_radius}
			else:
				# 否则环数-1
				new_positions[dot] = {"angle": current_angle, "radius": current_radius - 1}
	else:
		# 其他角度的直径保持原有的移动方向
		# 计算angle1方向的点的新位置（环数-1）
		for dot_info in first_side_dots:
			var current_radius = dot_info["radius"]
			var current_angle = dot_info["angle"]
			var dot = dot_info["dot"]
			
			if current_radius == 0:
				# 如果是最内圈，移到对面的最内圈
				new_positions[dot] = {"angle": angle_index2, "radius": current_radius}
			else:
				# 否则环数-1
				new_positions[dot] = {"angle": current_angle, "radius": current_radius - 1}
		
		# 计算angle2方向的点的新位置（环数+1）
		for dot_info in second_side_dots:
			var current_radius = dot_info["radius"]
			var current_angle = dot_info["angle"]
			var dot = dot_info["dot"]
			
			if current_radius == num_radii - 1:
				# 如果是最外圈，移到对面的最外圈
				new_positions[dot] = {"angle": angle_index1, "radius": current_radius}
			else:
				# 否则环数+1
				new_positions[dot] = {"angle": current_angle, "radius": current_radius + 1}
	
	# 保存所有点的起始和目标位置用于动画
	for dot in new_positions:
		var new_pos = new_positions[dot]
		var target_angle = new_pos["angle"] * (2 * PI / num_angles)
		var target_radius = base_radius + (new_pos["radius"] * spacing)
		var target_x = cos(target_angle) * target_radius
		var target_y = sin(target_angle) * target_radius
		var target_position = Vector2(target_x, target_y) + center
		
		diameter_dots_movement[dot] = {
			"start": dot.position,
			"end": target_position
		}
	
	# 清除所有涉及的点的原位置
	for dot_info in first_side_dots + second_side_dots:
		all_dots[dot_info["angle"]][dot_info["radius"]] = null
	
	# 将点移动到新位置（在数组中）
	for dot in new_positions:
		var new_pos = new_positions[dot]
		all_dots[new_pos["angle"]][new_pos["radius"]] = dot
	
	# 开始动画
	is_diameter_moving = true
	diameter_move_progress = 0.0

func update_ring_highlights():
	for i in range(num_radii):
		ring_highlights[i].visible = (i == selected_ring)

func update_diameter_highlights():
	for i in range(num_radii, ring_highlights.size()):
		ring_highlights[i].visible = (i - num_radii == selected_diameter)

func destroy_matches():
	# 遍历所有点，删除被标记为匹配的点
	var was_matched = false
	for angle_index in num_angles:
		for radius_index in num_radii:
			if all_dots[angle_index][radius_index] != null:
				if all_dots[angle_index][radius_index].matched:
					# 删除节点
					all_dots[angle_index][radius_index].queue_free()
					all_dots[angle_index][radius_index] = null
					was_matched = true

	if was_matched:
		collapse_timer.start()
	else:
		state = move
