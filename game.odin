package game

import hm "core:container/handle_map"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import k2 "karl2d"
import particles "particles"

v2 :: k2.Vec2

camera: k2.Camera

WINDOW_SIZE: v2 : {600, 480}
CAMERA_ZOOM: f32 : 2

edit_mode: bool
editor_camera_target: v2

TILE_SIDE_IN_PIXELS: i32 : 16
TILE_SIDE_IN_METERS: f32 : 1
METERS_TO_PIXELS: f32 : f32(TILE_SIDE_IN_PIXELS) / TILE_SIDE_IN_METERS
PIXELS_TO_METERS: f32 : TILE_SIDE_IN_METERS / f32(TILE_SIDE_IN_PIXELS)

Sprite_Name :: enum u32 {
	none,
	bobr,
	ground,
	door,
}

Sprite :: struct {
	tex:    k2.Texture,
	w, h:   f32,
	frames: f32,
}

sprites: [Sprite_Name]Sprite

E_Type :: enum {
	None,
	Player,
	Ground,
	Pickup,
	Door_Entry,
	Door_Exit,
}

Editor_Tile :: enum {
	Ground,
	Entry_Door,
	Exit_Door,
}

E_Flag :: enum u16 {
	None,
	Dynamic,
	Static,
	Pickup,
}

COYOTE_TIME_FRAMES: u8 : 5
E_Grounded :: struct {
	coyote_frame_timer: u8,
	has_left_ground:    bool,
}
E_Airborne :: struct {
	used_jumps: int,
}

E_State :: union {
	E_Grounded,
	E_Airborne,
}

Entity :: struct {
	handle:      Handle,
	type:        E_Type,
	flags:       bit_set[E_Flag],
	state:       E_State,
	pos:         v2,
	vel:         v2,
	speed:       f32,
	is_grounded: bool,
	used_jumps:  int,
	max_jumps:   int,
}

MAX_ENTITIES :: 256
TEMPORAL_FRAME_BUFFER_LENGHT :: 300
TEMPORAL_BUFFER_DELAY :: 300

Handle :: hm.Handle32

Game_Memory :: struct {
	game_running:           bool,
	sprites:                [Sprite_Name]Sprite,
	entities:               hm.Static_Handle_Map(MAX_ENTITIES, Entity, Handle),
	player_handle:          Handle,
	level_timer_seconds:	f32,
	temporal_positions:     [TEMPORAL_FRAME_BUFFER_LENGHT]v2,
	temporal_index:         int,
	temporal_index_highest: int,
	temporal_counter:       f32,
	is_game_over:			bool,
	game_over_timer:		f32,
	selected_tile:			Editor_Tile,
}

g: ^Game_Memory


LEVEL_1_PATH :: "data/levels/level_1.json"

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
	defer {
		if len(track.allocation_map) > 0 {
			fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
			for _, entry in track.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&track)
	}

	g = new(Game_Memory)
	defer free(g)

	init()
	for step() {}
	shutdown()

}

init :: proc() {
	//.Windowed
	//.Windowed_Resizable
	//.Borderless_Fullscreen
	k2.init(int(WINDOW_SIZE.x), int(WINDOW_SIZE.y), "bobr", options = {window_mode = .Windowed})

	editor_init()

	particles.init(k2.draw_circle)

	init_sprite_data()
	init_game_state()

	camera = k2.Camera {
		zoom = CAMERA_ZOOM,
	}
}

init_sprite_data :: proc() {
	g.sprites[.bobr].tex = k2.load_texture_from_bytes(#load("data/sprites/bobr.png"))
	g.sprites[.bobr].w = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.bobr].h = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.bobr].frames = 2
	g.sprites[.ground].tex = k2.load_texture_from_bytes(#load("data/sprites/ground.png"))
	g.sprites[.ground].w = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.ground].h = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.ground].frames = 1
	g.sprites[.door].tex = k2.load_texture_from_bytes(#load("data/sprites/door.png"))
	g.sprites[.door].w = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.door].h = f32(TILE_SIDE_IN_PIXELS * 2)
	g.sprites[.door].frames = 1
}

init_game_state :: proc() {

	g.is_game_over = false
	g.level_timer_seconds = 10.0
	g.temporal_index = 0
	g.temporal_index_highest = 0
	g.temporal_counter = 0
	g.game_over_timer = 1.33

	hm.clear(&g.entities)

	g.player_handle = hm.add(&g.entities, Entity{type = .Player, flags = {.Dynamic}, speed = 5, state = E_Airborne{}})

	_ = hm.add(&g.entities, Entity{type = .Pickup, flags = {.Pickup}, pos = {3, -2}})

	level_1_data := #load(LEVEL_1_PATH)
	level_entities := make([dynamic]Entity)
	defer delete(level_entities)
	if json.unmarshal(level_1_data, &level_entities, allocator = context.temp_allocator) != nil {
		fmt.print("level failed to load:", LEVEL_1_PATH)
	}

	for e in level_entities {
		_ = hm.add(&g.entities, e)
	}
}

