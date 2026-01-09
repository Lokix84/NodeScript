extends CharacterBody2D

signal died


@onready var animation: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite
#region Player
@export var move_speed: float = 200.0
enum State {IDLE, RUN, JUMP, FALL}


var state: State = State.IDLE
#endregion Player


#region HP
@export var max_health: int = 100
var health: int = 100
#endregion HP


#region test_3
class character:
	pass

#endregion test_3


class test:
	#region test_2
	#endregion test_2

	pass


#region test
#endregion test


signal health_changed(current, max)

func _ready() -> void:
	# Initialize
	animation.play("idle")
	emit_signal("health_changed", health, max_health)

func _process(delta: float) -> void:
	_handle_input(delta)
	_apply_state(delta)

func _handle_input(_delta: float) -> void:
	var x := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")

	if x != 0:
		velocity.x = x * move_speed
		state = State.RUN
	else:
		velocity.x = 0
		state = State.IDLE

	if Input.is_action_just_pressed("ui_accept"):
		_jump()

func _apply_state(_delta: float) -> void:
	match state:
		State.IDLE:
			animation.play("idle")

		State.RUN:
			animation.play("run")

		_:
			animation.play("idle")

func _jump() -> void:
	if is_on_floor():
		velocity.y = -350
		state = State.JUMP
		animation.play("jump")

func take_damage(amount: int) -> void:
	if health <= 0:
		return

	health -= amount
	emit_signal("health_changed", health, max_health)

	if health <= 0:
		emit_signal("died")
		animation.play("death")
