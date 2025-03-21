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

# 音效资源预加载
@onready var sound_match_basic = preload("res://Assets/Music/消除个数-基础.mp3")
@onready var sound_match_basic_1 = preload("res://Assets/Music/消除个数-基础+1.mp3")
@onready var sound_match_basic_2 = preload("res://Assets/Music/消除个数-基础+2.mp3") 
@onready var sound_rating_1 = preload("res://Assets/Music/消除评价-1级.mp3")
@onready var sound_rating_2 = preload("res://Assets/Music/消除评价-2级.mp3")

# 音效播放相关变量
var total_match_chains = 0  # 总消除次数，用于评价音效

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

# 直径拖动相关变量
var diameter_drag_active: bool = false
var diameter_drag_start_position: Vector2
var diameter_drag_offset: float = 0.0
var diameter_original_positions = {}  # 存储点的原始位置
var diameter_original_index = 0  # 拖动开始时的位置索引
var diameter_snapping: bool = false
var diameter_snap_target = 0  # 吸附目标位置
var diameter_snap_progress: float = 0.0
var diameter_points = [] # 存储当前直径上所有点的数组
var diameter_dragging_clockwise = false # 拖动方向
var diameter_target_positions = [] # 目标位置
var diameter_steps = 0 # 移动的格数

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

# 分数系统参数
@export var base_score: int = 10  # 圆点的基础分值
@export var extra_score_base: int = 10  # 额外消除加成的基础分值
@export var min_match_count: int = 4  # 最少消除个数
@export var chain_bonus_base: int = 50  # 连锁奖励基础值
var chain_match_count = 0  # 连锁消除计数

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
	# 环的吸附动画
	if snapping_to_index:
		snap_progress += delta * snap_speed
		if snap_progress >= 1.0:
			snap_progress = 1.0
			snapping_to_index = false
			
			# 更新最终位置
			ring_angle_indices[selected_ring] = int(round(drag_rotation / (2 * PI / num_angles))) % num_angles
			if ring_angle_indices[selected_ring] < 0:
				ring_angle_indices[selected_ring] += num_angles
				
			# 消除匹配
			check_all_matches()
			if remaining_moves <= 0:
				state = wait
			else:
				state = move
		
		# 更新旋转角度
		drag_rotation = lerp_angle(drag_rotation, snap_target_angle, snap_progress)
		update_drag_visuals()
	
	# 直径的吸附动画
	if diameter_snapping:
		update_diameter_snap(delta)

func _input(event):
	if state == wait or is_rotating or is_diameter_moving:
		return
		
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_TAB:  # 使用Tab键切换模式
			toggle_selection_mode()
	
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 鼠标按下，只选择环或直径而不开始拖动
				if current_mode == ring_mode:
					var clicked_ring = get_ring_at_position(event.position)
					if clicked_ring != -1:
						select_ring(clicked_ring)
				else:  # diameter_mode
					var clicked_diameter = get_diameter_at_position(event.position)
					if clicked_diameter != -1:
						select_diameter(clicked_diameter)
			else:
				# 鼠标释放
				if is_dragging and current_mode == ring_mode:
					end_ring_drag(event.position)
				elif diameter_drag_active and current_mode == diameter_mode:
					end_diameter_drag()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# 右键取消拖动
			print("右键取消拖动尝试：is_dragging=", is_dragging, ", diameter_drag_active=", diameter_drag_active)
			if is_dragging and current_mode == ring_mode:
				cancel_ring_drag()
			elif diameter_drag_active and current_mode == diameter_mode:
				cancel_diameter_drag()
	
	elif event is InputEventMouseMotion:
		# 鼠标移动时才开始拖动
		if event.button_mask == MOUSE_BUTTON_MASK_LEFT:
			if current_mode == ring_mode and selected_ring != -1:
				if !is_dragging:
					# 首次移动时开始拖动
					start_ring_drag(event.position)
				else:
					update_ring_drag(event.position)
			elif current_mode == diameter_mode and selected_diameter != -1:
				if !diameter_drag_active:
					# 首次移动时开始拖动直径
					start_diameter_drag(event.position)
				else:
					update_diameter_drag(event.position)

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
	
	# 重置连锁计数
	chain_match_count = 0
	
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

