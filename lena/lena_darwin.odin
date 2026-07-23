#+private
#+build darwin
package lena

import "core:math"
import "core:time"
import "base:intrinsics"

import NS "core:sys/darwin/Foundation"

/*
	[On Objective-C Interfacing]

	Throughout this file, there's a mixture of core:sys/darwin
	library types and procedures, custom bindings and
	naked, 'unsafe' uses of objc_send. This is because Odin's
	Cocoa bindings are incomplete, but *also* there is an
	arbitrary limitation within Odin's Objective-C interface that
	class interfaces and methods must be bound within the same
	scope (and for our purposes, the same file). This means that
	where a type is defined in sys/darwin *but not all of its
	methods are available*, we cannot extend them 'correctly'.

	Our choices are to re-declare and re-bind everything we need
	locally (as I have done with NSImage) or to simply nakedly
	pass calls through intrinsics.objc_send. I *should* rebind
	everything for clarity's sake, but certain classes/structures,
	like NSApplication, are so complex that we'd have a few thousand
	lines of code we'd never call on before we even got to any Lena
	source -- adding tremendous complexity to this file for the sake
	of type-safety that we don't need because these calls aren't
	exposed to the game designer's code

	as the Odin Darwin bindings improve to be API-complete, I will
	progressively replace the naked calls with the real versions
*/

objc_send :: intrinsics.objc_send

NEAREST:  ^NS.String
RGBSPACE: ^NS.String

@(objc_class="NSImage")
NSImage :: struct { using _: NS.Object }

@(objc_class="NSImageRep")
NSImageRep :: struct { using _: NS.Object }

@(objc_class="NSBitmapImageRep")
NSBitmapImageRep :: struct { using _: NSImageRep }

@(objc_type=NSImage, objc_name="alloc", objc_is_class_method=true)
NSImage_alloc :: proc() -> ^NSImage {
	return objc_send(^NSImage, NSImage, "alloc")
}

@(objc_type=NSImage, objc_name="initWithSize")
NSImage_initWithSize :: proc(self: ^NSImage, size: NS.Size) -> ^NSImage {
	return objc_send(^NSImage, self, "initWithSize:", size)
}

@(objc_type=NSImage, objc_name="addRepresentation")
NSImage_addRepresentation :: proc(self: ^NSImage, rep: ^NSImageRep) {
	objc_send(nil, self, "addRepresentation:", rep)
}

@(objc_type=NSBitmapImageRep, objc_name="alloc", objc_is_class_method=true)
NSBitmapImageRep_alloc :: proc() -> ^NSBitmapImageRep {
	return objc_send(^NSBitmapImageRep, NSBitmapImageRep, "alloc")
}

@(objc_type=NSBitmapImageRep, objc_name="initWithBitmapData")
NSBitmapImageRep_initWithBitmapData :: proc(self: ^NSBitmapImageRep, planes: rawptr, pixelsWide, pixelsHigh, bitsPerSample, samplesPerPixel: NS.Integer, hasAlpha, isPlanar: NS.BOOL, colorSpaceName: ^NS.String, /*bitmapFormat: u64,*/ bytesPerRow, bitsPerPixel: NS.Integer) -> ^NSBitmapImageRep {
	msg :: "initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:"
	return objc_send(^NSBitmapImageRep, self, msg, planes, pixelsWide, pixelsHigh, bitsPerSample, samplesPerPixel, hasAlpha, isPlanar, colorSpaceName, /*bitmapFormat,*/ bytesPerRow, bitsPerPixel)
}

@(objc_class="NSCursor")
NSCursor :: struct { using _: NS.Object }

@(objc_type=NSCursor, objc_name="hide", objc_is_class_method=true)
NSCursor_hide :: proc() {
	objc_send(nil, NSCursor, "hide")
}

@(objc_type=NSCursor, objc_name="unhide", objc_is_class_method=true)
NSCursor_unhide :: proc() {
	objc_send(nil, NSCursor, "unhide")
}

Platform_Context :: struct {
	nsapp:    ^NS.Application,
	nswindow: ^NS.Window,

	cursor_visible: bool,
	last_window_background: u8,
}

