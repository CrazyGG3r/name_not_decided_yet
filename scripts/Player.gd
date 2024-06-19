extends CharacterBody3D

# Initialize node references
@onready var camera_mount = $camera_mount
@onready var animation_player = $visuals/mixamo_base/AnimationPlayer
@onready var visuals = $visuals
@onready var delay_timer = get_node("DelayTimer")

#======================================================#

# Speed settings
var SPEED = 3.0  # Default movement speed
const JUMP_VELOCITY = 4.5  # Velocity for jumping

# Different movement speed states
var walking_speed = 1.25
var normal_speed = 2.5
var running_speed = 5.0

# Movement state flags
var running = false
var walking = false
var is_locked = false  # If the character's movement is locked (e.g., during aiming)

#======================================================#

# Camera sensitivity settings
@export var sens_horizontal = 0.05  # Horizontal mouse sensitivity
@export var sens_vertical = 0.05  # Vertical mouse sensitivity

# Camera movement variables
var mouse_x_movement = 0.0  # Track mouse X movement
var camera_position  # Current position of the camera
var camera_direction_z  # Direction the camera is facing
var target_position  # Target position for camera movements
const MIN_ROTATION_X = deg_to_rad(-40)  # Minimum vertical camera rotation
const MAX_ROTATION_X = deg_to_rad(40)  # Maximum vertical camera rotation

# Camera position settings for sprinting
var initial_camera_position  # Initial position of the camera
var target_camera_position  # Target position for smooth camera transitions
const SPRINT_DISTANCE = 1  # Distance the camera moves during sprint
const TRANSITION_SPEED = 5.0  # Speed of camera position transition

#======================================================#

# Stamina settings
var stamina_cap = 100  # Maximum stamina
var stamina = stamina_cap  # Current stamina
var last_stamina = stamina  # Track the last recorded stamina
var is_tired = false  # Flag if the character is tired
var is_recovering = false  # Flag if the character is recovering stamina
var stamina_recovery_delay_timer = 3  # Delay before stamina starts recovering
#var delay_timer  # Timer node reference
var stamina_reduction_rate = stamina_cap / 10.0  # Rate of stamina reduction
var stamina_recovery_rate = stamina_cap / 6.0  # Rate of stamina recovery

# Get the gravity setting from project settings
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

#choppy animation settings
const FRAME_TIME := 0.17
var time_accumulator := 0.0
var last_animation := ""
var animation_position := 0.0
# Function to decrease stamina
func decrease_stamina(amount):
	if is_recovering:
		is_recovering = false
		delay_timer.stop()

	stamina -= amount
	if stamina <= 0:
		stamina = 0
		is_tired = true

	if delay_timer.is_stopped():
		delay_timer.start(stamina_recovery_delay_timer)

# Function called when the stamina recovery delay timer times out
func _on_Timer_timeout():
	if stamina == last_stamina and stamina < stamina_cap:
		is_recovering = true
		start_recovering_stamina()

# Function to start recovering stamina
func start_recovering_stamina():
	while is_recovering and stamina < stamina_cap:
		stamina += stamina_recovery_rate
		print("Recovering: Stamina = ", stamina)
		await get_tree().create_timer(0.1).timeout  # 0.1 second delay for smooth recovery
		if stamina == stamina_cap:
			is_recovering = false
			is_tired = false
			print("Recovery complete: Stamina = ", stamina)

# Ready function to initialize settings
func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # Capture the mouse for camera movement
	
	# Store the initial camera position
	initial_camera_position = camera_mount.position
	target_camera_position = initial_camera_position
	
	# Get the Timer node
	delay_timer = get_node("DelayTimer")
	if delay_timer:
		delay_timer.one_shot = true
		delay_timer.connect("timeout", Callable(self, "_on_Timer_timeout"))
	else:
		print("DelayTimer node not found")

# Input function to handle mouse and keyboard input
func _input(event):
	if event is InputEventMouseMotion:
		# Rotate character and camera based on mouse movement
		rotate_y(deg_to_rad(-event.relative.x * sens_horizontal))
		camera_mount.rotate_x(deg_to_rad(-event.relative.y * sens_vertical))
					
		if !is_locked:
			visuals.rotate_y(deg_to_rad(event.relative.x * sens_horizontal))  # Allow free look without camera follow
		
		# Clamp camera rotation within specified limits
		var current_rotation = camera_mount.rotation_degrees
		current_rotation.x -= event.relative.y * 0.1  # Adjust vertical sensitivity
		current_rotation.x = clamp(current_rotation.x, rad_to_deg(MIN_ROTATION_X), rad_to_deg(MAX_ROTATION_X))
		camera_mount.rotation_degrees = current_rotation
		
		mouse_x_movement = event.relative.x  # Track mouse X movement

