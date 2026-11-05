import Foundation

/// Uso da Groq contado neste Mac: cada áudio enviado vira uma entrada com a duração e o modelo.
struct GroqUsage: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var date: Date
        var seconds: Double
        var model: String
    }

    var entries: [Entry] = []
    /// Pedidos restantes no dia, como a própria Groq informa na resposta (x-ratelimit-*-requests).
    var remainingRequests: Int?
    var limitRequests: Int?
    var headersDate: Date?

    func seconds(since date: Date) -> Double {
        entries.filter { $0.date >= date }.reduce(0) { $0 + $1.seconds }
    }

    func requests(since date: Date) -> Int {
        entries.filter { $0.date >= date }.count
    }

    /// Entradas do mês corrente (para o total e o custo).
    var thisMonth: [Entry] {
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .distantPast
        return entries.filter { $0.date >= start }
    }

    /// Quanto o mês custaria no plano pago, pelo preço de cada modelo.
    var monthCost: Double {
        thisMonth.reduce(0) { $0 + max($1.seconds, GroqLimits.minimumBilledSeconds) / 3600 * GroqLimits.pricePerHour($1.model) }
    }

    /// Fração usada de cada limite do plano grátis (0…1).
    var dayAudioFraction: Double { seconds(since: .now.addingTimeInterval(-86_400)) / GroqLimits.audioSecondsPerDay }
    var hourAudioFraction: Double { seconds(since: .now.addingTimeInterval(-3_600)) / GroqLimits.audioSecondsPerHour }

    /// Pedidos nas últimas 24 h: usa o número da Groq quando ele é recente, senão a contagem local.
    /// Pedidos gastos do saldo diário da Groq. Medido em 1 nov 2026 pelos cabeçalhos x-ratelimit-*: a Groq não conta
    /// "pedidos nas últimas 24 h", e sim um saldo que recarrega. Cada pedido gasta 1, e cada 1 volta depois de
    /// 24 h ÷ limite (43,2 s com 2.000). Por isso o saldo pode estar quase cheio mesmo com muitos pedidos no mês.
    func requestsUsed(at now: Date = .now) -> (used: Int, limit: Int) {
        if let remainingRequests, let limitRequests, limitRequests > 0, let headersDate {
            let refill = 86_400 / Double(limitRequests)
            let used = Double(limitRequests - remainingRequests) - now.timeIntervalSince(headersDate) / refill
            return (max(0, Int(used.rounded(.up))), limitRequests)
        }
        // Sem resposta da Groq ainda: o mesmo saldo, calculado pelos pedidos feitos neste Mac.
        let refill = 86_400 / Double(GroqLimits.requestsPerDay)
        var used = 0.0
        var last: Date?
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            if let last { used = max(0, used - entry.date.timeIntervalSince(last) / refill) }
            used += 1
            last = entry.date
        }
        if let last { used = max(0, used - now.timeIntervalSince(last) / refill) }
        return (Int(used.rounded(.up)), GroqLimits.requestsPerDay)
    }

    var dayRequests: (used: Int, limit: Int) { requestsUsed() }

    var dayRequestsFraction: Double {
        let r = dayRequests
        return Double(r.used) / Double(max(r.limit, 1))
    }

    /// O limite mais perto de acabar (é ele que dispara o aviso na Home).
    /// `name` diz qual limite: "day", "hour" ou "requests".
    var tightest: (fraction: Double, name: String) {
        [(dayAudioFraction, "day"), (hourAudioFraction, "hour"), (dayRequestsFraction, "requests")]
            .max { $0.0 < $1.0 }
            .map { (min($0.0, 1), $0.1) } ?? (0, "")
    }

    mutating func record(seconds: Double, model: String, remaining: Int?, limit: Int?) {
        entries.append(Entry(date: .now, seconds: seconds, model: model))
        // Guarda ~40 dias: o suficiente para o mês e para as janelas de 24 h.
        let cutoff = Date.now.addingTimeInterval(-40 * 86_400)
        entries.removeAll { $0.date < cutoff }
        if let remaining, let limit {
            remainingRequests = remaining
            limitRequests = limit
            headersDate = .now
        }
    }
}

/// Limites do plano grátis e preços da Groq (outubro de 2026, docs de rate limits e anúncio do turbo).
enum GroqLimits {
    static let audioSecondsPerDay = 28_800.0   // 8 h
    static let audioSecondsPerHour = 7_200.0   // 2 h
    static let requestsPerDay = 2_000
    /// A Groq cobra no mínimo 10 s por pedido.
    static let minimumBilledSeconds = 10.0
    /// O aviso na Home aparece quando sobra 15% ou menos de algum limite.
    static let warningFraction = 0.85

    static func pricePerHour(_ model: String) -> Double {
        model == "whisper-large-v3" ? 0.111 : 0.04
    }
}

enum UsageFormat {
    /// "0 min", "42 min", "1 h 05 min", "8 h".
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return seconds > 0 && minutes == 0 ? T("<1 min") : T("%ld min", minutes) }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? T("%ld h", h) : T("%ld h %02ld min", h, m)
    }

    static func dollars(_ value: Double) -> String {
        String(format: value > 0 && value < 0.01 ? "$%.3f" : "$%.2f", value)
    }
}