# 修改check_match函数返回匹配的点数组而不是布尔值
func check_match(angle_index: int, radius_index: int) -> Array:
	if all_dots[angle_index][radius_index] == null:
		return []
	
	var current_dot = all_dots[angle_index][radius_index]
	if current_dot.color == "gray":  # 灰色点不参与匹配
		return []
	
	var color_to_match = current_dot.color
	var matched_dots = []
	
	# 规则1: 同一条半径上有4个同色点才消除（角度索引一致，环数为0,1,2,3）
	var radius_dots = []
	# 只检查当前点所在的角度
	if radius_index < num_radii:  # 确保是有效的环索引
		var all_radius_dots_present = true
		for r in range(num_radii):
			if all_dots[angle_index][r] == null or all_dots[angle_index][r].color != color_to_match:
				all_radius_dots_present = false
				break
			radius_dots.append(all_dots[angle_index][r])
		
		# 只有当该半径上所有点都是同色的才匹配
		if all_radius_dots_present and radius_dots.size() == num_radii:
			for d in radius_dots:
				d.matched = true
				if not matched_dots.has(d):
					matched_dots.append(d)
	
	# 规则2: 同一环上有4个或更多连续同色点才消除（环数一致，角度索引连续，或0和num_angles-1连续）
	var ring_dots = []
	# 检查当前点的相邻点
	var a_prev = (angle_index - 1 + num_angles) % num_angles
	var a_next = (angle_index + 1) % num_angles
	
	# 将当前点加入环点列表
	ring_dots.append(current_dot)
	
	# 向前检查连续点
	var current_a = a_prev
	while true:
		if all_dots[current_a][radius_index] != null and all_dots[current_a][radius_index].color == color_to_match:
			ring_dots.insert(0, all_dots[current_a][radius_index])
			current_a = (current_a - 1 + num_angles) % num_angles
			# 如果绕了一圈回到起点，停止检查
			if current_a == angle_index:
				break
		else:
			break
	
	# 向后检查连续点
	current_a = a_next
	while true:
		if all_dots[current_a][radius_index] != null and all_dots[current_a][radius_index].color == color_to_match:
			ring_dots.append(all_dots[current_a][radius_index])
			current_a = (current_a + 1) % num_angles
			# 如果绕了一圈回到起点，停止检查
			if current_a == angle_index:
				break
		else:
			break
	
	# 检查是否有足够的连续点
	if ring_dots.size() >= min_match_count:
		for d in ring_dots:
			d.matched = true
			if not matched_dots.has(d):
				matched_dots.append(d)
	
	return matched_dots

# 优化check_all_matches函数，收集所有匹配点
func check_all_matches():
	var all_matched_dots = []
	var was_matched = false
	
	# 检查所有位置的匹配
	for angle_index in num_angles:
		for radius_index in num_radii:
			if all_dots[angle_index][radius_index] != null:
				var matched_dots = check_match(angle_index, radius_index)
				if matched_dots.size() > 0:
					was_matched = true
					# 添加唯一的匹配点
					for dot in matched_dots:
						if not all_matched_dots.has(dot):
							all_matched_dots.append(dot)
	
	# 一次性计算所有匹配点的分数
	if was_matched:
		calculate_score(all_matched_dots, chain_match_count)
		destroy_timer.start()
		
		# 检查关卡目标
		check_level_target()
		
		if game_mode == PUZZLE_MODE:
			check_level_complete()
	
	return was_matched

# 统一的分数计算函数
func calculate_score(matched_dots: Array, current_chain: int):
	if matched_dots.size() <= 0:
		return
	
	# 计算得分
	var points_count = matched_dots.size()
	var base_points = base_score * points_count
	var extra_points = extra_score_base * max(0, points_count - min_match_count)
	var chain_bonus = chain_bonus_base * (current_chain * current_chain)
	var total_score = base_points + extra_points + chain_bonus
	
	# 打印详细得分信息
	print("消除 %d 个圆点 (连锁次数 = %d)" % [points_count, current_chain])
	print("基础得分 = %d × %d = %d" % [base_score, points_count, base_points])
	print("额外消除加成 = %d × (%d - %d) = %d" % [extra_score_base, points_count, min_match_count, extra_points])
	print("连锁消除加成 = %d × (%d的平方) = %d" % [chain_bonus_base, current_chain, chain_bonus])
	print("总得分 = %d + %d + %d = %d" % [base_points, extra_points, chain_bonus, total_score])
	
	# 更新总分
	score += total_score
	print("消除得分: %d, 总分: %d" % [total_score, score])
	
	# 播放个数音效
	play_match_sound(points_count, current_chain)
	
	# 增加总消除次数
	total_match_chains += 1
	
	# 在消除完成后，增加连锁计数
	chain_match_count += 1

