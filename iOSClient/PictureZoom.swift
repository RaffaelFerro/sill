import CoreGraphics
import Combine

/// The picture's zoom: the streamed frame magnified on this device alone, with the Mac's pointer
/// held in the middle of the picture as macOS's own Zoom does (Raffael, 2026-10-21). Nothing goes to
/// the Mac: the window keeps its size, and a touch is mapped back through the zoom, so a click lands
/// where the finger is. Offered in a phone's row 1, under Aa (`TextScaleControl`'s second ruler);
/// it applies only while that arrangement shows (`allowed`), so a turn sideways shows the whole frame.
///
/// One object per client (`StreamClient.zoom`), main thread: the display view draws through `rect`,
/// the touch overlay maps through it, and the trackpad slows by `effectiveScale` so a stroke moves
/// the pointer as far on the glass as without zoom.
final class PictureZoom: ObservableObject {
    /// The ruler's detents.
    static let steps: [Double] = [1, 1.5, 2, 3, 4]
    /// What a tap on Aa zooms to when the picture is not zoomed, before any other value was chosen.
    static let defaultZoom: Double = 2

    /// The zoom chosen, 1 for none.
    @Published var scale: Double = 1 { didSet { if scale != oldValue { if scale > 1 { last = scale }; changed(animated: true) } } }
    /// The last zoom above 1, which a tap on Aa brings back.
    private(set) var last: Double = PictureZoom.defaultZoom
    /// Whether the arrangement that offers it is on screen: the phone held upright.
    private(set) var allowed = false { didSet { if allowed != oldValue { changed(animated: false) } } }
    /// The arrangements on screen that offer it: counted, since SwiftUI may show the new one before
    /// it lets the old one go.
    private var offering = 0 { didSet { allowed = offering > 0 } }
    func offered() { offering += 1 }
    func withdrawn() { offering = max(0, offering - 1) }
    /// The scale that applies now.
    var effectiveScale: CGFloat { allowed && scale > 1 ? CGFloat(scale) : 1 }

    /// The point of the frame held in the picture's middle, as fractions of the frame: where the
    /// Mac's pointer is, or where a finger last touched.
    private(set) var focus = CGPoint(x: 0.5, y: 0.5)
    /// Fingers on the picture: while any is down the view holds still, or the content would slide
    /// under a finger that is dragging on the Mac and the drag would chase itself.
    private var touching = 0
    /// A focus that came while a finger was down, taken when the last one lifts.
    private var pendingFocus: CGPoint?

    /// The display view, told to draw again; `animated` for a jump (a zoom chosen, a tap elsewhere).
    var onChange: ((_ animated: Bool) -> Void)?

    /// A tap on Aa: zoomed out, back to the last zoom; zoomed in, out.
    func toggle() { scale = scale > 1 ? 1 : last }

    /// The pointer is at `p` (a fraction of the frame): the Mac's arrow, this device's own, or a
    /// finger's touch.
    func follow(_ p: CGPoint) {
        let clamped = CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
        if touching > 0 { pendingFocus = clamped; return }
        let jump = hypot(clamped.x - focus.x, clamped.y - focus.y) * effectiveScale > 0.25
        focus = clamped
        if effectiveScale > 1 { onChange?(jump) }
    }

    func touchesBegan(_ count: Int) { touching += count }
    func touchesEnded(_ count: Int) {
        touching = max(0, touching - count)
        guard touching == 0, let p = pendingFocus else { return }
        pendingFocus = nil
        follow(p)
    }

    /// Where the whole frame is drawn now, for a frame drawn at `video` (aspect-fit) inside `bounds`.
    func rect(video: CGRect, bounds: CGRect) -> CGRect {
        Self.zoomedRect(video: video, bounds: bounds, scale: effectiveScale, focus: focus)
    }

    private func changed(animated: Bool) {
        if !allowed || scale <= 1 { touching = 0; pendingFocus = nil }
        onChange?(animated)
    }

    /// Pure: the frame, drawn at `video` without zoom, magnified `scale` times so the point `focus`
    /// (fractions of the frame) sits in the middle of `bounds`, but never leaving bounds uncovered
    /// along an axis the magnified frame is longer than: there it stops at the frame's edge. Along an
    /// axis where it is still shorter than `bounds` it stays centred, as the letterbox was.
    static func zoomedRect(video: CGRect, bounds: CGRect, scale: CGFloat, focus: CGPoint) -> CGRect {
        guard scale > 1, video.width > 0, video.height > 0, bounds.width > 0, bounds.height > 0 else { return video }
        func origin(length: CGFloat, boundsMin: CGFloat, boundsLength: CGFloat, fraction: CGFloat) -> CGFloat {
            guard length > boundsLength else { return boundsMin + (boundsLength - length) / 2 }
            let centred = boundsMin + boundsLength / 2 - fraction * length
            return min(boundsMin, max(boundsMin + boundsLength - length, centred))
        }
        let width = video.width * scale, height = video.height * scale
        return CGRect(x: origin(length: width, boundsMin: bounds.minX, boundsLength: bounds.width, fraction: focus.x),
                      y: origin(length: height, boundsMin: bounds.minY, boundsLength: bounds.height, fraction: focus.y),
                      width: width, height: height)
    }
}
