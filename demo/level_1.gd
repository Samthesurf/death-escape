extends Node2D
## Level 1: survive 3 minutes, reach the gold.
## Sun + clouds only, then the sky platform drops in with 1 archer who
## faces and shoots the runner. Draw ramps (climb over rocks) and shields
## (block arrows, limited durability). One hit / rock / hard fall = game over.

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
const ROCK_XS := [3000.0, 6000.0, 9000.0, 12000.0, 15000.0, 17500.0]

var level_time := 90.0
var time_left := 0.0
var gold_x := 19000.0
var state := "run" # run | win | lose
var nodmg := false # test hook: --nodmg disables deaths
var cli_args: PackedStringArray
var t := 0.0
var rng := RandomNumberGenerator.new()

var runner: CharacterBody2D
var runner_anim: AnimatedSprite2D
var peak_fall := 0.0
var was_air := false

var strokes: Array = [] # each {line, body, hp, max_hp}
var drawing := false
var cur_line: Line2D
var cur_body: StaticBody2D
var cur_hits := 0
var grabbing := false
var grab_idx := -1
var grab_prev := Vector2.ZERO
var move_mode := false
var move_btn: Button
var death_timer := 0.0
var pending_title := ""
var pending_sub := ""
var pending_sad := true

var block_tex: Texture2D
var plat: Node2D
var plat_placed := false
var plat_drop_t := -1.0
var archer: AnimatedSprite2D
var archer_cd := 3.0
var archer_release_until := 0.0
var arrows: Array = []

var rocks: Array = [] # each {node}
var rock_timer := 4.0

var gold: Sprite2D
var gold_spawned := false
var hug: AnimatedSprite2D

var hud_timer: Label
var overlay: Control
var ui: CanvasLayer
var cam: Camera2D
var clouds: Array = []

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
	bg.size = Vector2(W, H)
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
	# runner body (0.4 scale, ink feet at canvas bottom sit exactly on origin)
	runner = CharacterBody2D.new()
	runner.position = Vector2(RUNNER_X, GROUND_Y - 2)
	runner.collision_layer = 1
	runner.collision_mask = 1
	runner.floor_snap_length = 10.0
	runner.floor_max_angle = deg_to_rad(50.0)
	var cap := CapsuleShape2D.new()
	# slim: his drawn limbs are thin lines, kill only when truly close
	cap.radius = 10.0
	cap.height = 100.0
	var capcol := CollisionShape2D.new()
	capcol.shape = cap
	capcol.position = Vector2(0, -50)
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
	add_child(runner)
	# sky platform (drops in at t=6), smaller blocks
	block_tex = _cut("res://assets/obstacles/cut/block.png")
	plat = Node2D.new()
	plat.position.y = -420.0
	add_child(plat)
	var tile_w := float(block_tex.get_width()) * 0.18
	for i in 3:
		var tile := Sprite2D.new()
		tile.texture = block_tex
		tile.scale = Vector2(0.18, 0.18)
		tile.position = Vector2(PLAT0 + tile_w * (float(i) + 0.5), 330.0)
		plat.add_child(tile)
	archer = AnimatedSprite2D.new()
	archer.sprite_frames = _frames([
		"res://assets/enemies/cut/archer_draw.png",
		"res://assets/enemies/cut/archer_release.png",
	], 2.0)
	archer.scale = Vector2(0.45, 0.45)
	archer.rotation = deg_to_rad(90.0) # start aiming down
	archer.position = Vector2(PLAT0 + tile_w * 1.5, 330.0 - 39.0 - 58.0)
	archer.play()
	plat.add_child(archer)
	# rocks sit in the world ahead; gold waits at the end
	for rx in ROCK_XS:
		if rx < gold_x and not "--norocks" in cli_args:
			_spawn_rock_at(rx)
	gold = Sprite2D.new()
	gold.texture = _cut("res://assets/pickups/cut/gold_open.png")
	gold.scale = Vector2(0.45, 0.45)
	var gh0 := float(gold.texture.get_height()) * 0.45
	gold.position = Vector2(gold_x, GROUND_Y - gh0 * 0.5 + 6.0)
	add_child(gold)
	# HUD
	hud_timer = Label.new()
	hud_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_timer.add_theme_font_size_override("font_size", 40)
	hud_timer.add_theme_color_override("font_color", INK)
	hud_timer.position = Vector2(W * 0.5 - 60, 12)
	ui.add_child(hud_timer)
	var hint := Label.new()
	hint.text = "Drag draws in slow-mo (ramps + shields, they wear out). Move mode drags a drawing."
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", INK)
	hint.position = Vector2(16, H - 34)
	ui.add_child(hint)
	# touch buttons: move toggle, clear, restart (keys don't exist on phone)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.anchor_left = 1.0
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -330.0
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

