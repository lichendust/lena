package lena

import "base:runtime"

import "core:mem"
import "core:hash"
import "core:math"
import "core:time"
import "core:bytes"
import "core:image/png"

import "vendor:stb/truetype"

MAJOR :: 0
MINOR :: 1
PATCH :: 0

IS_WINDOWS :: ODIN_OS == .Windows
IS_DARWIN  :: ODIN_OS == .Darwin
IS_LINUX   :: ODIN_OS == .Linux
IS_WEB     :: ODIN_OS == .JS
IS_SDL     :: IS_LINUX

WIN95_MODE   :: #config(LENA_WIN95,   false)
PALETTE_SIZE :: #config(LENA_PALETTE, 32)

when PALETTE_SIZE < 1 || PALETTE_SIZE > 256 {
	#panic("lena_palette must be 1..256")
}

BLEND_PALETTE_SIZE :: PALETTE_SIZE * PALETTE_SIZE

// colordome by polyphrog
// https://lospec.com/palette-list/colordome-32
DEFAULT_PALETTE :: [32]u32{
	0xff0d0b0d, 0xfffff8e1, 0xffc8b89f, 0xff987a68, 0xff674949, 0xff3a3941, 0xff6b6f72, 0xffadb9b8,
	0xffadd9b7, 0xff6eb39d, 0xff30555b, 0xff1a1e2d, 0xff284e43, 0xff467e3e, 0xff93ab52, 0xfff2cf5c,
	0xffec773d, 0xffb83530, 0xff722030, 0xff281721, 0xff6d2944, 0xffc85257, 0xffec9983, 0xffdbaf77,
	0xffb77854, 0xff833e35, 0xff50282f, 0xff65432f, 0xff7e6d37, 0xff6ebe70, 0xffb75834, 0xffd55c4d,
}

@private
FONT   :: #load("scientifica.ttf")
FONT_WIDTH  :: 5
FONT_HEIGHT :: 11

@private
ctx: Context // Lena's implicit internal context

Context :: struct {
	flags: Startup_Flags,
	fps:   i64,

	// timers
	step_time:  time.Duration,
	prev_time:  time.Time,
	delta_time: f64,

	text_step:        f64,
	typewriter_step:  f64,
	typewriter_state: u64,

	// screen
	screen:     Image,
	backbuffer: []u32,

	// internal state
	window:      struct { w, h: int },
	mouse_pos:   struct { x, y: int },
	key_state:   [256]u8,
	mouse_state: [8]u8,
	set_quit:    bool,
	has_focus:   bool,

	// drawing state
	draw_state: Draw_Flags,
	alpha_index:       u8,
	text_index:        u8,
	bold_index:        u8,
	mask_index:        u8,
	palette_shift:     u8,
	window_background: u8,

	clip_rect: Rect,

	palette:       [PALETTE_SIZE]u32,
	blend_palette: [BLEND_PALETTE_SIZE]u8,

	// fonts
	font_info:   truetype.fontinfo,
	font_cache:  map[rune]Image,
	font_scale:  f32,
	font_ascent: i32,

	// allocator
	internal_buffer: []u8,
	arena:           mem.Arena,
	allocator:       runtime.Allocator,

	// modular data fields
	using os: Platform_Context,
	using au: Audio_Context,
}

FPS_AUTO :: -1
FPS_INF  :: 0
FPS_60   :: 60
FPS_144  :: 144

Startup_Flags :: bit_set[Startup_Flag]
Startup_Flag  :: enum u8 {
	FULLSCREEN,
	HIDE_CURSOR,
	DEFER_WINDOW,
	HIDE_WINDOW = DEFER_WINDOW, // @1.0 will be deprecated
}

Draw_Flags :: bit_set[Draw_Flag]
Draw_Flag  :: enum u8 {
	MASK,
	SHIFT,
	BLEND,
	LOCK_ALPHA,
}

Rect  :: struct { x, y, w, h: int }
Image :: struct {
	w, h:   int,
	pixels: []u8,
}

