class_name TerminalCommands
extends RefCounted

const COMMAND_BLACKLIST = ["_init", "execute", "get_command_names", "parse_line", "handle_output"]

const COMMAND_INFO = {
	"pwd": "Print the current working directory",
	"cd": "Change the current working directory",
	"mkdir": "Create a directory",
	"rmdir": "Remove an empty directory",
	"ls": "List directory contents",
	"echo": "Print text",
	"touch": "Create an empty file",
	"cat": "Print file contents",
	"cp": "Copy a file",
	"mv": "Move or rename a file",
	"rm": "Remove a file",
	"uname": "Print system information",
	"whoami": "Print the current user",
	"clear": "Clear the terminal",
	"help": "Show available commands"
}

var terminal: Terminal
var command_names

func _init(terminal_ref) -> void:
	terminal = terminal_ref
	command_names = get_command_names()

func execute(command_line) -> void:
	var parts = parse_line(command_line)
	
	if parts.is_empty():
		return
	
	var command = parts[0]
	var args = parts.slice(1)
	
	if command in get_command_names():
		handle_output(args, Callable(self, command))
	else:
		terminal.write_output(command + ": not found", Color("#FF628C"))

func get_command_names():
	var command_names = []
	
	for method in get_script().get_script_method_list():
		var name = method.name
		
		if name not in COMMAND_BLACKLIST:
			command_names.append(name)
		
	return command_names

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

func handle_output(args, function):
	if args.size() >= 2 and args[-2] == ">":
		var output_path = args[-1].replace("\\", "/")
		var command_args = args.slice(0, -2)
		var func_res = function.call(command_args)
			
		if not output_path.is_absolute_path():
			output_path = terminal.working_dir.path_join(output_path)
		
		output_path = output_path.simplify_path().replace("\\", "/")
		var file = FileAccess.open(output_path, FileAccess.WRITE)
		
		if not file:
			terminal.write_output("cannot create file: " + args[-1], Color("#FF628C"))
			return
		
		if func_res is Array:
			file.store_string(str(func_res[0]))
		elif func_res:
			file.store_string(str(func_res))
		
		file.close()
		return
	
	var func_res = function.call(args)
	
	if func_res is Array:
		if func_res[0] is Array:
			for item in func_res:
				if item is Array and item.size() >= 2:
					terminal.write_output(item[0], item[1])
		else:
			terminal.write_output(func_res[0], func_res[1])
	else:
		if func_res:
			terminal.write_output(func_res)

func pwd(_args):
	return terminal.working_dir
	
func cd(args):
	if args.is_empty():
		terminal.set_working_dir(terminal.get_home_dir())
		return
	
	var target_path = args[0].replace("\\", "/")
	
	if target_path == "/":
		if OS.has_feature("windows"):
			var current_drive = terminal.working_dir.get_slice(":", 0)
			target_path = current_drive + ":/"
		else:
			target_path = "/"
	elif target_path == "..":
		target_path = terminal.working_dir.get_base_dir()
	
	if not target_path.is_absolute_path():
		target_path = terminal.working_dir.path_join(target_path)
	
	target_path = target_path.simplify_path().replace("\\", "/")
		
	if DirAccess.dir_exists_absolute(target_path):
		terminal.set_working_dir(target_path)
	else:
		return ["cd: " + args[0] + ": No such directory", Color("#FF628C")]

func mkdir(args):
	for arg in args:
		var path = arg.replace("\\", "/")
	
		if not path.is_absolute_path():
			path = terminal.working_dir.path_join(path)
		
		var err = DirAccess.make_dir_absolute(path)
		
		if err != OK:
			return ["mkdir: cannot create directory '" + arg + "'", Color("#FF628C")]

func rmdir(args):
	for arg in args:
		var path = arg.replace("\\", "/")
	
		if not path.is_absolute_path():
			path = terminal.working_dir.path_join(path)
		
		if DirAccess.dir_exists_absolute(path):
			var err = DirAccess.remove_absolute(path)
			
			if err != OK:
				return ["rmdir: failed to remove '" + arg + "'", Color("#FF628C")]
		else:
			return ["rmdir: " + arg + ": No such directory", Color("#FF628C")]
		
func ls(_args):
	var dirs = DirAccess.get_directories_at(terminal.working_dir)
	var files = DirAccess.get_files_at(terminal.working_dir)
	
	var all = []
	
	for dir in dirs:
		all.append([dir + "/", Color("#0088FF")])
	for file in files:
		all.append([file, terminal.get_theme_color("font_color")])
	
	all.sort_custom(func(a, b): return a[0] < b[0])
	
	return all