# 添加播放消除音效的函数
func play_match_sound(points_count: int, current_chain: int):
	var sound_to_play = null
	
	# 确定要播放的个数音效
	# 优先级：连锁 > 点数多少
	
	# 连锁消除逻辑
	if current_chain >= 2:
		sound_to_play = sound_match_basic_2
	elif current_chain == 1:
		sound_to_play = sound_match_basic_1
	# 非连锁消除，根据点数判断
	elif points_count > min_match_count * 2:
		sound_to_play = sound_match_basic_2
	elif points_count > min_match_count:
		sound_to_play = sound_match_basic_1
	else:
		sound_to_play = sound_match_basic
	
	# 播放音效
	if sound_to_play:
		var audio_player = AudioStreamPlayer.new()
		audio_player.stream = sound_to_play
		add_child(audio_player)
		audio_player.play()
		
		# 播放完成后自动移除
		await audio_player.finished
		audio_player.queue_free()

# 在所有消除和检查完成后，重置连锁计数
func destroy_matches():
	# 收集所有匹配的点
	var matched_dots = []
	for angle_index in num_angles:
		for radius_index in num_radii:
			if all_dots[angle_index][radius_index] != null:
				if all_dots[angle_index][radius_index].matched:
					matched_dots.append(all_dots[angle_index][radius_index])
	
	# 删除匹配的点
	for dot in matched_dots:
		dot.queue_free()
		
		# 从数组中移除
		for angle_index in num_angles:
			for radius_index in num_radii:
				if all_dots[angle_index][radius_index] == dot:
					all_dots[angle_index][radius_index] = null
	
	if matched_dots.size() > 0:
		collapse_timer.start()
		update_ui()
	else:
		state = move
		# 重置连锁计数
		chain_match_count = 0
		# 重置总消除次数
		total_match_chains = 0

func collapse_columns():
	# 在解谜模式中，将点向外移动填补空位
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
				if game_mode == puzzle_mode:
					# 解谜模式下填充灰色点
					var dot = gray_dot.instantiate()
					add_child(dot)
					# 设置初始位置在圆心
					dot.position = center
					# 移动到目标位置
					dot.move(grid_to_pixel(angle_index, radius_index))
					all_dots[angle_index][radius_index] = dot
					refilled = true
				else:
					# 无限模式下填充彩色点
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
			# 没有新的匹配，播放评价音效
			if total_match_chains > 0:  # 只有在有消除发生时才播放评价音效
				play_rating_sound()
			state = move
			# 重置连锁计数和总消除次数
			chain_match_count = 0
			total_match_chains = 0
	else:
		# 没有填充新的点，说明消除已经完全结束
		if total_match_chains > 0:  # 只有在有消除发生时才播放评价音效
			play_rating_sound()
		state = move
		# 重置连锁计数和总消除次数
		chain_match_count = 0
		total_match_chains = 0

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

func move_diameter_clockwise_direct():
	if selected_diameter == -1:
		return
	
	# 计算直径两端的角度索引
	var angle_index1 = selected_diameter
	var angle_index2 = (selected_diameter + num_angles / 2) % num_angles
	
	# 创建临时数组存储所有点的引用
	var temp_dots = []
	for radius_index in num_radii:
		temp_dots.append(all_dots[angle_index1][radius_index])
	
	# 1. 将angle_index1方向的点向外移动一步
	for radius_index in range(num_radii - 1, 0, -1):
		all_dots[angle_index1][radius_index] = all_dots[angle_index1][radius_index - 1]
	
	# 2. 将angle_index2末端的点移到angle_index1的开头
	all_dots[angle_index1][0] = all_dots[angle_index2][num_radii - 1]
	
	# 3. 将angle_index2方向的点向内移动一步
	for radius_index in range(num_radii - 1):
		all_dots[angle_index2][radius_index] = all_dots[angle_index2][radius_index + 1]
	
	# 4. 将angle_index1末端的点移到angle_index2的末端
	all_dots[angle_index2][num_radii - 1] = temp_dots[num_radii - 1]
	
	# 更新所有移动点的位置
	for radius_index in range(num_radii):
		if all_dots[angle_index1][radius_index] != null:
			var radius = base_radius + radius_index * spacing
			var angle = angle_index1 * (2 * PI / num_angles)
			all_dots[angle_index1][radius_index].position = Vector2(cos(angle) * radius, sin(angle) * radius) + center
		
		if all_dots[angle_index2][radius_index] != null:
			var radius = base_radius + radius_index * spacing
			var angle = angle_index2 * (2 * PI / num_angles)
			all_dots[angle_index2][radius_index].position = Vector2(cos(angle) * radius, sin(angle) * radius) + center

