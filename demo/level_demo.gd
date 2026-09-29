extends Node2D
## Level demo v2: transparent cut sprites, grounded props, bigger house.
## Uses assets/*/cut/*.png (white removed, tight-cropped).

const W := 1280.0
const H := 720.0
const GROUND_Y := 600.0
const PAPER := Color("f6f1e3")
const RULE := Color("9db3d4")
const INK := Color("2e2c28")

var runner: AnimatedSprite2D
var hound: AnimatedSprite2D
var bird: AnimatedSprite2D
var gold: Sprite2D
var gold_base_y := 0.0
var celebrate: Node2D
var jubilate: AnimatedSprite2D
var highfive: AnimatedSprite2D
var hug: AnimatedSprite2D
var clouds: Array[Sprite2D] = []
var world_speed := 120.0
var runner_speed := 60.0
var t := 0.0
var won := false

# drawing state
var drawing := false
var cur_line: Line2D
var strokes: Array[Line2D] = []

var sfx_bird: AudioStreamPlayer
var sfx_wolf: AudioStreamPlayer
var sfx_stomp: AudioStreamPlayer
var rng := RandomNumberGenerator.new()

# sky platform + archers
const BLOCK_SCALE := 0.28
const PLAT_TILES := 3
const PLAT_X := 480.0
const PLAT_Y := 330.0
var platform_top_y := 0.0
var archers: Array = []
var arrows: Array = []
var hits := 0
var hit_flash_until := 0.0

func _cut(path: String) -> Texture2D:
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("missing cut sprite: " + path)
	return tex

func _ground(s: Sprite2D, scale_v: float, sink := 6.0) -> void:
	# anchor sprite bottom on the ground line regardless of crop size
	s.scale = Vector2(scale_v, scale_v)
	var h := float(s.texture.get_height()) * scale_v
	s.position.y = GROUND_Y - h * 0.5 + sink

func _frames(paths: Array, fps: float) -> SpriteFrames:
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
	return sf

func _cut_anim(prefix: String, count: int, fps: float, scale_v: float) -> AnimatedSprite2D:
	var paths: Array = []
	for i in range(count):
		paths.append("res://assets/celebrate/cut/%s_%d.png" % [prefix, i + 1])
	var sp := AnimatedSprite2D.new()
	sp.sprite_frames = _frames(paths, fps)
	sp.scale = Vector2(scale_v, scale_v)
	sp.play()
	return sp

