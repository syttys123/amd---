#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RunPhase {
    Starting,
    Running,
    Exiting,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WindowVisibility {
    Hidden,
    Visible,
    Minimized,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LifecycleAction {
    AddTrayIcon,
    RemoveTrayIcon,
    ShowWindow,
    MinimizeWindow,
    HideWindow,
    BringToForeground,
    ExitMessageLoop,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LifecycleEvent {
    StartupRequested { start_hidden: bool },
    MinimizeRequested,
    WindowMinimized,
    CloseRequested,
    WindowHidden,
    WindowShown,
    TrayShowRequested,
    TrayExitRequested,
    SecondInstanceWakeRequested,
    ProcessPendingWake,
    ExitRequested,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Transition {
    pub accepted: bool,
    pub actions: Vec<LifecycleAction>,
}

impl Transition {
    fn accepted(actions: Vec<LifecycleAction>) -> Self {
        Self {
            accepted: true,
            actions,
        }
    }

    fn ignored() -> Self {
        Self {
            accepted: false,
            actions: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LifecycleState {
    phase: RunPhase,
    visibility: WindowVisibility,
    tray_present: bool,
    wake_pending: bool,
}

impl Default for LifecycleState {
    fn default() -> Self {
        Self {
            phase: RunPhase::Starting,
            visibility: WindowVisibility::Hidden,
            tray_present: false,
            wake_pending: false,
        }
    }
}

impl LifecycleState {
    pub fn phase(&self) -> RunPhase {
        self.phase
    }

    pub fn visibility(&self) -> WindowVisibility {
        self.visibility
    }

    pub fn tray_present(&self) -> bool {
        self.tray_present
    }

    pub fn wake_pending(&self) -> bool {
        self.wake_pending
    }

    pub fn handle_event(&mut self, event: LifecycleEvent) -> Transition {
        if self.phase == RunPhase::Exiting
            && !matches!(
                event,
                LifecycleEvent::ExitRequested
                    | LifecycleEvent::TrayExitRequested
                    | LifecycleEvent::WindowHidden
            )
        {
            return Transition::ignored();
        }

        match event {
            LifecycleEvent::StartupRequested { start_hidden } => {
                if self.phase != RunPhase::Starting {
                    return Transition::ignored();
                }

                self.phase = RunPhase::Running;
                self.visibility = if start_hidden {
                    WindowVisibility::Hidden
                } else {
                    WindowVisibility::Visible
                };
                self.tray_present = true;
                Transition::accepted(vec![LifecycleAction::AddTrayIcon])
            }
            LifecycleEvent::MinimizeRequested => {
                if self.phase != RunPhase::Running {
                    return Transition::ignored();
                }

                match self.visibility {
                    WindowVisibility::Visible => {
                        self.visibility = WindowVisibility::Minimized;
                        Transition::accepted(vec![LifecycleAction::MinimizeWindow])
                    }
                    WindowVisibility::Minimized | WindowVisibility::Hidden => {
                        Transition::ignored()
                    }
                }
            }
            LifecycleEvent::WindowMinimized => {
                if self.phase != RunPhase::Running {
                    return Transition::ignored();
                }

                self.visibility = WindowVisibility::Minimized;
                Transition::accepted(Vec::new())
            }
            LifecycleEvent::CloseRequested => {
                if self.phase != RunPhase::Running {
                    return Transition::ignored();
                }

                if self.visibility == WindowVisibility::Hidden {
                    return Transition::ignored();
                }

                self.visibility = WindowVisibility::Hidden;
                Transition::accepted(vec![LifecycleAction::HideWindow])
            }
            LifecycleEvent::WindowHidden => {
                if self.phase != RunPhase::Running {
                    return Transition::ignored();
                }

                self.visibility = WindowVisibility::Hidden;
                Transition::accepted(Vec::new())
            }
            LifecycleEvent::WindowShown => {
                if self.phase != RunPhase::Running {
                    return Transition::ignored();
                }

                self.visibility = WindowVisibility::Visible;
                Transition::accepted(Vec::new())
            }
            LifecycleEvent::TrayShowRequested => {
                if self.phase != RunPhase::Running {
                    return Transition::ignored();
                }

                self.wake_pending = false;
                self.visibility = WindowVisibility::Visible;
                Transition::accepted(vec![
                    LifecycleAction::ShowWindow,
                    LifecycleAction::BringToForeground,
                ])
            }
            LifecycleEvent::SecondInstanceWakeRequested => {
                if self.phase != RunPhase::Running {
                    return Transition::ignored();
                }

                self.wake_pending = true;
                Transition::accepted(Vec::new())
            }
            LifecycleEvent::ProcessPendingWake => {
                if self.phase != RunPhase::Running || !self.wake_pending {
                    return Transition::ignored();
                }

                self.wake_pending = false;
                self.visibility = WindowVisibility::Visible;
                Transition::accepted(vec![
                    LifecycleAction::ShowWindow,
                    LifecycleAction::BringToForeground,
                ])
            }
            LifecycleEvent::TrayExitRequested | LifecycleEvent::ExitRequested => {
                self.stop()
            }
        }
    }

    fn stop(&mut self) -> Transition {
        if self.phase == RunPhase::Exiting {
            return Transition::ignored();
        }

        self.phase = RunPhase::Exiting;
        self.visibility = WindowVisibility::Hidden;
        self.wake_pending = false;
        let mut actions = Vec::new();
        if self.tray_present {
            self.tray_present = false;
            actions.push(LifecycleAction::RemoveTrayIcon);
        }
        actions.push(LifecycleAction::ExitMessageLoop);
        Transition::accepted(actions)
    }
}

#[cfg(test)]
mod tests {
    use super::{
        LifecycleAction, LifecycleEvent, LifecycleState, RunPhase, Transition, WindowVisibility,
    };

    fn running_visible() -> LifecycleState {
        let mut state = LifecycleState::default();
        let transition = state.handle_event(LifecycleEvent::StartupRequested {
            start_hidden: false,
        });
        assert_eq!(
            transition,
            Transition::accepted(vec![LifecycleAction::AddTrayIcon])
        );
        state
    }

    #[test]
    fn startup_can_hide_directly_to_tray() {
        let mut state = LifecycleState::default();

        let transition = state.handle_event(LifecycleEvent::StartupRequested {
            start_hidden: true,
        });

        assert_eq!(
            transition,
            Transition::accepted(vec![LifecycleAction::AddTrayIcon])
        );
        assert_eq!(state.phase(), RunPhase::Running);
        assert_eq!(state.visibility(), WindowVisibility::Hidden);
        assert!(state.tray_present());
    }

    #[test]
    fn minimize_stays_in_the_taskbar() {
        let mut state = running_visible();

        let transition = state.handle_event(LifecycleEvent::MinimizeRequested);

        assert_eq!(
            transition,
            Transition::accepted(vec![LifecycleAction::MinimizeWindow])
        );
        assert_eq!(state.visibility(), WindowVisibility::Minimized);
        assert!(state.tray_present());
    }

    #[test]
    fn minimize_notification_never_hides_to_tray() {
        let mut state = running_visible();
        state.handle_event(LifecycleEvent::MinimizeRequested);

        let transition = state.handle_event(LifecycleEvent::WindowMinimized);

        assert!(transition.accepted);
        assert!(transition.actions.is_empty());
        assert_eq!(state.visibility(), WindowVisibility::Minimized);
        assert!(state.tray_present());
    }

    #[test]
    fn duplicate_minimize_request_is_idempotent() {
        let mut state = running_visible();
        state.handle_event(LifecycleEvent::MinimizeRequested);

        let transition = state.handle_event(LifecycleEvent::MinimizeRequested);

        assert_eq!(transition, Transition::ignored());
        assert_eq!(state.visibility(), WindowVisibility::Minimized);
    }

    #[test]
    fn close_request_hides_to_tray_without_exiting() {
        let mut state = running_visible();

        let transition = state.handle_event(LifecycleEvent::CloseRequested);

        assert_eq!(
            transition,
            Transition::accepted(vec![LifecycleAction::HideWindow])
        );
        assert_eq!(state.phase(), RunPhase::Running);
        assert_eq!(state.visibility(), WindowVisibility::Hidden);
        assert!(state.tray_present());
    }

    #[test]
    fn hidden_notification_after_close_does_not_reenter_hide() {
        let mut state = running_visible();
        state.handle_event(LifecycleEvent::CloseRequested);

        let transition = state.handle_event(LifecycleEvent::WindowHidden);

        assert!(transition.accepted);
        assert!(transition.actions.is_empty());
        assert_eq!(state.phase(), RunPhase::Running);
    }

    #[test]
    fn tray_show_restores_from_hidden_and_minimized() {
        for minimize_first in [false, true] {
            let mut state = running_visible();
            if minimize_first {
                state.handle_event(LifecycleEvent::MinimizeRequested);
            } else {
                state.handle_event(LifecycleEvent::CloseRequested);
            }

            let transition = state.handle_event(LifecycleEvent::TrayShowRequested);

            assert_eq!(
                transition,
                Transition::accepted(vec![
                    LifecycleAction::ShowWindow,
                    LifecycleAction::BringToForeground,
                ])
            );
            assert_eq!(state.visibility(), WindowVisibility::Visible);
        }
    }

    #[test]
    fn second_instance_wake_is_queued_for_the_ui_thread() {
        let mut state = running_visible();
        state.handle_event(LifecycleEvent::CloseRequested);

        let queued = state.handle_event(LifecycleEvent::SecondInstanceWakeRequested);

        assert!(queued.accepted);
        assert!(queued.actions.is_empty());
        assert!(state.wake_pending());
        assert_eq!(state.visibility(), WindowVisibility::Hidden);

        let applied = state.handle_event(LifecycleEvent::ProcessPendingWake);
        assert_eq!(
            applied,
            Transition::accepted(vec![
                LifecycleAction::ShowWindow,
                LifecycleAction::BringToForeground,
            ])
        );
        assert!(!state.wake_pending());
        assert_eq!(state.visibility(), WindowVisibility::Visible);
    }

    #[test]
    fn only_explicit_exit_removes_the_tray_icon_and_stops_the_loop() {
        let mut state = running_visible();
        state.handle_event(LifecycleEvent::CloseRequested);
        assert_eq!(state.phase(), RunPhase::Running);

        let transition = state.handle_event(LifecycleEvent::TrayExitRequested);

        assert_eq!(
            transition,
            Transition::accepted(vec![
                LifecycleAction::RemoveTrayIcon,
                LifecycleAction::ExitMessageLoop,
            ])
        );
        assert_eq!(state.phase(), RunPhase::Exiting);
        assert!(!state.tray_present());
    }

    #[test]
    fn exit_is_idempotent_and_ignores_late_window_events() {
        let mut state = running_visible();
        state.handle_event(LifecycleEvent::ExitRequested);

        assert_eq!(
            state.handle_event(LifecycleEvent::ExitRequested),
            Transition::ignored()
        );
        assert_eq!(
            state.handle_event(LifecycleEvent::TrayShowRequested),
            Transition::ignored()
        );
        assert_eq!(
            state.handle_event(LifecycleEvent::SecondInstanceWakeRequested),
            Transition::ignored()
        );
    }
}
