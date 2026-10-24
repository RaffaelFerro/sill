import SwiftUI
import UIKit
import StreamProtocol

/// Sill Plus: a left and a right mouse button and a scroll bar over the picture (Settings' Click
/// Buttons, `Sill.clickButtons`, off by default; Raffael, 2026-10-23). They act where the Mac's pointer
/// is now (the pad's anchor: the last tap, the trackpad's arrow or the Mac's own), as a mouse's buttons
/// and wheel do. The left button holds while the finger stays on it, so a finger on the trackpad, or
/// another on the picture, drags with it.
struct PointerButtons: View {
    let client: StreamClient

    static let key = "Sill.clickButtons"

    @State private var leftHeld = false
    @State private var rightHeld = false
    /// The scroll bar's drag so far, in points, and whether its gesture began on the Mac.
    @State private var scrolled: CGFloat = 0
    @State private var scrolling = false
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)

    /// Where the Mac's pointer is, as fractions of the frame; the middle before anything is known.
    private var at: CGPoint { client.pointerFeedState.anchor ?? CGPoint(x: 0.5, y: 0.5) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HStack(spacing: 6) {
                    button("L", label: "Left Click", held: $leftHeld, down: .leftDown, up: .leftUp)
                    button("R", label: "Right Click", held: $rightHeld, down: .rightDown, up: .rightUp)
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                scrollBar(height: max(60, geo.size.height - 64))
                    .padding(.top, 8)
                    .padding(.trailing, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }

    /// A button held while the finger stays on it: the button's down at the touch, its up at the lift.
    private func button(_ title: String, label: String, held: Binding<Bool>,
                        down: PointerAction, up: PointerAction) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 46, height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(held.wrappedValue ? 0.8 : 0.5)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(held.wrappedValue ? 0.5 : 0.18), lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !held.wrappedValue else { return }
                    held.wrappedValue = true
                    haptic.impactOccurred(intensity: 0.8)
                    let p = at
                    client.sendInput(.pointer(down, x: p.x, y: p.y))
                }
                .onEnded { _ in
                    guard held.wrappedValue else { return }
                    held.wrappedValue = false
                    let p = at
                    client.sendInput(.pointer(up, x: p.x, y: p.y))
                })
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                let p = at
                client.sendInput(.pointer(down, x: p.x, y: p.y))
                client.sendInput(.pointer(up, x: p.x, y: p.y))
            }
    }

    /// Drag down to see further down, as a scroll bar's thumb: the content moves the other way.
    private func scrollBar(height: CGFloat) -> some View {
        Capsule()
            .fill(Color.black.opacity(scrolling ? 0.7 : 0.4))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .overlay(VStack {
                Image(systemName: "chevron.up")
                Spacer()
                Image(systemName: "chevron.down")
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.8))
            .padding(.vertical, 8))
            .frame(width: 26, height: height)
            .frame(width: 40)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let p = at
                    if !scrolling {
                        scrolling = true
                        scrolled = 0
                        haptic.impactOccurred(intensity: 0.5)
                        client.sendInput(.scrollGesture(.began, x: p.x, y: p.y))
                    }
                    let delta = value.translation.height - scrolled
                    scrolled = value.translation.height
                    guard delta != 0 else { return }
                    // One bar's height of drag scrolls about a frame and a half.
                    client.sendInput(.scroll(x: p.x, y: p.y, dx: 0, dy: Double(-delta / height * 1.5)))
                }
                .onEnded { _ in
                    guard scrolling else { return }
                    scrolling = false
                    let p = at
                    client.sendInput(.scrollGesture(.ended, x: p.x, y: p.y))
                })
            .accessibilityLabel("Scroll")
            .accessibilityAdjustableAction { direction in
                let p = at
                let dy = direction == .increment ? -0.3 : 0.3
                client.sendInput(.scrollGesture(.began, x: p.x, y: p.y))
                client.sendInput(.scroll(x: p.x, y: p.y, dx: 0, dy: dy))
                client.sendInput(.scrollGesture(.ended, x: p.x, y: p.y))
            }
    }
}
