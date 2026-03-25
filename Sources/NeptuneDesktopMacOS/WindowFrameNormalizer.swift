import CoreGraphics

enum WindowFrameNormalizer {
    static func normalize(
        frame: CGRect,
        visibleFrames: [CGRect],
        minSize: CGSize,
        preferredSize: CGSize,
        centerOnPrimaryVisibleFrame: Bool = false
    ) -> CGRect {
        let candidateVisibleFrames = visibleFrames
            .map(\.standardized)
            .filter { $0.width > 0 && $0.height > 0 }

        var next = frame.standardized
        let minimumWidth = max(1, minSize.width)
        let minimumHeight = max(1, minSize.height)
        let desiredWidth = max(preferredSize.width, minimumWidth)
        let desiredHeight = max(preferredSize.height, minimumHeight)

        if next.width < minimumWidth {
            next.size.width = desiredWidth
        }
        if next.height < minimumHeight {
            next.size.height = desiredHeight
        }

        guard let primaryVisibleFrame = candidateVisibleFrames.first else {
            return next.integral
        }

        next.size.width = min(next.size.width, primaryVisibleFrame.width)
        next.size.height = min(next.size.height, primaryVisibleFrame.height)

        if centerOnPrimaryVisibleFrame || !candidateVisibleFrames.contains(where: { $0.intersects(next) }) {
            next.origin.x = primaryVisibleFrame.midX - next.width / 2
            next.origin.y = primaryVisibleFrame.midY - next.height / 2
        }

        if let intersectingVisibleFrame = candidateVisibleFrames.first(where: { $0.intersects(next) }) {
            next.origin.x = min(max(next.origin.x, intersectingVisibleFrame.minX), intersectingVisibleFrame.maxX - next.width)
            next.origin.y = min(max(next.origin.y, intersectingVisibleFrame.minY), intersectingVisibleFrame.maxY - next.height)
        }

        return next.integral
    }
}
