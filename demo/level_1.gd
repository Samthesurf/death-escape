extends Node2D
## Level 1: survive 105 seconds, reach the gold.
## Draw ramps (climb rocks), shields (block arrows, wear out), and CARS:
## a closed loop becomes a drivable hull. The stick hops in, drives it at
## ~320 px/s, and takes the hits in the hull instead of his chest.
## One rock / arrow / hard fall on foot = game over. In the car the hull
## absorbs damage first.

const W := 1280.0
const H := 720.0
const GROUND_Y := 600.0
const PAPER := Color("f6f1e3")
const RULE := Color("9db3d4")
const INK := Color("2e2c28")

const GRAV := 1800.0
const KILL_FALL := 1050.0
const SPEED := 240.0
const ARROW_SPEED := 520.0
const RUNNER_X := 300.0
const PLAT0 := 4500.0
# denser than before: something to deal with every ~8s, coins fill the gaps
const ROCK_XS := [2500.0, 4500.0, 6500.0, 8500.0, 10500.0, 12500.0, 14500.0, 16500.0]
const COIN_XS := [3500.0, 5500.0, 7500.0, 9500.0, 11500.0, 13500.0, 15500.0]

# ---------- car tuning ----------
const LOOP_CLOSE_DIST := 60.0
const LOOP_MIN_LEN := 300.0
const LOOP_MIN_W := 120.0
const LOOP_MIN_H := 60.0
const VEH_SPEED := 320.0
const VEH_HP := 6
const VEH_FORCE := 2600.0

# ---------- ink + score ----------
const INK_MAX := 100.0
const INK_PER_PX := 0.02
const INK_REGEN := 12.0

var level_time := 105.0
var time_left := 0.0
var gold_x := 19000.0
var state := "run" # run | dying | lose | win
var nodmg := false # test hook: --nodmg disables deaths
var cli_args: PackedStringArray
var t := 0.0
var rng := RandomNumberGenerator.new()

var runner: CharacterBody2D
var runner_anim: AnimatedSprite2D
var ride_sprite: Sprite2D
var peak_fall := 0.0
var was_air := false
var invuln := 0.0

var strokes: Array = [] # each {line, body, hp, max_hp}
var strokes_sealed := 0
var drawing := false
var cur_line: Line2D
var cur_body: StaticBody2D
var cur_hits := 0
var grabbing := false
var grab_idx := -1
var grab_prev := Vector2.ZERO
var move_mode := false
var move_btn: Button
var hop_btn: Button
var death_timer := 0.0
var pending_title := ""
var pending_sub := ""
var pending_sad := true

# ink + score
var ink := INK_MAX
var score := 0
var coins_got := 0
var coins_total := 0
var used_car := false
var hud_ink_bar: ColorRect
var hud_score: Label
var hud_prog_fill: ColorRect
var title_lbl: Label

# vehicle state
var vehicle: RigidBody2D
var veh_line: Line2D
var veh_hp := 0
var veh_max := VEH_HP
var veh_seat := Vector2.ZERO
var veh_radius := 60.0
var veh_wheels: Array = []
var riding := false
var veh_hit_cd := 0.0
var veh_stop_t := 0.0
var veh_peak := 0.0
var veh_was_air := false

var block_tex: Texture2D
var plat: Node2D
var plat_placed := false
var plat_drop_t := -1.0
var plat_rumbled := false
var archer: AnimatedSprite2D
var archer_cd := 3.0
var archer_release_until := 0.0
var arrows: Array = []

var rocks: Array = [] # each {node}
var rock_timer := 4.0

var gold: Sprite2D
var gold_spawned := false
var hug: AnimatedSprite2D
var coins: Array = [] # each {node, base_y, taken}

var hud_timer: Label
var overlay: Control
var ui: CanvasLayer
var cam: Camera2D
var clouds: Array = []
var shadow: Polygon2D
var dust_count := 0

# audio
var sfx_step: AudioStreamPlayer
var sfx_roll: AudioStreamPlayer
var sfx_wind: AudioStreamPlayer
var sfx_board: AudioStreamPlayer
var sfx_crash: AudioStreamPlayer
var sfx_coin: AudioStreamPlayer
var step_t := 0.0
var step_alt := false
var stuck_t := 0.0
var stuck_hint_cd := 0.0

func _cut(path: String) -> Texture2D:
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("missing: " + path)
	return tex

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

func _loop_wav(path: String) -> AudioStreamWAV:
	var w := load(path) as AudioStreamWAV
	if w != null:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.get_data().size() / 2
	return w

