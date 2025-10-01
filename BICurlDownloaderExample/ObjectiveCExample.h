//
//  ObjectiveCExample.h
//  BICurlDownloaderExample
//
//  Created by BiOM on 11.09.2025.
//

#import <Foundation/Foundation.h>

@class BIDownloadTask;
@protocol BIDownloadDelegate;

@interface ObjectiveCExample : NSObject <BIDownloadDelegate>

/// Демонстрация использования фреймворка из Objective-C
- (void)demonstrateFrameworkUsage;

/// Быстрая загрузка файла
- (void)quickDownloadExample;

/// Загрузка с настройками
- (void)advancedDownloadExample;

/// Загрузка с аутентификацией
- (void)downloadWithAuthenticationExample;

@end