init :: proc(title: string, w, h: int, target_framerate: i64 = FPS_AUTO, flags: Startup_Flags = {}, backing_allocator := context.allocator) -> ^Context {
	ctx.fps   = target_framerate
	ctx.flags = flags

	ctx.internal_buffer = make([]u8, 4 * (w * h + 1024 * 1024), backing_allocator)
	mem.arena_init(&ctx.arena, ctx.internal_buffer)
	ctx.allocator = mem.arena_allocator(&ctx.arena)

	ctx.screen.w      = w
	ctx.screen.h      = h
	ctx.screen.pixels = make([]u8,  w * h, ctx.allocator)
	ctx.backbuffer    = make([]u32, w * h, ctx.allocator)

	ctx.has_focus     = true
	ctx.text_index    = 1
	ctx.bold_index    = 15
	ctx.blend_palette = default_blend_palette()

	when PALETTE_SIZE == 32 {
		set_palette(DEFAULT_PALETTE)
	}

	truetype.InitFont(&ctx.font_info, raw_data(FONT), 0)
	ctx.font_scale = truetype.ScaleForPixelHeight(&ctx.font_info, FONT_HEIGHT)
	truetype.GetFontVMetrics(&ctx.font_info, &ctx.font_ascent, nil, nil)
	ctx.font_ascent = i32(math.round(f32(ctx.font_ascent) * ctx.font_scale))

	ctx.font_cache = make(type_of(ctx.font_cache), 2048, ctx.allocator)

	#force_inline os_init(title)
	#force_inline audio_init()

	ctx.prev_time = time.now()

	os_update_cursor()

	if .DEFER_WINDOW not_in ctx.flags {
		os_show_window()
	}

	return &ctx
}

step :: proc() -> (f64, bool) #no_bounds_check {
	free_all(context.temp_allocator)

	for pixel, index in ctx.screen.pixels {
		ctx.backbuffer[index] = ctx.palette[pixel]
	}

	#force_inline os_present()

	ctx.text_step       += ctx.delta_time * 15
	ctx.typewriter_step += ctx.delta_time * 10

	for &state in ctx.key_state {
		state &~= (KEY_STATE_PRESSED | KEY_STATE_RELEASED)
	}
	for &state in ctx.mouse_state {
		state &~= (KEY_STATE_PRESSED | KEY_STATE_RELEASED)
	}

	#force_inline os_step()
	#force_inline audio_step(ctx.delta_time)

	return ctx.delta_time, !ctx.set_quit
}

quit :: proc() {
	ctx.set_quit = true
}

still_running :: proc() -> bool {
	return !ctx.set_quit
}

destroy :: proc() {
	#force_inline os_destroy()
	#force_inline audio_destroy()
	free_all(ctx.allocator)
	delete(ctx.internal_buffer)
}

show_window :: #force_inline proc() {
	ctx.flags -= {.DEFER_WINDOW}
	os_show_window()
}

get_context :: #force_inline proc() -> ^Context {
	return &ctx
}

get_screen :: #force_inline proc() -> Image {
	return ctx.screen
}

set_title :: #force_inline proc(text: string) {
	os_set_title(text)
}

@private
adjusted_window_size :: proc() -> Rect {
	src_ratio := f64(ctx.screen.h) / f64(ctx.screen.w)
	dst_ratio := f64(ctx.window.h) / f64(ctx.window.w)

	w, h: int
	if src_ratio < dst_ratio {
		w = ctx.window.w
		h = int(math.ceil(f64(w) * src_ratio))
	} else {
		h = ctx.window.h
		w = int(math.ceil(f64(h) / src_ratio))
	}

	return {(ctx.window.w - w) / 2, (ctx.window.h - h) / 2, w, h}
}

@private
bgra_swizzle :: proc(c: ^u32) {
	n := transmute([4]u8) c^
	c^ = transmute(u32) n.bgra //swizzle(n, 2, 1, 0, 3) // rgba -> bgra
}

set_palette :: proc(colors: [PALETTE_SIZE]u32) {
	ctx.palette = colors
	#force_inline os_modify_palette()
}

set_blend_palette :: #force_inline proc(colors: [BLEND_PALETTE_SIZE]u8) {
	ctx.blend_palette = colors
}

default_blend_palette :: proc() -> [BLEND_PALETTE_SIZE]u8 #no_bounds_check {
	array: [BLEND_PALETTE_SIZE]u8
	for a in 0..<PALETTE_SIZE {
		for b in 0..<PALETTE_SIZE {
			array[szudzik_pair(cast(u8) b, cast(u8) a)] = cast(u8) b
		}
	}
	return array
}

set_blend_palette_pair :: proc "contextless" (src, dst, result: u8) {
	ctx.blend_palette[szudzik_pair(src, dst)] = result
}

set_draw_state :: proc "contextless" (flags: Draw_Flags = {}) {
	ctx.draw_state = flags
}

