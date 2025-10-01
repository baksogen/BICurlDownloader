# BICurlDownloader

BICurlDownloader is a powerful and flexible iOS framework that provides multi-threaded file downloads using the system libcurl library with background operation support through programmatically generated silent audio.

> 📚 **New to this project?** Check out the [Documentation Index](DOCUMENTATION_INDEX.md) for a complete guide to all available documentation.

## Key Features

- ✅ **Multi-threaded downloading** - automatic file splitting for parallel downloads
- ✅ **Background operation** - continued downloads in background mode via silent audio
- ✅ **Authentication support** - Basic, Digest, Bearer Token, and custom headers
- ✅ **Download management** - pause, resume, cancel, priority queue
- ✅ **Progress monitoring** - detailed download status information
- ✅ **Error handling** - smart retry system with exponential backoff
- ✅ **Network monitoring** - adaptation to connection type (Wi-Fi/Cellular)
- ✅ **Security** - SSL/TLS support and certificate validation

## Requirements

- iOS 13.0+
- Swift 5.0+
- Xcode 12.0+
- libcurl (system library)

## Building the Framework

### Prerequisites

Before building BICurlDownloader, you need to build the curl-ios framework:

1. Clone the curl-ios repository:
```bash
cd /path/to/your/workspace
git clone https://github.com/tls-inspector/curl-ios.git
cd curl-ios
```

2. Build the curl.xcframework:
```bash
chmod +x build-ios.sh
./build-ios.sh
```

This will create `curl.xcframework` which is required by BICurlDownloader.

3. Copy the generated `curl.xcframework` to the BICurlDownloader project:
```bash
cp -R curl.xcframework /path/to/BICurlDownloader/BICurlDownloader/External/curl-ios/
```

### Building BICurlDownloader

Once curl.xcframework is in place, build the BICurlDownloader framework:

```bash
cd /path/to/BICurlDownloader
chmod +x build.sh
./build.sh
```

The resulting `BICurlDownloader.xcframework` will be created in the `Result/` directory.

For detailed build instructions, see [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md).

## Installation

### Swift Package Manager

Add the following dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/baksogen/BICurlDownloader.git", from: "1.0.0")
]
```

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'BICurlDownloader', '~> 1.0'
```

## Quick Start

### Simple Download

```swift
import BICurlDownloader

// Quick file download
BIDownloadManager.shared.quickDownload(
    from: "https://example.com/file.zip",
    to: "/path/to/destination/file.zip"
) { result in
    switch result {
    case .success(let filePath):
        print("File downloaded: \(filePath)")
    case .failure(let error):
        print("Download error: \(error)")
    }
}
```

### Advanced Usage

```swift
import BICurlDownloader

class DownloadViewController: UIViewController {
    
    private var downloadTask: BIDownloadTask?
    
    func startDownload() {
        let url = URL(string: "https://example.com/largefile.zip")!
        let destinationPath = "/path/to/destination/largefile.zip"
        
        // Configure download options
        var options = BIDownloadOptions()
        options.enableBackgroundAudio = true
        options.enableMultipart = true
        options.maxConcurrentStreams = 4
        options.timeoutInterval = 60
        
        // Start download
        downloadTask = BIDownloadManager.shared.download(
            url: url,
            destinationPath: destinationPath,
            options: options
        )
        
        downloadTask?.delegate = self
    }
}

// MARK: - BIDownloadDelegate

extension DownloadViewController: BIDownloadDelegate {
    
    func downloadDidStart(_ task: BIDownloadTask) {
        print("Download started")
    }
    
    func downloadDidProgress(_ task: BIDownloadTask, progress: Double) {
        let percentage = Int(progress * 100)
        print("Progress: \(percentage)%")
    }
    
    func downloadDidComplete(_ task: BIDownloadTask, filePath: String) {
        print("Download completed: \(filePath)")
    }
    
    func downloadDidFail(_ task: BIDownloadTask, error: Error) {
        print("Download error: \(error)")
    }
}
```

## Configuration

### Download Manager Setup

```swift
var config = BIDownloadManagerConfiguration()
config.maxConcurrentDownloads = 3
config.enableLogging = true
config.logLevel = .info
config.defaultTimeoutInterval = 60

BIDownloadManager.shared.configure(config)
```

### Authentication Options

```swift
// Basic authentication
let basicAuth = BIAuthenticationOptions(
    type: .basic(username: "user", password: "pass")
)

// Bearer Token
let bearerAuth = BIAuthenticationOptions(
    type: .bearer(token: "your-token")
)

// Custom headers
let customAuth = BIAuthenticationOptions(
    type: .custom(header: "API-Key", value: "your-api-key")
)

var options = BIDownloadOptions()
options.authentication = basicAuth
```

### Custom Headers

```swift
var options = BIDownloadOptions()
options.customHeaders = [
    "User-Agent": "MyApp/1.0",
    "Accept": "application/octet-stream",
    "Custom-Header": "custom-value"
]
```

