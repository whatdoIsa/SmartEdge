import SwiftUI

/// Pillow-shaped notch overlay that hugs the top of the display.
///
/// Top edge is straight so the overlay tucks under the menu bar or
/// hardware notch with no visible seam; only the bottom two corners
/// are rounded. Falls back to a manually drawn `Path` instead of
/// `UnevenRoundedRectangle` because the latter occasionally rendered
/// blank when wrapped inside another `Shape` (likely an animation /
/// shape-style interaction). The hand-rolled path is bulletproof.
///
/// `animatableData` is the expansion progress so the bottom radius
/// interpolates smoothly between the collapsed and expanded states
/// rather than snapping.
struct NotchShape: Shape {
    let isExpanded: Bool

    var animatableData: Double {
        get { isExpanded ? 1.0 : 0.0 }
        set { _ = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = animatableData
        let baseRadius = 11 + (16 - 11) * CGFloat(progress)
        // Clamp radius so corners never overlap at tiny sizes (default
        // notch is 32pt tall; radius must be ≤ height/2).
        let radius = min(baseRadius, min(rect.width, rect.height) / 2)

        var path = Path()
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        // Walk the perimeter clockwise starting at the top-left.
        path.move(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - radius))

        // Bottom-right rounded corner.
        path.addQuadCurve(
            to: CGPoint(x: maxX - radius, y: maxY),
            control: CGPoint(x: maxX, y: maxY)
        )

        path.addLine(to: CGPoint(x: minX + radius, y: maxY))

        // Bottom-left rounded corner.
        path.addQuadCurve(
            to: CGPoint(x: minX, y: maxY - radius),
            control: CGPoint(x: minX, y: maxY)
        )

        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 24) {
        NotchShape(isExpanded: false)
            .fill(.regularMaterial)
            .frame(width: 200, height: 32)
        NotchShape(isExpanded: true)
            .fill(.regularMaterial)
            .frame(width: 380, height: 130)
    }
    .padding(40)
    .background(Color.black)
}
