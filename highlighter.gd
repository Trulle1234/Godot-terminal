class_name TerminalHighlighter
extends SyntaxHighlighter

const COLORS = {
	"black": Color("#000000"),
	"red": Color("#FF628C"),
	"green": Color("#3AD900"),
	"yellow": Color("#FFC600"),
	"blue": Color("#0088FF"),
	"pink": Color("#FB94FF"),
	"cyan": Color("#80FCFF"),
	"white": Color("#DCDCDCFF")
}

var rules = []
var line_colors = {}
var span_colors = {}

func _get_line_syntax_highlighting(line: int) -> Dictionary:
	var color_map = {}
	var text = get_text_edit().get_line(line)
	
	# full lines
	if line_colors.has(line):
		color_map[0] = {"color": line_colors[line]}
		return color_map
		
	# line spans
	if span_colors.has(line):
		for span in span_colors[line]:
			color_map[span.start] = {"color": span.color}
			color_map[span.end] = {"color": COLORS["white"]}
	
	# other rules
	for rule in rules:
		var command_text = text
		var offset = 0
		
		var prompt_end = text.find("$ ")
		
		if prompt_end != -1:
			offset = prompt_end + 2
			command_text = text.substr(offset)
		
		var regex = rule.regex
		var color = rule.color
		
		for result in regex.search_all(command_text):
			var start = result.get_start(2) + offset
			var end = result.get_end(2) + offset
			
			color_map[start] = {"color": color}
			color_map[end] = {"color": COLORS["white"]}
		
	return color_map

# add command with color
func add_command_color(words, color):
	var escaped_words = []
	
	for word in words:
		escaped_words.append("\\Q" + word + "\\E")
	
	var regex = RegEx.create_from_string("(^\\s*|;\\s*)(" + "|".join(escaped_words) + ")(?=\\s|$)")
	
	rules.append({"regex": regex, "color": COLORS[color]})
	
	clear_highlighting_cache()

# color a line
func set_line_color(line, color):
	line_colors[line] = COLORS[color]
	clear_highlighting_cache()

# color a span
func set_span_color(line, start, end, color):
	if not span_colors.has(line):
		span_colors[line] = []
	
	span_colors[line].append({"start": start, "end": end, "color": COLORS[color]})
	clear_highlighting_cache()