editor_save_entities_to_file :: proc(level_name: string) {

	level_entities := make([dynamic]Entity)
	defer delete(level_entities)

	entities_it := hm.iterator_make(&g.entities)
	for e, handle in hm.iterate(&entities_it) {

		if e.type == .Player {
			continue
		}

		append(&level_entities, e^)
	}

	//level_name_with_ending := fmt.tprint("data/levels/", level_name, "", ".json", sep = "")
	if level_data, error := json.marshal(level_entities, allocator = context.temp_allocator); error == nil {
		fmt.print("write file to:", LEVEL_1_PATH)
		err := os.write_entire_file(LEVEL_1_PATH, level_data)
	} else {
		fmt.print(error)
	}
}

step :: proc() -> bool {
	free_all(context.temp_allocator)

	if !k2.update() {
		return false
	}
	if k2.key_went_down(.Escape) {
		return false
	}

	dt := k2.get_frame_time()

	game_over: {
		if g.is_game_over {
			k2.clear(k2.BLACK)
			k2.set_camera(nil) // Ensure we draw in screen space

			text := "GAME BOBER :(\nPress (almost) any key to Restart"
			// Center the text roughly on screen
			text_pos := v2{WINDOW_SIZE.x / 2 - 180, WINDOW_SIZE.y / 2}
			k2.draw_text(text, text_pos, 32, k2.WHITE)
			k2.present()

			if g.game_over_timer > 0 {
				g.game_over_timer -= dt;
				return true
			}

			// Wait for input to restart
			if k2.key_went_down(.Space) ||
			k2.gamepad_button_went_down(0, .Right_Face_Up) ||
			k2.gamepad_button_went_down(0, .Right_Face_Down) ||
			k2.gamepad_button_went_down(0, .Right_Face_Left) ||
			k2.gamepad_button_went_down(0, .Right_Face_Right) ||
			k2.gamepad_button_went_down(0, .Middle_Face_Left) ||
			k2.gamepad_button_went_down(0, .Middle_Face_Middle) ||
			k2.gamepad_button_went_down(0, .Middle_Face_Right) {
				init_game_state()
			}

			return true
		}
	}



	if k2.key_went_down(.E) {
		edit_mode = !edit_mode

		if edit_mode do g.level_timer_seconds += 30.0
	}

	player := hm.get(&g.entities, g.player_handle)
	player.max_jumps = 2
	half_side := TILE_SIDE_IN_METERS / 2

	if !edit_mode && g.level_timer_seconds > 0 {
		g.level_timer_seconds -= dt
		if g.level_timer_seconds < 0 {
			g.level_timer_seconds = 0
			g.is_game_over = true
		}
	}


	temporal_buffering: {
		if g.temporal_counter < TEMPORAL_BUFFER_DELAY {
			g.temporal_counter += 1
		}

		// Do temporal buffering // NOTE: TENET
		g.temporal_positions[g.temporal_index] = player.pos
		g.temporal_index += 1
		if g.temporal_index == TEMPORAL_FRAME_BUFFER_LENGHT {
			g.temporal_index = 0
		}

		if g.temporal_index_highest < TEMPORAL_FRAME_BUFFER_LENGHT - 1 {
			g.temporal_index_highest += 1
		}

	}


	ai: {
		switch &s in player.state {
		case E_Grounded:
			if s.has_left_ground {
				s.coyote_frame_timer += 1
				fmt.println("coyote frame:", s.coyote_frame_timer)
				if s.coyote_frame_timer >= COYOTE_TIME_FRAMES {
					player.state = E_Airborne {
						used_jumps = 0,
					}
					fmt.println("set state to", player.state)
				}
			}
		case E_Airborne:
		}
	}

	input: {

		if edit_mode {

			editor_input()

			if k2.mouse_button_is_held(.Right) {
				editor_camera_target -= k2.get_mouse_delta()
			}
			if k2.mouse_button_went_down(.Left) {
				if k2.key_is_held(.D) {
					pos := get_snapped_mouse_pos()

					entities_it := hm.iterator_make(&g.entities)
					remove_check: for entity, handle in hm.iterate(&entities_it) {
						if !(.Static in entity.flags) {
							continue
						}

						rect: k2.Rect
						rect.w = TILE_SIDE_IN_METERS
						rect.h = TILE_SIDE_IN_METERS
						rect.x = entity.pos.x
						rect.y = entity.pos.y
						hit := k2.point_in_rect(pos, rect)
						if hit {
							hm.remove(&g.entities, handle)
							break remove_check
						}
					}
				} else {
					pos := get_snapped_mouse_pos()
					add_tile(pos)
				}
			}
			if k2.key_went_down(.S) {
				editor_save_entities_to_file(LEVEL_1_PATH)
			}
		}

		JUMP_FORCE: f32 : 20
		AIR_TURN_MODIFIER: f32 : 0.75
		if player.is_grounded {
			player.vel += input_direction()
		} else {
			player.vel += input_direction() * AIR_TURN_MODIFIER
		}
		if input_jump() { 	// TODO: hold to jump higher?
			if player.used_jumps < player.max_jumps {
				player.vel.y = -JUMP_FORCE
				player.used_jumps += 1
				particles.spawn_particle_ring(player.pos * METERS_TO_PIXELS)
			}
		}

		if input_temporal_return() {
			t_index: int
			if g.temporal_index_highest == TEMPORAL_FRAME_BUFFER_LENGHT - 1 {
				// NOTE: temporal buffer has or should loop
				// NOTE: return index is temporal_index + 1 unless temporal_index is == TEMPORAL_FRAME_BUFFER_LENGHT in which case return index is 0
				if g.temporal_index == TEMPORAL_FRAME_BUFFER_LENGHT {
					t_index = 0
				} else {
					t_index = g.temporal_index + 1
				}
			} else {
				// NOTE: temporal buffer is not full, return index is always 0
				t_index = 0
			}

			player.pos = g.temporal_positions[t_index]
		}
	}

	physics: {
		JUMP_GRAVITY: f32 : 9.8 * 0.8
		FALL_GRAVITY: f32 : 9.8
		TERMINAL_VELOCITY: f32 : 30
		FRICTION: f32 : 0.75

		player.vel.x *= FRICTION

		if player.vel.y < 0 {
			player.vel.y += JUMP_GRAVITY * JUMP_GRAVITY * dt
		} else {
			player.vel.y += FALL_GRAVITY * FALL_GRAVITY * dt
		}

		player.vel.y = math.min(player.vel.y, TERMINAL_VELOCITY)

		//
		// X AXIS
		//
		player.pos.x += player.vel.x * player.speed * dt

		player_rect: k2.Rect
		player_rect.w = TILE_SIDE_IN_METERS
		player_rect.h = TILE_SIDE_IN_METERS
		player_rect.x = player.pos.x
		player_rect.y = player.pos.y

		entities_it := hm.iterator_make(&g.entities)
		for entity, handle in hm.iterate(&entities_it) {
			assert(hm.is_valid(g.entities, handle))

			if !(.Static in entity.flags) {
				continue
			}

			ground_rect: k2.Rect
			ground_rect.w = TILE_SIDE_IN_METERS
			ground_rect.h = TILE_SIDE_IN_METERS
			ground_rect.x = entity.pos.x
			ground_rect.y = entity.pos.y

			overlap_rect, collided := k2.rect_overlap(player_rect, ground_rect)
			if !collided {
				continue
			}

			if player.vel.x > 0 {
				// Moving right into wall
				player.pos.x -= overlap_rect.w
			} else if player.vel.x < 0 {
				// Moving left into wall
				player.pos.x += overlap_rect.w
			}

			player.vel.x = 0
			player_rect.x = player.pos.x
		}

		//
		// Y AXIS
		//
		player.pos.y += player.vel.y * dt
		player_rect.y = player.pos.y

		had_ground_collision: bool = false

		entities_it = hm.iterator_make(&g.entities)
		for entity, handle in hm.iterate(&entities_it) {
			assert(hm.is_valid(g.entities, handle))

			if !(.Static in entity.flags) {
				continue
			}

			ground_rect: k2.Rect
			ground_rect.w = TILE_SIDE_IN_METERS
			ground_rect.h = TILE_SIDE_IN_METERS
			ground_rect.x = entity.pos.x
			ground_rect.y = entity.pos.y

			overlap_rect, collided := k2.rect_overlap(player_rect, ground_rect)
			if !collided {
				continue
			}

			if player.vel.y > 0 {
				// Falling onto ground
				player.pos.y -= overlap_rect.h
				player.vel.y = 0
				if _, ok := player.state.(E_Airborne); ok {
					player.state = E_Grounded{}
					fmt.println("set state to", player.state)
					particles.spawn_particle_ring(player.pos * METERS_TO_PIXELS)
				}
				had_ground_collision = true
				//player.is_grounded = true
				player.used_jumps = 0
			} else if player.vel.y < 0 {
				// Hitting ceiling
				player.pos.y += overlap_rect.h
				player.vel.y = 0
			}

			player_rect.y = player.pos.y
		}

		if !had_ground_collision {
			if grounded_state, ok := player.state.(E_Grounded); ok {
				grounded_state.has_left_ground = true
				player.state = grounded_state
			}
		}

		pickup_collision: {
			pickup_it := hm.iterator_make(&g.entities)
			for entity, handle in hm.iterate(&pickup_it) {
				if !(.Pickup in entity.flags) {
					continue
				}

				pickup_rect: k2.Rect
				pickup_rect.w = TILE_SIDE_IN_METERS
				pickup_rect.h = TILE_SIDE_IN_METERS
				pickup_rect.x = entity.pos.x
				pickup_rect.y = entity.pos.y

				_, collided := k2.rect_overlap(player_rect, pickup_rect)
				if collided {
					g.level_timer_seconds += 5.0
					hm.remove(&g.entities, handle)

					break
				}
			}
		}

	}

	if edit_mode {
		editor_process_frame()
	}

	render: {
		k2.clear(k2.BLACK)

		if edit_mode {
			camera.target = editor_camera_target
		} else {
			camera.target =
				player.pos * METERS_TO_PIXELS + {-WINDOW_SIZE.x / (CAMERA_ZOOM * 2), -WINDOW_SIZE.y / (CAMERA_ZOOM * 2)}
			editor_camera_target = camera.target
		}

		k2.set_camera(camera)

		k2.draw_text(fmt.tprint("edit_mode:", edit_mode), {-128, -32}, 32, k2.WHITE)
		k2.draw_text(
			"E to toggle edit,\nMouse_Left to place tile,\nMouse_Right hold to move,\nS to save",
			{-128, 86},
			24,
			k2.WHITE,
		)
		//k2.draw_text(fmt.tprintf("%.2f", player.vel), {-128, -128}, 64, k2.WHITE)

		render_geometry: {
			entities_it := hm.iterator_make(&g.entities)
			for entity, handle in hm.iterate(&entities_it) {

				assert(hm.is_valid(g.entities, handle))

				#partial switch entity.type {
				case .Ground:
					draw_sprite(.ground, entity.pos)

				case .Door_Entry:
					draw_sprite(.door, entity.pos, tint = k2.BLUE)

				case .Door_Exit:
					draw_sprite(.door, entity.pos, tint = k2.MAGENTA)

				case .Pickup:
					pixel_pos := entity.pos * METERS_TO_PIXELS

					pickup_rect := k2.Rect{
						x = pixel_pos.x - (f32(TILE_SIDE_IN_PIXELS) / 2),
						y = pixel_pos.y - (f32(TILE_SIDE_IN_PIXELS) / 2),
						w = f32(TILE_SIDE_IN_PIXELS),
						h = f32(TILE_SIDE_IN_PIXELS),
					}

					k2.draw_rect(pickup_rect, k2.GREEN)
				}
			}
		}

		render_player: {
			@(static) animation_frame: f32 = 0
			@(static) animation_timer: f32 = 0
			animation_fps: f32 : 1.0 / 12.0 // NOTE: 12 fps

			if math.abs(player.vel.x) > 0.1 {
				animation_timer += dt
			}
			if animation_timer >= animation_fps {
				animation_timer = 0

				animation_frame += 1
				if animation_frame >= g.sprites[.bobr].frames do animation_frame = 0
			}

			is_moving_right := player.vel.x > 0
			draw_sprite(.bobr, player.pos, animation_frame, is_moving_right)

			// render_temporal_ghost
			t_index: int
			if g.temporal_index_highest == TEMPORAL_FRAME_BUFFER_LENGHT - 1 {
			// NOTE: temporal buffer has or should loop
			// NOTE: return index is temporal_index + 1 unless temporal_index is == TEMPORAL_FRAME_BUFFER_LENGHT in which case return index is 0
				if g.temporal_index == TEMPORAL_FRAME_BUFFER_LENGHT - 1 {
					t_index = 0
				} else {
					t_index = g.temporal_index + 1
				}
			} else {
			// NOTE: temporal buffer is not full, return index is always 0
				t_index = 0
			}

			draw_sprite(.bobr, g.temporal_positions[t_index], animation_frame, is_moving_right, k2.LIGHT_GREEN)
		}


		if edit_mode {
			preview_pos := get_snapped_mouse_pos()

			preview_sprite: Sprite_Name
			tint_color: k2.Color

			switch g.selected_tile {
			case .Ground:
				preview_sprite = .ground
				tint_color = k2.WHITE
			case .Entry_Door:
				preview_sprite = .door
				tint_color = k2.BLUE
			case .Exit_Door:
				preview_sprite = .door
				tint_color = k2.MAGENTA
			}

			tint_color.a = 128
			draw_sprite(preview_sprite, preview_pos, 0, false, tint_color)
		}

		particles.update(dt)

		k2.set_camera(nil)

		hud: {
			seconds := int(g.level_timer_seconds)
			hundredths := int((g.level_timer_seconds - f32(seconds)) * 100)
			countdown_text := fmt.tprintf("%02d:%02d", seconds, hundredths)
			font_size: f32 = 24
			text_pos := v2{ WINDOW_SIZE.x - 70, 16 }
			k2.draw_text(countdown_text, text_pos, font_size, k2.WHITE)
		}

		if edit_mode {
			editor_render()
		}

		k2.present()
	}

	return true
}