func move_diameter_counter_clockwise_direct():
	if selected_diameter == -1:
		return
	
	# 计算直径两端的角度索引
	var angle_index1 = selected_diameter
	var angle_index2 = (selected_diameter + num_angles / 2) % num_angles
	
	# 创建临时数组存储所有点的引用
	var temp_dots = []
	for radius_index in num_radii:
		temp_dots.append(all_dots[angle_index1][radius_index])
	
	# 1. 将angle_index1方向的点向内移动一步
	for radius_index in range(num_radii - 1):
		all_dots[angle_index1][radius_index] = all_dots[angle_index1][radius_index + 1]
	
	# 2. 将angle_index2开头的点移到angle_index1的末端
	all_dots[angle_index1][num_radii - 1] = all_dots[angle_index2][0]
	
	# 3. 将angle_index2方向的点向外移动一步
	for radius_index in range(1, num_radii):
		all_dots[angle_index2][radius_index - 1] = all_dots[angle_index2][radius_index]
	
	# 4. 将angle_index1开头的点移到angle_index2的开头
	all_dots[angle_index2][num_radii - 1] = temp_dots[0]
	
	# 更新所有移动点的位置
	for radius_index in range(num_radii):
		if all_dots[angle_index1][radius_index] != null:
			var radius = base_radius + radius_index * spacing
			var angle = angle_index1 * (2 * PI / num_angles)
			all_dots[angle_index1][radius_index].position = Vector2(cos(angle) * radius, sin(angle) * radius) + center
		
		if all_dots[angle_index2][radius_index] != null:
			var radius = base_radius + radius_index * spacing
			var angle = angle_index2 * (2 * PI / num_angles)
			all_dots[angle_index2][radius_index].position = Vector2(cos(angle) * radius, sin(angle) * radius) + center

# 开始直径拖动
func start_diameter_drag(position: Vector2):
	if selected_diameter == -1 or state != move:
		return
	
	print("开始直径拖动 - 直径索引:", selected_diameter)
	
	# 完全重置所有拖动状态
	diameter_drag_active = true
	diameter_drag_start_position = position
	diameter_drag_offset = 0.0
	diameter_snapping = false
	diameter_snap_progress = 0.0
	diameter_snap_target = 0
	diameter_steps = 0
	diameter_points.clear()
	diameter_target_positions.clear()
	
	# 清理并记录点的原始位置
	diameter_original_positions.clear()
	
	# 计算直径两端的角度索引
	var angle_index1 = selected_diameter  # 3点钟方向
	var angle_index2 = (selected_diameter + num_angles / 2) % num_angles  # 9点钟方向
	
	print("直径端点角度索引: ", angle_index1, "点钟和", angle_index2, "点钟")
	
	# 收集直径上所有点并记录它们的位置
	# 按照指定的循环顺序排列: [第1层-3点, 第2层-3点, 第3层-3点, 第4层-3点, 第4层-9点, 第3层-9点, 第2层-9点, 第1层-9点]
	
	# 首先添加3点钟方向的点（从内到外）
	for radius_index in range(num_radii):
		if all_dots[angle_index1][radius_index] != null:
			diameter_points.append({
				"dot": all_dots[angle_index1][radius_index],
				"position": all_dots[angle_index1][radius_index].position,
				"angle_index": angle_index1,
				"radius_index": radius_index,
				"end": 0,  # 0表示3点钟端
				"label": "第" + str(radius_index + 1) + "层-" + str(angle_index1) + "点"
			})
			diameter_original_positions[Vector2(angle_index1, radius_index)] = all_dots[angle_index1][radius_index].position
	
	# 然后添加9点钟方向的点（从外到内）
	for radius_index in range(num_radii - 1, -1, -1):
		if all_dots[angle_index2][radius_index] != null:
			diameter_points.append({
				"dot": all_dots[angle_index2][radius_index],
				"position": all_dots[angle_index2][radius_index].position,
				"angle_index": angle_index2,
				"radius_index": radius_index,
				"end": 1,  # 1表示9点钟端
				"label": "第" + str(radius_index + 1) + "层-" + str(angle_index2) + "点"
			})
			diameter_original_positions[Vector2(angle_index2, radius_index)] = all_dots[angle_index2][radius_index].position
	
	# 计算所有可能的目标位置（用于动画）
	diameter_target_positions = calculate_all_diameter_positions()
	
	print("直径上找到", diameter_points.size(), "个点")
	for i in range(diameter_points.size()):
		print("点", i, ": ", diameter_points[i].label)

