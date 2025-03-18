extends Node2D

enum {wait, move} #state 变量用于存储当前游戏的状态，可能用于控制玩家何时可以操作棋盘，例如：wait 状态：等待玩家输入或动画结束。move 状态：正在执行消除或填充动画时，不允许新的输入
enum {puzzle_mode, endless_mode} #游戏模式
enum {ring_mode, diameter_mode} # 选择模式

# 交互系统说明：
# 1. 使用鼠标点击选择环/直径
# 2. 环模式下，可以拖动环旋转，松开时自动吸附到最近的整数索引位置
# 3. 直径模式下，点击直径两端的任意一端移动直径上的点
# 4. TAB键用于切换环模式和直径模式
# 5. 只有在环的位置确实发生变化时才会消耗步数
# 6. 在拖动结束后检测消除

var state
var remaining_moves = 10 #剩余步数
var score = 0 #分数

@export var num_angles: int = 8  # 角度切分数量，例如 8 份
@export var num_radii: int = 4   # 圆盘的层数（半径方向），改为4圈
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

# 鼠标交互相关变量
var is_dragging = false             # 是否正在拖动
var drag_start_position = Vector2() # 拖动起始位置
var drag_start_angle = 0.0          # 拖动起始角度
var drag_current_angle = 0.0        # 当前拖动角度
var original_angle_index = 0        # 拖动开始时的角度索引
var min_drag_distance = 10.0        # 最小拖动距离(像素)，小于此距离不视为拖动
var is_diameter_dragging = false    # 是否正在拖动直径
var drag_rotation = 0.0             # 当前拖动的旋转角度（弧度）
var drag_start_rotation = 0.0       # 拖动开始时的旋转角度
var snapping_to_index = false       # 是否正在吸附到整数索引
var snap_target_angle = 0.0         # 吸附目标角度
var snap_progress = 0.0             # 吸附进度
var snap_speed = 10.0               # 吸附速度

# 在文件开头的变量声明部分添加新的变量
var is_diameter_moving = false
var diameter_move_progress = 0.0
var diameter_move_speed = 5.0  # 调整这个值可以改变移动速度
var diameter_dots_movement = {}  # 存储点的起始位置和目标位置

# 在文件开头添加新的变量
var current_level = 1  # 当前关卡
var level_data = null  # 关卡数据
var gray_dot = preload("res://Scenes/Dots/gray_dot.tscn")

@onready var ui = null  # 将在_ready中初始化

const PUZZLE_MODE = 0
const ENDLESS_MODE = 1

@export var game_mode: int  # 不再设置默认值

# 无限模式关卡设置
var level_targets = [500, 1000, 2000, 3000, 5000, 7500, 10000]  # 每关目标分数
var level_moves = [15, 18, 20, 22, 25, 28, 30]  # 每关可用步数

# buff系统
var active_buffs = []
var available_buffs = [
	# 消除规则类
	{"id": 1, "name": "同色四连消除", "description": "同色四连消除获得额外分数"},
	{"id": 2, "name": "十字消除", "description": "消除时同时消除十字交叉点"},
	{"id": 3, "name": "环形消除", "description": "消除时可以消除整个圆环上同色的点"},
	{"id": 4, "name": "连锁反应", "description": "消除后相邻同色点也会消除"},
	
	# 得分提升类
	{"id": 5, "name": "同色消除加成", "description": "相同颜色消除分数+50%"},
	{"id": 6, "name": "连击加成", "description": "连续消除提供递增分数"},
	{"id": 7, "name": "完美消除", "description": "一次消除>=5个点额外加分"},
	{"id": 8, "name": "环形奖励", "description": "整圆环颜色一致时额外得分"},
	
	# 特殊效果类
	{"id": 9, "name": "额外步数", "description": "每关开始时+2步"},
	{"id": 10, "name": "重置机会", "description": "每关有1次重置圆盘机会"},
	{"id": 11, "name": "预览效果", "description": "显示下一次旋转的效果"},
	{"id": 12, "name": "保护罩", "description": "失败时有一次继续机会"}
]

