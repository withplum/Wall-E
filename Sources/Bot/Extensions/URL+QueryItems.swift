import Foundation

extension URL {
    func addingQueryItems(_ queryItems: [URLQueryItem]) -> URL {
        guard queryItems.isEmpty == false else { return self }
        
        var components = URLComponents(url: self, resolvingAgainstBaseURL: true)!
        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url!
    }
}
