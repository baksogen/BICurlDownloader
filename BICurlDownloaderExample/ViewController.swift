//
//  ViewController.swift
//  BICurlDownloaderExample
//
//  Created by BiOM on 11.09.2025.
//

import UIKit
import BICurlDownloader

class ViewController: UIViewController {
    
    // MARK: - UI Elements
    
    @IBOutlet weak var urlTextField: UITextField!
    @IBOutlet weak var downloadButton: UIButton!
    @IBOutlet weak var pauseButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var speedLabel: UILabel!
    @IBOutlet weak var backgroundAudioSwitch: UISwitch!
    @IBOutlet weak var multipartSwitch: UISwitch!
    @IBOutlet weak var logTextView: UITextView!
    
    // MARK: - Properties
    
    private var currentDownloadTask: BIDownloadTask?
    private var downloadManager: BIDownloadManager {
        return BIDownloadManager.shared
    }
    
    private var lastProgressUpdate = Date()
    private var lastBytesDownloaded: Int64 = 0
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureDownloadManager()
        logMessage("BICurlDownloader Example App Started")
        logMessage("Framework Version: \(BICurlDownloaderInfo.fullVersion)")
        logMessage("Supported Features: \(BICurlDownloaderInfo.supportedFeatures.joined(separator: ", "))")
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        title = "BICurlDownloader Example"
        
        // Настройка UI элементов
        urlTextField.text = "https://examplefiles.org/files/video/mp4-example-video-download-4k-uhd-3840x2160.mp4"
        urlTextField.text = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_30MB.mp4"
        urlTextField.placeholder = "Enter download URL..."
        
        downloadButton.setTitle("Download", for: .normal)
        pauseButton.setTitle("Pause", for: .normal)
        cancelButton.setTitle("Cancel", for: .normal)
        
        pauseButton.isEnabled = false
        cancelButton.isEnabled = false
        
        progressView.progress = 0.0
        statusLabel.text = "Ready to download"
        speedLabel.text = ""
        
        backgroundAudioSwitch.isOn = true
        multipartSwitch.isOn = true
        
        // Настройка лог textView
        logTextView.isEditable = false
        logTextView.text = ""
        logTextView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.backgroundColor = UIColor.systemGray6
    }
    
    private func configureDownloadManager() {
        let config = BIDownloadManagerConfiguration(
            enableLogging: true,
            logLevel: .info,
            maxConcurrentDownloads: 5
        )
        
        downloadManager.configure(config)
        
        logMessage("Download Manager Configured")
        logMessage("Max Concurrent Downloads: \(config.maxConcurrentDownloads)")
    }
    
    // MARK: - Actions
    
    @IBAction func downloadButtonTapped(_ sender: UIButton) {
        guard let urlString = urlTextField.text, !urlString.isEmpty else {
            showAlert(title: "Error", message: "Please enter a valid URL")
            return
        }
        
        guard let url = URL(string: urlString) else {
            showAlert(title: "Error", message: "Invalid URL format")
            return
        }
        
        // Создаем путь для сохранения файла
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = url.lastPathComponent.isEmpty ? "downloaded_file" : url.lastPathComponent
        let destinationPath = documentsPath.appendingPathComponent(fileName).path
        
        // Настраиваем опции загрузки
        let options = BIDownloadOptions(
            enableBackgroundAudio: backgroundAudioSwitch.isOn,
            enableMultipart: multipartSwitch.isOn,
            timeoutInterval: 60
        )
        options.maxConcurrentStreams = 5
        options.userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
        
        // Запускаем загрузку
        currentDownloadTask = downloadManager.download(
            url: url,
            destinationPath: destinationPath,
            options: options
        )
        
        currentDownloadTask?.delegate = self
        
        // Обновляем UI
        downloadButton.isEnabled = false
        pauseButton.isEnabled = true
        cancelButton.isEnabled = true
        
        logMessage("Started download: \(urlString)")
        logMessage("Destination: \(destinationPath)")
        logMessage("Background Audio: \(options.enableBackgroundAudio)")
        logMessage("Multipart: \(options.enableMultipart)")
    }
    
    @IBAction func pauseButtonTapped(_ sender: UIButton) {
        guard let task = currentDownloadTask else { return }
        
        switch task.state {
        case .downloading:
            task.pause()
            pauseButton.setTitle("Resume", for: .normal)
            logMessage("Download paused")
            
        case .paused:
            task.resume()
            pauseButton.setTitle("Pause", for: .normal)
            logMessage("Download resumed")
            
        default:
            break
        }
    }
    
    @IBAction func cancelButtonTapped(_ sender: UIButton) {
        currentDownloadTask?.cancel()
        resetUI()
        logMessage("Download cancelled")
    }
    
    @IBAction func clearLogsButtonTapped(_ sender: UIButton) {
        logTextView.text = ""
    }
    
    @IBAction func testMultipleDownloadsButtonTapped(_ sender: UIButton) {
        let testUrls = [
            "https://sample-videos.com/zip/10/mp4/SampleVideo_1280x720_1mb.mp4",
            "https://www.learningcontainer.com/wp-content/uploads/2020/05/sample-mp4-file.mp4",
            "https://file-examples.com/storage/fe68c1f7d2b60fa2944e90d/2017/10/file_example_JPG_100kB.jpg"
        ]
        
        for (index, urlString) in testUrls.enumerated() {
            guard let url = URL(string: urlString) else { continue }
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileName = "test_file_\(index)_\(url.lastPathComponent)"
            let destinationPath = documentsPath.appendingPathComponent(fileName).path
            
            let task = downloadManager.download(url: url, destinationPath: destinationPath)
            task.delegate = self
            
            logMessage("Started test download \(index + 1): \(url.lastPathComponent)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func resetUI() {
        downloadButton.isEnabled = true
        pauseButton.isEnabled = false
        pauseButton.setTitle("Pause", for: .normal)
        cancelButton.isEnabled = false
        
        progressView.progress = 0.0
        statusLabel.text = "Ready to download"
        speedLabel.text = ""
        
        currentDownloadTask = nil
        lastBytesDownloaded = 0
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func logMessage(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)\n"
        
        DispatchQueue.main.async { [weak self] in
            self?.logTextView.text += logEntry
            
            // Автоматически прокручиваем к концу
            let bottom = NSMakeRange(self?.logTextView.text.count ?? 0, 0)
            self?.logTextView.scrollRangeToVisible(bottom)
        }
    }
    
    private func updateDownloadSpeed(bytesDownloaded: Int64) {
        let now = Date()
        let timeDiff = now.timeIntervalSince(lastProgressUpdate)
        
        if timeDiff >= 1.0 { // Обновляем скорость каждую секунду
            let bytesDiff = bytesDownloaded - lastBytesDownloaded
            let speed = Double(bytesDiff) / timeDiff
            
            let speedString = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file)
            speedLabel.text = "\(speedString)/s"
            
            lastProgressUpdate = now
            lastBytesDownloaded = bytesDownloaded
        }
    }
}

