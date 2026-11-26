import Foundation
import SwiftUI

struct PassPresentation: Equatable {
    var title: String
    var primary: String
    var secondary: String
    /// Set when the pass refers to a moment that has not happened yet; the
    /// Dynamic Island turns it into a live countdown.
    var countdownEnd: Date?
    var countdownLabel: String?

    static let empty = PassPresentation(title: "凭证", primary: "—", secondary: "", countdownEnd: nil, countdownLabel: nil)
}

extension PassType {
    var tint: Color {
        switch self {
        case .pickupFood: return .orange
        case .pickupParcel: return .brown
        case .train: return .blue
        case .flight: return .indigo
        case .movie: return .red
        case .show: return .pink
        case .ride: return .green
        case .voucher: return .purple
        case .subscription: return .teal
        case .unknown: return .gray
        }
    }
}

enum PassFormatter {
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func dateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }

    /// Same day collapses to just the clock time, which is all that fits on the
    /// Lock Screen row.
    static func shortDate(_ date: Date, now: Date = Date()) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return timeFormatter.string(from: date)
        }
        return dateTime(date)
    }

    static func price(_ value: Double, currency: String?) -> String {
        guard let text = priceFormatter.string(from: NSNumber(value: value)) else {
            return String(value)
        }
        let symbol = (currency == nil || currency?.isEmpty == true) ? "¥" : currency!
        return "\(symbol)\(text)"
    }
}

extension Pass {
    var presentation: PassPresentation {
        let f = fields
        switch type {
        case .pickupFood:
            return PassPresentation(
                title: f.text("store") ?? "取餐",
                primary: f.text("code") ?? "—",
                secondary: compact([
                    f.text("order_no").map { "单号 \($0)" },
                    f.date("pickup_by").map { "\(PassFormatter.shortDate($0)) 前取" },
                    f.text("location"),
                ]),
                countdownEnd: futureDate(f.date("pickup_by")),
                countdownLabel: countdownLabel(for: f.date("pickup_by"), verb: "取餐"))

        case .pickupParcel:
            return PassPresentation(
                title: f.text("station") ?? f.text("carrier") ?? "快递",
                primary: f.text("code") ?? "—",
                secondary: compact([
                    f.text("carrier"),
                    f.date("expires_at").map { "\(PassFormatter.shortDate($0)) 到期" },
                ]),
                countdownEnd: futureDate(f.date("expires_at")),
                countdownLabel: countdownLabel(for: f.date("expires_at"), verb: "到期"))

        case .train:
            return PassPresentation(
                title: route(from: f.text("from_station"), to: f.text("to_station"), fallback: "火车行程"),
                primary: f.text("train_no") ?? "—",
                secondary: compact([
                    unit(f.text("carriage"), "车"),
                    f.text("seat"),
                    f.text("seat_class"),
                    f.date("depart_at").map { PassFormatter.shortDate($0) },
                    f.text("gate").map { withSuffix($0, "检票口") },
                ]),
                countdownEnd: futureDate(f.date("depart_at")),
                countdownLabel: countdownLabel(for: f.date("depart_at"), verb: "发车"))

        case .flight:
            return PassPresentation(
                title: route(from: f.text("from_airport"), to: f.text("to_airport"), fallback: "航班"),
                primary: f.text("flight_no") ?? "—",
                secondary: compact([
                    f.date("depart_at").map { PassFormatter.shortDate($0) },
                    f.text("terminal_from").map { "T\($0)" },
                    f.text("gate").map { "\($0)登机口" },
                    f.text("seat"),
                ]),
                countdownEnd: futureDate(f.firstDate("boarding_time", "depart_at")),
                countdownLabel: countdownLabel(for: f.firstDate("boarding_time", "depart_at"), verb: "登机"))

        case .movie, .show:
            let venue = type == .movie
                ? f.firstText("cinema", "venue")
                : f.firstText("venue", "cinema")
            return PassPresentation(
                title: f.text("title") ?? type.label,
                primary: venue ?? "—",
                secondary: compact([
                    f.date("start_at").map { PassFormatter.shortDate($0) },
                    unit(f.text("screen"), "厅"),
                    f.text("seat"),
                    f.text("language"),
                    f.text("version"),
                ]),
                countdownEnd: futureDate(f.date("start_at")),
                countdownLabel: countdownLabel(for: f.date("start_at"), verb: "开场"))

        case .ride:
            return PassPresentation(
                title: f.text("destination") ?? f.text("pickup_point") ?? "行程",
                primary: f.text("plate_no") ?? "—",
                secondary: compact([
                    f.text("platform"),
                    f.text("vehicle_color"),
                    f.text("vehicle"),
                    f.date("ride_at").map { PassFormatter.shortDate($0) },
                ]),
                countdownEnd: futureDate(f.date("ride_at")),
                countdownLabel: countdownLabel(for: f.date("ride_at"), verb: "上车"))

        case .voucher:
            return PassPresentation(
                title: f.text("merchant") ?? "兑换券",
                primary: f.text("code") ?? "—",
                secondary: compact([
                    f.text("value"),
                    f.date("expires_at").map { "\(PassFormatter.shortDate($0)) 到期" },
                    f.text("terms"),
                ]),
                countdownEnd: futureDate(f.date("expires_at")),
                countdownLabel: countdownLabel(for: f.date("expires_at"), verb: "到期"))

        case .subscription:
            let amount = f.number("price").map { PassFormatter.price($0, currency: f.text("currency")) }
            return PassPresentation(
                title: f.text("service") ?? "订阅",
                primary: amount ?? f.text("cycle") ?? "—",
                secondary: compact([
                    amount == nil ? nil : cycleLabel(f.text("cycle")),
                    f.date("next_charge_at").map { "\(PassFormatter.shortDate($0)) 扣款" },
                    f.text("status").map { subscriptionStatusLabel($0) },
                ]),
                countdownEnd: futureDate(f.date("next_charge_at")),
                countdownLabel: countdownLabel(for: f.date("next_charge_at"), verb: "扣款"))

        case .unknown:
            return PassPresentation(
                title: "未识别的凭证",
                primary: f.text("code") ?? f.text("notes") ?? "—",
                secondary: f.text("location") ?? "",
                countdownEnd: nil,
                countdownLabel: nil)
        }
    }

