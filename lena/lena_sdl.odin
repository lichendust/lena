#+private
#+build linux
package lena

import "core:mem"
import "core:time"
import "core:strings"

import SDL "vendor:sdl3"

Platform_Context :: struct {
	sdl_window:   ^SDL.Window,
	sdl_renderer: ^SDL.Renderer,
	sdl_buffer:   ^SDL.Texture,
}

os_init :: proc(title: string) {
	init_success := SDL.Init({.VIDEO})
	if !init_success {
		return
	}

	ctx.sdl_window   = SDL.CreateWindow(strings.clone_to_cstring(title, context.temp_allocator), 128, 128, {.RESIZABLE, .HIDDEN})
	ctx.sdl_renderer = SDL.CreateRenderer(ctx.sdl_window, nil)

	ctx.sdl_buffer = SDL.CreateTexture(ctx.sdl_renderer, .BGRA32, .STREAMING, cast(i32) ctx.screen.w, cast(i32) ctx.screen.h)
	SDL.SetTextureScaleMode(ctx.sdl_buffer, .NEAREST)

	if ctx.fps != FPS_INF {
		SDL.SetRenderVSync(ctx.sdl_renderer, 1)
	}

	os_update_cursor()
	os_update_fullscreen()

	if .HIDE_WINDOW not_in ctx.flags {
		os_show_window()
	}
}

os_destroy :: proc() {
	SDL.DestroyTexture(ctx.sdl_buffer)
	SDL.DestroyRenderer(ctx.sdl_renderer)
	SDL.Quit()
}

os_step :: proc() {
	ctx.delta_time = time.duration_seconds(time.diff(ctx.prev_time, time.now()))
	ctx.prev_time  = time.now()

	e: SDL.Event
	for SDL.PollEvent(&e) {
		#partial switch e.type {
		case .KEY_DOWN:
			code := switch_keys(e.key.key)
			ctx.key_state[code] = KEY_STATE_HELD | KEY_STATE_PRESSED

		case .KEY_UP:
			code := switch_keys(e.key.key)
			ctx.key_state[code] &= ~KEY_STATE_HELD
			ctx.key_state[code] |=  KEY_STATE_RELEASED

		case .MOUSE_BUTTON_DOWN:
			button := switch_button(e.button.button)
			ctx.mouse_state[button] = KEY_STATE_HELD | KEY_STATE_PRESSED

		case .MOUSE_BUTTON_UP:
			button := switch_button(e.button.button)
			ctx.mouse_state[button] &= ~KEY_STATE_HELD
			ctx.mouse_state[button] |= KEY_STATE_RELEASED

		case .MOUSE_MOTION:
			dimms := adjusted_window_size()
			ctx.mouse_pos.x = (int(e.motion.x) - dimms.x) * ctx.screen.w / dimms.w
			ctx.mouse_pos.y = (int(e.motion.y) - dimms.y) * ctx.screen.h / dimms.h

		case .QUIT:
			ctx.set_quit = true

		case .WINDOW_FOCUS_GAINED:
			ctx.has_focus = true

		case .WINDOW_FOCUS_LOST:
			ctx.has_focus = false

		case .WINDOW_RESIZED:
			w, h: i32
			SDL.GetWindowSize(ctx.sdl_window, &w, &h)
			ctx.window.w, ctx.window.h = int(w), int(h)
		}
	}
}

os_present :: proc() {
	pitch:  i32
	pixels: rawptr
	success := SDL.LockTexture(ctx.sdl_buffer, nil, &pixels, &pitch)
	if !success {
		panic("failed to grab texture")
	}

	for pixel, index in ctx.screen.pixels {
		ctx.backbuffer[index] = ctx.palette[pixel]
	}

	mem.copy(cast([^]u32) pixels, raw_data(ctx.backbuffer), len(ctx.backbuffer) * 4)

	SDL.UnlockTexture(ctx.sdl_buffer)

	x := ctx.palette[ctx.window_background]
	bgra_swizzle(&x)
	c := transmute([4]u8) x

	SDL.SetRenderDrawColor(ctx.sdl_renderer, c.r, c.g, c.b, 255)
	SDL.RenderClear(ctx.sdl_renderer)

	dimms := adjusted_window_size()
	r := SDL.FRect{f32(dimms.x), f32(dimms.y), f32(dimms.w), f32(dimms.h)}

	SDL.RenderTexture(ctx.sdl_renderer, ctx.sdl_buffer, nil, &r)
	SDL.RenderPresent(ctx.sdl_renderer)
}

