class_name TerminalCommands
extends RefCounted

const COMMAND_BLACKLIST = [
	"_init",
	"execute",
	"parse_line",
	"handle_output",
	"solve_path",
	"handle_redirect",
	"output_to_text",
	"remove_recursive",
	"get_wc_text",
	"get_grep_text",
	"register_commands",
	"get_tree_text",
	"install_plugin",
	"split_unquoted"
]

const COMMAND_INFO = {
	"pwd": "Print the current working directory",
	"cd": "Change the current working directory",
	"mkdir": "Create directory",
	"rmdir": "Remove empty directory",
	"ls": "List directory contents",
	"tree": "Print directory tree",
	"echo": "Output text",
	"touch": "Create empty file",
	"cat": "Print and concatenate file contents",
	"head": "Print first line of file",
	"tail": "Print last line of file",
	"wc": "Count lines, words and bytes",
	"sort": "Sort lines of text file",
	"grep": "Search for a pattern in file",
	"cp": "Copy file",
	"mv": "Move or rename file",
	"rm": "Remove file",
	"ping": "Ping server",
	"curl": "Send HTTP request to server",
	"gdpt": "Get libraries, locally or from server.",
	"uname": "Print system information",
	"whoami": "Print the current user",
	"clear": "Clear the terminal",
	"help": "Print command information",
	"man": "Print manual page for command",
	"history": "Print command history",
	"reset": "Resets the terminal",
	"colors": "Display all colors"
}

var terminal: Terminal

var command_registry = {}
var loaded_plugins = []
var plugin_commands = {}

var command_info = {}

var man_dict

func _init(terminal_ref) -> void:
	terminal = terminal_ref
	register_commands(self, "terminal")

func execute(command_line) -> void:
	var history_file = FileAccess.open("user://entered_commands.save", FileAccess.WRITE)
	history_file.store_var(terminal.entered_commands)
	history_file.close()
	
	var lines = split_unquoted(command_line, ";")
	
	for line in lines:
		var pipeline = split_unquoted(line, "|")
		var pipe_input = null
		
		for i in range(pipeline.size()):
			var parts = parse_line(pipeline[i].strip_edges())
			if parts.is_empty():
				continue
			
			var command = parts[0]
			var args = parts.slice(1)
			
			if command not in command_registry:
				var solved_path = solve_path(command)
				var pid = -1
				
				if FileAccess.file_exists(solved_path):
					pid = OS.create_process(solved_path, args)
				
				if pid == -1:
					terminal.write_output(command + ": not found", "red")
					break
				
			else:
				var is_last = i == pipeline.size() - 1
				if is_last:
					await handle_output(args, command_registry[command], pipe_input)
				else:
					pipe_input =  await handle_output(args, command_registry[command], pipe_input, true)

func register_commands(instance, file_name, overwrite=false):
	if not is_instance_valid(instance) or not instance.get_script():
		return false
	
	var script = instance.get_script()
	var blacklist = []
	
	if instance.has_method("get_command_blacklist"):
		blacklist = instance.get_command_blacklist()
	
	var new_commands = {}
	
	for method in script.get_script_method_list():
		var name = method.name
		
		if name in blacklist or name.begins_with("_") or name == "get_command_blacklist" or name == "get_command_info":
			continue
		if method.args.size() != 3:
			continue
		
		var registered_name = name
		
		if name in command_registry and not (overwrite and name in plugin_commands.get(file_name, [])):
			registered_name = file_name + "." + name
		if registered_name in new_commands:
			return false
		if registered_name in command_registry and not (overwrite and registered_name in plugin_commands.get(file_name, [])):
			return false
			
		new_commands[registered_name] = Callable(instance, name)
	
	if instance.has_method("get_command_info"):
			command_info.merge(instance.get_command_info(), true)
	
	if overwrite:
		for old_name in plugin_commands.get(file_name, []):
			command_registry.erase(old_name)
	
	plugin_commands[file_name] = new_commands.keys()
	command_registry.merge(new_commands, true)
	
	terminal.highlighter.add_command_color(command_registry.keys(), "yellow")
	return true

func get_command_blacklist():
	return COMMAND_BLACKLIST