set_text_color        :: proc "contextless" (color:  u8) { ctx.text_index        = color  }
set_bold_color        :: proc "contextless" (color:  u8) { ctx.bold_index        = color  }
set_mask_color        :: proc "contextless" (color:  u8) { ctx.mask_index        = color  }
set_window_background :: proc "contextless" (color:  u8) { ctx.window_background = color  }
set_palette_shift     :: proc "contextless" (offset: u8) { ctx.palette_shift     = offset }
set_alpha_index       :: proc "contextless" (alpha:  u8) { ctx.alpha_index       = alpha  }

set_clip_rect :: proc "contextless" (rect: Rect = {}) {
	ctx.clip_rect = get_intersect({0, 0, ctx.screen.w, ctx.screen.h}, rect)
}

@private
clip_rect_or_target_size :: proc "contextless" (target: Image) -> Rect {
	if ctx.clip_rect.w == 0 || ctx.clip_rect.h == 0 {
		return {0, 0, target.w, target.h}
	}
	return ctx.clip_rect
}

toggle_fullscreen :: proc() {
	ctx.flags ~= {.FULLSCREEN}
	#force_inline os_update_fullscreen()
}

toggle_cursor :: proc() {
	ctx.flags ~= {.HIDE_CURSOR}
	#force_inline os_update_cursor()
}

create_image :: proc(w, h: int, allocator := context.allocator) -> Image {
	img: Image
	img.w = w
	img.h = h
	img.pixels = make([]u8, w * h, allocator)
	return img
}

create_image_from_png :: proc(blob: []u8, allocator := context.allocator) -> Image {
	the_png, err := png.load_from_bytes(blob, {.do_not_expand_indexed}, context.temp_allocator)
	if err != nil {
		return {}
	}

	dat := bytes.buffer_to_bytes(&the_png.pixels)
	img := create_image(the_png.width, the_png.height, allocator)
	copy(img.pixels, dat)

	return img
}

destroy_image :: proc(img: Image) {
	delete(img.pixels)
}

@private
palette_shift_value :: #force_inline proc "contextless" (value: u8) -> u8 {
	when PALETTE_SIZE == 256 {
		return (value + ctx.palette_shift)
	} else {
		return (value + ctx.palette_shift) % PALETTE_SIZE
	}
}

set_pixel :: #force_inline proc "contextless" (x, y: int, color: u8) {
	set_pixel_on_image(ctx.screen, x, y, color)
}
set_pixel_on_image :: proc "contextless" (target: Image, x, y: int, color: u8) {
	if x < 0 || y < 0 || x >= target.w || y >= target.h do return

	color := color
	if .SHIFT in ctx.draw_state {
		color = palette_shift_value(color)
	}

	clip_rect := clip_rect_or_target_size(target)
	#force_inline set_pixel_on_image_no_shift(target, x, y, color, clip_rect)
}

@private
set_pixel_on_image_no_shift :: proc "contextless" (target: Image, x, y: int, color: u8, clip_rect: Rect) #no_bounds_check {
	if !is_inside(clip_rect, x, y) do return

	index := x + y * target.w
	color := color
	if .BLEND in ctx.draw_state {
		color = ctx.blend_palette[szudzik_pair(color, target.pixels[index])]
	}
	if .LOCK_ALPHA in ctx.draw_state && target.pixels[index] != ctx.alpha_index {
		target.pixels[index] = color
		return
	}
	target.pixels[index] = color
}

get_pixel :: proc "contextless" (x, y: int) -> u8 {
	return get_pixel_on_image(ctx.screen, x, y)
}
get_pixel_on_image :: proc "contextless" (target: Image, x, y: int) -> u8 #no_bounds_check {
	n := x + y * target.w
	if n >= len(target.pixels) do return 0
	return target.pixels[n]
}

clear_screen :: #force_inline proc(c: u8 = 0) {
	clear_image(ctx.screen, c)
}

clear_image :: proc(source: Image, c: u8 = 0) #no_bounds_check {
	for i in 0 ..< len(source.pixels) {
		source.pixels[i] = c
	}
}

draw_image :: #force_inline proc "contextless" (source: Image, x, y: int) {
	draw_image_to_image_scaled(source, ctx.screen, {0, 0, source.w, source.h}, {x, y, source.w, source.h})
}
draw_image_to_image :: #force_inline proc "contextless" (source, target: Image, x, y: int) {
	draw_image_to_image_scaled(source, target, {0, 0, source.w, source.h}, {x, y, source.w, source.h})
}