func _ready():
	# 初始化UI引用
	if get_tree().get_root().has_node("Game/EndlessUI"):
		ui = get_tree().get_root().get_node("Game/EndlessUI")
		game_mode = ENDLESS_MODE  # 在Game场景中设置为无限模式
	elif get_tree().get_root().has_node("PuzzleGame/PuzzleUI"):
		ui = get_tree().get_root().get_node("PuzzleGame/PuzzleUI")
		game_mode = PUZZLE_MODE  # 在PuzzleGame场景中设置为解谜模式

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
	
	# 重置鼠标操作相关变量
	is_dragging = false
	is_diameter_dragging = false
	
	# 根据游戏模式初始化
	if game_mode == PUZZLE_MODE:
		load_puzzle_level()  # 加载解谜关卡
	else:
		initialize_endless_mode()  # 初始化无限模式
		
	create_ring_highlights()
	await get_tree().process_frame
	update_ui()
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
			# 立即检查匹配
			check_all_matches()
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
			check_all_matches()
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

	if snapping_to_index:
		snap_progress += delta * snap_speed
		if snap_progress >= 1.0:
			# 吸附完成
			snap_progress = 1.0
			snapping_to_index = false
			
			# 更新环的角度索引
			var angle_step = 2 * PI / num_angles
			var target_angle_normalized = fmod(snap_target_angle, 2 * PI)
			if target_angle_normalized < 0:
				target_angle_normalized += 2 * PI
				
			var target_index = int(round(target_angle_normalized / angle_step)) % int(num_angles)
			
			ring_angle_indices[selected_ring] = target_index
			
			# 更新数据结构中点的实际位置
			update_all_dots_positions()
			
			# 检查是否有消除
			check_all_matches()
			
			# 更新游戏状态
			if target_index != original_angle_index:
				if !destroy_timer.is_stopped():
					state = wait
				else:
					state = move
			else:
				state = move
		
		# 更新旋转角度
		drag_rotation = lerp_angle(drag_rotation, snap_target_angle, snap_progress)
		update_drag_visuals()

func _input(event):
	if state == wait or is_rotating or is_diameter_moving:
		return
		
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_TAB:  # 使用Tab键切换模式
			toggle_selection_mode()
	
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 鼠标按下，只选择环而不开始拖动
				if current_mode == ring_mode:
					var clicked_ring = get_ring_at_position(event.position)
					print("input方法！")
					if clicked_ring != -1:
						select_ring(clicked_ring)
						print("input方法调用了select—ring了！")
						# 不要立即调用start_ring_drag - 等待鼠标移动
				else:  # diameter_mode
					var clicked_diameter = get_diameter_at_position(event.position)
					if clicked_diameter != -1:
						select_diameter(clicked_diameter)
						
						# 计算点击点与直径的关系，确定移动方向
						var diameter_angle = clicked_diameter * (2 * PI / num_angles)
						var direction = (event.position - center).normalized()
						var click_angle = atan2(direction.y, direction.x)
						if click_angle < 0:
							click_angle += 2 * PI
							
						# 计算角度差来确定拖动点在直径的哪一端
						var angle_diff = angle_difference(click_angle, diameter_angle)
						
						if abs(angle_diff) < PI/2: # 点在直径的右侧
							move_diameter_clockwise()
						else: # 点在直径的左侧
							move_diameter_counter_clockwise()
			else:
				# 鼠标释放
				if is_dragging and current_mode == ring_mode:
					end_ring_drag(event.position)
					#for i in range(num_radii):
						#ring_angle_indices[i] = 0
					#update_all_dots_positions()
					#check_all_matches()
					print("input方法调用了end-ring-drag了！")
	
	elif event is InputEventMouseMotion:
		# 鼠标移动时才开始拖动
		if event.button_mask == MOUSE_BUTTON_MASK_LEFT and current_mode == ring_mode and selected_ring != -1:
			if !is_dragging:
				# 首次移动时开始拖动
				start_ring_drag(event.position)
				print("input方法调用了start-ring了！")
			else:
				update_ring_drag(event.position)
				print("input方法调用了update-ring了！")

