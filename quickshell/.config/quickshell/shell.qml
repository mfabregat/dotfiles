//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1

// shell.qml — quickshell entry point.
// Phase 1 bootstrap: minimal right bar. Components are added in later phases.
import Quickshell
import QtQuick
import qs.bar

ShellRoot {
    RightBar {}
}