func _player(stream: AudioStream, vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	return p

func _ready() -> void:
	rng.randomize()
	Engine.time_scale = 1.0
	var args := OS.get_cmdline_user_args()
	cli_args = args
	if "--fast" in args:
		level_time = 25.0
		gold_x = 5600.0
	if "--nodmg" in args:
		nodmg = true
	time_left = level_time
	# camera chases the runner through a long world
	cam = Camera2D.new()
	cam.position = Vector2(RUNNER_X + 200, 360)
	add_child(cam)
	cam.make_current()
	ui = CanvasLayer.new()
	add_child(ui)
	# notebook paper is the screen itself: fixed to viewport, scrolls forever
	var paper := CanvasLayer.new()
	paper.layer = -1
	add_child(paper)
	var bg := ColorRect.new()
	bg.color = PAPER
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	paper.add_child(bg)
	var y := 28.0
	# oversized on purpose: phones in landscape show a bigger viewport
	# than 1280x720, and every visible pixel needs ruling
	while y < 1440.0:
		var rl := Line2D.new()
		rl.points = PackedVector2Array([Vector2(0, y), Vector2(2560, y)])
		rl.width = 1.0
		rl.default_color = RULE
		paper.add_child(rl)
		y += 28.0
	var gline := Line2D.new()
	gline.points = PackedVector2Array([Vector2(-500, GROUND_Y), Vector2(gold_x + 3000, GROUND_Y)])
	gline.width = 4.0
	gline.default_color = INK
	add_child(gline)
	var ground := StaticBody2D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var gshape := SegmentShape2D.new()
	gshape.a = Vector2(-500, GROUND_Y)
	gshape.b = Vector2(gold_x + 3000, GROUND_Y)
	var gcol := CollisionShape2D.new()
	gcol.shape = gshape
	ground.add_child(gcol)
	add_child(ground)
	# sun + clouds live on the page (screen-fixed sky)
	var sun := Sprite2D.new()
	sun.texture = _cut("res://assets/obstacles/cut/sun.png")
	sun.position = Vector2(1100, 130)
	sun.scale = Vector2(0.55, 0.55)
	paper.add_child(sun)
	var cloud_files := ["cloud1", "cloud2", "cloud3"]
	for i in 3:
		var c := Sprite2D.new()
		c.texture = _cut("res://assets/obstacles/cut/%s.png" % cloud_files[i])
		c.position = Vector2(200 + i * 400, 110 + i * 45)
		c.scale = Vector2(0.8, 0.8)
		paper.add_child(c)
		clouds.append(c)
	# distant birds: tiny ink doodles high in the sky (screen-fixed, like the
	# clouds). They never touch the running line, so they read as scenery,
	# never as obstacles.
	for i in 3:
		var b := Line2D.new()
		var bx := 300.0 + i * 350.0
		var by := 180.0 + i * 30.0
		var bp := PackedVector2Array()
		for k in 13:
			var u := float(k) / 12.0 - 0.5
			bp.append(Vector2(bx + u * 36.0, by + absf(u) * 14.0))
		b.points = bp
		b.width = 2.0
		b.default_color = Color(0.18, 0.17, 0.15, 0.45)
		paper.add_child(b)
		clouds.append(b)
	# runner body (0.4 scale, ink feet at canvas bottom sit exactly on origin)
	runner = CharacterBody2D.new()
	runner.position = Vector2(RUNNER_X, GROUND_Y - 2)
	runner.collision_layer = 1
	runner.collision_mask = 1
	runner.floor_snap_length = 10.0
	runner.floor_max_angle = deg_to_rad(50.0)
	var cap := CapsuleShape2D.new()
	# feet-only: his head and arms pass under overhead strokes, so a shield
	# drawn at head height blocks arrows but never wedges him. Low lines
	# still trip his feet by design. Rocks still kill via the chest check.
	cap.radius = 10.0
	cap.height = 64.0
	var capcol := CollisionShape2D.new()
	capcol.shape = cap
	capcol.position = Vector2(0, -32)
	runner.add_child(capcol)
	runner_anim = AnimatedSprite2D.new()
	runner_anim.sprite_frames = _frames([
		"res://assets/stick-runner/rig/run_1_R_contact.png",
		"res://assets/stick-runner/rig/run_2_R_stance.png",
		"res://assets/stick-runner/rig/run_3_L_swingthru.png",
		"res://assets/stick-runner/rig/run_4_L_plant.png",
		"res://assets/stick-runner/rig/run_5_L_contact.png",
		"res://assets/stick-runner/rig/run_6_L_stance.png",
		"res://assets/stick-runner/rig/run_7_R_swingthru.png",
		"res://assets/stick-runner/rig/run_8_R_plant.png",
	], 11.0)
	runner_anim.scale = Vector2(0.4, 0.4)
	runner_anim.position = Vector2(0, -79)
	runner_anim.play()
	runner.add_child(runner_anim)
	# seated driver pose, shown only while riding (same scale + offset)
	ride_sprite = Sprite2D.new()
	ride_sprite.texture = _cut("res://assets/stick-runner/rig/drive_seated.png")
	ride_sprite.scale = Vector2(0.4, 0.4)
	ride_sprite.position = Vector2(0, -79)
	ride_sprite.visible = false
	runner.add_child(ride_sprite)
	add_child(runner)
	# soft blob shadow grounds him visually
	shadow = Polygon2D.new()
	var sh_pts := PackedVector2Array()
	for i in 13:
		var a := TAU * float(i) / 12.0
		sh_pts.append(Vector2(cos(a) * 26.0, sin(a) * 7.0))
	shadow.polygon = sh_pts
	shadow.color = Color(0.18, 0.17, 0.15, 0.20)
	shadow.z_index = -2
	add_child(shadow)
	# sky platform (drops in as the runner closes in), high enough that
	# even a tall car + rider passes under
	block_tex = _cut("res://assets/obstacles/cut/block.png")
	plat = Node2D.new()
	plat.position.y = -420.0
	add_child(plat)
	var tile_w := float(block_tex.get_width()) * 0.18
	for i in 3:
		var tile := Sprite2D.new()
		tile.texture = block_tex
		tile.scale = Vector2(0.18, 0.18)
		tile.position = Vector2(PLAT0 + tile_w * (float(i) + 0.5), 200.0)
		plat.add_child(tile)
	archer = AnimatedSprite2D.new()
	archer.sprite_frames = _frames([
		"res://assets/enemies/cut/archer_draw.png",
		"res://assets/enemies/cut/archer_release.png",
	], 2.0)
	archer.scale = Vector2(0.45, 0.45)
	archer.rotation = deg_to_rad(90.0) # start aiming down
	archer.position = Vector2(PLAT0 + tile_w * 1.5, 200.0 - 39.0 - 58.0)
	archer.play()
	plat.add_child(archer)
	# rocks sit in the world ahead; coins between them; gold waits at the end
	for rx in ROCK_XS:
		if rx < gold_x and not "--norocks" in cli_args:
			_spawn_rock_at(rx)
	coins_total = 0
	for cx in COIN_XS:
		if cx < gold_x - 200.0 and not "--norocks" in cli_args:
			_spawn_coin(cx)
			coins_total += 1
	gold = Sprite2D.new()
	gold.texture = _cut("res://assets/pickups/cut/gold_open.png")
	gold.scale = Vector2(0.45, 0.45)
	var gh0 := float(gold.texture.get_height()) * 0.45
	gold.position = Vector2(gold_x, GROUND_Y - gh0 * 0.5 + 6.0)
	add_child(gold)
	# audio: footsteps, rolling hum, wind bed, one-shots
	sfx_step = _player(load("res://assets/sfx/run_step.wav") as AudioStream, -10.0)
	sfx_roll = _player(_loop_wav("res://assets/sfx/roll_loop.wav"), -60.0)
	sfx_wind = _player(_loop_wav("res://assets/sfx/wind_loop.wav"), -26.0)
	sfx_board = _player(load("res://assets/sfx/board_thunk.wav") as AudioStream, -6.0)
	sfx_crash = _player(load("res://assets/sfx/crash_break.wav") as AudioStream, -6.0)
	sfx_coin = _player(load("res://assets/sfx/coin_blip.wav") as AudioStream, -8.0)
	sfx_roll.play()
	sfx_wind.play()
	# HUD
	hud_score = Label.new()
	hud_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_score.add_theme_font_size_override("font_size", 30)
	hud_score.add_theme_color_override("font_color", INK)
	hud_score.position = Vector2(16, 10)
	hud_score.text = "0 pts"
	ui.add_child(hud_score)
	var ink_lbl := Label.new()
	ink_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ink_lbl.add_theme_font_size_override("font_size", 18)
	ink_lbl.add_theme_color_override("font_color", INK)
	ink_lbl.position = Vector2(16, 48)
	ink_lbl.text = "INK"
	ui.add_child(ink_lbl)
	var ink_bg := ColorRect.new()
	ink_bg.color = Color(0.18, 0.17, 0.15, 0.25)
	ink_bg.position = Vector2(60, 50)
	ink_bg.size = Vector2(220, 14)
	ui.add_child(ink_bg)
	hud_ink_bar = ColorRect.new()
	hud_ink_bar.color = INK
	hud_ink_bar.position = Vector2(60, 50)
	hud_ink_bar.size = Vector2(220, 14)
	ui.add_child(hud_ink_bar)
	hud_timer = Label.new()
	hud_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_timer.add_theme_font_size_override("font_size", 40)
	hud_timer.add_theme_color_override("font_color", INK)
	hud_timer.position = Vector2(W * 0.5 - 60, 12)
	ui.add_child(hud_timer)
	var prog_bg := ColorRect.new()
	prog_bg.color = Color(0.18, 0.17, 0.15, 0.25)
	prog_bg.position = Vector2(W * 0.5 - 150, 62)
	prog_bg.size = Vector2(300, 8)
	ui.add_child(prog_bg)
	hud_prog_fill = ColorRect.new()
	hud_prog_fill.color = Color(0.75, 0.55, 0.15)
	hud_prog_fill.position = Vector2(W * 0.5 - 150, 62)
	hud_prog_fill.size = Vector2(4, 8)
	ui.add_child(hud_prog_fill)
	var hint := Label.new()
	hint.text = "Drag: line = ramp, LOOP = car. Shields HIGH so he runs under."
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", INK)
	hint.position = Vector2(16, H - 34)
	ui.add_child(hint)
	# story card, fades after a few seconds
	title_lbl = Label.new()
	title_lbl.text = "He saw the bag. RUN."
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.add_theme_font_size_override("font_size", 52)
	title_lbl.add_theme_color_override("font_color", INK)
	title_lbl.position = Vector2(W * 0.5 - 250, 140)
	ui.add_child(title_lbl)
	# touch buttons: move toggle, hop off, clear, restart
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.anchor_left = 1.0
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -450.0
	bar.offset_top = -76.0
	bar.offset_right = -16.0
	bar.offset_bottom = -16.0
	ui.add_child(bar)
	move_btn = Button.new()
	move_btn.text = "Move: off"
	move_btn.toggle_mode = true
	move_btn.custom_minimum_size = Vector2(100, 56)
	move_btn.pressed.connect(_on_move_toggle)
	bar.add_child(move_btn)
	hop_btn = Button.new()
	hop_btn.text = "Hop off"
	hop_btn.custom_minimum_size = Vector2(100, 56)
	hop_btn.pressed.connect(_on_hop_btn)
	hop_btn.visible = false
	bar.add_child(hop_btn)
	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.custom_minimum_size = Vector2(100, 56)
	clear_btn.pressed.connect(_on_clear_btn)
	bar.add_child(clear_btn)
	var restart_btn := Button.new()
	restart_btn.text = "Restart"
	restart_btn.custom_minimum_size = Vector2(100, 56)
	restart_btn.pressed.connect(_on_restart_btn)
	bar.add_child(restart_btn)
	print("level1 ready: survive %.0f seconds" % level_time)

func _on_move_toggle() -> void:
	move_mode = move_btn.button_pressed
	move_btn.text = "Move: on" if move_mode else "Move: off"

func _on_hop_btn() -> void:
	if riding:
		_eject_vehicle(true)

func _on_clear_btn() -> void:
	_clear_strokes()

func _on_restart_btn() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

# ---------- drawing: ramps + shields + cars, all with durability ----------
func _unhandled_input(event: InputEvent) -> void:
	if state != "run":
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			get_tree().reload_current_scene()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if move_mode:
				grab_idx = _stroke_at(get_global_mouse_position())
				if grab_idx >= 0:
					grabbing = true
					Engine.time_scale = 0.45
					grab_prev = get_global_mouse_position()
					_set_grab_tint(true)
					return
			if ink <= 1.0:
				return # dry pen: wait for regen
			drawing = true
			Engine.time_scale = 0.45
			cur_line = Line2D.new()
			cur_line.width = 3.0
			cur_line.antialiased = true
			cur_line.default_color = INK
			cur_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			cur_line.end_cap_mode = Line2D.LINE_CAP_ROUND
			cur_line.joint_mode = Line2D.LINE_JOINT_ROUND
			cur_line.add_point(get_global_mouse_position())
			add_child(cur_line)
			# live body: he runs on it while it is still being drawn
			cur_body = StaticBody2D.new()
			cur_body.collision_layer = 1
			cur_body.collision_mask = 0
			add_child(cur_body)
		else:
			Engine.time_scale = 1.0
			if drawing and cur_line != null and cur_line.get_point_count() > 1:
				_register_stroke(cur_line, cur_body)
			else:
				if cur_line != null:
					cur_line.queue_free()
				if cur_body != null:
					cur_body.queue_free()
			drawing = false
			cur_line = null
			cur_body = null
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			grab_idx = _stroke_at(get_global_mouse_position())
			if grab_idx >= 0:
				grabbing = true
				Engine.time_scale = 0.45
				grab_prev = get_global_mouse_position()
				_set_grab_tint(true)
		else:
			Engine.time_scale = 1.0
			_set_grab_tint(false)
			grabbing = false
			grab_idx = -1
	elif event is InputEventMouseMotion and drawing and cur_line != null:
		var mp := get_global_mouse_position()
		if cur_line.get_point_count() == 0 or cur_line.get_point_position(cur_line.get_point_count() - 1).distance_to(mp) > 6.0:
			var prev := cur_line.get_point_position(cur_line.get_point_count() - 1)
			var cost := prev.distance_to(mp) * INK_PER_PX
			if ink < cost:
				# pen ran dry mid-stroke: seal what we have
				_register_stroke(cur_line, cur_body)
				drawing = false
				cur_line = null
				cur_body = null
				Engine.time_scale = 1.0
				return
			ink -= cost
			cur_line.add_point(mp)
			var n := cur_line.get_point_count()
			if n > 1 and cur_body != null:
				cur_body.add_child(_seg_collider(cur_line.get_point_position(n - 2), cur_line.get_point_position(n - 1)))
	elif event is InputEventMouseMotion and grabbing and grab_idx >= 0:
		if grab_idx < strokes.size():
			var line = strokes[grab_idx]["line"]
			var body = strokes[grab_idx]["body"]
			if is_instance_valid(line) and is_instance_valid(body):
				var mp := get_global_mouse_position()
				var d := mp - grab_prev
				grab_prev = mp
				line.position += d
				body.position += d
			else:
				grabbing = false
				grab_idx = -1
	elif event is InputEventKey and event.pressed and event.keycode == KEY_C:
		_clear_strokes()
	elif event is InputEventKey and event.pressed and (event.keycode == KEY_E or event.keycode == KEY_SPACE):
		if riding:
			_eject_vehicle(true)

func _seg_collider(a: Vector2, b: Vector2) -> CollisionShape2D:
	var shape := RectangleShape2D.new()
	# short end extension: just enough to hide the blunt end-cap at a
	# ground junction. Long extensions turn curves into lumpy chords
	# that snag him, so the glide assist below handles lips instead.
	shape.size = Vector2(a.distance_to(b) + 20.0, 14.0)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = (a + b) * 0.5
	col.rotation = (b - a).angle()
	return col

func _loop_stats(line: Line2D) -> Dictionary:
	var n := line.get_point_count()
	if n < 24:
		return {"loop": false}
	var first := line.get_point_position(0)
	var last := line.get_point_position(n - 1)
	if first.distance_to(last) > LOOP_CLOSE_DIST:
		return {"loop": false}
	var len := 0.0
	var mn := first
	var mx := first
	for i in range(1, n):
		var a := line.get_point_position(i - 1)
		var b := line.get_point_position(i)
		len += a.distance_to(b)
		mn.x = minf(mn.x, b.x)
		mn.y = minf(mn.y, b.y)
		mx.x = maxf(mx.x, b.x)
		mx.y = maxf(mx.y, b.y)
	var w := mx.x - mn.x
	var h := mx.y - mn.y
	if len < LOOP_MIN_LEN or w < LOOP_MIN_W or h < LOOP_MIN_H:
		return {"loop": false}
	return {"loop": true, "len": len, "w": w, "h": h, "center": (mn + mx) * 0.5}

func _register_stroke(line: Line2D, body: StaticBody2D) -> void:
	strokes_sealed += 1
	var ls := _loop_stats(line)
	if bool(ls.get("loop", false)) and not riding:
		# closed loop on foot: it becomes a car, not a ramp
		body.queue_free()
		_build_vehicle(line)
		return
	var segs := line.get_point_count() - 1
	var hp := mini(6 + segs / 2, 18) - cur_hits
	cur_hits = 0
	if hp <= 0:
		line.queue_free()
		body.queue_free()
		return
	# gesture read: flat wide strokes are shields (arrow bonus), slopes are ramps
	var p0 := line.get_point_position(0)
	var p1 := line.get_point_position(line.get_point_count() - 1)
	var span: float = absf(p1.x - p0.x)
	var rise: float = absf(p1.y - p0.y)
	if span > 120.0 and rise < span * 0.25:
		hp += 2
		line.modulate = Color(0.82, 0.88, 1.0)
	strokes.append({"line": line, "body": body, "hp": hp, "max_hp": hp})
	if strokes.size() > 10:
		var old = strokes.pop_front()
		(old["line"] as Line2D).queue_free()
		(old["body"] as StaticBody2D).queue_free()

func _seal_stroke(line: Line2D) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	for i in range(line.get_point_count() - 1):
		body.add_child(_seg_collider(line.get_point_position(i), line.get_point_position(i + 1)))
	add_child(body)
	_register_stroke(line, body)

# ---------- vehicle: closed loop becomes a drivable hull ----------
func _build_vehicle(line: Line2D) -> void:
	_destroy_vehicle_silent()
	var n := line.get_point_count()
	var center := Vector2.ZERO
	for i in n:
		center += line.get_point_position(i)
	center /= float(n)
	# simplify to ~14 hull points for a stable ring
	var step := maxi(1, n / 14)
	var pts := PackedVector2Array()
	var i := 0
	while i < n:
		pts.append(line.get_point_position(i) - center)
		i += step
	var w := 0.0
	var h := 0.0
	for p in pts:
		w = maxf(w, absf(p.x) * 2.0)
		h = maxf(h, absf(p.y) * 2.0)
	# spawn un-wedged: big loops always dip below the ground line, so rest
	# a straddling hull on top of it instead of burying it (buried hulls
	# stall instantly and toss him right back out)
	var bottom := center.y + h * 0.5
	if bottom > GROUND_Y + 10.0 and center.y - h * 0.5 < GROUND_Y:
		var lift := bottom - (GROUND_Y - 4.0)
		center.y -= lift
		for k in pts.size():
			pts[k].y += lift
	# sled bottom: flatten the lowest band into a flat runner so the hull
	# cannot pitch onto a front vertex and plow. An ellipse bottom wants
	# to tip forward under drive force; a flat bottom stays level.
	var flat := h * 0.5 - 12.0
	for k in pts.size():
		if pts[k].y > flat:
			pts[k].y = flat
	var body := RigidBody2D.new()
	body.position = center
	body.mass = 2.0
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.friction = 1.0
	body.physics_material_override.bounce = 0.05
	body.collision_layer = 1
	body.collision_mask = 1
	body.contact_monitor = true
	body.max_contacts_reported = 6
	body.gravity_scale = 1.0
	body.linear_damp = 0.4
	body.angular_damp = 4.0
	var m := pts.size()
	for k in m:
		body.add_child(_seg_collider(pts[k], pts[(k + 1) % m]))
	# hull skin follows the body, so tilt reads instantly
	remove_child(line)
	line.position = Vector2.ZERO
	var draw_pts := PackedVector2Array(pts)
	draw_pts.append(pts[0])
	line.points = draw_pts
	line.width = 5.0
	body.add_child(line)
	# two pebble wheels at the bottom corners: they spin with speed
	veh_wheels.clear()
	for sx in [-0.28, 0.28]:
		var hub := Node2D.new()
		hub.position = Vector2(w * sx, h * 0.5 - 4.0)
		var ring := Line2D.new()
		var rp := PackedVector2Array()
		for k in 13:
			var a := TAU * float(k) / 12.0
			rp.append(Vector2(cos(a), sin(a)) * 10.0)
		ring.points = rp
		ring.width = 3.0
		ring.default_color = INK
		hub.add_child(ring)
		var spoke := Line2D.new()
		spoke.points = PackedVector2Array([Vector2.ZERO, Vector2(10, 0)])
		spoke.width = 2.0
		spoke.default_color = INK
		hub.add_child(spoke)
		body.add_child(hub)
		veh_wheels.append(hub)
	add_child(body)
	vehicle = body
	veh_line = line
	veh_hp = VEH_HP
	veh_max = VEH_HP
	veh_seat = Vector2(0, -h * 0.5 - 30.0)
	veh_radius = maxf(w, h) * 0.5
	veh_hit_cd = 0.5 # spawn grace: a loop drawn overlapping a rock settles first
	veh_stop_t = 0.0
	veh_peak = 0.0
	veh_was_air = false
	_popup(center + Vector2(-40, -90), "CAR!", INK)
	if runner.global_position.distance_to(center) < 700.0:
		_board_vehicle()
	else:
		_popup(center + Vector2(-60, -60), "hop in!", INK)

func _board_vehicle() -> void:
	if riding or not is_instance_valid(vehicle):
		return
	riding = true
	used_car = true
	runner.collision_mask = 0
	runner.velocity = Vector2.ZERO
	runner_anim.visible = false
	ride_sprite.visible = true
	hop_btn.visible = true
	sfx_board.play()
	_add_score(50, vehicle.global_position + Vector2(-40, -110), "VROOM +50")

func _place_runner_at(pos: Vector2, vel: Vector2) -> void:
	runner.global_position = pos
	runner.rotation = 0.0
	runner.velocity = vel
	runner.collision_mask = 1
	runner_anim.visible = true
	ride_sprite.visible = false
	hop_btn.visible = false
	riding = false

func _eject_vehicle(hop: bool, msg: String = "hop!") -> void:
	# voluntary hop-off (or replace): hull settles into a static ramp
	if not is_instance_valid(vehicle):
		riding = false
		return
	var seat_g: Vector2 = vehicle.to_global(veh_seat)
	var xf: Transform2D = vehicle.global_transform
	var local: PackedVector2Array = veh_line.points.duplicate()
	# rebuild as an ordinary static stroke with leftover durability
	var wline := Line2D.new()
	wline.width = 5.0
	wline.antialiased = true
	wline.default_color = INK
	wline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	wline.end_cap_mode = Line2D.LINE_CAP_ROUND
	wline.joint_mode = Line2D.LINE_JOINT_ROUND
	var gpts := PackedVector2Array()
	for p in local:
		gpts.append(xf * p)
	wline.points = gpts
	add_child(wline)
	var wbody := StaticBody2D.new()
	wbody.collision_layer = 1
	wbody.collision_mask = 0
	for k in range(gpts.size() - 1):
		wbody.add_child(_seg_collider(gpts[k], gpts[k + 1]))
	add_child(wbody)
	strokes.append({"line": wline, "body": wbody, "hp": veh_hp, "max_hp": veh_max})
	vehicle.queue_free()
	vehicle = null
	veh_line = null
	veh_wheels.clear()
	sfx_roll.volume_db = -60.0
	if hop:
		_popup(seat_g + Vector2(-30, -60), msg, INK)
	# small dismount step, not a launch: a big toss is what used to throw
	# him clean over his own car
	_place_runner_at(seat_g + Vector2(0, -10), Vector2(120, -150) if hop else Vector2.ZERO)
	invuln = 0.8

func _break_vehicle(reason: String) -> void:
	if not is_instance_valid(vehicle):
		riding = false
		return
	var seat_g: Vector2 = vehicle.to_global(veh_seat)
	_popup(seat_g + Vector2(-50, -70), reason, Color(0.7, 0.15, 0.1))
	sfx_crash.play()
	vehicle.queue_free()
	vehicle = null
	veh_line = null
	veh_wheels.clear()
	sfx_roll.volume_db = -60.0
	_place_runner_at(seat_g + Vector2(0, -10), Vector2(120, -200))
	invuln = 1.0

func _destroy_vehicle_silent() -> void:
	if is_instance_valid(vehicle):
		vehicle.queue_free()
	vehicle = null
	veh_line = null
	veh_wheels.clear()
	if riding:
		runner.collision_mask = 1
		runner_anim.visible = true
		ride_sprite.visible = false
		hop_btn.visible = false
		riding = false

func _damage_vehicle(amount: int, at: Vector2, label: String) -> void:
	if not riding or nodmg:
		if nodmg:
			return
	veh_hp -= amount
	veh_hit_cd = 1.0
	if label != "":
		_popup(at, label, INK)
	if veh_hp <= 0:
		_break_vehicle("WRECK!")
	else:
		sfx_crash.play()
		var a := 0.35 + 0.65 * float(veh_hp) / float(veh_max)
		if is_instance_valid(veh_line):
			veh_line.modulate.a = a

func _stroke_at(mp: Vector2) -> int:
	var best := -1
	var best_d := 30.0
	for si in strokes.size():
		var line = strokes[si]["line"]
		if not is_instance_valid(line):
			continue
		for i in range(line.get_point_count() - 1):
			var d := _pt_seg_dist(mp, line.to_global(line.get_point_position(i)), line.to_global(line.get_point_position(i + 1)))
			if d < best_d:
				best_d = d
				best = si
	return best

func _set_grab_tint(on: bool) -> void:
	if grab_idx < 0 or grab_idx >= strokes.size():
		return
	var gline = strokes[grab_idx]["line"]
	if is_instance_valid(gline):
		var a: float = gline.modulate.a
		gline.modulate = Color(0.45, 0.65, 1.0, a) if on else Color(1, 1, 1, a)

func _clear_strokes() -> void:
	grabbing = false
	grab_idx = -1
	drawing = false
	cur_hits = 0
	Engine.time_scale = 1.0
	if cur_line != null:
		cur_line.queue_free()
		cur_line = null
	if cur_body != null:
		cur_body.queue_free()
		cur_body = null
	for s in strokes:
		(s["line"] as Line2D).queue_free()
		(s["body"] as StaticBody2D).queue_free()
	strokes.clear()
	if riding and is_instance_valid(vehicle):
		var seat_g: Vector2 = vehicle.to_global(veh_seat)
		_destroy_vehicle_silent()
		_place_runner_at(seat_g, Vector2.ZERO)
	else:
		_destroy_vehicle_silent()

func _damage_stroke(s: Dictionary) -> void:
	s["hp"] = int(s["hp"]) - 1
	var line = s["line"]
	if int(s["hp"]) <= 0:
		line.queue_free()
		(s["body"] as StaticBody2D).queue_free()
		strokes.erase(s)
		grabbing = false
		grab_idx = -1
	else:
		var a := 0.35 + 0.65 * float(s["hp"]) / float(s["max_hp"])
		line.modulate.a = a

# ---------- score + popups ----------
func _add_score(amount: int, at: Vector2, label: String) -> void:
	score += amount
	hud_score.text = "%d pts" % score
	if label != "":
		_popup(at, label, INK)

func _popup(at: Vector2, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", color)
	lbl.position = at + Vector2(rng.randf_range(-8, 8), 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 60.0, 0.9)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.9)
	tw.set_parallel(false)
	tw.tween_callback(lbl.queue_free)

func _spawn_dust(at: Vector2, big: bool) -> void:
	if dust_count > 40:
		return
	dust_count += 1
	var p := Polygon2D.new()
	var r := 7.0 if big else 4.0
	var pts := PackedVector2Array()
	for i in 7:
		var a := TAU * float(i) / 6.0
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	p.polygon = pts
	p.color = Color(0.18, 0.17, 0.15, 0.30)
	p.position = at
	add_child(p)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "position", at + Vector2(rng.randf_range(-30, -10), rng.randf_range(-34, -18)), 0.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.set_parallel(false)
	tw.tween_callback(p.queue_free)
	tw.tween_callback(_dust_freed)

func _dust_freed() -> void:
	dust_count = maxi(0, dust_count - 1)

# ---------- geometry helpers ----------
func _pt_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.001:
		return p.distance_to(a)
	var u := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * u)

