#+feature dynamic-literals
package sote
import "base:runtime"
import "vendor:ENet"
import "base:intrinsics"

import "core:fmt"
import "core:strings"
import sa "core:container/small_array"
import ba "core:container/bit_array"

import rl "vendor:raylib"

BATTLE_FADE_SPEED :: 1.25
PARTY_FADE_SPEED :: 1.6
BATTLE_GAUGE_SPEED :: 0.3

@private ActionSequencer :: struct {
    action: ^Action,
    index: int,
    clock: f32,
}

@private action_sequencer_init :: proc(this: ^ActionSequencer, action: ^Action) {
    this^ = {
        action = action,
        index = 0,
        clock = 0.0,
    }
}

@private action_sequencer_tick :: proc(this: ^ActionSequencer, id: BattleEntityID) {
    this.clock += g.deltas
    for this.clock >= this.action.sequence[this.index].time_before {
        // Fire event
        {
            this_event := &this.action.sequence[this.index]
            if this_event.procedure != nil {
                this_event.procedure(this, id)
            }
        }
        this.clock -= this.action.sequence[this.index].time_before
        this.index += 1
    }
}

@private ActionSequencerEvent :: struct {
    time_before: f32,
    procedure: proc(this: ^BattleController, id: BattleEntityID),
}

ActionID :: enum {
    DEBUG = 0,
    STR_STRIKE,

    OBL_BREAK,

    BST_EMBOLDEN,

    MAN_FATIGUE,

    RES_RESTORE,
    RES_RESTORE_ALL,
    RES_REVIVE,
}

@private Action :: struct {
    targeting: enum { ONE_OPPOSING, ONE_ALLY, ALL_OPPOSING, ALL_ALLY },
    visual_name: i18n,
    sequence: []ActionSequencerEvent,
}

@private action_table := [ActionID]Action{
    .DEBUG = {},
    .STR_STRIKE = {
        targeting = .ONE_OPPOSING,
        visual_name = .action_STR_STRIKE,
        sequence = {
            // 
            {time_before = 0.0, procedure = proc(this: ^BattleController, id: BattleEntityID) {
                
            }},
            // 
            {time_before = 0.5, procedure = proc(this: ^BattleController, id: BattleEntityID) {
                
            }},
        },
    },

    .OBL_BREAK = {
        targeting = .ONE_OPPOSING,
        visual_name = .action_OBL_BREAK,
    },

    .BST_EMBOLDEN = {
        targeting = .ONE_ALLY,
        visual_name = .action_BST_EMBOLDEN,
    },

    .MAN_FATIGUE = {
        targeting = .ONE_OPPOSING,
        visual_name = .action_MAN_FATIGUE,
    },

    .RES_RESTORE = {},
    .RES_RESTORE_ALL = {},
    .RES_REVIVE = {},
}

BattleEntityID :: enum {
    NONE = 0,
    TERRY,
    VIOLA,
    DEX,

    DEBUG_ENEMY,
}

BattleEntityState :: enum {
    BUFFERING = 0,
    APPROACHING_TARGET_BEFORE_MOVE,
    USING_MOVE,
}

BattleEntity :: struct {
    id: BattleEntityID,
    intrinsic_data: struct {
        hp, stre, intl: int,
        gauge_segments: int,
        
    },
    volatile_data: struct {
        hp, max_hp: int,
        
    },
    state: BattleEntityState,

    // Gauge state
    gauge_progress: f32,
    gauge_segments_filled: int, // Must sync with gauge_progress state

    // Sequencer
    action_sequencer: struct {
        action: ^Action,
        index: int,
        clock: f32,
    },
}

BattleController :: struct {
    background_img: []u8,
    fade_progress: f32,
    party_fade_progress: f32,
    entities: sa.Small_Array(16, BattleEntity),
}

battle_controller_setup :: proc(this: ^BattleController, background_img: []u8) {
    this^ = {}
    this.background_img = background_img
    for i := 0; i < sa.len(g.sdata.save.party); i += 1 {
        if g.sdata.save.party[i] == .None { break }
        sa.push_back(&this.entities, BattleEntity{})
        added := sa.get_ptr(&this.entities, sa.len(this.entities)-1)
        init_entity_with_stats(added, i)
    }
}

battle_controller_get_gauge :: proc(this: ^BattleController, id: BattleEntityID) -> (f32) {
    for _, i in sa.slice(&this.entities) {
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

    for &entity in sa.slice(&this.entities) {
        progress_linear(&entity.gauge_progress, BATTLE_GAUGE_SPEED)
    }
}