func echo(args):
	var text = ""
	for arg in args:
		text += arg + "\n"
	
	return text

func touch(args):
	for arg in args:
		var path = arg.replace("\\", "/")
		
		if not path.is_absolute_path():
			path = terminal.working_dir.path_join(path)
		
		if FileAccess.file_exists(path):
			continue
		
		var file = FileAccess.open(path, FileAccess.WRITE)
		
		if not file:
			return ["touch: cannot touch '" + arg + "'", Color("#FF628C")]
		
		file.close()

func cat(args):
	var text = ""
	for arg in args:
		var path = arg.replace("\\", "/")
	
		if not path.is_absolute_path():
			path = terminal.working_dir.path_join(path)
		
		var file = FileAccess.open(path, FileAccess.READ)
		
		if not file:
			return ["cat: " + arg + ": No such file", Color("#FF628C")]
		
		text += file.get_as_text()
		file.close()
		
	return text

func wc(args):
	var text = ""
	for arg in args:
		var path = arg.replace("\\", "/")
	
		if not path.is_absolute_path():
			path = terminal.working_dir.path_join(path)
		
		var file = FileAccess.open(path, FileAccess.READ)
		
		if not file:
			return ["wc: " + arg + ": No such file", Color("#FF628C")]
		
		var text_content = file.get_as_text()
		var lines = text_content.split(" ", false).size()
		var words = text_content.split("\n", false).size()
		var chars = text_content.length()
		
		text += str(lines) + " " + str(words) + " " + str(chars) + " " + path.get_file() + "\n"
		file.close()
		
	return text

func sort(args):
	var lines = []
	
	for arg in args:
		var path = arg.replace("\\", "/")
	
		if not path.is_absolute_path():
			path = terminal.working_dir.path_join(path)
		
		var file = FileAccess.open(path, FileAccess.READ)
		
		if not file:
			return ["wc: " + arg + ": No such file", Color("#FF628C")]
				
		for line in file.get_as_text().split("\n", false):
			lines.append(line)
		file.close()
	
	lines.sort()
	
	var text = ""
	for line in lines:
		text += line + "\n"
	
	return text

func cp(args):
	if not args[0] and not args[1]:
		return ["cp: missing target file or directory", Color("#FF628C")]
	
	var path = args[0].replace("\\", "/")
	var res_path = args[1].replace("\\", "/")
	
	if not path.is_absolute_path():
		path = terminal.working_dir.path_join(path)
	if not res_path.is_absolute_path():
		res_path = terminal.working_dir.path_join(res_path)
	
	var err = DirAccess.copy_absolute(path, res_path)
	
	if err != OK:
		return ["cp: " + args[0] + ": No such file or directory", Color("#FF628C")]
		
func mv(args):
	var old_path = args[0].replace("\\", "/")
	var new_path = args[1].replace("\\", "/")
	
	if not old_path.is_absolute_path():
		old_path = terminal.working_dir.path_join(old_path)
	if not new_path.is_absolute_path():
		new_path = terminal.working_dir.path_join(new_path)
	
	if DirAccess.dir_exists_absolute(new_path):
		new_path = new_path.path_join(old_path.get_file())
	
	var err = DirAccess.rename_absolute(old_path, new_path)
	
	if err != OK:
		return ["mv: " + args[0] + ": No such file or directory", Color("#FF628C")]

func rm(args):
	for arg in args:
		var path = arg.replace("\\", "/")
	
		if not path.is_absolute_path():
			path = terminal.working_dir.path_join(path)
		
		if FileAccess.file_exists(path):
			var err = DirAccess.remove_absolute(path)
			
			if err != OK:
				return ["rm: failed to remove '" + arg + "'", Color("#FF628C")]
		else:
			return ["rm: " + arg + ": No such file", Color("#FF628C")]

func uname(_args):
	return OS.get_name()

func whoami(_args):
	if OS.has_environment("USERNAME"):
		return OS.get_environment("USERNAME")
	elif OS.has_environment("USER"):
		return OS.get_environment("USER")

func clear(_args):
	terminal.clear_and_reset_colors()
	
func help(args):
	var text = ""
	
	if args:
		for arg in args:
			var description = COMMAND_INFO.get(arg, "")
			
			if description != "":
				text += arg + " - " + description + "\n"
			else:
				text += arg + "\n"
	
	else:
		for command in get_command_names():
			var description = COMMAND_INFO.get(command, "")
			
			if description != "":
				text += command + " - " + description + "\n"
			else:
				text += command + "\n"
	
	return text