# Physics process function for movement and physics calculations
func _physics_process(delta):
	# Update camera position and direction
	camera_position = camera_mount.global_transform.origin
	camera_direction_z = -camera_mount.global_transform.basis.z
	target_position = camera_position + camera_direction_z
	target_position.y = global_transform.origin.y
	
	# Handle sprint input and camera position changes
	if Input.is_action_just_pressed("sprint") and stamina > 0:
		target_camera_position = initial_camera_position + Vector3(0, 0, SPRINT_DISTANCE)  # Move camera back

	if Input.is_action_just_released("sprint"):
		target_camera_position = initial_camera_position  # Reset camera position
	
	# Smoothly interpolate camera position
	camera_mount.position = camera_mount.position.lerp(target_camera_position, TRANSITION_SPEED * delta)
	
	# Handle aim state and animation locking
	if !animation_player.is_playing():
		is_locked = false
		
	if Input.is_action_just_released("aim"):
		is_locked = false
		print("AIM STATE: OFF")
		
	if is_locked:
		running = false
	
	# Handle stamina recovery timing
	if stamina != last_stamina:
		if is_recovering:
			is_recovering = false
		delay_timer.stop()
		delay_timer.start(stamina_recovery_delay_timer)

	last_stamina = stamina

	# Apply gravity if the character is not on the floor
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:  # Handle ground state actions				
		if Input.is_action_just_pressed("aim"):
			print("AIM STATE: ON")
			animation_player.play("idle")
			is_locked = true
			
		if Input.is_action_pressed("aim"):
			visuals.look_at(target_position, Vector3.UP)
			running = false
			
		if Input.is_action_just_pressed("walk"):
			walking = not walking
			print("WALK STATE: ON" if walking else "WALK STATE: OFF")
				
		if Input.is_action_pressed("sprint"):
			running = true
			if walking:
				walking = false
				print("WALK STATE: OFF --> SPRINTING")
			
		if Input.is_action_just_released("sprint"):
			running = false
			
		# Determine movement speed based on state
		if walking:
			running = false
		elif running and !is_locked:
			if stamina > 0:
				running = true
				walking = false
				if Input.get_vector("move_left", "move_right", "move_forward", "move_backward"):
					decrease_stamina(stamina_reduction_rate * delta)  # Decrease stamina while sprinting
					print("SPRINTING [Stamina = %d]" % stamina)
			else:
				running = false
		else:
			running = false
			walking = false
		
		# Set movement speed based on state
		SPEED = running_speed if running else walking_speed if walking else normal_speed

	# Get the input direction and handle movement
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		if !running:
			if animation_player.current_animation != "walking":
				if walking:
					animation_player.advance(delta / 2)
				#animation_player.play("walking")
				set_animation("walking")
		else:	
			if animation_player.current_animation != "running":
				#animation_player.play("running")
				set_animation("running")
		
		if !is_locked:
			visuals.look_at(position + direction)  # Run in the direction the character is facing
		
		velocity.x = -direction.x * SPEED
		velocity.z = -direction.z * SPEED
	else:
		if !is_locked and animation_player.current_animation != "idle":
			animation_player.play("idle")
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		
	if velocity.x == 0 and velocity.y == 0 and is_locked:
		animation_player.play("idle")
	
	# Move the character
	move_and_slide()  # Move the character based on velocity

func set_animation(animation_name):
	var ticks_msec = Time.get_ticks_msec();
	if last_animation != animation_name:
		animation_player.play(animation_name)
		animation_player.stop()
		last_animation = animation_name
		animation_position = 0.0
		time_accumulator = 0.0
	elif time_accumulator>= FRAME_TIME:
		animation_position += time_accumulator
		animation_player.seek(animation_position,true)
		animation_player.stop(true)
		print(float(ticks_msec%int(FRAME_TIME * 1000))/1000);
		time_accumulator += float(ticks_msec%int(FRAME_TIME * 1000))/1000;
	
