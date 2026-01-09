@tool
extends HBoxContainer

var text_edit: LineEdit


func _ready() -> void:
	# Lookup the LineEdit dynamically to ensure editor-safe behavior
	text_edit = find_child("Text", true, false)
	if not text_edit:
		push_warning("CommentBlock: Text LineEdit not found.")


func set_comment_text(t: String) -> void:
	if not text_edit:
		text_edit = find_child("Text", true, false)
	if text_edit:
		text_edit.text = t
