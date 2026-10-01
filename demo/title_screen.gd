extends Control

const PAPER := Color("f6f1e3")
const RULE := Color("9db3d4")
const INK := Color("2e2c28")
const GOLD := Color("d5a52c")
const RUST := Color("b85f49")
const STORY_TEXT := "Andre the stickman needs his bag of gold to feed his family but many obstacles prevent him from getting it, help Andre reach the bag of gold and he will be forever grateful"
const INTRO_MUSIC_PATH := "res://assets/music/title_intro.mp3"
const LEVEL_PICKER_META := "death_escape_open_level_picker"
const RUN_FRAMES := [
	"res://assets/stick-runner/rig/run_1_R_contact.png",
	"res://assets/stick-runner/rig/run_2_R_stance.png",
	"res://assets/stick-runner/rig/run_3_L_swingthru.png",
	"res://assets/stick-runner/rig/run_4_L_plant.png",
]

var pages: Array[Control] = []
var current_page := 0
var page_width := 1280.0
var page_height := 720.0
var cursive_font: Font
var transitioning := false
var typing_story := false
var typewriter_clock := 0.0
var story_label: Label
var start_button: Button
var tap_hint_label: Label
var title_bag: Sprite2D
var andre_sprite: AnimatedSprite2D
var title_time := 0.0
var intro_music_player: AudioStreamPlayer

func _ready() -> void:
	Engine.time_scale = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS
	page_width = get_viewport_rect().size.x
	page_height = get_viewport_rect().size.y
	cursive_font = load("res://assets/fonts/Caveat-VF.ttf") as Font
	_start_intro_music()
	pages.append(_new_page())
	pages.append(_new_page())
	pages.append(_new_page())
	_build_title_page(pages[0])
	_build_story_page(pages[1])
	_build_level_page(pages[2])
	var open_level_picker := get_tree().root.has_meta(LEVEL_PICKER_META)
	if open_level_picker:
		get_tree().root.remove_meta(LEVEL_PICKER_META)
	current_page = 2 if open_level_picker else 0
	pages[0].visible = not open_level_picker
	pages[1].visible = false
	pages[2].visible = open_level_picker
	get_viewport().size_changed.connect(_on_viewport_resized)

func _process(delta: float) -> void:
	title_time += delta
	if is_instance_valid(title_bag):
		title_bag.position.y = page_height * 0.59 + sin(title_time * 1.8) * 8.0
	if typing_story and current_page == 1 and is_instance_valid(story_label):
		typewriter_clock += delta * 42.0
		var visible_count := mini(STORY_TEXT.length(), int(typewriter_clock))
		story_label.visible_characters = visible_count
		if visible_count >= STORY_TEXT.length():
			typing_story = false
			_reveal_start_button()

func _unhandled_input(event: InputEvent) -> void:
	if not typing_story:
		return
	var accept_tap := false
	if event is InputEventMouseButton:
		accept_tap = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		accept_tap = event.pressed
	elif event is InputEventKey:
		accept_tap = event.pressed and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER)
	if accept_tap:
		_finish_story_text()
		get_viewport().set_input_as_handled()

func _start_intro_music() -> void:
	var stream := load(INTRO_MUSIC_PATH) as AudioStreamMP3
	if stream == null:
		push_error("Missing intro music: " + INTRO_MUSIC_PATH)
		return
	stream.loop = true
	intro_music_player = AudioStreamPlayer.new()
	intro_music_player.stream = stream
	intro_music_player.volume_db = -16.0
	add_child(intro_music_player)
	intro_music_player.play()

func _new_page() -> Control:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 0.0
	page.offset_top = 0.0
	page.offset_right = 0.0
	page.offset_bottom = 0.0
	page.mouse_filter = Control.MOUSE_FILTER_PASS
	page.visible = false
	add_child(page)
	_add_paper_background(page)
	return page

func _add_paper_background(page: Control) -> void:
	var background := ColorRect.new()
	background.color = PAPER
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(background)
	for index in range(1, int(page_height / 32.0) + 1):
		var rule := ColorRect.new()
		rule.color = Color(RULE.r, RULE.g, RULE.b, 0.55)
		rule.anchor_left = 0.0
		rule.anchor_right = 1.0
		rule.offset_left = 0.0
		rule.offset_right = 0.0
		rule.offset_top = float(index) * 32.0
		rule.offset_bottom = float(index) * 32.0 + 1.0
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(rule)
	var margin := ColorRect.new()
	margin.color = Color(0.76, 0.36, 0.32, 0.55)
	margin.anchor_bottom = 1.0
	margin.offset_left = 66.0
	margin.offset_right = 68.0
	margin.offset_bottom = 0.0
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(margin)