# 获取点击位置对应的环索引
func get_ring_at_position(position: Vector2) -> int:
	var distance = position.distance_to(center)
	
	# 计算每个环的大致半径范围
	for i in range(num_radii):
		var ring_radius = base_radius + (i * spacing)
		var inner_bound = ring_radius - spacing/2
		var outer_bound = ring_radius + spacing/2
		
		if distance >= inner_bound and distance <= outer_bound:
			return i
	
	return -1

# 获取点击位置对应的直径索引
func get_diameter_at_position(position: Vector2) -> int:
	var direction = (position - center).normalized()
	var angle = atan2(direction.y, direction.x)
	if angle < 0:
		angle += 2 * PI
		
	# 将角度转换为直径索引
	# 直径索引是0到(num_angles/2 - 1)
	var angle_step = PI / (num_angles / 2)
	var index = int(round(angle / angle_step)) % (num_angles / 2)
	
	return index

# 开始环的拖动
func start_ring_drag(position: Vector2):
	if selected_ring == -1 or state != move:
		return
		
	is_dragging = true
	drag_start_position = position
	
	# 计算起始拖动角度
	var direction = (position - center).normalized()
	drag_start_angle = atan2(direction.y, direction.x)
	
	# 记录拖动开始时的旋转角度
	drag_rotation = ring_angle_indices[selected_ring] * (2 * PI / num_angles)
	drag_start_rotation = drag_rotation
	original_angle_index = ring_angle_indices[selected_ring]
	
	# 重置吸附状态
	snapping_to_index = false
	snap_progress = 0.0
	print("start—ring-drag 我动啦！")

# 更新环的拖动
func update_ring_drag(position: Vector2):
	if !is_dragging or selected_ring == -1:
		return
		
	# 计算当前鼠标位置相对于中心的角度
	var drag_vector = position - center
	drag_current_angle = atan2(drag_vector.y, drag_vector.x)
	
	# 计算从开始拖动到现在的角度差
	var angle_diff = drag_current_angle - drag_start_angle
	
	# 处理角度环绕（从-π到π的跨越）
	if angle_diff > PI:
		angle_diff -= 2 * PI
	elif angle_diff < -PI:
		angle_diff += 2 * PI
	
	# 将角度差直接应用到旋转角度上 (不再取反)
	drag_rotation = drag_start_rotation + angle_diff
	
	# 更新可视旋转效果
	update_drag_visuals()

# 结束环的拖动
func end_ring_drag(position: Vector2):
	if !is_dragging or selected_ring == -1:
		return
		
	is_dragging = false
	
	# 确定最接近的角度索引
	var angle_step = 2 * PI / num_angles
	
	# 计算当前拖动旋转相对于0度的角度
	var current_rotation_normalized = fmod(drag_rotation, 2 * PI)
	if current_rotation_normalized < 0:
		current_rotation_normalized += 2 * PI
	
	# 计算目标索引
	var target_index = int(round(current_rotation_normalized / angle_step)) % int(num_angles)
	if target_index < 0:
		target_index += int(num_angles)
	
	print("drag_rotation:", drag_rotation, " target_index:", target_index)
	
	# 计算目标角度
	var target_angle = target_index * angle_step
	
	# 判断是否发生了实际的旋转
	if target_index != original_angle_index:
		# 发生了旋转，扣除步数
		if remaining_moves > 0:
			remaining_moves -= 1
		update_ui()
	
	# 启动吸附动画
	snapping_to_index = true
	snap_target_angle = target_angle
	snap_progress = 0.0

