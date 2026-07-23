#+private
#+build windows
package lena

import "core:time"
import "base:runtime"
import "core:sys/windows"

REDRAW_FLAGS: windows.RedrawWindowFlags: .RDW_INVALIDATE | .RDW_UPDATENOW

WINDOWED_STYLE :: windows.WS_CAPTION | windows.WS_THICKFRAME | windows.WS_SYSMENU | windows.WS_MINIMIZEBOX | windows.WS_MAXIMIZEBOX
WINDOWEX_STYLE :: windows.WS_EX_DLGMODALFRAME

Platform_Context :: struct {
	hwnd: windows.HWND,
	hdc:  windows.HDC,
	last_window_background: u8,
}

os_init :: proc(title: string) {
	windows.SetConsoleOutputCP(.UTF8)
	windows.timeBeginPeriod(1)

	wintitle  := windows.utf8_to_wstring(title, context.temp_allocator)
	winstance := cast(windows.HINSTANCE) windows.GetModuleHandleW(nil)

	windows.RegisterClassExW(&{
		cbSize        = size_of(windows.WNDCLASSEXW),
		style         = windows.CS_OWNDC | windows.CS_HREDRAW | windows.CS_VREDRAW,
		lpfnWndProc   = windows_bind,
		hCursor       = windows.LoadCursorA(nil, windows.IDC_ARROW),
		hInstance     = winstance,
		lpszClassName = wintitle,
	})

	ctx.hwnd = windows.CreateWindowExW(WINDOWEX_STYLE, wintitle, wintitle, WINDOWED_STYLE, 0, 0, 128, 128, nil, nil, nil, winstance)
	ctx.hdc  = windows.GetDC(ctx.hwnd)

	when WIN95_MODE {
		x := windows.utf8_to_wstring(" ", context.temp_allocator)
		windows.SetWindowTheme(ctx.hwnd, x, x)
	} else {
		local_true := windows.TRUE
		windows.DwmSetWindowAttribute(ctx.hwnd, u32(windows.DWMWINDOWATTRIBUTE.DWMWA_USE_IMMERSIVE_DARK_MODE), &local_true, size_of(local_true))
	}

	step := ctx.fps
	if ctx.fps == FPS_AUTO {
		refresh_info: windows.DEVMODEW
		windows.EnumDisplaySettingsW(nil, 0, &refresh_info)
		step = cast(i64) refresh_info.dmDisplayFrequency
	}
	if step > 0 {
		ctx.step_time = time.Second / cast(time.Duration) step
	}

	os_update_fullscreen()
}

os_destroy :: proc() {
	windows.timeEndPeriod(1)
	windows.ReleaseDC(ctx.hwnd, ctx.hdc)
	windows.DestroyWindow(ctx.hwnd)
}

os_step :: proc() {
	if ctx.step_time > 0 {
		time.accurate_sleep(ctx.step_time - time.diff(ctx.prev_time, time.now()))
	}
	ctx.delta_time = time.duration_seconds(time.diff(ctx.prev_time, time.now()))
	ctx.prev_time  = time.now()

	msg: windows.MSG
	for windows.PeekMessageW(&msg, ctx.hwnd, 0, 0, windows.PM_REMOVE) {
		windows.TranslateMessage(&msg)
		windows.DispatchMessageW(&msg)
	}
}

os_present :: proc() {
	windows.RedrawWindow(ctx.hwnd, nil, nil, REDRAW_FLAGS)
}

os_show_window :: proc() {
	windows.ShowWindow(ctx.hwnd, 1)
}

os_modify_palette :: proc() {} // Windows byte-order is canonical

switch_button :: #force_inline proc(x: u32) -> Mouse {
	switch x {
	case windows.WM_RBUTTONDOWN, windows.WM_RBUTTONUP: return .RIGHT
	case windows.WM_MBUTTONDOWN, windows.WM_MBUTTONUP: return .MIDDLE
	}
	return .LEFT
}

