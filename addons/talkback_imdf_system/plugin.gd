@tool
extends EditorPlugin

func _enter_tree() -> void:
	print("TalkBack + IMDF System addon loaded")

func _exit_tree() -> void:
	print("TalkBack + IMDF System addon unloaded")
