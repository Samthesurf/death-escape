extends Node2D
## Predator animation demo: AI-frame sprites on notebook paper.
## Hound gallops left along the ground, bird flies above with a bob.

const W := 1280.0
const H := 720.0
const GROUND_Y := 600.0

const PAPER := Color("f6f1e3")
const RULE := Color("9db3d4")
const INK := Color("2e2c28")

var hound: AnimatedSprite2D
var bird: AnimatedSprite2D
var hound_speed := 260.0
var bird_speed := 150.0
var t := 0.0
var frames_done := 0


func _frames(paths: Array, fps: float, pingpong := false) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.set_animation_speed("default", fps)
	sf.set_animation_loop("default", true)
	while sf.get_frame_count("default") > 0 and sf.get_frame("default", 0) == null:
		sf.remove_frame("default", 0)
	for p in paths:
		var tex := load(p) as Texture2D
		if tex == null:
			push_error("missing frame: " + p)
			continue
		sf.add_frame("default", tex)
	if pingpong:
		sf.set_animation_loop("default", false)
	return sf


func _ready() -> void:
	# paper background
	var bg := ColorRect.new()
	bg.color = PAPER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.size = Vector2(W, H)
	add_child(bg)
	# ruled lines: straight by construction
	var y := 28.0
	while y < H:
		var rl := Line2D.new()
		rl.points = PackedVector2Array([Vector2(0, y), Vector2(W, y)])
		rl.width = 1.0
		rl.default_color = RULE
		add_child(rl)
		y += 28.0
	# ground line
	var g := Line2D.new()
	g.points = PackedVector2Array([Vector2(0, GROUND_Y), Vector2(W, GROUND_Y)])
	g.width = 4.0
	g.default_color = INK
	add_child(g)
	# hound: faces left in the art, runs left
	hound = AnimatedSprite2D.new()
	hound.sprite_frames = _frames([
		"res://assets/predators/hound/cycle/f1_lunge_base.png",
		"res://assets/predators/hound/cycle/f2_gallop_stretch.png",
		"res://assets/predators/hound/cycle/f3_suspension_air.png",
		"res://assets/predators/hound/cycle/f4_landing_reach.png",
	], 9.0)
	hound.scale = Vector2(0.75, 0.75)
	hound.position = Vector2(W - 200.0, GROUND_Y - 112.0)
	hound.play()
	add_child(hound)
	# stick runner: faces right in the art, runs in place ahead of the hound
	var runner := AnimatedSprite2D.new()
	runner.sprite_frames = _frames([
		"res://assets/stick-runner/rig/run_1_R_contact.png",
		"res://assets/stick-runner/rig/run_2_R_stance.png",
		"res://assets/stick-runner/rig/run_3_L_swingthru.png",
		"res://assets/stick-runner/rig/run_4_L_plant.png",
		"res://assets/stick-runner/rig/run_5_L_contact.png",
		"res://assets/stick-runner/rig/run_6_L_stance.png",
		"res://assets/stick-runner/rig/run_7_R_swingthru.png",
		"res://assets/stick-runner/rig/run_8_R_plant.png",
	], 11.0)
	runner.scale = Vector2(0.6, 0.6)
	runner.position = Vector2(300.0, GROUND_Y - 120.0)
	runner.play()
	add_child(runner)
	# bird: ping-pong flap so there is no snap back to dive
	bird = AnimatedSprite2D.new()
	var bsf := _frames([
		"res://assets/predators/bird/cycle/f1_dive_base.png",
		"res://assets/predators/bird/cycle/f2_flap_up.png",
		"res://assets/predators/bird/cycle/f3_glide_downstroke.png",
		"res://assets/predators/bird/cycle/f4_glide_level.png",
		"res://assets/predators/bird/cycle/f3_glide_downstroke.png",
		"res://assets/predators/bird/cycle/f2_flap_up.png",
	], 9.0)
	bird.sprite_frames = bsf
	bird.scale = Vector2(0.5, 0.5)
	bird.position = Vector2(W - 300.0, 220.0)
	# face along the swoop path: vx=-150, vy=+380*150/1720
	bird.rotation = atan2(33.1, -150.0) - PI
	bird.play()
	add_child(bird)


func _process(dt: float) -> void:
	t += dt
	frames_done += 1
	hound.position.x -= hound_speed * dt
	if hound.position.x < -260.0:
		hound.position.x = W + 260.0
	bird.position.x -= bird_speed * dt
	if bird.position.x < -220.0:
		bird.position.x = W + 220.0
	# diagonal swoop: top-right down to low-left, closing on the runner
	var prog := 1.0 - (bird.position.x + 220.0) / (W + 440.0)
	bird.position.y = 80.0 + prog * 380.0
	if frames_done % 60 == 0:
		print("tick hound_x=%.0f hound_frame=%d bird_x=%.0f bird_frame=%d" % [
			hound.position.x, hound.frame, bird.position.x, bird.frame])