func get_command_info():
	return COMMAND_INFO

func parse_line(line):
	var regex = RegEx.create_from_string(r'"([^"]*)"|(\S+)')
	var parts = []
	
	for match in regex.search_all(line.strip_edges()):
		var quoted = match.get_string(1)
		
		if quoted != "":
			parts.append(quoted)
		else:
			parts.append(match.get_string(2))
	
	return parts

func split_unquoted(text, separator):
	var parts = []
	var current = ""
	var quote = ""
	var escaped = false
	
	for c in text:
		if escaped:
			current += c
			escaped = false
		elif c == "\\":
			current += c
			escaped = true
		elif c == quote and quote != "":
			quote = ""
			current += c
		elif c == '"' or c == "'":
			quote = c
			current += c
		elif c == separator and quote == "":
			parts.append(current)
			current = ""
		else:
			current += c
	
	parts.append(current)
	return parts
	
func has_arg(function, arg_name):
	var obj = function.get_object()
	var script = obj.get_script()
	
	for method in script.get_script_method_list():
		if method["name"] != function.get_method():
			continue
		
		for arg in method["args"]:
			if arg["name"] == arg_name:
				return true
	
	return false

func handle_output(args, function, pipe_input=null, pipe=false):
	var options = []
	var new_args = []
	var parsing_options = true

	for arg in args:
		if parsing_options and arg == "--":
			parsing_options = false
		elif parsing_options and arg.begins_with("-"):
			options.append(arg)
		else:
			new_args.append(arg)

	args = new_args
	
	if not has_arg(function, "options") and not options.is_empty():
		terminal.write_output(function.get_method() + ": unrecognized option '" + options[0] + "'", "red")
		return
		
	if await handle_redirect(args, options, function, pipe_input):
		return
	
	var func_res = await function.call(args, options, pipe_input)
	
	if pipe:
		return output_to_text(func_res)
	
	if func_res is Array:
		if func_res.is_empty():
			return
		
		if func_res[0] is Array:
			for item in func_res:
				if item is Array and item.size() >= 2:
					terminal.write_output(item[0], item[1])
		else:
			terminal.write_output(func_res[0], func_res[1] if func_res.size() > 1 else "white")
	elif func_res:
		terminal.write_output(func_res)

func handle_redirect(args, options, function, pipe_input):
	if args.size() >= 2 and (args[-2] == ">" or args[-2] == ">>"):
		var output_path = solve_path(args[-1])
		var command_args = args.slice(0, -2)
		var func_res = await function.call(command_args, options, pipe_input)
		var append = false
		if args[-2] == ">>":
			append = true
		var file
		
		if append and FileAccess.file_exists(output_path):
			file = FileAccess.open(output_path, FileAccess.READ_WRITE)
		else:
			file = FileAccess.open(output_path, FileAccess.WRITE)
		
		if not file:
			terminal.write_output("Cannot create file: " + args[-1], "red")
			return true
			
		if append:
			file.seek_end()
		
		var output = output_to_text(func_res)
		if not output.ends_with("\n"):
			output += "\n"
		
		file.store_string(output)
		
		return true

func output_to_text(output):
	if output == null:
		return ""
	
	if output is Array:
		if output.is_empty():
			return ""
		
		if output[0] is Array:
			var lines = []
			
			for item in output:
				if item is Array and not item.is_empty():
					lines.append(str(item[0]))
			
			return "\n".join(lines)
		
		return str(output[0])
	
	return str(output)

func solve_path(path):
	path = path.replace("\\", "/")
	
	if path == "~":
		return terminal.get_home_dir()
	elif path.begins_with("~/"):
		return path.replace("~", terminal.get_home_dir()).simplify_path()
	
	if path == "-":
		return terminal.last_working_dir
	
	if path == "$gd_user":
		return OS.get_user_data_dir()
	elif path.begins_with("$gd_user/"):
		return path.replace("$gd_user", OS.get_user_data_dir()).simplify_path()
		
	
	if path.begins_with("/") and OS.has_feature("windows"):
		var parts = path.split("/", false)
		
		if parts.is_empty():
			return terminal.working_dir.get_slice(":", 0).to_lower() + ":/" + "/".join(parts)
			
		var drive = parts[0]
		
		if drive.length() == 1 and drive.to_lower() >= "a" and drive.to_lower() <= "z":
			parts.remove_at(0)
			return drive.to_lower() + ":/" + "/".join(parts)
	
	if not path.is_absolute_path():
		path = terminal.working_dir.path_join(path)
	
	return path.simplify_path().replace("\\", "/")