draw_tile :: #force_inline proc "contextless" (source: Image, src: Rect, x, y: int) {
	draw_image_to_image_scaled(source, ctx.screen, src, {x, y, src.w, src.h})
}
draw_tile_to_image :: proc "contextless" (source, target: Image, src: Rect, x, y: int) {
	draw_image_to_image_scaled(source, target, src, {x, y, src.w, src.h})
}

draw_image_scaled :: proc "contextless" (source: Image, src, dst: Rect) {
	draw_image_to_image_scaled(source, ctx.screen, src, dst)
}
draw_image_to_image_scaled :: proc "contextless" (source, target: Image, src, dst: Rect) {
	// draw_image_int here is essentially acting as a macro and
	// we're expanding it with all the nitty gritty decisions
	// locked-in above the fold instead of down in the hottest
	// part of the loop
	// it's pretty damn, but it eeks out another 12%-25% of
	// performance when blitting images

	switch ctx.draw_state {
	case {.MASK, .SHIFT, .BLEND, .LOCK_ALPHA}:
		draw_image_int(source, target, src, dst, {.MASK, .SHIFT, .BLEND, .LOCK_ALPHA})
	case {.MASK, .SHIFT, .LOCK_ALPHA}:
		draw_image_int(source, target, src, dst, {.MASK, .SHIFT, .LOCK_ALPHA})
	case {.MASK, .BLEND, .LOCK_ALPHA}:
		draw_image_int(source, target, src, dst, {.MASK, .BLEND, .LOCK_ALPHA})
	case {.SHIFT, .BLEND, .LOCK_ALPHA}:
		draw_image_int(source, target, src, dst, {.SHIFT, .BLEND, .LOCK_ALPHA})
	case {.MASK, .LOCK_ALPHA}:
		draw_image_int(source, target, src, dst, {.MASK, .LOCK_ALPHA})
	case {.SHIFT, .LOCK_ALPHA}:
		draw_image_int(source, target, src, dst, {.SHIFT, .LOCK_ALPHA})
	case {.BLEND, .LOCK_ALPHA}:
		draw_image_int(source, target, src, dst, {.BLEND, .LOCK_ALPHA})
	case {.MASK, .SHIFT}:
		draw_image_int(source, target, src, dst, {.MASK, .SHIFT})
	case {.MASK, .BLEND}:
		draw_image_int(source, target, src, dst, {.MASK, .BLEND})
	case {.SHIFT, .BLEND}:
		draw_image_int(source, target, src, dst, {.SHIFT, .BLEND})
	case {.MASK}:
		draw_image_int(source, target, src, dst, {.MASK})
	case {.SHIFT}:
		draw_image_int(source, target, src, dst, {.SHIFT})
	case {.BLEND}:
		draw_image_int(source, target, src, dst, {.BLEND})
	case {.LOCK_ALPHA}:
		draw_image_int(source, target, src, dst, {.LOCK_ALPHA})
	case:
		draw_image_int(source, target, src, dst, {})
	}
}

@private
draw_image_int :: proc "contextless" (source, target: Image, src, dst: Rect, $draw_flags: Draw_Flags) #no_bounds_check {
	// https://github.com/rxi/kit (MIT) provided the basis for this procedure

	if src.w == 0 || src.h == 0 || dst.w == 0 || dst.h == 0 {
		return
	}

	clip_rect := clip_rect_or_target_size(target)

	if clip_rect.w == 0 || clip_rect.h == 0 {
		return
	}

	cx1   := clip_rect.x
	cy1   := clip_rect.y
	cx2   := cx1 + clip_rect.w
	cy2   := cx2 + clip_rect.h
	stepx := (src.w << 10) / dst.w
	stepy := (src.h << 10) / dst.h
	sy    := src.y << 10

	dy := dst.y
	if dy < cy1 {
		sy += (cy1 - dy) * stepy
		dy = cy1
	}
	ey := min(cy2, dst.y + dst.h)

	for ; dy < ey; dy += 1 {
		if dy >= cy1 && dy < cy2 {
			sx := src.x << 10

			srow := source.pixels[(sy >> 10) * source.w:]
			drow := target.pixels[dy * target.w:]

			dx := dst.x;
			if dx < cx1 {
				sx += (cx1 - dx) * stepx
				dx = cx1
			}
			ex := min(cx2, dst.x + dst.w)

			for ; dx < ex; dx += 1 {
				if i := srow[sx >> 10]; i != ctx.alpha_index {
					when .LOCK_ALPHA in draw_flags do if drow[dx] == ctx.alpha_index {
						sx += stepx
						continue
					}

					when .MASK  in draw_flags {
						i = ctx.mask_index
					}
					when .SHIFT in draw_flags {
						i = palette_shift_value(i)
					}

					when .BLEND in draw_flags {
						drow[dx] = ctx.blend_palette[szudzik_pair(i, drow[dx])]
					} else {
						drow[dx] = i
					}
				}

				sx += stepx
			}
		}

		sy += stepy
	}
}