func _ready() -> void:
	rng.randomize()
	var bg := ColorRect.new()
	bg.color = PAPER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.size = Vector2(W, H)
	add_child(bg)
	var y := 28.0
	while y < H:
		var rl := Line2D.new()
		rl.points = PackedVector2Array([Vector2(0, y), Vector2(W, y)])
		rl.width = 1.0
		rl.default_color = RULE
		add_child(rl)
		y += 28.0
	var g := Line2D.new()
	g.points = PackedVector2Array([Vector2(0, GROUND_Y), Vector2(W, GROUND_Y)])
	g.width = 4.0
	g.default_color = INK
	add_child(g)

	# sun: always up in the sky
	var sun := Sprite2D.new()
	sun.texture = _cut("res://assets/obstacles/cut/sun.png")
	sun.position = Vector2(1100, 130)
	sun.scale = Vector2(0.55, 0.55)
	add_child(sun)

	# clouds: always drifting in the sky
	var cloud_files := [
		"res://assets/obstacles/cut/cloud1.png",
		"res://assets/obstacles/cut/cloud2.png",
		"res://assets/obstacles/cut/cloud3.png",
	]
	for i in 3:
		var c := Sprite2D.new()
		c.texture = _cut(cloud_files[i])
		c.position = Vector2(200 + i * 400, 110 + i * 45)
		c.scale = Vector2(0.8, 0.8)
		c.modulate.a = 0.95
		add_child(c)
		clouds.append(c)

	# static hills grounded in the distance
	for i in 2:
		var hill := Sprite2D.new()
		hill.texture = _cut("res://assets/obstacles/cut/hill.png")
		hill.position.x = 450.0 + i * 700.0
		_ground(hill, 0.7, 4.0)
		hill.modulate.a = 0.9
		add_child(hill)

	# sky platform: 3 blocks in a row, archers stand on top and shoot down
	var block_tex := _cut("res://assets/obstacles/cut/block.png")
	var tile_w := float(block_tex.get_width()) * BLOCK_SCALE
	for i in PLAT_TILES:
		var tile := Sprite2D.new()
		tile.texture = block_tex
		tile.scale = Vector2(BLOCK_SCALE, BLOCK_SCALE)
		tile.position = Vector2(PLAT_X + tile_w * (float(i) + 0.5), PLAT_Y)
		add_child(tile)
	platform_top_y = PLAT_Y - float(block_tex.get_height()) * BLOCK_SCALE * 0.5
	for i in 2:
		var an := AnimatedSprite2D.new()
		an.sprite_frames = _frames([
			"res://assets/enemies/cut/archer_draw.png",
			"res://assets/enemies/cut/archer_release.png",
		], 2.0)
		an.scale = Vector2(0.45, 0.45)
		var ax := PLAT_X + tile_w * (0.9 + 1.2 * float(i))
		an.position = Vector2(ax, platform_top_y - 62.0)
		an.play()
		add_child(an)
		archers.append({"node": an, "cooldown": 1.0 + 1.5 * float(i), "release_until": 0.0})

	# runner (existing rig)
	runner = AnimatedSprite2D.new()
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
	runner.position = Vector2(200.0, GROUND_Y - 120.0)
	runner.play()
	add_child(runner)

	# hound chaser
	hound = AnimatedSprite2D.new()
	hound.sprite_frames = _frames([
		"res://assets/predators/hound/cycle/f1_lunge_base.png",
		"res://assets/predators/hound/cycle/f2_gallop_stretch.png",
		"res://assets/predators/hound/cycle/f3_suspension_air.png",
		"res://assets/predators/hound/cycle/f4_landing_reach.png",
	], 9.0)
	hound.scale = Vector2(0.75, 0.75)
	hound.position = Vector2(60.0, GROUND_Y - 112.0)
	hound.play()
	add_child(hound)

	# bird (normalized cycle_cut frames: same size, no zoom; diagonal swoop hunts the runner)
	bird = AnimatedSprite2D.new()
	var bsf := _frames([
		"res://assets/predators/bird/cycle_cut/f1_glide.png",
		"res://assets/predators/bird/cycle_cut/f2_wings_up.png",
	], 7.0)
	bird.sprite_frames = bsf
	bird.scale = Vector2(0.5, 0.5)
	bird.position = Vector2(W - 300.0, 220.0)
	# face along the swoop path: vx=-150, vy=+380*150/1720
	bird.rotation = atan2(33.1, -150.0) - PI
	bird.play()
	add_child(bird)

	# gold bag goal, grounded
	gold = Sprite2D.new()
	gold.texture = _cut("res://assets/pickups/cut/gold_open.png")
	gold.position.x = 1100.0
	_ground(gold, 0.45, 6.0)
	gold_base_y = gold.position.y
	add_child(gold)

	# celebration trio (hidden until win), grounded
	celebrate = Node2D.new()
	celebrate.visible = false
	add_child(celebrate)
	jubilate = _cut_anim("jubilate", 4, 8.0, 0.45)
	jubilate.position = Vector2(380, GROUND_Y - 110)
	celebrate.add_child(jubilate)
	highfive = _cut_anim("highfive", 6, 8.0, 0.6)
	highfive.position = Vector2(640, GROUND_Y - 90)
	celebrate.add_child(highfive)
	hug = _cut_anim("hug", 4, 6.0, 0.45)
	hug.position = Vector2(900, GROUND_Y - 110)
	celebrate.add_child(hug)

	# SFX players (synth WAV placeholders)
	sfx_bird = _sfx("res://assets/sfx/bird_chirp.wav")
	sfx_wolf = _sfx("res://assets/sfx/wolf_howl.wav")
	sfx_stomp = _sfx("res://assets/sfx/stomp_thump.wav")
	_loop_sfx(sfx_bird, 6.0, 10.0)
	_loop_sfx(sfx_wolf, 14.0, 22.0)
	_loop_sfx(sfx_stomp, 1.2, 1.6)

	# obstacle spawner: rocks/houses sometimes
	var spawner := Timer.new()
	spawner.wait_time = 3.5
	spawner.autostart = true
	spawner.timeout.connect(_spawn_obstacle)
	add_child(spawner)

	print("level_demo ready: draw with left mouse, C clears, reach bag to win")

