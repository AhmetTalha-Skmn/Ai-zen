import Foundation

// Uygulama içi wiki. Sayfalar depodaki wiki/*.md dosyalarından WikiIcerik.swift'e üretilir
// (macos/scripts/generate-wiki.ps1); kurallar Windows'taki hatirlatici/wiki.ps1 ile aynıdır.
public struct WikiSayfasi: Identifiable, Equatable {
    public let ad: String
    public let baslik: String
    /// Boş: bütün kurulum türlerinde görünür.
    public let turler: [String]
    public let sira: Int
    public let govde: String
    public var id: String { ad }
    public init(ad: String, baslik: String, turler: [String], sira: Int, govde: String) {
        self.ad = ad; self.baslik = baslik; self.turler = turler; self.sira = sira; self.govde = govde
    }
}

public enum WikiBlok: Equatable {
    case baslik(Int, String)
    case paragraf(String)
    case liste([String], sirali: Bool)
    case alinti(String)
    case kod(String)
    case tablo([[String]])
}

public enum Wiki {
    public static let platform = "mac"
    static let turEtiketleri: Set<String> = ["bireysel", "sirket", "ozel"]
    static let platformEtiketleri: Set<String> = ["windows", "mac"]

    public static func etiketler(_ metin: String) -> [String] {
        let m = metin.trimmingCharacters(in: .whitespaces).lowercased()
        if m.isEmpty || m == "hepsi" { return [] }
        return m.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" }).map(String.init)
    }

    /// Platform etiketi varsa platform, tür etiketi varsa tür eşleşmelidir.
    public static func gorunur(_ etiketler: [String], tur: String, platform: String = platform) -> Bool {
        let pl = etiketler.filter { platformEtiketleri.contains($0) }
        let tr = etiketler.filter { turEtiketleri.contains($0) }
        if !pl.isEmpty && !pl.contains(platform) { return false }
        if !tr.isEmpty && !tr.contains(tur) { return false }
        return true
    }