func is_path_protected(path):
	path = path.simplify_path().replace("\\", "/").trim_suffix("/")
	var home = terminal.get_home_dir().simplify_path().replace("\\", "/").trim_suffix("/")
	
	if OS.has_feature("windows"):
		path = path.to_lower()
		home = home.to_lower()
	
	if path == "" or path == "/":
		return true
	if path.length() == 2 and path[1] == ":":
		return true
		
	if path == home or home.begins_with(path + "/"):
		return true

	return false

func install_plugin(path, remote=false, temp=false, overwrite=false):
	var src = ""
	var name = ""
	
	# get script
	if remote:
		src  = await curl([path], null, null)
		if src is Array:
			return ["gdpt: failed to get '" + path + "'", "red"]
		
		name = path.split("?")[0].get_basename().get_file()
	else:
		var solved_path = solve_path(path)
		var file = FileAccess.open(solve_path(path), FileAccess.READ)
		if not file:
			return ["gdpt: file not found '" + path + "'", "red"]
		
		src = file.get_as_text()
		name = solved_path.get_basename().get_file()
	
	if name.is_empty() or name == "." or name == "..":
		return ["gdpt: invalid library name", "red"]
		
	# compile script
	var script = GDScript.new()
	script.source_code = src
	if script.reload() != OK:
		return ["gdpt: failed to import '" + path + "'", "red"]
	
	var init_args = 0
	for method in script.get_script_method_list():
		if method.name == "_init":
			init_args = method.args.size()
			break
		
	var instance
	
	if init_args == 0:
		instance = script.new()
	elif init_args == 1:
		instance = script.new(terminal)
	elif init_args == 2:
		instance = script.new(terminal, self)
	else:
		return ["gdpt: unsupported library constructor", "red"]
		
	if not is_instance_valid(instance):
		return ["gdpt: failed to create library instance", "red"]
	
	if not temp:
		if FileAccess.file_exists("user://libs/" + name + ".gd") and not overwrite:
			return ["gdpt: library '" + name + "' already installed, use gdpt update to overwrite.", "red"]
		
		var file =  FileAccess.open("user://libs/" + name + ".gd" , FileAccess.WRITE)
		file.store_string(src)
	
	if not register_commands(instance, name, overwrite):
		if not temp and not overwrite:
			DirAccess.remove_absolute("user://libs/" + name + ".gd")

		return ["gdpt: invalid library interface", "red"]
	
	loaded_plugins.append(instance)
	return ""

func remove_recursive(path):
	for file in DirAccess.get_files_at(path):
		var file_path = path.path_join(file)
		var err = DirAccess.remove_absolute(file_path)
		
		if err != OK:
			return err
	
	for dir in DirAccess.get_directories_at(path):
		var dir_path = path.path_join(dir)
		var err = remove_recursive(dir_path)
		
		if err != OK:
			return err
	
	return DirAccess.remove_absolute(path)

func get_wc_text(text_content, name, options):
	var lines = text_content.count("\n")
	var word_regex = RegEx.create_from_string(r"\S+")
	var words = word_regex.search_all(text_content).size()
	var bytes = text_content.to_utf8_buffer().size()
	
	var text_line = ""
	
	if "-l" in options:
		text_line += str(lines) + " "
	if "-w" in options:
		text_line += str(words) + " "
	if "-c" in options:
		text_line += str(bytes) + " "
	
	if text_line == "":
		text_line = str(lines) + " " + str(words) + " " + str(bytes) + " "
	
	return text_line + name

