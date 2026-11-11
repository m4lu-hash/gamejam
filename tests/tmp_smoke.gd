extends SceneTree
## 临时冒烟测试（跑完即删）

func _initialize() -> void:
	print("smoke: start")
	var s: Script = load("res://scripts/audio/voice_synth.gd")
	print("smoke: loaded=", s != null)
	var v: Node = s.new()
	print("smoke: new ok")
	root.add_child(v)
	print("smoke: added, noise size=", (v.get("_noise_table") as PackedFloat32Array).size())
	var w: AudioStreamWAV = v.synthesize("你好")
	print("smoke: synth bytes=", w.data.size())
	quit(0)