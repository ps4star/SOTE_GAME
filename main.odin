package sote
import "base:runtime"
import "base:intrinsics"

import "core:fmt"
import "core:slice"
import "core:mem"
import "core:time"
import "core:strings"
import "core:log"
import "core:strconv"
import "core:terminal"
import fp "core:path/filepath"
import "core:unicode/utf8"
import "core:os"
import "core:encoding/json"
import sa "core:container/small_array"

import "./lib/clay"
import rl "vendor:raylib"

/*
There are two layers of saved information.
There's a huge list of save files (MAX_SAVES)
which are save-specific data,
then there's the general SData struct which is
anything that's global across save files,
such as mainly user preferences (keybindings etc)
*/
SaveFileData :: struct {
    story_chapter: StoryChapter,
    story_subchapter: int,
    party: [3]BattleEntityID,
    party_stats: [3]BattleEntityIntrinsicStats,
}

DEFAULT_SAVE :: SaveFileData{
    story_chapter = .ChapterOne,
    story_subchapter = 0,
    party = { .Terry, .Viola, .Dex },
}

MAX_SAVES :: 100
SData :: struct {
    i18n_language: i18n_Language,
    input_bindings: InputBindings,

    save: SaveFileData,
    other_saves: [MAX_SAVES-1]SaveFileData,
}

Font :: struct {
    rl_font: rl.Font,
    size: int,
    letter_spacing: f32,
    line_height: f32,
}

UI_FONT :: #load("./embed/ttf/ui_font.ttf", []u8)
UI_FONT_SIZE :: 20
FONT_ID_UI :: 0

TITLE_FONT :: #load("./embed/ttf/ui_font.ttf", []u8)
TITLE_FONT_SIZE :: 42
FONT_ID_TITLE :: 1

IMG_MAIN_MENU_BACKGROUND :: #load("./embed/img/main_menu_background.png")
IMG_SETTINGS_BACKGROUND :: #load("./embed/img/settings.png")
IMG_BATTLE_BACKGROUND_KAERI1 :: #load("./embed/img/battle_kaeri1.png")
IMG_UI_GAUGE :: #load("./embed/img/gauges.png")
IMG_UI_GAUGE_EMPTY_RECT :: rl.Rectangle{ 0,0,600,124 }
IMG_UI_GAUGE_FULL_RECT :: rl.Rectangle{ 0,169,600,124 }

Scene :: enum { MainMenu = 0, Settings, Gameplay, Battle, MusicEditor, }

Globals :: struct {
    base_context: runtime.Context,
    global_allocator: runtime.Allocator,
    global_pool: mem.Dynamic_Arena,
    clay_arena: clay.Arena,

    input_ctl: InputController,
    title_control: TitleScreenController,
    settings_control: SettingsMenuController,
    battle_control: BattleController,
    music_editor: MusicEditor,
    scene: Scene,

    // UI State

    app_path: string,
    sdata_path: string,
    sdata: SData,

    delta: f32,
    fonts: [16]Font,
}
g := Globals{}

DEBUG :: #config(DEBUG, false)