func get_grep_text(text, pattern, options):
	var output = ""
	var count = 0
	var search_pattern = pattern.to_lower() if "-i" in options else pattern
	
	for line in text.split("\n", false):
		var search_line
		if "-i" in options:
			search_line = line.to_lower()
		else:
			search_line = line
		
		if search_line.contains(search_pattern) and "-v" not in options:
			count += 1
			if "-c" not in options:
				output += line + "\n"
		elif "-v" in options and not search_line.contains(search_pattern):
			count += 1
			if "-c" not in options:
				output += line + "\n"
	
	if "-c" in options:
		output += str(count)
	
	return output.trim_suffix("\n")

func get_tree_text(arg, path, options, current_layer, prefix=""):
	if not DirAccess.dir_exists_absolute(path):
		return [[["tree: " + arg + ": No such directory", "red"]], 0, 0]
	
	var dirs = DirAccess.get_directories_at(path)
	var files = DirAccess.get_files_at(path)
	
	var all_here = []
	var entries = []
	
	var dir_ammount = 0
	var file_ammount = 0
	
	for dir in dirs:
		if not dir.begins_with(".") or "-a" in options:
			entries.append([dir, true])

	for file in files:
		if not file.begins_with(".") or "-a" in options:
			entries.append([file, false])
	
	for i in range(entries.size()):
		var name = entries[i][0]
		var is_dir = entries[i][1]
		var is_last = i == entries.size() - 1
		
		var branch = "└── " if is_last else "├── "
		var next_prefix = prefix + ("    " if is_last else "│   ")
		
		all_here.append([prefix + branch + name + ("/..." if is_dir and current_layer >= 3 else "/" if is_dir else ""), "white"])
		
		if is_dir:
			dir_ammount += 1
			
			if current_layer < 3:
				var result = get_tree_text(name, path.path_join(name), options, current_layer + 1, next_prefix)
				all_here.append_array(result[0])
				dir_ammount += result[1]
				file_ammount += result[2]
		else:
			file_ammount += 1
			
	return [all_here, dir_ammount, file_ammount]

func pwd(_args, _options, _pipe_input):
	return terminal.working_dir
	
func cd(args, _options, _pipe_input):
	if args.is_empty():
		terminal.set_working_dir(terminal.get_home_dir())
		return
	
	var path = solve_path(args[0])
	
	if DirAccess.dir_exists_absolute(path):
		terminal.set_working_dir(path)
		return
	
	return ["cd: " + args[0] + ": No such directory", "red"]

func mkdir(args, options, _pipe_input):
	var valid_options = ["-p"]
	for option in options:
		if option not in valid_options:
			return ["mkdir: unrecognized option '" + option + "'" , "red"]
	
	if not args:
		return ["mkdir: missing directory", "red"]
	
	for arg in args:
		var path = solve_path(arg)
		
		var err
		if "-p" in options:
			err = DirAccess.make_dir_recursive_absolute(path)
		else:
			err = DirAccess.make_dir_absolute(path)
		
		if err != OK:
			return ["mkdir: cannot create directory '" + arg + "'", "red"]

func rmdir(args, _options, _pipe_input):
	if not args:
		return ["rmdir: missing directory", "red"]
		
	for arg in args:
		var path = solve_path(arg)
		
		if DirAccess.dir_exists_absolute(path):
			var err = DirAccess.remove_absolute(path)
			
			if err != OK:
				return ["rmdir: failed to remove '" + arg + "'", "red"]
		else:
			return ["rmdir: " + arg + ": No such directory", "red"]
		
func ls(args, options, _pipe_input):
	var valid_options = ["-a"]
	for option in options:
		if option not in valid_options:
			return ["ls: unrecognized option '" + option + "'" , "red"]
	
	if args.is_empty():
		args.append(terminal.working_dir)
	
	var all = []
	
	for arg in args:
		var path = solve_path(arg)
		
		if not DirAccess.dir_exists_absolute(path):
			return ["ls: " + arg + ": No such directory", "red"]
		
		var dirs = DirAccess.get_directories_at(path)
		var files = DirAccess.get_files_at(path)
		
		var all_here = []
		
		for dir in dirs:
			if not dir.begins_with(".") or "-a" in options:
				all_here.append([dir + "/", "blue"])
		for file in files:
			if not file.begins_with(".") or "-a" in options:
				all_here.append([file, "white"])
		
		all_here.sort_custom(func(a, b): return a[0] < b[0])
		
		all.append([path.get_file() + "/:", "cyan"])
		all.append_array(all_here)
		if not arg == args[args.size() - 1]:
			all.append([" ", "white"])
	
	return all

