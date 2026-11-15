import SwiftUI
import UIKit

/// Asks before unbonding, and offers "Export our relationship first": a readable copy of
/// Where we stand with them (meter history, wishes, promises, kept moments) through the
/// share sheet. Then the bond is removed as usual, and the shared Us data goes with it.
struct UnbondConfirm: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Binding var partner: Partner?
    var onDone: () -> Void = {}
    @State private var files: ExportFiles?
    /// Asked again once the share sheet closes.
    @State private var askAgain: Partner?

    struct ExportFiles: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Unbond from \(partner?.displayName ?? "this partner")?",
                                isPresented: Binding(get: { partner != nil }, set: { if !$0 { partner = nil } }),
                                titleVisibility: .visible, presenting: partner) { p in
                if !p.bond.legacy && Feature.us.isOn {
                    Button("Export our relationship first") {
                        askAgain = p
                        let urls = model.standExport(p.id)
                        // After the dialog has gone, or the sheet won't show.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { files = ExportFiles(urls: urls) }
                    }
                }
                Button("Unbond", role: .destructive) {
                    Task { await model.removeBond(p.bond); onDone() }
                }
                Button("Cancel", role: .cancel) {}
            } message: { p in
                Text(p.bond.legacy ? "You can bond again later with a new invite."
                                   : "Your Us space with \(p.displayName), Where we stand included, goes with the bond. You can export a copy first.")
            }
            .sheet(item: $files, onDismiss: {
                guard let p = askAgain else { return }
                askAgain = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { partner = p }
            }) { f in
                ActivityView(items: f.urls).presentationDetents([.medium, .large])
            }
    }
}

extension View {
    /// The unbond question, with an export first, while `partner` is set.
    func unbondConfirm(_ partner: Binding<Partner?>, onDone: @escaping () -> Void = {}) -> some View {
        modifier(UnbondConfirm(partner: partner, onDone: onDone))
    }
}

/// The system share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
