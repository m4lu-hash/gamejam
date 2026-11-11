extends SceneTree
## 临时测试脚本（验证完即删）：噪声合成旁白 voice_synth.gd

const VOICE_PATH := "res://scripts/audio/voice_synth.gd"

var _fail := 0


func _initialize() -> void:
	var script: Script = load(VOICE_PATH)
	if script == null:
		printerr("FAIL: 无法加载 %s" % VOICE_PATH)
		quit(1)
		return

	var t0 := Time.get_ticks_usec()
	var voice: Node = script.new()
	root.add_child(voice)
	# _initialize 阶段 root 尚未跑 _ready，手动建表并计时
	voice.call("_build_tables")
	var boot_us := Time.get_ticks_usec() - t0
	print("初始化（建噪声表/正弦表）耗时: %.2f ms" % (boot_us / 1000.0))

	var noise_table: PackedFloat32Array = voice.get("_noise_table")
	print("噪声表: N=%d  首值=%.6f  末值=%.6f  表哈希=%d" % [
		noise_table.size(), noise_table[0], noise_table[noise_table.size() - 1], hash(noise_table)
	])
	_check(noise_table.size() == 4096, "噪声表长度应为 4096")
	var in_range := true
	for v in noise_table:
		if v < 0.0 or v > 1.0:
			in_range = false
			break
	_check(in_range, "噪声表值域应在 0..1")

	# ---------- 1. 参数检查 ----------
	print("\n=== 1. WAV 参数 ===")
	var s1: AudioStreamWAV = voice.synthesize("测试旁白")
	print("format=%d mix_rate=%d stereo=%s data=%d 字节 长度=%.3fs" % [
		s1.format, s1.mix_rate, str(s1.stereo), s1.data.size(), s1.get_length()
	])
	_check(s1.format == AudioStreamWAV.FORMAT_16_BITS, "应为 16-bit PCM")
	_check(s1.mix_rate == 22050, "采样率应为 22050")
	_check(s1.stereo == false, "应为单声道")
	_check(s1.data.size() % 2 == 0, "字节数应为 2 的倍数（16-bit）")

	# ---------- 2. 同文本两次生成是否完全一致（绕过缓存）----------
	print("\n=== 2. 同文本两次合成一致性 ===")
	var text_same := "测试一下旁白，一二三四五六七八九十。"
	var a: AudioStreamWAV = voice.synthesize(text_same)
	var a_hash := hash(a.data)
	var a_size := a.data.size()
	voice.clear_cache()
	var b: AudioStreamWAV = voice.synthesize(text_same)
	var b_hash := hash(b.data)
	var b_size := b.data.size()
	var same_bytes := _bytes_equal(a.data, b.data)
	print("第一次: %d 字节  hash=%d" % [a_size, a_hash])
	print("第二次: %d 字节  hash=%d" % [b_size, b_hash])
	print("字节数一致: %s   字节内容逐字节一致: %s" % [str(a_size == b_size), str(same_bytes)])
	_check(a_size == b_size, "两次合成字节数应一致")
	_check(a_hash == b_hash, "两次合成哈希应一致")
	_check(same_bytes, "两次合成内容应逐字节一致")
	_check(a_size > 0, "WAV 字节数应 > 0")
	print("speak 目标句长度: %.3fs" % (a.get_length()))

	# ---------- 3. 不同字符结果不同 ----------
	print("\n=== 3. 不同字符 -> 不同音频 ===")
	for pair in [["啊", "哦"], ["一", "九"], ["A", "Z"], ["呢", "吧"]]:
		var ga: AudioStreamWAV = voice.synthesize(pair[0])
		var gb: AudioStreamWAV = voice.synthesize(pair[1])
		var la := ga.data.size() / 2.0 / 22050.0
		var lb := gb.data.size() / 2.0 / 22050.0
		var diff := not _bytes_equal(ga.data, gb.data)
		print("'%s' vs '%s': %.3fs(%dB) / %.3fs(%dB) 内容不同=%s 频率=%.1f/%.1fHz" % [
			pair[0], pair[1], la, ga.data.size(), lb, gb.data.size(), str(diff),
			voice.get_char_freq(pair[0].unicode_at(0)), voice.get_char_freq(pair[1].unicode_at(0))
		])
		_check(diff, "不同字符 '%s' 与 '%s' 的音频应不同" % [pair[0], pair[1]])

	# ---------- 4. speak 不报错 ----------
	print("\n=== 4. speak() ===")
	voice.speak("测试一下旁白，一二三四五六七八九十。")
	var player: AudioStreamPlayer = voice.get("_player")
	var playing_stream: AudioStreamWAV = player.stream
	print("speak 后: playing=%s  stream_data=%d 字节  长度=%.3fs  pitch=%.2f" % [
		str(voice.is_speaking()), playing_stream.data.size(), playing_stream.get_length(),
		voice.get_pitch_scale()
	])
	_check(playing_stream != null and playing_stream.data.size() > 0, "speak 后应有有效 WAV")
	_check(voice.is_speaking(), "speak 后应处于播放状态")

	voice.set_pitch_scale(1.5)
	_check(is_equal_approx(player.pitch_scale, 1.5), "pitch_scale 应传到播放器")
	voice.set_muted(true)
	_check(voice.is_muted() and not voice.is_speaking(), "静音后应停止播放")
	voice.set_muted(false)
	voice.speak("测试一下旁白，一二三四五六七八九十。")
	_check(voice.is_speaking(), "取消静音后应能继续播")
	voice.set_pitch_scale(1.0)
	voice.stop()
	_check(not voice.is_speaking(), "stop() 后应停止")

	# 缓存：同文本第二次不应重复合成
	voice.clear_cache()
	voice.synthesize("缓存测试")
	voice.synthesize("缓存测试")
	_check(voice.get_cache_size() == 1, "同文本应只缓存一条")

	# ---------- 5. 性能：100 字 ----------
	print("\n=== 5. 性能（100 字）===")
	var long_text: String = "这是一段用于测试噪声合成旁白速度的文本请问它到底有多快呢".repeat(4).substr(0, 100)
	print("测试文本长度: %d 字" % long_text.length())
	var times: Array[float] = []
	var last_stream: AudioStreamWAV = null
	for i in 3:
		voice.clear_cache()
		var t := Time.get_ticks_usec()
		last_stream = voice.synthesize(long_text)
		var us := Time.get_ticks_usec() - t
		times.append(us / 1000.0)
		print("第 %d 次（冷缓存）: %.2f ms" % [i + 1, us / 1000.0])
	var t_cache := Time.get_ticks_usec()
	voice.synthesize(long_text)
	var cache_us := Time.get_ticks_usec() - t_cache
	print("命中缓存: %.3f ms" % (cache_us / 1000.0))
	print("音频长度: %.3fs  %d 字节" % [last_stream.get_length(), last_stream.data.size()])
	_check(times.min() < 50.0, "100 字冷合成应 < 50ms（实测最小 %.2fms）" % times.min())

	# ---------- 6. 20 秒上限 ----------
	print("\n=== 6. 时长上限 ===")
	var huge := "超长旁白压力测试文本".repeat(60)
	var huge_stream: AudioStreamWAV = voice.synthesize(huge)
	print("输入 %d 字 -> %.3fs（上限 %.1fs）" % [huge.length(), huge_stream.get_length(), 20.0])
	_check(huge_stream.get_length() <= 20.0 + 0.001, "总时长应被截断到 20 秒内")

	# ---------- 汇总 ----------
	print("\n固定句子 PCM 哈希（用于跨进程比对）: %d" % hash(voice.synthesize("跨进程一致性").data))
	if _fail == 0:
		print("\n全部通过")
		quit(0)
	else:
		printerr("\n失败 %d 项" % _fail)
		quit(1)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] %s" % msg)
	else:
		_fail += 1
		printerr("  [FAIL] %s" % msg)


func _bytes_equal(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true