func _on_clear_btn() -> void:
	_clear_strokes()

func _on_restart_btn() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

# ---------- drawing: ramps + shields with durability ----------
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
			cur_line.add_point(mp)
			var n := cur_line.get_point_count()
			if n > 1 and cur_body != null:
				cur_body.add_child(_seg_collider(cur_line.get_point_position(n - 2), cur_line.get_point_position(n - 1)))
	elif event is InputEventMouseMotion and grabbing and grab_idx >= 0:
		if grab_idx < strokes.size():
			var line: Line2D = strokes[grab_idx]["line"]
			var body: StaticBody2D = strokes[grab_idx]["body"]
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

func _seg_collider(a: Vector2, b: Vector2) -> CollisionShape2D:
	var shape := RectangleShape2D.new()
	# ends extend past the drawn endpoints: feet bury under the ground
	# plane instead of presenting a vertical end-cap wall at the junction
	shape.size = Vector2(a.distance_to(b) + 14.0 + 48.0, 14.0)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = (a + b) * 0.5
	col.rotation = (b - a).angle()
	return col

func _register_stroke(line: Line2D, body: StaticBody2D) -> void:
	var segs := line.get_point_count() - 1
	var hp := mini(6 + segs / 2, 18) - cur_hits
	cur_hits = 0
	if hp <= 0:
		line.queue_free()
		body.queue_free()
		return
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

func _stroke_at(mp: Vector2) -> int:
	var best := -1
	var best_d := 30.0
	for si in strokes.size():
		var line: Line2D = strokes[si]["line"]
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
	var line: Line2D = strokes[grab_idx]["line"]
	if is_instance_valid(line):
		var a := line.modulate.a
		line.modulate = Color(0.45, 0.65, 1.0, a) if on else Color(1, 1, 1, a)

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

func _damage_stroke(s: Dictionary) -> void:
	s["hp"] = int(s["hp"]) - 1
	var line: Line2D = s["line"]
	if int(s["hp"]) <= 0:
		line.queue_free()
		(s["body"] as StaticBody2D).queue_free()
		strokes.erase(s)
		grabbing = false
		grab_idx = -1
	else:
		var a := 0.35 + 0.65 * float(s["hp"]) / float(s["max_hp"])
		line.modulate.a = a

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

# ---------- rocks (static in the world, runner climbs over via ramps) ----------
func _core_hits(body: Object) -> bool:
	# world rect of the rock's stone core vs his chest point
	for ch in (body as Node).get_children():
		if ch is CollisionShape2D and (ch as CollisionShape2D).shape is RectangleShape2D:
			var sz: Vector2 = ((ch as CollisionShape2D).shape as RectangleShape2D).size
			var c: Vector2 = (ch as CollisionShape2D).global_position
			var chest: Vector2 = runner.global_position + Vector2(0, -55)
			var dx := maxf(c.x - sz.x * 0.5 - chest.x, maxf(0.0, chest.x - (c.x + sz.x * 0.5)))
			var dy := maxf(c.y - sz.y * 0.5 - chest.y, maxf(0.0, chest.y - (c.y + sz.y * 0.5)))
			# 14px = capsule radius (10) + a hair: face-first contact kills,
			# foot clips and near misses don't
			return Vector2(dx, dy).length() < 14.0
	return true # no shape found: fall back to killing (safe default)
