//
//  ViewController.m
//  BICurlDownloaderExampleObjC
//
//  Created by BiOM on 29.09.2025.
//

#import "ViewController.h"
@import BICurlDownloader;

@interface ViewController () <BIDownloadDelegate>

// MARK: - UI Elements
@property (weak, nonatomic) IBOutlet UITextField *urlTextField;
@property (weak, nonatomic) IBOutlet UIButton *downloadButton;
@property (weak, nonatomic) IBOutlet UIButton *pauseButton;
@property (weak, nonatomic) IBOutlet UIButton *cancelButton;
@property (weak, nonatomic) IBOutlet UIProgressView *progressView;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UILabel *speedLabel;
@property (weak, nonatomic) IBOutlet UISwitch *backgroundAudioSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *multipartSwitch;
@property (weak, nonatomic) IBOutlet UITextView *logTextView;

// MARK: - Properties
@property (strong, nonatomic) BIDownloadTask *currentDownloadTask;
@property (strong, nonatomic) NSDate *lastProgressUpdate;
@property (nonatomic) int64_t lastBytesDownloaded;

@end

@implementation ViewController

// MARK: - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self configureDownloadManager];
    [self logMessage:@"BICurlDownloader Example App Started"];
    [self logMessage:[NSString stringWithFormat:@"Framework Version: %@", BICurlDownloaderInfo.fullVersion]];
    [self logMessage:[NSString stringWithFormat:@"Supported Features: %@", [BICurlDownloaderInfo.supportedFeatures componentsJoinedByString:@", "]]];
}

// MARK: - Setup

- (void)setupUI {
    self.title = @"BICurlDownloader Example";
    
    // Настройка UI элементов
    self.urlTextField.text = @"https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_30MB.mp4";
    self.urlTextField.text = @"https://examplefiles.org/files/video/mp4-example-video-download-4k-uhd-3840x2160.mp4";
    self.urlTextField.text = @"https://archive.org/compress/contes_temps_passe_librivox/formats=64KBPS MP3&file=/contes_temps_passe_librivox.zip";
    self.urlTextField.placeholder = @"Enter download URL...";
    
    [self.downloadButton setTitle:@"Download" forState:UIControlStateNormal];
    [self.pauseButton setTitle:@"Pause" forState:UIControlStateNormal];
    [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    
    self.pauseButton.enabled = NO;
    self.cancelButton.enabled = NO;
    
    self.progressView.progress = 0.0;
    self.statusLabel.text = @"Ready to download";
    self.speedLabel.text = @"";
    
    self.backgroundAudioSwitch.on = YES;
    self.multipartSwitch.on = YES;
    
    // Настройка лог textView
    self.logTextView.editable = NO;
    self.logTextView.text = @"";
    self.logTextView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.logTextView.backgroundColor = [UIColor systemGray6Color];
    
    self.lastProgressUpdate = [NSDate date];
    self.lastBytesDownloaded = 0;
}

- (void)configureDownloadManager {
    BIDownloadManagerConfiguration *config = [[BIDownloadManagerConfiguration alloc] initWithEnableLogging:YES 
                                                                                                  logLevel:BILogLevelVerbose
                                                                                      maxConcurrentDownloads:5];
    
    [BIDownloadManager.shared configure:config];
    
    [self logMessage:@"Download Manager Configured"];
    [self logMessage:[NSString stringWithFormat:@"Max Concurrent Downloads: %ld", (long)config.maxConcurrentDownloads]];
}

// MARK: - Actions

- (IBAction)downloadButtonTapped:(UIButton *)sender {
    NSString *urlString = self.urlTextField.text;
    if (!urlString || urlString.length == 0) {
        [self showAlertWithTitle:@"Error" message:@"Please enter a valid URL"];
        return;
    }
    
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [self showAlertWithTitle:@"Error" message:@"Invalid URL format"];
        return;
    }
    
    // Создаем путь для сохранения файла
    NSURL *documentsPath = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory 
                                                                   inDomains:NSUserDomainMask] firstObject];
    NSString *fileName = url.lastPathComponent.length > 0 ? url.lastPathComponent : @"downloaded_file";
    NSString *destinationPath = [[documentsPath URLByAppendingPathComponent:fileName] path];
    
    // Настраиваем опции загрузки
    BIDownloadOptions *options = [[BIDownloadOptions alloc] initWithEnableBackgroundAudio:self.backgroundAudioSwitch.on
                                                                          enableMultipart:self.multipartSwitch.on
                                                                          timeoutInterval:60];
    options.maxConcurrentStreams = 5;
    options.userAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";
    
    // Запускаем загрузку
    self.currentDownloadTask = [BIDownloadManager.shared downloadWithUrl:url 
                                                          destinationPath:destinationPath 
                                                                  options:options];
    
    self.currentDownloadTask.delegate = self;
    
    // Обновляем UI
    self.downloadButton.enabled = NO;
    self.pauseButton.enabled = YES;
    self.cancelButton.enabled = YES;
    
    [self logMessage:[NSString stringWithFormat:@"Started download: %@", urlString]];
    [self logMessage:[NSString stringWithFormat:@"Destination: %@", destinationPath]];
    [self logMessage:[NSString stringWithFormat:@"Background Audio: %@", options.enableBackgroundAudio ? @"YES" : @"NO"]];
    [self logMessage:[NSString stringWithFormat:@"Multipart: %@", options.enableMultipart ? @"YES" : @"NO"]];
}

