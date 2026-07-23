package game

import "core:fmt"
import k2 "karl2d"
import mu "microui"

FONT_HEIGHT :: 12
mu_ctx: ^mu.Context

editor_init :: proc() {
	mu_ctx = new(mu.Context)
	mu.init(mu_ctx)
	text_width :: #force_inline proc(font: mu.Font, text: string) -> i32 {
		return r_get_text_width(text)
	}
	text_height :: #force_inline proc(font: mu.Font) -> i32 {
		return r_get_text_height()
	}
	mu_ctx.text_width = text_width
	mu_ctx.text_height = text_height
}

editor_destroy :: proc() {
	free(mu_ctx)
}

mu_push_texture :: proc(ctx: ^mu.Context, texture: k2.Texture) {
	rect := mu.layout_next(ctx)

	// Add mu.Command_Texture, fill it out and then add it to the command queue in render
	//cmd := mu.push_command(mu_ctx, mu.Command_Variant, size_of(mu.Command_Variant))
}

editor_process_frame :: proc() {
	mu.begin(mu_ctx)
	//test_window(mu_ctx)
	rect: mu.Rect = {0, 0, 128, 128}
	if mu.begin_window(mu_ctx, "bobr", rect, {}) {
		mu.layout_row(mu_ctx, []i32{-1}, 0)
		//mu.label(mu_ctx, "kurwa")
		//rect_t: mu.Rect = {64, 64, 128, 128}
		//mu.draw_texture(mu_ctx, rect_t, mu.Id(Sprite_Name.bobr)) // TODO: make a copy of mu.button instead and call it texture_button or some shit
		//if mu.button(mu_ctx, "bbb") == {.SUBMIT} {
		if mu.texture_button(mu_ctx, mu.Id(Sprite_Name.bobr)) == {.SUBMIT} {
			fmt.print("BBB")
			//mu.open_popup(mu_ctx, "popu")
		}
		mu.end_window(mu_ctx)
	}
	mu.end(mu_ctx)
}

test_window :: proc(ctx: ^mu.Context) {
	@(static) opts: mu.Options

	button :: #force_inline proc(ctx: ^mu.Context, label: string) -> bool {return mu.button(ctx, label) == {.SUBMIT}}

	/* do window */
	if mu.begin_window(ctx, "Demo Window", {40, 40, 300, 450}, opts) {
		if mu.header(ctx, "Frame Stats") != {} {
			mu.layout_row(ctx, []i32{-1}, 0)
			mu.text(ctx, fmt.tprintf("FPS %v MSPF %v", 69, 0.16))
		}

		if mu.header(ctx, "Window Options") != {} {
			win := mu.get_current_container(ctx)
			mu.layout_row(ctx, []i32{120, 120, 120}, 0)
			for opt in mu.Opt {
				state: bool = opt in opts
				if mu.checkbox(ctx, fmt.tprintf("%v", opt), &state) != {} {
					if state {
						opts |= {opt}
					} else {
						opts &~= {opt}
					}
				}
			}
		}

		/* window info */
		if mu.header(ctx, "Window Info") != {} {
			win := mu.get_current_container(ctx)
			mu.layout_row(ctx, []i32{54, -1}, 0)
			mu.label(ctx, "Position:")
			mu.label(ctx, fmt.tprintf("%d, %d", win.rect.x, win.rect.y))
			mu.label(ctx, "Size:")
			mu.label(ctx, fmt.tprintf("%d, %d", win.rect.w, win.rect.h))
		}

		/* labels + buttons */
		if mu.header(ctx, "Test Buttons", {.EXPANDED}) != {} {
			mu.layout_row(ctx, []i32{86, -110, -1}, 0)
			mu.label(ctx, "Test buttons 1:")
			if button(ctx, "Button 1") do fmt.print("Pressed button 1")
			if button(ctx, "Button 2") do fmt.print("Pressed button 2")
			mu.label(ctx, "Test buttons 2:")
			if button(ctx, "Button 3") do fmt.print("Pressed button 3")
			if button(ctx, "Button 4") do fmt.print("Pressed button 4")
		}

		/* tree */
		if mu.header(ctx, "Tree and Text", {.EXPANDED}) != {} {
			mu.layout_row(ctx, []i32{140, -1}, 0)
			mu.layout_begin_column(ctx)
			if mu.begin_treenode(ctx, "Test 1") != {} {
				if mu.begin_treenode(ctx, "Test 1a") != {} {
					mu.label(ctx, "Hello")
					mu.label(ctx, "world")
					mu.end_treenode(ctx)
				}
				if mu.begin_treenode(ctx, "Test 1b") != {} {
					if button(ctx, "Button 1") do fmt.print("Pressed button 1")
					if button(ctx, "Button 2") do fmt.print("Pressed button 2")
					mu.end_treenode(ctx)
				}
				mu.end_treenode(ctx)
			}
			if mu.begin_treenode(ctx, "Test 2") != {} {
				mu.layout_row(ctx, []i32{54, 54}, 0)
				if button(ctx, "Button 3") do fmt.print("Pressed button 3")
				if button(ctx, "Button 4") do fmt.print("Pressed button 4")
				if button(ctx, "Button 5") do fmt.print("Pressed button 5")
				if button(ctx, "Button 6") do fmt.print("Pressed button 6")
				mu.end_treenode(ctx)
			}
			if mu.begin_treenode(ctx, "Test 3") != {} {
				@(static) checks := [3]bool{true, false, true}
				mu.checkbox(ctx, "Checkbox 1", &checks[0])
				mu.checkbox(ctx, "Checkbox 2", &checks[1])
				mu.checkbox(ctx, "Checkbox 3", &checks[2])
				mu.end_treenode(ctx)
			}
			mu.layout_end_column(ctx)

			mu.layout_begin_column(ctx)
			mu.layout_row(ctx, []i32{-1}, 0)
			mu.text(
				ctx,
				"Lorem ipsum\n dolor sit amet, consectetur adipiscing elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus ipsum, eu varius magna felis a nulla.",
			)
			mu.layout_end_column(ctx)
		}

		mu.end_window(ctx)
	}
}