func tree(args, options, _pipe_input):
	var valid_options = ["-a"]
	for option in options:
		if option not in valid_options:
			return ["tree: unrecognized option '" + option + "'" , "red"]
	
	if args.is_empty():
		args.append(terminal.working_dir)
	
	var all = []
	
	for arg in args:
		var path = solve_path(arg)
		var all_here = get_tree_text(arg, path, options, 1)
		
		all.append([path.get_file() + "/:", "cyan"])
		all.append_array(all_here[0])
		if not arg == args[args.size() - 1]:
			all.append([" ", "white"])
		
		var ammount_info = str(all_here[1]) + (" directory" if all_here[1] == 1 else " directories") + ", "
		ammount_info +=  str(all_here[2]) + (" file" if all_here[2] == 1 else " files")
		
		
		all.append_array([[" ", "white"], [ammount_info , "white"]])
	
	return all

func echo(args, options, _pipe_input):
	var valid_options = ["-e", "-c"]
	for option in options:
		if option not in valid_options:
			return ["echo: unrecognized option '" + option + "'" , "red"]
	
	var color = "white"
	if "-c" in options:
		if args.is_empty():
			return ["echo: missing color", "red"]
		
		color = args.pop_front()
		
		if color not in terminal.highlighter.color_names:
			return ["echo: color '" + color + "' does not exist", "red"]
	
	var text = " ".join(args)
	
	if "-e" in options:
		text = text.c_unescape()
	
	return [text, color]

func touch(args, _options, _pipe_input):
	if not args:
		return ["touch: missing path", "red"]
	
	for arg in args:
		var path = solve_path(arg)
		var file
		if FileAccess.file_exists(path):
			file = FileAccess.open(path, FileAccess.READ_WRITE)
		else:
			file = FileAccess.open(path, FileAccess.WRITE)
		
		if not file:
			return ["touch: cannot touch '" + arg + "'", "red"]
		
func cat(args, options, pipe_input):
	var valid_options = ["-n"]
	for option in options:
		if option not in valid_options:
			return ["cat: unrecognized option '" + option + "'" , "red"]
	
	if args.is_empty() and pipe_input == null:
		return ["cat: missing file", "red"]
	
	var text = ""
	
	if pipe_input:
		text += pipe_input
		
	for arg in args:
		var path = solve_path(arg)
		var file = FileAccess.open(path, FileAccess.READ)
		
		if not file:
			return ["cat: " + arg + ": No such file", "red"]
		
		text += file.get_as_text()
	
	if "-n" in options:
		var text_lines = text.split("\n")
		text = ""
		for i in text_lines.size():
			if i == text_lines.size() - 1:
				text += str(i + 1) + " " + text_lines[i]
			else:
				text += str(i + 1) + " " + text_lines[i] + "\n"
				
	return text

func head(args, _options, pipe_input):
	if args.is_empty() and pipe_input == null:
		return ["head: missing file", "red"]
	
	var text = ""
	
	if pipe_input:
		if args.size() > 0:
			text += "==> piped <==\n" + pipe_input.split("\n", false)[0] + "\n"
		else:
			text += pipe_input.split("\n", false)[0] + "\n"
		
	for arg in args:
		var path = solve_path(arg)
		var file = FileAccess.open(path, FileAccess.READ)
		
		if not file:
			return ["head: " + arg + ": No such file", "red"]
		
		if args.size() > 1:
			text += "==> " + path.get_file() + " <==\n" + file.get_line() + "\n"
			if not arg == args[args.size() - 1]:
				text += "\n"
		else:
			text += file.get_line()
			
	return text.trim_suffix("\n")

