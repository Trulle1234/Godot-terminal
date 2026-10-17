class_name Terminal
extends CodeEdit

var busy = false

var terminal_info = "Godot Terminal [Version 1.2.3]
Copyright (c) Trulle123 2026 - MIT License"

var prompt

var updating_output = false
var last_valid_text = ""
var working_dir
var last_working_dir

var commands: TerminalCommands

var entered_commands = []
var last_previewd_command = ""
var command_preview_i = 0

var highlighter: TerminalHighlighter
var colors = {}

const USER_README = "GODOT TERMINAL
--------------

- To change colors edit the hex codes in colors.json
  - You can fine examples at https://github.com/Trulle1234/Godot-terminal/tree/main/themes

- If you want to change the font, add a TTF font to this folder and call it font.ttf


!!! Don't touch entered_commands.save unless you know what you are doing !!!
"

const DEF_COLORS_FILE = preload("res://themes/default.json")

func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(640, 128))
	get_v_scroll_bar().step = 1.0
	
	working_dir = get_home_dir()
	last_working_dir = working_dir
	
	if not FileAccess.file_exists("user://README.txt"):
		var readme_file = FileAccess.open("user://README.txt", FileAccess.WRITE)
		readme_file.store_string(USER_README)
		
	if not DirAccess.dir_exists_absolute("user://libs"):
		DirAccess.make_dir_absolute("user://libs")
	
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
		var json = JSON.new()
		var colors_err = json.parse(colors_file.get_as_text())
		
		if colors_err != OK:
			colors = DEF_COLORS_FILE.data
		else:
			colors = json.data
			
	else:
		var colors_file = FileAccess.open("user://colors.json", FileAccess.WRITE)
		colors_file.store_string(JSON.stringify(DEF_COLORS_FILE.data, "\t"))
		colors = DEF_COLORS_FILE.data
	
	if FileAccess.file_exists("user://font.ttf"):
		var font_data: PackedByteArray = FileAccess.get_file_as_bytes("user://font.ttf")
		var new_font = FontFile.new()
		new_font.data = font_data
		
		theme.set_font("font", "CodeEdit", new_font)
		
	highlighter = TerminalHighlighter.new(colors)
	syntax_highlighter = highlighter
	
	theme.set_color("caret_color", "CodeEdit", syntax_highlighter.colors["caret"])
	theme.set_color("font_color", "CodeEdit", syntax_highlighter.colors["white"])
	theme.set_color("font_selected_color", "CodeEdit", syntax_highlighter.colors["selected"])
	theme.set_color("selection_color", "CodeEdit", syntax_highlighter.colors["selection"])
	var current_style = theme.get_stylebox("normal", "CodeEdit").duplicate()
	current_style.bg_color = Color(syntax_highlighter.colors["bg"])
	theme.set_stylebox("normal", "CodeEdit", current_style)
	
	commands = TerminalCommands.new(self)
	var libs = DirAccess.get_files_at("user://libs")
	
	for lib in libs:
		commands.gdpt(["install", ProjectSettings.globalize_path("user://libs".path_join(lib))], ["-t"], null)
	
	command_preview_i = entered_commands.size()
	prompt = get_prompt()
	text = get_startup() + "\n\n" + prompt
	last_valid_text = text
	
	highlighter.set_span_color(get_line_count() - 1, 0, prompt.length(), "green")
	
	grab_focus()
	set_caret_to_end()

