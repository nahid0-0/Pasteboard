import SwiftUI
import AppKit
import Carbon

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case spaceGray      = "spaceGray"
    case nordicNight    = "nordicNight"
    case deepOcean      = "deepOcean"
    case githubDark     = "githubDark"
    case cursorPure     = "cursorPure"
    case cursorSlate    = "cursorSlate"
    case cyberBlack     = "cyberBlack"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spaceGray:   return "Space Gray"
        case .nordicNight: return "Nordic Night"
        case .deepOcean:   return "Deep Ocean"
        case .githubDark:  return "GitHub Dark Blue"
        case .cursorPure:  return "Cursor Pure Black"
        case .cursorSlate: return "Cursor Slate Black"
        case .cyberBlack:  return "Cyber Black"
        }
    }

    // MARK: SwiftUI colors

    var mainBg: Color {
        switch self {
        case .spaceGray:   return Color(hex: "1a1b1e")
        case .nordicNight: return Color(hex: "0f141c")
        case .deepOcean:   return Color(hex: "080d1a")
        case .githubDark:  return Color(hex: "0d1117")
        case .cursorPure:  return Color(hex: "0a0a0a")
        case .cursorSlate: return Color(hex: "0b0d10")
        case .cyberBlack:  return Color(hex: "0c0d0e")
        }
    }

    var panelBg: Color {
        switch self {
        case .spaceGray:   return Color(hex: "1e1f23")
        case .nordicNight: return Color(hex: "131a26")
        case .deepOcean:   return Color(hex: "0d1428")
        case .githubDark:  return Color(hex: "161b22")
        case .cursorPure:  return Color(hex: "121212")
        case .cursorSlate: return Color(hex: "0f1115")
        case .cyberBlack:  return Color(hex: "131416")
        }
    }

    var emptyBg: Color {
        switch self {
        case .spaceGray:   return Color(hex: "16171a")
        case .nordicNight: return Color(hex: "0b0e14")
        case .deepOcean:   return Color(hex: "040710")
        case .githubDark:  return Color(hex: "090d13")
        case .cursorPure:  return Color(hex: "050505")
        case .cursorSlate: return Color(hex: "07080a")
        case .cyberBlack:  return Color(hex: "080809")
        }
    }

    var cardBgNormal: Color {
        switch self {
        case .spaceGray:   return Color(hex: "25262b")
        case .nordicNight: return Color(hex: "1b2434")
        case .deepOcean:   return Color(hex: "141f38")
        case .githubDark:  return Color(hex: "21262d")
        case .cursorPure:  return Color(hex: "181818")
        case .cursorSlate: return Color(hex: "16191f")
        case .cyberBlack:  return Color(hex: "181a1d")
        }
    }

    var cardBgHover: Color {
        switch self {
        case .spaceGray:   return Color(hex: "28292e")
        case .nordicNight: return Color(hex: "1f293b")
        case .deepOcean:   return Color(hex: "172441")
        case .githubDark:  return Color(hex: "242a32")
        case .cursorPure:  return Color(hex: "1d1d1d")
        case .cursorSlate: return Color(hex: "1a1d24")
        case .cyberBlack:  return Color(hex: "1c1f23")
        }
    }

    var cardBgSelected: Color {
        switch self {
        case .spaceGray:   return Color(hex: "2a2b30")
        case .nordicNight: return Color(hex: "222e42")
        case .deepOcean:   return Color(hex: "1b2949")
        case .githubDark:  return Color(hex: "282d34")
        case .cursorPure:  return Color(hex: "222222")
        case .cursorSlate: return Color(hex: "1e2229")
        case .cyberBlack:  return Color(hex: "212429")
        }
    }

    // MARK: AppKit colors (for NSTextView, ruler, etc.)

    /// NSColor twin of `mainBg` — use this (not `nsEditorBg`) behind any NSTextView
    /// that sits directly against SwiftUI chrome using `mainBg`, so the two don't
    /// show a seam where they meet.
    var nsMainBg: NSColor {
        switch self {
        case .spaceGray:   return NSColor(red: 26/255, green: 27/255, blue: 30/255, alpha: 1)
        case .nordicNight: return NSColor(red: 15/255, green: 20/255, blue: 28/255, alpha: 1)
        case .deepOcean:   return NSColor(red: 8/255,  green: 13/255, blue: 26/255, alpha: 1)
        case .githubDark:  return NSColor(red: 13/255, green: 17/255, blue: 23/255, alpha: 1)
        case .cursorPure:  return NSColor(red: 10/255, green: 10/255, blue: 10/255, alpha: 1)
        case .cursorSlate: return NSColor(red: 11/255, green: 13/255, blue: 16/255, alpha: 1)
        case .cyberBlack:  return NSColor(red: 12/255, green: 13/255, blue: 14/255, alpha: 1)
        }
    }

    var nsEditorBg: NSColor {
        switch self {
        case .spaceGray:   return NSColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 1)
        case .nordicNight: return NSColor(red: 11/255, green: 14/255, blue: 20/255, alpha: 1)
        case .deepOcean:   return NSColor(red: 4/255,  green: 7/255,  blue: 16/255, alpha: 1)
        case .githubDark:  return NSColor(red: 9/255,  green: 13/255, blue: 19/255, alpha: 1)
        case .cursorPure:  return NSColor(red: 5/255,  green: 5/255,  blue: 5/255,  alpha: 1)
        case .cursorSlate: return NSColor(red: 7/255,  green: 8/255,  blue: 10/255, alpha: 1)
        case .cyberBlack:  return NSColor(red: 8/255,  green: 8/255,  blue: 9/255,  alpha: 1)
        }
    }

    var nsRulerBg: NSColor {
        switch self {
        case .spaceGray:   return NSColor(white: 0.13, alpha: 1)
        case .nordicNight: return NSColor(red: 13/255,  green: 18/255, blue: 28/255, alpha: 1)
        case .deepOcean:   return NSColor(red: 8/255,   green: 13/255, blue: 28/255, alpha: 1)
        case .githubDark:  return NSColor(red: 13/255,  green: 17/255, blue: 23/255, alpha: 1)
        case .cursorPure:  return NSColor(white: 0.06, alpha: 1)
        case .cursorSlate: return NSColor(red: 9/255,   green: 10/255, blue: 13/255, alpha: 1)
        case .cyberBlack:  return NSColor(white: 0.07, alpha: 1)
        }
    }

    var nsRulerSeparator: NSColor {
        switch self {
        case .spaceGray:   return NSColor(white: 0.25, alpha: 1)
        case .nordicNight: return NSColor(red: 35/255,  green: 50/255,  blue: 80/255, alpha: 1)
        case .deepOcean:   return NSColor(red: 20/255,  green: 40/255,  blue: 80/255, alpha: 1)
        case .githubDark:  return NSColor(red: 48/255,  green: 54/255,  blue: 61/255, alpha: 1)
        case .cursorPure:  return NSColor(white: 0.18, alpha: 1)
        case .cursorSlate: return NSColor(white: 0.15, alpha: 1)
        case .cyberBlack:  return NSColor(white: 0.16, alpha: 1)
        }
    }
}