func _segs_cross(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	var d := (a2 - a1).cross(b2 - b1)
	if absf(d) < 0.0001:
		return false
	var u := ((b1 - a1).cross(b2 - b1)) / d
	var v := ((b1 - a1).cross(a2 - a1)) / d
	return u >= 0.0 and u <= 1.0 and v >= 0.0 and v <= 1.0

func _seg_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var c := [r.position, r.position + Vector2(r.size.x, 0), r.position + r.size, r.position + Vector2(0, r.size.y)]
	for i in 4:
		if _segs_cross(a, b, c[i], c[(i + 1) % 4]):
			return true
	return false

# ---------- rocks: chest inside the stone kills, shoulders scramble ----------
# 0 = miss, 1 = shoulder brush (climb), 2 = face-first (kill)
func _core_test(body: Object) -> int:
	for ch in (body as Node).get_children():
		if ch is CollisionShape2D and (ch as CollisionShape2D).shape is RectangleShape2D:
			var sz: Vector2 = ((ch as CollisionShape2D).shape as RectangleShape2D).size
			var c: Vector2 = (ch as CollisionShape2D).global_position
			var chest: Vector2 = runner.global_position + Vector2(0, -55)
			var top := c.y - sz.y * 0.5
			# edge distance from the chest point to the stone. A pressed
			# face-plant parks ~10px off the face (capsule radius), so the
			# kill band must reach past that or he sticks alive forever.
			var dx := maxf(c.x - sz.x * 0.5 - chest.x, maxf(0.0, chest.x - (c.x + sz.x * 0.5)))
			var dy := maxf(top - chest.y, maxf(0.0, chest.y - (top + sz.y)))
			var dist := Vector2(dx, dy).length()
			var near_top := chest.y < top + 18.0 and chest.x > c.x - sz.x * 0.5 - 30.0 and chest.x < c.x + sz.x * 0.5 + 30.0
			# top 18px band, reached from a ramp or bridge: scramble onto
			# the shoulder instead of dying. A level run hits the face.
			if near_top and dist < 30.0:
				return 1
			if dist < 12.0:
				return 2
			return 0
	return 2 # no shape found: fall back to killing (safe default)

func _spawn_rock_at(x: float) -> void:
	var tex := _cut("res://assets/obstacles/cut/rock.png")
	var n := Node2D.new()
	n.position = Vector2(x, 0)
	var s := Sprite2D.new()
	s.texture = tex
	var sc := rng.randf_range(0.50, 0.60)
	s.scale = Vector2(sc, sc)
	var sh := float(tex.get_height()) * sc
	s.position = Vector2(0, GROUND_Y - sh * 0.5 + 10.0)
	n.add_child(s)
	var body := StaticBody2D.new()
	body.collision_layer = 0 if nodmg else 1
	body.collision_mask = 0
	body.set_meta("kills", true)
	var rect := RectangleShape2D.new()
	# erode past the bbox: grassy edges and empty corners don't kill,
	# only the stone core within ~5px of his body does
	rect.size = (Vector2(float(tex.get_width()) * sc, sh) * 0.85) - Vector2(20, 20)
	var col := CollisionShape2D.new()
	col.shape = rect
	col.position = s.position
	body.add_child(col)
	n.add_child(body)
	n.set_meta("w", rect.size.x)
	n.set_meta("h", rect.size.y)
	add_child(n)
	rocks.append({"node": n, "stopped": false})

func _spawn_coin(x: float) -> void:
	var c := Sprite2D.new()
	c.texture = _cut("res://assets/pickups/cut/gold_closed.png")
	c.scale = Vector2(0.35, 0.35)
	var ch := float(c.texture.get_height()) * 0.35
	c.position = Vector2(x, GROUND_Y - 120.0)
	add_child(c)
	coins.append({"node": c, "base_y": c.position.y, "taken": false})

# ---------- arrows ----------
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
	var vel := (target - from).normalized() * ARROW_SPEED
	n.rotation = vel.angle()
	add_child(n)
	arrows.append({"node": n, "vel": vel, "life": 6.0})

# ---------- win / lose ----------
# sad face in its own fixed box so it flows inside container layouts
func _make_face() -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(150, 140)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := Node2D.new()
	f.position = Vector2(75, 66)
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in 41:
		var a := TAU * float(i) / 40.0
		pts.append(Vector2(cos(a), sin(a)) * 44.0)
	ring.points = pts
	ring.width = 5.0
	ring.default_color = INK
	f.add_child(ring)
	for ex in [-16.0, 16.0]:
		var eye := Polygon2D.new()
		var ep := PackedVector2Array()
		for i in 13:
			var a := TAU * float(i) / 12.0
			ep.append(Vector2(ex, -10) + Vector2(cos(a), sin(a)) * 6.0)
		eye.polygon = ep
		eye.color = INK
		f.add_child(eye)
	var frown := Line2D.new()
	var fp := PackedVector2Array()
	# shallow parabola mouth, low in the face: sad, not eyebrows
	for i in 25:
		var x := -20.0 + 40.0 * float(i) / 24.0
		fp.append(Vector2(x, 12.0 + (x / 20.0) * (x / 20.0) * 8.0))
	frown.points = fp
	frown.width = 5.0
	frown.default_color = INK
	f.add_child(frown)
	box.add_child(f)
	return box

func _end_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _stars() -> int:
	if score >= 500 and used_car:
		return 3
	if score >= 250:
		return 2
	return 1

func _show_end(title: String, sub: String, sad: bool) -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.96, 0.95, 0.89, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	# containers do the spreading: centered stack, even gaps, every viewport
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 28)
	center.add_child(vbox)
	vbox.add_child(_end_label(title, 64))
	if sad:
		vbox.add_child(_make_face())
	vbox.add_child(_end_label(sub + ("\nPress R to retry" if sad else ""), 26))
	var again := Button.new()
	again.text = "Try Again" if sad else "Play Again"
	again.custom_minimum_size = Vector2(240, 64)
	again.add_theme_font_size_override("font_size", 30)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(_on_restart_btn)
	vbox.add_child(again)
	ui.add_child(overlay)