# handle enter presses
func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var last_line = get_line_count() - 1
		var locked_column = prompt.length()
		
		if event.keycode == KEY_BACKSPACE:
			if get_caret_line() < last_line:
				accept_event()
				return
			if get_caret_column() <= locked_column:
				accept_event()
				return
		
		elif event.keycode == KEY_DELETE:
			if get_caret_line() < last_line:
				accept_event()
				return
			
			if get_caret_column() < locked_column:
				accept_event()
				return
	
	if event.is_action_pressed("enter") and not busy:
		accept_event()
		busy = true
		
		var lines = text.split("\n")
		var current_command = lines[-1].substr(prompt.length())
		
		if entered_commands.is_empty() or entered_commands[-1] != current_command:
			entered_commands.append(current_command)
		
		updating_output = true
		await commands.execute(current_command)
		
		command_preview_i = entered_commands.size()
		last_previewd_command = ""
		
		set_caret_to_end()
		
		if text.is_empty():
			insert_text_at_caret(prompt)
		else:
			insert_text_at_caret("\n" + prompt)
		
		set_caret_to_end()
		
		highlighter.set_span_color(get_line_count() - 1, 0, prompt.length(), "green")
		
		last_valid_text = text
		updating_output = false
		
		await get_tree().process_frame
		set_caret_to_end()
		busy = false
	
	elif event.is_action_pressed("tab"):
		accept_event()
		
		var parts = text.split("\n")[-1].substr(prompt.length()).split(" ")
		var input_path = parts[-1]
		var path = commands.solve_path(input_path)
		var path_part = path.get_file()
		var path_dir = path.get_base_dir()
		
		if input_path == "" or input_path.ends_with("/"):
			path_dir = path
			path_part = ""
		
		var dirs = DirAccess.get_directories_at(path_dir)
		var files = DirAccess.get_files_at(path_dir)
		var both = dirs + files
		
		var matches = []
		
		for thing in both:
			if thing.to_lower().begins_with(path_part.to_lower()):
				matches.append(thing)
		
		if matches:
			matches.sort_custom(func(a, b): return a.length() < b.length()) 
			
			var completion = matches[0]
			text = text.left(text.length() - path_part.length()) + completion
			
			if completion in dirs:
				text += "/"
			else:
				text += " "
		
		last_valid_text = text
		set_caret_to_end()
		
	elif event.is_action_pressed("up_arrow"):
		accept_event()
		if entered_commands.size() > 0:
			var current_command = get_line(get_line_count() - 1).substr(prompt.length())
			
			text = text.left(text.length() - current_command.length())
			
			command_preview_i = max(command_preview_i - 1, 0)
			last_previewd_command = entered_commands[command_preview_i]
			
			text += last_previewd_command
			set_caret_to_end()
		
	elif event.is_action_pressed("down_arrow"):
		accept_event()
		
		var current_command = get_line(get_line_count() - 1).substr(prompt.length())
			
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
		theme.set_constant("caret_width", "CodeEdit", int((theme.get_font_size("font_size", "CodeEdit")) * 0.625))
		
	elif event.is_action_pressed("zoom_out"):
		var font_size = max(1, theme.get_font_size("font_size", "CodeEdit") - 1)
		theme.set_font_size("font_size", "CodeEdit", font_size)
		theme.set_constant("caret_width", "CodeEdit", int(font_size * 0.625))
	
	elif event.is_action_pressed("copy"):
		accept_event()
		if has_selection():
			DisplayServer.clipboard_set(get_selected_text())
	
	elif event.is_action_pressed("paste"):
		accept_event()
		var current_command = get_line(get_line_count() - 1).substr(prompt.length())
		var echo_e_regex = RegEx.create_from_string(r'(^\s*|;\s*|\|\s*)echo\s+-e(?=\s|$|;|\|)')
		
		if echo_e_regex.search(current_command):
			insert_text_at_caret(DisplayServer.clipboard_get().replace("\n", "\\n"))
		else:
			insert_text_at_caret(DisplayServer.clipboard_get().replace("\n", "; "))
	
	elif event.is_action_pressed("clear") and not busy:
		accept_event()
		commands.execute("clear")
		
		set_caret_to_end()
		insert_text_at_caret(prompt)
		highlighter.set_span_color(get_line_count() - 1, 0, prompt.length(), "green")

# revert the text to last "saved state"
func revert_text():
	var saved_col = get_caret_column()
	
	updating_output = true
	text = last_valid_text
	
	set_caret_line(get_line_count() - 1)
	set_caret_column(min(saved_col, get_line(get_line_count() - 1).length()))
	
	updating_output = false

