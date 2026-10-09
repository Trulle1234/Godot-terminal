class_name Terminal
extends CodeEdit

var startup_text = "Godot Terminal [Version 1.0]
Copyright (c) Trulle123 2026 - MIT License"

var prompt

var last_valid_text = ""
var working_dir
var last_working_dir

var commands: TerminalCommands
var recognized_commands

var entered_commands = []
var last_previewd_command = ""
var command_preview_i = 0

var highlighter: TerminalHighlighter
var colors = {}
const DEF_COLORS = {
	"black": "#000000",
	"white": "#DCDCDCFF",
	"red": "#FF628C",
	"yellow": "#FFC600",
	"pink": "#FB94FF",
	"green": "#3AD900",
	"cyan": "#80FCFF",
	"blue": "#0088FF"
}

func _ready() -> void:
	commands = TerminalCommands.new(self)
	
	recognized_commands = commands.get_command_names()
	working_dir = get_home_dir()
	last_working_dir = working_dir
	
	if FileAccess.file_exists("user://entered_commands.save"):
		var history_file = FileAccess.open("user://entered_commands.save", FileAccess.READ)
		entered_commands = history_file.get_var()
			
		if history_file.get_error() != OK or not entered_commands is Array:
			entered_commands = []
		
		if entered_commands is Array and entered_commands.size() > 500:
			entered_commands = entered_commands.slice(-500)
	else:
		var history_file = FileAccess.open("user://entered_commands.save", FileAccess.WRITE)
		history_file.store_var(entered_commands)
	
	if FileAccess.file_exists("user://colors.json"):
		var colors_file = FileAccess.open("user://colors.json", FileAccess.READ)
		colors = JSON.parse_string(colors_file.get_as_text())
	else:
		var colors_file = FileAccess.open("user://colors.json", FileAccess.WRITE)
		colors_file.store_string(JSON.stringify(DEF_COLORS, "\t"))
		colors = DEF_COLORS
	
	highlighter = TerminalHighlighter.new(colors)
	syntax_highlighter = highlighter
	
	theme.set_color("caret_color", "CodeEdit", colors["white"])
	theme.set_color("font_color", "CodeEdit", colors["white"])
	var current_style = theme.get_stylebox("normal", "CodeEdit").duplicate()
	current_style.bg_color = Color(colors["black"])
	theme.set_stylebox("normal", "CodeEdit", current_style)
	
	command_preview_i = entered_commands.size()
	
	prompt = working_dir + "$ "
	
	text = startup_text + "\n\n" + prompt
	last_valid_text = text
	
	highlighter.set_span_color(get_line_count() - 1, 0, prompt.length(), "green")
	highlighter.add_command_color(recognized_commands, "yellow")
	
# handle enter presses
func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("enter"):
		accept_event()
		
		var lines = text.split("\n")
		var current_command = lines[-1].substr(prompt.length())
			
		if entered_commands.is_empty() or entered_commands[-1] != current_command:
			entered_commands.append(current_command)
		
		await commands.execute(current_command)
		
		command_preview_i = entered_commands.size()
		last_previewd_command = ""
		
		if current_command == "clear":
			text += prompt
		else:
			text += "\n" + prompt
		
		highlighter.set_span_color(get_line_count() - 1, 0, prompt.length(), "green")
		
		last_valid_text = text
		
		if get_tree():
			await get_tree().process_frame
		set_caret_to_end()
	
	elif event.is_action_pressed("up_arrow"):
		accept_event()
		
		var lines = text.split("\n")
		var current_command = lines[-1].substr(prompt.length())
		
		if entered_commands.size() > 0:
			if not last_previewd_command.is_empty():
				text = text.left(text.length() - current_command.length())
				
			command_preview_i = max(command_preview_i - 1, 0)
			
			last_previewd_command = entered_commands[command_preview_i]
			text += last_previewd_command
		
		set_caret_to_end()
		
	elif event.is_action_pressed("down_arrow"):
		accept_event()
		
		var lines = text.split("\n")
		var current_command = lines[-1].substr(prompt.length())
		
		if entered_commands.size() > 0:
			if not last_previewd_command.is_empty():
				text = text.left(text.length() - current_command.length())
				
			command_preview_i += 1
			
			if command_preview_i >= entered_commands.size():
				command_preview_i = entered_commands.size()
				last_previewd_command = ""
			else:
				last_previewd_command = entered_commands[command_preview_i]
				text += last_previewd_command
		
		set_caret_to_end()
	
	elif event.is_action_pressed("zoom_in"):
		theme.set_font_size("font_size", "CodeEdit", theme.get_font_size("font_size", "CodeEdit") + 1)
		
	elif event.is_action_pressed("zoom_out"):
		theme.set_font_size("font_size", "CodeEdit", theme.get_font_size("font_size", "CodeEdit") - 1)
	
	elif event.is_action_pressed("paste"):
		text += DisplayServer.clipboard_get()

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
func write_output(output, color="white"):
	var lines = output.split("\n", false)
	
	for line in lines:
		text += "\n" + line
		highlighter.set_line_color(get_line_count() - 1, color)

# sets the current working dir
func set_working_dir(path):
	last_working_dir = working_dir
	working_dir = path
	prompt = working_dir + "$ "
	
# clears the terminal and resets the colors
func clear_and_reset_colors():
	text = ""
	highlighter.line_colors.clear()
	highlighter.span_colors.clear()
	highlighter.clear_highlighting_cache()
