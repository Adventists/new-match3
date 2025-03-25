extends Node

# 背景音乐播放器
var current_bgm: AudioStreamPlayer

# 预加载音乐资源
@onready var bgm1 = preload("res://Assets/Music/bgm1.mp3")

# 播放背景音乐
func play_bgm(stream: AudioStream = null, fade_duration: float = 1.0):
	# 如果没有指定音乐，使用默认的bgm1
	if stream == null:
		stream = bgm1
	
	# 如果当前有音乐在播放，先淡出
	if current_bgm:
		var fade_out = create_tween()
		fade_out.tween_property(current_bgm, "volume_db", -80, fade_duration)
		await fade_out.finished
		current_bgm.stop()
		current_bgm.queue_free()
	
	# 创建新的音乐播放器
	current_bgm = AudioStreamPlayer.new()
	current_bgm.stream = stream
	current_bgm.volume_db = -80  # 从静音开始
	add_child(current_bgm)
	current_bgm.play()
	
	# 淡入新音乐
	var fade_in = create_tween()
	fade_in.tween_property(current_bgm, "volume_db", -10, fade_duration)

# 停止背景音乐
func stop_bgm(fade_duration: float = 1.0):
	if current_bgm:
		var fade_out = create_tween()
		fade_out.tween_property(current_bgm, "volume_db", -80, fade_duration)
		await fade_out.finished
		current_bgm.stop()
		current_bgm.queue_free()
		current_bgm = null 