package main

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import rl "vendor:raylib"

Animation :: struct {
	texture:     rl.Texture2D,
	num_frames:  int,
	frame_timer: f32, // used to determine wether its time to advance to the next frame
	cur_frame:   int,
	frame_delay: f32, // Delay between each frame
	id:          int,
}

update_animation :: proc(anim: ^Animation) {
	anim.frame_timer += rl.GetFrameTime()

	for anim.frame_timer > anim.frame_delay {
		anim.cur_frame = (anim.cur_frame + 1) % anim.num_frames
		anim.frame_timer -= anim.frame_delay
	}
}

draw_animation :: proc(anim: Animation, pos: rl.Vector2, flipped: bool) {
	tex_width := f32(anim.texture.width)
	tex_height := f32(anim.texture.height)


	source_rec := rl.Rectangle {
		x      = f32(anim.cur_frame) * tex_width / f32(anim.num_frames),
		y      = 0,
		width  = tex_width / f32(anim.num_frames),
		height = tex_height,
	}

	if flipped {
		source_rec.width = -source_rec.width
	}

	dest_rec := rl.Rectangle {
		x      = pos.x,
		y      = pos.y,
		width  = tex_width / f32(anim.num_frames),
		height = tex_height,
	}

	origin := rl.Vector2{dest_rec.width / 2, dest_rec.height}

	rl.DrawTexturePro(anim.texture, source_rec, dest_rec, origin, 0, rl.WHITE)
}

PixelWindowHeight :: 180

Level :: struct {
	platforms: [dynamic]rl.Vector2,
}

platform_collider :: proc(pos: rl.Vector2) -> rl.Rectangle {
	return {pos.x, pos.y, 96, 16}
}

