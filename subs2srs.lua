--[[
Copyright (C) 2020-2022 Ren Tatsumoto and contributors
Copyright (C) 2022 Randy Palamar

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

Requirements:
* mpv >= 0.32.0
* curl (for forvo)
* xclip (when running X11)
* wl-copy (when running Wayland)

Usage:
1. Change `config` according to your needs
* Config path: ~/.config/mpv/script-opts/subs2srs.conf
* Config file isn't created automatically.

2. Open a video

3. Use key bindings to manipulate the script
* Open mpvacious menu - `a`
* Create a note from the current subtitle line - `Ctrl + e`

For complete usage guide, see <https://github.com/Ajatt-Tools/mpvacious/blob/master/README.md>
]]

local config = {
    -- Common
    autoclip = false, -- enable copying subs to the clipboard when mpv starts
    nuke_spaces = false, -- remove all spaces from exported anki cards
    clipboard_trim_enabled = true, -- remove unnecessary characters from strings before copying to the clipboard
    use_ffmpeg = false, -- if set to true, use ffmpeg to create audio clips and snapshots. by default use mpv.
    snapshot_format = "webp", -- webp or jpg
    snapshot_quality = 15, -- from 0=lowest to 100=highest
    snapshot_width = -2, -- a positive integer or -2 for auto
    snapshot_height = 200, -- same
    audio_format = "opus", -- opus or mp3
    audio_bitrate = "18k", -- from 16k to 32k
    audio_padding = 0.12, -- Set a pad to the dialog timings. 0.5 = audio is padded by .5 seconds. 0 = disable.
    tie_volumes = false, -- if set to true, the volume of the outputted audio file depends on the volume of the player at the time of export
    menu_font_size = 25,

    -- Custom encoding args
    ffmpeg_audio_args = '-af silenceremove=1:0:-50dB',
    mpv_audio_args = '--af-append=silenceremove=1:0:-50dB',

    -- Anki
    sentence_field = "SentKanji",
    audio_field = "SentAudio",
    create_image = true,

    -- Forvo support
    use_forvo = "yes", -- 'yes', 'no', 'always'
    vocab_field = "VocabKanji", -- target word field
    vocab_audio_field = "VocabAudio", -- target word audio
}

