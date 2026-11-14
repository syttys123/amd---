use crate::state::UiMode;

pub const SIMPLE_CLIENT_SIZE: (i32, i32) = (600, 360);
pub const ADVANCED_CLIENT_SIZE: (i32, i32) = (780, 680);
pub const ADVANCED_CONTENT_WIDTH: i32 = 760;

/// Painting and child placement must share the same scrollable canvas.
pub fn content_width(mode: UiMode, viewport_width: i32) -> i32 {
    minimum_client_size(mode).0.max(viewport_width)
}

pub fn minimum_client_size(mode: UiMode) -> (i32, i32) {
    match mode {
        UiMode::Simple => (560, 360),
        UiMode::Advanced => (ADVANCED_CONTENT_WIDTH, 420),
    }
}

/// Window-level minimum client size. Advanced keeps the 760 px content width
/// and scrolls horizontally when the work area is narrower (for example
/// 1366x768 at 200% scaling), so the window never exceeds the screen.
pub fn minimum_window_client_size(mode: UiMode) -> (i32, i32) {
    match mode {
        UiMode::Simple => minimum_client_size(mode),
        UiMode::Advanced => (560, 420),
    }
}

pub fn scroll_position(position: i32, content_height: i32, viewport_height: i32) -> i32 {
    position.clamp(0, (content_height - viewport_height).max(0))
}

/// One scrollbar page equals one viewport. Kept in logical pixels so both
/// axes and the scrollbar's `SIF_PAGE` value stay in sync.
pub fn page_scroll(position: i32, viewport: i32, forward: bool) -> i32 {
    let viewport = viewport.max(1);
    if forward {
        position.saturating_add(viewport)
    } else {
        position.saturating_sub(viewport)
    }
}

#[derive(Debug, Clone, Copy)]
pub struct CommandLayout {
    pub width: i32,
    pub target_left: i32,
    pub target_width: i32,
    pub apply_left: i32,
    pub apply_width: i32,
    pub preset_left: i32,
    pub preset_width: i32,
    pub edit_left: i32,
}

impl CommandLayout {
    pub fn new(width: i32) -> Self {
        let target_left = width / 2 + 12;
        let target_width = width - target_left - 24;
        let apply_left = target_left + 112;
        let preset_left = 96;
        let preset_width = (width - preset_left - 24 - 44 - 3 * 8) / 3;
        Self {
            width,
            target_left,
            target_width,
            apply_left,
            apply_width: width - 24 - apply_left,
            preset_left,
            preset_width,
            edit_left: width - 24 - 44,
        }
    }

    pub fn preset_x(self, slot: i32) -> i32 {
        self.preset_left + slot * (self.preset_width + 8)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scrollable_canvas_preserves_geometry_in_narrow_viewports() {
        for viewport in [480, 560, 600, 740, 759, 760, 780, 1200] {
            let width = content_width(UiMode::Advanced, viewport);
            assert_eq!(width, viewport.max(ADVANCED_CONTENT_WIDTH));
            let layout = CommandLayout::new(width);
            assert_eq!(layout.edit_left + 44, width - 24);
            assert_eq!(layout.apply_left + layout.apply_width, width - 24);
        }
        assert_eq!(content_width(UiMode::Simple, 480), 560);
        assert_eq!(content_width(UiMode::Simple, 600), 600);
    }

    #[test]
    fn command_controls_fit_at_minimum_and_expanded_widths() {
        for width in [560, 600, 780, 960, 1200] {
            let layout = CommandLayout::new(width);
            assert!(layout.apply_width >= 120);
            assert!(layout.preset_width >= 112);
            assert!(layout.target_left > 270);
            assert!(layout.preset_x(2) + layout.preset_width + 8 <= layout.edit_left);
            assert_eq!(layout.edit_left + 44, width - 24);
            assert_eq!(layout.apply_left + layout.apply_width, width - 24);
        }
    }

    #[test]
    fn advanced_content_can_scroll_in_a_short_viewport() {
        assert_eq!(minimum_client_size(UiMode::Advanced), (760, 420));
        assert_eq!(minimum_window_client_size(UiMode::Advanced), (560, 420));
        assert_eq!(ADVANCED_CONTENT_WIDTH, 760);
        assert_eq!(scroll_position(1000, 680, 420), 260);
        assert_eq!(scroll_position(-10, 680, 420), 0);
        assert_eq!(scroll_position(50, 680, 720), 0);
    }

    #[test]
    fn simple_content_can_scroll_when_the_work_area_is_short() {
        assert_eq!(SIMPLE_CLIENT_SIZE, (600, 360));
        assert_eq!(scroll_position(-10, 360, 300), 0);
        assert_eq!(scroll_position(20, 360, 300), 20);
        assert_eq!(scroll_position(1000, 360, 300), 60);
        assert_eq!(scroll_position(50, 360, 360), 0);
    }

    #[test]
    fn page_scroll_moves_exactly_one_viewport() {
        assert_eq!(page_scroll(0, 420, true), 420);
        assert_eq!(page_scroll(420, 420, false), 0);
        assert_eq!(page_scroll(0, 0, true), 1);
        assert_eq!(scroll_position(page_scroll(0, 420, true), 680, 420), 260);
    }

    #[test]
    fn maximizing_clamps_a_previously_scrolled_offset() {
        // Advancing from a 420 px viewport to the full 680 px content height
        // makes the old 260 px offset invalid; the maximize path must re-clamp.
        assert_eq!(scroll_position(260, 680, 420), 260);
        assert_eq!(scroll_position(260, 680, 680), 0);
    }
}
