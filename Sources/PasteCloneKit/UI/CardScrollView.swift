import AppKit
import SwiftUI

/// SwiftUI's `ScrollView(.horizontal)` doesn't respond to a plain vertical
/// mouse-wheel (only to trackpad horizontal swipes) — but Paste's own
/// timeline does. This NSScrollView subclass redirects a vertical wheel
/// delta into horizontal scrolling while leaving genuine horizontal input
/// (trackpad swipes) untouched.
final class WheelRedirectScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard let clipView = contentView as NSClipView? else {
            super.scrollWheel(with: event)
            return
        }
        // A trackpad swipe already carries a meaningful deltaX; only
        // redirect when the input is coming in on the vertical axis.
        let delta = abs(event.scrollingDeltaX) > 0.01 ? event.scrollingDeltaX : event.scrollingDeltaY
        var origin = clipView.bounds.origin
        origin.x -= delta
        let maxX = max(0, (documentView?.frame.width ?? 0) - clipView.bounds.width)
        origin.x = min(max(origin.x, 0), maxX)
        clipView.setBoundsOrigin(origin)
        reflectScrolledClipView(clipView)
    }
}

/// Owns the live NSScrollView so SwiftUI can ask it to scroll a given card
/// index into view (mirrors what `ScrollViewReader.scrollTo` gave us, but
/// computed from the cards' known fixed geometry instead of view lookup).
/// Not @MainActor-isolated: it's stored in a SwiftUI `@State` (whose default
/// value is evaluated in a non-isolated initializer context) but is only
/// ever touched from main-thread SwiftUI/AppKit callbacks in practice.
final class CardScrollCoordinator {
    fileprivate weak var scrollView: NSScrollView?

    func scrollToIndex(_ index: Int, cardWidth: CGFloat, spacing: CGFloat, leading: CGFloat, animated: Bool) {
        guard let scrollView, let clipView = scrollView.contentView as NSClipView? else { return }
        let cardMinX = leading + CGFloat(index) * (cardWidth + spacing)
        let cardMaxX = cardMinX + cardWidth
        let visible = clipView.bounds
        var targetX = visible.origin.x
        if cardMinX < visible.origin.x {
            targetX = cardMinX
        } else if cardMaxX > visible.origin.x + visible.width {
            targetX = cardMaxX - visible.width
        } else {
            return // already fully visible
        }
        let maxX = max(0, (scrollView.documentView?.frame.width ?? 0) - visible.width)
        targetX = min(max(targetX, 0), maxX)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                clipView.animator().setBoundsOrigin(NSPoint(x: targetX, y: visible.origin.y))
            }
        } else {
            clipView.setBoundsOrigin(NSPoint(x: targetX, y: visible.origin.y))
        }
        scrollView.reflectScrolledClipView(clipView)
    }
}

/// Hosts SwiftUI content inside a horizontally-scrolling NSScrollView.
struct CardScrollView<Content: View>: NSViewRepresentable {
    let coordinator: CardScrollCoordinator
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = WheelRedirectScrollView()
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none

        let hosting = NSHostingView(rootView: content())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hosting
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: scrollView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            hosting.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
        ])
        coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let hosting = nsView.documentView as? NSHostingView<Content> {
            hosting.rootView = content()
        }
        coordinator.scrollView = nsView
    }
}