# 计算直径上所有可能的位置
func calculate_all_diameter_positions() -> Array:
	var positions = []
	var angle_index1 = selected_diameter  # 3点钟方向
	var angle_index2 = (selected_diameter + num_angles / 2) % num_angles  # 9点钟方向
	
	# 添加3点钟方向的位置（从内到外）
	for radius_index in range(num_radii):
		var pos = Vector2(
			center.x + cos(angle_index1 * (2 * PI / num_angles)) * (base_radius + radius_index * spacing),
			center.y + sin(angle_index1 * (2 * PI / num_angles)) * (base_radius + radius_index * spacing)
		)
		positions.append({
			"position": pos,
			"angle_index": angle_index1,
			"radius_index": radius_index
		})
	
	# 添加9点钟方向的位置（从外到内）
	for radius_index in range(num_radii - 1, -1, -1):
		var pos = Vector2(
			center.x + cos(angle_index2 * (2 * PI / num_angles)) * (base_radius + radius_index * spacing),
			center.y + sin(angle_index2 * (2 * PI / num_angles)) * (base_radius + radius_index * spacing)
		)
		positions.append({
			"position": pos,
			"angle_index": angle_index2,
			"radius_index": radius_index
		})
	
	return positions

# 更新直径的拖动
func update_diameter_drag(position: Vector2):
	if !diameter_drag_active or selected_diameter == -1:
		return
	
	# 如果原始位置为空，中止拖动
	if diameter_original_positions.size() == 0 or diameter_points.size() == 0:
		diameter_drag_active = false
		return
	
	# 计算直径的方向向量（使用沿着直径的矢量，而不是垂直矢量）
	var diameter_angle = selected_diameter * (2 * PI / num_angles)
	var diameter_vector = Vector2(cos(diameter_angle), sin(diameter_angle))  # 沿直径的向量
	
	# 计算鼠标移动向量
	var drag_vector = position - diameter_drag_start_position
	
	# 计算拖动向量在垂直于直径方向的投影
	# 使用叉积计算垂直方向的移动量（2D叉积返回一个标量）
	var dot_product = diameter_vector.dot(drag_vector)
	var drag_projection = dot_product  # 正值表示向一个方向，负值表示向另一个方向
	
	# 设置拖动偏移量
	diameter_drag_offset = drag_projection
	
	# 计算应该移动的格数
	var drag_distance = abs(diameter_drag_offset)
	var threshold = spacing * 0.5  # 移动一格的阈值，调低使拖动更敏感
	var steps = int(floor(drag_distance / threshold))
	if steps >= diameter_points.size():
		steps = steps % diameter_points.size()
	
	# 只有当步数变化时才更新和打印
	if steps != diameter_steps or diameter_dragging_clockwise != (drag_projection > 0):
		diameter_steps = steps
		diameter_dragging_clockwise = drag_projection > 0  # 根据投影方向确定顺时针/逆时针
		
		if steps > 0:
			print("拖动: ", "顺时针" if diameter_dragging_clockwise else "逆时针", "移动", steps, "格")
			
			var direction_text = "向下" if diameter_dragging_clockwise else "向上"
			print("拖动", direction_text, "- 3点钟端向", "外" if diameter_dragging_clockwise else "内", "移动，9点钟端向", "内" if diameter_dragging_clockwise else "外", "移动")
	
	# 更新视觉效果，传递拖动进度以获得更平滑的动画
	var progress = min(1.0, fmod(drag_distance, threshold) / threshold)
	preview_diameter_movement(steps, diameter_dragging_clockwise, progress)