func _lose(reason: String) -> void:
	if state != "run":
		return
	state = "dying"
	runner.velocity = Vector2.ZERO
	runner.modulate = Color(1, 0.35, 0.35)
	runner_anim.stop()
	Engine.time_scale = 1.0
	sfx_roll.volume_db = -60.0
	death_timer = 0.7
	print("LOSE: " + reason)
	var why: String = {
		"arrow hit": "An arrow got him.",
		"hit an obstacle": "He slammed into a rock.",
		"fell from height": "He fell too far.",
		"time ran out": "Time ran out.",
	}.get(reason, reason)
	pending_title = "GAME OVER"
	pending_sub = "%s\nStick couldn't get the bag\nScore: %d pts" % [why, score]
	pending_sad = true

func _win() -> void:
	if state != "run":
		return
	state = "win"
	Engine.time_scale = 1.0
	sfx_roll.volume_db = -60.0
	if is_instance_valid(gold):
		gold.queue_free()
	hug = AnimatedSprite2D.new()
	hug.sprite_frames = _frames([
		"res://assets/celebrate/cut/hug_1.png",
		"res://assets/celebrate/cut/hug_2.png",
		"res://assets/celebrate/cut/hug_3.png",
		"res://assets/celebrate/cut/hug_4.png",
	], 6.0)
	hug.scale = Vector2(0.5, 0.5)
	hug.position = Vector2(gold_x + 130, GROUND_Y - 110)
	hug.play()
	add_child(hug)
	var st := _stars()
	var car_line := " - Car: yes!" if used_car else ""
	_show_end("YOU GOT THE BAG!", "Stars: %d/3 - Score: %d pts\nCoins: %d/%d%s" % [st, score, coins_got, coins_total, car_line], false)
	print("WIN: runner reached the gold score=%d stars=%d" % [score, st])

