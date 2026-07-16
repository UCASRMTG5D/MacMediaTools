import Foundation

/// 安全范围书签存储服务
/// 用于存储和解析安全范围书签数据，以便在沙盒环境中访问用户选择的目录
actor SecurityBookmarkStore {
    static let shared = SecurityBookmarkStore()
    private init() {}
    
    /// 保存URL的安全范围书签数据到UserDefaults
    /// - Parameters:
    ///   - url: 要存储书签的URL
    ///   - key: 在UserDefaults中的键
    func saveBookmark(for url: URL, key: String) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: key)
        } catch {
            print("Failed to create bookmark for URL \(url): \(error)")
        }
    }
    
    /// 从UserDefaults解析安全范围书签数据
    /// - Parameter key: 在UserDefaults中的键
    /// - Returns: 解析后的URL，如果书签数据无效或丢失则返回nil
    func resolveBookmark(key: String) -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            if isStale {
                // 书签已过期，返回nil以触发重新选择
                return nil
            }
            return url
        } catch {
            print("Failed to resolve bookmark for key \(key): \(error)")
            return nil
        }
    }
    
    /// 开始访问安全范围资源
    /// - Parameter URL: 要访问的URL
    /// - Returns: 如果成功开始访问则返回true
    nonisolated func startAccessing(_ url: URL) -> Bool {
        return url.startAccessingSecurityScopedResource()
    }
    
    /// 停止访问安全范围资源
    /// - Parameter URL: 要停止访问的URL
    nonisolated func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}