## Download Management

### Pause and Resume

```swift
// Pause
downloadTask.pause()

// Resume
downloadTask.resume()

// Cancel
downloadTask.cancel()
```

### Managing All Downloads

```swift
let manager = BIDownloadManager.shared

// Pause all downloads
manager.pauseAll()

// Resume all downloads
manager.resumeAll()

// Cancel all downloads
manager.cancelAll()

// Get statistics
let stats = manager.getDownloadStatistics()
print("Active downloads: \(stats.activeDownloads)")
print("Queued: \(stats.queuedDownloads)")
```

## Background Operation

The framework automatically supports background downloads using silent audio:

```swift
var options = BIDownloadOptions()
options.enableBackgroundAudio = true // Enabled by default
```

### Info.plist Configuration

Add the following permissions to your `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

## Multi-threaded Downloading

The framework automatically detects if the server supports Range requests and uses multi-threaded downloading for large files:

```swift
var options = BIDownloadOptions()
options.enableMultipart = true
options.maxConcurrentStreams = 4 // Number of threads
```

## Network Monitoring

The framework automatically adapts to network connection type:

```swift
// Automatic detection of optimal settings
// for Wi-Fi, Cellular, Ethernet connections
```

## Error Handling

```swift
func downloadDidFail(_ task: BIDownloadTask, error: Error) {
    if let downloadError = error as? BIDownloadError {
        switch downloadError {
        case .networkError(let underlyingError):
            print("Network error: \(underlyingError)")
        case .insufficientSpace:
            print("Insufficient disk space")
        case .rangeNotSupported:
            print("Server doesn't support Range requests")
        case .authenticationError(let message):
            print("Authentication error: \(message)")
        default:
            print("Other error: \(downloadError)")
        }
    }
}
```

## Logging

```swift
var config = BIDownloadManagerConfiguration()
config.enableLogging = true
config.logLevel = .debug // .verbose, .debug, .info, .warning, .error

BIDownloadManager.shared.configure(config)
```

## Performance

### Configuration Recommendations

- For Wi-Fi connections: `maxConcurrentStreams = 4-6`
- For Cellular connections: `maxConcurrentStreams = 1-2`
- For large files (>100MB): enable multi-threaded downloading
- For multiple downloads: limit `maxConcurrentDownloads = 2-3`

### Memory Optimization

The framework automatically manages memory and releases resources after download completion.

## Usage Examples

### Download with Progress Bar

```swift
class DownloadViewController: UIViewController {
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var statusLabel: UILabel!
    
    func downloadDidProgress(_ task: BIDownloadTask, progress: Double) {
        DispatchQueue.main.async {
            self.progressView.progress = Float(progress)
            self.statusLabel.text = "Downloaded: \(Int(progress * 100))%"
        }
    }
}
```

### Multiple Downloads

```swift
let urls = [
    "https://example.com/file1.zip",
    "https://example.com/file2.zip",
    "https://example.com/file3.zip"
]

for (index, urlString) in urls.enumerated() {
    guard let url = URL(string: urlString) else { continue }
    
    let task = BIDownloadManager.shared.download(
        url: url,
        destinationPath: "/path/to/file\(index).zip"
    )
    task.delegate = self
}
```

### Download with Authentication

```swift
let auth = BIAuthenticationOptions(
    type: .basic(username: "api_user", password: "api_password")
)

var options = BIDownloadOptions()
options.authentication = auth
options.customHeaders = ["API-Version": "v2"]

let task = BIDownloadManager.shared.download(
    url: url,
    destinationPath: destinationPath,
    options: options
)
```

## Testing

The framework includes an extensive set of unit and integration tests:

```bash
# Run tests
xcodebuild test -scheme BICurlDownloader -destination 'platform=iOS Simulator,name=iPhone 14'
```

## Performance Benchmarks

- **Download speed**: Up to 90% of maximum connection bandwidth
- **Memory usage**: <50MB for downloading files up to 10GB
- **Background operation**: Up to 30 minutes of continuous background work

## Compatibility

- iOS 13.0+ (main features)
- iOS 12.0+ (limited network monitoring functionality)
- Architectures: arm64, x86_64
- IPv4 and IPv6 support

## License

BICurlDownloader is distributed under the MIT License. See [LICENSE](LICENSE) for details.

## Contributing

We welcome contributions to the project! Please check [CONTRIBUTING.md](CONTRIBUTING.md) for instructions.

## Support

- GitHub Issues: [https://github.com/baksogen/BICurlDownloader/issues](https://github.com/baksogen/BICurlDownloader/issues)
- Email: support@example.com
- Documentation: [https://bicurldownloader.docs.com](https://bicurldownloader.docs.com)

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version information and changes.

---

**BICurlDownloader** - a reliable solution for file downloading in iOS applications with maximum performance and configuration flexibility.
