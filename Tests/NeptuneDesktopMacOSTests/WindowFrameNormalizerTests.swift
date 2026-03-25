import CoreGraphics
import Testing
@testable import NeptuneDesktopMacOS

@Suite("WindowFrameNormalizer")
struct WindowFrameNormalizerTests {
    @Test("re-centers frame when window is entirely outside all visible screens")
    func recentersOffscreenWindow() {
        let visible = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let frame = CGRect(x: -1800, y: 120, width: 1280, height: 860)

        let normalized = WindowFrameNormalizer.normalize(
            frame: frame,
            visibleFrames: visible,
            minSize: CGSize(width: 960, height: 640),
            preferredSize: CGSize(width: 1280, height: 860)
        )

        #expect(visible[0].intersects(normalized))
        #expect(normalized.width == 1280)
        #expect(normalized.height == 860)
    }

    @Test("expands invalid tiny frame to preferred size and clamps inside visible area")
    func expandsTinyFrame() {
        let visible = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let frame = CGRect(x: 100, y: 100, width: 1, height: 28)

        let normalized = WindowFrameNormalizer.normalize(
            frame: frame,
            visibleFrames: visible,
            minSize: CGSize(width: 960, height: 640),
            preferredSize: CGSize(width: 1280, height: 860)
        )

        #expect(normalized.width == 1280)
        #expect(normalized.height == 860)
        #expect(visible[0].contains(normalized))
    }

    @Test("centers window on primary visible frame when requested")
    func centersOnPrimaryVisibleFrame() {
        let primary = CGRect(x: 0, y: 0, width: 1728, height: 995)
        let secondary = CGRect(x: 1728, y: -390, width: 1080, height: 1920)
        let frameOnSecondary = CGRect(x: 1728, y: -383, width: 1080, height: 860)

        let normalized = WindowFrameNormalizer.normalize(
            frame: frameOnSecondary,
            visibleFrames: [primary, secondary],
            minSize: CGSize(width: 960, height: 640),
            preferredSize: CGSize(width: 1280, height: 860),
            centerOnPrimaryVisibleFrame: true
        )

        #expect(primary.intersects(normalized))
        #expect(primary.contains(normalized))
    }
}