# ---------- per-frame ----------
func _physics_process(dt: float) -> void:
	if state != "run":
		return
	t += dt
	time_left -= dt
	invuln = maxf(0.0, invuln - dt)
	veh_hit_cd = maxf(0.0, veh_hit_cd - dt)
	if riding and is_instance_valid(vehicle):
		_physics_ride(dt)
	else:
		_physics_run(dt)
	# pending car: he runs into a loop drawn far ahead, hops in on touch
	if is_instance_valid(vehicle) and not riding:
		if runner.global_position.distance_to(vehicle.global_position) < 140.0:
			_board_vehicle()
		elif vehicle.global_position.x < runner.global_position.x - 900.0:
			_destroy_vehicle_silent()
	if runner.global_position.x >= gold_x - 90.0:
		_win()
		return
	if time_left <= 0.0:
		_lose("time ran out")
		return

func _physics_run(dt: float) -> void:
	# runner charges right; walls stop him, ramps lift him, timer running out loses
	var on_floor_before := runner.is_on_floor()
	runner.velocity.x = SPEED
	runner.velocity.y += GRAV * dt
	runner.move_and_slide()
	# step-up assist: walled on the ground with a low surface above the feet
	# (ramp foot floating slightly off the ground) -> lift onto it. Skipped
	# while touching stone: lifting at a rock face would feed him into
	# scramble range and let him mount every rock with no drawing.
	var walled_on_ink := false
	if (runner.is_on_floor() or on_floor_before) and absf(runner.get_real_velocity().x) < 40.0:
		var on_rock := false
		for i in runner.get_slide_collision_count():
			var c := runner.get_slide_collision(i).get_collider()
			if c != null and (c as Object).has_meta("kills"):
				on_rock = true
				break
		if not on_rock:
			walled_on_ink = true
	if walled_on_ink:
		var climbed := false
		for i in range(40):
			var up := Vector2(0, -(i + 1))
			var lifted := runner.global_transform.translated(up)
			if not runner.test_move(lifted, Vector2(4, 0)) and runner.test_move(lifted, Vector2(0, 44)):
				runner.global_position += up
				climbed = true
				break
		if climbed and not nodmg:
			_add_score(0, runner.global_position + Vector2(-30, -120), "")
	# glide assist: walled on the ground against his own ink (or the ground)
	# on a climbable face -> slide up along it so any drawn ramp or arch
	# carries him. Faces steeper than 65 deg are still walls by design.
	if (runner.is_on_floor() or on_floor_before) and absf(runner.get_real_velocity().x) < 40.0:
		for i in runner.get_slide_collision_count():
			var sc := runner.get_slide_collision(i)
			var collider := sc.get_collider()
			if collider != null and (collider as Object).has_meta("kills"):
				continue
			if sc.get_normal().angle_to(Vector2.UP) < deg_to_rad(65.0):
				var tang := Vector2(sc.get_normal().y, -sc.get_normal().x)
				if tang.x < 0.0:
					tang = -tang
				if tang.y > -0.15:
					tang.y = -0.35
				runner.global_position += tang.normalized() * SPEED * 0.85 * dt
				break
	if not runner.is_on_floor():
		was_air = true
		peak_fall = maxf(peak_fall, runner.velocity.y)
	elif was_air:
		was_air = false
		if peak_fall > KILL_FALL and not nodmg and invuln <= 0.0:
			_lose("fell from height")
			return
		elif peak_fall > 500.0:
			_add_score(50, runner.global_position + Vector2(-40, -120), "LAND +50")
		peak_fall = 0.0
	for i in runner.get_slide_collision_count():
		var col := runner.get_slide_collision(i).get_collider()
		if col != null and col.has_meta("kills") and not nodmg and invuln <= 0.0:
			var verdict := _core_test(col)
			if verdict == 2:
				_lose("hit an obstacle")
				return
			elif verdict == 1:
				# shoulder brush: scramble up instead of dying
				for k in range(24):
					var up := Vector2(0, -(float(k) + 1.0) * 2.0)
					var lifted := runner.global_transform.translated(up)
					if not runner.test_move(lifted, Vector2(6, 0)):
						runner.global_position += up
						break