func _sfx(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(path) as AudioStream
	add_child(p)
	return p

func _loop_sfx(p: AudioStreamPlayer, lo: float, hi: float) -> void:
	var tw := create_tween().set_loops()
	var wait := rng.randf_range(lo, hi)
	tw.tween_interval(wait)
	tw.tween_callback(p.play)

func _spawn_arrow(from: Vector2, target: Vector2) -> void:
	var n := Node2D.new()
	n.position = from
	var shaft := Line2D.new()
	shaft.points = PackedVector2Array([Vector2.ZERO, Vector2(34, 0)])
	shaft.width = 3.0
	shaft.default_color = INK
	n.add_child(shaft)
	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([Vector2(34, 0), Vector2(24, -6), Vector2(24, 6)])
	head.color = INK
	n.add_child(head)
	var vel := (target - from).normalized() * 420.0
	vel.x += rng.randf_range(-20.0, 20.0)
	n.rotation = vel.angle()
	add_child(n)
	arrows.append({"node": n, "vel": vel, "life": 6.0})

func _spawn_obstacle() -> void:
	# 50% rock, 30% house, 20% skip (sometimes appear)
	var roll := rng.randf()
	if roll < 0.2:
		return
	var s := Sprite2D.new()
	if roll < 0.7:
		s.texture = _cut("res://assets/obstacles/cut/rock.png")
		s.position.x = W + 100
		_ground(s, 0.55, 10.0)
	else:
		s.texture = _cut("res://assets/obstacles/cut/house.png")
		s.position.x = W + 180
		_ground(s, 1.0, 24.0)
	s.set_meta("scroll", true)
	add_child(s)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			drawing = true
			cur_line = Line2D.new()
			cur_line.width = 5.0
			cur_line.default_color = INK
			cur_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			cur_line.end_cap_mode = Line2D.LINE_CAP_ROUND
			cur_line.joint_mode = Line2D.LINE_JOINT_ROUND
			cur_line.add_point(get_global_mouse_position())
			add_child(cur_line)
		else:
			if drawing and cur_line != null and cur_line.get_point_count() > 1:
				_seal_stroke(cur_line)
				strokes.append(cur_line)
			drawing = false
	elif event is InputEventMouseMotion and drawing and cur_line != null:
		var mp := get_global_mouse_position()
		if cur_line.get_point_count() == 0 or cur_line.get_point_position(cur_line.get_point_count() - 1).distance_to(mp) > 6.0:
			cur_line.add_point(mp)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_C:
		for s in strokes:
			s.queue_free()
		strokes.clear()

func _seal_stroke(line: Line2D) -> void:
	# static collision so drawn ink blocks chasers / arrows later
	var body := StaticBody2D.new()
	for i in range(line.get_point_count() - 1):
		var a := line.get_point_position(i)
		var b := line.get_point_position(i + 1)
		var shape := SegmentShape2D.new()
		shape.a = a
		shape.b = b
		var col := CollisionShape2D.new()
		col.shape = shape
		body.add_child(col)
	add_child(body)
	line.set_meta("body", body)

func _process(dt: float) -> void:
	t += dt
	# clouds drift
	for i in clouds.size():
		clouds[i].position.x -= 12.0 * dt
		if clouds[i].position.x < -200:
			clouds[i].position.x = W + 200
	# scrolling obstacles
	for child in get_children():
		if child is Sprite2D and child.has_meta("scroll"):
			child.position.x -= world_speed * dt
			if child.position.x < -200:
				child.queue_free()
	# gold bob
	gold.position.y = gold_base_y + sin(t * 2.0) * 6.0
	# archers fire down at the runner
	for a in archers:
		var an: AnimatedSprite2D = a["node"]
		a["cooldown"] = float(a["cooldown"]) - dt
		if t > float(a["release_until"]):
			an.frame = 0
		if float(a["cooldown"]) <= 0.0 and not won:
			a["cooldown"] = rng.randf_range(2.2, 3.4)
			a["release_until"] = t + 0.3
			an.frame = 1
			_spawn_arrow(an.position + Vector2(-20, -30), runner.position + Vector2(0, -60))
	# arrows fly with light gravity, hit runner or ground
	for arrow in arrows.duplicate():
		var n: Node2D = arrow["node"]
		if not is_instance_valid(n):
			arrows.erase(arrow)
			continue
		var v: Vector2 = arrow["vel"]
		v.y += 260.0 * dt
		arrow["vel"] = v
		arrow["life"] = float(arrow["life"]) - dt
		n.position += v * dt
		n.rotation = v.angle()
		var done := false
		if n.position.distance_to(runner.position + Vector2(0, -60)) < 45.0 and not won:
			hits += 1
			hit_flash_until = t + 0.3
			print("HIT: arrow got the runner (%d)" % hits)
			done = true
		elif n.position.y >= GROUND_Y - 4.0 or n.position.x < -60.0 or float(arrow["life"]) <= 0.0:
			done = true
		if done:
			n.queue_free()
			arrows.erase(arrow)
	if t < hit_flash_until:
		runner.modulate = Color(1, 0.4, 0.4)
	else:
		runner.modulate = Color.WHITE
	# runner advances toward bag; hound chases behind
	# bird diagonal swoop: top-right down to low-left, closing on the runner
	bird.position.x -= 150.0 * dt
	if bird.position.x < -220.0:
		bird.position.x = W + 220.0
	var prog := 1.0 - (bird.position.x + 220.0) / (W + 440.0)
	bird.position.y = 80.0 + prog * 380.0
	if not won:
		runner.position.x += runner_speed * dt
		hound.position.x += (runner_speed * 0.92) * dt
		if runner.position.x >= gold.position.x - 90.0:
			won = true
			celebrate.visible = true
			sfx_stomp.play()
			print("WIN: runner reached the gold")