editor_input :: proc() {
	mouse_move := k2.get_mouse_delta()
	mouse_pos := k2.get_mouse_position()
	mu.input_mouse_move(mu_ctx, i32(mouse_pos.x), i32(mouse_pos.y))

	if k2.mouse_button_went_down(.Left) {
		mu.input_mouse_down(mu_ctx, i32(mouse_pos.x), i32(mouse_pos.y), .LEFT)
	}
	if k2.mouse_button_went_down(.Right) {
		mu.input_mouse_down(mu_ctx, i32(mouse_pos.x), i32(mouse_pos.y), .RIGHT)
	}
	if k2.mouse_button_went_up(.Left) {
		mu.input_mouse_up(mu_ctx, i32(mouse_pos.x), i32(mouse_pos.y), .LEFT)
	}
	if k2.mouse_button_went_up(.Right) {
		mu.input_mouse_up(mu_ctx, i32(mouse_pos.x), i32(mouse_pos.y), .RIGHT)
	}
}

editor_render :: proc() {
	mu_command: ^mu.Command
	for mu.next_command(mu_ctx, &mu_command) {
		switch cmd in mu_command.variant {
		case ^mu.Command_Jump:
			unreachable() /* handled internally by next_command() */
		case ^mu.Command_Clip:
		//SDL_SetRenderClipRect, gl_scissor. how to make k2 do it, or is it even needed?
		case ^mu.Command_Rect:
			// NOTE: transmute(k2.Rect)(cmd.rect) does not work?
			rect: k2.Rect = {f32(cmd.rect.x), f32(cmd.rect.y), f32(cmd.rect.w), f32(cmd.rect.h)}
			k2.draw_rect(
				rect,
				transmute(k2.Color)cmd.color,
				//{f32(cmd.rect.x) - f32(cmd.rect.w) / 2, f32(cmd.rect.y) - f32(cmd.rect.h) / 2},
			)
		case ^mu.Command_Text:
			k2.draw_text(cmd.str, {f32(cmd.pos.x), f32(cmd.pos.y)}, FONT_HEIGHT, transmute(k2.Color)(cmd.color))
		case ^mu.Command_Icon:
			tex_r := k2.get_texture_rect(g.sprites[.ground].tex)
			tex_r.w /= 2
			k2.draw_texture_rect(g.sprites[.ground].tex, tex_r, {f32(cmd.rect.x), f32(cmd.rect.y)}, 8, 0)
		case ^mu.Command_Texture:
			tex_r := k2.get_texture_rect(g.sprites[Sprite_Name(cmd.id)].tex)
			//tex_r.w /= 2
			r: k2.Rect = {f32(cmd.rect.x), f32(cmd.rect.y), f32(cmd.rect.w), f32(cmd.rect.h)}
			k2.draw_texture_rect(g.sprites[Sprite_Name(cmd.id)].tex, tex_r, {r.x, r.y}, 8, 0)
		}
	}
}

r_get_text_width :: proc(text: string) -> (res: i32) {
	res = i32(k2.measure_text(text, FONT_HEIGHT).x)
	return
}

r_get_text_height :: proc() -> i32 {
	return FONT_HEIGHT
}
