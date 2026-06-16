import SwiftUI
import os

// MARK: - Error State Preview
struct ErrorStatePreview: View {
    @State private var selectedDemo = DemoState.musicPlayerLoading
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Demo selector
                Picker("Demo State", selection: $selectedDemo) {
                    ForEach(DemoState.allCases, id: \.self) { state in
                        Text(state.title).tag(state)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Demo content
                Group {
                    switch selectedDemo {
                    case .musicPlayerLoading:
                        MusicPlayerLoadingDemo()
                    case .musicPlayerError:
                        MusicPlayerErrorDemo()
                    case .musicPlayerEmpty:
                        MusicPlayerEmptyDemo()
                    case .notchInitializing:
                        NotchInitializingDemo()
                    case .notchError:
                        NotchErrorDemo()
                    case .errorToast:
                        ErrorToastDemo()
                    case .skeletonLoading:
                        SkeletonLoadingDemo()
                    case .loadingStates:
                        LoadingStatesDemo()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .cornerRadius(12)
                
                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Demo States
enum DemoState: CaseIterable {
    case musicPlayerLoading
    case musicPlayerError
    case musicPlayerEmpty
    case notchInitializing
    case notchError
    case errorToast
    case skeletonLoading
    case loadingStates
    
    var title: String {
        switch self {
        case .musicPlayerLoading:
            return "Music Loading"
        case .musicPlayerError:
            return "Music Error"
        case .musicPlayerEmpty:
            return "Music Empty"
        case .notchInitializing:
            return "Notch Init"
        case .notchError:
            return "Notch Error"
        case .errorToast:
            return "Error Toast"
        case .skeletonLoading:
            return "Skeleton"
        case .loadingStates:
            return "Loading"
        }
    }
}

// MARK: - Music Player Demos
private struct MusicPlayerLoadingDemo: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Music Player - Loading State")
                .font(.headline)
                .foregroundColor(.white)
            
            MusicPlayerSkeleton()
                .frame(maxWidth: 320)
        }
        .padding()
    }
}

private struct MusicPlayerErrorDemo: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Music Player - Error State")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(spacing: 16) {
                ErrorView(error: .mediaServiceUnavailable) {
                    AppLogger.ui.debug("Retry tapped")
                }
                .frame(maxWidth: 320)
                
                ErrorToast(error: .mediaServiceUnavailable)
                    .frame(maxWidth: 320)
            }
        }
        .padding()
    }
}

private struct MusicPlayerEmptyDemo: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Music Player - Empty State")
                .font(.headline)
                .foregroundColor(.white)
            
            EmptyStateView(
                icon: "music.note",
                title: "No Music Playing",
                subtitle: "Start playing music to see controls here",
                actionTitle: "Open Music App"
            ) {
                AppLogger.ui.debug("Open Music App tapped")
            }
            .frame(maxWidth: 320)
        }
        .padding()
    }
}

// MARK: - Notch Demos
private struct NotchInitializingDemo: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Notch - Initializing State")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                LoadingSpinner(size: 16)
                
                Text("Initializing...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding()
    }
}

private struct NotchErrorDemo: View {
    @State private var showingDetails = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Notch - Error State")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14, weight: .medium))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Service Error")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    
                    if showingDetails {
                        Text("Notch service initialization failed")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                    }
                }
                
                Spacer()
                
                Button("Retry") {
                    AppLogger.ui.debug("Retry tapped")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.accentColor)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingDetails.toggle()
                }
            }
        }
        .padding()
    }
}

// MARK: - Error Toast Demo
private struct ErrorToastDemo: View {
    @State private var errors: [AppError] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Error Toast Demo")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                Button("Show Media Error") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        errors.append(.mediaServiceUnavailable)
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation(.easeOut) {
                            errors.removeAll()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Show Network Error") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        errors.append(.networkTimeout)
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation(.easeOut) {
                            errors.removeAll()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Show Permission Error") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        errors.append(.permissionDenied)
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation(.easeOut) {
                            errors.removeAll()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                ForEach(errors.indices, id: \.self) { index in
                    ErrorToast(error: errors[index])
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 20)
            .padding(.trailing, 20)
        }
    }
}

// MARK: - Skeleton Loading Demo
private struct SkeletonLoadingDemo: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Skeleton Loading Demo")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(spacing: 16) {
                // Music player skeleton
                VStack(alignment: .leading, spacing: 8) {
                    Text("Music Player Skeleton")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    MusicPlayerSkeleton()
                        .frame(maxWidth: 320)
                }
                
                // General skeletons
                VStack(alignment: .leading, spacing: 8) {
                    Text("General Skeletons")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 12) {
                        SkeletonView(width: 200, height: 16, cornerRadius: 4)
                        SkeletonView(width: 150, height: 14, cornerRadius: 4)
                        SkeletonView(width: 100, height: 12, cornerRadius: 4)
                        
                        HStack(spacing: 8) {
                            SkeletonView(width: 24, height: 24, cornerRadius: 12)
                            SkeletonView(width: 24, height: 24, cornerRadius: 12)
                            SkeletonView(width: 24, height: 24, cornerRadius: 12)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: 320)
                }
            }
        }
        .padding()
    }
}

// MARK: - Loading States Demo
private struct LoadingStatesDemo: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Loading States Demo")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(spacing: 16) {
                // Loading spinners
                VStack(alignment: .leading, spacing: 8) {
                    Text("Loading Spinners")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 20) {
                        VStack(spacing: 4) {
                            LoadingSpinner(size: 12)
                            Text("Small")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 4) {
                            LoadingSpinner(size: 16)
                            Text("Medium")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 4) {
                            LoadingSpinner(size: 24)
                            Text("Large")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                
                // Loading indicators
                VStack(alignment: .leading, spacing: 8) {
                    Text("Loading Indicators")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 12) {
                        LoadingIndicator("Loading content...")
                        LoadingIndicator("Connecting...", compact: true)
                        LoadingIndicator("Initializing services...")
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                
                // Inline error views
                VStack(alignment: .leading, spacing: 8) {
                    Text("Inline Errors")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 12) {
                        InlineErrorView("WiFi Error")
                        InlineErrorView("BT Error", compact: true)
                        InlineErrorView("Battery Error")
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
    }
}

#Preview {
    ErrorStatePreview()
}