# 预览直径移动效果（平滑动画，但不改变数据）
func preview_diameter_movement(steps: int, is_clockwise: bool, progress: float = 0.0):
	if diameter_points.size() == 0 or diameter_target_positions.size() == 0:
		return
	
	# 如果没有实际移动
	if steps == 0:
		# 恢复所有点到原始位置
		for point in diameter_points:
			point.dot.position = point.position
		return
	
	# 计算每个点的新位置
	for i in range(diameter_points.size()):
		var point = diameter_points[i]
		var dot = point.dot
		
		# 计算当前步数的目标索引
		var current_target_index
		if is_clockwise:
			current_target_index = (i + steps) % diameter_points.size()
		else:
			current_target_index = (i - steps + diameter_points.size()) % diameter_points.size()
		
		# 计算下一步的目标索引（用于插值）
		var next_target_index
		if is_clockwise:
			next_target_index = (i + steps + 1) % diameter_points.size()
		else:
			next_target_index = (i - steps - 1 + diameter_points.size()) % diameter_points.size()
		
		# 获取当前步数目标位置
		var current_target_position = diameter_target_positions[current_target_index].position
		
		# 如果没有下一步，直接使用当前目标
		if steps == diameter_points.size() - 1:
			dot.position = current_target_position
		else:
			# 获取下一步目标位置
			var next_target_position = diameter_target_positions[next_target_index].position
			
			# 在当前目标和下一步目标之间进行插值
			dot.position = lerp(current_target_position, next_target_position, progress)

# 完成直径移动（更新数组）
func finalize_diameter_movement():
	if diameter_points.size() == 0 or diameter_target_positions.size() == 0:
		return
	
	print("完成直径移动: ", "顺时针" if diameter_dragging_clockwise else "逆时针", "移动", diameter_steps, "格")
	
	# 创建新的点数组
	var new_dots = []
	for i in range(diameter_points.size()):
		new_dots.append(null)
	
	# 计算每个点的新位置
	for i in range(diameter_points.size()):
		var target_index
		if diameter_dragging_clockwise:
			target_index = (i + diameter_steps) % diameter_points.size()
		else:
			target_index = (i - diameter_steps + diameter_points.size()) % diameter_points.size()
		
		# 放到新数组中
		new_dots[target_index] = diameter_points[i].dot
	
	# 更新数组和位置
	for i in range(diameter_points.size()):
		var target_pos_data = diameter_target_positions[i]
		var angle_index = target_pos_data.angle_index
		var radius_index = target_pos_data.radius_index
		
		# 更新all_dots数组
		all_dots[angle_index][radius_index] = new_dots[i]
		
		# 更新点的位置
		if new_dots[i] != null:
			new_dots[i].position = target_pos_data.position
			
	# 打印更新后的点位置
	print("更新后的点位置:")
	for i in range(num_angles):
		for j in range(num_radii):
			if all_dots[i][j] != null:
				print("第", j+1, "层-", i, "点: ", all_dots[i][j].color)

# 更新直径吸附动画
func update_diameter_snap(delta):
	if !diameter_snapping:
		return
	
	diameter_snap_progress += delta * snap_speed
	if diameter_snap_progress >= 1.0:
		# 动画完成
		diameter_snap_progress = 1.0
		diameter_snapping = false
		
		# 实际执行点的移动（更新数组）
		finalize_diameter_movement()
		
		# 动画完成后清理状态
		diameter_points.clear()
		diameter_target_positions.clear()
		diameter_original_positions.clear()
		
		# 扣除步数并检查消除
		if diameter_snap_target != 0:
			print("扣除一步，剩余步数: ", remaining_moves - 1)
			remaining_moves -= 1
			update_ui()
			check_all_matches()
		
		if remaining_moves <= 0:
			state = wait
		else:
			state = move
	else:
		# 更新动画
		for i in range(diameter_points.size()):
			var point = diameter_points[i]
			var dot = point.dot
			
			# 计算目标索引
			var target_index
			if diameter_dragging_clockwise:
				target_index = (i + diameter_steps) % diameter_points.size()
			else:
				target_index = (i - diameter_steps + diameter_points.size()) % diameter_points.size()
			
			# 平滑移动到目标位置
			var target_position = diameter_target_positions[target_index].position
			dot.position = lerp(point.position, target_position, diameter_snap_progress)

