import Foundation

/// App-side configuration. The widget extension needs none of this: everything
/// it draws arrives inside the activity payload.
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let serverURLKey = "server.baseURL"

    var serverURLString: String {
        get { defaults.string(forKey: serverURLKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                           forKey: serverURLKey) }
    }

    var serverURL: URL? {
        guard !serverURLString.isEmpty,
              let url = URL(string: serverURLString),
              url.scheme != nil,
              url.host != nil
        else { return nil }
        return url
    }

    /// The iPhone cannot reach a laptop's `127.0.0.1`, so the blank state names
    /// the LAN address the user actually needs.
    var serverURLDisplay: String {
        serverURLString.isEmpty ? "未设置" : serverURLString
    }

    private init() {}
}
