extends SceneTree
## Renders a scene for a few frames and saves a PNG. Needs a real display
## (use xvfb-run on a server):
##   xvfb-run -s "-screen 0 720x1280x24" godot --path . --rendering-driver opengl3 \
##     --script res://tools/screenshot.gd -- res://scenes/main.tscn out.png [setup_method]

var _frames := 0
var _out := ""
var _setup := ""
var _node: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else "res://scenes/main.tscn"
	_out = args[1] if args.size() > 1 else "/tmp/shot.png"
	_setup = args[2] if args.size() > 2 else ""
	_node = load(scene_path).instantiate()
	root.add_child(_node)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3 and _setup != "" and _node.has_method(_setup):
		_node.call(_setup)
	if _frames == 8:
		var img := root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out, " ", img.get_size())
		quit()
	return false
