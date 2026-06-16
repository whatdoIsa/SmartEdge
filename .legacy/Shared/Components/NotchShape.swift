import SwiftUI

struct NotchShape: Shape {
    let isExpanded: Bool
    
    var animatableData: Double {
        get { isExpanded ? 1.0 : 0.0 }
        set { }
    }
    
    func path(in rect: CGRect) -> Path {
        let progress = animatableData
        
        // Interpolate corner radius based on expansion state
        let collapsedRadius: CGFloat = 12
        let expandedRadius: CGFloat = 16
        let cornerRadius = collapsedRadius + (expandedRadius - collapsedRadius) * progress
        
        // Create smooth rounded rectangle path
        return Path { path in
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
            )
        }
    }
}