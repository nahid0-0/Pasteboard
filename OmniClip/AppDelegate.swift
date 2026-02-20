import Cocoa
import SwiftUI
import Combine
import Carbon

// Shared keyboard action publisher - owned by AppDelegate, observed by ContentView
class KeyboardActionPublisher: ObservableObject {
    @Published var actionCounter: Int = 0
    var lastAction: String = ""  // "up", "down", "enter", "search"
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var panel: NSPanel!
    private var settingsWindow: NSWindow?
    private var clipboardManager: ClipboardManager!
    private var appSettings: AppSettings!
    private var settingsObserver: AnyCancellable?
    private var hotKeyRef: EventHotKeyRef?
    private var keyMonitor: Any?
    
    // Shared with ContentView
    let keyboardActions = KeyboardActionPublisher()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        appSettings = AppSettings()
        clipboardManager = ClipboardManager()
        
        clipboardManager.configureScreenshotWatcher(enabled: appSettings.captureScreenshots)
        
        settingsObserver = appSettings.$captureScreenshots.sink { [weak self] enabled in
            self?.clipboardManager.configureScreenshotWatcher(enabled: enabled)
        }
        
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            button.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "OmniClip")?.withSymbolConfiguration(config)
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        let contentView = ContentView(
            clipboardManager: clipboardManager,
            appSettings: appSettings,
            keyboardActions: keyboardActions
        )
        
        // Create popover (menu bar dropdown mode)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 900, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // Create panel (centered popup / keyboard mode)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "OmniClip"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.contentView = NSHostingView(rootView: contentView)
        
        // Register global hotkey: Cmd+Shift+J
        registerGlobalHotKey()
        
        // Set up keyboard monitor for navigation
        setupKeyboardMonitor()
        
        // Listen for dismiss notification from ContentView (Enter key)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismiss),
            name: .dismissOmniClip,
            object: nil
        )
    }
    
    @objc private func handleDismiss() {
        if popover.isShown {
            popover.performClose(nil)
        }
        panel.orderOut(nil)
    }
    
    // MARK: - Keyboard Monitor (runs in AppDelegate for reliability)
    
    private func setupKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Only intercept when our popover or panel is visible
            let isVisible = self.popover.isShown || self.panel.isVisible
            guard isVisible else { return event }
            
            let shift = event.modifierFlags.contains(.shift)
            let cmd = event.modifierFlags.contains(.command)
            let opt = event.modifierFlags.contains(.option)
            let ctrl = event.modifierFlags.contains(.control)
            let plainModifiers = !cmd && !opt && !ctrl
            
            // Shift+Up
            if event.keyCode == 126 && shift && plainModifiers {
                self.keyboardActions.lastAction = "up"
                self.keyboardActions.actionCounter += 1
                return nil
            }
            
            // Shift+Down
            if event.keyCode == 125 && shift && plainModifiers {
                self.keyboardActions.lastAction = "down"
                self.keyboardActions.actionCounter += 1
                return nil
            }
            
            // Shift+Left - focus search
            if event.keyCode == 123 && shift && plainModifiers {
                self.keyboardActions.lastAction = "search"
                self.keyboardActions.actionCounter += 1
                return nil
            }
            
            // Enter/Return
            if (event.keyCode == 36 || event.keyCode == 76) && !shift && plainModifiers {
                self.keyboardActions.lastAction = "enter"
                self.keyboardActions.actionCounter += 1
                return nil
            }
            
            return event
        }
    }
    
    // MARK: - Global Hotkey (Cmd+Shift+J)
    
    private func registerGlobalHotKey() {
        let keyCode: UInt32 = 38
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4F43_4C50)
        hotKeyID.id = 1
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    delegate.handleGlobalHotKey()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
        
        if status == noErr {
            RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        }
    }
    
    @objc func handleGlobalHotKey() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            if popover.isShown {
                popover.performClose(nil)
            }
            centerPanel()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    // MARK: - Status Item Click
    
    @objc func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            showContextMenu()
            return
        }
        
        if appSettings.usePopupMode {
            togglePanel()
        } else {
            togglePopover()
        }
    }
    
    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            panel.orderOut(nil)
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            if popover.isShown {
                popover.performClose(nil)
            }
            centerPanel()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func centerPanel() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.midY - panelFrame.height / 2 + 10
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    // MARK: - Dismiss
    
    private func dismissAll() {
        if popover.isShown {
            popover.performClose(nil)
        }
        panel.orderOut(nil)
    }
    
    // MARK: - Context Menu
    
    @objc func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit OmniClip", action: #selector(quitApp), keyEquivalent: "q"))
        
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
        }
    }
    
    @objc func openSettings() {
        if popover.isShown {
            popover.performClose(nil)
        }
        panel.orderOut(nil)
        
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "OmniClip Settings"
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(settings: appSettings))
            settingsWindow = window
        }
        
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        clipboardManager.stopMonitoring()
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