func _physics_ride(dt: float) -> void:
	if not is_instance_valid(vehicle):
		riding = false
		return
	# drive: constant push toward VEH_SPEED, physics handles slopes
	if vehicle.linear_velocity.x < VEH_SPEED:
		vehicle.constant_force = Vector2(VEH_FORCE, 0)
	else:
		vehicle.constant_force = Vector2.ZERO
	# tilt law: nose follows vertical velocity (up = nose up, down = nose down),
	# spring back to level, hard clamp so it never flips or plows
	var want := clampf(vehicle.linear_velocity.y * 0.0009, -0.5, 0.5)
	var torque := (want - vehicle.rotation) * 1400.0 - vehicle.angular_velocity * 160.0
	vehicle.constant_torque = clampf(torque, -2000.0, 2000.0)
	if absf(vehicle.rotation) > 0.45:
		vehicle.rotation = clampf(vehicle.rotation, -0.45, 0.45)
		vehicle.angular_velocity *= 0.2
	# he sits in the hull and leans with it
	var seat_g: Vector2 = vehicle.to_global(veh_seat)
	runner.global_position = seat_g
	runner.rotation = vehicle.rotation
	runner.velocity = vehicle.linear_velocity
	# wheels spin with ground speed
	var spin: float = vehicle.linear_velocity.x / 10.0
	for hub in veh_wheels:
		(hub as Node2D).rotation += spin * dt
	# rolling hum tracks speed
	var spd := vehicle.linear_velocity.length()
	# climb assist, parity with feet: nosing into a climbable lip of his own
	# ink at low speed pops the hull up instead of stalling out and tossing
	# him. Same 65-degree rule as the feet glide; flat ground reads 0 deg
	# and is skipped, rocks (kills) stop him as before.
	if spd < 140.0:
		var space := get_world_2d().direct_space_state
		var qp := PhysicsRayQueryParameters2D.create(
			vehicle.global_position + Vector2(veh_radius * 0.6, veh_radius * 0.2),
			vehicle.global_position + Vector2(veh_radius * 0.6 + 46.0, veh_radius * 0.2 + 34.0))
		qp.collision_mask = 1
		qp.exclude = [vehicle.get_rid(), runner.get_rid()]
		var hit := space.intersect_ray(qp)
		if not hit.is_empty():
			var hb = hit["collider"]
			if hb != null and not (hb as Object).has_meta("kills"):
				var nrm: Vector2 = hit["normal"]
				var tilt := nrm.angle_to(Vector2.UP)
				if tilt > deg_to_rad(15.0) and tilt < deg_to_rad(65.0):
					vehicle.linear_velocity.y = minf(vehicle.linear_velocity.y, -140.0)
					vehicle.linear_velocity.x = maxf(vehicle.linear_velocity.x, 140.0)
					spd = vehicle.linear_velocity.length()
	sfx_roll.volume_db = lerpf(-60.0, -12.0, clampf(spd / VEH_SPEED, 0.0, 1.0))
	sfx_roll.pitch_scale = 0.8 + spd / 700.0
	_spawn_dust(vehicle.global_position + Vector2(-veh_radius, 10), true)
	# rock impacts go to the hull, not his chest
	var bodies := vehicle.get_colliding_bodies()
	var touching_rock := false
	for b in bodies:
		if b != null and (b as Object).has_meta("kills"):
			touching_rock = true
			break
	if touching_rock and veh_hit_cd <= 0.0:
		if spd > 300.0 and not nodmg:
			_damage_vehicle(3, seat_g + Vector2(-50, -70), "CRASH -3")
			vehicle.linear_velocity *= 0.15
		elif not nodmg:
			_damage_vehicle(1, seat_g + Vector2(-50, -70), "SCRAPE -1")
			vehicle.linear_velocity *= 0.6
		if not is_instance_valid(vehicle):
			return
	# hard landings wreck the hull; the ejection saves him
	var airborne := bodies.is_empty()
	if airborne:
		veh_was_air = true
		veh_peak = maxf(veh_peak, vehicle.linear_velocity.y)
	elif veh_was_air:
		veh_was_air = false
		if veh_peak > KILL_FALL and not nodmg:
			_break_vehicle("DROPPED!")
			return
		veh_peak = 0.0
	# stalled against a wall: auto hop-off so he is never stuck
	if spd < 30.0:
		veh_stop_t += dt
		if veh_stop_t > 1.5:
			_eject_vehicle(true, "stuck!")
			return
	else:
		veh_stop_t = 0.0
	# near miss on foot earns nothing here; blocks are scored in the arrow loop