draw_sprite :: proc(name: Sprite_Name, pos: v2, frame: f32 = 0, flip_x: bool = false, tint: k2.Color = k2.WHITE) {

	sprite := &g.sprites[name]
	rect := k2.get_texture_rect(sprite.tex)

	frame_width := rect.w / sprite.frames
	rect.w = frame_width
	rect.x = frame_width * math.floor(frame)

	if flip_x {
		rect.w *= -1
	}

	pixel_pos := pos * METERS_TO_PIXELS
	offset := (TILE_SIDE_IN_METERS / 2) * METERS_TO_PIXELS

	k2.draw_texture_rect(sprite.tex, rect, pixel_pos, offset, 0, tint)
}

get_snapped_mouse_pos :: proc() -> v2 {
	pos := camera.target * PIXELS_TO_METERS
	pos += (k2.get_mouse_position() / 2) * PIXELS_TO_METERS
	pos.x = math.floor(pos.x + 0.5)
	pos.y = math.floor(pos.y + 0.5)
	return pos
}

add_tile :: proc(pos: v2) {
	switch g.selected_tile {
	case .Ground:
		_ = hm.add(&g.entities, Entity{pos = pos, type = .Ground, flags = {.Static}})

	case .Entry_Door:
		entities_it := hm.iterator_make(&g.entities)
		for entity, handle in hm.iterate(&entities_it) {
			if entity.type == .Door_Entry {
				hm.remove(&g.entities, handle)
				break
			}
		}
		_ = hm.add(&g.entities, Entity{pos = pos, type = .Door_Entry, flags = {.Static}})

	case .Exit_Door:
	// Remove existing Exit Door so there's only ever 1
		entities_it := hm.iterator_make(&g.entities)
		for entity, handle in hm.iterate(&entities_it) {
			if entity.type == .Door_Exit {
				hm.remove(&g.entities, handle)
				break
			}
		}
		_ = hm.add(&g.entities, Entity{pos = pos, type = .Door_Exit, flags = {.Static}})
	}
}