get_glyph :: proc(r: rune) -> Image {
	if glyph, exists := ctx.font_cache[r]; exists {
		return glyph
	}

	glyph := create_image(FONT_WIDTH, FONT_HEIGHT, ctx.allocator)
	ctx.font_cache[r] = glyph

	x1, y1, x2, y2: i32
	truetype.GetCodepointBitmapBox(&ctx.font_info, r, ctx.font_scale, ctx.font_scale, &x1, &y1, &x2, &y2)

	byte_offset := (ctx.font_ascent + y1) * FONT_WIDTH
	truetype.MakeCodepointBitmap(&ctx.font_info, raw_data(glyph.pixels[byte_offset:]), x2 - x1, y2 - y1, FONT_WIDTH, ctx.font_scale, ctx.font_scale, r)

	return glyph
}

KEY_STATE_HELD:     u8: 0x0001
KEY_STATE_PRESSED:  u8: 0x0002
KEY_STATE_RELEASED: u8: 0x0004

key_held :: #force_inline proc(key: Key) -> bool {
	return ctx.key_state[key] & KEY_STATE_HELD != 0
}
key_pressed :: #force_inline proc(key: Key) -> bool {
	return ctx.key_state[key] & KEY_STATE_PRESSED != 0
}
key_released :: #force_inline proc(key: Key) -> bool {
	return ctx.key_state[key] & KEY_STATE_RELEASED != 0
}

mouse_held :: #force_inline proc(button: Mouse) -> bool {
	return ctx.mouse_state[button] & KEY_STATE_HELD != 0
}
mouse_pressed :: #force_inline proc(button: Mouse) -> bool {
	return ctx.mouse_state[button] & KEY_STATE_PRESSED != 0
}
mouse_released :: #force_inline proc(button: Mouse) -> bool {
	return ctx.mouse_state[button] & KEY_STATE_RELEASED != 0
}

// this is a 'fast' line drawer for just filling rows on targets
@private
horizontal_line :: proc(target: Image, x, y, x2: int, color: u8, clip_rect: Rect) #no_bounds_check {
	w := target.w - 1

	if y < 0 || y > target.h - 1 do return
	if x < 0 && x2 < 0 || x > w && x2 > w do return
	if y < clip_rect.y || y > clip_rect.y + clip_rect.h - 1 do return

	row := clamp(y,  0, target.h - 1) * target.w
	min := row + clamp(x,  clip_rect.x, clip_rect.x + clip_rect.w)
	max := row + clamp(x2, clip_rect.x - 1, clip_rect.x + clip_rect.w - 1)

	color := color
	if .SHIFT in ctx.draw_state {
		color = palette_shift_value(color)
	}

	for i in min ..= max {
		if .LOCK_ALPHA in ctx.draw_state && target.pixels[i] == ctx.alpha_index {
			continue
		}
		if .BLEND in ctx.draw_state {
			target.pixels[i] = ctx.blend_palette[szudzik_pair(color, target.pixels[i])]
		} else {
			target.pixels[i] = color
		}
	}
}