func tail(args, _options, pipe_input):
	if args.is_empty() and pipe_input == null:
		return ["tail: missing file", "red"]
	
	var text = ""
	
	if pipe_input:
		if args.size() > 0:
			text += "==> piped <==\n" + pipe_input.split("\n", false)[-1] + "\n"
		else:
			text += pipe_input.split("\n", false)[-1] + "\n"
			
	for arg in args:
		var path = solve_path(arg)
		var file = FileAccess.open(path, FileAccess.READ)
		
		if not file:
			return ["tail: " + arg + ": No such file", "red"]
		
		if args.size() > 1:
			text += "==> " + path.get_file() + " <==\n" + file.get_as_text().split("\n", false)[-1]  + "\n"
			if not arg == args[args.size() - 1]:
				text += "\n"
		else:
			text += file.get_as_text().split("\n", false)[-1]
			
	return text.trim_suffix("\n")

func wc(args, options, pipe_input):
	var valid_options = ["-l", "-w", "-c"]
	for option in options:
		if option not in valid_options:
			return ["wc: unrecognized option '" + option + "'" , "red"]
	
	if args.is_empty() and pipe_input == null:
		return ["wc: missing file", "red"]
	
	var text = ""
	
	if pipe_input:
		text += get_wc_text(pipe_input, "piped", options) + "\n"
	
	for arg in args:
		var path = solve_path(arg)
		var file = FileAccess.open(path, FileAccess.READ)
		
		if not file:
			return ["wc: " + arg + ": No such file", "red"]
		
		text += get_wc_text(file.get_as_text(), path.get_file(), options) + "\n"
		
	return text.trim_suffix("\n")

func sort(args, _options, pipe_input):
	if args.is_empty() and pipe_input == null:
		return ["sort: missing file", "red"]
	
	var lines = []
	
	if pipe_input:
		for line in pipe_input.split("\n", false):
			lines.append(line)
	
	for arg in args:
		var path = solve_path(arg)
		var file = FileAccess.open(path, FileAccess.READ)
		
		if not file:
			return ["sort: " + arg + ": No such file", "red"]
				
		for line in file.get_as_text().split("\n", false):
			lines.append(line)
	
	lines.sort()
	
	return "\n".join(lines)

func grep(args, options, pipe_input):
	var valid_options = ["-i", "-v", "-c"]
	for option in options:
		if option not in valid_options:
			return ["grep: unrecognized option '" + option + "'" , "red"]
	
	if not args:
		return ["grep: missing pattern", "red"]
	
	var pattern = args[0]
	args.remove_at(0)
	var text = ""
	
	if pipe_input:
		text += get_grep_text(pipe_input, pattern, options)
		if args.size() > 1:
			text += "\n"
	
	for arg in args:
		var path = solve_path(arg)
		var file = FileAccess.open(path, FileAccess.READ)
		if not file:
			return ["grep: " + arg + ": No such file", "red"]
		
		if args.size() > 1:
			text += "==> " + path.get_file() + " <==\n"
		
		text += get_grep_text(file.get_as_text(), pattern, options)
		
		if args.size() > 1 and arg != args[-1]:
			text += "\n"
		
	return text

func cp(args, _options, _pipe_input):
	if args.size() < 2:
		return ["cp: missing target file or directory", "red"]
	
	var path = solve_path(args[0])
	var res_path = solve_path(args[1])
	
	if DirAccess.dir_exists_absolute(res_path):
		res_path = res_path.path_join(path.get_file())
	
	var err = DirAccess.copy_absolute(path, res_path)
	
	if err != OK:
		return ["cp: " + args[0] + ": No such file or directory", "red"]
		
func mv(args, _options, _pipe_input):
	if args.size() < 2:
		return ["mv: missing target file or directory", "red"]
	
	var old_path = solve_path(args[0])
	var new_path = solve_path(args[1])
	
	if DirAccess.dir_exists_absolute(new_path):
		new_path = new_path.path_join(old_path.get_file())
	
	var err = DirAccess.rename_absolute(old_path, new_path)
	
	if err != OK:
		return ["mv: cannot move '" + args[0] + "'", "red"]