// MARK: - App Settings


class AppSettings: ObservableObject {
    @Published var copyOnClick: Bool {
        didSet {
            UserDefaults.standard.set(copyOnClick, forKey: "copyOnClick")
        }
    }
    
    @Published var captureScreenshots: Bool {
        didSet {
            UserDefaults.standard.set(captureScreenshots, forKey: "captureScreenshots")
        }
    }
    
    @Published var openURLsInBrowser: Bool {
        didSet {
            UserDefaults.standard.set(openURLsInBrowser, forKey: "openURLsInBrowser")
        }
    }
    
    @Published var syntaxHighlighting: Bool {
        didSet {
            UserDefaults.standard.set(syntaxHighlighting, forKey: "syntaxHighlighting")
        }
    }
    
    @Published var usePopupMode: Bool {
        didSet {
            UserDefaults.standard.set(usePopupMode, forKey: "usePopupMode")
        }
    }
    
    @Published var isFloating: Bool {
        didSet {
            UserDefaults.standard.set(isFloating, forKey: "isFloating")
        }
    }
    
    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
        }
    }
    
    // MARK: - Keyboard Shortcuts
    
    @Published var keyboardModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(keyboardModeEnabled, forKey: "keyboardModeEnabled")
        }
    }
    
    // Stack mode toggle hotkey (default: Cmd+Shift+D, disabled by default)
    @Published var stackModeHotkeyEnabled: Bool {
        didSet { UserDefaults.standard.set(stackModeHotkeyEnabled, forKey: "stackModeHotkeyEnabled") }
    }
    @Published var stackModeHotkeyKeyCode: UInt32 {
        didSet { UserDefaults.standard.set(stackModeHotkeyKeyCode, forKey: "stackModeHotkeyKeyCode") }
    }
    @Published var stackModeHotkeyModifiers: UInt32 {
        didSet { UserDefaults.standard.set(stackModeHotkeyModifiers, forKey: "stackModeHotkeyModifiers") }
    }
    @Published var stackModeHotkeyDisplay: String {
        didSet { UserDefaults.standard.set(stackModeHotkeyDisplay, forKey: "stackModeHotkeyDisplay") }
    }
    
    // Toggle hotkey (default: Cmd+Shift+J)
    @Published var toggleHotkeyKeyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(toggleHotkeyKeyCode, forKey: "toggleHotkeyKeyCode")
        }
    }
    @Published var toggleHotkeyModifiers: UInt32 {
        didSet {
            UserDefaults.standard.set(toggleHotkeyModifiers, forKey: "toggleHotkeyModifiers")
        }
    }
    @Published var toggleHotkeyDisplay: String {
        didSet {
            UserDefaults.standard.set(toggleHotkeyDisplay, forKey: "toggleHotkeyDisplay")
        }
    }
    
    // Navigate Up shortcut (default: Shift+Up)
    @Published var navUpKeyCode: UInt16 {
        didSet {
            UserDefaults.standard.set(navUpKeyCode, forKey: "navUpKeyCode")
        }
    }
    @Published var navUpModifiers: UInt {
        didSet {
            UserDefaults.standard.set(navUpModifiers, forKey: "navUpModifiers")
        }
    }
    @Published var navUpDisplay: String {
        didSet {
            UserDefaults.standard.set(navUpDisplay, forKey: "navUpDisplay")
        }
    }
    
    // Navigate Down shortcut (default: Shift+Down)
    @Published var navDownKeyCode: UInt16 {
        didSet {
            UserDefaults.standard.set(navDownKeyCode, forKey: "navDownKeyCode")
        }
    }
    @Published var navDownModifiers: UInt {
        didSet {
            UserDefaults.standard.set(navDownModifiers, forKey: "navDownModifiers")
        }
    }
    @Published var navDownDisplay: String {
        didSet {
            UserDefaults.standard.set(navDownDisplay, forKey: "navDownDisplay")
        }
    }
    
    // Default Carbon modifier values
    static let defaultToggleKeyCode: UInt32 = 38  // J
    static let defaultToggleModifiers: UInt32 = UInt32(cmdKey | shiftKey)
    static let defaultToggleDisplay = "⌘⇧J"
    
    static let defaultNavUpKeyCode: UInt16 = 126   // Up arrow
    static let defaultNavUpModifiers: UInt = NSEvent.ModifierFlags.shift.rawValue
    static let defaultNavUpDisplay = "⇧↑"
    
    static let defaultStackModeKeyCode: UInt32 = 2  // D
    static let defaultStackModeModifiers: UInt32 = UInt32(cmdKey | shiftKey)
    static let defaultStackModeDisplay = "⌘⇧D"
    
    static let defaultNavDownKeyCode: UInt16 = 125 // Down arrow
    static let defaultNavDownModifiers: UInt = NSEvent.ModifierFlags.shift.rawValue
    static let defaultNavDownDisplay = "⇧↓"
    
    init() {
        // Existing settings
        self.copyOnClick = UserDefaults.standard.object(forKey: "copyOnClick") != nil
            ? UserDefaults.standard.bool(forKey: "copyOnClick") : false
        
        self.captureScreenshots = UserDefaults.standard.object(forKey: "captureScreenshots") != nil
            ? UserDefaults.standard.bool(forKey: "captureScreenshots") : true
        
        self.openURLsInBrowser = UserDefaults.standard.object(forKey: "openURLsInBrowser") != nil
            ? UserDefaults.standard.bool(forKey: "openURLsInBrowser") : true
        
        self.syntaxHighlighting = UserDefaults.standard.object(forKey: "syntaxHighlighting") != nil
            ? UserDefaults.standard.bool(forKey: "syntaxHighlighting") : true
        
        self.usePopupMode = UserDefaults.standard.object(forKey: "usePopupMode") != nil
            ? UserDefaults.standard.bool(forKey: "usePopupMode") : false
        
        self.isFloating = UserDefaults.standard.object(forKey: "isFloating") != nil
            ? UserDefaults.standard.bool(forKey: "isFloating") : false
        
        if let savedTheme = UserDefaults.standard.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: savedTheme) {
            self.theme = theme
        } else {
            self.theme = .spaceGray
        }
        
        // Keyboard shortcuts
        self.keyboardModeEnabled = UserDefaults.standard.object(forKey: "keyboardModeEnabled") != nil
            ? UserDefaults.standard.bool(forKey: "keyboardModeEnabled") : true
            
        self.stackModeHotkeyEnabled = UserDefaults.standard.object(forKey: "stackModeHotkeyEnabled") != nil
            ? UserDefaults.standard.bool(forKey: "stackModeHotkeyEnabled") : false
            
        self.stackModeHotkeyKeyCode = UserDefaults.standard.object(forKey: "stackModeHotkeyKeyCode") != nil
            ? UInt32(UserDefaults.standard.integer(forKey: "stackModeHotkeyKeyCode"))
            : AppSettings.defaultStackModeKeyCode
        
        self.stackModeHotkeyModifiers = UserDefaults.standard.object(forKey: "stackModeHotkeyModifiers") != nil
            ? UInt32(UserDefaults.standard.integer(forKey: "stackModeHotkeyModifiers"))
            : AppSettings.defaultStackModeModifiers
        
        self.stackModeHotkeyDisplay = UserDefaults.standard.string(forKey: "stackModeHotkeyDisplay")
            ?? AppSettings.defaultStackModeDisplay
        
        self.toggleHotkeyKeyCode = UserDefaults.standard.object(forKey: "toggleHotkeyKeyCode") != nil
            ? UInt32(UserDefaults.standard.integer(forKey: "toggleHotkeyKeyCode"))
            : AppSettings.defaultToggleKeyCode
        
        self.toggleHotkeyModifiers = UserDefaults.standard.object(forKey: "toggleHotkeyModifiers") != nil
            ? UInt32(UserDefaults.standard.integer(forKey: "toggleHotkeyModifiers"))
            : AppSettings.defaultToggleModifiers
        
        self.toggleHotkeyDisplay = UserDefaults.standard.string(forKey: "toggleHotkeyDisplay")
            ?? AppSettings.defaultToggleDisplay
        
        self.navUpKeyCode = UserDefaults.standard.object(forKey: "navUpKeyCode") != nil
            ? UInt16(UserDefaults.standard.integer(forKey: "navUpKeyCode"))
            : AppSettings.defaultNavUpKeyCode
        
        self.navUpModifiers = UserDefaults.standard.object(forKey: "navUpModifiers") != nil
            ? UInt(UserDefaults.standard.integer(forKey: "navUpModifiers"))
            : AppSettings.defaultNavUpModifiers
        
        self.navUpDisplay = UserDefaults.standard.string(forKey: "navUpDisplay")
            ?? AppSettings.defaultNavUpDisplay
        
        self.navDownKeyCode = UserDefaults.standard.object(forKey: "navDownKeyCode") != nil
            ? UInt16(UserDefaults.standard.integer(forKey: "navDownKeyCode"))
            : AppSettings.defaultNavDownKeyCode
        
        self.navDownModifiers = UserDefaults.standard.object(forKey: "navDownModifiers") != nil
            ? UInt(UserDefaults.standard.integer(forKey: "navDownModifiers"))
            : AppSettings.defaultNavDownModifiers
        
        self.navDownDisplay = UserDefaults.standard.string(forKey: "navDownDisplay")
            ?? AppSettings.defaultNavDownDisplay
    }
    
    func resetShortcutsToDefaults() {
        keyboardModeEnabled = true
        toggleHotkeyKeyCode = AppSettings.defaultToggleKeyCode
        toggleHotkeyModifiers = AppSettings.defaultToggleModifiers
        toggleHotkeyDisplay = AppSettings.defaultToggleDisplay
        stackModeHotkeyEnabled = false
        stackModeHotkeyKeyCode = AppSettings.defaultStackModeKeyCode
        stackModeHotkeyModifiers = AppSettings.defaultStackModeModifiers
        stackModeHotkeyDisplay = AppSettings.defaultStackModeDisplay
        navUpKeyCode = AppSettings.defaultNavUpKeyCode
        navUpModifiers = AppSettings.defaultNavUpModifiers
        navUpDisplay = AppSettings.defaultNavUpDisplay
        navDownKeyCode = AppSettings.defaultNavDownKeyCode
        navDownModifiers = AppSettings.defaultNavDownModifiers
        navDownDisplay = AppSettings.defaultNavDownDisplay
    }
    
    // MARK: - Helpers
    
    /// Build a human-readable display string from an NSEvent
    static func displayString(for keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }
    
    /// Convert Carbon modifiers (UInt32) to a display string prefix
    static func displayStringFromCarbon(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0  { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0   { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0     { parts.append("⌘") }
        parts.append(keyName(for: UInt16(keyCode)))
        return parts.joined()
    }
    
    /// Convert NSEvent.ModifierFlags to Carbon modifier mask for RegisterEventHotKey
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }
    
    private static func keyName(for keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
            36: "↩", 48: "⇥", 51: "⌫", 53: "⎋",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 109: "F10", 111: "F12", 103: "F11",
            105: "F13", 107: "F14", 113: "F15",
            118: "F4", 120: "F2", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}