os_init :: proc(title: string) {
	NS.scoped_autoreleasepool()

	ctx.nsapp = NS.Application.sharedApplication()
	ctx.nsapp->setActivationPolicy(.Regular)
	ctx.nsapp->activate()

	settings := NS.WindowStyleMask{
		.Titled,
		.Closable,
		.Miniaturizable,
		.Resizable,
	}

	screen := NS.Screen_mainScreen()

	{
		mon := screen->frame()

		monitor_w := cast(int) mon.width
		monitor_h := cast(int) mon.height

		scale := cast(f32) (monitor_w > monitor_h ? monitor_h / ctx.screen.h : monitor_w / ctx.screen.w) / 5

		ctx.window.w = ctx.screen.w * cast(int) (scale * 4)
		ctx.window.h = ctx.screen.h * cast(int) (scale * 4)

		content := NS.Rect{
			{0, 0},
			{NS.Float(ctx.window.w), NS.Float(ctx.window.h)},
		}

		ctx.nswindow = NS.Window.alloc()->initWithContentRect(content, settings, .Buffered, false)
	}

	wd := NS.window_delegate_register_and_alloc({
		windowWillClose = proc(n: ^NS.Notification) {
			ctx.set_quit = true
		},
		windowShouldClose = proc(sender: ^NS.Window) -> NS.BOOL {
			return !ctx.set_quit
		},
		windowDidResize = proc(n: ^NS.Notification) {
			// hack because ButtonUp events don't fire when releasing
			// a resize, so we just clear all the buttons
			for &state in ctx.mouse_state do state &~= KEY_STATE_HELD
		},
	}, "lena_window_delegate", context)

	ctx.nswindow->setDelegate(wd)
	ctx.nswindow->center()
	ctx.nsapp->finishLaunching()

	NEAREST  = NS.String.alloc()->initWithOdinString("nearest")
	RGBSPACE = NS.String.alloc()->initWithOdinString("NSDeviceRGBColorSpace")

	view := ctx.nswindow->contentView()
	objc_send(nil, view, "setLayerContentsPlacement:", NS.Integer(1)) // scaleProportionallyToFit

	step := ctx.fps
	if step == FPS_AUTO {
		number := objc_send(NS.TimeInterval, screen, "minimumRefreshInterval")
		step = cast(i64) math.ceil(cast(f64) (1 / number))
	}
	if step > 0 {
		ctx.step_time = time.Second / cast(time.Duration) step
	}

	os_set_title(title)
	if .FULLSCREEN in ctx.flags {
		os_update_fullscreen()
	}
}

os_step :: proc() {
	NS.scoped_autoreleasepool()

	if ctx.step_time > 0 {
		time.accurate_sleep(ctx.step_time - time.diff(ctx.prev_time, time.now()))
	}
	ctx.delta_time = time.duration_seconds(time.diff(ctx.prev_time, time.now()))
	ctx.prev_time = time.now()

	bounds := ctx.nswindow->contentView()->bounds()

	ctx.window.w = cast(int) bounds.width
	ctx.window.h = cast(int) bounds.height

	for {
		event := ctx.nsapp->nextEventMatchingMask(NS.EventMaskAny, nil, NS.DefaultRunLoopMode, true)
		if event == nil {
			break
		}

		frame := ctx.nswindow->contentView()->bounds()
		point := objc_send(NS.Point, ctx.nswindow, "mouseLocationOutsideOfEventStream")

		point.y = bounds.height - point.y
		mouse_inside := point.x > 0 && point.y > 0 && point.x < frame.width && point.y < frame.height

		_type := event->type()
		#partial switch _type {
		case .KeyDown:
			code := switch_keys(event->keyCode())
			// macOS helpfully sends multiple keydown events, so we gate it
			if ctx.key_state[code] & KEY_STATE_HELD != KEY_STATE_HELD {
				ctx.key_state[code] = KEY_STATE_HELD | KEY_STATE_PRESSED
			}

			return

		case .KeyUp:
			code := switch_keys(event->keyCode())
			ctx.key_state[code] &= ~KEY_STATE_HELD
			ctx.key_state[code] |=  KEY_STATE_RELEASED
			return

		case .LeftMouseDown, .RightMouseDown:
			if mouse_inside {
				button := 1 if _type == .LeftMouseDown else 2
				ctx.mouse_state[button] = KEY_STATE_HELD | KEY_STATE_PRESSED
			}

		case .LeftMouseUp, .RightMouseUp:
			button := 1 if _type == .LeftMouseUp else 2
			ctx.mouse_state[button] &= ~KEY_STATE_HELD
			ctx.mouse_state[button] |= KEY_STATE_RELEASED

		case .MouseMoved, .LeftMouseDragged, .RightMouseDragged:
			// we manually implement re-showing the cursor beyond
			// the edges of the window
			if mouse_inside && .HIDE_CURSOR in ctx.flags {
				hide_cursor()
			} else {
				show_cursor()
			}

			if mouse_inside || _type != .MouseMoved {
				dimms := adjusted_window_size()

				// we can technically track the window long past
				// the edges all the time, but we only allow it
				// during click-drags to match Windows behaviour
				ctx.mouse_pos.x = (cast(int) point.x - dimms.x) * ctx.screen.w / dimms.w
				ctx.mouse_pos.y = (cast(int) point.y - dimms.y) * ctx.screen.h / dimms.h
			}

		case .MouseEntered:
			ctx.has_focus = true

		case .MouseExited:
			ctx.has_focus = false
		}

		ctx.nsapp->sendEvent(event)
	}
}