// MARK: - BIDownloadDelegate

extension ViewController: BIDownloadDelegate {
    
    func downloadDidStart(_ task: BIDownloadTask) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = "Downloading..."
            self?.logMessage("Download started for task: \(task.id)")
        }
    }
    
    func downloadDidProgress(_ task: BIDownloadTask, progress: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.progressView.progress = Float(progress)
            
            let percentage = Int(progress * 100)
            self?.statusLabel.text = "Downloading... \(percentage)%"
            
            // Обновляем скорость загрузки
            let bytesDownloaded = task.progress.completedUnitCount
            self?.updateDownloadSpeed(bytesDownloaded: bytesDownloaded)
        }
    }
    
    func downloadDidComplete(_ task: BIDownloadTask, filePath: String) {
        DispatchQueue.main.async { [weak self] in
            self?.progressView.progress = 1.0
            self?.statusLabel.text = "Download completed!"
            self?.speedLabel.text = ""
            
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? Int64) ?? 0
            let sizeString = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            
            self?.logMessage("Download completed successfully")
            self?.logMessage("File saved to: \(filePath)")
            self?.logMessage("File size: \(sizeString)")
            
            self?.showAlert(title: "Success", message: "File downloaded successfully!\nSize: \(sizeString)")
            
            // Сбрасываем UI через 2 секунды
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.resetUI()
            }
        }
    }
    
    func downloadDidFail(_ task: BIDownloadTask, error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = "Download failed"
            self?.speedLabel.text = ""
            
            let errorMessage = error.localizedDescription
            self?.logMessage("Download failed: \(errorMessage)")
            
            self?.showAlert(title: "Download Failed", message: errorMessage)
            
            self?.resetUI()
        }
    }
}

// MARK: - Quick Download Example

extension ViewController {
    
    @IBAction func quickDownloadButtonTapped(_ sender: UIButton) {
        // Массив тестовых URL для проверки
        let testUrls = [
            "https://cdn.dribbble.com/users/5031/screenshots/3713646/attachments/832536/wallpaper_mikael_gustafsson.png",
            "https://toptreki.com/uploads/files/2025-09/1758737659_8p4s-n-vdn.mp3",
            "https://images.unsplash.com/photo-1485470733090-0aae1788d5af?fm=jpg&q=60&w=3000&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8M3x8d2FsbHBhcGVyJTIwNGt8ZW58MHx8MHx8fDA%3D",
            "https://www.win-rar.com/fileadmin/winrar-versions/rarmacos-x64-712.tar.gz"
        ]
        
        // Используем первый URL для теста
        let testUrl = testUrls[0]
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationPath = documentsPath.appendingPathComponent("quick_download.jpg").path
        
        logMessage("Starting quick download...")
        
        // Запускаем диагностику перед загрузкой
        guard let url = URL(string: testUrl) else {
            logMessage("Invalid URL: \(testUrl)")
            return
        }
        
        let _ = downloadManager.quickDownload(
            from: testUrl,
            to: destinationPath
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let filePath):
                    self?.logMessage("Quick download completed: \(filePath)")
                    self?.showAlert(title: "Quick Download", message: "File downloaded successfully!")
                    
                case .failure(let error):
                    self?.logMessage("Quick download failed: \(error.localizedDescription)")
                    self?.showAlert(title: "Quick Download Failed", message: error.localizedDescription)
                }
            }
        }
    }
}