# 更新点的位置和数据结构
func update_all_dots_positions(force_final_position: bool = false):
	# 添加角度步长的定义
	var angle_step = 2 * PI / num_angles
	
	for angle_index in range(num_angles):
		for radius_index in range(num_radii):
			# 计算实际角度
			var actual_angle = 0.0
			if current_mode == ring_mode and radius_index == selected_ring and !force_final_position:
				if is_dragging:
					# 拖动时使用拖动旋转量
					actual_angle = angle_index * angle_step - drag_rotation
				elif snapping_to_index:
					# 正在吸附到整数位置时
					actual_angle = angle_index * angle_step - drag_rotation
				else:
					# 静止状态，直接使用存储的索引偏移
					actual_angle = (angle_index + ring_angle_indices[radius_index]) % num_angles * angle_step
			else:
				# 非选中环或非环模式，使用存储的索引偏移
				actual_angle = (angle_index + ring_angle_indices[radius_index]) % num_angles * angle_step
			
			# 设置点的位置
			if angle_index < num_angles and radius_index < num_radii:
				var dot = all_dots[angle_index][radius_index]
				if dot != null:
					dot.position = Vector2(
						center.x + cos(actual_angle) * (base_radius + radius_index * spacing),
						center.y + sin(actual_angle) * (base_radius + radius_index * spacing)
					)

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

# 添加加载关卡数据的函数
func load_level_data():
	var file = FileAccess.open("res://Resources/puzzle_levels.json", FileAccess.READ)

	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		var data = json.get_data()
		if error == OK:
			level_data = null  # 重置关卡数据
			for level in data["levels"]:
				if level["level"] == current_level:
					level_data = level
					remaining_moves = level["moves"]
					break
		file.close()
		
		# 如果没有找到当前关卡的数据，回到第一关
		if level_data == null:
			current_level = 1
			for level in data["levels"]:
				if level["level"] == current_level:
					level_data = level
					remaining_moves = level["moves"]
					break

# 修改spawn_dots函数
func spawn_puzzle_dots():
	if level_data == null:
		push_error("没有找到关卡数据！")
		return
		
	# 先用灰色点填充所有位置
	for angle_index in num_angles:
		for radius_index in num_radii:
			if !restricted_fill(Vector2(angle_index, radius_index)):
				var dot = gray_dot.instantiate()
				add_child(dot)
				dot.position = grid_to_pixel(angle_index, radius_index, false)
				all_dots[angle_index][radius_index] = dot
	
	# 放置关卡指定的彩色点
	for dot_data in level_data["dots"]:
		var angle_index = dot_data["angle_index"]
		var radius_index = dot_data["radius_index"]
		var color = dot_data["color"]
		
		# 移除该位置的灰色点
		if all_dots[angle_index][radius_index] != null:
			all_dots[angle_index][radius_index].queue_free()
		
		# 根据颜色选择正确的场景
		var dot_scene = null
		match color:
			"red":
				dot_scene = possible_dots[3]  # 红色
			"blue":
				dot_scene = possible_dots[0]  # 蓝色
			"green":
				dot_scene = possible_dots[1]  # 绿色
			"pink":
				dot_scene = possible_dots[2]  # 粉色
			"yellow":
				dot_scene = possible_dots[4]  # 黄色
		
		if dot_scene:
			var dot = dot_scene.instantiate()
			add_child(dot)
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