func _spawn_rock_at(x: float) -> void:
	var tex := _cut("res://assets/obstacles/cut/rock.png")
	var n := Node2D.new()
	n.position = Vector2(x, 0)
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2(0.55, 0.55)
	var sh := float(tex.get_height()) * 0.55
	s.position = Vector2(0, GROUND_Y - sh * 0.5 + 10.0)
	n.add_child(s)
	var body := StaticBody2D.new()
	body.collision_layer = 0 if nodmg else 1
	body.collision_mask = 0
	body.set_meta("kills", true)
	var rect := RectangleShape2D.new()
	# erode past the bbox: grassy edges and empty corners don't kill,
	# only the stone core within ~5px of his body does
	rect.size = (Vector2(float(tex.get_width()) * 0.55, sh) * 0.85) - Vector2(20, 20)
	var col := CollisionShape2D.new()
	col.shape = rect
	col.position = s.position
	body.add_child(col)
	n.add_child(body)
	n.set_meta("w", rect.size.x)
	n.set_meta("h", rect.size.y)
	add_child(n)
	rocks.append({"node": n, "stopped": false})

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
func _sad_face(parent: Control, center: Vector2) -> void:
	var f := Node2D.new()
	f.position = center
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
	# Node2D inside Control needs a canvas parent: wrap via Node2D at top level instead
	parent.add_child(f)

