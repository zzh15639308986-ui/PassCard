import Foundation

/// Raw values match the `type` strings emitted by the recognition backend.
enum PassType: String, Codable, CaseIterable, Equatable, Hashable {
    case pickupFood = "pickup_food"
    case pickupParcel = "pickup_parcel"
    case train
    case flight
    case movie
    case show
    case ride
    case voucher
    case subscription
    case unknown

    var label: String {
        switch self {
        case .pickupFood: return "取餐码"
        case .pickupParcel: return "取件码"
        case .train: return "火车票"
        case .flight: return "机票"
        case .movie: return "电影票"
        case .show: return "演出票"
        case .ride: return "打车"
        case .voucher: return "兑换券"
        case .subscription: return "订阅"
        case .unknown: return "未识别"
        }
    }

    var symbolName: String {
        switch self {
        case .pickupFood: return "cup.and.saucer.fill"
        case .pickupParcel: return "shippingbox.fill"
        case .train: return "tram.fill"
        case .flight: return "airplane"
        case .movie: return "film.fill"
        case .show: return "ticket.fill"
        case .ride: return "car.fill"
        case .voucher: return "gift.fill"
        case .subscription: return "arrow.triangle.2.circlepath"
        case .unknown: return "questionmark.square.dashed"
        }
    }

    /// The verb shown on the "mark as done" button, so completing a pass reads
    /// naturally instead of always saying the same word.
    var completionVerb: String {
        switch self {
        case .pickupFood: return "已取餐"
        case .pickupParcel: return "已取件"
        case .train: return "已到达"
        case .flight: return "已落地"
        case .movie, .show: return "已看完"
        case .ride: return "已下车"
        case .voucher: return "已使用"
        case .subscription: return "已退订"
        case .unknown: return "已完成"
        }
    }

    /// Field names whose value is a code worth showing large on the Lock Screen.
    var codeField: String? {
        switch self {
        case .pickupFood, .pickupParcel, .voucher: return "code"
        case .ride: return "plate_no"
        case .train: return "train_no"
        case .flight: return "flight_no"
        default: return nil
        }
    }
}
