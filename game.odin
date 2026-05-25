package game

import hm "core:container/handle_map"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import k2 "karl2d"

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

Sprite_Name :: enum {
	bobr,
	ground,
}

Sprite :: struct {
	tex:  k2.Texture,
	w, h: f32,
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

Entity :: struct {
	handle:      Handle,
	type:        E_Type,
	flags:       bit_set[E_Flag],
	pos:         v2,
	vel:         v2,
	speed:       f32,
	is_grounded: bool,
	used_jumps:  int,
	max_jumps:   int,
}

MAX_ENTITIES :: 256

Handle :: hm.Handle32

Game_Memory :: struct {
	game_running:  bool,
	sprites:       [Sprite_Name]Sprite,
	entities:      hm.Static_Handle_Map(MAX_ENTITIES, Entity, Handle),
	player_handle: Handle,
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

	g.sprites[.bobr].tex = k2.load_texture_from_bytes(#load("data/sprites/bobr.png"))
	g.sprites[.bobr].w = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.bobr].h = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.ground].tex = k2.load_texture_from_bytes(#load("data/sprites/ground.png"))
	g.sprites[.ground].w = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.ground].h = f32(TILE_SIDE_IN_PIXELS)

	g.player_handle = hm.add(&g.entities, Entity{type = .Player, flags = {.Dynamic}, speed = 5})

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

	ai: {
	}

	input: {
		if edit_mode {
			if k2.mouse_button_is_held(.Right) {
				editor_camera_target -= k2.get_mouse_delta()
			}
			if k2.mouse_button_went_down(.Left) {
				pos := camera.target * PIXELS_TO_METERS
				pos += (k2.get_mouse_position() / 2) * PIXELS_TO_METERS
				pos.x = math.floor(pos.x + 0.5)
				pos.y = math.floor(pos.y + 0.5)
				_ = hm.add(&g.entities, Entity{pos = pos, type = .Ground, flags = {.Static}})
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
			}
		}
	}

	physics: {
		JUMP_GRAVITY: f32 : 9.8 * 0.8
		FALL_GRAVITY: f32 : 9.8
		TERMINAL_VELOCITY: f32 : 30
		FRICTION: f32 : 0.75

		//if player.is_grounded {
		// TODO: remove friction and just use a max speed?
		player.vel.x *= FRICTION
		//}
		if player.vel.y < 0 {
			player.vel.y += JUMP_GRAVITY * JUMP_GRAVITY * dt
		} else {
			player.vel.y += FALL_GRAVITY * FALL_GRAVITY * dt
		}
		player.vel.y = math.min(player.vel.y, TERMINAL_VELOCITY)
		// TODO: needs to take the sign/direction into account
		//player.vel.x = math.min(player.vel.x, player.max_speed)
		player.pos.x += player.vel.x * player.speed * dt
		player.pos.y += player.vel.y * dt

		player_rect: k2.Rect
		player_rect.w = TILE_SIDE_IN_METERS
		player_rect.h = TILE_SIDE_IN_METERS
		player_rect.x = player.pos.x
		player_rect.y = player.pos.y

		player.is_grounded = false

		entities_it := hm.iterator_make(&g.entities)
		ground_check: for entity, handle in hm.iterate(&entities_it) {
			assert(hm.is_valid(g.entities, handle))

			if .Static in entity.flags {
				ground_rect: k2.Rect
				ground_rect.w = TILE_SIDE_IN_METERS
				ground_rect.h = TILE_SIDE_IN_METERS
				ground_rect.x = entity.pos.x
				ground_rect.y = entity.pos.y

				/*
				** TODO: for every collision, add a collision object to a collission array
				** and handle collision response in a separate loop :)
				*/

				overlap_rect, collided := k2.rect_overlap(player_rect, ground_rect)
				if !collided {
					continue
				}


				// Overlap is wider than it is tall
				if overlap_rect.h < overlap_rect.w {
					// Player is above ground
					if player.pos.y < entity.pos.y {
						// Push player up, mark as grounded, prevent player from moving down through ground
						player.pos.y -= overlap_rect.h
						player.is_grounded = true
						player.used_jumps = 0
						player.vel.y = math.min(0, player.vel.y)
						// Player is below ground
					} else {
						// Push player down, prevent player from moving up through ground
						player.pos.y += overlap_rect.h
						player.vel.y = math.max(0, player.vel.y)
					}
					// Overlap is taller that it is wide
				} else {
					// Player is to the left of wall
					if player.pos.x < entity.pos.x {
						// Push player left
						player.pos.x -= overlap_rect.w
						// Player is to the right of wall
					} else {
						// Push player right
						player.pos.x += overlap_rect.w
					}
					// Prevent player from moving through walls
					player.vel.x = 0
				}

				player_rect.x = player.pos.x
				player_rect.y = player.pos.y
			}
		}
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
		@(static) animation_frames: f32 = 2
		@(static) animation_timer: f32 = 0
		animation_fps: f32 : 1.0 / 12.0 // NOTE: 12 fps

		animation_timer += dt
		if animation_timer >= animation_fps {
			animation_timer = 0

			animation_frame += 1
			if animation_frame >= animation_frames do animation_frame = 0
		}
		bobr_r := k2.get_texture_rect(g.sprites[.bobr].tex)

		bobr_r.x = 16 * animation_frame // NOTE: 16 is the witdt of one frame
		bobr_r.w = bobr_r.w / animation_frames

		if player.vel.x > 0 {
			bobr_r.w *= -1
		}

		k2.draw_texture_rect(g.sprites[.bobr].tex, bobr_r, player.pos * METERS_TO_PIXELS, half_side * METERS_TO_PIXELS, 0)


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

shutdown :: proc() {
	k2.shutdown()
}
