extends Node
## 噪声合成旁白：不录音，用「固定种子噪声表 + 逐字哈希」生成嘟嘟囔囔的说话声。
##
## 设计要点：
## 1. 启动时用固定种子的 FastNoiseLite 生成 4096 点噪声表（值域 0..1），
##    不依赖任何运行时随机数，每次启动完全一致。
## 2. 每个字符由 Unicode 码位算出稳定哈希 h，再映射出音色 / 半音 / 时长：
##      h = (cp * 2654435761) & 0xFFFFFFFF
##      idx      = h % 4096            -> 噪声表取值，决定音色与振幅
##      semitone = h % 12              -> 音高在 12 个半音内抖动
##      dur      = 0.04 + (h % 4)*0.01 -> 单音节时长（40~70ms）
## 3. 合成 16-bit PCM / 22050Hz / 单声道 AudioStreamWAV：
##    波形 = 正弦(70%) + 噪声(30%)，频率 = base_freq * pow(2, semitone/12)；
##    每个音节 5ms 快起 + 15ms 快落包络（避免爆音）；
##    空格 / 标点插入 60~120ms 静音；总时长超过 20 秒直接截断。
## 4. 同一段文本的合成结果进缓存（Dictionary[String, AudioStreamWAV]），重复播放零开销。
##
## 用法（由 Lead 注册 autoload，或手动挂到场景里）：
##     var voice: Node = load("res://scripts/audio/voice_synth.gd").new()
##     add_child(voice)
##     voice.speak("旁白文本")
##
## 接口：
##     speak(text: String) -> void      合成并播放（命中缓存则直接播放）
##     stop() -> void                   立刻停止播放
##     set_muted(bool) / is_muted()     静音开关（静音时正在播的声音会被停掉）
##     set_pitch_scale(float)           语速 / 音高倍率（0.25~4.0，默认 1.0）
##     synthesize(text: String)         只合成不播放，返回 AudioStreamWAV（调试 / 预生成用）
##     is_speaking() -> bool            当前是否在出声
##     clear_cache() -> void            清空缓存

## 播放结束（播完或 stop() 都会发）
signal finished

## 采样率：旁白够用，体积小
const SAMPLE_RATE := 22050
## 噪声表长度 N（必须是 2 的幂，索引用 & 掩码）
const NOISE_SIZE := 4096
const NOISE_MASK := NOISE_SIZE - 1
## 固定种子：改动它会改变所有角色的音色
const NOISE_SEED := 20261111
## 默认基频：中性偏低
const BASE_FREQ := 105.0
## 噪声在波形里的权重（越小越温和）
const NOISE_MIX := 0.10
## 包络：18ms 慢起 / 55ms 慢落（更柔和，不刺耳）
const ATTACK_SEC := 0.018
const RELEASE_SEC := 0.055
## 一阶低通系数（越小越闷、越温和）
const LOWPASS_ALPHA := 0.22
## 单段文本最长合成时长（秒），超出直接截断
const MAX_SECONDS := 20.0
## 缓存上限（条），超出后淘汰最早的一条，防止无限增长
const MAX_CACHE := 64
## 哈希乘子（Knuth 常数）
const HASH_MUL := 2654435761

## 正弦波表长度（2 的幂，索引用 & 掩码）
const SINE_SIZE := 4096
## 相位定点小数位数：相位用 int 存，高 16 位是波表下标
const PHASE_SHIFT := 16
const PHASE_MASK := (SINE_SIZE << PHASE_SHIFT) - 1

## 视为「停顿」的字符：空白 + 中英文标点
const PAUSE_CHARS := " \t\r\n\u00a0\u3000，。、；：！？…—～·,.!?;:'\"()[]{}<>《》【】（）「」『』/\\|-_+=*&^%$#@~`"