func check_match(angle_index: int, radius_index: int) -> bool:
	var dot = all_dots[angle_index][radius_index]
	if dot == null:
		return false
		
	# 获取当前点的颜色
	var current_color = dot.color
	
	# 如果是灰色点，直接返回false
	if current_color == "gray":
		return false
	
	var was_matched = false
	var matched_dots = []
	
	# 检查环形方向的匹配
	var ring_dots = []
	var i = angle_index
	
	# 向左检查
	while i >= 0:
		var check_dot = all_dots[i][radius_index]
		if check_dot != null and check_dot.color == current_color and check_dot.color != "gray":
			ring_dots.append(check_dot)
		else:
			break
		i -= 1
	
	# 向右检查
	i = angle_index + 1
	while i < num_angles:
		var check_dot = all_dots[i][radius_index]
		if check_dot != null and check_dot.color == current_color and check_dot.color != "gray":
			ring_dots.append(check_dot)
		else:
			break
		i += 1
	
	# 检查环形边界情况（首尾相连）
	if angle_index == 0 or angle_index == num_angles - 1:
		var boundary_dots = []
		
		# 从右边界向左检查
		i = num_angles - 1
		while i >= 0:
			var check_dot = all_dots[i][radius_index]
			if check_dot != null and check_dot.color == current_color and check_dot.color != "gray":
				boundary_dots.append(check_dot)
			else:
				break
			i -= 1
		
		# 从左边界向右检查
		i = 0
		while i < num_angles:
			var check_dot = all_dots[i][radius_index]
			if check_dot != null and check_dot.color == current_color and check_dot.color != "gray":
				boundary_dots.append(check_dot)
			else:
				break
			i += 1
		
		if boundary_dots.size() >= match_count:
			for d in boundary_dots:
				if not ring_dots.has(d):
					ring_dots.append(d)
	
	# 检查半径方向的匹配
	var radius_dots = []
	i = radius_index
	
	# 向内检查
	while i >= 0:
		var check_dot = all_dots[angle_index][i]
		if check_dot != null and check_dot.color == current_color and check_dot.color != "gray":
			radius_dots.append(check_dot)
		else:
			break
		i -= 1
	
	# 向外检查
	i = radius_index + 1
	while i < num_radii:
		var check_dot = all_dots[angle_index][i]
		if check_dot != null and check_dot.color == current_color and check_dot.color != "gray":
			radius_dots.append(check_dot)
		else:
			break
		i += 1
	
	# 如果任一方向达到匹配数量，标记为匹配
	if ring_dots.size() >= match_count:
		for d in ring_dots:
			d.matched = true
			d.dim()
			matched_dots.append(d)
		was_matched = true
	
	if radius_dots.size() >= match_count:
		for d in radius_dots:
			d.matched = true
			d.dim()
			matched_dots.append(d)
		was_matched = true
	
	# 更新分数
	if was_matched:
		score += matched_dots.size()
		check_level_target()
		
	return was_matched

func check_all_matches():
	var was_matched = false
	
	# 检查所有位置的匹配
	for angle_index in num_angles:
		for radius_index in num_radii:
			if all_dots[angle_index][radius_index] != null:
				was_matched = check_match(angle_index, radius_index) or was_matched
	
	if was_matched:
		destroy_timer.start()
		if game_mode == PUZZLE_MODE:
			check_level_complete()
	
	return was_matched

func collapse_columns():
	# 在解谜模式中，不需要下落和填充新的点
	if game_mode == puzzle_mode:
		state = move
		return
	
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
	# 在解谜模式中，不需要填充新的点
	if game_mode == puzzle_mode:
		state = move
		return
	
	var refilled = false
	
	for angle_index in num_angles:
		for radius_index in num_radii:
			if all_dots[angle_index][radius_index] == null and !restricted_fill(Vector2(angle_index, radius_index)):
				var rand = floor(randf_range(0, possible_dots.size()))
				var dot = possible_dots[rand].instantiate()
				var loops = 0
				
				while (check_match(angle_index, radius_index) and loops < 100):
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
		if check_all_matches():
			state = wait
		else:
			state = move
	else:
		state = move

func grid_to_pixel(angle_index, radius_index, _apply_rotation: bool = true):  # 添加下划线前缀
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
		if game_mode == PUZZLE_MODE:
			ui.update_level(current_level)
		elif game_mode == ENDLESS_MODE:
			var target = get_current_level_target()
			var next_target = get_next_level_target()
			ui.update_level_info(current_level, target, next_target)

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