func _place(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0

func _make_label(text: String, font_size: int, color: Color, alignment: int = HORIZONTAL_ALIGNMENT_CENTER, use_script_font: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if use_script_font and cursive_font != null:
		label.add_theme_font_override("font", cursive_font)
	return label

func _make_button(text: String, font_size: int, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(250.0, 68.0)
	button.add_theme_font_size_override("font_size", font_size)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_color_override("font_color", PAPER if primary else INK)
	button.add_theme_color_override("font_hover_color", PAPER if primary else INK)
	button.add_theme_color_override("font_pressed_color", PAPER if primary else INK)
	var normal := _button_style(INK if primary else Color("fffdf7"), GOLD if primary else INK)
	var hover := _button_style(Color("433f36") if primary else Color("f4e8c8"), GOLD)
	var pressed := _button_style(Color("25231f") if primary else Color("ead9ae"), GOLD)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	return button

func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0.10, 0.09, 0.08, 0.18)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 3.0)
	return style

func _build_title_page(page: Control) -> void:
	var eyebrow := _make_label("A HAND-DRAWN ADVENTURE", 21, RUST)
	_place(eyebrow, 0.18, 0.10, 0.82, 0.17)
	page.add_child(eyebrow)
	var title := _make_label("Death Escape", 126, INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	_place(title, 0.08, 0.19, 0.92, 0.42)
	page.add_child(title)
	var title_rule := Line2D.new()
	title_rule.points = PackedVector2Array([
		Vector2(page_width * 0.34, page_height * 0.425),
		Vector2(page_width * 0.44, page_height * 0.438),
		Vector2(page_width * 0.56, page_height * 0.432),
		Vector2(page_width * 0.66, page_height * 0.42),
	])
	title_rule.width = 3.0
	title_rule.default_color = GOLD
	title_rule.antialiased = true
	page.add_child(title_rule)
	var subtitle := _make_label("A little ink. A long run. One very important bag.", 25, INK)
	_place(subtitle, 0.17, 0.44, 0.83, 0.52)
	page.add_child(subtitle)
	var sun := Sprite2D.new()
	sun.texture = _load_texture("res://assets/obstacles/cut/sun.png")
	sun.position = Vector2(page_width * 0.84, page_height * 0.22)
	sun.scale = Vector2(0.30, 0.30)
	sun.modulate = Color(1.0, 0.91, 0.68, 0.92)
	page.add_child(sun)
	title_bag = Sprite2D.new()
	title_bag.texture = _load_texture("res://assets/pickups/cut/gold_open.png")
	title_bag.position = Vector2(page_width * 0.74, page_height * 0.59)
	title_bag.scale = Vector2(0.34, 0.34)
	title_bag.rotation = deg_to_rad(5.0)
	page.add_child(title_bag)
	_add_sparkle(page, Vector2(page_width * 0.66, page_height * 0.59), 15.0)
	_add_sparkle(page, Vector2(page_width * 0.84, page_height * 0.50), 10.0)
	var left_doodle := _make_doodle_runner(page, Vector2(page_width * 0.26, page_height * 0.62), 0.46)
	left_doodle.modulate = Color(1.0, 1.0, 1.0, 0.76)
	var next_button := _make_button("TURN THE PAGE  ›", 29, true)
	_place(next_button, 0.34, 0.79, 0.66, 0.91)
	next_button.pressed.connect(_open_story_page)
	page.add_child(next_button)
	_add_page_number(page, "01   /   03")

func _build_story_page(page: Control) -> void:
	var heading := _make_label("ANDRE'S STORY", 26, RUST, HORIZONTAL_ALIGNMENT_LEFT)
	_place(heading, 0.09, 0.075, 0.42, 0.15)
	page.add_child(heading)
	andre_sprite = _make_animated_runner(page, Vector2(page_width * 0.19, page_height * 0.61), 0.77)
	var andre_name := _make_label("Andre", 42, INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	_place(andre_name, 0.10, 0.79, 0.30, 0.88)
	page.add_child(andre_name)
	var bag := Sprite2D.new()
	bag.texture = _load_texture("res://assets/pickups/cut/gold_open.png")
	bag.position = Vector2(page_width * 0.29, page_height * 0.79)
	bag.scale = Vector2(0.13, 0.13)
	bag.rotation = deg_to_rad(-5.0)
	page.add_child(bag)
	_add_bubble_tail(page)
	var bubble := PanelContainer.new()
	_place(bubble, 0.36, 0.19, 0.93, 0.79)
	bubble.add_theme_stylebox_override("panel", _speech_bubble_style())
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bubble)
	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 32)
	margins.add_theme_constant_override("margin_right", 32)
	margins.add_theme_constant_override("margin_top", 26)
	margins.add_theme_constant_override("margin_bottom", 26)
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(margins)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margins.add_child(column)
	var bubble_label := _make_label("A NOTE FROM ANDRE", 24, RUST, HORIZONTAL_ALIGNMENT_LEFT, true)
	column.add_child(bubble_label)
	story_label = _make_label(STORY_TEXT, 25, INK, HORIZONTAL_ALIGNMENT_LEFT)
	story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	story_label.visible_characters = 0
	column.add_child(story_label)
	start_button = _make_button("START  ›", 31, true)
	start_button.custom_minimum_size = Vector2(260.0, 70.0)
	_place(start_button, 0.68, 0.82, 0.92, 0.94)
	start_button.visible = false
	start_button.modulate.a = 0.0
	start_button.pressed.connect(_open_levels_page)
	page.add_child(start_button)
	tap_hint_label = _make_label("Tap once to finish the note", 17, Color(INK.r, INK.g, INK.b, 0.65))
	_place(tap_hint_label, 0.40, 0.82, 0.65, 0.94)
	page.add_child(tap_hint_label)
	_add_page_number(page, "02   /   03")

func _build_level_page(page: Control) -> void:
	var eyebrow := _make_label("YOUR NEXT RUN", 21, RUST)
	_place(eyebrow, 0.22, 0.07, 0.78, 0.13)
	page.add_child(eyebrow)
	var title := _make_label("Choose a level", 82, INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	_place(title, 0.12, 0.11, 0.88, 0.27)
	page.add_child(title)
	var subtitle := _make_label("Pick a chapter. Andre is counting on you.", 23, INK)
	_place(subtitle, 0.19, 0.25, 0.81, 0.32)
	page.add_child(subtitle)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_place(row, 0.08, 0.36, 0.92, 0.80)
	page.add_child(row)
	row.add_child(_make_level_card("LEVEL 1", "The Getaway", "Learn the lines. Reach the bag.", GOLD, "res://demo/level_1.tscn"))
	row.add_child(_make_level_card("LEVEL 2", "The Hound", "A closer chase. More hazards.", RUST, "res://demo/level_2.tscn"))
	var back_button := _make_button("‹  BACK", 25, false)
	back_button.custom_minimum_size = Vector2(200.0, 64.0)
	_place(back_button, 0.07, 0.84, 0.25, 0.94)
	back_button.pressed.connect(_back_to_story_page)
	page.add_child(back_button)
	_add_page_number(page, "03   /   03")

func _make_level_card(number: String, title: String, description: String, accent: Color, scene_path: String) -> Button:
	var card := Button.new()
	card.text = ""
	card.custom_minimum_size = Vector2(360.0, 270.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_ALL
	var normal := _button_style(Color("fffdf7"), accent)
	var hover := _button_style(Color("f5ebd2"), accent)
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", _button_style(Color("eee0bd"), accent))
	card.add_theme_stylebox_override("focus", hover)
	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 26)
	margins.add_theme_constant_override("margin_right", 26)
	margins.add_theme_constant_override("margin_top", 24)
	margins.add_theme_constant_override("margin_bottom", 24)
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margins)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margins.add_child(column)
	var index_label := _make_label(number, 22, accent, HORIZONTAL_ALIGNMENT_LEFT)
	column.add_child(index_label)
	var title_label := _make_label(title, 56, INK, HORIZONTAL_ALIGNMENT_LEFT, true)
	column.add_child(title_label)
	var description_label := _make_label(description, 22, INK, HORIZONTAL_ALIGNMENT_LEFT)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(description_label)
	var play_label := _make_label("PLAY  ›", 21, accent, HORIZONTAL_ALIGNMENT_LEFT)
	column.add_child(play_label)
	card.pressed.connect(_launch_level.bind(scene_path))
	return card

func _make_doodle_runner(parent: Control, center: Vector2, scale: float) -> Node2D:
	var group := Node2D.new()
	group.position = center
	group.scale = Vector2(scale, scale)
	parent.add_child(group)
	var head := Line2D.new()
	var circle := PackedVector2Array()
	for i in range(33):
		var angle := TAU * float(i) / 32.0
		circle.append(Vector2(cos(angle), sin(angle)) * 28.0 + Vector2(0.0, -90.0))
	head.points = circle
	head.width = 5.0
	head.default_color = INK
	head.antialiased = true
	group.add_child(head)
	var torso := Line2D.new()
	torso.points = PackedVector2Array([Vector2(0, -62), Vector2(-4, 8)])
	torso.width = 6.0
	torso.default_color = INK
	torso.begin_cap_mode = Line2D.LINE_CAP_ROUND
	torso.end_cap_mode = Line2D.LINE_CAP_ROUND
	group.add_child(torso)
	var arms := Line2D.new()
	arms.points = PackedVector2Array([Vector2(-2, -42), Vector2(-36, -20), Vector2(-55, -44)])
	arms.width = 5.0
	arms.default_color = INK
	arms.begin_cap_mode = Line2D.LINE_CAP_ROUND
	arms.end_cap_mode = Line2D.LINE_CAP_ROUND
	group.add_child(arms)
	var waving_arm := Line2D.new()
	waving_arm.points = PackedVector2Array([Vector2(-2, -42), Vector2(29, -67), Vector2(45, -105)])
	waving_arm.width = 5.0
	waving_arm.default_color = INK
	waving_arm.begin_cap_mode = Line2D.LINE_CAP_ROUND
	waving_arm.end_cap_mode = Line2D.LINE_CAP_ROUND
	group.add_child(waving_arm)
	var legs := Line2D.new()
	legs.points = PackedVector2Array([Vector2(-4, 8), Vector2(-32, 48), Vector2(-58, 78)])
	legs.width = 6.0
	legs.default_color = INK
	legs.begin_cap_mode = Line2D.LINE_CAP_ROUND
	legs.end_cap_mode = Line2D.LINE_CAP_ROUND
	group.add_child(legs)
	var other_leg := Line2D.new()
	other_leg.points = PackedVector2Array([Vector2(-4, 8), Vector2(24, 38), Vector2(49, 72)])
	other_leg.width = 6.0
	other_leg.default_color = INK
	other_leg.begin_cap_mode = Line2D.LINE_CAP_ROUND
	other_leg.end_cap_mode = Line2D.LINE_CAP_ROUND
	group.add_child(other_leg)
	var scarf := Line2D.new()
	scarf.points = PackedVector2Array([Vector2(-12, -65), Vector2(7, -58), Vector2(26, -65), Vector2(38, -57)])
	scarf.width = 9.0
	scarf.default_color = GOLD
	scarf.begin_cap_mode = Line2D.LINE_CAP_ROUND
	scarf.end_cap_mode = Line2D.LINE_CAP_ROUND
	group.add_child(scarf)
	for eye_x in [-9.0, 9.0]:
		var eye := Polygon2D.new()
		var points := PackedVector2Array()
		for i in range(9):
			var angle := TAU * float(i) / 8.0
			points.append(Vector2(eye_x, -94.0) + Vector2(cos(angle), sin(angle)) * 3.2)
		eye.polygon = points
		eye.color = INK
		group.add_child(eye)
	return group

func _make_animated_runner(parent: Control, position: Vector2, scale: float) -> AnimatedSprite2D:
	var frames := SpriteFrames.new()
	frames.add_animation("run")
	frames.set_animation_speed("run", 6.0)
	frames.set_animation_loop("run", true)
	for frame_path in RUN_FRAMES:
		var texture := _load_texture(frame_path)
		if texture != null:
			frames.add_frame("run", texture)
	var character := AnimatedSprite2D.new()
	character.sprite_frames = frames
	character.animation = "run"
	character.position = position
	character.scale = Vector2(scale, scale)
	character.play()
	parent.add_child(character)
	return character

func _add_bubble_tail(page: Control) -> void:
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(0, 0), Vector2(58, 26), Vector2(0, 58)])
	tail.position = Vector2(page_width * 0.325, page_height * 0.53)
	tail.color = Color("fffdf7")
	page.add_child(tail)
	var outline := Line2D.new()
	outline.points = PackedVector2Array([Vector2(0, 0), Vector2(58, 26), Vector2(0, 58)])
	outline.position = tail.position
	outline.width = 3.0
	outline.default_color = INK
	outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	outline.end_cap_mode = Line2D.LINE_CAP_ROUND
	page.add_child(outline)

