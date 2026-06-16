//
//  SystemStatusView.swift
//  SmartEdge
//

import SwiftUI

struct SystemStatusView: View {
    @StateObject private var viewModel = ServiceContainer.shared.createSystemStatusViewModel()
    @State private var showingDetail = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Battery Status
            batteryStatusView
            
            // Bluetooth Status
            if viewModel.isBluetoothAvailable {
                bluetoothStatusView
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.1))
        )
        .onTapGesture {
            showingDetail.toggle()
        }
        .sheet(isPresented: $showingDetail) {
            SystemStatusDetailView(viewModel: viewModel)
        }
    }
    
    private var batteryStatusView: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.batteryInfo.iconName)
                .foregroundColor(Color(viewModel.batteryStatusColor))
            
            Text(viewModel.batteryLevelFormatted)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
    
    private var bluetoothStatusView: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.bluetoothStatusIcon)
                .foregroundColor(.blue)
            
            if viewModel.connectedDevices.count > 0 {
                Text("\(viewModel.connectedDevices.count)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }
}

struct SystemStatusDetailView: View {
    @ObservedObject var viewModel: SystemStatusViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Critical Alerts
                    if viewModel.hasCriticalAlerts {
                        criticalAlertsSection
                    }
                    
                    // Battery Section
                    batterySection
                    
                    // Bluetooth Section
                    bluetoothSection
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("System Status")
            // Note: navigationBarTitleDisplayMode is iOS-only
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .secondaryAction) {
                    Button("Refresh") {
                        viewModel.refreshAll()
                    }
                }
            }
        }
    }
    
    private var criticalAlertsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Critical Alerts", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(.red)
            
            ForEach(viewModel.criticalAlerts, id: \.title) { alert in
                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(alert.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(alert.severity.color).opacity(0.1))
                )
            }
        }
    }
    
    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Battery", systemImage: "battery.100")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: viewModel.batteryInfo.iconName)
                        .foregroundColor(Color(viewModel.batteryStatusColor))
                    
                    Text("\(viewModel.batteryInfo.levelPercentage)%")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(viewModel.batteryInfo.chargingState.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if viewModel.batteryInfo.timeRemaining > 0 {
                            Text(viewModel.batteryTimeRemainingFormatted)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if let temperature = viewModel.batteryInfo.temperature {
                    Text("Temperature: \(String(format: "%.1f°C", temperature))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Power Source:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.batteryInfo.powerSourceType.rawValue)
                        .font(.caption)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
            )
        }
    }
    
    private var bluetoothSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bluetooth", systemImage: "bluetooth")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: viewModel.bluetoothStatusIcon)
                        .foregroundColor(.blue)
                    
                    Text(viewModel.bluetoothStatusDescription)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if viewModel.isBluetoothAvailable {
                        Button(viewModel.isBluetoothScanning ? "Stop Scan" : "Scan") {
                            if viewModel.isBluetoothScanning {
                                viewModel.stopBluetoothScanning()
                            } else {
                                viewModel.startBluetoothScanning()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                if !viewModel.connectedDevices.isEmpty {
                    ForEach(viewModel.connectedDevices, id: \.id) { device in
                        HStack {
                            Image(systemName: device.deviceType.iconName)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                
                                if let batteryLevel = device.batteryPercentage {
                                    Text("Battery: \(batteryLevel)%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Text(device.connectionStatus.description)
                                .font(.caption2)
                                .foregroundColor(Color(device.connectionStatus.color))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
            )
        }
    }
}

#Preview {
    SystemStatusView()
}