main :: proc() {
	// Lets wrap the context allocator with a tracking allocator
	// This will track any memory leaks
	track_alloc: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track_alloc, context.allocator)
	context.allocator = mem.tracking_allocator(&track_alloc)
	defer {
		// At the end of the program, lets print out the results
		fmt.eprintf("\n")
		// Memory leaks
		for _, entry in track_alloc.allocation_map {
			fmt.eprintf("- %v leaked %v bytes\n", entry.location, entry.size)
		}
		// Double free etc.
		for entry in track_alloc.bad_free_array {
			fmt.eprintf("- %v bad free\n", entry.location)
		}
		mem.tracking_allocator_destroy(&track_alloc)
		fmt.eprintf("\n")
	}

	rl.InitWindow(1280, 720, "My First Game")
	rl.SetWindowState({.WINDOW_RESIZABLE})
	rl.SetTargetFPS(120)
	rl.GuiSetStyle(i32(rl.GuiControl.DEFAULT), i32(rl.GuiDefaultProperty.TEXT_SIZE), 22)
	player_pos := rl.Vector2{0, 0}
	player_vel := rl.Vector2{0, 0}
	player_speed: f32 = 100
	player_jump_force: f32 = 300
	player_grounded := false
	player_flipped := false
	gravity: f32 = 1000

	load_texture_from_memory :: proc(data: []u8, filter: bool = false) -> rl.Texture2D {
		img := rl.LoadImageFromMemory(".png", &data[0], i32(len(data)))
		tex := rl.LoadTextureFromImage(img)
		rl.UnloadImage(img)
		// We only want a filter when it is not pixel art
		if filter {
			rl.SetTextureFilter(tex, .BILINEAR)
		}
		rl.SetTextureWrap(tex, .CLAMP)
		return tex
	}

	// #load() loads any file at compile time and puts it into the binary
	// it is then provided as a []u8 array
	player_anim_run := Animation {
		texture     = load_texture_from_memory(#load("cat_run.png")),
		num_frames  = 4,
		frame_delay = 0.1,
		id          = 1,
	}

	player_anim_idle := Animation {
		texture     = load_texture_from_memory(#load("cat_idle.png")),
		num_frames  = 2,
		frame_delay = 0.4,
		id          = 2,
	}

	current_anim := player_anim_idle

	level: Level

	// Load level data from file
	if level_data, ok := os.read_entire_file("level.json", context.temp_allocator); ok {
		if json.unmarshal(level_data, &level) != nil {
			append(&level.platforms, rl.Vector2{-20, 20})
		}
	} else {
		append(&level.platforms, rl.Vector2{-20, 20})
	}

	platform_tex := load_texture_from_memory(#load("platform.png"))
	editing := false
	edit_mode_btn_pressed := false

	// Main loop
	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground({110, 184, 168, 255})

		if rl.IsKeyDown(rl.KeyboardKey.A) {
			player_vel.x = -player_speed
			player_flipped = true
			if current_anim.id != player_anim_run.id {
				current_anim = player_anim_run
			}
		} else if rl.IsKeyDown(rl.KeyboardKey.D) {
			player_vel.x = player_speed
			player_flipped = false
			if current_anim.id != player_anim_run.id {
				current_anim = player_anim_run
			}
		} else {
			player_vel.x = 0
			if current_anim.id != player_anim_idle.id {
				current_anim = player_anim_idle
			}
		}

		player_vel.y += gravity * rl.GetFrameTime()

		if !player_grounded {
			if current_anim.id != player_anim_idle.id {
				current_anim = player_anim_idle
			}
		}

		if player_grounded && rl.IsKeyPressed(.SPACE) {
			player_vel.y = -player_jump_force
		}

		player_pos += player_vel * rl.GetFrameTime()

		player_feet_collider := rl.Rectangle{player_pos.x - 4, player_pos.y - 4, 8, 4}

		player_grounded = false

		for platform in level.platforms {
			if rl.CheckCollisionRecs(player_feet_collider, platform_collider(platform)) &&
			   player_vel.y > 0 {
				player_vel.y = 0
				player_pos.y = platform.y
				player_grounded = true
			}
		}

		update_animation(&current_anim)

		screen_width := f32(rl.GetScreenHeight())
		screen_height := f32(rl.GetScreenHeight())

		camera := rl.Camera2D {
			// Uncomment the following line to have a fixed zoom of 4
			// zoom   = 4,
			// or use this line to have a dynamic zoom that changes depending on the window height
			zoom   = screen_height / PixelWindowHeight,
			// Put the origin of the camera to the center
			offset = {screen_width / 2, screen_height / 2},
			// Let the camera look at the player
			target = player_pos,
		}

		// Render everything that should be clipped/viewed through the camera
		rl.BeginMode2D(camera)

		for platform in level.platforms {
			rl.DrawTextureV(platform_tex, platform, rl.WHITE)
		}
		draw_animation(current_anim, player_pos, player_flipped)

		if editing {
			if rl.GetMousePosition().y > 80 {
				mp := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

				rl.DrawTextureV(platform_tex, mp, rl.WHITE)

				if rl.IsMouseButtonPressed(.LEFT) {

					append(&level.platforms, mp)
				}


				if rl.IsMouseButtonPressed(.RIGHT) {
					for pos, idx in level.platforms {
						if rl.CheckCollisionPointRec(mp, platform_collider(pos)) {
							unordered_remove(&level.platforms, idx)
							break
						}
					}
				}
			}
		}

		rl.EndMode2D()

		// Gui stuff (should not be affected/clipped by the camera)

		edit_mode_btn_pressed = rl.GuiButton(
			{20, 20, 200, 50},
			editing ? "Edit Mode" : "Game Mode",
		)

		rl.EndDrawing()

		if edit_mode_btn_pressed {
			editing = !editing
		}
	}

	rl.CloseWindow()


	// Save level data befor quitting
	if level_data, err := json.marshal(level, allocator = context.temp_allocator); err == nil {
		os.write_entire_file("level.json", level_data)
	}

	free_all(context.temp_allocator)
	delete(level.platforms)
}
