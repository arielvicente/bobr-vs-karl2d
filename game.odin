package game

import hm "core:container/handle_map"
import "core:fmt"
import "core:math/linalg"
import k2 "karl2d"

v2 :: k2.Vec2

camera: k2.Camera

TILE_SIDE_IN_PIXELS: i32 : 16
TILE_SIDE_IN_METERS: f32 : 1
METERS_TO_PIXELS: f32 : f32(TILE_SIDE_IN_PIXELS) / TILE_SIDE_IN_METERS
PIXELS_TO_METERS: f32 : TILE_SIDE_IN_METERS / f32(TILE_SIDE_IN_PIXELS)

Handle :: hm.Handle32

E_Type :: enum {
	None,
	Player,
}

Entity :: struct {
	handle: Handle,
	type:   E_Type,
	pos:    v2,
	vel:	v2,
}

MAX_ENTITIES :: 256
entities: hm.Static_Handle_Map(MAX_ENTITIES, Entity, Handle)

player_handle: Handle

bobr_tex: k2.Texture

main :: proc() {
	init()
	for step() {}
	shutdown()
}

init :: proc() {
	//.Windowed
	//.Borderless_Fullscreen
	k2.init(600, 480, "bobr", options = {window_mode = .Windowed})

	bobr_tex = k2.load_texture_from_bytes(#load("data/sprites/bobr.png"))

	player_handle = hm.add(&entities, Entity{type = .Player})
	player := hm.get(&entities, player_handle)

	camera = k2.Camera {
		zoom = 1,
	}
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}
	if k2.key_went_down(.Escape) {
		return false
	}

	dt := k2.get_frame_time()
	player := hm.get(&entities, player_handle)
	half_side := f32(TILE_SIDE_IN_PIXELS / 2)

	ai: {
	}

	input: {
		player.pos += input_direction()
	}

	physics: {
		entities_it := hm.iterator_make(&entities)
		for entity, handle in hm.iterate(&entities_it) {
			assert(hm.is_valid(entities, handle))
			entity.vel += { 0, 1 * dt}
			entity.pos += entity.vel
		}
	}

	render: {
		k2.clear(k2.BLACK)
		camera.target = player.pos + {-600 / 2, -480 / 2}
		k2.set_camera(camera)
		k2.draw_text("bobr", {-128, -128}, 64, k2.WHITE)

		bobr_r := k2.get_texture_rect(bobr_tex)
		k2.draw_texture_rect(bobr_tex, bobr_r, player.pos, half_side, 0)

		k2.present()
	}

	return true
}

input_direction :: proc() -> v2 {
	dir: v2
	if k2.key_is_held(.W) || k2.key_is_held(.Up) || k2.gamepad_button_is_held(0, .Left_Face_Up) {
		dir.y = -1
	}
	if k2.key_is_held(.S) ||
	   k2.key_is_held(.Down) ||
	   k2.gamepad_button_is_held(0, .Left_Face_Down) {
		dir.y = 1
	}
	if k2.key_is_held(.A) ||
	   k2.key_is_held(.Left) ||
	   k2.gamepad_button_is_held(0, .Left_Face_Left) {
		dir.x = -1
	}
	if k2.key_is_held(.D) ||
	   k2.key_is_held(.Right) ||
	   k2.gamepad_button_is_held(0, .Left_Face_Right) {
		dir.x = 1
	}

	return linalg.normalize0(dir)
}

shutdown :: proc() {
	k2.shutdown()
}
