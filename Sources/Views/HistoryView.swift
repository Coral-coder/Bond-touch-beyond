import SwiftUI

/// Log of touches sent and received, newest first (mirrors the original's History).
struct HistoryView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.history.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock").font(.largeTitle).foregroundStyle(.secondary)
                Text("No touches yet").font(.headline)
                Text("Touches you send and receive appear here.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.history.reversed()) { touch in
                let mine = touch.senderID == model.myUserID
                HStack(spacing: 12) {
                    Image(systemName: mine ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(mine ? Color.blue : Color.green)
                    Circle().fill(Color(rgbInt: touch.colorRGB)).frame(width: 16, height: 16)
                    VStack(alignment: .leading) {
                        Text(mine ? "Sent" : "Received").font(.subheadline.weight(.medium))
                        Text("\(touch.pattern.count + 1) tap\(touch.pattern.count == 0 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(touch.sentAt, style: .time).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
