#+build !js
package lena

import "vendor:miniaudio"

CHANNEL_COUNT :: #config(LENA_CHANNEL_COUNT, 2)
SAMPLE_RATE   :: #config(LENA_SAMPLE_RATE, 44_100)

@private
Audio_Context :: struct {
	can_sleep:     bool,
	is_asleep:     bool,
	tracks:        [dynamic]Audio_Track,
	device:        miniaudio.device,
	device_config: miniaudio.device_config,
	group_volumes: [16]f32,
	group_fader:   [16]f32,
}

Audio_Track :: struct {
	decoder: miniaudio.decoder,
	group:   u8,
	is_done: bool,
	volume:  f32,
}

play_sound :: proc(blob: []byte, volume: f64 = 1, loop := false, group: u8 = 0) -> bool {
	data: Audio_Track
	data.volume = cast(f32) max(volume, 0)
	data.group  = min(group, 15)

	ctx.group_volumes[data.group] = 1
	ctx.group_fader[data.group]   = 0

	sample_format := ctx.device_config.playback.format
	channel_count := ctx.device_config.playback.channels
	sample_rate   := ctx.device_config.sampleRate

	config := miniaudio.decoder_config_init(sample_format, channel_count, sample_rate)
	result := miniaudio.decoder_init_memory(raw_data(blob), len(blob), &config, &data.decoder)
	if result != .SUCCESS {
		return false
	}

	if loop {
		miniaudio.data_source_set_looping(data.decoder.pBackend, b32(loop))
	}

	append(&ctx.tracks, data)
	ctx.can_sleep = false
	ctx.is_asleep = false

	if miniaudio.device_is_started(&ctx.device) {
		return false
	}

	result = miniaudio.device_start(&ctx.device)
	if result != .SUCCESS {
		return false
	}

	return true
}

clear_sounds :: proc(group: u8 = 0, with_fade: f64 = 0) {
	with_fade := cast(f32) max(with_fade, 0)
	the_group := min(group, 15)

	if with_fade > 0 {
		if the_group > 0 {
			ctx.group_fader[the_group] = with_fade
			return
		}

		for &fader in ctx.group_fader {
			fader = with_fade
		}
		return
	}

	if the_group > 0 {
		for &track in ctx.tracks {
			if track.group == the_group {
				track.is_done = true
			}
		}
		return
	}

	miniaudio.device_stop(&ctx.device)
	for &track in ctx.tracks {
		miniaudio.decoder_uninit(&track.decoder)
	}
	clear(&ctx.tracks)
	ctx.is_asleep = true
}

@private
audio_init :: proc() -> bool {
	ctx.tracks = make(type_of(ctx.tracks), 0, 16, ctx.allocator)

	for &group in ctx.group_volumes {
		group = 1
	}

	ctx.device_config = miniaudio.device_config_init(.playback)

	ctx.device_config.playback.format   = miniaudio.format.f32
	ctx.device_config.playback.channels = CHANNEL_COUNT
	ctx.device_config.sampleRate        = SAMPLE_RATE
	ctx.device_config.dataCallback      = data_callback

	result := miniaudio.device_init(nil, &ctx.device_config, &ctx.device)
	if result != .SUCCESS {
		return false
	}

	ctx.is_asleep = true
	return true
}

@private
audio_destroy :: proc() {
	clear_sounds()
	miniaudio.device_uninit(&ctx.device)
}

@private
audio_step :: proc(delta_time: f64) {
	if ctx.is_asleep {
		return
	}

	if ctx.can_sleep {
		clear_sounds()
		return
	}

	delta_time := cast(f32) delta_time

	for &group, index in ctx.group_volumes {
		fader := ctx.group_fader[index]
		if fader > 0 {
			group -= delta_time / fader
			if group < 0 {
				group = 0
				ctx.group_fader[index] = 0
				clear_sounds(group = cast(u8) index)
			}
		}
	}

	for &track, i in ctx.tracks {
		if track.is_done {
			miniaudio.decoder_uninit(&track.decoder)
			unordered_remove(&ctx.tracks, i)
			break // only one track is cleaned-up per-frame
		}
	}
}

@private
data_callback :: proc "c" (device: ^miniaudio.device, output, input: rawptr, frame_count: u32) {
	TEMP_SIZE :: 4096

	frame_count   := cast(u64) frame_count
	channel_count := cast(u64) ctx.device_config.playback.channels

	output := cast([^]f32) output

	any_active := false
	for &track in ctx.tracks {
		if track.is_done {
			continue
		}

		temp: [TEMP_SIZE]f32
		total_frames_read: u64 = 0

		this_track_volume := track.volume * ctx.group_volumes[track.group]

		for total_frames_read < frame_count {
			frames_read: u64
			frames_due:  u64 = TEMP_SIZE / channel_count

			total_frames_remaining := frame_count - total_frames_read

			if frames_due > total_frames_remaining {
				frames_due = total_frames_remaining
			}

			result := miniaudio.decoder_read_pcm_frames(&track.decoder, raw_data(temp[:]), frames_due, &frames_read)
			if result != .SUCCESS || frames_read == 0 {
				break
			}

			{
				limit  := channel_count * frames_read
				offset := channel_count * total_frames_read
				for i: u64 = 0; i < limit; i += 1 {
					output[offset + i] += temp[i] * this_track_volume
				}
			}

			total_frames_read += frames_read
			if frames_read < frames_due {
				break
			}
		}

		if total_frames_read < frame_count {
			track.is_done = true
			continue
		}

		any_active = true
	}

	ctx.can_sleep = !any_active
}
