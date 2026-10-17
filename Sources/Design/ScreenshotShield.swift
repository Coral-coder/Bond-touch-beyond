import SwiftUI
import UIKit

/// Hides its content from screenshots and screen recordings, as the original Private Space
/// does on Android (FLAG_SECURE). iOS has no such flag, so the content is hosted inside a
/// secure text field's canvas — the layer iOS blanks out of captures. If that layer isn't
/// there (a future iOS), the content simply shows normally.
///
/// The content is hosted in its own UIKit view, so pass in the environment objects it needs.
struct ScreenshotShield<Content: View>: UIViewRepresentable {
    @ViewBuilder var content: () -> Content

    func makeUIView(context: Context) -> UIView {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        let host = context.coordinator.host
        let container = HostContainer(host: host)
        container.backgroundColor = .clear
        host.rootView = AnyView(content())
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        // The secure field's first subview is the canvas iOS keeps out of captures.
        let canvas = field.subviews.first
        let parent = canvas ?? container
        if let canvas {
            canvas.isUserInteractionEnabled = true
            canvas.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(canvas)
            pin(canvas, to: container)
        }
        parent.addSubview(host.view)
        pin(host.view, to: parent)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.host.rootView = AnyView(content())
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        let host = UIHostingController(rootView: AnyView(EmptyView()))
    }

    /// Makes the hosting controller a child of the screen's view controller once on screen,
    /// so sheets, pickers and full-screen views presented from inside it work.
    final class HostContainer: UIView {
        let host: UIViewController
        init(host: UIViewController) { self.host = host; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                host.willMove(toParent: nil)
                host.removeFromParent()
                return
            }
            guard host.parent == nil, let parent = owningViewController else { return }
            parent.addChild(host)
            host.didMove(toParent: parent)
        }

        private var owningViewController: UIViewController? {
            var responder: UIResponder? = next
            while let r = responder {
                if let vc = r as? UIViewController { return vc }
                responder = r.next
            }
            return nil
        }
    }

    private func pin(_ view: UIView, to parent: UIView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            view.topAnchor.constraint(equalTo: parent.topAnchor),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }
}