## 噪声表：值域 0..1，给音色用（每次启动完全一致）
var _noise_table: PackedFloat32Array = PackedFloat32Array()
## 噪声表：值域 -1..1，给波形混合用
var _noise_audio: PackedFloat32Array = PackedFloat32Array()
## 正弦波表：一个完整周期
var _sine: PackedFloat32Array = PackedFloat32Array()
## 12 个半音各自的相位步进（定点）
var _phase_steps: PackedInt32Array = PackedInt32Array()
## 停顿字符的码位集合，O(1) 判断
var _pause_codepoints: Dictionary[int, bool] = {}
## 包络表缓存：key = 帧数
var _env_cache: Dictionary[int, PackedFloat32Array] = {}
## 音频缓存：同文本只合成一次
var _cache: Dictionary[String, AudioStreamWAV] = {}

## 内部播放器，自己创建，不依赖场景
var _player: AudioStreamPlayer = null
var _muted := false
var _pitch_scale := 1.0


func _ready() -> void:
	_build_tables()
	_ensure_player()


## 合成并播放一段文本。空文本等价于 stop()。
func speak(text: String) -> void:
	if text.is_empty():
		stop()
		return
	var stream := synthesize(text)
	if _muted or stream == null or stream.data.is_empty():
		return
	_ensure_player()
	_player.stream = stream
	_player.pitch_scale = _pitch_scale
	_player.play()


## 立刻停止播放。若当时正在播，会补发一次 finished，方便对话流程推进。
func stop() -> void:
	if _player != null and _player.playing:
		_player.stop()
		finished.emit()


## 静音开关。静音时会立刻停掉正在播的声音，但缓存与合成逻辑照常。
func set_muted(value: bool) -> void:
	_muted = value
	if _muted:
		stop()


func is_muted() -> bool:
	return _muted


## 语速 / 音高倍率，直接作用在播放器上（缓存不失效）。
func set_pitch_scale(value: float) -> void:
	_pitch_scale = clampf(value, 0.25, 4.0)
	if _player != null:
		_player.pitch_scale = _pitch_scale


func get_pitch_scale() -> float:
	return _pitch_scale


## 当前是否在出声。
func is_speaking() -> bool:
	return _player != null and _player.playing


## 只合成不播放：命中缓存直接返回，否则现场合成并缓存。
func synthesize(text: String) -> AudioStreamWAV:
	_build_tables()
	if _cache.has(text):
		return _cache[text]
	var stream := _render(text)
	if _cache.size() >= MAX_CACHE:
		# 字典保持插入顺序，淘汰最早的一条
		_cache.erase(_cache.keys()[0])
	_cache[text] = stream
	return stream


## 缓存的文本条数。
func get_cache_size() -> int:
	return _cache.size()


## 清空音频缓存（换角色 / 换种子后调用）。
func clear_cache() -> void:
	_cache.clear()


## 单字音高（Hz），测试与调参用。
func get_char_freq(cp: int) -> float:
	var h := (cp * HASH_MUL) & 0xFFFFFFFF
	var semitone := h % 12
	return BASE_FREQ * pow(2.0, float(semitone) / 12.0)


func _on_player_finished() -> void:
	finished.emit()


## 懒创建播放器：脚本挂到任何 Node 上都能工作。
func _ensure_player() -> AudioStreamPlayer:
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.name = "VoicePlayer"
		_player.bus = &"Master"
		add_child(_player)
		_player.finished.connect(_on_player_finished)
	return _player


## 生成噪声表 / 正弦表 / 相位步进，只做一次。
func _build_tables() -> void:
	if not _noise_table.is_empty():
		return

	# 固定种子的平滑噪声：保证每次启动拿出完全相同的表
	var noise := FastNoiseLite.new()
	noise.seed = NOISE_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3

	_noise_table.resize(NOISE_SIZE)
	_noise_audio.resize(NOISE_SIZE)
	for i in NOISE_SIZE:
		var v := clampf((noise.get_noise_1d(float(i)) + 1.0) * 0.5, 0.0, 1.0)
		_noise_table[i] = v
		_noise_audio[i] = v * 2.0 - 1.0

	_sine.resize(SINE_SIZE)
	for i in SINE_SIZE:
		_sine[i] = sin(TAU * float(i) / float(SINE_SIZE))

	# 12 个半音的相位步进一次算好，内层循环只做加法
	_phase_steps.resize(12)
	for s in 12:
		var freq := BASE_FREQ * pow(2.0, float(s) / 12.0)
		var step := freq * float(SINE_SIZE) / float(SAMPLE_RATE) * float(1 << PHASE_SHIFT)
		_phase_steps[s] = int(round(step))

	_pause_codepoints.clear()
	for i in PAUSE_CHARS.length():
		_pause_codepoints[PAUSE_CHARS.unicode_at(i)] = true


