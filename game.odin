package game

import hm "core:container/handle_map"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import k2 "karl2d"

v2 :: k2.Vec2

camera: k2.Camera

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
	//.Borderless_Fullscreen
	k2.init(600, 480, "bobr", options = {window_mode = .Windowed})

	g.sprites[.bobr].tex = k2.load_texture_from_bytes(#load("data/sprites/bobr.png"))
	g.sprites[.bobr].w = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.bobr].h = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.ground].tex = k2.load_texture_from_bytes(#load("data/sprites/ground.png"))
	g.sprites[.ground].w = f32(TILE_SIDE_IN_PIXELS)
	g.sprites[.ground].h = f32(TILE_SIDE_IN_PIXELS)

	g.player_handle = hm.add(&g.entities, Entity{type = .Player, flags = {.Dynamic}, speed = 5})

	floor_tile_height: i32 = 1
	floor_tile_width: i32 = 600 / TILE_SIDE_IN_PIXELS * 2
	floor_offset: f32 = 5

	for y in 0 ..< floor_tile_height {
		for x in 0 ..< floor_tile_width {
			_ = hm.add(
				&g.entities,
				Entity{type = .Ground, pos = {f32(x) - floor_offset, f32(y) + floor_offset}, flags = {.Static}},
			)
		}
	}

	camera = k2.Camera {
		zoom = 1,
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
	player := hm.get(&g.entities, g.player_handle)
	half_side := TILE_SIDE_IN_METERS / 2

	ai: {
	}

	input: {
		JUMP_SPEED: f32 : 5
		if player.is_grounded {
			player.vel += input_direction()
		}
		if input_jump() {
			if player.is_grounded {
				player.vel.y -= JUMP_SPEED
			}
		}
	}

	physics: {
		GRAVITY: f32 : 9.8
		if player.is_grounded {
			player.vel.x *= 0.8 // friction
		}
		player.vel.y += GRAVITY * dt
		player.pos += player.vel * player.speed * dt

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
				if collided {
					if overlap_rect.h < overlap_rect.w {
						if player.pos.y < entity.pos.y {
							player.pos.y -= overlap_rect.h
							player.is_grounded = true
							player.vel.y = math.min(0, player.vel.y)
						} else {
							player.pos.y += overlap_rect.h
							player.vel.y = math.max(0, player.vel.y)
						}
					} else {
						if player.pos.x < entity.pos.x {
							player.pos.x -= overlap_rect.w
						} else {
							player.pos.x += overlap_rect.w
						}
						player.vel.x = 0

					}
					player_rect.x = player.pos.x
					player_rect.y = player.pos.y
				}
			}
		}
	}

	render: {
		k2.clear(k2.BLACK)
		camera.target = player.pos * METERS_TO_PIXELS + {-600 / 2, -480 / 2}
		k2.set_camera(camera)
		//k2.draw_text("bobr", {-128, -128}, 64, k2.WHITE)
		k2.draw_text(fmt.tprint(player.is_grounded), {-128, -128}, 64, k2.WHITE)
		//k2.draw_text(fmt.tprintf("%.2f", player.vel), {-128, -128}, 64, k2.WHITE)

		bobr_r := k2.get_texture_rect(g.sprites[.bobr].tex)
		ground_r := k2.get_texture_rect(g.sprites[.ground].tex)
		k2.draw_texture_rect(g.sprites[.bobr].tex, bobr_r, player.pos * METERS_TO_PIXELS, half_side * METERS_TO_PIXELS, 0)

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