os_present :: proc() #no_bounds_check {
	NS.scoped_autoreleasepool()

	if ctx.last_window_background != ctx.window_background {
		color := transmute([4]u8) ctx.palette[ctx.window_background]
		nscolor := NS.Color.colorWithCalibratedRed(cast(NS.Float) color.r / 255, cast(NS.Float) color.g / 255, cast(NS.Float) color.b / 255, 1)
		ctx.nswindow->setBackgroundColor(nscolor)
		ctx.last_window_background = ctx.window_background
	}

	// we *should* just create the image once and continuously
	// write to it but I cannot, for the life of me, get the
	// NSImage to stop caching the NSBitmapImageRep data;
	// so while this hurts performance a bit, it *works*

	imgscale := NS.Size{
		width  = cast(NS.Float) ctx.screen.w,
		height = cast(NS.Float) ctx.screen.h,
	}
	nsimage := NSImage.alloc()->initWithSize(imgscale)

	nsbitmaprep := NSBitmapImageRep.alloc()->initWithBitmapData(
		planes          = &ctx.backbuffer,
		pixelsWide      = cast(NS.Integer) ctx.screen.w,
		pixelsHigh      = cast(NS.Integer) ctx.screen.h,
		bitsPerSample   = 8,
		samplesPerPixel = 4,
		hasAlpha        = true,
		isPlanar        = false,
		colorSpaceName  = RGBSPACE,
		bytesPerRow     = cast(NS.Integer) ctx.screen.w * 4,
		bitsPerPixel    = 32,
	)
	nsimage->addRepresentation(nsbitmaprep)

	layer := ctx.nswindow->contentView()->layer()
	if layer != nil {
		objc_send(nil, layer, "setContents:", nsimage)
		objc_send(nil, layer, "setMagnificationFilter:", NEAREST)
		objc_send(nil, layer, "setNeedsDisplay")
	}

	nsbitmaprep->release()
	nsimage->release()
}

os_show_window :: proc() {
	ctx.nswindow->makeKeyAndOrderFront(nil)
}

os_modify_palette :: proc() {
	for &c in ctx.palette do bgra_swizzle(&c)
}

os_destroy :: proc() {
	NEAREST->release()
	RGBSPACE->release()
	ctx.nswindow->close()
}

os_update_fullscreen :: proc() {
	ctx.nswindow->toggleFullScreen(nil)
}

/*
	[on cursor hiding]
	this redundant cursor state tracking seems obviously stupid
	but we need it because:

	- the Cocoa API is crazy[1] and if we don't exactly balance
	calls to show/hide, it just won't work, so we gate them
	for safety reasons

	- we need to manually implement showing the cursor beyond
	the bounds of the Lena window requesting it to be hidden
	because otherwise the player gets their cursor globally
	deleted while Lena is on their desktop; other platforms
	do this for free, but not macOS

	[1]: https://developer.apple.com/documentation/appkit/nscursor#Balancing-Cursor-Hiding-and-Unhiding
*/

hide_cursor :: proc() {
	if ctx.cursor_visible {
		NSCursor.hide()
		ctx.cursor_visible = false
	}
}