func _speech_bubble_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fffdf7")
	style.border_color = INK
	style.set_border_width_all(3)
	style.set_corner_radius_all(22)
	style.shadow_color = Color(0.10, 0.09, 0.08, 0.18)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 5.0)
	return style

func _add_sparkle(parent: Control, center: Vector2, radius: float) -> void:
	var star := Polygon2D.new()
	var points := PackedVector2Array()
	for i in range(8):
		var angle := TAU * float(i) / 8.0 - PI * 0.5
		var r := radius if i % 2 == 0 else radius * 0.22
		points.append(Vector2(cos(angle), sin(angle)) * r)
	star.polygon = points
	star.position = center
	star.color = GOLD
	parent.add_child(star)

func _add_page_number(page: Control, value: String) -> void:
	var label := _make_label(value, 18, Color(INK.r, INK.g, INK.b, 0.62), HORIZONTAL_ALIGNMENT_RIGHT)
	_place(label, 0.80, 0.94, 0.96, 0.985)
	page.add_child(label)

func _load_texture(path: String) -> Texture2D:
	var texture := load(path) as Texture2D
	if texture == null:
		push_error("Missing title-screen texture: " + path)
	return texture

func _open_story_page() -> void:
	_transition_to_page(1)

func _open_levels_page() -> void:
	_transition_to_page(2)

