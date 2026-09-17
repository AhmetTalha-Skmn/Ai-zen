import SwiftUI
import AppKit
import ServiceManagement
import TakipCore

@main @MainActor struct CalismaTakipApp: App {
    @StateObject private var engine: Engine
    @Environment(\.openWindow) private var openWindow
    init() {
        if CommandLine.arguments.contains("--unregister-login") {
            do {
                if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
                exit(0)
            }
            catch { fputs("Otomatik başlatma kapatılamadı. Uygulama ayarlarından kapatın.\n", stderr); exit(1) }
        }
        do {
            // StateObject kapanışı hata fırlatamaz ve geç çalışır; motor önce oluşturulur ki
            // başlatma hatası burada yakalanıp kullanıcıya gösterilebilsin.
            let engine = try Engine()
            _engine = StateObject(wrappedValue: engine)
        }
        catch {
            let alert = NSAlert(); alert.messageText = "Aizen başlatılamadı"
            alert.informativeText = error.localizedDescription; alert.runModal()
            exit(1)
        }
    }
    var body: some Scene {
        MenuBarExtra("\(engine.total)/\(engine.state.settings.targetMinutes) dk", systemImage: "timer") {
            Button("Aizen’i aç") { openWindow(id: "panel"); NSApp.activate(ignoringOtherApps: true) }
            Text("Bu Mac: \(engine.today.minutes) dk · Diğer cihazlar: \(engine.otherMinutes) dk")
            Divider()
            if engine.paused { Button("Takibi sürdür") { engine.resume() } }
            else { Button("30 dakika duraklat") { engine.pause(minutes: 30) } }
            Button(engine.stopped ? "Acil durdurmayı kaldır" : "Acil durdur · uyarıları kapat") { engine.emergency() }
            Divider()
            Button("Çıkış") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
        Window("Aizen", id: "panel") { Panel(engine: engine) }
            .defaultSize(width: 1050, height: 760)
    }
}

// Xcode 15 SDK'da View yalniz body'yi MainActor yapar; yardimci uyeler Engine/Center'a eristigi icin tum gorunum MainActor.
@MainActor struct Panel: View {
    @ObservedObject var engine: Engine
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Aizen").font(.largeTitle.bold())
                    Text(engine.currentApp).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text("\(engine.total) / \(engine.state.settings.targetMinutes) dk").font(.title.monospacedDigit().bold())
            }
            ProgressView(value: min(Double(engine.total), Double(engine.state.settings.targetMinutes)), total: Double(engine.state.settings.targetMinutes))
            HStack {
                Text("Bu Mac \(engine.today.minutes) dk · Diğer cihazlar \(engine.otherMinutes) dk").foregroundStyle(.secondary)
                Spacer()
                if engine.paused { Text("Duraklatıldı").foregroundStyle(.orange) }
                if engine.stopped { Text("Acil durdurma açık").foregroundStyle(.red) }
            }
            if !engine.permissionsOK {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text("Pencere başlığı ve tarayıcı alan adı için Erişilebilirlik izni gerekiyor. Uygulama adıyla takip devam eder.").font(.callout)
                    Spacer(); Button("İzin ver") { Activity.requestPermission() }
                }.padding(10).background(.orange.opacity(0.08)).cornerRadius(8)
            }
            TabView {
                TodayView(engine: engine).tabItem { Label("Takip ve rapor", systemImage: "chart.bar") }
                LocalRulesView(engine: engine).tabItem { Label("Yerel kurallar", systemImage: "checklist") }
                ConnectionView(engine: engine).tabItem { Label("Merkeze bağlan", systemImage: "network") }
                CenterView(center: engine.center).tabItem { Label("Mac merkez", systemImage: "desktopcomputer") }
                SettingsView(engine: engine).tabItem { Label("Ayarlar ve yedek", systemImage: "gearshape") }
                WikiView(engine: engine).tabItem { Label("Yardım", systemImage: "questionmark.circle") }
            }
            if !engine.error.isEmpty { Text(engine.error).foregroundStyle(.red).textSelection(.enabled) }
            if !engine.information.isEmpty { Text(engine.information).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.padding(22).frame(minWidth: 960, minHeight: 680)
    }
}
@MainActor struct TodayView: View {
    @ObservedObject var engine: Engine
    @State private var selected = dayKey(Date())
    var day: Day { engine.state.days[selected] ?? Day(date: selected) }
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Gün", selection: $selected) {
                    ForEach(Array(Set(engine.state.days.keys).union([dayKey(Date())])).sorted(by: >), id: \.self) { Text($0).tag($0) }
                }.frame(width: 220)
                Text("Çalışma \(day.minutes) dk · Diğer \(Int(day.otherSeconds/60)) dk · Boşta \(Int(day.idleSeconds/60)) dk").foregroundStyle(.secondary)
                Spacer(); Button("CSV aktar") { engine.export(day: day) }
            }
            HStack {
                Button("45 dk odak") { engine.focus(minutes: 45) }
                    .disabled(!engine.state.settings.screenLockEnabled)
                    .help(engine.state.settings.screenLockEnabled ? "Odak süresince izinsiz uygulama ekranı kaplayan uyarı gösterir." : "Ekran kilidi kapalı: odak oturumu engel göstermez. Ayarlar’dan açılabilir.")
                Button("Odağı bitir") { engine.focus(minutes: 0) }
                if engine.paused { Button("Sürdür") { engine.resume() } } else { Button("30 dk mola") { engine.pause(minutes: 30) } }
                Spacer(); Button(engine.stopped ? "Acil durdurmayı kaldır" : "Acil durdur") { engine.emergency() }.tint(.red)
            }
            if let end = engine.state.settings.focusUntil, end > Date() { Text("Odak bitişi: \(end.formatted(date: .omitted, time: .shortened))").foregroundStyle(.orange) }
            Table(day.applications.values.sorted { $0.seconds > $1.seconds }) {
                TableColumn("Uygulama", value: \.name)
                TableColumn("Kategori") { Text($0.category.rawValue) }
                TableColumn("Süre") { Text("\(Int($0.seconds / 60)) dk").monospacedDigit() }
            }
            Text("İncelenecek uygulamalar").font(.headline)
            List(day.unknown.values.filter { !Classifier.decided($0, rules: engine.state.rules) }.sorted { $0.seconds > $1.seconds }) { item in
                HStack {
                    VStack(alignment: .leading) { Text(item.app); Text(item.domain.isEmpty ? item.title : item.domain).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer()
                    Button("İzinli uygulama") { engine.decide(value: item.app, kind: .process, decision: .work) }
                    Button("İzinsiz uygulama") { engine.decide(value: item.app, kind: .process, decision: .forbidden) }
                    Button("Belirsiz kalsın") { engine.decide(value: item.app, kind: .process, decision: .uncertain) }
                }
            }.frame(minHeight: 110, maxHeight: 170)
        }.padding(14)
    }
}
@MainActor struct RuleEditor: View {
    let save: (String, RuleKind, Decision) -> Void
    @State private var value = ""
    @State private var kind = RuleKind.process
    @State private var decision = Decision.work
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Uygulama adı, tam başlık veya alan adı", text: $value)
                Picker("Tür", selection: $kind) { ForEach(RuleKind.allCases) { Text($0.label).tag($0) } }.frame(width: 185)
                Picker("Karar", selection: $decision) { ForEach(Decision.allCases) { Text($0.label).tag($0) } }.frame(width: 150)
                Button("Kaydet") { save(value, kind, decision) }.disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Başlık kuralında genel kelime yerine tam pencere adını kullan. Karar değişikliği aynı öğeye yeniden karar verilerek yapılır.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
@MainActor struct LocalRulesView: View {
    @ObservedObject var engine: Engine
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RuleEditor { engine.decide(value: $0, kind: $1, decision: $2) }
            List(engine.state.rules.rows, id: \.rowKey) { row in
                HStack { Text(row.oge).textSelection(.enabled); Spacer(); Text(row.tur.label).foregroundStyle(.secondary); Text(row.karar.label).frame(width: 80); Button("Yerelden sil") { engine.removeRule(row) } }
            }
            Toggle("Belirsiz süreler çalışma sayılsın", isOn: Binding(get: { engine.state.rules.belirsizSayilsin }, set: { value in engine.action { try engine.mutate { $0.rules.belirsizSayilsin = value } } }))
            Text("Finder, Dock ve kritik macOS süreçleri engelleme istisnasıdır. Merkez bu istisnaları değiştirmez.").font(.caption).foregroundStyle(.secondary)
        }.padding(14)
    }
}
@MainActor struct ConnectionView: View {
    @ObservedObject var engine: Engine
    @State private var server = "http://127.0.0.1:8787"
    @State private var code = ""
    @State private var name = Host.current().localizedName ?? "Mac"
    @State private var consent = false
    var body: some View {
        Form {
            if let c = engine.state.connection {
                LabeledContent("Merkez", value: c.server)
                LabeledContent("Cihaz", value: c.deviceName)
                LabeledContent("Son gönderim", value: c.lastSuccess?.formatted() ?? "Henüz yok")
                LabeledContent("Son kural alımı", value: c.lastRuleSuccess?.formatted() ?? "Henüz yok")
                LabeledContent("Bekleyen karar", value: String(engine.state.pending.count))
                LabeledContent("Bekleyen gün", value: String(engine.state.dirtyDays.count))
                if !c.lastError.isEmpty { Text(c.lastError).foregroundStyle(.red).textSelection(.enabled) }
                HStack { Button("Şimdi senkronla") { Task { await engine.sync() } }; Button("Bağlantıyı kes") { engine.disconnect() } }.disabled(engine.busy)
                Text("Bu Mac aynı zamanda merkezse, kendi takibinin ortak toplama katılması için merkez sekmesinde kendine kod üretip buradan bağlan.").font(.callout)
            } else {
                TextField("Merkez adresi", text: $server)
                TextField("Bu cihazın adı", text: $name)
                SecureField("Eşleşme kodu", text: $code)
                Text("5 dakikada bir uygulama adı, kategori, toplam süre ve takip sağlığı gönderilir. Karar verdiğin kural öğeleri ortak kural senkronunda paylaşılır. Ölçülen pencere başlıkları, tam URL, tuş, pano, ekran görüntüsü ve dosya içerikleri gönderilmez.").fixedSize(horizontal: false, vertical: true)
                Toggle("Bu kapsamda merkeze veri gönderilmesini onaylıyorum", isOn: $consent)
                Button(engine.busy ? "Bağlanıyor…" : "Merkeze bağlan") {
                    Task { await engine.connect(server: server, code: code, name: name, consent: consent); if engine.state.connection != nil { code = "" } }
                }.disabled(!consent || code.isEmpty || engine.busy)
                Text("Windows ve Mac merkezleri desteklenir. HTTP bağlantısını yalnız özel LAN/VPN üzerinde kullan.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
@MainActor struct CenterView: View {
    @ObservedObject var center: Center
    @State private var port = 8787
    @State private var target = 240
    @State private var lan = false
    @State private var deviceName = ""
    @State private var generatedCode = ""
    @State private var message = ""
    @State private var day = dayKey(Date())
    @State private var section = 0
    func perform(_ action: () throws -> Void) { do { try action(); message = "" } catch { message = error.localizedDescription } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(center.status).font(.headline)
                Spacer()
                TextField("Port", value: $port, format: .number).frame(width: 75)
                Toggle("LAN’a aç", isOn: $lan)
                TextField("Ortak hedef", value: $target, format: .number).frame(width: 75)
                Text("dk")
                Button(center.state.enabled ? "Merkezi kapat" : "Merkezi başlat") {
                    perform { guard let port = UInt16(exactly: port) else { throw AppError.message("Port geçersiz.") }; try center.configure(enabled: !center.state.enabled, port: port, lan: lan, target: target) }
                }
            }
            Text("Ağ/port/hedef değişiklikleri başlatma sırasında uygulanır. LAN modu tüm yerel ağ arayüzlerinde dinler; modemden port yönlendirmesi yapma.").font(.caption).foregroundStyle(.secondary)
            Picker("Görünüm", selection: $section) { Text("Cihazlar ve toplam").tag(0); Text("Ortak kurallar").tag(1) }.pickerStyle(.segmented)
            if section == 0 {
                HStack {
                    Picker("Gün", selection: $day) { ForEach(Array(Set(center.state.reports.keys).union([dayKey(Date())])).sorted(by: >), id: \.self) { Text($0).tag($0) } }.frame(width: 210)
                    Text("Toplam \(center.total(day: day)) / \(center.state.target) dk").font(.title2.bold())
                    Spacer()
                }
                HStack { TextField("Yeni cihaz adı", text: $deviceName); Button("1 saatlik eşleşme kodu üret") { perform { generatedCode = try center.code(name: deviceName) } } }
                if !generatedCode.isEmpty { Text(generatedCode).font(.title.monospaced()).textSelection(.enabled); Text("Kodu ilgili cihazda gir. Tek kullanımlıktır; burada yalnız bu oturumda gösterilir.").font(.caption) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(center.state.devices) { device in
                            CenterDeviceRow(center: center, device: device, report: center.state.reports[day]?[device.id], renewed: { generatedCode = $0 })
                        }
                    }
                }
                if center.state.devices.isEmpty { Text("Henüz cihaz yok. Windows veya Mac istemci için bir eşleşme kodu üret.").foregroundStyle(.secondary) }
            } else {
                RuleEditor { value, kind, decision in perform { try center.rule(RuleChange(value: value, kind: kind, decision: decision)) } }
                List(center.state.rules.rows, id: \.rowKey) { row in
                    HStack { Text(row.oge); Spacer(); Text(row.tur.label); Text(row.karar.label).frame(width: 80); Button("Ortak kuralı sil") { perform { try center.rule(row, remove: true) } } }
                }
                Text("Ortak kurallar sonraki gönderim turunda alınır. Silme işlemini destekleyen güncel istemciler silme kayıtlarını uygular.").font(.caption).foregroundStyle(.secondary)
            }
            if !message.isEmpty { Text(message).foregroundStyle(.red) }
        }.padding(14).onAppear { port = Int(center.state.port); lan = center.state.lan; target = center.state.target }
    }
}
@MainActor struct CenterDeviceRow: View {
    @ObservedObject var center: Center
    let device: CenterDevice
    let report: CenterReport?
    let renewed: (String) -> Void
    @State private var error = ""
    @State private var showDetails = false
    func change(_ action: (inout CenterDevice) -> Void) {
        var next = device; action(&next)
        do { try center.updateDevice(next); error = "" } catch { self.error = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(device.name).font(.headline)
                Text(report.map { "\($0.work) / \(device.target) dk" } ?? "Veri yok").monospacedDigit()
                Spacer()
                Toggle("Aktif", isOn: Binding(get: { device.active }, set: { flag in change { $0.active = flag } }))
                Toggle("Kural yazabilir", isOn: Binding(get: { device.canWriteRules }, set: { flag in change { $0.canWriteRules = flag } }))
                Button("Yeni kod") { do { renewed(try center.code(name: device.name, deviceID: device.id)) } catch { self.error = error.localizedDescription } }
            }
            HStack {
                Stepper("Hedef \(device.target) dk", value: Binding(get: { device.target }, set: { value in change { $0.target = value } }), in: 15...1440, step: 15)
                Spacer()
                Text("Onay: " + (device.consent?.formatted(date: .numeric, time: .shortened) ?? "Bekleniyor")).font(.caption)
            }
            if let report {
                Text("Son gönderim: \(report.received.formatted()) · Bekleyen karar: \(report.pendingRules.map(String.init) ?? "Bilinmiyor")").font(.caption)
                    .foregroundColor(Date().timeIntervalSince(report.received) > 21600 ? .red : .secondary)
                if !report.syncError.isEmpty { Text("Son bildirilen hata: " + report.syncError).font(.caption).foregroundStyle(.orange) }
                DisclosureGroup("Uygulama dağılımı", isExpanded: $showDetails) {
                    ForEach(Array(report.apps.enumerated()), id: \.offset) { _, app in
                        HStack { Text(app.name); Spacer(); Text("\(app.minutes) dk · \(app.category)") }
                    }
                }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
        }.padding(12).background(Color.primary.opacity(0.04)).cornerRadius(8)
    }
}
@MainActor struct SettingsView: View {
    @ObservedObject var engine: Engine
    @State private var target = 240
    var typeDescription: String {
        switch engine.state.settings.effectiveInstallType {
        case .individual: return "Kişisel kullanım: hatırlatma ve ekran kilidi varsayılan olarak açık."
        case .company: return "Şirket bilgisayarı: hatırlatma yok; ekran kilidi varsayılan olarak kapalı."
        case .custom: return "Özel: hatırlatma varsayılan olarak açık, ekran kilidi kapalı; ikisini de aşağıdan seç."
        }
    }
    var body: some View {
        Form {
            Section("Kurulum türü ve özellikler") {
                Picker("Kurulum türü", selection: Binding(get: { engine.state.settings.effectiveInstallType }, set: { engine.setInstallType($0) })) {
                    ForEach(InstallType.allCases) { Text($0.label).tag($0) }
                }
                Text(typeDescription).font(.caption).foregroundStyle(.secondary)
                if engine.state.settings.remindersAvailable {
                    Toggle("45 dakikalık çalışma hatırlatmaları", isOn: Binding(get: { engine.state.settings.remindersEnabled }, set: { engine.setReminders($0) }))
                } else {
                    Text("Şirket kurulumunda hatırlatma yoktur. Ölçüm, rapor ve günlük hedef çalışmaya devam eder.").font(.callout)
                }
                Toggle("Ekran kilidi: uyarılar ve odak engeli ekranı kaplasın", isOn: Binding(get: { engine.state.settings.screenLockEnabled }, set: { engine.setScreenLock($0) }))
                Text("Kapalıyken hatırlatma küçük bir pencerede çıkar, ölçüm sürer ve odak oturumu engel göstermez.").font(.caption).foregroundStyle(.secondary)
                Button("Varsayılana dön") { engine.resetFeatures() }
            }
            HStack { TextField("Günlük hedef (dk)", value: $target, format: .number); Button("Kaydet") { engine.target(target) } }
            Toggle("Oturum açınca başlat", isOn: Binding(get: { engine.loginEnabled }, set: { engine.login($0) }))
            HStack { Button("Süresiz duraklat") { engine.pause(minutes: nil) }; Button("Takibi sürdür") { engine.resume() } }
            Section("Yerel veri yedeği") {
                Text("Haftada bir yedek alınır; son 8 otomatik yedek saklanır. Kurallar, ayarlar, günlük özetler ve aktivite CSV’leri dahildir. Cihaz anahtarları ve merkez sunucusunun verileri bu yedeğe girmez.")
                HStack { Button("Şimdi yedek al") { engine.backup() }; Button("Yedekten geri yükle") { engine.restore() }.disabled(engine.busy) }
                Text("Geri yüklemeden önce yedek doğrulanır ve mevcut verinin güvenlik yedeği alınır. Bağlı merkez kendi ortak kurallarını sonraki senkronda tekrar uygular.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Veri klasörünü aç") { NSWorkspace.shared.open(engine.storage.root) }
            Text(engine.storage.root.path).font(.caption).textSelection(.enabled)
            Text("Tarayıcı geçmişi okunmaz. Tarayıcı adres çubuğu Erişilebilirlik üzerinden tanınabildiğinde yalnız alan adı kaydedilir. macOS izin vermediğinde alan adı boş bırakılır.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).onAppear { target = engine.state.settings.targetMinutes }
    }
}
// Uygulama içi wiki: sayfalar kurulum türüne göre süzülür (TakipCore/Wiki.swift, içerik WikiIcerik.swift).
@MainActor struct WikiView: View {
    @ObservedObject var engine: Engine
    @State private var selected: String? = "baslarken"
    var body: some View {
        let pages = Wiki.sayfalar(tur: engine.state.settings.effectiveInstallType.rawValue)
        let names = Set(pages.map(\.ad))
        HStack(alignment: .top, spacing: 0) {
            List(pages, selection: $selected) { page in Text(page.baslik).tag(page.ad) }
                .frame(width: 220)
            Divider()
            ScrollView {
                if let page = pages.first(where: { $0.ad == selected }) ?? pages.first {
                    WikiPageView(page: page, names: names)
                        .padding(20)
                        .frame(maxWidth: 760, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Sayfa içi bağlantılar "wiki:<ad>" adresidir; dış adres açılmaz.
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "wiki" else { return .discarded }
                selected = String(url.absoluteString.dropFirst("wiki:".count))
                return .handled
            })
        }
    }
}
@MainActor struct WikiPageView: View {
    let page: WikiSayfasi
    let names: Set<String>
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Wiki.bloklar(page.govde).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }
    @ViewBuilder func blockView(_ block: WikiBlok) -> some View {
        switch block {
        case .baslik(let level, let text):
            inline(text)
                .font(level == 1 ? Font.title.bold() : level == 2 ? Font.title3.bold() : Font.headline)
                .padding(.top, level == 1 ? 0 : 6)
        case .paragraf(let text):
            inline(text).fixedSize(horizontal: false, vertical: true)
        case .liste(let items, let ordered):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: ordered ? "\(index + 1)." : "•").monospacedDigit()
                        inline(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .alinti(let text):
            inline(text)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(6)
        case .kod(let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
        case .tablo(let rows):
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            inline(cell).fontWeight(index == 0 ? Font.Weight.semibold : Font.Weight.regular).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if index == 0 { Divider() }
                }
            }
        }
    }
    /// Satır içi Markdown (kalın, kod, bağlantı); görünmeyen sayfaya bağlantı düz metin olur.
    func inline(_ text: String) -> Text {
        let markdown = Wiki.baglantilariCevir(text, adlar: names)
        if let attributed = try? AttributedString(markdown: markdown, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(markdown)
    }
}