draw_rect :: #force_inline proc(r: Rect, color: u8, filled: bool) {
	draw_rect_to_image(ctx.screen, r, color, filled)
}
draw_rect_to_image :: proc(target: Image, r: Rect, color: u8, filled: bool) #no_bounds_check {
	if target.w == 0 || target.h == 0 do return

	color := color
	if .SHIFT in ctx.draw_state {
		color = palette_shift_value(color)
	}

	clip_rect := clip_rect_or_target_size(target)

	if filled {
		rect := get_intersect(r, clip_rect)
		if rect.w == 0 || rect.h == 0 {
			return
		}

		diff := target.w - rect.w
		i := target.w * rect.y + rect.x
		for y := 0; y < rect.h; y += 1 {
			for x := 0; x < rect.w; x += 1 {
				if .LOCK_ALPHA in ctx.draw_state && target.pixels[i] == ctx.alpha_index {
					i += 1
					continue
				}
				if .BLEND in ctx.draw_state {
					target.pixels[i] = ctx.blend_palette[szudzik_pair(color, target.pixels[i])]
				} else {
					target.pixels[i] = color
				}
				i += 1
			}
			i += diff
		}
		return
	}

	// hollow
	w := min(target.w, r.x + r.w - 1)
	h := min(target.h, r.y + r.h - 1)

	horizontal_line(target, r.x, r.y, w, color, clip_rect)
	horizontal_line(target, r.x, h,   w, color, clip_rect)

	// this could be faster
	for i := r.y + 1; i <= h - 1; i += 1 {
		set_pixel_on_image_no_shift(target, r.x, i, color, clip_rect)
		set_pixel_on_image_no_shift(target, w,   i, color, clip_rect)
	}
}

draw_circle :: #force_inline proc(cx, cy, radius: int, color: u8, filled: bool) {
	draw_circle_to_image(ctx.screen, cx, cy, radius, color, filled)
}
draw_circle_to_image :: proc(target: Image, cx, cy, radius: int, color: u8, filled: bool) #no_bounds_check {
	if radius == 0 do return
	if target.w == 0 || target.h == 0 do return

	color := color
	if .SHIFT in ctx.draw_state {
		color = palette_shift_value(color)
	}

	clip_rect := clip_rect_or_target_size(target)

	x, y := radius, 0

	if filled {
		error := -radius
		for x >= y {
			pre_y := y
			error += y; y += 1; error += y
			horizontal_line(target, cx - x, cy + pre_y, cx + x, color, clip_rect)

			if pre_y != 0 {
				horizontal_line(target, cx - x, cy - pre_y, cx + x, color, clip_rect)
			}

			if error >= 0 {
				if x != pre_y {
					horizontal_line(target, cx - pre_y, cy + x, cx + pre_y, color, clip_rect)
					if pre_y != 0 {
						horizontal_line(target, cx - pre_y, cy - x, cx + pre_y, color, clip_rect)
					}
				}
				error -= x; x -= 1; error -= x
			}
		}

		return
	}

	set_pixel_on_image_no_shift(target,  x + cx,  y + cy, color, clip_rect)
	set_pixel_on_image_no_shift(target, -x + cx,  y + cy, color, clip_rect)
	set_pixel_on_image_no_shift(target,  y + cx, -x + cy, color, clip_rect)
	set_pixel_on_image_no_shift(target, -y + cx,  x + cy, color, clip_rect)

	P := 1 - radius
	for x > y {
		y += 1
		if P <= 0 {
			P = P + 2 * y + 1
		} else {
			x -= 1
			P = P + 2 * y - 2 * x + 1
		}
		if x < y do break

		set_pixel_on_image_no_shift(target,  x + cx,  y + cy, color, clip_rect)
		set_pixel_on_image_no_shift(target, -x + cx,  y + cy, color, clip_rect)
		set_pixel_on_image_no_shift(target,  x + cx, -y + cy, color, clip_rect)
		set_pixel_on_image_no_shift(target, -x + cx, -y + cy, color, clip_rect)

		if x != y {
			set_pixel_on_image_no_shift(target,  y + cx,  x + cy, color, clip_rect)
			set_pixel_on_image_no_shift(target, -y + cx,  x + cy, color, clip_rect)
			set_pixel_on_image_no_shift(target,  y + cx, -x + cy, color, clip_rect)
			set_pixel_on_image_no_shift(target, -y + cx, -x + cy, color, clip_rect)
		}
	}
}

draw_line :: #force_inline proc(x1, y1, x2, y2: int, color: u8) {
	draw_line_to_image(ctx.screen, x1, y1, x2, y2, color)
}
draw_line_to_image :: proc(target: Image, x1, y1, x2, y2: int, color: u8) #no_bounds_check {
	if target.w == 0 || target.h == 0 do return

	x1 := x1
	y1 := y1
	dx :=  math.abs(x2 - x1)
	dy := -math.abs(y2 - y1)
	sx := x1 < x2 ? 1 : -1
	sy := y1 < y2 ? 1 : -1

	error := dx + dy
	color := color
	if .SHIFT in ctx.draw_state {
		color = palette_shift_value(color)
	}

	clip_rect := clip_rect_or_target_size(target)

	for {
		set_pixel_on_image_no_shift(target, x1, y1, color, clip_rect)

		if x1 == x2 && y1 == y2 do break

		e2 := 2 * error
		if e2 >= dy {
			if x1 == x2 do break
			error += dy
			x1 += sx
		}
		if e2 <= dx {
			if y1 == y2 do break
			error += dx
			y1 += sy
		}
	}
}

