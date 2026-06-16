import SwiftUI

struct PermissionRow: View {
    let title: String
    let description: String
    let status: PermissionStatus
    let onRequestAction: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                statusIndicator
            }
            
            if status == .denied {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    
                    Text("Permission denied. Please enable in System Preferences.")
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    Spacer()
                    
                    Button("Open Settings") {
                        openSystemPreferences()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
        }
    }
    
    private var statusIndicator: some View {
        HStack(spacing: 8) {
            switch status {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Granted")
                    .font(.caption)
                    .foregroundColor(.green)
                
            case .denied:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Denied")
                    .font(.caption)
                    .foregroundColor(.red)
                
            case .notDetermined:
                Button("Request Permission") {
                    onRequestAction()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
    
    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
}


#if DEBUG
struct PermissionRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            PermissionRow(
                title: "Calendar Access",
                description: "Required to read your calendar events",
                status: .granted
            ) {}
            
            PermissionRow(
                title: "Accessibility",
                description: "Required to intercept system HUD events",
                status: .denied
            ) {}
            
            PermissionRow(
                title: "Notifications",
                description: "Required to send event reminders",
                status: .notDetermined
            ) {}
        }
        .padding()
    }
}
#endif