    private func route(from: String?, to: String?, fallback: String) -> String {
        switch (from, to) {
        case (let origin?, let destination?): return "\(origin) → \(destination)"
        case (let origin?, nil): return origin
        case (nil, let destination?): return destination
        default: return fallback
        }
    }

    private func compact(_ parts: [String?]) -> String {
        let kept = parts.compactMap { $0 }.filter { !$0.isEmpty }
        return kept.prefix(3).joined(separator: " · ")
    }

    /// The extractor may already have spelled the unit out ("07车"), so only
    /// append it to a bare number.
    private func unit(_ value: String?, _ suffix: String) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let digitsOnly = value.allSatisfy { $0.isNumber }
        return digitsOnly ? "\(value)\(suffix)" : value
    }

    private func withSuffix(_ value: String, _ suffix: String) -> String {
        value.hasSuffix(suffix) ? value : "\(value)\(suffix)"
    }

    /// A countdown only makes sense for a moment still ahead; rendering one for
    /// a past date would show a negative timer on the Lock Screen.
    private func futureDate(_ date: Date?, now: Date = Date()) -> Date? {
        guard let date, date > now else { return nil }
        return date
    }

    private func countdownLabel(for date: Date?, verb: String, now: Date = Date()) -> String? {
        guard let date, date > now else { return nil }
        return verb
    }

    private func cycleLabel(_ raw: String?) -> String? {
        switch raw {
        case "monthly": return "每月"
        case "quarterly": return "每季"
        case "yearly": return "每年"
        case "weekly": return "每周"
        case "one_time": return "一次性"
        default: return nil
        }
    }

    private func subscriptionStatusLabel(_ raw: String) -> String {
        switch raw {
        case "active": return "生效中"
        case "cancelled": return "已取消"
        case "trial": return "试用中"
        case "expired": return "已过期"
        default: return raw
        }
    }
}

extension PassActivityAttributes.ContentState {
    init(_ pass: Pass, now: Date = Date()) {
        let presentation = pass.presentation
        self.init(
            title: presentation.title,
            primary: presentation.primary,
            secondary: presentation.secondary,
            symbolName: pass.type.symbolName,
            countdownVerb: presentation.countdownLabel,
            countdownStart: presentation.countdownEnd == nil ? nil : now,
            countdownEnd: presentation.countdownEnd)
    }
}
