# mpv2oboeru

mpv2oboeru is a semi-automatic subs2srs helper for mpv.
It started as a fork of [mpvacious](https://github.com/Ajatt-Tools/mpvacious).

## Table of contents

* [Requirements](#requirements)
* [Installation](#installation)
    * [Manually](#manually)
    * [Using git](#using-git)
    * [Updating with git](#updating-with-git)
* [Configuration](#configuration)
* [Usage](#usage)
    * [Global bindings](#global-bindings)
    * [Menu options](#menu-options)
    * [Other tools](#other-tools)
* [Profiles](#profiles)
* [Hacking](#hacking)

## Requirements

* mpv
* xclip - when using X11
* wl-copy - when using Wayland

## Installation

### Manually

Download
[the repository](https://github.com/0x766F6964/mpv2oboeru/archive/refs/heads/master.zip)
and extract the folder containing
[subs2srs.lua](https://raw.githubusercontent.com/0x766F6964/mpv2oboeru/master/subs2srs.lua)
to your [mpv scripts](https://github.com/mpv-player/mpv/wiki/User-Scripts) directory:

	~/.config/mpv/scripts/

### Using git

If you already have your dotfiles set up similar to
[Arch Wiki recommendations](https://wiki.archlinux.org/index.php/Dotfiles#Tracking_dotfiles_directly_with_Git), execute:

	$ git submodule add 'https://github.com/0x766F6964/mpv2oboeru.git' ~/.config/mpv/scripts/mpv2oboeru

If not, either proceed to Arch Wiki and come back when you're done, or simply clone the repo:

	$ git clone 'https://github.com/0x766F6964/mpv2oboeru.git' ~/.config/mpv/scripts/mpv2oboeru

### Updating with git

Submodules: `$ git submodule update --remote --merge`
Plain git: `$ cd ~/.config/mpv/scripts/subs2srs && git pull`

## Configuration

The config file should be created by the user, if needed.

	~/.config/mpv/script-opts/subs2srs.conf

If a parameter is not specified
in the config file, the default value will be used.
mpv doesn't tolerate spaces before and after `=`.

If no matter what mpv2oboeru fails to create audio clips and/or snapshots,
change `use_ffmpeg` to `yes`.
By using ffmpeg instead of the encoder built in mpv you can work around most encoder issues.
You need to have ffmpeg installed for this to work.

### Key bindings

The user may change some key bindings, though this step is not necessary.
See [Usage](#usage) for the explanation of what they do.

	~/.config/mpv/input.conf

Default bindings:

```
a            script-binding mpvacious-menu-open

Ctrl+n       script-binding mpvacious-export-note

Ctrl+c       script-binding mpvacious-copy-sub-to-clipboard
Ctrl+t       script-binding mpvacious-autocopy-toggle

H            script-binding mpvacious-sub-seek-back
L            script-binding mpvacious-sub-seek-forward

Alt+h        script-binding mpvacious-sub-seek-back-pause
Alt+l        script-binding mpvacious-sub-seek-forward-pause

Ctrl+h       script-binding mpvacious-sub-rewind
Ctrl+H       script-binding mpvacious-sub-replay
Ctrl+L       script-binding mpvacious-sub-play-up-to-next
```

**Note:** A capital letter means that you need to press Shift in order to activate the corresponding binding.
For example, `Ctrl+M` actually means `Ctrl+Shift+m`.
mpv accepts both variants in `input.conf`.

## Usage

### Global bindings

Menu:
* `a` - Open `advanced menu`.

Make a card:
* `Ctrl+n` - Export a card with the currently visible subtitle line on the front.
Use this when your subs are well-timed,
and the target sentence doesn't span multiple subs.

Clipboard:
* `Ctrl+c` - Copy current subtitle string to the system clipboard.
* `Ctrl+t` - Toggle automatic copying of subtitles to the clipboard.

Seeking:
* `Shift+h` and `Shift+l` - Seek to the previous or the next subtitle.
* `Alt+h` and `Alt+l` - Seek to the previous, or the next subtitle, and pause.
* `Ctrl+h` - Seek to the start of the currently visible subtitle. Use it if you missed something.
* `Ctrl+Shift+h` - Replay current subtitle line, and pause.
* `Ctrl+Shift+l` - Play until the end of the next subtitle, and pause. Useful for beginners who need
to look up words in each and every dialogue line.

### Menu options

Let's say your subs are well-timed,
but the sentence you want to add is split between multiple subs.
We need to combine the lines before making a card.

Advanced menu has the following options:

* `c` - Set timings to the current sub and remember the corresponding line.
It does nothing if there are no subs on screen.

Then seek with `Shift+h` and `Shift+l` to the previous/next line that you want to add.
Press `n` to make the card.

* `r` - Forget all previously saved timings and associated dialogs.

If subs are badly timed, first, you could try to re-time them.
[ffsubsync](https://github.com/smacke/ffsubsync) is a program that will do it for you.
Another option would be to shift timings using key bindings provided by mpv.

* `z` and `Shift+z` - Adjust subtitle delay.

If above fails, you have to manually set timings.
* `s` - Set the start time.
* `e` - Set the end time.

Then, as earlier, press `n` to make the card.

**Tip**: change playback speed by pressing `[` and `]`
to precisely mark start and end of the phrase.

**The process:**

1. Open `Yomichan Search` by pressing `Alt+Insert` in your web browser.
2. Enable `Clipboard autocopy` in mpv2oboeru by pressing `t` in the `advanced menu`.
3. Go back to mpv and add the snapshot and the audio clip
   to the card you've just made by pressing `m` in the `advanced menu`.
   Pressing `Shift+m` will overwrite any existing data in media fields.

Don't forget to set the right timings and join lines together
if the sentence is split between multiple subs.

### Other tools

If you don't like the default Yomichan Search tool, try:

* Clipboard Inserter browser add-on
([chrome](https://chrome.google.com/webstore/detail/clipboard-inserter/deahejllghicakhplliloeheabddjajm))
([firefox](https://addons.mozilla.org/ja/firefox/addon/clipboard-inserter/))
* A html page ([1](https://pastebin.com/zDY6s3NK)) ([2](https://pastebin.com/hZ4sawL4))
to paste the contents of your clipboard to

You can use any html page as long as it has \<body\>\</body\> in it.

## Profiles

Mpvacious supports config profiles.
To make use of them, create a new config file called `subs2srs_profiles.conf`
in the same folder as your [subs2srs.conf](#Configuration).
Inside the file, define available profile names (without `.conf`) and the name of the active profile:

```
profiles=subs2srs,english,german
active=subs2srs
```

In the example above, I have three profiles.
The first one is the default,
the second one is for learning English,
the third one is for learning German.

Then in the same folder create config files for each of the defined profiles.
For example, below is the contents of my `english.conf` file:

```
deck_name=English sentence mining
model_name=General
sentence_field=Question
audio_field=Audio
image_field=Extra
```

You don't have to redefine all settings in the new profile.
Specify only the ones you want to be different from the default.

To cycle profiles, open the advanced menu by pressing `a` and then press `p`.
At any time you can see what profile is active in the menu's status bar.

## Hacking

If you want to modify this script
or make an entirely new one from scratch,
these links may help.
* https://mpv.io/manual/master/#lua-scripting
* https://github.com/mpv-player/mpv/blob/master/player/lua/defaults.lua
* https://github.com/SenneH/mpv2anki
* https://github.com/kelciour/mpv-scripts/blob/master/subs2srs.lua
* https://pastebin.com/M2gBksHT
* https://pastebin.com/NBudhMUk
* https://pastebin.com/W5YV1A9q
* https://github.com/ayuryshev/subs2srs
* https://github.com/erjiang/subs2srs