func rm(args, options, _pipe_input):
	var valid_options = ["-r"]
	for option in options:
		if option not in valid_options:
			return ["rm: unrecognized option '" + option + "'" , "red"]
	
	if not args:
		return ["rm: missing target file", "red"]
	
	for arg in args:
		var path = solve_path(arg).simplify_path().trim_suffix("/")
		
		if is_path_protected(path):
			return ["rm: refusing to remove protected path '" + arg + "'", "red"]
		
		if FileAccess.file_exists(path):
			var err = DirAccess.remove_absolute(path)
			if err != OK:
				return ["rm: failed to remove '" + arg + "'", "red"]
		elif DirAccess.dir_exists_absolute(path):
			if "-r" not in options:
				return ["rm: cannot remove '" + arg + "': Is a directory", "red"]
			
			var err = remove_recursive(path)
			if err != OK:
				return ["rm: failed to remove '" + arg + "'", "red"]
		else:
			return ["rm: cannot remove '" + arg + "': No such file or directory", "red"]

func ping(args, _options, _pipe_input):
	if not args:
		return ["ping: no URL specified", "red"]
	
	var url = args[0]
	
	if not url.begins_with("http://") and not url.begins_with("https://"):
		url = "https://" + url
	
	var http = HTTPRequest.new()
	http.timeout = 10
	terminal.add_child(http)
	
	var start_time = Time.get_ticks_usec()
	
	var error = http.request(url, [], HTTPClient.METHOD_HEAD)
	if error != OK:
		http.queue_free()
		return ["ping: failed to start request", "red"]
		
	var response = await http.request_completed
	var end_time = Time.get_ticks_usec()
	http.queue_free()
	
	var result = response[0]
	
	if result != HTTPRequest.RESULT_SUCCESS:
		return ["ping: request failed (" + str(result) + ")", "red"]
	
	return "PING " + args[0] + "\nResponse in: " + str((end_time - start_time) / 1000.0) + " ms"

func curl(args, _options, _pipe_input):
	if not args:
		return ["curl: no URL specified", "red"]
	
	var url = args[0]
	
	if not url.begins_with("http://") and not url.begins_with("https://"):
		url = "https://" + url
	
	var http = HTTPRequest.new()
	http.timeout = 10
	terminal.add_child(http)
	
	var error = http.request(url)
	if error != OK:
		http.queue_free()
		return ["curl: failed to start request", "red"]
		
	var response = await http.request_completed
	http.queue_free()
	
	var result = response[0]
	var body = response[3]
	
	if result != HTTPRequest.RESULT_SUCCESS:
		return ["curl: request failed (" + str(result) + ")", "red"]
		
	var content = body.get_string_from_utf8()
	
	return content

func gdpt(args, options, _pipe_input):
	var valid_options = ["-r", "-t"]
	for option in options:
		if option not in valid_options:
			return ["gdpt: unrecognized option '" + option + "'" , "red"]
	
	if not args:
		return ["gdpt: invalid command", "red"]
	if args[0] not in ["install", "update"]:
		return ["gdpt: invalid command '" + args[0] + "'", "red"]
	if args.size() < 2:
		return ["gdpt: missing file", "red"]
	
	var overwrite = false
	if args[0] == "update":
		overwrite = true
	
	var installed = 0
	
	for path in args.slice(1):
		var result = await install_plugin(path, "-r" in options, "-t" in options, overwrite)
		if result is Array:
			return result
		
		installed += 1
	
	return "gdpt: installed " + str(installed) + " libraries successfully"

func uname(_args, options, _pipe_input):
	var valid_options = ["-a", "-s", "-o", "-r", "-n", "-m", "-p", "-i"]
	for option in options:
		if option not in valid_options:
			return ["uname: unrecognized option '" + option + "'" , "red"]
	
	if "-a" in options:
		var host = OS.get_environment("COMPUTERNAME")
		if host.is_empty():
			host = OS.get_environment("HOSTNAME")
		if host.is_empty():
			var output = []
			if OS.execute("hostname", [], output) == 0 and not output.is_empty():
				host = output[0].strip_edges()
		if host.is_empty():
			host = "localhost"
		
		return OS.get_name() + " " + OS.get_version_alias() + " " + OS.get_version() + " " + host + " " + Engine.get_architecture_name() + " "
		
	var text = ""
	if "-s" in options or "-o" in options:
		text += OS.get_name() + " "
	if "-r" in options:
		text += OS.get_version_alias() + " " + OS.get_version() + " "
	if "-n" in options:
		var host = OS.get_environment("COMPUTERNAME")
		if host.is_empty():
			host = OS.get_environment("HOSTNAME")
		if host.is_empty():
			var output = []
			if OS.execute("hostname", [], output) == 0 and not output.is_empty():
				host = output[0].strip_edges()
		if host.is_empty():
			host = "localhost"
			
		text += host + " "
	if "-m" in options or "-p" in options or "-i" in options:
		text += Engine.get_architecture_name() + " "
	
	if text == "":
		text = OS.get_name()
	
	return text

