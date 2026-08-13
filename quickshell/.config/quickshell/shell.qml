// Platform menus (tray) require QApplication mode
//@ pragma UseQApplication
//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1

// shell.qml — quickshell entry point.
import Quickshell
import QtQuick
import qs.bar
import qs.popups

ShellRoot {
    RightBar {}

    // Launcher: one fullscreen window per screen; only the focused
    // monitor's instance is visible (see popups/Launcher.qml).
    Variants {
        model: Quickshell.screens
        Launcher {}
    }
}
