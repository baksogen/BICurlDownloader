//
//  BINetworkMonitor.swift
//  BICurlDownloader
//
//  Created by BiOM on 11.09.2025.
//

import Foundation
import Network
import SystemConfiguration

/// Мониторинг состояния сети
@available(iOS 12.0, *)
class BINetworkMonitor: ObservableObject {
    
    // MARK: - Properties
    
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.bi.curldownloader.networkmonitor")
    
    @Published var isConnected = false
    @Published var connectionType: ConnectionType = .unknown
    @Published var isExpensive = false
    @Published var isConstrained = false
    
    private let logger = BILogger.shared
    
    // MARK: - Types
    
    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case other
        case unknown
    }
    
    // MARK: - Initialization
    
    init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Запуск мониторинга сети
    func startMonitoring() {
        logger.info("Starting network monitoring")
        
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateNetworkStatus(path: path)
            }
        }
        
        monitor.start(queue: monitorQueue)
    }
    
    /// Остановка мониторинга сети
    func stopMonitoring() {
        logger.info("Stopping network monitoring")
        monitor.cancel()
    }
    
    /// Получение текущего состояния сети
    var currentNetworkStatus: NetworkStatus {
        return NetworkStatus(
            isConnected: isConnected,
            connectionType: connectionType,
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
    }
    
    /// Проверка, подходит ли текущее соединение для загрузки
    func isConnectionSuitableForDownload(allowCellular: Bool = true, allowExpensive: Bool = false) -> Bool {
        guard isConnected else {
            logger.warning("No network connection available")
            return false
        }
        
        // Проверяем тип соединения
        if connectionType == .cellular && !allowCellular {
            logger.info("Cellular connection not allowed for download")
            return false
        }
        
        // Проверяем, является ли соединение дорогим
        if isExpensive && !allowExpensive {
            logger.info("Expensive connection not allowed for download")
            return false
        }
        
        // Проверяем, является ли соединение ограниченным
        if isConstrained {
            logger.warning("Constrained connection detected")
        }
        
        return true
    }
    
    /// Получение рекомендуемого количества одновременных загрузок для текущего соединения
    func getRecommendedConcurrentDownloads() -> Int {
        guard isConnected else { return 0 }
        
        switch connectionType {
        case .wifi:
            return isConstrained ? 2 : 4
        case .cellular:
            return isExpensive ? 1 : 2
        case .ethernet:
            return 6
        case .other:
            return 2
        case .unknown:
            return 1
        }
    }
    
    /// Получение рекомендуемого размера буфера для текущего соединения
    func getRecommendedBufferSize() -> Int {
        guard isConnected else { return 1024 }
        
        switch connectionType {
        case .wifi:
            return isConstrained ? 4096 : 8192
        case .cellular:
            return isExpensive ? 1024 : 2048
        case .ethernet:
            return 16384
        case .other:
            return 2048
        case .unknown:
            return 1024
        }
    }
    
    // MARK: - Private Methods
    
    private func updateNetworkStatus(path: NWPath) {
        let wasConnected = isConnected
        let previousType = connectionType
        
        // Обновляем состояние подключения
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        
        // Определяем тип подключения
        connectionType = determineConnectionType(path: path)
        
        // Логируем изменения
        if wasConnected != isConnected {
            logger.info("Network connection changed: \(isConnected ? "connected" : "disconnected")")
        }
        
        if previousType != connectionType {
            logger.info("Connection type changed: \(connectionType)")
        }
        
        if isExpensive {
            logger.warning("Network connection is expensive")
        }
        
        if isConstrained {
            logger.warning("Network connection is constrained")
        }
        
        // Отправляем уведомление об изменении сети
        NotificationCenter.default.safeSend(
            name: .networkStatusChanged,
            object: self,
            userInfo: ["status": currentNetworkStatus]
        )
    }
    
    private func determineConnectionType(path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else if path.usesInterfaceType(.other) {
            return .other
        } else {
            return .unknown
        }
    }
}

// MARK: - NetworkStatus

/// Структура для представления состояния сети
struct NetworkStatus {
    let isConnected: Bool
    let connectionType: BINetworkMonitor.ConnectionType
    let isExpensive: Bool
    let isConstrained: Bool
    
    var description: String {
        var components = [String]()
        
        if isConnected {
            components.append("connected")
            components.append("type: \(connectionType)")
            
            if isExpensive {
                components.append("expensive")
            }
            
            if isConstrained {
                components.append("constrained")
            }
        } else {
            components.append("disconnected")
        }
        
        return components.joined(separator: ", ")
    }
}

// MARK: - BINetworkMonitor для iOS < 12

/// Упрощенный мониторинг сети для старых версий iOS
class BILegacyNetworkMonitor {
    
    // MARK: - Properties
    
    private var reachability: SCNetworkReachability?
    private let logger = BILogger.shared
    
    @Published var isConnected = false
    @Published var connectionType: ConnectionType = .unknown
    
    enum ConnectionType {
        case wifi
        case cellular
        case unknown
    }
    
    // MARK: - Initialization
    
    init() {
        setupReachability()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        logger.info("Starting legacy network monitoring")
        // Реализация для SCNetworkReachability
    }
    
    func stopMonitoring() {
        logger.info("Stopping legacy network monitoring")
        if let reachability = reachability {
            SCNetworkReachabilitySetCallback(reachability, nil, nil)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupReachability() {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        
        reachability = withUnsafePointer(to: &address) { pointer in
            return pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                return SCNetworkReachabilityCreateWithAddress(nil, addr)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let networkStatusChanged = Notification.Name("BINetworkStatusChanged")
}

// MARK: - Factory

/// Фабрика для создания подходящего монитора сети в зависимости от версии iOS
class BINetworkMonitorFactory {
    
    static func createNetworkMonitor() -> AnyObject {
        if #available(iOS 12.0, *) {
            return BINetworkMonitor()
        } else {
            return BILegacyNetworkMonitor()
        }
    }
}