func select_ring(ring: int):
	if ring < 0 or ring >= num_radii:
		return
		
	if ring == selected_ring:
		return
	
	# 首先重置所有状态变量
	var old_ring = selected_ring
	var was_dragging = is_dragging
	var was_snapping = snapping_to_index
	
	is_dragging = false
	snapping_to_index = false
	drag_start_position = Vector2.ZERO
	drag_start_angle = 0.0
	drag_current_angle = 0.0
	drag_rotation = 0.0
	drag_start_rotation = 0.0
	original_angle_index = 0
	snap_progress = 0.0
	snap_target_angle = 0.0
	
	# 在切换环之前，确保之前环的位置被正确保存
	if old_ring != -1 and (was_dragging or was_snapping):
		# 使用环的实际角度索引计算最终位置
		var final_index = ring_angle_indices[old_ring]
		print("Switching from ring", old_ring, "to ring", ring, "final_index:", final_index)
	
	# 取消之前的高亮
	for i in range(num_radii):
		if i < ring_highlights.size():
			ring_highlights[i].visible = false
	
	# 设置新的高亮
	selected_ring = ring
	if selected_ring < ring_highlights.size():
		ring_highlights[selected_ring].visible = true
	
	# 使用当前环的实际角度索引
	current_angle_index = ring_angle_indices[ring]
	target_angle_index = current_angle_index
	rotation_progress = 0.0
	is_rotating = false
	
	# 更新所有点的位置以反映当前状态
	#update_all_dots_positions(true)
	print("Before update_all_dots_positions: ", ring_angle_indices[selected_ring])
	update_all_dots_positions(true)
	print("After update_all_dots_positions: ", ring_angle_indices[selected_ring])

	

func toggle_selection_mode():
	# 重置拖动状态
	is_dragging = false
	is_diameter_dragging = false
	
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
	
	# 检查是否有匹配
	if check_all_matches():
		state = wait
	else:
		state = move

func select_diameter(diameter_index: int):
	if diameter_index < 0 or diameter_index >= num_angles / 2:
		return
		
	if diameter_index == selected_diameter:
		return
	
	# 取消之前的高亮
	for i in range(num_radii, ring_highlights.size()):
		ring_highlights[i].visible = false
	
	# 设置新的高亮
	selected_diameter = diameter_index
	if selected_diameter + num_radii < ring_highlights.size():
		ring_highlights[selected_diameter + num_radii].visible = true

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
	# 此函数保留但通过点击直径选择后的左右移动实现
	if state != move or selected_diameter == -1:
		return
		
	if game_mode == ENDLESS_MODE and remaining_moves <= 0:
		if ui:
			game_over()  # 显示游戏结束
		return
		
	state = wait
	
	# 扣除步数
	if remaining_moves > 0:
		remaining_moves -= 1
	update_ui()
	
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
	
	# 扣除步数
	if remaining_moves > 0:
		remaining_moves -= 1
	update_ui()
	
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
	# 在无限模式下，应用buff效果
	var was_matched = false
	var matched_count = 0
	var matched_dots = []
	
	# 收集所有匹配的点
	for angle_index in num_angles:
		for radius_index in num_radii:
			if all_dots[angle_index][radius_index] != null:
				if all_dots[angle_index][radius_index].matched:
					matched_dots.append(all_dots[angle_index][radius_index])
					matched_count += 1
	
	# 应用得分规则
	var score_multiplier = 1
	
	# 检查是否有得分加成buff
	if game_mode == ENDLESS_MODE:
		for buff in active_buffs:
			match buff.id:
				5:  # 同色消除加成
					var all_same_color = true
					var first_color = ""
					
					if matched_dots.size() > 0:
						first_color = matched_dots[0].color
						for dot in matched_dots:
							if dot.color != first_color:
								all_same_color = false
								break
					
					if all_same_color and matched_dots.size() > 0:
						score_multiplier *= 1.5
				
				6:  # 连击加成
					# 连击系统需要额外状态跟踪，这里简化为按匹配数量加成
					score_multiplier *= (1.0 + min(matched_count / 10.0, 1.0))
				
				7:  # 完美消除
					if matched_count >= 5:
						score_multiplier *= 1.5
	
	# 计算分数
	if matched_count > 0:
		was_matched = true
		score += matched_count * score_multiplier
		
		# 检查是否达到关卡目标
		if game_mode == ENDLESS_MODE:
			check_level_target()
	
	# 删除匹配的点
	for dot in matched_dots:
		dot.queue_free()
		
		# 从数组中移除
		for angle_index in num_angles:
			for radius_index in num_radii:
				if all_dots[angle_index][radius_index] == dot:
					all_dots[angle_index][radius_index] = null
	
	if was_matched:
		collapse_timer.start()
		update_ui()
	else:
		state = move