os_show_window :: proc() {
	SDL.ShowWindow(ctx.sdl_window)
}

os_modify_palette :: proc() {}

os_update_fullscreen :: proc() {
	SDL.SetWindowFullscreen(ctx.sdl_window, .FULLSCREEN in ctx.flags)
	if .FULLSCREEN in ctx.flags {
		return
	}

	buffer_w  := ctx.screen.w
	buffer_h  := ctx.screen.h
	monitor_w := ctx.window.w
	monitor_h := ctx.window.h

	monitor := SDL.GetDesktopDisplayMode(SDL.GetPrimaryDisplay())
	if monitor != nil {
		monitor_w = cast(int) monitor.w
		monitor_h = cast(int) monitor.h
	}

	scale := cast(f32) (monitor_w > monitor_h ? monitor_h / buffer_h : monitor_w / buffer_w) / 5

	ctx.window.w = buffer_w * cast(int) (scale * 4)
	ctx.window.h = buffer_h * cast(int) (scale * 4)

	x := monitor_w / 2 - ctx.window.w / 2
	y := monitor_h / 2 - ctx.window.h / 2

	SDL.SetWindowPosition(ctx.sdl_window, cast(i32) x, cast(i32) y)
	SDL.SetWindowSize(ctx.sdl_window, cast(i32) ctx.window.w, cast(i32) ctx.window.h)
}

os_update_cursor :: proc() {
	success: bool
	if .HIDE_CURSOR in ctx.flags {
		success = SDL.HideCursor()
	} else {
		success = SDL.ShowCursor()
	}
	if !success {
		panic("failed to show or hide cursor")
	}
}

os_set_title :: proc(text: string) {
	SDL.SetWindowTitle(ctx.sdl_window, strings.clone_to_cstring(text, context.temp_allocator))
}

switch_button :: proc(m: u8) -> Mouse {
	switch m {
	case SDL.BUTTON_LEFT:
		return .LEFT
	case SDL.BUTTON_RIGHT:
		return .RIGHT
	case SDL.BUTTON_MIDDLE:
		return .MIDDLE
	}
	return .UNKNOWN
}

