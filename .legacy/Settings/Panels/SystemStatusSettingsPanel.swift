import SwiftUI

struct SystemStatusSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel
    @State private var batteryLevel: Double = 75
    @State private var isCharging = false
    @State private var bluetoothConnected = 2
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                panelHeader
                
                batterySection
                
                Divider()
                
                bluetoothSection
                
                Divider()
                
                networkSection
                
                Divider()
                
                displaySection
            }
            .padding()
        }
    }
    
    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "battery.100")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("System Status")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            
            Text("Monitor and display system status indicators")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Battery Monitoring")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show battery status", isOn: $settings.showBatteryStatus)
                
                if settings.showBatteryStatus {
                    VStack(alignment: .leading, spacing: 16) {
                        // Battery preview
                        batteryPreview
                        
                        // Low battery threshold
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Low Battery Alert Threshold")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack {
                                Slider(value: $settings.batteryLowThreshold, in: 5...50, step: 5)
                                
                                Text("\(Int(settings.batteryLowThreshold))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 30)
                            }
                        }
                        
                        HStack {
                            Button("Test Alert") {
                                testBatteryAlert()
                            }
                            .font(.caption)
                            
                            Spacer()
                        }
                    }
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Display battery percentage and charging status in the notch")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var batteryPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                Image(systemName: batteryIcon)
                    .font(.caption)
                    .foregroundColor(batteryColor)
                
                Text("\(Int(batteryLevel))%")
                    .font(.caption)
                    .fontWeight(.medium)
                
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                Toggle("Charging", isOn: $isCharging)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            
            // Battery level slider for testing
            HStack {
                Text("Test Level:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Slider(value: $batteryLevel, in: 0...100, step: 5)
                    .frame(width: 100)
            }
            .padding(.top, 4)
        }
    }
    
    private var batteryIcon: String {
        if isCharging {
            return "battery.100.bolt"
        }
        
        switch batteryLevel {
        case 0..<25:
            return "battery.25"
        case 25..<50:
            return "battery.50"
        case 50..<75:
            return "battery.75"
        default:
            return "battery.100"
        }
    }
    
    private var batteryColor: Color {
        if isCharging {
            return .orange
        }
        
        if batteryLevel <= settings.batteryLowThreshold {
            return .red
        } else if batteryLevel <= settings.batteryLowThreshold + 10 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var bluetoothSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bluetooth Status")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show Bluetooth status", isOn: $settings.showBluetoothStatus)
                
                if settings.showBluetoothStatus {
                    VStack(alignment: .leading, spacing: 12) {
                        bluetoothPreview
                        
                        HStack(spacing: 16) {
                            Button("Simulate Connect") {
                                bluetoothConnected = min(bluetoothConnected + 1, 5)
                            }
                            .font(.caption)
                            
                            Button("Simulate Disconnect") {
                                bluetoothConnected = max(bluetoothConnected - 1, 0)
                            }
                            .font(.caption)
                            
                            Spacer()
                        }
                    }
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Monitor Bluetooth connectivity and connected device count")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var bluetoothPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                Image(systemName: "bluetooth")
                    .font(.caption)
                    .foregroundColor(bluetoothConnected > 0 ? .blue : .gray)
                
                if bluetoothConnected > 0 {
                    Text("\(bluetoothConnected)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundColor(.blue)
                } else {
                    Text("Off")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }
    
    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Network Status")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show Wi-Fi status", isOn: $settings.showWiFiStatus)
                
                if settings.showWiFiStatus {
                    wifiPreview
                        .padding(.leading, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Display Wi-Fi network name and signal strength")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var wifiPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("My Network")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Strong Signal")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }
    
    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Display Settings")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Status Indicator Priority")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("When multiple status indicators are active, they appear in this order:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    priorityItem(number: 1, title: "Battery (when low or charging)", isActive: settings.showBatteryStatus)
                    priorityItem(number: 2, title: "Bluetooth connections", isActive: settings.showBluetoothStatus)
                    priorityItem(number: 3, title: "Wi-Fi network", isActive: settings.showWiFiStatus)
                }
                .padding(.leading, 16)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Status indicators automatically hide when the notch is full to prioritize more important content like music or calendar events.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private func priorityItem(number: Int, title: String, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(isActive ? .blue : .gray.opacity(0.5), in: Circle())
            
            Text(title)
                .font(.caption)
                .foregroundColor(isActive ? .primary : .secondary)
            
            Spacer()
        }
    }
    
    private func testBatteryAlert() {
        let alert = NSAlert()
        alert.messageText = "Low Battery Alert"
        alert.informativeText = "Battery level is at \(Int(settings.batteryLowThreshold))%. Consider connecting to power."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

#Preview {
    SystemStatusSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 800)
}