#+feature dynamic-literals
package sote

import "core:reflect"

StoryChapter :: enum {
    ChapterOne,
    ChapterTwo,
    ChapterThree,
    ChapterFour,
    ChapterFive,
}

StoryChapterData :: struct {
    num_subchapters: int,
}

STORY_CHAPTERS := [StoryChapter]StoryChapterData{
    .ChapterOne = {
        // TheAppleLady
        // Fire
        // NightTerrors
        // Remnant
        num_subchapters = 4,
    },
    .ChapterTwo = {
        num_subchapters = 1,
    },
    .ChapterThree = {
        num_subchapters = 1,
    },
    .ChapterFour = {
        num_subchapters = 1,
    },
    .ChapterFive = {
        num_subchapters = 1,
    },
}

advance_subchapter :: proc() {
    g.sdata.save.story_subchapter += 1
    if g.sdata.save.story_subchapter >= STORY_CHAPTERS[g.sdata.save.story_chapter].num_subchapters {
        g.sdata.save.story_subchapter = 0
        g.sdata.save.story_chapter = StoryChapter(int(g.sdata.save.story_chapter) + 1)
    }
}