func _back_to_story_page() -> void:
	_transition_to_page(1)

func _begin_story_typewriter() -> void:
	if not is_instance_valid(story_label):
		return
	typewriter_clock = 0.0
	typing_story = true
	story_label.visible_characters = 0
	if is_instance_valid(tap_hint_label):
		tap_hint_label.visible = true
	start_button.visible = false
	start_button.modulate.a = 0.0

func _finish_story_text() -> void:
	if not typing_story:
		return
	typing_story = false
	if is_instance_valid(story_label):
		story_label.visible_characters = STORY_TEXT.length()
	_reveal_start_button()

func _reveal_start_button() -> void:
	if is_instance_valid(tap_hint_label):
		tap_hint_label.visible = false
	if not is_instance_valid(start_button):
		return
	start_button.visible = true
	start_button.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(start_button, "modulate:a", 1.0, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _transition_to_page(next_index: int) -> void:
	if transitioning or next_index < 0 or next_index >= pages.size() or next_index == current_page:
		return
	transitioning = true
	typing_story = false
	var outgoing := pages[current_page]
	var incoming := pages[next_index]
	incoming.position = Vector2(page_width * 0.16, 0.0)
	incoming.modulate.a = 0.0
	incoming.visible = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(outgoing, "position:x", -page_width * 0.13, 0.44).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(outgoing, "modulate:a", 0.0, 0.34)
	tween.tween_property(incoming, "position:x", 0.0, 0.52).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(incoming, "modulate:a", 1.0, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished
	outgoing.visible = false
	outgoing.position = Vector2.ZERO
	outgoing.modulate = Color.WHITE
	incoming.position = Vector2.ZERO
	incoming.modulate = Color.WHITE
	current_page = next_index
	transitioning = false
	if current_page == 1:
		_begin_story_typewriter()

func _launch_level(scene_path: String) -> void:
	if transitioning:
		return
	transitioning = true
	typing_story = false
	Engine.time_scale = 1.0
	var curtain := ColorRect.new()
	curtain.color = Color(INK.r, INK.g, INK.b, 0.0)
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(curtain)
	var tween := create_tween()
	tween.tween_property(curtain, "color:a", 1.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tween.finished
	if is_instance_valid(intro_music_player):
		intro_music_player.stop()
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		push_error("Could not launch level: " + scene_path)

func _exit_tree() -> void:
	if is_instance_valid(intro_music_player):
		intro_music_player.stop()
		intro_music_player.stream = null

func _on_viewport_resized() -> void:
	page_width = get_viewport_rect().size.x
	page_height = get_viewport_rect().size.y
