package sote
import "core:fmt"
import "core:strings"
import "core:reflect"

i18n_Language :: enum {
    EN,
    DE,
    FR,
    ES,
}

i18n :: enum {
    none = 0,
    debug,
    debug2,
    win_title_main,
    game_title,
    title_button_0,
    title_button_1,
    title_button_2,

    story_ch1_0,
    story_ch1_1,
    story_ch1_2,
    story_ch1_3,
    story_ch1_4,
    story_ch1_5,
    story_ch1_6,

    story_ch2_0,
    story_ch2_1,
    story_ch2_2,
    story_ch2_3,
    story_ch2_4,
    story_ch2_5,
    story_ch2_6,
}

i18n_lut := #partial [i18n][i18n_Language]string{
    .none = #partial {
        .EN = "???",
        .DE = "???",
        .FR = "???",
        .ES = "???",
    },
    .debug = #partial {
        .EN = "debug",
        .DE = "debug",
        .FR = "debug",
        .ES = "debug",
    },
    .debug2 = #partial {
        .EN = "debug2",
        .DE = "debug2",
        .FR = "debug2",
        .ES = "debug2",
    },
    .win_title_main = #partial {
        .EN = "Song of the Earth",
        .DE = "Lied der Erde",
        .FR = "Chant de la Terre",
        .ES = "Canto de la Tierra",
    },
    .game_title = #partial {
        .EN = "SONG OF THE EARTH",
        .DE = "LIED DER ERDE",
        .FR = "CHANT DE LA TERRE",
        .ES = "CANTO DE LA TIERRA",
    },
    .title_button_0 = #partial {
        .EN = "Begin Adventure",
        .DE = "Spiel Starten",
        .FR = "Démarrer le Jeu",
        .ES = "Iniciar Juego",
    },
    .title_button_1 = #partial {
        .EN = "Settings",
        .DE = "Einstellungen",
        .FR = "Paramètres",
        .ES = "Configuración",
    },
    .story_ch1_0 = #partial {
        .EN = "The Apple Orchard",
    },
    .story_ch1_1 = #partial {
        .EN = "Fire",
    },
    .story_ch1_2 = #partial {
        .EN = "Night Terrors",
    },
    .story_ch1_3 = #partial {
        .EN = "Remnant",
    },
}

i18n_get :: proc(name: i18n, loc := #caller_location) -> (string) {
    if !reflect.enum_value_has_name(name) {
        panic(fmt.tprintln("i18n: no such key", name, " @", loc))
    }
    lut_result := &i18n_lut[name]
    return lut_result[g.sdata.i18n_language]
}

i18n_get_cstring :: proc(name: i18n, loc := #caller_location) -> (cstring) {
    str := i18n_get(name, loc)
    return strings.clone_to_cstring(str, context.temp_allocator)
}