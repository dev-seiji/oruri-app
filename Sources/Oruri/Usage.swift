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
    /// Limpezas pela Groq (desde a 0.6.6). O modelo de texto tem um saldo de pedidos próprio, separado do Whisper.
    /// Opcionais para os dados salvos antes continuarem abrindo.
    var cleanups: [Date]?
    var cleanupRemaining: Int?
    var cleanupLimit: Int?
    var cleanupHeadersDate: Date?

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
        Self.allowance(remaining: remainingRequests, limit: limitRequests, headersDate: headersDate,
                       dates: entries.map(\.date), fallbackLimit: GroqLimits.requestsPerDay, now: now)
    }

    /// Saldo diário de pedidos das limpezas (modelo de texto da Groq).
    func cleanupRequestsUsed(at now: Date = .now) -> (used: Int, limit: Int) {
        Self.allowance(remaining: cleanupRemaining, limit: cleanupLimit, headersDate: cleanupHeadersDate,
                       dates: cleanups ?? [], fallbackLimit: GroqLimits.cleanupRequestsPerDay, now: now)
    }

    var cleanupRequestsFraction: Double {
        let r = cleanupRequestsUsed()
        return Double(r.used) / Double(max(r.limit, 1))
    }

    /// Limpezas do mês corrente.
    var cleanupsThisMonth: Int {
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .distantPast
        return (cleanups ?? []).filter { $0 >= start }.count
    }

    private static func allowance(remaining: Int?, limit: Int?, headersDate: Date?, dates: [Date],
                                  fallbackLimit: Int, now: Date) -> (used: Int, limit: Int) {
        if let remaining, let limit, limit > 0, let headersDate {
            let refill = 86_400 / Double(limit)
            let used = Double(limit - remaining) - now.timeIntervalSince(headersDate) / refill
            return (max(0, Int(used.rounded(.up))), limit)
        }
        // Sem resposta da Groq ainda: o mesmo saldo, calculado pelos pedidos feitos neste Mac.
        let refill = 86_400 / Double(fallbackLimit)
        var used = 0.0
        var last: Date?
        for date in dates.sorted() {
            if let last { used = max(0, used - date.timeIntervalSince(last) / refill) }
            used += 1
            last = date
        }
        if let last { used = max(0, used - now.timeIntervalSince(last) / refill) }
        return (Int(used.rounded(.up)), fallbackLimit)
    }

    var dayRequests: (used: Int, limit: Int) { requestsUsed() }

    var dayRequestsFraction: Double {
        let r = dayRequests
        return Double(r.used) / Double(max(r.limit, 1))
    }

    /// O limite mais perto de acabar (é ele que dispara o aviso na Home).
    /// `name` diz qual limite: "day", "hour" ou "requests".
    var tightest: (fraction: Double, name: String) {
        [(dayAudioFraction, "day"), (hourAudioFraction, "hour"), (dayRequestsFraction, "requests"),
         (cleanupRequestsFraction, "cleanup")]
            .max { $0.0 < $1.0 }
            .map { (min($0.0, 1), $0.1) } ?? (0, "")
    }

    mutating func recordCleanup(remaining: Int?, limit: Int?, at now: Date = .now) {
        let cutoff = now.addingTimeInterval(-40 * 86_400)
        cleanups = ((cleanups ?? []) + [now]).filter { $0 >= cutoff }
        if let remaining, let limit {
            cleanupRemaining = remaining
            cleanupLimit = limit
            cleanupHeadersDate = now
        }
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
    /// Saldo dos modelos de texto quando a Groq ainda não informou (o certo vem nos cabeçalhos da resposta).
    static let cleanupRequestsPerDay = 1_000
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