## 停顿字符判定：控制字符 / 空白一律当停顿。
func _is_pause(cp: int) -> bool:
	return cp <= 32 or _pause_codepoints.has(cp)


## 取（并按帧数缓存）快起快落包络。
func _get_envelope(frames: int) -> PackedFloat32Array:
	if _env_cache.has(frames):
		return _env_cache[frames]
	var env := PackedFloat32Array()
	env.resize(frames)
	var attack := maxi(1, int(ATTACK_SEC * float(SAMPLE_RATE)))
	var release := maxi(1, int(RELEASE_SEC * float(SAMPLE_RATE)))
	# 最短音节 40ms 也放得下 5ms+15ms；这里只是兜底，防止以后改参数时包络重叠
	if attack + release > frames:
		release = maxi(1, frames - attack)
	for i in frames:
		var v := 1.0
		if i < attack:
			v = float(i) / float(attack)
		var tail := frames - 1 - i
		if tail < release:
			v = minf(v, float(tail) / float(release))
		env[i] = v
	_env_cache[frames] = env
	return env


## 把文本渲染成 AudioStreamWAV（16-bit PCM / 22050Hz / 单声道）。
## 整个过程是纯计算，无节点依赖，可安全地在主线程同步调用。
func _render(text: String) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED

	var max_bytes := int(MAX_SECONDS * float(SAMPLE_RATE)) * 2
	var data := PackedByteArray()
	data.resize(max_bytes)  # 预留 20 秒，写多少最后再裁
	var pos := 0
	var prev := 0.0  # 低通滤波器状态，跨字保持连续

	for i in text.length():
		var cp := text.unicode_at(i)
		var h := (cp * HASH_MUL) & 0xFFFFFFFF

		# 空格 / 标点：插入 60~120ms 静音（buffer 新分配的字节默认就是 0）
		if _is_pause(cp):
			var pause_frames := int((0.06 + float(h % 7) * 0.01) * float(SAMPLE_RATE))
			if pos + pause_frames * 2 > max_bytes:
				pos = max_bytes
				break
			pos += pause_frames * 2
			continue

		var semitone := h % 7
		var dur := 0.045 + float(h % 4) * 0.012
		var frames := int(dur * float(SAMPLE_RATE))
		if pos + frames * 2 > max_bytes:
			break  # 超过 20 秒上限，整字截断

		var timbre := _noise_table[h % NOISE_SIZE]
		var amp := 0.18 + 0.22 * timbre  # 0.18~0.40，整体音量更轻
		var sine_amp := amp * (1.0 - NOISE_MIX)
		var noise_amp := amp * NOISE_MIX

		var env := _get_envelope(frames)
		var step := _phase_steps[semitone]
		var phase := 0
		# 每个字用不同的步长扫噪声表，得到各不相同的噪声纹理
		var stride := ((h >> 8) & NOISE_MASK) | 1
		var ni := (h % NOISE_SIZE) & NOISE_MASK

		for f in frames:
			var s := _sine[phase >> PHASE_SHIFT] * sine_amp + _noise_audio[ni] * noise_amp
			s *= env[f]
			# 一阶低通：削掉刺耳的高频，听感更接近"咕哝"
			s = prev + (s - prev) * LOWPASS_ALPHA
			prev = s
			phase = (phase + step) & PHASE_MASK
			ni = (ni + stride) & NOISE_MASK
			var v := int(s * 32767.0)
			data[pos] = v & 0xFF
			data[pos + 1] = (v >> 8) & 0xFF
			pos += 2

	if pos <= 0:
		# 空文本 / 全是标点：给一个合法的空流，调用方看 data.is_empty() 即可
		stream.data = PackedByteArray()
		return stream

	data.resize(pos)
	stream.data = data
	return stream