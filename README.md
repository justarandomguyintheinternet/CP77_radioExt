# RadioExt
A mod for CP2077 that allows for the addition of radio stations.

## How to use:

- Have the latest version of the game installed
- Download and install [CET](https://github.com/yamashi/CyberEngineTweaks), latest version
- Download and install [Red4Ext](https://github.com/WopsS/RED4ext), latest version
- Download and install the mod from releases page

## Creating a new station:

### Prerequisites
- Everything from the [How to use](#how-to-use) section
- A text editor with syntax highlighting for editing JSON files (e.g. Sublime Text or VSCode), do **not** skip this, as most issues related to creating stations come from improperly edited JSON files.

### Folder Structure
- First you will need to find the installation directory of your game
- Next, navigate to the radioExt folder: `Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\radioExt`
- In the radioExt folder you will see two items that will be important later: The template `metadata.json` file, and the `radios` folder
	```
	├── radioExt
		└── metadata.json <-- Template file
		└── radios
			└── ...
	```
- Each station is a folder inside the `radios` folder, containing a `metadata.json` file, which contains the information regarding the station
- So to create a new radio station firstly create a new folder inside the `radios` folder, and name it something unique (Like your station's name)
- Next, copy and paste the template `metadata.json` file from the mods root folder and paste it into your station's folder (The folder you created in the previous step)
- The folder structure should now look as follows:
	```
	├── radioExt
		└── radios
			└── folderForYourStation
				└── metadata.json
	```

#### Using Symbolic Links
Not enough space on your game installation drive, or want to place the radio folder somewhere else? No problem! You can put the radio folder wherever you like and then use a **symbolic link** to connect it to `Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\radioExt\radios`. The steps are simple:
- Press **Windows+R**
- Type `cmd` in the Run window
- Press **Ctrl+Shift+Enter** to open the command prompt as an administrator
- Enter the command `mklink /D [link] [target]` and press Enter to create the symbolic link. For example, if you want every directory under `D:\Music` to serve as a radio directory, and your game is installed at `E:\SteamLibrary\steamapps\common\Cyberpunk 2077`, then the command should be:  
  `mklink /D "E:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\radioExt\radios" "D:\Music"`

##### Note:
- **Symbolic links are not shortcuts**; the mod does not support pointing the radio folder via shortcuts.
- On Windows, symbolic links are supported only on the NTFS file system.
- If you encounter compatibility issues, try deleting the symbolic link and moving the radio folder directly to its default location.
- Generally, placing the radio folder on an HDD won’t noticeably affect performance, but if you have a large number of audio files or run into performance issues, consider moving the radio folder to an SSD.

### Adding Songs
- To add songs to your station, simply copy the song files into your station's folder
- Supported formats are: `.mp3`, `.wav`, `.ogg`, `.flac`, `.mp2`, `.wax`, `.wma`
- Keep in mind that the songs file names are being used as song names in-game, so keep them clean
- If you want to use a web audio stream instead of files shipped with your station, refer to the [Web Streams](#web-streams) section

### Metadata File

- The `metadata.json` file of your stations defines its properties such as the name, icon and more.
- Open it with any text editor that has **syntax highlighting for JSON files**, do **not** skip this, as most issues related to creating stations come from improperly edited JSON files.
- If your `metadata.json` file is missing any properties that have been added in an update of the mod, simply run the game once with the updated version of the mod installed, as that will add the missing fields automatically
- For properties that use strings (Such as `displayName`) any [reserved characters](https://www.lambdatest.com/free-online-tools/json-escape) need to properly escaped, again any half decent text editor will let you know if you missed any.

#### Basic Properties
- `displayName`: This controls the name of your station that will be displayed in the game
- `fm`: A number (Do not put it in quotation marks), which is used to place the station at the right place in the stations list. If the `displayName` has an FM number, it should be the same
- `volume`: Overall volume multiplier for the station (Also a number), make sure all songs have the same volume, then adjust the overall volume of the station with this value to match up with vanilla stations
- `icon`: The icon for the station, if you don't use a custom one. It can be any `UIIcon.` record. To find a list of all records, open the CET console's `TweakDB Editor` tab, and enter `UIIcon.` in the search bar (Make sure you have the [tweakdb.str](https://cdn-l-cyberpunk.cdprojektred.com/metadata-1.5.2.zip) file placed inside the `Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks` folder)

#### Custom Icon
- All settings related to custom icons are inside the `customIcon` section of a stations `metadata.json` file
- `useCustom`: If this is set to `false` the icon specified inside `icon` will be used. If set to true the custom icon will be used
- `inkAtlasPath` points to the `.inkatlas` that holds the icon texture, e.g. `base\\gameplay\\gui\\world\\vending_machines\\atlas_roach_race.inkatlas` (Path requires double backslashes `\\`)
- `inkAtlasPart` specifies which part of the `.inkatlas` should be used for the icon, e.g. `gryphon_5`
- To create your own `.inkatlas` file, use [WolvenKit](https://github.com/WolvenKit/WolvenKit)
- Written tutorials can be found [here](https://wiki.redmodding.org/cyberpunk-2077-modding/for-mod-creators/modding-guides/custom-icons-and-ui) (The tutorials are for clothing / item icons, but the exact same process applies to radio station icons)
- A video tutorial can be found [here](https://www.youtube.com/watch?v=N8C8SaRypog) (WKit interface has changed a bit since the video has been made, so not everything shown there is at the same place anymore, but the general process is still the exact same)

#### Web Streams
- Instead of using song files placed in the station's folder, you can also use any web audio streams (URL's that end in e.g. `.mp3`, and display the default audio player when opened, e.g. `https://radio.garden/api/ara/content/listen/TP8NDBv7/channel.mp3`) and Youtube streams
- Some examples can be found [here](https://truck-simulator.fandom.com/wiki/Radio_Stations#Radio_Stations_by_country), but also most stations from [here](https://radio.garden) can be used
- `isStream`: This must be set to true for the mod to try to stream from the specified URL
- `streamURL`: URL of the stream
- For audio streams, FMOD only supports them if the response is HTTP/1.0. If the `streamURL` responds with HTTP/1.1+, local Icecast server and FFmpeg relay will be used
- For Youtube streams, the combination of yt-dlp, FFmpeg and an Icecast server will be used
- Icecast server and all relays for stations that require them will be started on game launch automatically
- The pre-built mod release comes bundled with ffmpeg, icecast and yt-dlp. However, it is possible to provide your own executables instead. For this, you should:
  1. Get [Icecast](https://icecast.org/download/) and install it anywhere
  2. Copy contents from your installed `Icecast\bin` into `Cyberpunk 2077\red4ext\plugins\RadioExt\icecast` and `Icecast\icecast.xml` into `Cyberpunk 2077\red4ext\plugins\RadioExt\icecast`
  3. Copy `Icecast\log` into `Cyberpunk 2077\red4ext\plugins\RadioExt`
  4. Get [FFmpeg](https://ffmpeg.org/download.html) and [yt-dlp](https://github.com/yt-dlp/yt-dlp). We only need the ffmpeg.exe and yt-dlp.exe
  5. You can either:
     1. Install them as usual and and them to **PATH** 
     2. Copy both executables into `Cyberpunk 2077\red4ext\plugins\RadioExt`
    
  6. Mod will look for executables in `Cyberpunk 2077\red4ext\plugins\RadioExt` first, and will try to get them from **PATH** if there are none. If any issues arise please revert to the provided binaries, or try to get the version on which the mod was tested: ffmpeg version `2025-04-17-git-7684243fbe-full_build-www.gyan.dev`, yt-dlp version `2025.03.31`
- To post relays the default icecast server properties are used. The server should only be available locally, however, if you wish to additionally secure it, you'd have to change the logins and passwords in `Cyberpunk 2077\red4ext\plugins\RadioExt\icecast\icecast.xml` and `Cyberpunk 2077\red4ext\plugins\RadioExt\icecast_credentials.txt`


#### Song Ordering
- The `order` field can be used to specify an order in which the songs should be played
- It must not contain all the songs of the station, any songs not specified in the `order` will be played randomly before / after the ordered section
- Simply add all the songs file names that you want ordered in the field, each as its own string and comma separated:
```json
"order": [
     "firstSongFile.mp3",
	 "secondSongFile.mp3",
	 "thirdSongFile.mp3"
]
```

## Configuration Options
- Mod configuration file location:  
  `Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\radioExt`

> `enableCustomStationsInWorldRadios`
- **Boolean** (`true`/`false`)  
  When `true`: Custom stations become available on **world radios** (environmental radio devices).  
  When `false`: Custom stations only work on **vehicle radios**/player's portable radio.  
  Default: `true`

> `includeCustomStationsInRandom`
- **Boolean** (`true`/`false`)  
  When `true`: World radios will **randomize to custom stations**.  
  When `false`: World radios only cycle through **vanilla stations**.  
  Default: `false`  
  **⚠️ Warning:** Only enable this if you fully understand the implications. See important notes below.

## ⚠️ Important Notes

### Save File Safety
- **World radio modifications are PERSISTENT**  
  If you save the game with a world radio tuned to custom stations:
  - Radio will become **silent** after mod uninstallation
  - Recovery requires **manual intervention**

### 🔴 Critical Exceptions
- **Growl FM Party Radio Corruption**  
  Visiting the "Growl FM Party" scene with both settings enabled：
  ```
  includeCustomStationsInRandom = true
  enableCustomStationsInWorldRadios = true
  ```
  
  **Permanent consequences:**
  - Radio stuck on incorrect station (can't switch)
  - Original Growl FM content fails to play
  - No recovery through normal gameplay

### Recovery Options
1. **Before uninstalling**:  
   Tune all modified world radios back to **vanilla stations**
2. **After uninstalling**:  
   Cycle station once on affected radios to restore functionality

### Critical Limitations
- 🔴 `enableCustomStationsInWorldRadios = false` **WILL NOT**  
  - Fix existing modified radios in save files  
  - Remove custom station assignments  
  *Manual reset is always required*

### Safety Lock Mechanism
World radios **will NEVER auto-randomize** to custom stations unless:
```lua
-- Both conditions must be true
enableCustomStationsInWorldRadios = true
includeCustomStationsInRandom = true
```

## Troubleshooting
- If anything does not work as expected, firstly make sure that all the points of the [How to use](#how-to-use) section are fulfilled, and the required mods are working properly
- The mod prints messages to the CET console for most of the common issues, so open the CET console and look for any `"[RadioExt] Error/Warning: ..."` messages
>`"[RadioExt] Error: Red4Ext part of the mod is missing"`
- This means that the Red4Ext parts are either not installed, or could not be loaded by Red4Ext. Make sure you are on the most recent version of the game, and have the correct version of Red4Ext installed (Version of the game, version of Red4Ext and version of this mod must be compatible with each other). Also make sure that both the `RadioExt.dll` and `fmod.dll` files are present inside `Cyberpunk 2077\red4ext\plugins\RadioExt`
> `"[RadioExt] Red4Ext Part is not up to date: Version is xxx Expected: xxx or newer"`
- Make sure that the files inside `Cyberpunk 2077\red4ext\plugins\RadioExt` come from the same version of the mod you downloaded. Doing a clean install of the mod can help.
> `[RadioExt] Could not find metadata.json file in "radios/folderName""`
 - This means that you forgot to add the `metadata.json file` (See [Folder Structure](#folder-structure) section)
> `[RadioExt] Error: Failed to load the metadata.json file for "stationFolderName". Make sure the file is valid.`
- This means the `metadata.json` file is corrupted / not valid. Usually caused by missing brackets, commas or parentheses. Can also be caused by not properly escaped characters. Make sure to use a text editor with syntax highlighting / JSON validation.
> `[RadioExt] Warning: Failed to load the settings.json,use default settings.`
- This means the `settings.json` file is corrupted / not valid / lacks essential configuration entries. Usually caused by missing brackets, commas or parentheses. Can also be caused by not properly escaped characters. Make sure to use a text editor with syntax highlighting / JSON validation.
> `"[RadioExt] Warning: The file "songFile.mp3" requested for the ordering of station "Station Name" was not found."`
- Make sure the file you specified in the `order` field does exist and that its filename is spelled properly
>`"[RadioExt] Error: Station "Station Name" is not a stream, but also has no song files. Using fallback webstream instead."`
- This happens if there are no song files in a station's folder, but the `isStream` flag in its `metadata.json` file is also not set to `true`
>`[RadioExt] Error: All channels used (Too many radios)`
- This happens if there are more physical radios playing a custom station than there are audio channels reserved by the mod (Currently 256, so this is extremely unlikely to ever happen)


#### Credits
- Uses [FMOD](https://www.fmod.com/) by Firelight Technologies
- [psiberx](https://github.com/psiberx/cp2077-cet-kit) for Cron.lua, GameUI.lua and GameSettings.lua
- [WSS](https://github.com/WSSDude420) for letting me use some of his C++ code

## Licenses for Included Software

This project bundles third-party executables:

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) - Unlicense / Public Domain
- [FFmpeg](https://ffmpeg.org/) - LGPL 2.1+ Licensed
- [Icecast](https://icecast.org/) - GPL 2.0 Licensed
- [curl](https://curl.se/) (MIT/X curl license)

See the LICENSES/ folder for details and license texts.