draw_text :: #force_inline proc(t: string, x, y: int, wrap_width: int = 0, left_margin: int = -1) -> (int, int) {
	return draw_text_to_image(ctx.screen, t, x, y, wrap_width, left_margin)
}
draw_text_to_image :: proc(target: Image, t: string, x, y: int, wrap_width: int = 0, left_margin: int = -1) -> (int, int) {
	return draw_text_int(target, t, x, y, wrap_width, left_margin, 9999)
}

draw_typewriter_text :: #force_inline proc(t: string, x, y: int, wrap_width: int = 0, left_margin: int = -1) -> (int, int) {
	return draw_typewriter_text_to_image(ctx.screen, t, x, y, wrap_width, left_margin)
}
draw_typewriter_text_to_image :: proc(target: Image, t: string, x, y: int, wrap_width: int = 0, left_margin: int = -1) -> (int, int) {
	h := hash.fnv64a(transmute([]u8) t)
	if ctx.typewriter_state != h {
		ctx.typewriter_step  = 0
		ctx.typewriter_state = h
	}
	return draw_text_int(target, t, x, y, wrap_width, left_margin, cast(int) ctx.typewriter_step)
}

skip_typewriter :: proc() {
	ctx.typewriter_step = 9999
}

@private
draw_text_int :: proc(target: Image, t: string, x, y, wrap_width, left_margin, char_limit: int) -> (int, int) #no_bounds_check {
	oscillate :: #force_inline proc "contextless" (input: int) -> int {
		return math.abs(((input + 2) % 4) - 2) - 1
	}

	wrap_width      := target.w if wrap_width == 0 else wrap_width
	left_margin := x if left_margin == -1 else left_margin

	// we hijack the mask_index field to colour our text, so we restore it when done
	saved_color := ctx.mask_index
	ctx.mask_index = ctx.text_index
	defer ctx.mask_index = saved_color

	// we also hijack the alpha, because stb_ttf creates 1 bit images
	saved_alpha := ctx.alpha_index
	ctx.alpha_index = 0
	defer ctx.alpha_index = saved_alpha

	// and again, we hijack the draw_state and add our nonsense to it
	saved_state := ctx.draw_state
	ctx.draw_state += {.MASK}
	defer ctx.draw_state = saved_state

	sx, sy := x, y

	is_escaped: bool
	do_wobble:  bool

	letter_offset := 0
	global_offset := oscillate(cast(int) ctx.text_step)

	index := 0
	for c, i in t {
		index += 1
		if index > char_limit do break

		switch c {
		case ' ':
			sx += FONT_WIDTH
			local_x := sx

			wrap_loop: for subchar in t[i + 1:] {
				switch subchar {
					case '|', '/', '\\', '*':
						continue
					case ' ', '\n', '\t':
						break wrap_loop
				}

				local_x += FONT_WIDTH
				if local_x > wrap_width {
					sy += FONT_HEIGHT; sx = left_margin
					break wrap_loop
				}
			}
			continue

		case '\n':
			sy += FONT_HEIGHT; sx = left_margin
			continue

		case '\t':
			sx += FONT_WIDTH * 4
			continue

		case '|':
			if !is_escaped {
				do_wobble = !do_wobble
				continue
			}

		case '*':
			if !is_escaped {
				ctx.mask_index = ctx.bold_index if ctx.mask_index == ctx.text_index else ctx.text_index
				continue
			}

		case '\\':
			if !is_escaped {
				is_escaped = true
				continue
			}
		}

		wobble_adjust := 0
		if do_wobble {
			letter_offset += 1
			wobble_adjust = oscillate(letter_offset + global_offset)
		}

		draw_image_to_image(get_glyph(c), target, sx, sy + wobble_adjust)
		sx += FONT_WIDTH
		is_escaped = false
	}

	return sx, sy
}

is_inside :: proc "contextless" (r: Rect, x, y: int) -> bool {
	return x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h
}

