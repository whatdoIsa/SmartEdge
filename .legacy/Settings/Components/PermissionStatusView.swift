import SwiftUI

struct PermissionStatusView: View {
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    statusIndicator
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            if !isGranted {
                Button("Grant Access") {
                    action()
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isGranted ? .green : .red)
                .frame(width: 6, height: 6)
            
            Text(isGranted ? "Granted" : "Required")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(isGranted ? .green : .red)
        }
    }
    
    private var backgroundColor: Color {
        if isGranted {
            return .green.opacity(0.05)
        } else {
            return .red.opacity(0.05)
        }
    }
    
    private var borderColor: Color {
        if isGranted {
            return .green.opacity(0.2)
        } else {
            return .red.opacity(0.2)
        }
    }
}

// MARK: - Permission Status with Custom Action Text

struct PermissionStatusView2: View {
    let title: String
    let description: String
    let isGranted: Bool
    let actionTitle: String
    let action: (() -> Void)?
    
    init(title: String, description: String, isGranted: Bool, actionTitle: String = "Grant Access", action: (() -> Void)? = nil) {
        self.title = title
        self.description = description
        self.isGranted = isGranted
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    statusBadge
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            if let action = action, !isGranted {
                Button(actionTitle) {
                    action()
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isGranted ? .green.opacity(0.3) : .red.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var iconName: String {
        if isGranted {
            return "checkmark.shield.fill"
        } else {
            return "exclamationmark.shield.fill"
        }
    }
    
    private var iconColor: Color {
        isGranted ? .green : .orange
    }
    
    private var statusBadge: some View {
        Text(isGranted ? "Granted" : "Required")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isGranted ? .green.opacity(0.2) : .red.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
            .foregroundColor(isGranted ? .green : .red)
    }
}

// MARK: - Detailed Permission Status

struct DetailedPermissionView: View {
    let title: String
    let description: String
    let isGranted: Bool
    let details: [String]
    let action: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: isGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundColor(isGranted ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                statusIndicator
            }
            
            if !details.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This permission enables:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    ForEach(details, id: \.self) { detail in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.blue)
                                .frame(width: 4, height: 4)
                            
                            Text(detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                    }
                }
                .padding(.leading, 20)
            }
            
            if let action = action, !isGranted {
                HStack {
                    Button("Grant Permission") {
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isGranted ? .green.opacity(0.3) : .orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var statusIndicator: some View {
        VStack(spacing: 4) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundColor(isGranted ? .green : .red)
            
            Text(isGranted ? "Granted" : "Required")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(isGranted ? .green : .red)
        }
    }
}

#Preview("Basic Permission View") {
    VStack(spacing: 16) {
        PermissionStatusView(
            title: "Calendar Access",
            description: "Required to display upcoming events and meetings",
            isGranted: true,
            action: {}
        )
        
        PermissionStatusView(
            title: "Accessibility Access",
            description: "Required to intercept system HUD events",
            isGranted: false,
            action: {}
        )
    }
    .padding()
    .frame(width: 400)
}

#Preview("Enhanced Permission View") {
    VStack(spacing: 16) {
        PermissionStatusView2(
            title: "Media Remote Access",
            description: "Required to display and control music playback",
            isGranted: true,
            actionTitle: "Grant Access"
        )
        
        PermissionStatusView2(
            title: "Screen Recording",
            description: "Optional for enhanced visual features",
            isGranted: false,
            actionTitle: "Enable",
            action: {}
        )
    }
    .padding()
    .frame(width: 400)
}

#Preview("Detailed Permission View") {
    DetailedPermissionView(
        title: "Accessibility Access",
        description: "System-level access for HUD interception",
        isGranted: false,
        details: [
            "Intercept volume and brightness controls",
            "Monitor keyboard events",
            "Display custom HUD overlays",
            "Enhance system integration"
        ],
        action: {}
    )
    .padding()
    .frame(width: 450)
}