- (IBAction)pauseButtonTapped:(UIButton *)sender {
    if (!self.currentDownloadTask) return;
    
    switch (self.currentDownloadTask.state) {
        case BIDownloadStateDownloading:
            [self.currentDownloadTask pause];
            [self.pauseButton setTitle:@"Resume" forState:UIControlStateNormal];
            [self logMessage:@"Download paused"];
            break;
            
        case BIDownloadStatePaused:
            [self.currentDownloadTask resume];
            [self.pauseButton setTitle:@"Pause" forState:UIControlStateNormal];
            [self logMessage:@"Download resumed"];
            break;
            
        default:
            break;
    }
}

- (IBAction)cancelButtonTapped:(UIButton *)sender {
    [self.currentDownloadTask cancel];
    [self resetUI];
    [self logMessage:@"Download cancelled"];
}

- (IBAction)clearLogsButtonTapped:(UIButton *)sender {
    self.logTextView.text = @"";
}

- (IBAction)testMultipleDownloadsButtonTapped:(UIButton *)sender {
    NSArray<NSString *> *testUrls = @[
        @"https://sample-videos.com/zip/10/mp4/SampleVideo_1280x720_1mb.mp4",
        @"https://www.learningcontainer.com/wp-content/uploads/2020/05/sample-mp4-file.mp4",
        @"https://file-examples.com/storage/fe68c1f7d2b60fa2944e90d/2017/10/file_example_JPG_100kB.jpg"
    ];
    
    [testUrls enumerateObjectsUsingBlock:^(NSString *urlString, NSUInteger index, BOOL *stop) {
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) return;
        
        NSURL *documentsPath = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory 
                                                                       inDomains:NSUserDomainMask] firstObject];
        NSString *fileName = [NSString stringWithFormat:@"test_file_%lu_%@", (unsigned long)index, url.lastPathComponent];
        NSString *destinationPath = [[documentsPath URLByAppendingPathComponent:fileName] path];
        
        BIDownloadTask *task = [BIDownloadManager.shared downloadWithUrl:url 
                                                          destinationPath:destinationPath 
                                                                  options:[[BIDownloadOptions alloc] init]];
        task.delegate = self;
        
        [self logMessage:[NSString stringWithFormat:@"Started test download %lu: %@", (unsigned long)(index + 1), url.lastPathComponent]];
    }];
}

- (IBAction)quickDownloadButtonTapped:(UIButton *)sender {
    // Массив тестовых URL для проверки
    NSArray<NSString *> *testUrls = @[
        @"https://cdn.dribbble.com/users/5031/screenshots/3713646/attachments/832536/wallpaper_mikael_gustafsson.png",
        @"https://toptreki.com/uploads/files/2025-09/1758737659_8p4s-n-vdn.mp3",
        @"https://images.unsplash.com/photo-1485470733090-0aae1788d5af?fm=jpg&q=60&w=3000&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8M3x8d2FsbHBhcGVyJTIwNGt8ZW58MHx8MHx8fDA%3D",
        @"https://www.win-rar.com/fileadmin/winrar-versions/rarmacos-x64-712.tar.gz"
    ];
    
    // Используем первый URL для теста
    NSString *testUrl = testUrls[0];
    
    NSURL *documentsPath = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory 
                                                                   inDomains:NSUserDomainMask] firstObject];
    NSString *destinationPath = [[documentsPath URLByAppendingPathComponent:@"quick_download.jpg"] path];
    
    [self logMessage:@"Starting quick download..."];
    
    __weak typeof(self) weakSelf = self;
    [BIDownloadManager.shared quickDownloadFromString:testUrl
                                        destinationPath:destinationPath
                                             completion:^(NSString * _Nullable filePath, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [weakSelf logMessage:[NSString stringWithFormat:@"Quick download failed: %@", error.localizedDescription]];
                [weakSelf showAlertWithTitle:@"Quick Download Failed" message:error.localizedDescription];
            } else {
                [weakSelf logMessage:[NSString stringWithFormat:@"Quick download completed: %@", filePath]];
                [weakSelf showAlertWithTitle:@"Quick Download" message:@"File downloaded successfully!"];
            }
        });
    }];
}