is_overlapped :: proc "contextless" (a, b: Rect) -> bool {
	return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

get_intersect :: proc "contextless" (a, b: Rect) -> Rect {
	x1 := max(a.x, b.x)
	y1 := max(a.y, b.y)
	x2 := min(a.x + a.w, b.x + b.w)
	y2 := min(a.y + a.h, b.y + b.h)
	return { x1, y1, x2 - x1, y2 - y1 }
}

get_cursor :: proc() -> (int, int) {
	return ctx.mouse_pos.x, ctx.mouse_pos.y
}

has_focus :: proc() -> bool {
	return ctx.has_focus
}

szudzik_pair :: proc "contextless" (a, b: u8) -> u16 {
	a, b := cast(u16) a, cast(u16) b
	return a >= b ? a * a + a + b : a + b * b
}

Mouse :: enum u8 {
	UNKNOWN = 0,
	LEFT    = 1,
	RIGHT   = 2,
	MIDDLE  = 3,
}

Key :: enum u8 {
	UNKNOWN = 0,

	N0 = '0',
	N1 = '1',
	N2 = '2',
	N3 = '3',
	N4 = '4',
	N5 = '5',
	N6 = '6',
	N7 = '7',
	N8 = '8',
	N9 = '9',

	A = 'A',
	B = 'B',
	C = 'C',
	D = 'D',
	E = 'E',
	F = 'F',
	G = 'G',
	H = 'H',
	I = 'I',
	J = 'J',
	K = 'K',
	L = 'L',
	M = 'M',
	N = 'N',
	O = 'O',
	P = 'P',
	Q = 'Q',
	R = 'R',
	S = 'S',
	T = 'T',
	U = 'U',
	V = 'V',
	W = 'W',
	X = 'X',
	Y = 'Y',
	Z = 'Z',

	RETURN    = 0x0D,
	TAB       = 0x09,
	BACKSPACE = 0x08,
	DELETE    = 0x2E,
	ESCAPE    = 0x1B,
	SPACE     = 0x20,

	LEFT_SHIFT    = 0xA0,
	RIGHT_SHIFT   = 0xA1,
	LEFT_CONTROL  = 0xA2,
	RIGHT_CONTROL = 0xA3,
	LEFT_ALT      = 0xA4,
	RIGHT_ALT     = 0xA5,
	LEFT_SUPER    = 0x5B,
	RIGHT_SUPER   = 0x5C,

	END   = 0x23,
	HOME  = 0x24,
	LEFT  = 0x25,
	UP    = 0x26,
	RIGHT = 0x27,
	DOWN  = 0x28,

	SEMICOLON = 0xBA,
	EQUALS    = 0xBB,
	COMMA     = 0xBC,
	MINUS     = 0xBD,
	DOT       = 0xBE,
	PERIOD    = DOT,
	SLASH     = 0xBF,
	GRAVE     = 0xC0,

	PAGE_UP   = 0x21,
	PAGE_DOWN = 0x22,

	LEFT_BRACKET  = 0xDB,
	RIGHT_BRACKET = 0xDD,
	BACKSLASH     = 0xDC,
	QUOTE         = 0xDE,

	P0 = 0x60,
	P1 = 0x61,
	P2 = 0x62,
	P3 = 0x63,
	P4 = 0x64,
	P5 = 0x65,
	P6 = 0x66,
	P7 = 0x67,
	P8 = 0x68,
	P9 = 0x69,

	KEYPAD_MULTIPLY = 0x6A,
	KEYPAD_PLUS     = 0x6B,
	KEYPAD_MINUS    = 0x6D,
	KEYPAD_DOT      = 0x6E,
	KEYPAD_PERIOD   = KEYPAD_DOT,
	KEYPAD_DIVIDE   = 0x6F,
	KEYPAD_RETURN   = RETURN,
	KEYPAD_EQUALS   = EQUALS,

	F1  = 0x70,
	F2  = 0x71,
	F3  = 0x72,
	F4  = 0x73,
	F5  = 0x74,
	F6  = 0x75,
	F7  = 0x76,
	F8  = 0x77,
	F9  = 0x78,
	F10 = 0x79,
	F11 = 0x7A,
	F12 = 0x7B,
	F13 = 0x7C,
	F14 = 0x7D,
	F15 = 0x7E,
	F16 = 0x7F,
	F17 = 0x80,
	F18 = 0x81,
	F19 = 0x82,
	F20 = 0x83,
}
