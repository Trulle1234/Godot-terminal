class_name Terminal
extends CodeEdit

var startup_text = "Godot Terminal [Version 0.0]
Copyright (c) Trulle123 2026 - MIT License"

var prompt

var last_valid_text = ""
var entered_commands = []
var working_dir

var commands: TerminalCommands
var recognized_commands

var highlighter: TerminalHighlighter

func _ready() -> void:
	commands = TerminalCommands.new(self)
	highlighter = TerminalHighlighter.new()
	syntax_highlighter = highlighter
	
	recognized_commands = commands.get_command_names()
	working_dir = get_home_dir()
	
	prompt = working_dir + "$ "
	
	text = startup_text + "\n\n" + prompt
	last_valid_text = text
	
	# highlighting
	highlighter.set_span_color(get_line_count() - 1, 0, prompt.length(), Color("#3AD900"))
	highlighter.add_keywords(recognized_commands, Color("#FFC600"))

# handle enter presses
func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("enter"):
		accept_event()
		
		var lines = text.split("\n")
		var current_command = lines[-1].substr(prompt.length())
		
		commands.execute(current_command)
		entered_commands.append(current_command)
		
		if current_command == "clear":
			text += prompt
		else:
			text += "\n" + prompt
		
		highlighter.set_span_color(get_line_count() - 1, 0, prompt.length(), Color("#3AD900"))
		
		last_valid_text = text
		
		await get_tree().process_frame
		set_caret_to_end()
	
	if event.is_action_pressed("up_arrow"):
		if entered_commands.size() > 0:
			text += entered_commands[entered_commands.size() - 1]

# revert the text to last "saved state"
func revert_text():
	text_changed.disconnect(_on_text_changed)
	
	var saved_col = get_caret_column()
	
	text = last_valid_text
	await get_tree().process_frame
	
	set_caret_line(get_line_count() - 1)
	set_caret_column(saved_col)
	
	text_changed.connect(_on_text_changed)

# when text chaged stop non allowed deleation
func _on_text_changed() -> void:
	var lines = text.split("\n")
	var current_line_i = get_caret_line()
	
	if current_line_i < lines.size() - 1:
		revert_text()
		return
	
	var last_line = lines[lines.size() - 1]
	if not last_line.begins_with(prompt):
		revert_text()
		return

#when the caret changed make sure its in an allowed spot
func _on_caret_changed() -> void:
	var total_lines = get_line_count()
	var current_line = get_caret_line()
	var current_col = get_caret_column()
	
	if current_line < total_lines - 1:
		set_caret_to_end()
		return
	
	if current_line == total_lines - 1 and current_col < prompt.length():
		set_caret_column(prompt.length())

# helper to put the caret at text end
func set_caret_to_end() -> void:
	var lines = text.split("\n")
	set_caret_line(lines.size() - 1)
	set_caret_column(lines[-1].length())

# get users home dr
func get_home_dir():
	if OS.has_feature("windows"):
		return OS.get_environment("USERPROFILE").replace("\\", "/")
	else:
		return OS.get_environment("HOME")

# write output to self
func write_output(output, color=get_theme_color("font_color")):
	var lines = output.split("\n", false)
	
	for line in lines:
		text += "\n" + line
		highlighter.set_line_color(get_line_count() - 1, color)

# sets the current working dir
func set_working_dir(path):
	working_dir = path
	prompt = working_dir + "$ "
	
# clears the terminal and resets the colors
func clear_and_reset_colors():
	text = ""
	highlighter.line_colors.clear()
	highlighter.span_colors.clear()
	highlighter.clear_highlighting_cache()
