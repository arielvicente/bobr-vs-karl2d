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
}

E_Flag :: enum u16 {
	None,
	Dynamic,
	Static,
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

	g.level_timer_seconds = 10.0

	g.temporal_index = 0

	g.sprites[.bobr].tex = k2.load_texture_from_bytes(#load("data/sprites/bobr.png"))
	g.sprites[.bobr].w = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.bobr].h = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.bobr].frames = 2
	g.sprites[.ground].tex = k2.load_texture_from_bytes(#load("data/sprites/ground.png"))
	g.sprites[.ground].w = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.ground].h = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.ground].frames = 1

	g.player_handle = hm.add(&g.entities, Entity{type = .Player, flags = {.Dynamic}, speed = 5, state = E_Airborne{}})
	fmt.println(hm.get(&g.entities, g.player_handle).state)

	level_1_data := #load(LEVEL_1_PATH)
	level_entities := make([dynamic]Entity)
	defer delete(level_entities)
	if json.unmarshal(level_1_data, &level_entities, allocator = context.temp_allocator) != nil {
		fmt.print("level failed to load:", LEVEL_1_PATH)
	}

	for e in level_entities {
		_ = hm.add(&g.entities, e)
	}

	camera = k2.Camera {
		zoom = CAMERA_ZOOM,
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
	if k2.key_went_down(.E) {
		edit_mode = !edit_mode
	}

	dt := k2.get_frame_time()
	player := hm.get(&g.entities, g.player_handle)
	player.max_jumps = 2
	half_side := TILE_SIDE_IN_METERS / 2

	if g.level_timer_seconds > 0 {
		g.level_timer_seconds -= dt
		if g.level_timer_seconds < 0 {
			g.level_timer_seconds = 0
			// Game over
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
		}

		if edit_mode {
			if k2.mouse_button_is_held(.Right) {
				editor_camera_target -= k2.get_mouse_delta()
			}
			if k2.mouse_button_went_down(.Left) {
				if k2.key_is_held(.D) {
					pos := camera.target * PIXELS_TO_METERS
					pos += (k2.get_mouse_position() / 2) * PIXELS_TO_METERS
					pos.x = math.floor(pos.x + 0.5)
					pos.y = math.floor(pos.y + 0.5)

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
					pos := camera.target * PIXELS_TO_METERS
					pos += (k2.get_mouse_position() / 2) * PIXELS_TO_METERS
					pos.x = math.floor(pos.x + 0.5)
					pos.y = math.floor(pos.y + 0.5)
					_ = hm.add(&g.entities, Entity{pos = pos, type = .Ground, flags = {.Static}})
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

		if input_temporal_return() { 	// TODO: hold to jump higher?
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
		bobr_r := k2.get_texture_rect(g.sprites[.bobr].tex)

		bobr_r.x = 16 * animation_frame // NOTE: 16 is the witdt of one frame
		bobr_r.w = bobr_r.w / g.sprites[.bobr].frames

		if player.vel.x > 0 {
			bobr_r.w *= -1
		}

		k2.draw_texture_rect(g.sprites[.bobr].tex, bobr_r, player.pos * METERS_TO_PIXELS, half_side * METERS_TO_PIXELS, 0)

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

		k2.draw_texture_rect(
			g.sprites[.bobr].tex,
			bobr_r,
			g.temporal_positions[t_index] * METERS_TO_PIXELS,
			half_side * METERS_TO_PIXELS,
			0,
			k2.LIGHT_GREEN,
		)

		ground_r := k2.get_texture_rect(g.sprites[.ground].tex)
		entities_it := hm.iterator_make(&g.entities)
		for entity, handle in hm.iterate(&entities_it) {
			assert(hm.is_valid(g.entities, handle))
			if entity.type == .Ground {
				k2.draw_texture_rect(
					g.sprites[.ground].tex,
					ground_r,
					entity.pos * METERS_TO_PIXELS,
					half_side * METERS_TO_PIXELS,
					0,
				)
			}
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

input_direction :: proc() -> v2 {
	dir: v2
	if k2.key_is_held(.W) || k2.key_is_held(.Up) || k2.gamepad_button_is_held(0, .Left_Face_Up) {
		dir.y = -1
	}
	if k2.key_is_held(.S) || k2.key_is_held(.Down) || k2.gamepad_button_is_held(0, .Left_Face_Down) {
		dir.y = 1
	}
	if k2.key_is_held(.A) || k2.key_is_held(.Left) || k2.gamepad_button_is_held(0, .Left_Face_Left) {
		dir.x = -1
	}
	if k2.key_is_held(.D) || k2.key_is_held(.Right) || k2.gamepad_button_is_held(0, .Left_Face_Right) {
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

shutdown :: proc() {
	editor_destroy()
	particles.dispose()
	k2.shutdown()
}