input_direction :: proc() -> v2 {
	dir: v2

	x_axis := k2.get_gamepad_axis(0, .Left_Stick_X)

	if x_axis < -0.1 || x_axis > 0.1
	{
		dir.x = x_axis
	}

	if input_any_of_keys_are_held({.A, .Left}) || k2.gamepad_button_is_held(0, .Left_Face_Left){
		dir.x = -1
	}

	if input_any_of_keys_are_held({.D, .Right}) || k2.gamepad_button_is_held(0, .Left_Face_Right) {
		dir.x = 1
	}

	return linalg.normalize0(dir)
}

input_jump :: proc() -> bool {
	result := k2.key_went_down(.Space) || k2.gamepad_button_went_down(0, .Right_Face_Down)
	return result
}

input_temporal_return :: proc() -> bool {
	result := k2.key_went_down(.R) || k2.gamepad_button_went_down(0, .Right_Face_Up)
	return result
}

input_any_of_keys_are_held :: proc(keys : []k2.Keyboard_Key) -> bool {
	for i in 0 ..<len(keys) {
		key := keys[i]

		if k2.key_is_held(key) do return true
	}

	return false
}

input_any_of_buttons_are_held :: proc(buttons : []k2.Gamepad_Button) -> bool {
	for i in 0 ..<len(buttons) {
		button := buttons[i]

		if k2.gamepad_button_is_held(0, button) do return true
	}

	return false
}


shutdown :: proc() {
	editor_destroy()
	particles.dispose()
	k2.shutdown()
}