func _process(dt: float) -> void:
	# sky drifts on the page; camera chases whoever is moving (feet or hull)
	for c in clouds:
		var cn := c as Node2D
		cn.position.x -= 12.0 * dt
		if cn.position.x < -200:
			cn.position.x = W + 200
	var focus_x := runner.global_position.x
	if riding and is_instance_valid(vehicle):
		focus_x = vehicle.global_position.x
	if is_instance_valid(cam):
		cam.position.x = focus_x + 200.0
		cam.position.y = 360.0
	# shadow tracks the moving body, shrinks with height
	if is_instance_valid(shadow) and is_instance_valid(runner):
		var h := clampf(GROUND_Y - runner.global_position.y, 0.0, 400.0)
		shadow.position = Vector2(runner.global_position.x, GROUND_Y + 6.0)
		var s := clampf(1.0 - h / 500.0, 0.3, 1.0)
		shadow.scale = Vector2(s, s)
		shadow.modulate.a = 0.20 * s
	# story card fades
	if is_instance_valid(title_lbl) and t > 3.0:
		title_lbl.modulate.a = maxf(0.0, title_lbl.modulate.a - dt * 0.8)
	# dying beat: freeze a moment on the red flash, then the overlay
	if state == "dying":
		Engine.time_scale = 1.0
		death_timer -= dt
		if death_timer <= 0.0:
			state = "lose"
			_show_end(pending_title, pending_sub, pending_sad)
		return
	if state == "lose" or state == "win":
		Engine.time_scale = 1.0
		return
	# ink regen + bar
	if not drawing:
		ink = minf(INK_MAX, ink + INK_REGEN * dt)
	hud_ink_bar.size.x = 220.0 * ink / INK_MAX
	hud_ink_bar.color = Color(0.75, 0.2, 0.15) if ink < 25.0 else INK
	# slow-mo ground truth: only while input is truly held, never leaks
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or drawing or grabbing
	Engine.time_scale = 0.45 if held else 1.0
	# footsteps on the ground, alternating feet
	if not riding and runner.is_on_floor() and absf(runner.velocity.x) > 100.0:
		step_t += dt
		if step_t >= 0.30:
			step_t = 0.0
			step_alt = not step_alt
			sfx_step.pitch_scale = 1.0 if step_alt else 0.88
			sfx_step.play()
		_spawn_dust(runner.global_position + Vector2(-8, -2), false)
	# stuck on his own ink? point at the way out instead of leaving him there
	stuck_hint_cd = maxf(0.0, stuck_hint_cd - dt)
	if not riding and not drawing and not grabbing and runner.is_on_floor() and absf(runner.velocity.x) > 100.0:
		if absf(runner.get_real_velocity().x) < 30.0:
			stuck_t += dt
			if stuck_t > 2.5 and stuck_hint_cd <= 0.0:
				stuck_hint_cd = 15.0
				stuck_t = 0.0
				_popup(runner.global_position + Vector2(-80, -140), "stuck? C clears ink", INK)
		else:
			stuck_t = 0.0
	else:
		stuck_t = 0.0
	# test hooks headlessly
	if "--autocar" in cli_args and t >= 1.0 and not is_instance_valid(vehicle):
		var cx := runner.global_position.x + 400.0
		var cy := GROUND_Y - 80.0
		var loop := Line2D.new()
		var pts := PackedVector2Array()
		for k in 17:
			var a := TAU * float(k) / 16.0
			pts.append(Vector2(cx, cy) + Vector2(cos(a) * 80.0, sin(a) * 45.0))
		loop.points = pts
		add_child(loop)
		_build_vehicle(loop)
		print("AUTOCAR: riding=%s hp=%d" % [str(riding), veh_hp])
	if "--autoshield" in cli_args and t >= 1.0 and strokes.is_empty():
		var sh := Line2D.new()
		var sx := runner.global_position.x + 200.0
		sh.points = PackedVector2Array([Vector2(sx, GROUND_Y - 90.0), Vector2(sx + 400.0, GROUND_Y - 90.0)])
		add_child(sh)
		_seal_stroke(sh)
		print("AUTOSHIELD: strokes=%d" % strokes.size())
	if "--autoramp55" in cli_args and t >= 1.0 and strokes.is_empty():
		# 55-degree straight ramp: steeper than floor_max_angle, must glide up
		var rp := Line2D.new()
		var rpts := PackedVector2Array()
		var rx := runner.global_position.x + 150.0
		for k in 25:
			var u := float(k) / 24.0
			rpts.append(Vector2(rx + u * 140.0, GROUND_Y - u * 200.0))
		rp.points = rpts
		add_child(rp)
		_seal_stroke(rp)
		print("AUTORAMP55: strokes=%d" % strokes.size())
	if "--autodraw" in cli_args and t >= 1.0 and strokes.is_empty():
		var test := Line2D.new()
		test.points = PackedVector2Array([Vector2(100, 300), Vector2(700, 300)])
		add_child(test)
		_seal_stroke(test)
		print("AUTODRAW: strokes=%d" % strokes.size())
	# timer + progress HUD
	var mm := int(maxf(time_left, 0.0)) / 60
	var ss := int(maxf(time_left, 0.0)) % 60
	hud_timer.text = "%d:%02d" % [mm, ss]
	hud_prog_fill.size.x = 300.0 * clampf(focus_x / gold_x, 0.0, 1.0)
	# platform drops in as the runner closes in
	if plat_drop_t < 0.0 and focus_x >= PLAT0 - 1100.0:
		plat_drop_t = 0.0
	if plat_drop_t >= 0.0 and not plat_placed:
		plat_drop_t += dt
		var u := clampf(plat_drop_t / 1.2, 0.0, 1.0)
		plat.position.y = -420.0 * (1.0 - u * u)
		if u >= 1.0:
			plat_placed = true
			if not plat_rumbled:
				plat_rumbled = true
				sfx_crash.volume_db = -18.0
				sfx_crash.play()
				sfx_crash.volume_db = -6.0
	# archer senses runner, faces him, shoots down with drop-compensated aim
	if plat_placed:
		var ap := archer.global_position
		var rp := runner.global_position + Vector2(0, -65)
		var to := rp - ap
		if absf(to.x) < 800.0:
			# bow tracks his chest exactly; the fired arrow leads him
			var want := clampf(to.angle(), deg_to_rad(5.0), deg_to_rad(175.0))
			archer.rotation = lerp_angle(archer.rotation, want, 12.0 * dt)
			archer_cd -= dt
			if t > archer_release_until:
				archer.frame = 0
			if archer_cd <= 0.0:
				archer_cd = 3.6
				archer_release_until = t + 0.3
				archer.frame = 1
				var dist := to.length()
				var tof := dist / ARROW_SPEED
				var lead: Vector2 = rp + Vector2(SPEED * tof, 0.0)
				tof = (lead - ap).length() / ARROW_SPEED
				lead = rp + Vector2(SPEED * tof, 0.0)
				var aim: Vector2 = lead + Vector2(0, -0.5 * 160.0 * tof * tof)
				_spawn_arrow(ap + Vector2(45, 0).rotated(archer.rotation), aim)
				sfx_step.pitch_scale = 0.5
				sfx_step.play()
	# rocks are static; drop them once far behind the camera
	for r in rocks.duplicate():
		var n = r["node"]
		if not is_instance_valid(n):
			rocks.erase(r)
			continue
		if n.position.x < focus_x - 900.0:
			n.queue_free()
			rocks.erase(r)
	# coins bob; grab radius is generous in the car
	for cn in coins:
		if bool(cn["taken"]):
			continue
		var cnode = cn["node"]
		if not is_instance_valid(cnode):
			continue
		cnode.position.y = float(cn["base_y"]) + sin(t * 2.0 + float(cn["base_y"])) * 6.0
		var grab_r := 60.0 if riding else 46.0
		if runner.global_position.distance_to(cnode.position) < grab_r:
			cn["taken"] = true
			cnode.queue_free()
			coins_got += 1
			sfx_coin.play()
			_add_score(25, cnode.position + Vector2(-20, -30), "+25")
	# arrows fly; the hull takes hits while riding, shields wear down on foot
	for arrow in arrows.duplicate():
		var n = arrow["node"]
		if not is_instance_valid(n):
			arrows.erase(arrow)
			continue
		var v: Vector2 = arrow["vel"]
		v.y += 160.0 * dt
		arrow["vel"] = v
		arrow["life"] = float(arrow["life"]) - dt
		n.position += v * dt
		n.rotation = v.angle()
		var done := false
		if riding and is_instance_valid(vehicle):
			if n.position.distance_to(vehicle.global_position) < veh_radius + 18.0:
				_damage_vehicle(1, n.position + Vector2(-30, -20), "BLOCK +100")
				if is_instance_valid(vehicle):
					_add_score(100, n.position + Vector2(-30, -40), "")
				else:
					_add_score(100, n.position + Vector2(-30, -40), "")
				done = true
		elif n.position.distance_to(runner.global_position + Vector2(0, -65)) < 34.0 and not nodmg and invuln <= 0.0:
			_lose("arrow hit")
			return
		# live line also blocks arrows; hits carry into its durability on release
		if not done and drawing and cur_line != null and cur_line.get_point_count() > 1:
			for i in range(cur_line.get_point_count() - 1):
				var ca := cur_line.to_global(cur_line.get_point_position(i))
				var cb := cur_line.to_global(cur_line.get_point_position(i + 1))
				if _pt_seg_dist(n.position, ca, cb) < 12.0:
					cur_hits += 1
					done = true
					break
		for s in strokes.duplicate():
			var line = s["line"]
			if not is_instance_valid(line):
				continue
			for i in range(line.get_point_count() - 1):
				var ga: Vector2 = line.to_global(line.get_point_position(i))
				var gb: Vector2 = line.to_global(line.get_point_position(i + 1))
				if _pt_seg_dist(n.position, ga, gb) < 12.0:
					_damage_stroke(s)
					_add_score(100, n.position + Vector2(-40, -20), "BLOCK +100")
					done = true
					break
			if done:
				break
		if not done and (n.position.y >= GROUND_Y - 4.0 or n.position.x < -60.0 or float(arrow["life"]) <= 0.0):
			done = true
		if done:
			n.queue_free()
			arrows.erase(arrow)
	# gold bobs on the ground where it waits
	if is_instance_valid(gold):
		gold.position.y += sin(t * 2.0) * 2.0 * dt
