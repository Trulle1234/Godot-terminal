class_name TerminalHighlighter
extends SyntaxHighlighter

var rules = []
var line_colors = {}
var span_colors = {}

func _get_line_syntax_highlighting(line: int) -> Dictionary:
	var color_map = {}
	var text = get_text_edit().get_line(line)
	var default_color = get_text_edit().get_theme_color("font_color")
	
	# full lines
	if line_colors.has(line):
		color_map[0] = {"color": line_colors[line]}
		return color_map
		
	# line spans
	if span_colors.has(line):
		for span in span_colors[line]:
			color_map[span.start] = {"color": span.color}
			color_map[span.end] = {"color": default_color}
	
	# other rules
	for rule in rules:
		var regex = rule.regex
		var color = rule.color
		
		for result in regex.search_all(text):
			var start = result.get_start()
			var end = result.get_end()
			
			color_map[start] = {"color": color}
			color_map[end] = {"color": default_color}
		
	return color_map

# add keyword with color
func add_keywords(words, color):
	var escaped_words = []
	
	for word in words:
		escaped_words.append("\\Q" + word + "\\E(?:\\s+|$)")
	
	var regex = RegEx.create_from_string("(" + "|".join(escaped_words) + ")")
	
	rules.append({"regex": regex, "color": color})
	clear_highlighting_cache()

# color a line
func set_line_color(line, color):
	line_colors[line] = color
	clear_highlighting_cache()

# color a span
func set_span_color(line, start, end, color):
	if not span_colors.has(line):
		span_colors[line] = []
	
	span_colors[line].append({"start": start, "end": end, "color": color})
	clear_highlighting_cache()