    /// `<!-- yalniz: ... -->` / `<!-- /yalniz -->` bloklarını uygular (iç içe olabilir); işaret satırları çıkar.
    public static func suz(_ govde: String, tur: String, platform: String = platform) -> String {
        var cikti: [String] = []
        var yigin: [Bool] = []
        for satir in govde.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let t = satir.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("<!--") && t.hasSuffix("-->") && t.count >= 7 {
                let ic = String(t.dropFirst(4).dropLast(3)).trimmingCharacters(in: .whitespaces)
                if ic == "/yalniz" { if !yigin.isEmpty { yigin.removeLast() }; continue }
                if ic.hasPrefix("yalniz") {
                    let kalan = String(ic.dropFirst("yalniz".count)).trimmingCharacters(in: .whitespaces)
                    if kalan.hasPrefix(":") {
                        yigin.append(gorunur(etiketler(String(kalan.dropFirst())), tur: tur, platform: platform))
                        continue
                    }
                }
            }
            if yigin.contains(false) { continue }
            cikti.append(satir)
        }
        return cikti.joined(separator: "\n")
    }

    /// Bu kurulum türünde görünen sayfalar, sıraya göre, blokları süzülmüş.
    public static func sayfalar(tur: String, kaynak: [WikiSayfasi] = WikiIcerik.sayfalar) -> [WikiSayfasi] {
        kaynak.filter { $0.turler.isEmpty || $0.turler.contains(tur) }
            .sorted { ($0.sira, $0.ad) < ($1.sira, $1.ad) }
            .map { WikiSayfasi(ad: $0.ad, baslik: $0.baslik, turler: $0.turler, sira: $0.sira, govde: suz($0.govde, tur: tur)) }
    }

    /// `[metin](sayfa)` bağlantısını görünen sayfa için `wiki:sayfa` adresine çevirir; gizli sayfaya bağlantı düz metin olur.
    public static func baglantilariCevir(_ metin: String, adlar: Set<String>) -> String {
        guard let desen = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#) else { return metin }
        let ns = metin as NSString
        var sonuc = ""
        var son = 0
        for m in desen.matches(in: metin, range: NSRange(location: 0, length: ns.length)) {
            sonuc += ns.substring(with: NSRange(location: son, length: m.range.location - son))
            let yazi = ns.substring(with: m.range(at: 1))
            let hedef = ns.substring(with: m.range(at: 2)).lowercased()
            sonuc += adlar.contains(hedef) ? "[\(yazi)](wiki:\(hedef))" : yazi
            son = m.range.location + m.range.length
        }
        return sonuc + ns.substring(from: son)
    }

    /// Desteklenen Markdown alt kümesini bloklara ayırır (wiki/README.md).
    public static func bloklar(_ markdown: String) -> [WikiBlok] {
        var sonuc: [WikiBlok] = []
        var paragraf: [String] = []
        var liste: [String] = []
        var sirali = false
        var alinti: [String] = []
        func kapat() {
            if !paragraf.isEmpty { sonuc.append(.paragraf(paragraf.joined(separator: " "))); paragraf = [] }
            if !liste.isEmpty { sonuc.append(.liste(liste, sirali: sirali)); liste = [] }
            if !alinti.isEmpty { sonuc.append(.alinti(alinti.joined(separator: " "))); alinti = [] }
        }
        let satirlar = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0
        while i < satirlar.count {
            let satir = satirlar[i]
            let t = satir.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                kapat()
                var kod: [String] = []
                i += 1
                while i < satirlar.count, !satirlar[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { kod.append(satirlar[i]); i += 1 }
                sonuc.append(.kod(kod.joined(separator: "\n")))
                i += 1
                continue
            }
            if t.isEmpty { kapat(); i += 1; continue }
            if t.hasPrefix("#") {
                let seviye = t.prefix(while: { $0 == "#" }).count
                let metin = t.dropFirst(seviye)
                if (1...3).contains(seviye), metin.first == " " {
                    kapat()
                    sonuc.append(.baslik(seviye, metin.trimmingCharacters(in: .whitespaces)))
                    i += 1
                    continue
                }
            }
            if t.hasPrefix("|") && t.hasSuffix("|") {
                kapat()
                var satirlarT: [[String]] = []
                while i < satirlar.count {
                    let tt = satirlar[i].trimmingCharacters(in: .whitespaces)
                    guard tt.hasPrefix("|"), tt.hasSuffix("|"), tt.count >= 2 else { break }
                    let hucreler = tt.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    let ayirici = hucreler.allSatisfy { hucre in !hucre.isEmpty && hucre.allSatisfy { "-: ".contains($0) } }
                    if !ayirici { satirlarT.append(hucreler) }
                    i += 1
                }
                sonuc.append(.tablo(satirlarT))
                continue
            }
            if let madde = listeOgesi(t) {
                if !paragraf.isEmpty || !alinti.isEmpty || (!liste.isEmpty && sirali != madde.sirali) { kapat() }
                sirali = madde.sirali
                liste.append(madde.metin)
                i += 1
                continue
            }
            if !liste.isEmpty, satir.hasPrefix("  ") { liste[liste.count - 1] += " " + t; i += 1; continue }
            if t.hasPrefix(">") {
                if !paragraf.isEmpty || !liste.isEmpty { kapat() }
                alinti.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                i += 1
                continue
            }
            if !liste.isEmpty || !alinti.isEmpty { kapat() }
            paragraf.append(t)
            i += 1
        }
        kapat()
        return sonuc
    }

    static func listeOgesi(_ t: String) -> (metin: String, sirali: Bool)? {
        if t.hasPrefix("- ") || t.hasPrefix("* ") { return (String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces), false) }
        let rakamlar = t.prefix(while: { $0.isASCII && $0.isNumber })
        if !rakamlar.isEmpty, t.dropFirst(rakamlar.count).hasPrefix(". ") {
            return (String(t.dropFirst(rakamlar.count + 2)).trimmingCharacters(in: .whitespaces), true)
        }
        return nil
    }
}
