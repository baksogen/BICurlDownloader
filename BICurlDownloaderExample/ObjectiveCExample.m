//
//  ObjectiveCExample.m
//  BICurlDownloaderExample
//
//  Created by BiOM on 11.09.2025.
//

#import "ObjectiveCExample.h"
@import BICurlDownloader;

@interface ObjectiveCExample ()
@property (nonatomic, strong) BIDownloadTask *currentTask;
@end

@implementation ObjectiveCExample

- (void)demonstrateFrameworkUsage {
    NSLog(@"=== BICurlDownloader Objective-C Example ===");
    NSLog(@"Framework Version: %@", [BICurlDownloaderInfo fullVersion]);
    NSLog(@"Supported Features: %@", [BICurlDownloaderInfo supportedFeatures]);
    NSLog(@"Compatible: %@", [BICurlDownloaderInfo isCompatible] ? @"YES" : @"NO");
    
    // Настройка менеджера
    BIDownloadManagerConfiguration *config = [[BIDownloadManagerConfiguration alloc] init];
    config.enableLogging = YES;
    config.logLevel = BILogLevelInfo;
    config.maxConcurrentDownloads = 2;
    
    [[BIDownloadManager shared] configure:config];
    NSLog(@"Download manager configured");
    
    // Запускаем примеры
    [self quickDownloadExample];
}

- (void)quickDownloadExample {
    NSLog(@"\n=== Quick Download Example ===");
    
    NSString *urlString = @"https://file-examples.com/storage/fe68c1f7d2b60fa2944e90d/2017/10/file_example_JPG_100kB.jpg";
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *destinationPath = [documentsPath stringByAppendingPathComponent:@"objc_quick_download.jpg"];
    
    BIDownloadTask *task = [[BIDownloadManager shared] quickDownloadFromString:urlString
                                                               destinationPath:destinationPath
                                                                    completion:^(NSString *filePath, NSError *error) {
        if (error) {
            NSLog(@"Quick download failed: %@", error.localizedDescription);
        } else {
            NSLog(@"Quick download completed: %@", filePath);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self advancedDownloadExample];
            });
        }
    }];
    
    if (task) {
        NSLog(@"Quick download task created: %@", task.taskId);
    }
}

- (void)advancedDownloadExample {
    NSLog(@"\n=== Advanced Download Example ===");
    
    NSURL *url = [NSURL URLWithString:@"https://sample-videos.com/zip/10/mp4/SampleVideo_1280x720_1mb.mp4"];
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *destinationPath = [documentsPath stringByAppendingPathComponent:@"objc_advanced_download.mp4"];
    
    // Настраиваем опции загрузки
    BIDownloadOptions *options = [[BIDownloadOptions alloc] init];
    options.enableBackgroundAudio = YES;
    options.enableMultipart = YES;
    options.maxConcurrentStreams = 4;
    options.timeoutInterval = 60;
    options.customHeaders = @{
        @"User-Agent": @"BICurlDownloader-ObjC-Example/1.0",
        @"Accept": @"video/mp4"
    };
    
    // Запускаем загрузку
    self.currentTask = [[BIDownloadManager shared] downloadFromURL:url
                                                    destinationPath:destinationPath
                                                            options:options];
    self.currentTask.delegate = self;
    
    NSLog(@"Advanced download started with options:");
    NSLog(@"- Background Audio: %@", options.enableBackgroundAudio ? @"YES" : @"NO");
    NSLog(@"- Multipart: %@", options.enableMultipart ? @"YES" : @"NO");
    NSLog(@"- Concurrent Streams: %ld", (long)options.maxConcurrentStreams);
}

- (void)downloadWithAuthenticationExample {
    NSLog(@"\n=== Authentication Example ===");
    
    // Пример с Bearer Token аутентификацией
    BIAuthenticationOptions *auth = [[BIAuthenticationOptions alloc] initWithBearerToken:@"your-api-token"];
    
    BIDownloadOptions *options = [[BIDownloadOptions alloc] init];
    options.authentication = auth;
    options.customHeaders = @{
        @"API-Version": @"v1",
        @"Content-Type": @"application/octet-stream"
    };
    
    NSLog(@"Authentication configured:");
    NSLog(@"- Type: Bearer Token");
    NSLog(@"- Custom headers: %@", options.customHeaders);
    
    // Пример с Basic аутентификацией
    BIAuthenticationOptions *basicAuth = [[BIAuthenticationOptions alloc] initWithBasicWithUsername:@"username"
                                                                                            password:@"password"];
    NSLog(@"Basic auth example created");
    
    // Пример с кастомным заголовком
    BIAuthenticationOptions *customAuth = [[BIAuthenticationOptions alloc] initWithCustomWithHeader:@"X-API-Key"
                                                                                               value:@"your-api-key"];
    NSLog(@"Custom auth example created");
}

#pragma mark - BIDownloadDelegate

- (void)downloadDidStart:(BIDownloadTask *)task {
    NSLog(@"[Delegate] Download started: %@", task.taskId);
}

- (void)downloadDidProgress:(BIDownloadTask *)task progress:(double)progress {
    NSInteger percentage = (NSInteger)(progress * 100);
    if (percentage % 10 == 0) { // Логируем каждые 10%
        NSLog(@"[Delegate] Download progress: %ld%% (Task: %@)", (long)percentage, task.taskId);
    }
}

- (void)downloadDidComplete:(BIDownloadTask *)task filePath:(NSString *)filePath {
    NSLog(@"[Delegate] Download completed: %@", filePath);
    NSLog(@"[Delegate] Task ID: %@", task.taskId);
    
    // Получаем размер файла
    NSError *error;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
    if (!error) {
        NSNumber *fileSize = [attributes objectForKey:NSFileSize];
        NSLog(@"[Delegate] File size: %@ bytes", fileSize);
    }
    
    // Запускаем следующий пример
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self downloadWithAuthenticationExample];
    });
}

- (void)downloadDidFail:(BIDownloadTask *)task error:(NSError *)error {
    NSLog(@"[Delegate] Download failed: %@", error.localizedDescription);
    NSLog(@"[Delegate] Task ID: %@", task.taskId);
    NSLog(@"[Delegate] Error domain: %@", error.domain);
    NSLog(@"[Delegate] Error code: %ld", (long)error.code);
    
    if (error.userInfo[NSUnderlyingErrorKey]) {
        NSError *underlyingError = error.userInfo[NSUnderlyingErrorKey];
        NSLog(@"[Delegate] Underlying error: %@", underlyingError.localizedDescription);
    }
}

@end
