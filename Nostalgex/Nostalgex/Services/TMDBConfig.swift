import Foundation

enum TMDBConfig {
    /// Prefer `Info.plist` keys in production builds; fall back to environment for CI/dev.
    /// Keep these empty by default so the app still compiles without secrets.
    static let tmdbAPIKey: String = value(forEnv: "TMDB_API_KEY", infoPlistKey: "TMDBApiKey")
    static let omdbAPIKey: String = value(forEnv: "OMDB_API_KEY", infoPlistKey: "OMDBApiKey")
    static let supabaseURL: String = value(forEnv: "SUPABASE_URL", infoPlistKey: "SupabaseURL")
    static let supabaseAnonKey: String = value(forEnv: "SUPABASE_ANON_KEY", infoPlistKey: "SupabaseAnonKey")

    /// The site's TMDB proxy (`api/tmdb.js`). The App Store build carries no TMDB key;
    /// it asks the proxy, which holds the key as a Vercel env var and caches answers at
    /// the edge. A build with `tmdbAPIKey` set (dev) talks to TMDB directly instead.
    static let tmdbProxyURL = "https://www.nostalgex.app/api/tmdb"

    private static func value(forEnv envKey: String, infoPlistKey: String) -> String {
        if let v = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String, !v.isEmpty {
            return v
        }
        if let v = ProcessInfo.processInfo.environment[envKey], !v.isEmpty {
            return v
        }
        return ""
    }
}
