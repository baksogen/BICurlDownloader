//
//  BIFileManager.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation

/// File manager for working with downloaded files
class BIFileManager {
    
    // MARK: - Singleton
    
    static let shared = BIFileManager()
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    private let logger = BILogger.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Get directory for temporary files
    func getTempDirectory() -> String {
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("BICurlDownloader")
        
        // Create directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            logger.warning("Failed to create temp directory: \(error)")
        }
        
        return tempDir.path
    }
    
    /// Get cache directory
    func getCacheDirectory() -> String {
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BICurlDownloader")
        
        // Создаем директорию если она не существует
        do {
            try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            logger.warning("Failed to create cache directory: \(error)")
        }
        
        return cacheDir.path
    }
    
    /// Check available disk space
    func getAvailableDiskSpace() -> Int64 {
        do {
            let resourceValues = try fileManager.url(for: .documentDirectory,
                                                   in: .userDomainMask,
                                                   appropriateFor: nil,
                                                   create: false).resourceValues(forKeys: [.volumeAvailableCapacityKey])
            
            if let availableBytes = resourceValues.volumeAvailableCapacity {
                return Int64(availableBytes)
            }
        } catch {
            logger.error("Failed to get available disk space: \(error)")
        }
        
        return 0
    }
    
    /// Check if there is enough space for file download
    func hasEnoughSpace(for fileSize: Int64) -> Bool {
        let availableSpace = getAvailableDiskSpace()
        let requiredSpace = fileSize + (100 * 1024 * 1024) // +100MB buffer
        
        let hasSpace = availableSpace >= requiredSpace
        
        logger.info("Available space: \(availableSpace) bytes, required: \(requiredSpace) bytes, sufficient: \(hasSpace)")
        
        return hasSpace
    }
    
    /// Создание директории по пути
    func createDirectory(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        logger.verbose("Created directory: \(path)")
    }
    
    /// Удаление файла
    func removeFile(at path: String) throws {
        guard fileManager.fileExists(atPath: path) else {
            logger.verbose("File does not exist, nothing to remove: \(path)")
            return
        }
        
        try fileManager.removeItem(atPath: path)
        logger.verbose("Removed file: \(path)")
    }
    
    /// Перемещение файла
    func moveFile(from sourcePath: String, to destinationPath: String) throws {
        // Создаем директорию назначения если необходимо
        let destinationURL = URL(fileURLWithPath: destinationPath)
        let destinationDir = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        
        // Удаляем файл назначения если он существует
        if fileManager.fileExists(atPath: destinationPath) {
            try fileManager.removeItem(atPath: destinationPath)
        }
        
        // Перемещаем файл
        try fileManager.moveItem(atPath: sourcePath, toPath: destinationPath)
        logger.verbose("Moved file from \(sourcePath) to \(destinationPath)")
    }
    
    /// Копирование файла
    func copyFile(from sourcePath: String, to destinationPath: String) throws {
        // Создаем директорию назначения если необходимо
        let destinationURL = URL(fileURLWithPath: destinationPath)
        let destinationDir = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        
        // Удаляем файл назначения если он существует
        if fileManager.fileExists(atPath: destinationPath) {
            try fileManager.removeItem(atPath: destinationPath)
        }
        
        // Копируем файл
        try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
        logger.verbose("Copied file from \(sourcePath) to \(destinationPath)")
    }
    
    /// Получение размера файла
    func getFileSize(at path: String) -> Int64? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            return attributes[.size] as? Int64
        } catch {
            logger.warning("Failed to get file size for \(path): \(error)")
            return nil
        }
    }
    
    /// Проверка доступности директории для записи
    func checkDirectoryAccess(at path: String) -> (exists: Bool, writable: Bool, error: String?) {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        let directoryPath = directory.path
        
        // Проверяем существование директории
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directoryPath, isDirectory: &isDirectory)
        
        if !exists {
            // Пытаемся создать директорию
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                logger.info("Created directory: \(directoryPath)")
            } catch {
                return (false, false, "Failed to create directory: \(error.localizedDescription)")
            }
        } else if !isDirectory.boolValue {
            return (false, false, "Path exists but is not a directory")
        }
        
        // Проверяем права на запись
        let writable = fileManager.isWritableFile(atPath: directoryPath)
        if !writable {
            return (true, false, "No write permission for directory")
        }
        
        // Проверяем доступное место
        let availableSpace = getAvailableDiskSpace()
        if availableSpace < 1024 * 1024 { // Минимум 1 МБ
            return (true, false, "Insufficient disk space (\(availableSpace) bytes available)")
        }
        
        return (true, true, nil)
    }
    
    /// Создание тестового файла для проверки доступа
    func testFileCreation(in directoryPath: String) -> (success: Bool, error: String?) {
        let testFileName = "test_write_\(UUID().uuidString).tmp"
        let testFilePath = "\(directoryPath)/\(testFileName)"
        
        do {
            // Создаем тестовый файл
            let testData = "test".data(using: .utf8)!
            let success = fileManager.createFile(atPath: testFilePath, contents: testData, attributes: [
                .posixPermissions: 0o644
            ])
            
            if !success {
                return (false, "Failed to create test file")
            }
            
            // Проверяем что файл создался
            guard fileManager.fileExists(atPath: testFilePath) else {
                return (false, "Test file was not created")
            }
            
            // Пытаемся открыть для записи
            guard let fileHandle = FileHandle(forWritingAtPath: testFilePath) else {
                try? fileManager.removeItem(atPath: testFilePath)
                return (false, "Failed to open test file for writing")
            }
            
            // Пытаемся записать данные
            fileHandle.write("additional data".data(using: .utf8)!)
            fileHandle.closeFile()
            
            // Удаляем тестовый файл
            try fileManager.removeItem(atPath: testFilePath)
            
            return (true, nil)
            
        } catch {
            return (false, "Test file creation failed: \(error.localizedDescription)")
        }
    }
    
    /// Проверка существования файла
    func fileExists(at path: String) -> Bool {
        return fileManager.fileExists(atPath: path)
    }
    
    /// Очистка временных файлов
    func cleanupTempFiles() {
        let tempDir = getTempDirectory()
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: tempDir)
            
            for file in contents {
                let filePath = "\(tempDir)/\(file)"
                try removeFile(at: filePath)
            }
            
            logger.info("Cleaned up \(contents.count) temporary files")
            
        } catch {
            logger.error("Failed to cleanup temp files: \(error)")
        }
    }
    
    /// Очистка старых файлов кэша (старше указанного времени)
    func cleanupOldCacheFiles(olderThan timeInterval: TimeInterval) {
        let cacheDir = getCacheDirectory()
        let cutoffDate = Date().addingTimeInterval(-timeInterval)
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: cacheDir)
            var removedCount = 0
            
            for file in contents {
                let filePath = "\(cacheDir)/\(file)"
                let attributes = try fileManager.attributesOfItem(atPath: filePath)
                
                if let modificationDate = attributes[.modificationDate] as? Date,
                   modificationDate < cutoffDate {
                    try removeFile(at: filePath)
                    removedCount += 1
                }
            }
            
            logger.info("Cleaned up \(removedCount) old cache files")
            
        } catch {
            logger.error("Failed to cleanup old cache files: \(error)")
        }
    }
    
    /// Получение информации о файле
    func getFileInfo(at path: String) -> BIFileInfo? {
        guard fileExists(at: path) else {
            return nil
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            let url = URL(fileURLWithPath: path)
            
            return BIFileInfo(
                path: path,
                name: url.lastPathComponent,
                size: attributes[.size] as? Int64 ?? 0,
                creationDate: attributes[.creationDate] as? Date,
                modificationDate: attributes[.modificationDate] as? Date
            )
            
        } catch {
            logger.error("Failed to get file info for \(path): \(error)")
            return nil
        }
    }
}

// MARK: - BIFileInfo

/// Информация о файле
struct BIFileInfo {
    let path: String
    let name: String
    let size: Int64
    let creationDate: Date?
    let modificationDate: Date?
    
    var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