func _show_end(title: String, sub: String, sad: bool) -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.96, 0.95, 0.89, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 72)
	t.add_theme_color_override("font_color", INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.set_anchors_preset(Control.PRESET_TOP_WIDE)
	t.offset_top = 220.0
	overlay.add_child(t)
	if sad:
		_sad_face(overlay, Vector2(W * 0.5, 420))
	var s := Label.new()
	s.text = sub + ("\nPress R to retry" if sad else "")
	s.add_theme_font_size_override("font_size", 28)
	s.add_theme_color_override("font_color", INK)
	s.position = Vector2(W * 0.5 - 220, 490)
	overlay.add_child(s)
	if sad:
		var again := Button.new()
		again.text = "Try Again"
		again.custom_minimum_size = Vector2(220, 64)
		again.add_theme_font_size_override("font_size", 30)
		again.position = Vector2(W * 0.5 - 110, 620)
		again.pressed.connect(_on_restart_btn)
		overlay.add_child(again)
	else:
		var again := Button.new()
		again.text = "Play Again"
		again.custom_minimum_size = Vector2(220, 64)
		again.add_theme_font_size_override("font_size", 30)
		again.position = Vector2(W * 0.5 - 110, 560)
		again.pressed.connect(_on_restart_btn)
		overlay.add_child(again)
	ui.add_child(overlay)

func _lose(reason: String) -> void:
	if state != "run":
		return
	state = "dying"
	runner.velocity = Vector2.ZERO
	runner.modulate = Color(1, 0.35, 0.35)
	runner_anim.stop()
	Engine.time_scale = 1.0
	death_timer = 0.7
	print("LOSE: " + reason)
	var why: String = {
		"arrow hit": "An arrow got him.",
		"hit an obstacle": "He slammed into a rock.",
		"fell from height": "He fell too far.",
		"time ran out": "Time ran out.",
	}.get(reason, reason)
	pending_title = "GAME OVER"
	pending_sub = "%s\nStick couldn't get the bag" % why
	pending_sad = true

func _win() -> void:
	if state != "run":
		return
	state = "win"
	Engine.time_scale = 1.0
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
	_show_end("YOU GOT THE BAG!", "", false)
	print("WIN: runner reached the gold")

# ---------- per-frame ----------
func _physics_process(dt: float) -> void:
	if state != "run":
		return
	t += dt
	time_left -= dt
	# runner charges right; walls stop him, ramps lift him, timer running out loses
	var on_floor_before := runner.is_on_floor()
	runner.velocity.x = SPEED
	runner.velocity.y += GRAV * dt
	runner.move_and_slide()
	# step-up assist: walled on the ground with a low surface above the feet
	# (ramp foot floating slightly off the ground) -> lift onto it. Tall walls
	# and chest-high lines still stop him cold, by design.
	if (runner.is_on_floor() or on_floor_before) and absf(runner.get_real_velocity().x) < 40.0:
		for i in range(40):
			var up := Vector2(0, -(i + 1))
			var lifted := runner.global_transform.translated(up)
			if not runner.test_move(lifted, Vector2(4, 0)) and runner.test_move(lifted, Vector2(0, 44)):
				runner.global_position += up
				break
	if not runner.is_on_floor():
		was_air = true
		peak_fall = maxf(peak_fall, runner.velocity.y)
	elif was_air:
		was_air = false
		if peak_fall > KILL_FALL and not nodmg:
			_lose("fell from height")
			return
		peak_fall = 0.0
	for i in runner.get_slide_collision_count():
		var col := runner.get_slide_collision(i).get_collider()
		if col != null and col.has_meta("kills") and not nodmg:
			# pixel-tight: limbs brushing stone don't kill, only his chest core
			# truly inside the rock does (within ~8px of the stone)
			if _core_hits(col):
				_lose("hit an obstacle")
				return
	if runner.global_position.x >= gold_x - 90.0:
		_win()
		return
	if time_left <= 0.0:
		_lose("time ran out")
		return

func _process(dt: float) -> void:
	# sky drifts on the page; camera chases the runner
	for c in clouds:
		(c as Sprite2D).position.x -= 12.0 * dt
		if (c as Sprite2D).position.x < -200:
			(c as Sprite2D).position.x = W + 200
	if is_instance_valid(cam) and is_instance_valid(runner):
		cam.position.x = runner.global_position.x + 200.0
		cam.position.y = 360.0
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
	# slow-mo ground truth: only while input is truly held, never leaks
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or drawing or grabbing
	Engine.time_scale = 0.45 if held else 1.0
	# test hook: simulate a sealed stroke headlessly
	if "--autodraw" in cli_args and t >= 1.0 and strokes.is_empty():
		var test := Line2D.new()
		test.points = PackedVector2Array([Vector2(100, 300), Vector2(700, 300)])
		add_child(test)
		_seal_stroke(test)
		print("AUTODRAW: strokes=%d" % strokes.size())
	# timer HUD
	var mm := int(maxf(time_left, 0.0)) / 60
	var ss := int(maxf(time_left, 0.0)) % 60
	hud_timer.text = "%d:%02d" % [mm, ss]
	# platform drops in as the runner closes in
	if plat_drop_t < 0.0 and runner.global_position.x >= PLAT0 - 1100.0:
		plat_drop_t = 0.0
	if plat_drop_t >= 0.0 and not plat_placed:
		plat_drop_t += dt
		var u := clampf(plat_drop_t / 1.2, 0.0, 1.0)
		plat.position.y = -420.0 * (1.0 - u * u)
		if u >= 1.0:
			plat_placed = true
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
	# rocks are static; drop them once far behind the camera
	for r in rocks.duplicate():
		var n: Node2D = r["node"]
		if not is_instance_valid(n):
			rocks.erase(r)
			continue
		if n.position.x < runner.global_position.x - 900.0:
			n.queue_free()
			rocks.erase(r)
	# arrows fly, shields wear down
	for arrow in arrows.duplicate():
		var n: Node2D = arrow["node"]
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
		if n.position.distance_to(runner.global_position + Vector2(0, -65)) < 34.0 and not nodmg:
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
			var line: Line2D = s["line"]
			if not is_instance_valid(line):
				continue
			for i in range(line.get_point_count() - 1):
				var ga := line.to_global(line.get_point_position(i))
				var gb := line.to_global(line.get_point_position(i + 1))
				if _pt_seg_dist(n.position, ga, gb) < 12.0:
					_damage_stroke(s)
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
