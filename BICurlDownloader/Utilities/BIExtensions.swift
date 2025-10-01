//
//  BIExtensions.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation

// MARK: - NotificationCenter Extension

extension NotificationCenter {
    /// Безопасная отправка уведомлений (не выбрасывает исключения)
    func safeSend(name: NSNotification.Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        DispatchQueue.main.async {
            self.post(name: name, object: object, userInfo: userInfo)
        }
    }
}

// MARK: - String Extension

extension String {
    /// Безопасное извлечение подстроки
    func safeSubstring(from: Int, length: Int) -> String {
        guard from >= 0, from < self.count else { return "" }
        let startIndex = self.index(self.startIndex, offsetBy: from)
        let endIndex = self.index(startIndex, offsetBy: min(length, self.count - from))
        return String(self[startIndex..<endIndex])
    }
}

// MARK: - Data Extension

extension Data {
    /// Конвертация в hex string
    func hexString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: - URL Extension

extension URL {
    /// Получение размера файла
    var fileSize: Int64? {
        let values = try? resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map { Int64($0) }
    }
    
    /// Проверка существования файла
    var fileExists: Bool {
        return FileManager.default.fileExists(atPath: path)
    }
}

// MARK: - Int64 Extension

extension Int64 {
    /// Форматирование размера файла в читаемый формат
    var formattedByteSize: String {
        return ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

// MARK: - Double Extension

extension Double {
    /// Форматирование progress в проценты
    var percentString: String {
        return String(format: "%.1f%%", self * 100)
    }
}

// MARK: - cURL Constants

/// Константы для аутентификации cURL (из curl.h)
let CURLAUTH_BASIC: Int = 1 << 0    // 1
let CURLAUTH_DIGEST: Int = 1 << 1   // 2
