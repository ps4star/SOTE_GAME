package sote
// import "base:runtime"
// import "vendor:ENet"
import "base:intrinsics"

import "core:fmt"
// import "core:strings"
import sa "core:container/small_array"

// import rl "vendor:raylib"

BATTLE_FADE_SPEED :: 1.25
PARTY_FADE_SPEED :: 1.6
BATTLE_GAUGE_SPEED :: 0.3

BattleEntityID :: enum {
    None = 0,
    Terry,
    Viola,
    Dex,

    DebugEnemy,
}

BattleEntityMovementState :: enum {
    StandingStill = 0,
    ApproachingOtherSideTarget,
}

BattleEntity :: struct {
    id: BattleEntityID,
    intrinsic_stats: BattleEntityIntrinsicStats,
    dynamic_stats: BattleEntityDynamicStats,
    movement_state: BattleEntityMovementState,
    offset_transition_progress: f32,
    gauge_progress: f32,
}

BattleEntityIntrinsicStats :: struct {
    hp, stre, intl: int,
}

BattleEntityDynamicStats :: struct {
    hp, max_hp, stre, intl: f32,
}

BattleController :: struct {
    background_img: []u8,
    fade_progress: f32,
    party_fade_progress: f32,
    entities: sa.Small_Array(16, BattleEntity),
}

intrinsic_to_dynamic_stats :: proc(is: BattleEntityIntrinsicStats) -> (BattleEntityDynamicStats) {
    return {
        hp = f32(is.hp), max_hp = f32(is.hp),
        stre = f32(is.stre), intl = f32(is.intl),
    }
}

battle_controller_setup :: proc(this: ^BattleController, background_img: []u8) {
    this^ = {}
    this.background_img = background_img
    for i := 0; i < len(g.sdata.save.party); i += 1 {
        if g.sdata.save.party[i] == .None { break }
        sa.push_back(&this.entities, BattleEntity{
            id = g.sdata.save.party[i],
            intrinsic_stats = g.sdata.save.party_stats[i],
            dynamic_stats = intrinsic_to_dynamic_stats(g.sdata.save.party_stats[i]),
            movement_state = .StandingStill,
        })
    }
}

battle_controller_get_gauge :: proc(this: ^BattleController, id: BattleEntityID) -> (f32) {
    for _, i in this.entities.data[:this.entities.len] {
        if this.entities.data[i].id == id {
            return this.entities.data[i].gauge_progress
        }
    }
    return -1
}

battle_controller_tick :: proc(this: ^BattleController) {
    if this.fade_progress < 1.0 {
        progress_linear(&this.fade_progress, BATTLE_FADE_SPEED)
        return
    }
    if this.party_fade_progress < 1.0 {
        progress_linear(&this.party_fade_progress, PARTY_FADE_SPEED)
        return
    }

    for &entity in this.entities.data[:this.entities.len] {
        progress_linear(&entity.gauge_progress, BATTLE_GAUGE_SPEED)
    }
}