-- Defines config profiles
-- Each name references a file in ~/.config/mpv/script-opts/*.conf
-- Profiles themselves are defined in ~/.config/mpv/script-opts/subs2srs_profiles.conf
local profiles = {
    profiles = "subs2srs,subs2srs_english",
    active = "subs2srs",
}

local mp = require('mp')
local utils = require('mp.utils')
local msg = require('mp.msg')
local OSD = require('osd_styler')
local config_manager = require('config')
local encoder = require('encoder')
local helpers = require('helpers')
local Menu = require('menu')

-- namespaces
local subs
local clip_autocopy
local ankiconnect
local menu
local platform
local append_forvo_pronunciation

-- classes
local Subtitle

------------------------------------------------------------
-- utility functions

---Returns true if table contains element. Returns false otherwise.
---@param table table
---@param element any
---@return boolean
function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

---Returns the largest numeric index.
---@param table table
---@return number
function table.max_num(table)
    local max = table[1]
    for _, value in ipairs(table) do
        if value > max then
            max = value
        end
    end
    return max
end

---Returns a value for the given key. If key is not available then returns default value 'nil'.
---@param table table
---@param key string
---@param default any
---@return any
function table.get(table, key, default)
    if table[key] == nil then
        return default or 'nil'
    else
        return table[key]
    end
end

local function is_running_wayland()
    return os.getenv('WAYLAND_DISPLAY') ~= nil
end

local function contains_non_latin_letters(str)
    return str:match("[^%c%p%s%w]")
end

local function capitalize_first_letter(string)
    return string:gsub("^%l", string.upper)
end

local escape_special_characters
do
    local entities = {
        ['&'] = '&amp;',
        ['"'] = '&quot;',
        ["'"] = '&apos;',
        ['<'] = '&lt;',
        ['>'] = '&gt;',
    }
    escape_special_characters = function(s)
        return s:gsub('[&"\'<>]', entities)
    end
end

local function remove_extension(filename)
    return filename:gsub('%.%w+$', '')
end

local function remove_special_characters(str)
    return str:gsub('[%c%p%s]', ''):gsub('　', '')
end

local function remove_text_in_brackets(str)
    return str:gsub('%b[]', ''):gsub('【.-】', '')
end

local function remove_filename_text_in_parentheses(str)
    return str:gsub('%b()', ''):gsub('（.-）', '')
end

local function remove_common_resolutions(str)
    -- Also removes empty leftover parentheses and brackets.
    return str:gsub("2160p", ""):gsub("1080p", ""):gsub("720p", ""):gsub("576p", ""):gsub("480p", ""):gsub("%(%)", ""):gsub("%[%]", "")
end

local function remove_text_in_parentheses(str)
    -- Remove text like （泣き声） or （ドアの開く音）
    -- No deletion is performed if there's no text after the parentheses.
    -- Note: the modifier `-´ matches zero or more occurrences.
    -- However, instead of matching the longest sequence, it matches the shortest one.
    return str:gsub('(%b())(.)', '%2'):gsub('(（.-）)(.)', '%2')
end

local function remove_newlines(str)
    return str:gsub('[\n\r]+', ' ')
end

local function remove_leading_trailing_spaces(str)
    return str:gsub('^%s*(.-)%s*$', '%1')
end

local function remove_leading_trailing_dashes(str)
    return str:gsub('^[%-_]*(.-)[%-_]*$', '%1')
end

local function remove_all_spaces(str)
    return str:gsub('%s*', '')
end

local function remove_spaces(str)
    if config.nuke_spaces == true and contains_non_latin_letters(str) then
        return remove_all_spaces(str)
    else
        return remove_leading_trailing_spaces(str)
    end
end

local function trim(str)
    str = remove_spaces(str)
    str = remove_text_in_parentheses(str)
    str = remove_newlines(str)
    return str
end

local function copy_to_clipboard(_, text)
    if not helpers.is_empty(text) then
        text = config.clipboard_trim_enabled and trim(text) or remove_newlines(text)
        platform.copy_to_clipboard(text)
    end
end

local function copy_sub_to_clipboard()
    copy_to_clipboard("copy-on-demand", mp.get_property("sub-text"))
end

local function human_readable_time(seconds)
    if type(seconds) ~= 'number' or seconds < 0 then
        return 'empty'
    end

    local parts = {
        h = math.floor(seconds / 3600),
        m = math.floor(seconds / 60) % 60,
        s = math.floor(seconds % 60),
        ms = math.floor((seconds * 1000) % 1000),
    }

    local ret = string.format("%02dm%02ds%03dms", parts.m, parts.s, parts.ms)

    if parts.h > 0 then
        ret = string.format('%dh%s', parts.h, ret)
    end

    return ret
end

local function subprocess(args, completion_fn)
    -- if `completion_fn` is passed, the command is ran asynchronously,
    -- and upon completion, `completion_fn` is called to process the results.
    local command_native = type(completion_fn) == 'function' and mp.command_native_async or mp.command_native
    local command_table = {
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        args = args
    }
    return command_native(command_table, completion_fn)
end

local codec_support = (function()
    local ovc_help = subprocess { 'mpv', '--ovc=help' }
    local oac_help = subprocess { 'mpv', '--oac=help' }

    local function is_audio_supported(codec)
        return oac_help.status == 0 and oac_help.stdout:match('--oac=' .. codec) ~= nil
    end

    local function is_image_supported(codec)
        return ovc_help.status == 0 and ovc_help.stdout:match('--ovc=' .. codec) ~= nil
    end

    return {
        snapshot = {
            libwebp = is_image_supported('libwebp'),
            mjpeg = is_image_supported('mjpeg'),
        },
        audio = {
            libmp3lame = is_audio_supported('libmp3lame'),
            libopus = is_audio_supported('libopus'),
        },
    }
end)()

local function warn_formats(osd)
    if config.use_ffmpeg then
        return
    end
    for type, codecs in pairs(codec_support) do
        for codec, supported in pairs(codecs) do
            if not supported and config[type .. '_codec'] == codec then
                osd:red('warning: '):newline()
                osd:tab():text(string.format("your version of mpv does not support %s.", codec)):newline()
                osd:tab():text(string.format("mpvacious won't be able to create %s files.", type)):newline()
            end
        end
    end
end

local function load_next_profile()
    config_manager.next_profile()
    helpers.notify("Loaded profile " .. profiles.active)
end

local function minutes_ago(m)
    return (os.time() - 60 * m) * 1000
end

local function audio_padding()
    local video_duration = mp.get_property_number('duration')
    if config.audio_padding == 0.0 or not video_duration then
        return 0.0
    end
    if subs.user_timings.is_set('start') or subs.user_timings.is_set('end') then
        return 0.0
    end
    return config.audio_padding
end

------------------------------------------------------------
-- utility classes

local function new_timings()
    local self = { ['start'] = -1, ['end'] = -1, }
    local is_set = function(position)
        return self[position] >= 0
    end
    local set = function(position)
        self[position] = mp.get_property_number('time-pos')
    end
    local get = function(position)
        return self[position]
    end
    return {
        is_set = is_set,
        set = set,
        get = get,
    }
end

local function new_sub_list()
    local subs_list = {}
    local _is_empty = function()
        return next(subs_list) == nil
    end
    local find_i = function(sub)
        for i, v in ipairs(subs_list) do
            if sub < v then
                return i
            end
        end
        return #subs_list + 1
    end
    local get_time = function(position)
        local i = position == 'start' and 1 or #subs_list
        return subs_list[i][position]
    end
    local get_text = function()
        local speech = {}
        for _, sub in ipairs(subs_list) do
            table.insert(speech, sub['text'])
        end
        return table.concat(speech, ' ')
    end
    local insert = function(sub)
        if sub ~= nil and not table.contains(subs_list, sub) then
            table.insert(subs_list, find_i(sub), sub)
            return true
        end
        return false
    end
    return {
        get_time = get_time,
        get_text = get_text,
        is_empty = _is_empty,
        insert = insert
    }
end

local function make_switch(states)
    local self = {
        states = states,
        current_state = 1
    }
    local bump = function()
        self.current_state = self.current_state + 1
        if self.current_state > #self.states then
            self.current_state = 1
        end
    end
    local get = function()
        return self.states[self.current_state]
    end
    return {
        bump = bump,
        get = get
    }
end

local filename_factory = (function()
    local filename

    local anki_compatible_length = (function()
        -- Anki forcibly mutilates all filenames longer than 119 bytes when you run `Tools->Check Media...`.
        local allowed_bytes = 119
        local timestamp_bytes = #'_99h99m99s999ms-99h99m99s999ms.webp'

        return function(str, timestamp)
            -- if timestamp provided, recalculate limit_bytes
            local limit_bytes = allowed_bytes - (timestamp and #timestamp or timestamp_bytes)

            if #str <= limit_bytes then
                return str
            end

            local bytes_per_char = contains_non_latin_letters(str) and #'車' or #'z'
            local limit_chars = math.floor(limit_bytes / bytes_per_char)

            if limit_chars == limit_bytes then
                return str:sub(1, limit_bytes)
            end

            local ret = subprocess {
                'awk',
                '-v', string.format('str=%s', str),
                '-v', string.format('limit=%d', limit_chars),
                'BEGIN{print substr(str, 1, limit); exit}'
            }

            if ret.status == 0 then
                ret.stdout = remove_newlines(ret.stdout)
                ret.stdout = remove_leading_trailing_spaces(ret.stdout)
                return ret.stdout
            else
                return 'subs2srs_' .. os.time()
            end
        end
    end)()

    local make_media_filename = function()
        filename = mp.get_property("filename") -- filename without path
        filename = remove_extension(filename)
        filename = remove_text_in_brackets(filename)
        filename = remove_special_characters(filename)
    end

    local make_audio_filename = function(speech_start, speech_end)
        local filename_timestamp = string.format(
                '_%s-%s%s',
                human_readable_time(speech_start),
                human_readable_time(speech_end),
                config.audio_extension
        )
        return anki_compatible_length(filename, filename_timestamp) .. filename_timestamp
    end

    local make_snapshot_filename = function(timestamp)
        local filename_timestamp = string.format(
                '_%s%s',
                human_readable_time(timestamp),
                config.snapshot_extension
        )
        return anki_compatible_length(filename, filename_timestamp) .. filename_timestamp
    end

    mp.register_event("file-loaded", make_media_filename)

    return {
        make_audio_filename = make_audio_filename,
        make_snapshot_filename = make_snapshot_filename,
    }
end)()

------------------------------------------------------------
-- front for adding and updating notes

local function export_data()
    local sub = subs.get()
    if sub == nil then
        helpers.notify("Nothing to export.", "warn", 1)
        return
    end

    local snapshot_timestamp = mp.get_property_number("time-pos", 0)
    local snapshot_filename = filename_factory.make_snapshot_filename(snapshot_timestamp)
    local audio_filename = filename_factory.make_audio_filename(sub['start'], sub['end'])

    encoder.create_snapshot(snapshot_timestamp, snapshot_filename)
    encoder.create_audio(sub['start'], sub['end'], audio_filename, audio_padding())
    -- FIXME: export to correct folder
    subs.clear()
end

------------------------------------------------------------
-- seeking: sub replay, sub seek, sub rewind

local function _(params)
    return function()
        return pcall(helpers.unpack(params))
    end
end

local pause_timer = (function()
    local stop_time = -1
    local check_stop
    local set_stop_time = function(time)
        stop_time = time
        mp.observe_property("time-pos", "number", check_stop)
    end
    local stop = function()
        mp.unobserve_property(check_stop)
        stop_time = -1
    end
    check_stop = function(_, time)
        if time > stop_time then
            stop()
            mp.set_property("pause", "yes")
        end
    end
    return {
        set_stop_time = set_stop_time,
        check_stop = check_stop,
        stop = stop,
    }
end)()

local play_control = (function()
    local current_sub

    local function stop_at_the_end(sub)
        pause_timer.set_stop_time(sub['end'] - 0.050)
        helpers.notify("Playing till the end of the sub...", "info", 3)
    end

    local function play_till_sub_end()
        local sub = subs.get_current()
        mp.commandv('seek', sub['start'], 'absolute')
        mp.set_property("pause", "no")
        stop_at_the_end(sub)
    end

    local function sub_seek(direction, pause)
        mp.commandv("sub_seek", direction == 'backward' and '-1' or '1')
        mp.commandv("seek", "0.015", "relative+exact")
        if pause then
            mp.set_property("pause", "yes")
        end
        pause_timer.stop()
    end

    local function sub_rewind()
        mp.commandv('seek', subs.get_current()['start'] + 0.015, 'absolute')
        pause_timer.stop()
    end

    local function check_sub()
        local sub = subs.get_current()
        if sub and sub ~= current_sub then
            mp.unobserve_property(check_sub)
            stop_at_the_end(sub)
        end
    end

    local function play_till_next_sub_end()
        current_sub = subs.get_current()
        mp.observe_property("sub-text", "string", check_sub)
        mp.set_property("pause", "no")
        helpers.notify("Waiting till next sub...", "info", 10)
    end

    return {
        play_till_sub_end = play_till_sub_end,
        play_till_next_sub_end = play_till_next_sub_end,
        sub_seek = sub_seek,
        sub_rewind = sub_rewind,
    }
end)()

------------------------------------------------------------
-- platform specific

local function init_platform_nix()
    local self = {}
    local clip = is_running_wayland() and 'wl-copy' or 'xclip -i -selection clipboard'

    self.tmp_dir = function()
        return '/tmp'
    end

    self.copy_to_clipboard = function(text)
        local handle = io.popen(clip, 'w')
        handle:write(text)
        handle:close()
    end

    self.curl_request = function(request_json, completion_fn)
        local args = { 'curl', '-s', 'localhost:8765', '-X', 'POST', '-d', request_json }
        return subprocess(args, completion_fn)
    end

    return self
end

platform = init_platform_nix()

------------------------------------------------------------
-- utils for downloading pronunciations from Forvo

do
    local base64d -- http://lua-users.org/wiki/BaseSixtyFour
    do
        local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
        base64d = function(data)
            data = string.gsub(data, '[^' .. b .. '=]', '')
            return (data:gsub('.', function(x)
                if (x == '=') then return '' end
                local r, f = '', (b:find(x) - 1)
                for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0') end
                return r;
            end)        :gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
                if (#x ~= 8) then return '' end
                local c = 0
                for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2 ^ (8 - i) or 0) end
                return string.char(c)
            end))
        end
    end

    local function url_encode(url)
        -- https://gist.github.com/liukun/f9ce7d6d14fa45fe9b924a3eed5c3d99
        local char_to_hex = function(c)
            return string.format("%%%02X", string.byte(c))
        end
        if url == nil then
            return
        end
        url = url:gsub("\n", "\r\n")
        url = url:gsub("([^%w _%%%-%.~])", char_to_hex)
        url = url:gsub(" ", "+")
        return url
    end

    local function reencode(source_path, dest_path)
        local args = {
            'mpv',
            source_path,
            '--loop-file=no',
            '--video=no',
            '--no-ocopy-metadata',
            '--no-sub',
            '--audio-channels=mono',
            '--oacopts-add=vbr=on',
            '--oacopts-add=application=voip',
            '--oacopts-add=compression_level=10',
            '--af-append=silenceremove=1:0:-50dB',
            table.concat { '--oac=', config.audio_codec },
            table.concat { '--oacopts-add=b=', config.audio_bitrate },
            table.concat { '-o=', dest_path }
        }
        return subprocess(args)
    end

    local function reencode_and_store(source_path, filename)
        local reencoded_path = utils.join_path(platform.tmp_dir(), 'reencoded_' .. filename)
        reencode(source_path, reencoded_path)
        helpers.notify(string.format("Reencoded: '%s'", reencoded_path))
        return result
    end

    local function curl_save(source_url, save_location)
        local curl_args = { 'curl', source_url, '-s', '-L', '-o', save_location }
        return subprocess(curl_args).status == 0
    end

    local function get_pronunciation_url(word)
        local file_format = config.audio_extension:sub(2)
        local forvo_page = subprocess { 'curl', '-s', string.format('https://forvo.com/search/%s/ja', url_encode(word)) }.stdout
        local play_params = string.match(forvo_page, "Play%((.-)%);")

        if play_params then
            local iter = string.gmatch(play_params, "'(.-)'")
            local formats = { mp3 = iter(), ogg = iter() }
            return string.format('https://audio00.forvo.com/%s/%s', file_format, base64d(formats[file_format]))
        end
    end

    local function make_forvo_filename(word)
        return string.format('forvo_%s%s', platform.windows and os.time() or word, config.audio_extension)
    end

    local function get_forvo_pronunciation(word)
        local audio_url = get_pronunciation_url(word)

        if helpers.is_empty(audio_url) then
            msg.warn(string.format("Seems like Forvo doesn't have audio for word %s.", word))
            return
        end

        local filename = make_forvo_filename(word)
        local tmp_filepath = utils.join_path(platform.tmp_dir(), filename)

        local result
        if curl_save(audio_url, tmp_filepath) and reencode_and_store(tmp_filepath, filename) then
            result = string.format('[sound:%s]', filename)
        else
            msg.warn(string.format("Couldn't download audio for word %s from Forvo.", word))
        end

        os.remove(tmp_filepath)
        return result
    end

    append_forvo_pronunciation = function(new_data, stored_data)
        if config.use_forvo == 'no' then
            -- forvo functionality was disabled in the config file
            return new_data
        end

        if type(stored_data[config.vocab_audio_field]) ~= 'string' then
            -- there is no field configured to store forvo pronunciation
            return new_data
        end

        if helpers.is_empty(stored_data[config.vocab_field]) then
            -- target word field is empty. can't continue.
            return new_data
        end

        if config.use_forvo == 'always' or helpers.is_empty(stored_data[config.vocab_audio_field]) then
            local forvo_pronunciation = get_forvo_pronunciation(stored_data[config.vocab_field])
            if not helpers.is_empty(forvo_pronunciation) then
                if config.vocab_audio_field == config.audio_field then
                    -- improperly configured fields. don't lose sentence audio
                    new_data[config.audio_field] = forvo_pronunciation .. new_data[config.audio_field]
                else
                    new_data[config.vocab_audio_field] = forvo_pronunciation
                end
            end
        end

        return new_data
    end
end

------------------------------------------------------------
-- subtitles and timings

subs = {
    dialogs = new_sub_list(),
    user_timings = new_timings(),
    observed = false
}

subs.get_current = function()
    return Subtitle:now()
end

subs.get_timing = function(position)
    if subs.user_timings.is_set(position) then
        return subs.user_timings.get(position)
    elseif not subs.dialogs.is_empty() then
        return subs.dialogs.get_time(position)
    end
    return -1
end

subs.get = function()
    if subs.dialogs.is_empty() then
        subs.dialogs.insert(subs.get_current())
    end
    local sub = Subtitle:new {
        ['text'] = subs.dialogs.get_text(),
        ['start'] = subs.get_timing('start'),
        ['end'] = subs.get_timing('end'),
    }
    if sub['start'] < 0 or sub['end'] < 0 then
        return nil
    end
    if sub['start'] == sub['end'] then
        return nil
    end
    if sub['start'] > sub['end'] then
        sub['start'], sub['end'] = sub['end'], sub['start']
    end
    if not helpers.is_empty(sub['text']) then
        sub['text'] = trim(sub['text'])
        sub['text'] = escape_special_characters(sub['text'])
    end
    return sub
end

subs.append = function()
    if subs.dialogs.insert(subs.get_current()) then
        menu:update()
    end
end

subs.observe = function()
    mp.observe_property("sub-text", "string", subs.append)
    subs.observed = true
end

subs.unobserve = function()
    mp.unobserve_property(subs.append)
    subs.observed = false
end

subs.set_timing = function(position)
    subs.user_timings.set(position)
    helpers.notify(capitalize_first_letter(position) .. " time has been set.")
    if not subs.observed then
        subs.observe()
    end
end

subs.set_starting_line = function()
    subs.clear()
    if subs.get_current() then
        subs.observe()
        helpers.notify("Timings have been set to the current sub.", "info", 2)
    else
        helpers.notify("There's no visible subtitle.", "info", 2)
    end
end

subs.clear = function()
    subs.unobserve()
    subs.dialogs = new_sub_list()
    subs.user_timings = new_timings()
end

subs.clear_and_notify = function()
    subs.clear()
    helpers.notify("Timings have been reset.", "info", 2)
end

------------------------------------------------------------
-- send subs to clipboard as they appear

clip_autocopy = (function()
    local enable = function()
        mp.observe_property("sub-text", "string", copy_to_clipboard)
    end

    local disable = function()
        mp.unobserve_property(copy_to_clipboard)
    end

    local state_notify = function()
        helpers.notify(string.format("Clipboard autocopy has been %s.", config.autoclip and 'enabled' or 'disabled'))
    end

    local toggle = function()
        config.autoclip = not config.autoclip
        if config.autoclip == true then
            enable()
        else
            disable()
        end
        state_notify()
    end

    local is_enabled = function()
        return config.autoclip == true and 'enabled' or 'disabled'
    end

    local init = function()
        if config.autoclip == true then
            enable()
        end
    end

    return {
        enable = enable,
        disable = disable,
        init = init,
        toggle = toggle,
        is_enabled = is_enabled,
    }
end)()

------------------------------------------------------------
-- Subtitle class provides methods for comparing subtitle lines

Subtitle = {
    ['text'] = '',
    ['start'] = -1,
    ['end'] = -1,
}

function Subtitle:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Subtitle:now()
    local delay = mp.get_property_native("sub-delay") - mp.get_property_native("audio-delay")
    local text = mp.get_property("sub-text")
    local this = self:new {
        ['text'] = text, -- if is_empty then it's dealt with later
        ['start'] = mp.get_property_number("sub-start"),
        ['end'] = mp.get_property_number("sub-end"),
    }
    return this:valid() and this:delay(delay) or nil
end

function Subtitle:delay(delay)
    self['start'] = self['start'] + delay
    self['end'] = self['end'] + delay
    return self
end

function Subtitle:valid()
    return self['start'] and self['end'] and self['start'] >= 0 and self['end'] > 0
end

Subtitle.__eq = function(lhs, rhs)
    return lhs['text'] == rhs['text']
end

Subtitle.__lt = function(lhs, rhs)
    return lhs['start'] < rhs['start']
end

------------------------------------------------------------
-- main menu

menu = Menu:new {
    hints_state = make_switch { 'hidden', 'menu', 'global', },
}

menu.keybindings = {
    { key = 's', fn = menu:with_update { subs.set_timing, 'start' } },
    { key = 'e', fn = menu:with_update { subs.set_timing, 'end' } },
    { key = 'c', fn = menu:with_update { subs.set_starting_line } },
    { key = 'r', fn = menu:with_update { subs.clear_and_notify } },
    { key = 'g', fn = menu:with_update { export_data } },
    { key = 'n', fn = menu:with_update { export_data } },
    { key = 't', fn = menu:with_update { clip_autocopy.toggle } },
    { key = 'i', fn = menu:with_update { menu.hints_state.bump } },
    { key = 'p', fn = menu:with_update { load_next_profile } },
    { key = 'ESC', fn = function() menu:close() end },
    { key = 'q', fn = function() menu:close() end },
}

function menu:make_osd()
    local osd = OSD:new():size(config.menu_font_size):align(4)

    osd:submenu('mpvacious options'):newline()
    osd:item('Timings: '):text(human_readable_time(subs.get_timing('start')))
    osd:item(' to '):text(human_readable_time(subs.get_timing('end'))):newline()
    osd:item('Clipboard autocopy: '):text(clip_autocopy.is_enabled()):newline()
    osd:item('Active profile: '):text(profiles.active):newline()

    if self.hints_state.get() == 'global' then
        osd:submenu('Global bindings'):newline()
        osd:tab():item('ctrl+c: '):text('Copy current subtitle to clipboard'):newline()
        osd:tab():item('ctrl+h: '):text('Seek to the start of the line'):newline()
        osd:tab():item('ctrl+shift+h: '):text('Replay current subtitle'):newline()
        osd:tab():item('shift+h/l: '):text('Seek to the previous/next subtitle'):newline()
        osd:tab():item('alt+h/l: '):text('Seek to the previous/next subtitle and pause'):newline()
        osd:italics("Press "):item('i'):italics(" to hide bindings."):newline()
    elseif self.hints_state.get() == 'menu' then
        osd:submenu('Menu bindings'):newline()
        osd:tab():item('c: '):text('Set timings to the current sub'):newline()
        osd:tab():item('s: '):text('Set start time to current position'):newline()
        osd:tab():item('e: '):text('Set end time to current position'):newline()
        osd:tab():item('r: '):text('Reset timings'):newline()
        osd:tab():item('n: '):text('Export note'):newline()
        osd:tab():item('g: '):text('GUI export'):newline()
        osd:tab():item('m: '):text('Update the last added note '):italics('(+shift to overwrite)'):newline()
        osd:tab():item('t: '):text('Toggle clipboard autocopy'):newline()
        osd:tab():item('p: '):text('Switch to next profile'):newline()
        osd:tab():item('ESC: '):text('Close'):newline()
        osd:italics("Press "):item('i'):italics(" to show global bindings."):newline()
    else
        osd:italics("Press "):item('i'):italics(" to show menu bindings."):newline()
    end

    warn_formats(osd)

    return osd
end

------------------------------------------------------------
-- main

local main = (function()
    local main_executed = false
    return function()
        if main_executed then
            return
        else
            main_executed = true
        end

        config_manager.init(config, profiles)
        encoder.init(config, platform.tmp_dir, subprocess)
        clip_autocopy.init()

        -- Key bindings
        mp.add_forced_key_binding("Ctrl+n", "mpvacious-export-note", export_data)
        mp.add_forced_key_binding("Ctrl+c", "mpvacious-copy-sub-to-clipboard", copy_sub_to_clipboard)
        mp.add_key_binding("Ctrl+t", "mpvacious-autocopy-toggle", clip_autocopy.toggle)

        -- Open advanced menu
        mp.add_key_binding("a", "mpvacious-menu-open", function() menu:open() end)

        -- Vim-like seeking between subtitle lines
        mp.add_key_binding("H", "mpvacious-sub-seek-back", _ { play_control.sub_seek, 'backward' })
        mp.add_key_binding("L", "mpvacious-sub-seek-forward", _ { play_control.sub_seek, 'forward' })

        mp.add_key_binding("Alt+h", "mpvacious-sub-seek-back-pause", _ { play_control.sub_seek, 'backward', true })
        mp.add_key_binding("Alt+l", "mpvacious-sub-seek-forward-pause", _ { play_control.sub_seek, 'forward', true })

        mp.add_key_binding("Ctrl+h", "mpvacious-sub-rewind", _ { play_control.sub_rewind })
        mp.add_key_binding("Ctrl+H", "mpvacious-sub-replay", _ { play_control.play_till_sub_end })
        mp.add_key_binding("Ctrl+L", "mpvacious-sub-play-up-to-next", _ { play_control.play_till_next_sub_end })
    end
end)()

mp.register_event("file-loaded", main)