# 结束直径拖动
func end_diameter_drag():
	if !diameter_drag_active or selected_diameter == -1:
		return
	
	print("结束直径拖动 - 步数:", diameter_steps, "方向:", "顺时针" if diameter_dragging_clockwise else "逆时针")
	
	# 重置连锁计数
	chain_match_count = 0
	
	diameter_drag_active = false
	diameter_snapping = true
	diameter_snap_progress = 0.0
	
	# 如果没有实际移动
	if diameter_steps == 0:
		print("没有移动，恢复原始位置")
		# 恢复所有点到原始位置
		for point in diameter_points:
			point.dot.position = point.position
		
		# 清理状态
		diameter_original_positions.clear()
		diameter_points.clear()
		diameter_target_positions.clear()
		return
	
	# 确定最终的移动步数和方向
	diameter_snap_target = diameter_steps if diameter_dragging_clockwise else -diameter_steps
	print("最终移动目标: ", diameter_snap_target, "单位")
	
	# 在移动完成后才会进行后续处理（在snapping动画结束时）

func update_ring_highlights():
	for i in range(num_radii):
		ring_highlights[i].visible = (i == selected_ring)

func update_diameter_highlights():
	for i in range(num_radii, ring_highlights.size()):
		ring_highlights[i].visible = (i - num_radii == selected_diameter)

func check_level_complete():
	# 对于前两关，检查所有指定颜色的点是否都被消除
	var level_complete = false
	
	if current_level <= 3:
		# 前3关使用消除全部点的完成条件
		level_complete = true
		for angle_index in num_angles:
			for radius_index in num_radii:
				var dot = all_dots[angle_index][radius_index]
				if dot != null and dot.color != "gray" and not dot.matched:
					level_complete = false
					break
	else:
		# 第4关及以后使用分数目标作为完成条件
		var target_score = 20 * current_level  # 根据当前关卡级别设定目标分数
		if score >= target_score:
			level_complete = true
	
	if level_complete:
		# 显示关卡完成UI
		if ui:
			ui.show_level_complete()
			
		# 重要：不在这里设置Global的关卡号
		# 由_on_next_level_button_pressed函数处理

# 检查是否达成关卡目标
func check_level_target():
	if game_mode == PUZZLE_MODE:
		# 对于前两关，使用消除全部点的机制，已由check_level_complete处理
		if current_level <= 2:
			return
		
		# 第3关及以后，使用分数目标机制
		var target_score = 0
		
		# 读取关卡数据获取目标分数
		if level_data and level_data.has("description"):
			var description = level_data["description"]
			# 尝试从描述中解析目标分数
			var regex = RegEx.new()
			regex.compile("\\d+")
			var result = regex.search(description)
			if result:
				target_score = int(result.get_string())
		
		# 如果没有找到目标分数，使用默认公式
		if target_score == 0:
			target_score = 40 * current_level
		
		print("当前分数: %d, 目标分数: %d" % [score, target_score])
		
		# 检查是否达到目标分数
		if score >= target_score:
			# 不在这里调用show_level_complete，由check_level_complete处理
			# 仅检查是否达到目标分数并设置标记
			check_level_complete()
	elif game_mode == ENDLESS_MODE:
		# 无限模式下的目标检测
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

# 取消环的拖动
func cancel_ring_drag():
	if !is_dragging or selected_ring == -1:
		return
		
	print("取消环拖动 - 执行中")
	
	# 重置拖动状态
	is_dragging = false
	snapping_to_index = false
	
	# 重置拖动旋转到开始时的值
	drag_rotation = drag_start_rotation
	
	# 恢复原始位置
	update_all_dots_positions(true)
	
	# 状态恢复为可移动
	state = move
	
	print("环拖动已取消，点位已重置")

# 取消直径拖动
func cancel_diameter_drag():
	if !diameter_drag_active or selected_diameter == -1:
		return
		
	print("取消直径拖动")
	
	diameter_drag_active = false
	diameter_snapping = false
	
	# 恢复所有点到原始位置
	for point in diameter_points:
		point.dot.position = point.position
	
	# 清理状态
	diameter_original_positions.clear()
	diameter_points.clear()
	diameter_target_positions.clear()
	
	# 恢复状态
	state = move

# 添加播放评价音效的函数
func play_rating_sound():
	var sound_to_play = null
	
	# 根据总消除次数决定评价等级
	if total_match_chains >= 2:
		sound_to_play = sound_rating_2
	elif total_match_chains == 1:
		sound_to_play = sound_rating_1
	
	# 播放音效
	if sound_to_play:
		var audio_player = AudioStreamPlayer.new()
		audio_player.stream = sound_to_play
		add_child(audio_player)
		audio_player.play()
		
		# 播放完成后自动移除
		await audio_player.finished
		audio_player.queue_free()
