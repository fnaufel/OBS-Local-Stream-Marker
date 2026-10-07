local real_os = os

local function equal(actual, expected, description)
	if actual ~= expected then
		error(description .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local function fixture()
	local now = 1000
	local recording_active = false
	local recording_paused = false
	local streaming_active = false
	local callbacks = {}
	local files = {}
	local event_callback
	local split_callbacks = {}
	local output = {}
	local settings = {
		output_folder = "",
		output_file_name_custom = "",
		output_datetime_format = "%Y-%m-%d",
		comments_enabled = true,
		comment_count = 2,
		comment_text_1 = "KEEP_CUT",
		comment_text_2 = "DELETE",
	}
	local obs = {
		OBS_INVALID_HOTKEY_ID = -1,
		OBS_FRONTEND_EVENT_STREAMING_STARTED = "streaming_started",
		OBS_FRONTEND_EVENT_STREAMING_STOPPED = "streaming_stopped",
		OBS_FRONTEND_EVENT_RECORDING_STARTED = "recording_started",
		OBS_FRONTEND_EVENT_RECORDING_STOPPED = "recording_stopped",
		OBS_FRONTEND_EVENT_RECORDING_PAUSED = "recording_paused",
		OBS_FRONTEND_EVENT_RECORDING_UNPAUSED = "recording_unpaused",
		obs_data_get_string = function(data, key) return data[key] or "" end,
		obs_data_get_bool = function(data, key) return data[key] or false end,
		obs_data_get_int = function(data, key) return data[key] or 0 end,
		obs_data_get_array = function() return {} end,
		obs_data_array_release = function() end,
		obs_hotkey_load = function() end,
		obs_hotkey_register_frontend = function(name, _, callback)
			callbacks[name] = callback
			return name
		end,
		obs_frontend_add_event_callback = function(callback) event_callback = callback end,
		obs_frontend_recording_active = function() return recording_active end,
		obs_frontend_recording_paused = function() return recording_paused end,
		obs_frontend_streaming_active = function() return streaming_active end,
		obs_frontend_get_recording_output = function() return output end,
		obs_frontend_get_streaming_output = function() return output end,
		os_gettime_ns = function() return math.floor(now * 1000000000 + 0.5) end,
		obs_output_get_settings = function() return { path = "/virtual/recording.mkv" } end,
		obs_output_get_id = function() return "ffmpeg_muxer" end,
		obs_output_get_signal_handler = function() return output end,
		signal_handler_connect = function(_, _, callback)
			split_callbacks[#split_callbacks + 1] = callback
		end,
		signal_handler_disconnect = function(_, _, callback)
			for i = #split_callbacks, 1, -1 do
				if split_callbacks[i] == callback then table.remove(split_callbacks, i) end
			end
		end,
		calldata_string = function(data, key) return data[key] end,
		obs_data_release = function() end,
		obs_output_release = function() end,
		os_opendir = function() return nil end,
		os_quick_read_utf8_file = function(path) return files[path] end,
		os_quick_write_utf8_file = function(path, content) files[path] = content end,
	}
	local env = setmetatable({
		obslua = obs,
		os = {
			time = function() return math.floor(now) end,
			date = function(format, time) return real_os.date(format, math.floor(time or now)) end,
		},
		script_path = function() return "/virtual/" end,
	}, { __index = _G })
	assert(loadfile("local-stream-marker.lua", "t", env))()
	env.script_update(settings)
	env.script_load(settings)

	local function rows()
		local csv = files["/virtual/obs-local-stream-marker.csv"] or ""
		local result = {}
		for line in csv:gmatch("[^\r\n]+") do
			local fields = {}
			for field in line:gmatch("([^,]+)") do
				fields[#fields + 1] = field:match("^%s*(.-)%s*$")
			end
			result[#result + 1] = fields
		end
		table.remove(result, 1)
		return result
	end

	return {
		settings = settings,
		obs = obs,
		configure = function(key, value)
			settings[key] = value
			env.script_update(settings)
		end,
		advance = function(seconds) now = now + seconds end,
		set_time = function(time) now = time end,
		start_recording = function()
			recording_active = true
			event_callback(obs.OBS_FRONTEND_EVENT_RECORDING_STARTED)
		end,
		stop_recording = function()
			recording_active = false
			event_callback(obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED)
		end,
		pause = function()
			recording_paused = true
			event_callback(obs.OBS_FRONTEND_EVENT_RECORDING_PAUSED)
		end,
		unpause = function()
			recording_paused = false
			event_callback(obs.OBS_FRONTEND_EVENT_RECORDING_UNPAUSED)
		end,
		start_streaming = function()
			streaming_active = true
			event_callback(obs.OBS_FRONTEND_EVENT_STREAMING_STARTED)
		end,
		mark = function(index) callbacks["comment_hotkey_" .. index](true) end,
		mark_end = function(index) callbacks["comment_end_hotkey_" .. index](true) end,
		split = function(path)
			for _, callback in ipairs(split_callbacks) do
				callback({ next_file = path })
			end
		end,
		split_connection_count = function() return #split_callbacks end,
		rows = rows,
	}
end

local function recording_timestamps_ignore_paused_time()
	local app = fixture()
	app.start_streaming()
	app.start_recording()
	app.advance(5)
	app.mark(1)
	app.advance(5)
	app.pause()
	app.advance(6)
	app.mark(2)
	app.advance(2)
	app.unpause()
	app.advance(7)
	app.mark(1)

	local rows = app.rows()
	equal(rows[1][7], "00:00:05", "recording time before pause")
	equal(rows[2][7], "00:00:10", "recording time during pause")
	equal(rows[2][9], "00:00:10", "file time during pause")
	equal(rows[3][7], "00:00:17", "recording time after pause")
	equal(rows[2][3], "00:00:16", "stream time during recording pause")
end

local function last_paused_point_marker_replaces_earlier_one()
	local app = fixture()
	app.configure("keep_only_last_paused_marker", true)
	app.start_streaming()
	app.start_recording()
	app.advance(2)
	app.mark(1)
	app.advance(3)
	app.pause()
	app.advance(2)
	app.mark(1)
	app.advance(3)
	app.mark(2)
	app.unpause()
	app.advance(2)
	app.mark(1)

	local rows = app.rows()
	equal(#rows, 3, "one point marker per pause interval")
	equal(rows[1][11], "KEEP_CUT", "pre-pause marker remains")
	equal(rows[2][11], "DELETE", "last paused comment remains")
	equal(rows[2][7], "00:00:05", "last paused recording position")
	equal(rows[2][3], "00:00:10", "last paused stream position")
	equal(rows[3][7], "00:00:07", "post-pause marker remains")
end

local function default_keeps_multiple_paused_point_markers()
	local app = fixture()
	app.start_streaming()
	app.start_recording()
	app.advance(5)
	app.pause()
	app.advance(2)
	app.mark(1)
	app.advance(2)
	app.mark(2)

	local rows = app.rows()
	equal(#rows, 2, "default keeps both paused markers")
	equal(rows[1][7], "00:00:05", "first paused recording position")
	equal(rows[2][7], "00:00:05", "second paused recording position")
	equal(rows[1][3], "00:00:07", "first stream position")
	equal(rows[2][3], "00:00:09", "second stream position")
end

local function split_and_marker_end_use_recorded_duration()
	local app = fixture()
	app.start_recording()
	app.advance(2)
	app.mark(1)
	app.advance(3)
	app.pause()
	app.advance(4)
	app.unpause()
	app.advance(6)
	app.split("/virtual/recording-2.mkv")
	app.advance(3)
	app.pause()
	app.advance(2)
	app.mark_end(1)
	app.advance(1)
	app.unpause()
	app.advance(4)
	app.mark(2)

	local rows = app.rows()
	equal(rows[1][8], "00:00:14", "end recording position during second pause")
	equal(rows[1][10], "00:00:03", "end file position during second pause")
	equal(rows[2][7], "00:00:18", "recording position after two pauses")
	equal(rows[2][9], "00:00:07", "file position after split and pause")
end

local function replaced_marker_is_removed_from_end_hotkey_stack()
	local app = fixture()
	app.configure("keep_only_last_paused_marker", true)
	app.start_recording()
	app.advance(2)
	app.mark(2)
	app.advance(3)
	app.pause()
	app.advance(1)
	app.mark(2)
	app.advance(1)
	app.mark(1)
	app.mark_end(2)

	local rows = app.rows()
	equal(#rows, 2, "replaced marker leaves no extra row")
	equal(rows[1][8], "00:00:05", "end hotkey closes pre-pause marker")
	equal(rows[2][11], "KEEP_CUT", "replacement has the final comment")
end

local function stopping_while_paused_keeps_final_marker()
	local app = fixture()
	app.configure("keep_only_last_paused_marker", true)
	app.start_recording()
	app.advance(5)
	app.pause()
	app.advance(1)
	app.mark(1)
	app.advance(1)
	app.mark(2)
	app.stop_recording()
	app.advance(3)
	app.start_recording()
	app.advance(2)
	app.mark(1)

	local rows = app.rows()
	equal(#rows, 2, "last paused marker remains after stop")
	equal(rows[1][11], "DELETE", "final paused comment remains")
	equal(rows[1][7], "00:00:05", "final paused position remains")
	equal(rows[2][7], "00:00:02", "new recording resets pause time")
end

local function each_pause_interval_keeps_its_own_final_marker()
	local app = fixture()
	app.configure("keep_only_last_paused_marker", true)
	app.start_recording()
	app.advance(5)
	app.pause()
	app.mark(1)
	app.mark(2)
	app.unpause()
	app.advance(3)
	app.pause()
	app.mark(1)
	app.mark(2)

	local rows = app.rows()
	equal(#rows, 2, "one marker remains from each pause interval")
	equal(rows[1][7], "00:00:05", "first pause position remains")
	equal(rows[2][7], "00:00:08", "second pause position remains")
end

local function recording_split_callback_is_registered_once()
	local app = fixture()
	app.start_recording()
	equal(app.split_connection_count(), 1, "one split callback at recording start")
	app.pause()
	app.unpause()
	app.pause()
	app.unpause()
	equal(app.split_connection_count(), 1, "pause events do not add split callbacks")
	app.stop_recording()
	equal(app.split_connection_count(), 0, "split callback removed at recording stop")
end

local function short_pauses_accumulate_before_rounding_to_seconds()
	local app = fixture()
	app.start_recording()
	for i = 0, 3 do
		app.set_time(1000 + i + 0.1)
		app.pause()
		app.set_time(1000 + i + 0.9)
		app.unpause()
	end
	app.set_time(1004.4)
	app.mark(1)

	equal(app.rows()[1][7], "00:00:01", "four short pauses leave one recorded second")
end

recording_timestamps_ignore_paused_time()
last_paused_point_marker_replaces_earlier_one()
default_keeps_multiple_paused_point_markers()
split_and_marker_end_use_recorded_duration()
replaced_marker_is_removed_from_end_hotkey_stack()
stopping_while_paused_keeps_final_marker()
each_pause_interval_keeps_its_own_final_marker()
recording_split_callback_is_registered_once()
short_pauses_accumulate_before_rounding_to_seconds()
print("recording pause tests passed")
