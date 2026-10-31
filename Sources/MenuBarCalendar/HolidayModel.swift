import Foundation
import SwiftUI

enum HolidayKind: String, Codable {
    case holiday
    case work
}

struct HolidayInfo: Codable, Hashable {
    let kind: HolidayKind
    let name: String
}

@MainActor
final class HolidayModel: ObservableObject {
    @Published private(set) var holidayInfo: [Date: HolidayInfo] = [:]

    private static let cacheKey = "holiday-cache-v1"
    private var refreshTask: Task<Void, Never>?

    init() {
        loadCache()
    }

    deinit {
        refreshTask?.cancel()
    }

    func refreshIfNeeded(for date: Date) async {
        if refreshTask != nil {
            await refreshTask?.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefreshIfNeeded(for: date)
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefreshIfNeeded(for date: Date) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: today)

        guard let cache = Self.loadCache() else {
            await refresh(year: year, for: today)
            return
        }

        if cache.year != year {
            await refresh(year: year, for: today)
            return
        }

        if let maxDate = cache.maxDate, maxDate >= today {
            return
        }

        if let lastRefreshDate = cache.lastRefreshDate,
           calendar.isDate(lastRefreshDate, inSameDayAs: today) {
            return
        }

        await refresh(year: year, for: today)
    }

    private func refresh(year: Int, for today: Date) async {
        do {
            let entries = try await Self.fetchHolidays(year: year)
            var items: [String: HolidayInfo] = [:]
            var maxDate: Date?

            for entry in entries {
                items[Self.dayKey(for: entry.date)] = entry.info
                if maxDate == nil || entry.date > maxDate! {
                    maxDate = entry.date
                }
            }

            let cache = HolidayCache(
                year: year,
                lastRefreshDate: today,
                maxDate: maxDate,
                items: items
            )
            Self.saveCache(cache)
            loadCache()
        } catch {
            // 失败时静默降级：
            // - 同年失败：保留已有缓存，下次启动重试
            // - 跨年失败：清空旧年数据，下次启动重试
            let currentCache = Self.loadCache()
            if currentCache?.year != year {
                let cache = HolidayCache(
                    year: year,
                    lastRefreshDate: nil,
                    maxDate: nil,
                    items: [:]
                )
                Self.saveCache(cache)
                loadCache()
            }
        }
    }

    private func loadCache() {
        guard let cache = Self.loadCache() else {
            holidayInfo = [:]
            return
        }

        var result: [Date: HolidayInfo] = [:]
        for (dayKey, info) in cache.items {
            if let date = Self.date(fromDayKey: dayKey) {
                result[date] = info
            }
        }
        holidayInfo = result
    }

    private struct HolidayCache: Codable {
        let year: Int
        let lastRefreshDate: Date?
        let maxDate: Date?
        let items: [String: HolidayInfo]
    }

    private struct APIResponse: Decodable {
        let code: Int?
        let holiday: [String: APIEntry]?
    }

    private struct APIEntry: Decodable {
        let holiday: Bool?
        let name: String?
        let after: Bool?
        let target: String?
        let wage: Int?
        let date: String?
        let rest: Int?
    }

    private struct FetchedEntry {
        let date: Date
        let info: HolidayInfo
    }

    private static func fetchHolidays(year: Int) async throws -> [FetchedEntry] {
        var request = URLRequest(url: URL(string: "https://timor.tech/api/holiday/year/\(year)")!)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let result = try JSONDecoder().decode(APIResponse.self, from: data)
        guard result.code == 0 else {
            throw URLError(.badServerResponse)
        }

        var entries: [FetchedEntry] = []
        for (key, entry) in result.holiday ?? [:] {
            guard let isHoliday = entry.holiday, let name = entry.name else { continue }

            let dateString = entry.date ?? "\(year)-\(key)"
            guard let date = date(fromDateString: dateString) else { continue }

            entries.append(
                FetchedEntry(
                    date: date,
                    info: HolidayInfo(
                        kind: isHoliday ? .holiday : .work,
                        name: name
                    )
                )
            )
        }

        return entries
    }

    private static func date(fromDateString value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func date(fromDayKey value: String) -> Date? {
        date(fromDateString: value)
    }

    private static func loadCache() -> HolidayCache? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HolidayCache.self, from: data)
    }

    private static func saveCache(_ cache: HolidayCache) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}