switch_keys :: proc(k: SDL.Keycode) -> Key {
	switch k {
	case SDL.K_0: return .N0
	case SDL.K_1: return .N1
	case SDL.K_2: return .N2
	case SDL.K_3: return .N3
	case SDL.K_4: return .N4
	case SDL.K_5: return .N5
	case SDL.K_6: return .N6
	case SDL.K_7: return .N7
	case SDL.K_8: return .N8
	case SDL.K_9: return .N9

	case SDL.K_A: return .A
	case SDL.K_B: return .B
	case SDL.K_C: return .C
	case SDL.K_D: return .D
	case SDL.K_E: return .E
	case SDL.K_F: return .F
	case SDL.K_G: return .G
	case SDL.K_H: return .H
	case SDL.K_I: return .I
	case SDL.K_J: return .J
	case SDL.K_K: return .K
	case SDL.K_L: return .L
	case SDL.K_M: return .M
	case SDL.K_N: return .N
	case SDL.K_O: return .O
	case SDL.K_P: return .P
	case SDL.K_Q: return .Q
	case SDL.K_R: return .R
	case SDL.K_S: return .S
	case SDL.K_T: return .T
	case SDL.K_U: return .U
	case SDL.K_V: return .V
	case SDL.K_W: return .W
	case SDL.K_X: return .X
	case SDL.K_Y: return .Y
	case SDL.K_Z: return .Z

	case SDL.K_RETURN:    return .RETURN
	case SDL.K_TAB:       return .TAB
	case SDL.K_BACKSPACE: return .BACKSPACE
	case SDL.K_DELETE:    return .DELETE
	case SDL.K_ESCAPE:    return .ESCAPE
	case SDL.K_SPACE:     return .SPACE

	case SDL.K_LSHIFT: return .LEFT_SHIFT
	case SDL.K_RSHIFT: return .RIGHT_SHIFT
	case SDL.K_LCTRL:  return .LEFT_CONTROL
	case SDL.K_RCTRL:  return .RIGHT_CONTROL
	case SDL.K_LALT:   return .LEFT_ALT
	case SDL.K_RALT:   return .RIGHT_ALT
	case SDL.K_LGUI:   return .LEFT_SUPER
	case SDL.K_RGUI:   return .RIGHT_SUPER

	case SDL.K_END:   return .END
	case SDL.K_HOME:  return .HOME
	case SDL.K_LEFT:  return .LEFT
	case SDL.K_UP:    return .UP
	case SDL.K_RIGHT: return .RIGHT
	case SDL.K_DOWN:  return .DOWN

	case SDL.K_SEMICOLON: return .SEMICOLON
	case SDL.K_EQUALS:    return .EQUALS
	case SDL.K_COMMA:     return .COMMA
	case SDL.K_MINUS:     return .MINUS
	case SDL.K_PERIOD:    return .DOT
	case SDL.K_SLASH:     return .SLASH
	case SDL.K_GRAVE:     return .GRAVE

	case SDL.K_PAGEUP:   return .PAGE_UP
	case SDL.K_PAGEDOWN: return .PAGE_DOWN

	case SDL.K_LEFTBRACKET:  return .LEFT_BRACKET
	case SDL.K_RIGHTBRACKET: return .RIGHT_BRACKET
	case SDL.K_BACKSLASH:    return .BACKSLASH
	case SDL.K_APOSTROPHE:   return .QUOTE

	case SDL.K_KP_0: return .P0
	case SDL.K_KP_1: return .P1
	case SDL.K_KP_2: return .P2
	case SDL.K_KP_3: return .P3
	case SDL.K_KP_4: return .P4
	case SDL.K_KP_5: return .P5
	case SDL.K_KP_6: return .P6
	case SDL.K_KP_7: return .P7
	case SDL.K_KP_8: return .P8
	case SDL.K_KP_9: return .P9

	case SDL.K_KP_MULTIPLY: return .KEYPAD_MULTIPLY
	case SDL.K_KP_PLUS:     return .KEYPAD_PLUS
	case SDL.K_KP_MINUS:    return .KEYPAD_MINUS
	case SDL.K_KP_PERIOD:   return .KEYPAD_DOT
	case SDL.K_KP_DIVIDE:   return .KEYPAD_DIVIDE
	case SDL.K_KP_ENTER:    return .KEYPAD_RETURN
	case SDL.K_KP_EQUALS:   return .KEYPAD_EQUALS

	case SDL.K_F1:  return .F1
	case SDL.K_F2:  return .F2
	case SDL.K_F3:  return .F3
	case SDL.K_F4:  return .F4
	case SDL.K_F5:  return .F5
	case SDL.K_F6:  return .F6
	case SDL.K_F7:  return .F7
	case SDL.K_F8:  return .F8
	case SDL.K_F9:  return .F9
	case SDL.K_F10: return .F10
	case SDL.K_F11: return .F11
	case SDL.K_F12: return .F12
	case SDL.K_F13: return .F13
	case SDL.K_F14: return .F14
	case SDL.K_F15: return .F15
	case SDL.K_F16: return .F16
	case SDL.K_F17: return .F17
	case SDL.K_F18: return .F18
	case SDL.K_F19: return .F19
	case SDL.K_F20: return .F20
	}
	return .UNKNOWN
}
