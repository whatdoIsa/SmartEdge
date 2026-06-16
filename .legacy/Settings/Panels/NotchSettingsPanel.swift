import SwiftUI

struct NotchSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel
    @State private var showingPreview = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                panelHeader
                
                if showingPreview {
                    notchPreview
                    Divider()
                }
                
                contentPrioritySection
                
                Divider()
                
                appearanceSection
                
                Divider()
                
                behaviorSection
                
                Divider()
                
                animationSection
            }
            .padding()
        }
    }
    
    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "rectangle.and.hand.point.up.left")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Notch Display")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(showingPreview ? "Hide Preview" : "Show Preview") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingPreview.toggle()
                    }
                }
                .font(.caption)
            }
            
            Text("Customize how content appears in the notch area")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var notchPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Preview")
                .font(.headline)
                .fontWeight(.semibold)
            
            NotchPreview()
                .frame(height: 120)
                .background(.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var contentPrioritySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Content Priority")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Picker("Content Priority", selection: $settings.notchContentPriority) {
                    ForEach(NotchContentPriority.allCases, id: \.self) { priority in
                        Text(priority.title).tag(priority.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(priorityDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var priorityDescription: String {
        guard let priority = NotchContentPriority(rawValue: settings.notchContentPriority) else {
            return "Choose how content is prioritized when multiple items compete for space."
        }
        
        switch priority {
        case .music:
            return "Music player controls always take priority over other content."
        case .calendar:
            return "Calendar events and upcoming meetings take priority."
        case .system:
            return "System notifications and HUD controls take priority."
        case .balanced:
            return "Content rotates based on activity and user interaction."
        }
    }
    
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appearance")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Show notch when inactive", isOn: $settings.showNotchWhenInactive)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Corner Radius")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Slider(value: $settings.cornerRadius, in: 6...20, step: 1)
                        
                        Text("\(Int(settings.cornerRadius))px")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 30)
                    }
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Adjust the rounded corners of the notch display")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hover Behavior")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Picker("Hover Action", selection: $settings.hoverBehavior) {
                    ForEach(HoverBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.title).tag(behavior.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(hoverDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var hoverDescription: String {
        guard let behavior = HoverBehavior(rawValue: settings.hoverBehavior) else {
            return "Choose what happens when you hover over the notch."
        }
        
        switch behavior {
        case .expand:
            return "The notch expands to show more content and controls."
        case .showControls:
            return "Additional control buttons appear without expanding."
        case .none:
            return "No action is taken when hovering over the notch."
        }
    }
    
    private var animationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Animations")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Animation Speed")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Slider(value: $settings.animationSpeed, in: 0.1...1.0, step: 0.05)
                        
                        Text(String(format: "%.1fx", settings.animationSpeed))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40)
                    }
                }
                
                HStack(spacing: 16) {
                    Button("Test Animation") {
                        testAnimation()
                    }
                    .font(.caption)
                    
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Controls the speed of notch expand/collapse animations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private func testAnimation() {
        // Implement animation test - could trigger a preview animation
        withAnimation(.spring(response: settings.animationSpeed, dampingFraction: 0.8)) {
            // Trigger preview animation
        }
    }
}

// MARK: - NotchPreview Component

struct NotchPreview: View {
    @EnvironmentObject var settings: SettingsViewModel
    @State private var isExpanded = false
    
    var body: some View {
        HStack {
            Spacer()
            
            VStack {
                Spacer()
                
                // Notch simulation
                HStack(spacing: 12) {
                    // Music content preview
                    if settings.showMusicInNotch {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.blue.gradient)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Song Title")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("Artist Name")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(width: isExpanded ? 200 : 120)
                        .clipped()
                    }
                    
                    // System status indicators
                    if settings.showBatteryStatus || settings.showBluetoothStatus {
                        HStack(spacing: 6) {
                            if settings.showBatteryStatus {
                                Image(systemName: "battery.75")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            
                            if settings.showBluetoothStatus {
                                Image(systemName: "bluetooth")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: settings.cornerRadius))
                .shadow(radius: 4)
                .onTapGesture {
                    withAnimation(.spring(response: settings.animationSpeed, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
                
                Spacer()
            }
            
            Spacer()
        }
        .padding()
        .overlay(alignment: .bottom) {
            Text("Click to test expand/collapse animation")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    NotchSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 800)
}