# when text chaged stop non allowed deleation
func _on_text_changed() -> void:
	if updating_output:
		return
		
	if busy:
		updating_output = true
		revert_text()
		updating_output = false
		return
	
	var lines = text.split("\n")
	var current_line_i = get_caret_line()
		
	if current_line_i < lines.size() - 1:
		revert_text()
		return
	
	var last_line = lines[lines.size() - 1]
	if not last_line.begins_with(prompt):
		revert_text()
		return
	
	var protected_text = last_valid_text.substr(0, last_valid_text.rfind("\n") + 1)
	if not text.begins_with(protected_text):
		revert_text()
		return
	
	last_valid_text = text
	var scrollbar = get_v_scroll_bar()
	scrollbar.value = scrollbar.max_value

func _on_caret_changed() -> void:
	if has_selection():
		theme.set_color("caret_color", "CodeEdit", Color(0.0, 0.0, 0.0, 0.0))
	else:
		theme.set_color("caret_color", "CodeEdit", syntax_highlighter.colors["caret"])
	
	if get_caret_line() == get_line_count() - 1:
		set_line_as_last_visible.call_deferred(get_caret_line())

# helper to put the caret at text end
func set_caret_to_end():
	var lines = text.split("\n")
	set_caret_line(lines.size() - 1)
	set_caret_column(lines[-1].length())

func get_prompt():
	var user
	if OS.has_environment("USERNAME"):
		user = OS.get_environment("USERNAME")
	elif OS.has_environment("USER"):
		user = OS.get_environment("USER")
	
	var host = OS.get_environment("COMPUTERNAME")
	if host.is_empty():
		host = OS.get_environment("HOSTNAME")
	if host.is_empty():
		var output = []
		if OS.execute("hostname", [], output) == 0 and not output.is_empty():
			host = output[0].strip_edges()
	if host.is_empty():
		host = "localhost"
	
	var path = working_dir.replace(get_home_dir(), "~")
	if path.length() >= 3 and path[1] == ":" and path[2] == "/":
		path = "/" + path[0] + path.substr(2)
	
	return user + "@" + host + ":" + path + "$ "

func get_startup() -> String:
	var user
	if OS.has_environment("USERNAME"):
		user = OS.get_environment("USERNAME")
	elif OS.has_environment("USER"):
		user = OS.get_environment("USER")
	
	var host = OS.get_environment("COMPUTERNAME")
	if host.is_empty():
		host = OS.get_environment("HOSTNAME")
	if host.is_empty():
		var output = []
		if OS.execute("hostname", [], output) == 0 and not output.is_empty():
			host = output[0].strip_edges()
	if host.is_empty():
		host = "localhost"
	
	var lines = [
		terminal_info,
		"",
		user + "@" + host,
		"-".repeat((user + "@" + host).length()),
		"OS: " + OS.get_name() + " " + OS.get_version_alias() + " " + Engine.get_architecture_name(),
		"Host: " + host,
		"Libraries: " + str(DirAccess.get_files_at("user://libs").size()),
		"CPU: " + OS.get_processor_name(),
	]

	return "\n".join(lines)

# get users home dr
func get_home_dir():
	if OS.has_feature("windows"):
		return OS.get_environment("USERPROFILE").replace("\\", "/")
	else:
		return OS.get_environment("HOME")

# write output to self
func write_output(output, color="white"):
	var was_updating = updating_output
	updating_output = true

	var start_line = get_line_count() - 1
	
	set_caret_line(start_line)
	set_caret_column(get_line(start_line).length())
	
	insert_text_at_caret("\n" + str(output))
	
	for i in range(start_line + 1, get_line_count()):
		highlighter.set_line_color(i, color)
	
	last_valid_text = text
	updating_output = was_updating
	
	get_h_scroll_bar().value = 0

# sets the current working dir
func set_working_dir(path):
	last_working_dir = working_dir
	working_dir = path
	prompt = get_prompt()
	
# clears the terminal and resets the colors
func clear_and_reset_colors():
	text = ""
	highlighter.line_colors.clear()
	highlighter.span_colors.clear()
	highlighter.clear_highlighting_cache()
	
	last_valid_text = text