show_cursor :: proc() {
	if !ctx.cursor_visible {
		NSCursor.unhide()
		ctx.cursor_visible = true
	}
}

os_update_cursor :: proc() {
	if .HIDE_CURSOR in ctx.flags {
		hide_cursor()
		return
	}
	show_cursor()
}

os_set_title :: #force_inline proc(title: string) {
	ctx.nswindow->setTitle(NS.String.alloc()->initWithOdinString(title))
}

switch_keys :: proc(k: u16) -> Key {
	switch k {
	case 0x1D: return .N0
	case 0x12: return .N1
	case 0x13: return .N2
	case 0x14: return .N3
	case 0x15: return .N4
	case 0x17: return .N5
	case 0x16: return .N6
	case 0x1A: return .N7
	case 0x1C: return .N8
	case 0x19: return .N9

	case 0x00: return .A
	case 0x0B: return .B
	case 0x08: return .C
	case 0x02: return .D
	case 0x0E: return .E
	case 0x03: return .F
	case 0x05: return .G
	case 0x04: return .H
	case 0x22: return .I
	case 0x26: return .J
	case 0x28: return .K
	case 0x25: return .L
	case 0x2E: return .M
	case 0x2D: return .N
	case 0x1F: return .O
	case 0x23: return .P
	case 0x0C: return .Q
	case 0x0F: return .R
	case 0x01: return .S
	case 0x11: return .T
	case 0x20: return .U
	case 0x09: return .V
	case 0x0D: return .W
	case 0x07: return .X
	case 0x10: return .Y
	case 0x06: return .Z

	case 0x24: return .RETURN
	case 0x30: return .TAB
	case 0x33: return .BACKSPACE
	case 0x75: return .DELETE
	case 0x35: return .ESCAPE
	case 0x31: return .SPACE

	case 0x38: return .LEFT_SHIFT
	case 0x3C: return .RIGHT_SHIFT
	case 0x3B: return .LEFT_CONTROL
	case 0x3E: return .RIGHT_CONTROL
	case 0x3A: return .LEFT_ALT
	case 0x3D: return .RIGHT_ALT
	case 0x37: return .LEFT_SUPER
	case 0x36: return .RIGHT_SUPER

	case 0x77: return .END
	case 0x73: return .HOME
	case 0x7B: return .LEFT
	case 0x7E: return .UP
	case 0x7C: return .RIGHT
	case 0x7D: return .DOWN

	case 0x29: return .SEMICOLON
	case 0x18: return .EQUALS
	case 0x2B: return .COMMA
	case 0x1B: return .MINUS
	case 0x2F: return .DOT
	case 0x2C: return .SLASH
	case 0x32: return .GRAVE

	case 0x74: return .PAGE_UP
	case 0x79: return .PAGE_DOWN

	case 0x21: return .LEFT_BRACKET
	case 0x1E: return .RIGHT_BRACKET
	case 0x2A: return .BACKSLASH
	case 0x27: return .QUOTE

	case 0x52: return .P0
	case 0x53: return .P1
	case 0x54: return .P2
	case 0x55: return .P3
	case 0x56: return .P4
	case 0x57: return .P5
	case 0x58: return .P6
	case 0x59: return .P7
	case 0x5B: return .P8
	case 0x5C: return .P9

	case 0x43: return .KEYPAD_MULTIPLY
	case 0x45: return .KEYPAD_PLUS
	case 0x4E: return .KEYPAD_MINUS
	case 0x41: return .KEYPAD_DOT
	case 0x4B: return .KEYPAD_DIVIDE
	case 0x4C: return .KEYPAD_RETURN
	case 0x51: return .KEYPAD_EQUALS

	case 0x7A: return .F1
	case 0x78: return .F2
	case 0x63: return .F3
	case 0x76: return .F4
	case 0x60: return .F5
	case 0x61: return .F6
	case 0x62: return .F7
	case 0x64: return .F8
	case 0x65: return .F9
	case 0x6D: return .F10
	case 0x67: return .F11
	case 0x6F: return .F12
	case 0x69: return .F13
	case 0x6B: return .F14
	case 0x71: return .F15
	case 0x6A: return .F16
	case 0x40: return .F17
	case 0x4F: return .F18
	case 0x50: return .F19
	case 0x5A: return .F20
	}
	return .UNKNOWN
}