# 添加检查关卡完成的函数
func check_level_complete():
	# 检查所有指定颜色的点是否都被消除
	var level_complete = true
	for angle_index in num_angles:
		for radius_index in num_radii:
			var dot = all_dots[angle_index][radius_index]
			if dot != null and dot.color != "gray" and not dot.matched:
				level_complete = false
				break
	
	if level_complete:
		# 显示关卡完成UI
		if ui:
			ui.show_level_complete()
		# 解锁下一关
		current_level += 1

# 添加回spawn_dots函数
func spawn_dots():
	for angle_index in num_angles:  # 遍历所有角度
		for radius_index in num_radii:  # 遍历所有半径
			if !restricted_fill(Vector2(angle_index, radius_index)):  # 这里用极坐标
				var rand = floor(randf_range(0, possible_dots.size()))
				var dot = possible_dots[rand].instantiate()
				var loops = 0

				# 防止初始生成就有匹配
				while (check_match(angle_index, radius_index) and loops < 100):
					rand = floor(randf_range(0, possible_dots.size()))
					loops += 1
					dot = possible_dots[rand].instantiate()

				add_child(dot)
				dot.position = grid_to_pixel(angle_index, radius_index, false)
				all_dots[angle_index][radius_index] = dot

func load_puzzle_level():
	# 安全地从Global单例中获取当前关卡
	var global_node = null
	if get_tree().get_root().has_node("Global"):
		global_node = get_tree().get_root().get_node("Global")
	
	if global_node and global_node.has_method("get_current_puzzle_level"):
		current_level = global_node.get_current_puzzle_level()
	else:
		# 如果Global不存在或没有所需方法，使用默认值
		current_level = 1
		print("Warning: Global node or current_puzzle_level not found. Using default level 1.")
	
	# 加载关卡数据
	load_level_data()
	# 生成解谜模式的点阵
	spawn_puzzle_dots()

func initialize_endless_mode():
	current_level = 1
	score = 0
	
	# 设置当前关卡步数
	if current_level <= level_moves.size():
		remaining_moves = level_moves[current_level - 1]
	else:
		# 如果超出预设关卡，使用最后一个关卡的步数
		remaining_moves = level_moves[level_moves.size() - 1]
	
	# 更新UI显示
	if ui:
		var target = get_current_level_target()
		var next_target = get_next_level_target()
		ui.update_level_info(current_level, target, next_target)
	
	# 生成初始棋盘
	spawn_dots()
	
	# 应用激活的buff
	apply_active_buffs()

# 获取当前关卡目标分数
func get_current_level_target() -> int:
	if current_level <= level_targets.size():
		return level_targets[current_level - 1]
	else:
		# 如果超出预设关卡，使用公式计算目标分数
		var last_target = level_targets[level_targets.size() - 1]
		return last_target + (current_level - level_targets.size()) * 2500

# 获取下一关目标分数
func get_next_level_target() -> int:
	return get_current_level_target()