switch_keys :: #force_inline proc(virtual_code: u32, lparam: int) -> u32 {
	switch virtual_code {
	case windows.VK_SHIFT:
		return windows.MapVirtualKeyW(u32((lparam & 0x00ff0000) >> 16), windows.MAPVK_VSC_TO_VK_EX)
	case windows.VK_CONTROL:
		return (lparam & 0x01000000) != 0 ? windows.VK_RCONTROL : windows.VK_LCONTROL
	case windows.VK_MENU:
		return (lparam & 0x01000000) != 0 ? windows.VK_RMENU : windows.VK_LMENU
	}
	return virtual_code
}

windows_bind :: proc "stdcall" (hwnd: windows.HWND, message: windows.UINT, wparam: windows.WPARAM, lparam: windows.LPARAM) -> windows.LRESULT {
	context = runtime.default_context()

	switch message {
	case windows.WM_KEYDOWN, windows.WM_SYSKEYDOWN:
		if lparam & (1 << 30) != 0 do break // key repeat
		code := switch_keys(u32(wparam), lparam)
		ctx.key_state[code] = KEY_STATE_HELD | KEY_STATE_PRESSED

	case windows.WM_KEYUP, windows.WM_SYSKEYUP:
		code := switch_keys(u32(wparam), lparam)
		ctx.key_state[code] &= ~KEY_STATE_HELD
		ctx.key_state[code] |=  KEY_STATE_RELEASED

	case windows.WM_LBUTTONDOWN, windows.WM_RBUTTONDOWN, windows.WM_MBUTTONDOWN:
		windows.SetCapture(hwnd)
		button := switch_button(message)
		ctx.mouse_state[button] = KEY_STATE_HELD | KEY_STATE_PRESSED

	case windows.WM_LBUTTONUP, windows.WM_RBUTTONUP, windows.WM_MBUTTONUP:
		windows.ReleaseCapture()
		button := switch_button(message)
		ctx.mouse_state[button] &= ~KEY_STATE_HELD
		ctx.mouse_state[button] |= KEY_STATE_RELEASED

	case windows.WM_MOUSEMOVE:
		dimms := adjusted_window_size()
		ctx.mouse_pos.x = int((windows.GET_X_LPARAM(lparam) - i32(dimms.x))) * ctx.screen.w / dimms.w
		ctx.mouse_pos.y = int((windows.GET_Y_LPARAM(lparam) - i32(dimms.y))) * ctx.screen.h / dimms.h

	case windows.WM_QUIT, windows.WM_CLOSE:
		ctx.set_quit = true

	case windows.WM_SETFOCUS:
		ctx.has_focus = true
		break

	case windows.WM_KILLFOCUS:
		ctx.has_focus = false
		break

	case windows.WM_ACTIVATE:
		ctx.has_focus = (windows.LOWORD(u32(wparam)) != windows.WA_INACTIVE)
		break

	case windows.WM_PAINT:
		if ctx.last_window_background != ctx.window_background {
			clear_window()
			ctx.last_window_background = ctx.window_background
		}

		bmi := windows.BITMAPINFO{
			bmiHeader = {
				biSize = size_of(windows.BITMAPINFOHEADER),
				biBitCount = 32,
				biCompression = windows.BI_RGB,
				biPlanes = 1,
				biWidth  = i32(ctx.screen.w),
				biHeight = i32(-ctx.screen.h),
			},
		}

		dimms := adjusted_window_size()
		windows.StretchDIBits(ctx.hdc, i32(dimms.x), i32(dimms.y), i32(dimms.w), i32(dimms.h), 0, 0, i32(ctx.screen.w), i32(ctx.screen.h), raw_data(ctx.backbuffer), &bmi, windows.DIB_RGB_COLORS, windows.SRCCOPY)
		windows.ValidateRect(hwnd, nil)

	case windows.WM_SIZE:
		if wparam != windows.SIZE_MINIMIZED {
			ctx.window.w = cast(int) windows.LOWORD(lparam)
			ctx.window.h = cast(int) windows.HIWORD(lparam)
			clear_window()
			windows.RedrawWindow(ctx.hwnd, nil, nil, REDRAW_FLAGS)
			return 0
		}

	case:
		return windows.DefWindowProcW(hwnd, message, wparam, lparam)
	}

	return 0
}

