# Smart Edge

Transform your Mac's screen edges into a productivity powerhouse.

## 🎯 Overview

Smart Edge is a macOS application that converts your screen edges into intelligent widget zones, providing instant access to system information, media controls, and productivity tools without interrupting your workflow.

## ✨ Features

### Core Widgets
- **🖥️ System Monitor**: Real-time CPU, memory, and battery status
- **🎵 Media Control**: Universal media playback controls for music and videos
- **📅 Calendar Integration**: Upcoming events and quick schedule overview
- **🌤️ Weather Widget**: Current weather and forecast information
- **📝 Quick Notes**: Rapid note-taking without app switching

### Key Capabilities
- **Edge Positioning**: Place widgets on any screen edge (top, bottom, left, right)
- **Multi-Display Support**: Independent widgets for each connected display
- **Workspace Switching**: Different widget sets for different work modes
- **Smart Suggestions**: AI-powered widget recommendations based on usage patterns
- **Customizable Appearance**: Themes, colors, and transparency settings

## 🏗️ Architecture

### Technology Stack
- **Framework**: SwiftUI + AppKit hybrid
- **Language**: Swift 5.9+
- **Minimum macOS**: 13.0 (Ventura)
- **Architecture**: MVVM with Service Layer

### Project Structure
```
SmartEdge/
├── App/                    # Application entry point
├── Core/                   # Core business logic
│   ├── Models/            # Data models
│   ├── Services/          # Business services
│   └── Managers/          # System managers
├── Features/               # Feature modules
│   ├── SystemInfo/        # System monitoring
│   ├── MediaControl/      # Media playback
│   ├── Calendar/          # Calendar integration
│   └── Settings/          # App configuration
├── UI/                     # User interface
│   ├── Components/        # Reusable components
│   ├── Overlays/          # Overlay windows
│   └── Themes/            # Design system
└── Utils/                  # Utilities and constants
```

## 🚀 Getting Started

### Prerequisites
- macOS 13.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/smartedge/app.git
   cd SmartEdge
   ```

2. Open the project in Xcode:
   ```bash
   open SmartEdge.xcodeproj
   ```

3. Build and run the project (⌘+R)

### Required Permissions
Smart Edge requires the following permissions to function properly:
- **Accessibility**: System monitoring and media control
- **Calendar**: Display upcoming events
- **Network Access**: Weather data and updates

## 🎮 Usage

### Initial Setup
1. Launch Smart Edge
2. Grant required permissions when prompted
3. Configure your preferred edge position in Settings
4. Customize widgets and appearance to your liking

### Basic Controls
- **Hover**: Expand widgets for detailed information
- **Click**: Interact with widget controls
- **Settings**: Access via menu bar icon
- **Hide/Show**: Toggle widgets with keyboard shortcut

### Customization
- Choose screen edge position
- Select which widgets to display
- Customize colors and transparency
- Set up workspace-specific configurations

## 🛠️ Development

### Building from Source
```bash
# Build for development
xcodebuild -scheme SmartEdge -configuration Debug

# Build for release
xcodebuild -scheme SmartEdge -configuration Release
```

### Running Tests
```bash
xcodebuild test -scheme SmartEdge
```

### Code Style
- Follow Swift API Design Guidelines
- Use SwiftLint for code consistency
- Maintain MVVM architecture patterns
- Write comprehensive unit tests

## 📋 Roadmap

### Version 1.0 (MVP)
- [x] Core overlay system
- [x] System information widget
- [x] Basic media controls
- [x] Settings interface
- [x] Permission management

### Version 1.1
- [ ] Calendar widget
- [ ] Weather integration
- [ ] Workspace switching
- [ ] Enhanced customization

### Version 1.2
- [ ] Quick notes widget
- [ ] AI-powered suggestions
- [ ] Widget store
- [ ] Advanced animations

### Future Versions
- [ ] Third-party widget SDK
- [ ] Cloud sync for settings
- [ ] Automation triggers
- [ ] Integration with external services

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Process
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### Code of Conduct
Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before contributing.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

### Getting Help
- 📖 [Documentation](https://smartedge.app/docs)
- 💬 [Discussions](https://github.com/smartedge/app/discussions)
- 🐛 [Issues](https://github.com/smartedge/app/issues)

### Contact
- Email: support@smartedge.app
- Twitter: [@SmartEdgeApp](https://twitter.com/SmartEdgeApp)

## 🙏 Acknowledgments

- Inspired by modern productivity tools and macOS design principles
- Built with ❤️ for the Mac community
- Special thanks to all beta testers and contributors

---

**Smart Edge** - Making your Mac's edges work smarter, not harder.