# 检查是否达成关卡目标
func check_level_target():
	var target = get_current_level_target()
	if score >= target:
		complete_level()

# 完成关卡
func complete_level():
	# 提供3个随机buff供选择
	var buff_options = select_random_buffs(3)
	
	# 显示关卡完成面板
	if ui:
		ui.show_level_complete(score, buff_options)

# 从可用buff中随机选择指定数量
func select_random_buffs(count: int) -> Array:
	var unused_buffs = []
	var active_buff_ids = []
	
	# 获取已激活buff的ID列表
	for buff in active_buffs:
		active_buff_ids.append(buff.id)
	
	# 找出未使用的buff
	for buff in available_buffs:
		if not buff.id in active_buff_ids:
			unused_buffs.append(buff)
	
	# 如果可选buff不足，返回所有可用buff
	if unused_buffs.size() <= count:
		return unused_buffs
	
	# 随机选择指定数量的buff
	var selected_buffs = []
	for i in range(count):
		var rand_index = randi() % unused_buffs.size()
		selected_buffs.append(unused_buffs[rand_index])
		unused_buffs.remove_at(rand_index)
	
	return selected_buffs

# 应用buff
func apply_buff(buff_id: int):
	# 查找对应ID的buff
	for buff in available_buffs:
		if buff.id == buff_id:
			# 添加到激活列表
			active_buffs.append(buff)
			break
	
	# 应用所有激活的buff
	apply_active_buffs()
	
	# 进入下一关
	advance_to_next_level()

# 应用激活的所有buff
func apply_active_buffs():
	# 检查是否有额外步数buff
	for buff in active_buffs:
		if buff.id == 9:  # 额外步数
			remaining_moves += 2

# 进入下一关
func advance_to_next_level():
	current_level += 1
	
	# 设置新关卡的步数
	if current_level <= level_moves.size():
		remaining_moves = level_moves[current_level - 1]
	else:
		# 如果超出预设关卡，使用最后一个关卡的步数
		remaining_moves = level_moves[level_moves.size() - 1]
	
	# 重置分数
	score = 0
	
	# 更新UI
	if ui:
		var target = get_current_level_target()
		var next_target = get_next_level_target()
		ui.update_level_info(current_level, target, next_target)
	
	# 重新生成棋盘
	clear_board()
	spawn_dots()

# 清空棋盘
func clear_board():
	for angle_index in num_angles:
		for radius_index in num_radii:
			if all_dots[angle_index][radius_index] != null:
				all_dots[angle_index][radius_index].queue_free()
				all_dots[angle_index][radius_index] = null

# 游戏结束
func game_over():
	if ui:
		ui.show_game_over(score)

# 计算两个角度之间的最小差值（考虑循环）
func angle_difference(angle1: float, angle2: float) -> float:
	var diff = fmod(angle1 - angle2 + 3 * PI, 2 * PI) - PI
	return diff

# 更新拖动的视觉效果
func update_drag_visuals():
	if selected_ring == -1:
		return
		
	# 更新高亮环的旋转
	if selected_ring < ring_highlights.size():
		ring_highlights[selected_ring].rotation = drag_rotation
		
	# 更新环上所有点的位置
	for angle_index in num_angles:
		for radius_index in num_radii:
			if radius_index == selected_ring and all_dots[angle_index][radius_index] != null:
				var dot = all_dots[angle_index][radius_index]
				var angle_step = 2 * PI / num_angles
				
				# 计算点的基础角度
				var base_angle = angle_index * angle_step
				
				# 计算实际旋转后的角度，应用当前拖动值
				# 反转旋转方向以修复拖动方向问题
				var rotated_angle = base_angle + drag_rotation
				
				var radius = base_radius + (radius_index * spacing)
				var x = cos(rotated_angle) * radius
				var y = sin(rotated_angle) * radius
				dot.position = Vector2(x, y) + center
