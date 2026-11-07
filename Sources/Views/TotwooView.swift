import SwiftUI

/// Settings → totwoo jewellery: pair it, see its battery, try how a partner's touch looks on
/// it, and choose whether tapping it sends a touch.
struct TotwooView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: LocalStore

    var body: some View {
        TotwooContent(totwoo: model.totwoo)
            .onAppear { model.totwoo.activate() }
    }
}

private struct TotwooContent: View {
    @EnvironmentObject var store: LocalStore
    @ObservedObject var totwoo: TotwooBracelet

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                    Text(totwoo.state.text)
                    Spacer()
                    if let b = totwoo.battery { Text("\(b)%").foregroundStyle(Theme.subtitle) }
                }
                if let m = totwoo.model { LabeledContent("Model", value: m) }
                if let f = totwoo.firmware { LabeledContent("Firmware", value: f) }
                if let e = totwoo.lastEvent { Text(e).font(.caption).foregroundStyle(Theme.subtitle) }
                if totwoo.isPaired {
                    Button("Forget this totwoo", role: .destructive) { totwoo.forget() }
                } else {
                    Button("Find my totwoo") { totwoo.startPairing() }
                }
            } header: {
                Text("totwoo jewellery")
            } footer: {
                Text("Your partners' touches light it in their colour, alongside (or instead of) a Bond Touch bracelet.")
            }

            if !totwoo.isPaired, !totwoo.found.isEmpty {
                Section("Nearby — tap yours") {
                    ForEach(totwoo.found) { d in
                        Button { totwoo.pair(d.id) } label: {
                            HStack {
                                Text(d.name).foregroundStyle(Theme.title)
                                if d.likely { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent) }
                                Spacer()
                                Text("\(d.rssi) dBm").font(.caption).foregroundStyle(Theme.subtitle)
                            }
                        }
                    }
                }
            }

            if totwoo.isReady {
                Section {
                    Button("Light it in my colour") { totwoo.notify(rgb: store.profile.colorRGB) }
                    Button("Vibrate") { totwoo.vibrate(pattern: max(1, totwoo.vibration)) }
                    Toggle("Tapping it sends a touch", isOn: $totwoo.tapSends).tint(Theme.accent)
                } header: {
                    Text("Try it")
                }

                Section {
                    Stepper("Alert type: \(totwoo.notifyMode)", value: $totwoo.notifyMode, in: 0...255)
                    Stepper("Flash style: \(totwoo.notifyStyle)", value: $totwoo.notifyStyle, in: 0...255)
                    Stepper(totwoo.vibration == 0 ? "Vibration: off" : "Vibration pattern: \(totwoo.vibration)",
                            value: $totwoo.vibration, in: 0...255)
                    Button("Test these") { totwoo.notify(rgb: store.profile.colorRGB)
                        if totwoo.vibration > 0 { totwoo.vibrate(pattern: totwoo.vibration) } }
                } header: {
                    Text("How touches look")
                } footer: {
                    Text("totwoo pieces differ in what each alert type and flash style does. Step through them with Test until a touch looks right; every message the jewellery sends back is in the network log (Settings → Debug).")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("totwoo")
    }
}