main :: proc() {
	// mem.zero(&g, size_of(g))
    init_global_temporary_allocator(4 * mem.Megabyte)
    context.logger = log.create_console_logger()
    g.base_context = context

    mem.dynamic_arena_init(&g.global_pool, context.allocator, alignment = 1024, block_size = 64 * mem.Kilobyte)
    g.global_allocator = mem.dynamic_arena_allocator(&g.global_pool)

    preload_runtime_init: {
        input_controller_init_default(&g.input_ctl)
    }

    g.sdata.save = DEFAULT_SAVE
    try_load_sdata: {
        assert(len(os.args[0]) > 0)
        g.app_path = fp.dir(os.args[0])

        // Try to load sdata file
        sdata_path, fp_err := fp.join({ g.app_path, "sdata.json" }, g.global_allocator)
        if fp_err != .None {
            break try_load_sdata
        }
        g.sdata_path = sdata_path

        when DEBUG {
            os.remove(g.sdata_path)
            g.sdata.save = DEFAULT_SAVE
            break try_load_sdata
        }

        entire_file_data, entire_file_read_err := os.read_entire_file_from_path(g.sdata_path, context.temp_allocator)
        if entire_file_read_err != os.ERROR_NONE {
            fd, err := os.open(g.sdata_path, { .Create })
            assert(err == os.ERROR_NONE)
            os.close(fd)

            data, marshal_err := json.marshal(g.sdata, {}, context.temp_allocator)
            if marshal_err != json.Marshal_Data_Error.None {
                panic("Could not marshal json")
            }

            json_write_ok := os.write_entire_file_from_bytes(g.sdata_path, data, { .Write_User })
            if json_write_ok != os.ERROR_NONE {
                panic("Could not write json to sdata.json")
            }
            break try_load_sdata
        }

        json_err := json.unmarshal(entire_file_data, &g.sdata, json.DEFAULT_SPECIFICATION, g.global_allocator)
        if json_err != nil {
            panic(fmt.tprintln(json_err))
        }
    }

    runtime_init: {
        title_screen_init(&g.title_control)
        settings_menu_init(&g.settings_control)
        music_editor_init(&g.music_editor, context.allocator, ui_enabled=DEBUG)

        load_font :: proc(mem: []u8, size: int, letter_spacing, line_height: f32) -> (Font) {
            return Font{
                rl_font = rl.LoadFontFromMemory(".ttf", raw_data(mem), i32(len(mem)), i32(size), nil, 0),
                size = size,
                letter_spacing = letter_spacing,
                line_height = line_height,
            }
        }

        rl.SetTargetFPS(60)
        rl.SetConfigFlags({ .VSYNC_HINT, .WINDOW_RESIZABLE, .WINDOW_HIDDEN })
        rl.InitWindow(1280, 720, i18n_get_cstring(.win_title_main))
        rl.SetWindowMinSize(640, 480)
        defer { rl.ClearWindowState({ .WINDOW_HIDDEN }) }

        g.fonts[FONT_ID_UI] = load_font(UI_FONT, UI_FONT_SIZE, 1, 1)
        g.fonts[FONT_ID_TITLE] = load_font(TITLE_FONT, TITLE_FONT_SIZE, 1, 1)

        clay_measure_text :: proc "c" (text: clay.StringSlice, config: ^clay.TextElementConfig, user: rawptr) -> (clay.Dimensions) {
            // context = (transmute(^runtime.Context) user)^
            f := &g.fonts[config.fontId]
            tm := rl.MeasureTextEx(f.rl_font, cstring(text.chars), f32(f.size), f.letter_spacing)
            return {tm[0], tm[1]}
        }

        clay.SetMaxElementCount(196)
        clay_mem_size := clay.MinMemorySize()
        g.clay_arena = clay.CreateArenaWithCapacityAndMemory(uint(clay_mem_size), raw_data(make([]u8, int(clay_mem_size), context.allocator)))
        clay.Initialize(g.clay_arena, {1280, 720}, clay.ErrorHandler{nil, nil})
        clay.SetMeasureTextFunction(clay_measure_text, &g.base_context)

        // Default sdata before trying to load from FS
        g.sdata.i18n_language = .EN
    }

    free_all(context.temp_allocator)
    for !rl.WindowShouldClose() {
        when DEBUG {
            g.scene = .MusicEditor
        }
        g.delta = rl.GetFrameTime()
        cur_sw := int(rl.GetScreenWidth()); cur_sh := int(rl.GetScreenHeight())
        clay.SetLayoutDimensions({ f32(cur_sw), f32(cur_sh) })

        t_start := time.now()

        input_controller_gather_signals(&g.input_ctl)

        tick_all: {
            // must do this globally since this is also our music playback
            music_editor_tick(&g.music_editor)
        }

        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        clay.BeginLayout()

        if g.scene == .MainMenu {
            title_screen_tick(&g.title_control)
            UI_MAIN_MENU_H :: 320
            if clay.UI(clay.ID("main_menu_background"))({
                layout = { sizing = {clay.SizingGrow({}), clay.SizingGrow({})}, layoutDirection = .LeftToRight, childAlignment = {.Left, .Center} },
                custom = element(Element_TitleBackgroundImage{ IMG_MAIN_MENU_BACKGROUND }),
            }) {
                TITLE_BUTTON_PAD :: 48
                if clay.UI(clay.ID("main_menu_buttons"))({
                    layout = { sizing = {clay.SizingFit({}), clay.SizingGrow({})}, layoutDirection = .TopToBottom, childAlignment = {.Left, .Center}, padding={TITLE_BUTTON_PAD,0,0,0} },
                }) {
                    if clay.UI(clay.ID("main_menu_button_start"))({
                        layout = {  sizing = {clay.SizingFit({}), clay.SizingFixed(0)},  },
                        custom = element(Element_TitleButton{ text = .title_button_0, index = 0 }),
                    }) {}

                    if clay.UI(clay.ID("main_menu_button_settings"))({
                        layout = { sizing = {clay.SizingFit({}), clay.SizingFixed(0)}, },
                        custom = element(Element_TitleButton{ text = .title_button_1, index = 1 }),
                    }) {}
                }
            }
        } else if g.scene == .Settings {
            settings_menu_tick(&g.settings_control)
            if clay.UI(clay.ID("settings_background"))({
                layout = { sizing = {clay.SizingGrow({}), clay.SizingGrow({})}, layoutDirection = .LeftToRight, childAlignment = {.Left, .Center} },
                custom = element(Element_SettingsBackgroundImage{ IMG_SETTINGS_BACKGROUND }),
            }) {

            }
        } else if g.scene == .Battle {
            battle_controller_tick(&g.battle_control)
            if clay.UI(clay.ID("battle"))({
                layout = { sizing = {clay.SizingGrow({}), clay.SizingGrow({})}, layoutDirection = .TopToBottom, childAlignment = {.Left, .Bottom} },
                custom = element(Element_Battle{}),
            }) {
                BATTLE_PARTY_CONTAINER_H :: 0.45
                BATTLE_PARTY_GAUGE_W :: 0.3
                BATTLE_PARTY_GAUGE_H :: 12
                BATTLE_PARTY_OPTIONS_H :: 12
                if clay.UI(clay.ID("battle_party_container"))({
                    layout = { sizing = {clay.SizingGrow({}), clay.SizingPercent(BATTLE_PARTY_CONTAINER_H)}, padding = {64,64,64,0}, childAlignment = {.Left, .Top} },
                    custom = element(Element_None{})
                }) {
                    if clay.UI(clay.ID("battle_party_container_gauge"))({
                        layout = { sizing = {clay.SizingPercent(BATTLE_PARTY_GAUGE_W), clay.SizingFixed(BATTLE_PARTY_GAUGE_H)}, padding={4,0,4,0}, },
                        custom = element(Element_BattleGauge{ id = .Terry }),
                    }) {}

                    if clay.UI(clay.ID("battle_options_container"))({
                        layout = { sizing = {clay.SizingPercent(0.5), clay.SizingFixed(BATTLE_PARTY_OPTIONS_H)}, },
                        // custom = element(Element_BattleOption{}),
                    }) {

                    }
                }
            }
        } else if g.scene == .MusicEditor {
            if clay.UI(clay.ID("music_editor"))({
                layout = { sizing = {clay.SizingGrow({}), clay.SizingGrow({})}, layoutDirection = .TopToBottom, childAlignment = {.Left, .Bottom} },
                custom = element(Element_MusicEditor{}),
            }) {
                if g.music_editor.ui.view == .SurfaceTrackView {
                    if sa.len(g.music_editor.midi_tracks) > 0 {
                        if clay.UI(clay.ID("music_editor_tracks_container"))({
                            layout = { sizing = {clay.SizingGrow({}), clay.SizingGrow({})}, layoutDirection = .TopToBottom },
                            custom = element(Element_MusicEditorFrame{}),
                        }) {
                            for midi_trk, index in sa.slice(&g.music_editor.midi_tracks) {
                                MIDI_TRACK_H :: 64
                                if clay.UI(clay.ID("music_editor_track_n", u32(index)))({
                                    layout = { sizing = {clay.SizingGrow({}), clay.SizingFixed(MIDI_TRACK_H)} },
                                    custom = element(Element_MusicEditorTrackSurface{ index = index }),
                                }) {

                                }
                            }
                        }
                    }
                } else if g.music_editor.ui.view == .TrackView {
                    if !(sa.len(g.music_editor.midi_tracks) > 0) {
                        panic("Entered music editor TrackView without any tracks loaded")
                    }

                    if clay.UI(clay.ID("music_editor_track"))({
                        layout = {},
                    }) {

                    }
                }

                if clay.UI(clay.ID("music_editor_prompt"))({
                    layout = { sizing = {clay.SizingGrow({}), clay.SizingFixed(text_height(FONT_ID_UI) + 1)}, },
                    custom = element(Element_MusicEditorPrompt{}),
                }) {}
            }
        }

        cmds := clay.EndLayout()
        for i := i32(0); i < cmds.length; i += 1 {
            cmd := clay.RenderCommandArray_Get(&cmds, i)
            if cmd.commandType == .Custom {
                cust := (^Element_Any)(cmd.renderData.custom.customData)^
                element_render(cmd)
            } else {

            }
        }

        input_controller_update_pointer(&g.input_ctl)
        rl.EndDrawing()
        free_all(context.temp_allocator)
    }
}
