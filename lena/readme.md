# Lena Documentation v0.0.2

## Installation

On most platforms, you need no other third-party dependencies to use Lena than the Odin compiler. Follow the instructions to [install Odin for your platform here](https://odin-lang.org/docs/install).

> [!NOTE]
> - On macOS, the [homebrew](https://brew.sh) package manager makes installing Odin absolutely trivial.
> - On Linux, you'll need to install [SDL3](https://libsdl.org), which can usually be done through a package manager for your distro of choice.

Once you have Odin running, clone this repository. You can vendor a new copy of the Lena package into your game's code and hack away at it, or you can place a copy somewhere central on your system and to link to it via the compiler during builds:

```odin
odin build mygame.odin -file -collection:shared="/path/to/lena/repo"
```

This lets you reference Lena like so:

```odin
import "shared:lena"
```

## Contents

<!-- MarkdownTOC autolink=true -->

- [Some High-Level Concepts](#some-high-level-concepts)
	- [Getting Started](#getting-started)
	- [A Note on Memory](#a-note-on-memory)
	- [Graphics Overview](#graphics-overview)
		- [Drawing Modes](#drawing-modes)
		- [MASK](#mask)
		- [SHIFT](#shift)
		- [BLEND](#blend)
		- [LOCK_ALPHA](#lock_alpha)
	- [Audio Overview](#audio-overview)
	- [Drawing and Formatting Text](#drawing-and-formatting-text)
	- [Asset Formats](#asset-formats)
		- [Image Assets](#image-assets)
		- [Audio Assets](#audio-assets)
	- [Asset Packaging](#asset-packaging)
- [Constants](#constants)
	- [Version](#version)
	- [Platform Booleans](#platform-booleans)
	- [PALETTE_SIZE](#palette_size)
	- [BLEND_PALETTE_SIZE](#blend_palette_size)
	- [CHANNEL_COUNT](#channel_count)
	- [SAMPLE_RATE](#sample_rate)
	- [Font Sizing](#font-sizing)
	- [FPS](#fps)
	- [WASM Constants](#wasm-constants)
- [Types](#types)
	- [Image](#image)
	- [Rect](#rect)
	- [Startup_Flags](#startup_flags)
	- [Draw_Flags](#draw_flags)
		- [MASK](#mask-1)
		- [SHIFT](#shift-1)
		- [BLEND](#blend-1)
		- [LOCK_ALPHA](#lock_alpha-1)
	- [Context](#context)
	- [Mouse](#mouse)
	- [Key](#key)
- [Procedures](#procedures)
	- [init](#init)
	- [destroy](#destroy)
	- [quit](#quit)
	- [step](#step)
	- [show_window](#show_window)
	- [still_running](#still_running)
	- [clear_screen](#clear_screen)
	- [get_context](#get_context)
	- [get_screen](#get_screen)
	- [set_title](#set_title)
	- [has_focus](#has_focus)
	- [toggle_cursor](#toggle_cursor)
	- [toggle_fullscreen](#toggle_fullscreen)
	- [get_cursor](#get_cursor)
	- [key_held](#key_held)
	- [key_pressed](#key_pressed)
	- [key_released](#key_released)
	- [mouse_held](#mouse_held)
	- [mouse_pressed](#mouse_pressed)
	- [mouse_released](#mouse_released)
	- [play_sound](#play_sound)
	- [clear_sounds](#clear_sounds)
	- [create_image](#create_image)
	- [create_image_from_png](#create_image_from_png)
	- [clear_image](#clear_image)
	- [destroy_image](#destroy_image)
	- [default_palette](#default_palette)
	- [default_blend_palette](#default_blend_palette)
	- [set_palette](#set_palette)
	- [set_blend_palette](#set_blend_palette)
	- [set_blend_palette_pair](#set_blend_palette_pair)
	- [set_draw_state](#set_draw_state)
	- [set_window_background](#set_window_background)
	- [set_alpha_index](#set_alpha_index)
	- [set_mask_color](#set_mask_color)
	- [set_palette_shift](#set_palette_shift)
	- [set_clip_rect](#set_clip_rect)
	- [set_text_color](#set_text_color)
	- [set_bold_color](#set_bold_color)
	- [draw_image](#draw_image)
	- [draw_image_to_image](#draw_image_to_image)
	- [draw_tile](#draw_tile)
	- [draw_tile_to_image](#draw_tile_to_image)
	- [draw_image_scaled](#draw_image_scaled)
	- [draw_image_to_image_scaled](#draw_image_to_image_scaled)
	- [draw_line](#draw_line)
	- [draw_line_to_image](#draw_line_to_image)
	- [draw_rect](#draw_rect)
	- [draw_rect_to_image](#draw_rect_to_image)
	- [draw_circle](#draw_circle)
	- [draw_circle_to_image](#draw_circle_to_image)
	- [draw_text](#draw_text)
	- [draw_text_to_image](#draw_text_to_image)
	- [draw_typewriter_text](#draw_typewriter_text)
	- [draw_typewriter_text_on_image](#draw_typewriter_text_on_image)
	- [skip_typewriter](#skip_typewriter)
	- [get_glyph](#get_glyph)
	- [set_pixel](#set_pixel)
	- [set_pixel_on_image](#set_pixel_on_image)
	- [get_pixel](#get_pixel)
	- [get_pixel_on_image](#get_pixel_on_image)
	- [get_intersect](#get_intersect)
	- [is_inside](#is_inside)
	- [is_overlapped](#is_overlapped)
	- [szudzik_pair](#szudzik_pair)

<!-- /MarkdownTOC -->

## Some High-Level Concepts

### Getting Started

Lena is designed to be dead-simple to get started with. Once your compiler is up and running, you can create a working foundation to begin building a game in just a few lines:

```odin
package main

import "shared:lena"

main :: proc() {
    lena.init("Title", 128, 128)
    defer lena.destroy()

    for delta_time in lena.step() {
        lena.clear_screen(9)
        lena.draw_text("Hello, |world|!", 10, 10)
    }
}
```

You can compile this with:

```
odin build hello.odin -file -collection:shared="/path/to/lena/repo"
```

You should also take a look at the `demo.odin` in this repository for a more complex but still easy to follow example showing a handful of Lena's features in context.

### A Note on Memory

If you're familiar with Odin, you'll know that its implicit `context` structure, which is usually passed to every procedure, holds two allocators: `context.allocator` and `context.temp_allocator`, with the latter usually being a scratch allocator expected to be used for small one-off operations that are regularly freed en-masse.

Lena uses this system as intended, with things like asset loading using `context.allocator` to store the result, but making use of `context.temp_allocator` during transient operations that need to be discarded, like decompressing a loaded PNG while creating an `Image`.

> [!IMPORTANT]
> Lena enforces this by adopting the `context.temp_allocator` as a per-frame allocator and *automatically frees it at the end of each frame!*
>
>  This merely codifies the intended behaviour by the Odin developers for the use of `context.temp_allocator`: idiomatic Odin programmers will know this already, but it's worth being aware of if you're new to the language.
> If you're *not* familiar with this, you should crack open the [Odin documentation](https://odin-lang.org/docs/overview/) and read away, especially the [context section](https://odin-lang.org/docs/overview/#implicit-context-system).

You can still override both allocators at the context level and all relevant Lena procedures have an optional allocator parameter, much like any other Odin code you've read before. You should feel free to use the `context.temp_allocator` in your game code for any per-frame operations you need.

Lena simply expects the memory that `init` requests to exist for its whole lifetime (don't rug-pull it!) and the `context.temp_allocator` to be a scratch/arena/ring-buffer that it can reset/free entirely every frame.

### Graphics Overview

Lena comes with a default palette to get up and running, which is 32 colours. You can adjust the number of palette entries at compile-time by modifying the [`PALETTE_SIZE`](#palette_size) constant, but you'll always have to supply your own palette if the default is changed.

```odin
PALETTE :: [lena.PALETTE_SIZE]u32{
	0xff0d0b0d,  // ff       0d0b0d
	0xfffff8e1,  // ^ unused ^ rgb hex code
	...
}

lena.set_palette(PALETTE)
```

Note that the alpha byte in these `u32` colours does nothing here because Lena doesn't perform traditional alpha blending.

One of the indices of your palette must be chosen to use as an alpha (transparent) colour while drawing images. By default, of course, it's the `0` index. You can set it on the fly:

```odin
lena.set_alpha_index(1)
```

Note that the Lena 'backbuffer', the actual screen of the game, cannot be transparent. If you clear the screen to the alpha index, it will still be drawn as the palette colour of that index at the end of the frame.

#### Drawing Modes

Lena comes with a number of drawing modes for doing interesting things with palettised graphics. These modes are all driven by the drawing state defined by `set_draw_state`.

```odin
Draw_Flag :: enum u8 {
	MASK,
	SHIFT,
	BLEND,
	LOCK_ALPHA,
}
Draw_Flags :: bit_set[Draw_Flag; u8]

set_draw_state :: proc (flags: Draw_Flags = {})
```

These drawing flags modify the way in which drawing procedures operate: with the palette shifted, blitting alternate colours based on the blend palette or locking the alpha channel of the destination image. All of the flags can be used in conjunction with one another. Many combinations of effects are possible by modifying and manipulating data cleverly between different draw calls, as well as constructing elements on the fly on separate images before drawing them to the screen.

```odin
lena.set_draw_state({.LOCK_ALPHA, .BLEND})
```

#### MASK

`MASK` draws a single colour in place of any non-alpha colours, turning a full-colour sprite into a single-colour silhouette.

You might use this to create a shadow version of an existing sprite:

```odin
draw_dude :: proc(dude: ^Dude) {
	lena.set_mask_color(10)
	lena.set_draw_state({.MASK})
	lena.draw_image(dude.sprite, dude.x + 1, dude.y - 1)

	lena.set_draw_state()
	lena.draw_image(dude.sprite, dude.x, dude.y)
}
```

#### SHIFT

`SHIFT` adjusts subsequently drawn colours to higher palette indices. The operation wraps to the length of the palette to enable downshifting: just go over the top.

```odin
// all colours are now ten indices higher
lena.set_palette_shift(10)

// draw stuff with funky colours
lena.draw_image(...)
```

#### BLEND

`BLEND` causes colours to be sampled via the blend palette. Lena does **not** have complex blending modes like multiplication, screening or opacity. Instead, you can art-direct the interactions between colours by specifying what the resulting palette index should be when two colours meet.

```odin
lena.set_blend_palette_pair(1, 2, 3)
lena.set_draw_state({.BLEND})
// draw something
```

The palette pair above means that when the colour `1` is drawn on top of `2`, we replace it with `3`.

The `BLEND` mode allows you to create interesting interactions between colours for all sorts of artistic effects: if a blue shadow is drawn over the yellow of a sprite, replace it with orange tone. If a colour is drawn over itself, flip it to a complimentary colour to create a strong outline. Create a sprite whose outline is drawn in a different colour in the editor, but that only shows up when the player enters a cave.

#### LOCK_ALPHA

`LOCK_ALPHA` causes drawing procedures to preserve the alpha of the destination image, only blitting the incoming data onto already filled pixels.

The alpha index is still defined by the current alpha index, which can be changed on the fly for more complex effects. By temporarily 'misusing' the alpha index, you can treat `LOCK_ALPHA` like an inverse chroma-key/green-screen.

In the same way, alpha locking can still be used for compositing on the game's backbuffer, but again, any 'transparent' pixels are always drawn to the screen in their actual palette colour at the end of each frame.

### Audio Overview

The audio subsystem in Lena is purposefully minimal. It consists of exactly two procedures:

- `play_sound`
- `clear_sounds`

`play_sound` just accepts a blob of audio data as the first and only non-optional argument:

```odin
BEEP :: #load("beep.ogg")

main :: proc() {
	lena.play_sound(BEEP)
}
```

You can play any sound ad-hoc at any time, and Lena will simply mix it into the existing soundscape. Additional, named arguments to `play_sound` provide more complex functionality:

```odin
play_sound :: proc(blob: []byte, loop: bool = false, volume: f64 = 1, group: u8 = 0) -> bool {...}
```

- `loop: bool` — select whether the sound will loop indefinitely and stay alive in the mixer.
- `volume: f64` — set the lifetime volume of this sound, where 1 is the file's original volume and 0 is silent.
- `group: u8` — assign this sound to a specific internal group for manipulation later.

There are 15 available groups, from 1-15 inclusive. You might assign one group for music, one for sound effects, etc. Because these three parameters are optional, with default values, you can easily access them with Odin's syntactic sugar:

```odin
lena.play_sound(BEEP, group = 1)
```

The usefulness of grouping sounds comes into play with the `clear_sounds` procedure. To begin, calling it without argument will stop all sounds in the entire mixer instantly:

```odin
lena.clear_sounds()
```

You can also select and clear only the sounds in a specific group:

```odin
lena.clear_sounds(group = 1)
```

Using group `0` here will affect all sounds.

You can also add a fade, in seconds, to the clear operation. This example will fade and clean up every sound currently playing in the mixer:

```odin
lena.clear_sounds(with_fade = 2)
```

Or you can mix and match them:

```odin
MUSIC :: 8
lena.clear_sounds(group = MUSIC, with_fade = 3)
```

### Drawing and Formatting Text

The text drawing procedures in Lena are designed to offer a bunch of useful effects for storytelling.

```odin
draw_text :: (t: string, x, y: int, wrap_width: int = 0, left_margin: int = -1) -> (int, int) {...}
```

All of Lena's text drawing procedures resemble the base one in terms of parameter layout and functionality.  `t`, `x` and `y` are self-explanatory, so we'll skip to the two parameters with default behaviours.

- `wrap_width` specifies the distance in pixels from `x` before the string should wrap. If `wrap_width` is zero or not specified, the string will wrap at the edge of the screen or the target image.
- `left_margin`, if specified, overrides the `x` position as the point where a new line begins. This is **not** relative: it's a second absolute `x` coordinate.

`left_margin` may seem like an odd choice, but it allows you to do things like paragraph indentation and, combined with the return value of another `draw_text` call, can be used to construct a uniform 'text box' of many strings without needing to pre-compose a data structure:

```odin
LEFT_MARGIN :: 10

lena.set_draw_state()
nx, ny := lena.draw_text("The start ", LEFT_MARGIN, 10)

lena.set_draw_state({.BLEND})
lena.draw_text("of something new...", nx, ny, left_margin = LEFT_MARGIN)
```

This string will flow continuously as if it was drawn in a single call, by passing the 'final position' of the first call to the coordinates of the next one, then forcing the `left_margin` to match.

In line with this same philosophy, Lena's text drawing also uses a simple Markdown-ish syntax for effects internal to a single string. There are also some state settings specifically for text: `set_text_color` and `set_bold_color` allow you to set the two palette indices a single text draw call can make use of.

You can use an asterisk `*` in the string to switch to the bold colour, as well as a pipe character `|` to make text wiggle. You can escape these characters too.

```
This will *become the bold colour* and this will not be.
This is a |wiggly| word.
This won't \|wiggle\|. This will draw \\backslashes\\.
```

Lena also provides a stateless typewriter mode too, in the form:

```odin
draw_typewriter_text :: proc(t: string, x, y: int, wrap_width: int = 0, left_margin: int = -1) -> (int, int) {...}
```

The only caveat to typewriter mode is that you may only draw one typewriter string at a time! Different strings will reset one another's calls. Lena also provides a `skip_typewriter` procedure so you can give your players a fast-forward button.

### Asset Formats

Lena requires its images and audio files to be in specific formats with specific underlying properties. These aren't difficult requirements, but they may require some amount of research and setting up some tools to achieve.

#### Image Assets

Lena's software graphics are palette-driven, so images loaded with `create_image_from_png` must be PNGs saved in an indexed palette mode. You can use programs like Aseprite or GrafX2 to create PNGs with palettes. Apps like Affinity Photo and Adobe Photoshop can also do this, but the former are recommended for being focused on pixel art and palette-based graphics.

You can define the size and colours of your palette at compile-time if Lena's default 32 colours don't appeal to you, using the [`PALETTE_SIZE`](#palette_size) constant. You can also get a copy of Lena's default palette [for your app of choice here](https://lospec.com/palette-list/colordome-32), to save you transcribing it from the source code.

#### Audio Assets

Lena's audio pipeline also expects assets to be in a certain format: sounds should be Ogg Vorbis or MP3 with a uniform sample rate and channel count across all of them. The exact settings that Lena expects can be globally modified at compile-time:

- [`SAMPLE_RATE`](#sample_rate)
- [`CHANNEL_COUNT`](#channel_count)

Lena's default sample rate is 44,100Hz, which is the 'standard' sample rate for most digital audio. For instance, most MP3 music files and game audio library sounds are delivered in 44.1KHz.

Lena's default channel count is 2, or stereo. You can also change it to 1, for mono sounds.

If you're not creating or commissioning original sounds and music, you'll need to convert purchased library sounds to Ogg Vorbis or MP3 and downsample them to 44,100 (or your chosen sample rate). You can easily use tools like Audacity or ffmpeg to do this:

```sh
ffmpeg -i source.wav -ar 44100 -ac 2 -b:a 64k output.mp3
ffmpeg -i source.wav -c:a libvorbis -ar 44100 -ac 2 -b:a 64k output.ogg
```

These commands specify files with a relevant sample rate, two channels and a bit rate of 64K, which is a 'mid-quality' data rate (though if you're not using critical listening hardware, you most likely can't tell). Lena is indifferent to bit rates, so you can adjust this value to decide what works for your project in terms of listening quality vs distribution size.

> [!WARNING]
> In WASM builds, Lena relies on the browser's `AudioContext` to play back sounds. All major browsers support Ogg Vorbis playback *except* macOS's Safari, which only started recently with version 18 on macOS 15 *Sequoia*. If supporting Safari is an essential requirement, you should encode your audio in MP3. For all other purposes, you should prefer Ogg Vorbis' better file size to quality ratio.

### Asset Packaging

Odin provides two really neat compile-time procedures named `#load` and `#load_directory`, which will bundle external files directly into a compiled binary. You can [read about those here](https://odin-lang.org/docs/overview/#loadstring-path-or-loadstring-path-type).

For a large game in a modern resolution, the size of assets would render this unreasonable, but for a Lena game, which likely only has a handful of sprite sheets and audio files (even for a sprawling RPG), this is a no-brainer solution for quick packaging and distribution, like in a game-jam.

Here's an example of this workflow. Because audio files are decoded in real-time (and you can't meaningfully modify their data directly, which *is* useful with Lena sprite images), there is no intermediate conversion step like with PNGs. It's also trivial to use the `core:fmt` package to print out a loaded image and paste it back into the source code as a structure, which may be a solution for some projects.

```odin
VISUALS  :: #load("spritesheet.png")
AMBIANCE :: #load("ambiance.ogg")

main :: proc() {
	visuals := lena.create_image_from_png(VISUALS)
	defer lena.destroy_image(visuals)

	lena.play_sound(AMBIANCE)
	lena.draw_image(visuals, 10, 10)
}
```

Using `#load_directory` generates a data structure which can be trivially leveraged to write a [wrapper to invoke assets statelessly](https://www.rfleury.com/p/untangling-lifetimes-the-arena-allocator), but this is an exercise left to the reader. Also, be aware that you can pass any allocator you like to `create_image` and similar, removing the need to call `destroy_image` on each one individually. If you're new to Odin, the `core:mem` package comes with a batteries-included arena allocator!

## Constants

### Version

```odin
MAJOR :: 0
MINOR :: 0
PATCH :: 0
```

Lena follows semantic versioning: `MAJOR` refers to incompatible, breaking changes. These will be grouped into as few releases as possible. `MINOR` refers to backward-compatible changes, meaning updating to it should not break any game code written for a previous version with the same `MAJOR` value. `PATCH` is for bugs.

### Platform Booleans

```odin
IS_WINDOWS :: true
IS_DARWIN  :: false
IS_LINUX   :: false
IS_WEB     :: false
IS_SDL     :: false
```

Convenience values to make easy `when` statements against the platform your game is built on.  Their trueness is not mutually-exclusive: `IS_SDL` will be true alongside `IS_LINUX` due to the Linux build running on SDL3.

### PALETTE_SIZE

```odin
PALETTE_SIZE :: #config(LENA_PALETTE, 32)
```

Defines how many colours are available in Lena's palette, which must be 1-256 inclusive.

```sh
odin build -define:LENA_PALETTE=32
```

### BLEND_PALETTE_SIZE

```odin
BLEND_PALETTE_SIZE :: PALETTE_SIZE * PALETTE_SIZE
```

### CHANNEL_COUNT

```odin
CHANNEL_COUNT :: #config(LENA_CHANNEL_COUNT, 2)
```

Defines the number of channels in the audio files the audio engine will receive while running. The default of `2` means stereo.

### SAMPLE_RATE

```odin
SAMPLE_RATE :: #config(LENA_SAMPLE_RATE, 44_100)
```

Defines the sample count of the audio files the audio engine will receive while running. The default is a standard rate for digital audio.

### Font Sizing

```odin
FONT_WIDTH  :: 5
FONT_HEIGHT :: 11
```

Utility values providing the glyph (single character) size of Lena's default font, Scientifica: any `Image` returned by `get_glyph` will be this size.

### FPS

```odin
FPS_AUTO :: -1
FPS_INF  :: 0
FPS_60   :: 60
FPS_144  :: 144
```

A small set of sensible constants to use for FPS targets. `FPS_AUTO` will request the user's monitor refresh rate and target it, acting similarly to VSync (without actual hardware synchronisation), but you can pass any target value you like to `init`.

There are some caveats on some platforms in how they react to the requested values:

- WebAssembly games are driven by the browser, so the requested frame rate is entirely ignored.
- The Linux build relies on SDL3 and will only accept `FPS_INF` or `FPS_AUTO`. Any other value will be coerced into `FPS_AUTO`.

### WASM Constants

```odin
WASM_CANVAS     :: "lena-canvas"
WASM_BACKGROUND :: "lena-background"
```

These are only available on WASM targets and provide the DOM IDs for page elements that Lena attaches to.

## Types

### Image

```odin
Image :: struct {
	w, h:   int,
	pixels: []u8,
}
```

Lena's image representation.  Each pixel byte represents a palette index, which is only looked up and expanded when Lena presents to the screen at the end of a frame.  Images contain no colour information in of themselves.

**Related Procedures**

- [create_image_from_png](#create_image_from_png)
- [create_image](#create_image)
- [clear_image](#clear_image)
- [destroy_image](#destroy_image)
- [draw_image](#draw_image)
- [draw_image_to_image](#draw_image_to_image)
- [draw_tile](#draw_tile)
- [draw_tile_to_image](#draw_tile_to_image)
- [draw_image_scaled](#draw_image_scaled)
- [draw_image_to_image_scaled](#draw_image_to_image_scaled)
- [get_glyph](#get_glyph)

### Rect

```odin
Rect :: struct {
	x, y, w, h: int,
}
```

**Related Procedures**

- [get_intersect](#get_intersect)
- [is_inside](#is_inside)
- [is_overlapped](#is_overlapped)
- [draw_rect](#draw_rect)
- [draw_rect_to_image](#draw_rect_to_image)
- [draw_tile](#draw_tile)
- [draw_tile_to_image](#draw_tile_to_image)
- [draw_image_scaled](#draw_image_scaled)
- [draw_image_to_image_scaled](#draw_image_to_image_scaled)

### Startup_Flags

```odin
Startup_Flag :: enum u8 {
	FULLSCREEN,
	HIDE_CURSOR,
	HIDE_WINDOW,
}

Startup_Flags :: bit_set[Startup_Flag]
```

These flags are used to define the startup state for Lena. The fullscreen and cursor states may be toggled at any time with `toggle_xx` calls. The window may not be toggled: `HIDE_WINDOW` simply defers the window's start-up presentation until `show_window` is called.

**Related Procedures**

- [toggle_cursor](#toggle_cursor)
- [toggle_fullscreen](#toggle_fullscreen)
- [show_window](#show_window)

### Draw_Flags

```odin
Draw_Flag :: enum u8 {
	MASK,
	SHIFT,
	BLEND,
	LOCK_ALPHA,
}

Draw_Flags :: bit_set[Draw_Flag]
```

These draw state flags modify the way in which drawing procedures operate: with the palette shifted, blitting alternate colours based on the blend palette or locking the alpha channel of the destination image.

#### MASK

`MASK` draws a single colour in place of any non-alpha colours, turning a full-colour sprite into a single-colour silhouette.

#### SHIFT

`SHIFT` adjusts subsequently drawn colours to higher palette indices.  The operation wraps to the length of the palette to enable downshifting.

#### BLEND

`BLEND` causes colours to be sampled via the blend palette. Lena does **not** have complex blending modes like multiplication or screening. Instead, you can art-direct the interactions between colours by specifying what the resulting palette index should be when two colours meet.

#### LOCK_ALPHA

`LOCK_ALPHA` causes every subsequent drawing procedure to avoid overwriting any transparent pixels on the destination image.  What is considered a transparent pixel is controlled by the current alpha index, which can be changed independently for more complex effects.

**Related Procedures**

- [set_draw_state](#set_draw_state)
- [set_alpha_index](#set_alpha_index)
- [set_mask_color](#set_mask_color)
- [set_palette_shift](#set_palette_shift)
- [set_blend_palette_pair](#set_blend_palette_pair)

### Context

```odin
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
```

The `Context` structure is the backing data structure for the entire Lena program. All shared state is co-located here. While this structure can be modified directly, it is recommended to use the relevant procedures to edit Lena's state: some of them perform additional actions on different platforms that are better handled internally.

**Related Procedures**

- [init](#init)
- [get_context](#get_context)

### Mouse

```odin
Mouse :: enum u8 {
	UNKNOWN = 0,
	LEFT    = 1,
	RIGHT   = 2,
	MIDDLE  = 3,
}
```

> [!WARNING]
> `MIDDLE` is not recognised on macOS.

**Related Procedures**

- [mouse_held](#mouse_held)
- [mouse_pressed](#mouse_pressed)
- [mouse_released](#mouse_released)

### Key

```odin
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
```

Lena only provides the keycodes that are supported by basic, non-extended platform APIs. This means no function keys above F20 or specialised keys like Insert: macOS has no concept of an Insert key.

**Related Procedures**

- [key_held](#key_held)
- [key_pressed](#key_pressed)
- [key_released](#key_released)

## Procedures

### init

```odin
init :: proc(title: string, w, h: int, target_framerate: i64 = FPS_AUTO, flags: Startup_Flags = {}, backing_allocator := context.allocator) -> ^Context {...}
```

Initialises Lena and opens a window. Optionally returns a pointer to the internal context structure; you're not required to keep this handle, it's simply there for advanced users to directly manipulate Lena's state if they wish.

- You must call `init` before you call `step` or attempt to draw anything to the screen.
- `init` allocates a 1MB block of memory to partition out to its internal state. This memory is expected to be permanently available for the remainder of the program, or until [`destroy`](#destroy) is called, so be conscious of the context and allocator used during initialisation.

**Related Types**

- [Context](#context)
- [Startup_Flags](#startup_flags)

### destroy

```odin
destroy :: proc() {...}
```

Closes the window and cleans up the program internals.

### quit

```odin
quit :: proc() {...}
```

Call this from anywhere, at any time, to exit a Lena game. This procedure will breaks the `step` loop, but **does not trigger** `destroy`.

### step

```odin
step :: proc() -> (delta_time: f64, ok: bool) {...}
```

Manages the main loop. Note that in addition to handling the game's timing and updating Lena's internal state, `step` calls `free_all` on the `context.temp_allocator`, freeing your per-frame allocations automatically.

```odin
for delta_time in lena.step() {
	// game code
}
```

### show_window

```odin
show_window :: proc() {...}
```

Shows the window.  Used in conjunction with `HIDE_WINDOW`.

### still_running

```odin
still_running :: proc() -> bool {...}
```

A utility function for WASM builds.  See the `wasm` directory `readme` for examples of usage.

### clear_screen

```odin
clear_screen :: proc(c: u8 = 0) {...}
```

Clears the game's backbuffer to a specific colour.

### get_context

```odin
get_context :: proc() -> ^Context {...}
```

Fetches a pointer to the internal `Context` structure.

### get_screen

```odin
get_screen :: proc() -> Image {...}
```

Fetches a handle to the screen's bitmap.

### set_title

```odin
set_title :: proc(text: string) {...}
```

### has_focus

```odin
has_focus :: proc() -> bool {...}
```

Reports whether the Lena window is the foreground/active window on the desktop.

### toggle_cursor

```odin
toggle_cursor :: proc() {...}
```

Enables or disables the native cursor. Set the initial state with `.HIDE_CURSOR`.

### toggle_fullscreen

```odin
toggle_fullscreen :: proc() {...}
```

Toggles fullscreen behaviour. Uses a borderless window on Windows and Linux, but uses native spaces on macOS. Set the initial state with `.FULLSCREEN`.

### get_cursor

```odin
get_cursor :: proc() -> (mx: int, my: int) {...}
```

Retrieves the cursor location, pre-adjusted to the coordinates of the game screen.

### key_held

```odin
key_held :: proc(key: Key) -> bool {...}
```

Continuously reports whether a key is being held down.

**Related Types**

- [Key](#key)

### key_pressed

```odin
key_pressed :: proc(key: Key) -> bool {...}
```

Reports whether a key was just pressed on the current frame. Will not report again until the key has been released.

**Related Types**

- [Key](#key)

### key_released

```odin
key_released :: proc(key: Key) -> bool {...}
```

Reports whether a key was just released on the current frame. Will not report again until the key has been pressed.

**Related Types**

- [Key](#key)

### mouse_held

```odin
mouse_held :: proc(button: Mouse) -> bool {...}
```

Continuously reports whether a mouse button is being held down.

**Related Types**

- [Mouse](#mouse)

### mouse_pressed

```odin
mouse_pressed :: proc(button: Mouse) -> bool {...}
```

Reports whether a mouse button was just pressed on the current frame. Will not report again until the button has been released.

**Related Types**

- [Mouse](#mouse)

### mouse_released

```odin
mouse_released :: proc(button: Mouse) -> bool {...}
```

Reports whether a mouse button was just released on the current frame. Will not report again until the button has been pressed.

**Related Types**

- [Mouse](#mouse)

### play_sound

```odin
play_sound :: proc(blob: []byte, volume: f64 = 1, loop := false, group: u8 = 0) -> bool {...}
```

Adds a sound to the mixer with the specified attributes. `blob` is expected to be an MP3 or Ogg Vorbis file whose sample rate and channel count match [`SAMPLE_RATE`](#sample_rate) and [`CHANNEL_COUNT`](#channel_count).

Optionally sets the sound to loop forever (until cleared manually) or assigns it to a group for later manipulation.

### clear_sounds

```odin
clear_sounds :: proc(group: u8 = 0, with_fade: f64 = 0) {...}
```

Halts the mixer and cleans up all the sounds currently being played back. Can optionally target only the sounds in a specific group and/or can set them to fade out over a time frame given in seconds.

> [!NOTE]
> Calling `play_sound` and reviving a group that's currently fading out will cause all of the active sounds in that group to resume playing at their original volumes. If any were looping, they will continue to play indefinitely.

### create_image

```odin
create_image :: proc(w, h: int, allocator := context.allocator) -> Image {...}
```

**Related Types**

- [Image](#image)

### create_image_from_png

```odin
create_image_from_png :: proc(blob: []u8, allocator := context.allocator) -> Image {...}
```

> [!WARNING]
> `create_image_from_png` expects PNG files which are *palettised*. This is because it converts the palette index information directly into the `Image` structure and does not consider the PNG's own palette at all.

**Example**

```odin
IMAGE_BYTES :: #load("sprite.png")
sprite := lena.create_image_from_png(IMAGE_BYTES)
defer lena.destroy_image(sprite)
```

**Related Types**

- [Image](#image)

### clear_image

```odin
clear_image :: proc(source: Image, c: u8 = 0) {...}
```

Clears an image entirely to the given palette index. Used for clearing images being used as secondary buffers, and is the underlying procedure *actually* being used in [`clear_screen`](#clear_screen).

### destroy_image

```odin
destroy_image :: proc(img: Image) {...}
```

Frees the image's underlying pixel array.

**Related Types**

- [Image](#image)

### default_palette

```odin
default_palette :: proc() -> [32]u32 {...}
```

Retrieves a copy of the default palette. The palette is not applied on startup if `PALETTE_SIZE` is changed.

### default_blend_palette

```odin
default_blend_palette :: proc() -> [BLEND_PALETTE_SIZE]u8 {...}
```

Generates a new default blend palette. Each entry is mapped such that for every pair of colours, they will blend as if being drawn normally. Generating a new blend palette with this procedure allows you to only populate the colours you wish to *change* from default behaviour, rather than having to set a novel interaction for every single entry.

**Example**

You can build a blend palette from scratch like so:

```odin
blend_palette := lena.default_blend_palette()

// A draw over B results in C
blend_palette[lena.szudzik_pair(1, 4)] = 5
blend_palette[lena.szudzik_pair(2, 4)] = 7

lena.set_blend_palette(blend_palette)
```

**Related Procedures**

- [szudzik_pair](#szudzik_pair)
- [set_blend_palette](#set_blend_palette)

### set_palette

```odin
set_palette :: proc(colors: [PALETTE_SIZE]u8) {...}
```

Registers a new palette as the current Lena state.

### set_blend_palette

```odin
set_blend_palette :: proc(colors: [BLEND_PALETTE_SIZE]u8) {...}
```

Registers a blend palette as the current Lena state.

### set_blend_palette_pair

```odin
set_blend_palette_pair :: proc(src, dst, result: u8) {...}
```

Modifies Lena's default blend palette, which you can start modifying straight away using this procedure.

### set_draw_state

```odin
set_draw_state :: proc(flags: Draw_Flags = {}) {...}
```

Sets the current drawing state, which affects how all drawing procedures mix colours. For the clearest code legibility, Lena enforces that the state must be wholly set each time:

```odin
lena.set_draw_state({.BLEND, .LOCK_ALPHA})
```

**Related Types**

- [Draw_Flags](#draw_flags)

### set_window_background

```odin
set_window_background :: proc(color: u8) {...}
```

Sets the background palette index of the window *behind* the game's backbuffer.

### set_alpha_index

```odin
set_alpha_index :: proc(alpha: u8) {...}
```

Set the palette index to be considered transparent by drawing routines.

### set_mask_color

```odin
set_mask_color :: proc(color: u8) {...}
```

Sets a mask color to be applied by the `MASK` draw state. Does not apply to `draw_text` and its related procedures: see `set_text_color` instead.

### set_palette_shift

```odin
set_palette_shift :: proc(offset: u8) {...}
```

Sets a palette offset to use with the `SHIFT` draw state.

### set_clip_rect

```odin
set_clip_rect :: proc(rect: Rect = {}) {...}
```

Sets a clipping rectangle for subsequent drawing operations.  Also works for draw-to-image operations.

### set_text_color

```odin
set_text_color :: proc(color: u8) {...}
```

Sets the colour used by `draw_text` and its related procedures.

### set_bold_color

```odin
set_bold_color :: proc(color: u8) {...}
```

Sets the colour used by `draw_text` and its related procedures for characters inside the `*bold*` syntax.

### draw_image

```odin
draw_image :: proc(source: Image, x, y: int) {...}
```

Draws an image to the screen.

### draw_image_to_image

```odin
draw_image_to_image :: proc(source, target: Image, x, y: int) {...}
```

Copies an image to another image.

### draw_tile

```odin
draw_tile :: proc(source: Image, r: Rect, x, y: int) {...}
```

Draws a sub-rect of an image to the screen.

### draw_tile_to_image

```odin
draw_tile_to_image :: proc(source, target: Image, src:
Rect, x, y: int) {...}
```

Copies a sub-rect of an image to another image.

### draw_image_scaled

```odin
draw_image_scaled :: proc(source: Image, src, dst: Rect) {...}
```

Draws an image to the screen with arbitrary source and destination rects, which may be skewed or scaled.

### draw_image_to_image_scaled

```odin
draw_image_to_image_scaled :: proc(source, target: Image, src, dst: Rect) {...}
```

Copies an image to another image with arbitrary source and destination rects, which may be skewed or scaled.

### draw_line

```odin
draw_line :: proc(x1, y1, x2, y2: int, color: u8) {...}
```

Draws a line between two points.

### draw_line_to_image

```odin
draw_line :: proc(target: Image, x1, y1, x2, y2: int, color: u8) {...}
```

Draws a line between two points onto the target image.

### draw_rect

```odin
draw_rect :: proc(r: Rect, color: u8, filled: bool) {...}
```

Draws a rectangle, either outlined or filled.

**Related Types**

- [Rect](#rect)

### draw_rect_to_image

```odin
draw_rect_to_image :: proc(target: Image, r: Rect, color:
u8, filled: bool) {...}
```

Draws a rectangle, either outlined or filled, to an image.

**Related Types**

- [Rect](#rect)

### draw_circle

```odin
draw_circle :: proc(cx, cy, radius: int, color: u8, filled: bool) {...}
```

Draw a circle, either outlined or filled.

### draw_circle_to_image

```odin
draw_circle_to_image :: proc(target: Image, cx, cy, radius: int, color: u8, filled: bool) {...}
```

Draw a circle, either outlined or filled, to an image.

### draw_text

```odin
draw_text :: proc(t: string, x, y: int, wrap_width: int-> (int, int)  =
0, left_margin: int = -1) {...}
```

Draws a string to the screen.

- A `wrap_width` of zero, the default value, will cause the text to wrap against the edge of the target image. If you specify any other value, the text will wrap to that regardless of the coordinate origin.
- `left_margin` allows you to override the position to which a wrapped line will return, allowing for certain effects like paragraph indentation. See [Drawing and Formatting Text](#drawing-and-formatting-text) for detailed examples.

All `draw_text*` procedures also return the last character position after completion, which may be passed directly to a subsequent `draw_text*` call to continue the string as if in a single call.

### draw_text_to_image

```odin
draw_text_to_image :: proc(target: Image, t: string, x,-> (int, int)  y:
int, wrap_width: int = 0, left_margin: int = -1) {...}
```

Draws a string to the target image.

### draw_typewriter_text

```odin
draw_typewriter_text :: proc(t: string, x, y: int, wrap_width: int = 0, left_margin: int = -1) -> (int, int) {...}
```

Draws text which will type itself out over time.

> [!WARNING]
> You can only have one typewriter text block active at any given time. You can draw as many normal text boxes as you like, but multiple *typewriters* will result in constant resets to the animation of each.

### draw_typewriter_text_on_image

```odin
draw_typewriter_text_on_image :: proc(t: string, x, y: int, wrap_width: int = 0, left_margin: int = -1) -> (int, int) {...}
```

Draws text which will type itself out over time onto a target image. This may get weird if you don't also clear that image every frame.

### skip_typewriter

```odin
skip_typewriter :: proc() {...}
```

Skips the active typewriter text animation.

### get_glyph

```odin
get_glyph :: proc(r: rune) -> Image {...}
```

Returns an image of the glyph corresponding to the passed rune. Glyphs are generated and stored a dedicated internal arena, which is freed when [`destroy`](#destroy) is called.

### set_pixel

```odin
set_pixel :: proc(x, y: int, color: u8) {...}
```

### set_pixel_on_image

```odin
set_pixel_on_image :: proc(target: Image, x, y: int, color: u8) {...}
```

### get_pixel

```odin
get_pixel :: proc(x, y: int) -> u8 {...}
```

### get_pixel_on_image

```odin
get_pixel_on_image :: proc(target: Image, x, y: int) -> u8 {...}
```

### get_intersect

```odin
get_intersect :: proc(a, b: Rect) -> Rect {...}
```

Gets a `Rect` that corresponds to the overlapping area of two others.

**Related Types**

- [Rect](#rect)

### is_inside

```odin
is_inside :: proc(r: Rect, x, y: int) -> bool {...}
```

Checks whether a 2D coordinate is inside a `Rect`.

**Related Types**

- [Rect](#rect)

### is_overlapped

```odin
is_overlapped :: proc(a, b: Rect) -> bool {...}
```

Checks whether two `Rect` are overlapping.

**Related Types**

- [Rect](#rect)

### szudzik_pair

```odin
szudzik_pair :: proc(a, b: u8) -> u16 {...}
```

Implements the extremely small [Szudzik pairing function](http://szudzik.com/ElegantPairing.pdf), which is how Lena 'hashes' pairs of colours together to store the resulting indices in blend palettes.