// MARK: - Helper Methods

- (void)resetUI {
    self.downloadButton.enabled = YES;
    self.pauseButton.enabled = NO;
    [self.pauseButton setTitle:@"Pause" forState:UIControlStateNormal];
    self.cancelButton.enabled = NO;
    
    self.progressView.progress = 0.0;
    self.statusLabel.text = @"Ready to download";
    self.speedLabel.text = @"";
    
    self.currentDownloadTask = nil;
    self.lastBytesDownloaded = 0;
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)logMessage:(NSString *)message {
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] 
                                                         dateStyle:NSDateFormatterNoStyle 
                                                         timeStyle:NSDateFormatterMediumStyle];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        weakSelf.logTextView.text = [weakSelf.logTextView.text stringByAppendingString:logEntry];
        
        // Автоматически прокручиваем к концу
        NSRange bottom = NSMakeRange(weakSelf.logTextView.text.length, 0);
        [weakSelf.logTextView scrollRangeToVisible:bottom];
    });
}

- (void)updateDownloadSpeed:(int64_t)bytesDownloaded {
    NSDate *now = [NSDate date];
    NSTimeInterval timeDiff = [now timeIntervalSinceDate:self.lastProgressUpdate];
    
    if (timeDiff >= 1.0) { // Обновляем скорость каждую секунду
        int64_t bytesDiff = bytesDownloaded - self.lastBytesDownloaded;
        double speed = (double)bytesDiff / timeDiff;
        
        NSString *speedString = [NSByteCountFormatter stringFromByteCount:(int64_t)speed 
                                                               countStyle:NSByteCountFormatterCountStyleFile];
        self.speedLabel.text = [NSString stringWithFormat:@"%@/s", speedString];
        
        self.lastProgressUpdate = now;
        self.lastBytesDownloaded = bytesDownloaded;
    }
}

// MARK: - BIDownloadDelegate

- (void)downloadDidStart:(BIDownloadTask *)task {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        weakSelf.statusLabel.text = @"Downloading...";
        [weakSelf logMessage:[NSString stringWithFormat:@"Download started for task: %@", task.id]];
    });
}

- (void)downloadDidProgress:(BIDownloadTask *)task progress:(double)progress {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        weakSelf.progressView.progress = (float)progress;
        
        int percentage = (int)(progress * 100);
        weakSelf.statusLabel.text = [NSString stringWithFormat:@"Downloading... %d%%", percentage];
        
        // Обновляем скорость загрузки
        int64_t bytesDownloaded = task.progress.completedUnitCount;
        [weakSelf updateDownloadSpeed:bytesDownloaded];
    });
}

- (void)downloadDidComplete:(BIDownloadTask *)task filePath:(NSString *)filePath {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        weakSelf.progressView.progress = 1.0;
        weakSelf.statusLabel.text = @"Download completed!";
        weakSelf.speedLabel.text = @"";
        
        NSError *error = nil;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
        int64_t fileSize = error ? 0 : [attributes[NSFileSize] longLongValue];
        NSString *sizeString = [NSByteCountFormatter stringFromByteCount:fileSize 
                                                              countStyle:NSByteCountFormatterCountStyleFile];
        
        [weakSelf logMessage:@"Download completed successfully"];
        [weakSelf logMessage:[NSString stringWithFormat:@"File saved to: %@", filePath]];
        [weakSelf logMessage:[NSString stringWithFormat:@"File size: %@", sizeString]];
        
        [weakSelf showAlertWithTitle:@"Success" 
                             message:[NSString stringWithFormat:@"File downloaded successfully!\nSize: %@", sizeString]];
        
        // Сбрасываем UI через 2 секунды
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf resetUI];
        });
    });
}

- (void)downloadDidFail:(BIDownloadTask *)task error:(NSError *)error {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        weakSelf.statusLabel.text = @"Download failed";
        weakSelf.speedLabel.text = @"";
        
        NSString *errorMessage = error.localizedDescription;
        [weakSelf logMessage:[NSString stringWithFormat:@"Download failed: %@", errorMessage]];
        
        [weakSelf showAlertWithTitle:@"Download Failed" message:errorMessage];
        
        [weakSelf resetUI];
    });
}

@end