clear_window :: proc() {
	ps: windows.PAINTSTRUCT
	hdc := windows.BeginPaint(ctx.hwnd, &ps)

	x := ctx.palette[ctx.window_background]
	bgra_swizzle(&x)

	brush := windows.CreateSolidBrush(x ~ 0xff000000)
	windows.FillRect(hdc, &ps.rcPaint, brush)
	windows.DeleteObject(auto_cast brush)
	windows.EndPaint(ctx.hwnd, &ps)
}

os_update_fullscreen :: proc() {
	if .FULLSCREEN in ctx.flags {
		monitor := windows.MonitorFromWindow(ctx.hwnd, .MONITOR_DEFAULTTONEAREST)

		info: windows.MONITORINFO
		info.cbSize = size_of(windows.MONITORINFO)

		windows.GetMonitorInfoW(monitor, &info)

		// note: rcMonitor and rcWork are the same on my
		// system (and I use weird DPI scaling). should I
		// prefer one on Windows? unclear.

		cx, cy := info.rcMonitor.left,   info.rcMonitor.top
		wd, hg := info.rcMonitor.right - info.rcMonitor.left, info.rcMonitor.bottom - info.rcMonitor.top

		windows.SetWindowLongPtrW(ctx.hwnd, windows.GWL_STYLE,   auto_cast 0)
		windows.SetWindowLongPtrW(ctx.hwnd, windows.GWL_EXSTYLE, auto_cast 0)

		windows.SetWindowPos(ctx.hwnd, nil, cx, cy, wd, hg, windows.SWP_SHOWWINDOW if .HIDE_WINDOW not_in ctx.flags else 0)
		return
	}

	// windowed
	buffer_w  := ctx.screen.w
	buffer_h  := ctx.screen.h
	monitor_w := cast(int) windows.GetSystemMetrics(windows.SM_CXFULLSCREEN)
	monitor_h := cast(int) windows.GetSystemMetrics(windows.SM_CYFULLSCREEN)

	scale := cast(f32) (monitor_w > monitor_h ? monitor_h / buffer_h : monitor_w / buffer_w) / 5

	ctx.window.w = buffer_w * cast(int) (scale * 4)
	ctx.window.h = buffer_h * cast(int) (scale * 4)

	winrect := windows.RECT{0, 0, cast(i32) ctx.window.w, cast(i32) ctx.window.h}
	windows.AdjustWindowRectEx(&winrect, WINDOWED_STYLE, false, 0)

	sw := winrect.right  - winrect.left
	sh := winrect.bottom - winrect.top

	sx := (cast(i32) monitor_w - sw) / 2
	sy := (cast(i32) monitor_h - sh) / 2

	windows.SetWindowLongPtrW(ctx.hwnd, windows.GWL_STYLE,   auto_cast WINDOWED_STYLE)
	windows.SetWindowLongPtrW(ctx.hwnd, windows.GWL_EXSTYLE, auto_cast WINDOWEX_STYLE)

	windows.SetWindowPos(ctx.hwnd, nil, sx, sy, sw, sh, windows.SWP_SHOWWINDOW if .HIDE_WINDOW not_in ctx.flags else 0)
}

os_update_cursor :: #force_inline proc() {
	windows.ShowCursor(.HIDE_CURSOR not_in ctx.flags)
}

os_set_title :: proc(text: string) {
	windows.SetWindowTextW(ctx.hwnd, windows.utf8_to_wstring(text, context.temp_allocator))
}