func whoami(_args, _options, _pipe_input):
	if OS.has_environment("USERNAME"):
		return OS.get_environment("USERNAME")
	elif OS.has_environment("USER"):
		return OS.get_environment("USER")

func clear(_args, _options, _pipe_input):
	terminal.clear_and_reset_colors()
	
func help(args, _options, _pipe_input):
	var text = ""
	
	if args:
		for arg in args:
			var description = command_info.get(arg, "")
			
			if description != "":
				text += arg + " - " + description + "\n"
			else:
				text += arg + "\n"
	
	else:
		for command in command_registry.keys():
			var description = command_info.get(command, "")
			
			if description != "":
				text += command + " - " + description + "\n"
			else:
				text += command + "\n"
	
	return text.trim_suffix("\n")

func man(args, _options, _pipe_input):
	if not args:
		return ["man: missing command name", "red"]
	
	var command = args[0]
	if not man_dict:
		var file = FileAccess.open("res://man.json", FileAccess.READ)
		man_dict = JSON.parse_string(file.get_as_text())
	
	if command not in man_dict:
		return ["man: no manual page found for '" + command + "'", "red"]
	
	var text = "NAME\n\t" + help([command], null, null) + "\n\n"
	text += "SYNOPSIS\n\t" + man_dict[command]["synopsis"] + "\n\n"
	text += "DESCRIPTION\n\t" + man_dict[command]["description"]
	if "options" in man_dict[command]:
		text += "\n\nOPTIONS\n\t" + man_dict[command]["options"]
	
	return text

func history(_args, _options, _pipe_input):
	var text = ""
	for i in terminal.entered_commands.size():
		text += str(i + 1) + " " + terminal.entered_commands[i] + "\n"
		
	return text.trim_suffix("\n")

func reset(_args, _options, _pipe_input):
	if terminal.is_inside_tree():
		terminal.get_tree().call_deferred("reload_current_scene")

func colors(_args, options, _pipe_input):
	var lines = []
	
	var valid_options = ["-a"]
	for option in options:
		if option not in valid_options:
			return ["colors: unrecognized option '" + option + "'" , "red"]
	
	if "-a" in options:
		lines.append_array([
			["bg        ████   #" + terminal.syntax_highlighter.colors["bg"].to_html().to_upper(), "bg"],
			["caret     ████   #" + terminal.syntax_highlighter.colors["caret"].to_html().to_upper(), "caret"],
			["selection ████   #" + terminal.syntax_highlighter.colors["selection"].to_html().to_upper(), "selection"],
			["selected  ████   #" + terminal.syntax_highlighter.colors["selected"].to_html().to_upper(), "selected"],
			["black     ████   #" + terminal.syntax_highlighter.colors["black"].to_html().to_upper(), "black"],
		])
	
	lines.append_array([
		["white     ████   #" + terminal.syntax_highlighter.colors["white"].to_html().to_upper(), "white"],
		["red       ████   #" + terminal.syntax_highlighter.colors["red"].to_html().to_upper(), "red"],
		["yellow    ████   #" + terminal.syntax_highlighter.colors["yellow"].to_html().to_upper(), "yellow"],
		["pink      ████   #" + terminal.syntax_highlighter.colors["pink"].to_html().to_upper(), "pink"],
		["green     ████   #" + terminal.syntax_highlighter.colors["green"].to_html().to_upper(), "green"],
		["cyan      ████   #" + terminal.syntax_highlighter.colors["cyan"].to_html().to_upper(), "cyan"],
		["blue      ████   #" + terminal.syntax_highlighter.colors["blue"].to_html().to_upper(), "blue"],
	])
		
	return lines
