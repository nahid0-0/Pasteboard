# Pasteboard

A lightweight clipboard manager for macOS that runs in the menu bar.

## Features

- 📋 Automatic clipboard history tracking
- 🖼️ Screenshot detection and management
- ⚡ Quick access via menu bar or global hotkey
- 🔍 Search and filter clipboard items
- 🔎 Preview clipboard items with syntax highlighting
- ⌨️ Configurable global hotkey and keyboard navigation
- 📌 Pin important clips to keep them at the top
- 🗑️ Easy item management (delete, clear all/unpinned)
- 💾 Persistent storage across app restarts
- 🎨 Clean, native macOS interface

## Download

**[Download Pasteboard.app](https://github.com/nahid0-0/Pasteboard/raw/main/build/Pasteboard.app.zip)**

## Installation

1. Download the app using the link above
2. Unzip if downloaded as .zip
3. Move `Pasteboard.app` to your `/Applications` folder
4. Right-click the app and select "Open" (first time only to bypass Gatekeeper)
5. The app will appear in your menu bar

## Usage

- Click the clipboard icon in the menu bar to view history
- Use the global hotkey (configurable in Settings) to quickly access clipboard history
- Click any item to copy it to clipboard
- Use filter pills to filter by type (Text, Image, URL, File)
- Search clips using the search bar
- Use Settings to configure behavior, hotkeys, and navigation shortcuts

## Building from Source

### Requirements
- macOS 13.0 or later
- Xcode Command Line Tools
- Swift compiler

### Build Steps

```bash
# Clone the repository
git clone https://github.com/nahid0-0/Pasteboard.git
cd Pasteboard

# Run the build script
./build.sh

# The app will be created at build/Pasteboard.app
open build/Pasteboard.app
```

Or open the Xcode project and build normally.

## System Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel processor

## Permissions

Pasteboard requires the following permissions:
- **Accessibility**: To capture global hotkeys
- **Screen Recording**: To detect and manage screenshots (optional)

## License

Copyright © 2026 Nahid Rahman. All rights reserved.

## Contributing

Issues and pull requests are welcome!
