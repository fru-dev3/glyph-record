import AppKit
import GlyphCore
import SwiftUI

/// Glyph Record: records meetings, calls and conversations on the Mac and keeps a
/// library of them in the vault. The successor of Memosa; GlyphCore does the work.
@main
struct GlyphRecordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    init() {
        // Scroll bars show only while scrolling, even when System Settings says Always
        // or a mouse is plugged in: this app's own setting, read before any scroller exists.
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    var body: some Scene {
        Window("Glyph Record", id: "library") {
            LibraryWindow()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands { RecordCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            Image(systemName: model.isRecording ? "record.circle.fill" : "record.circle")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // The library window can close while a recording runs; the menu bar keeps the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            #if DEBUG
            DebugHook.install(AppModel.shared)
            #endif
        }
    }

    // Quitting mid-recording closes the file first, so no sound is lost.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let model = AppModel.shared
            guard model.isRecording else { return .terminateNow }
            Task { @MainActor in
                await model.stopRecording()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }
}
