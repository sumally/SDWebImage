/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImagePrefetcher.h"

#if !defined(DEBUG) && !defined (SD_VERBOSE)
#define NSLog(...)
#endif

@interface SDWebImagePrefetcherData : NSObject
@property (strong, nonatomic) NSArray *prefetchURLs;
@property (assign, nonatomic) NSUInteger requestedCount;
@property (assign, nonatomic) NSUInteger skippedCount;
@property (assign, nonatomic) NSUInteger finishedCount;
@property (assign, nonatomic) NSTimeInterval startedTime;
@property (copy, nonatomic) SDWebImagePrefetcherCompletionBlock completionBlock;
@property (copy, nonatomic) SDWebImagePrefetcherProgressBlock progressBlock;
@property (nonatomic, readonly) BOOL isCancelled;
@property (weak, nonatomic) SDWebImagePrefetcher* imagePrefetcher;
@property (weak, nonatomic) id <SDWebImagePrefetcherDelegate> delegate;
- (void)cancel;
@end

@implementation SDWebImagePrefetcherData
- (id)init {
    self = [super init];
    if (self) {
        _isCancelled = NO;
    }
    return self;
}

- (void)cancel {
    self.completionBlock = nil;
    self.progressBlock = nil;
    _isCancelled = YES;
}

- (void)reportStatus {
    NSUInteger total = [self.prefetchURLs count];
    NSLog(@"Finished prefetching (%@ successful, %@ skipped, timeElasped %.2f)", @(total - self.skippedCount), @(self.skippedCount), CFAbsoluteTimeGetCurrent() - self.startedTime);
    if ([self.delegate respondsToSelector:@selector(imagePrefetcher:didFinishWithTotalCount:skippedCount:)]) {
        [self.delegate imagePrefetcher:self.imagePrefetcher
               didFinishWithTotalCount:(total - self.skippedCount)
                          skippedCount:self.skippedCount
        ];
    }
}

@end


@interface SDWebImagePrefetcher ()

@property (strong, nonatomic) SDWebImageManager *manager;
@property (strong, nonatomic) SDWebImagePrefetcherData *data;

@end

@implementation SDWebImagePrefetcher

+ (SDWebImagePrefetcher *)sharedImagePrefetcher {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (id)init {
    if ((self = [super init])) {
        _manager = [SDWebImageManager new];
        _options = SDWebImageLowPriority;
        self.maxConcurrentDownloads = 3;
    }
    return self;
}

- (void)setMaxConcurrentDownloads:(NSUInteger)maxConcurrentDownloads {
    self.manager.imageDownloader.maxConcurrentDownloads = maxConcurrentDownloads;
}

- (NSUInteger)maxConcurrentDownloads {
    return self.manager.imageDownloader.maxConcurrentDownloads;
}

- (void)startPrefetchingAtIndex:(NSUInteger)index data:(SDWebImagePrefetcherData *)data {
    __weak SDWebImagePrefetcherData *weakData = data;
    if (index >= weakData.prefetchURLs.count) return;
    weakData.requestedCount++;
    [self.manager downloadImageWithURL:weakData.prefetchURLs[index] options:self.options progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
        if (!finished) return;

        if (!weakData || weakData.isCancelled) {
            return;
        }
        weakData.finishedCount++;

        if (image) {
            if (weakData.progressBlock) {
                weakData.progressBlock(weakData.finishedCount, [weakData.prefetchURLs count]);
            }
            NSLog(@"Prefetched %@ out of %@", @(weakData.finishedCount), @(weakData.prefetchURLs.count));
        }
        else {
            if (weakData.progressBlock) {
                weakData.progressBlock(weakData.finishedCount,[weakData.prefetchURLs count]);
            }
            NSLog(@"Prefetched %@ out of %@ (Failed)", @(weakData.finishedCount), @(weakData.prefetchURLs.count));

            // Add last failed
            weakData.skippedCount++;
        }
        if ([weakData.delegate respondsToSelector:@selector(imagePrefetcher:didPrefetchURL:finishedCount:totalCount:)]) {
            [weakData.delegate imagePrefetcher:self
                                didPrefetchURL:weakData.prefetchURLs[index]
                                 finishedCount:weakData.finishedCount
                                    totalCount:weakData.prefetchURLs.count
            ];
        }

        if (!weakData.isCancelled && weakData.prefetchURLs.count > weakData.requestedCount) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self startPrefetchingAtIndex:weakData.requestedCount data:weakData];
            });
        }
        else if (weakData.finishedCount == weakData.requestedCount) {
            [weakData reportStatus];
            if (weakData.completionBlock) {
                weakData.completionBlock(weakData.finishedCount, weakData.skippedCount);
                weakData.completionBlock = nil;
            }
        }
    }];
}

- (void)prefetchURLs:(NSArray *)urls {
    [self prefetchURLs:urls progress:nil completed:nil];
}

- (void)prefetchURLs:(NSArray *)urls progress:(SDWebImagePrefetcherProgressBlock)progressBlock completed:(SDWebImagePrefetcherCompletionBlock)completionBlock {
    [self cancelPrefetching]; // Prevent duplicate prefetch request

    SDWebImagePrefetcherData *data = [SDWebImagePrefetcherData new];
    data.startedTime = CFAbsoluteTimeGetCurrent();
    data.prefetchURLs = urls;
    data.completionBlock = completionBlock;
    data.progressBlock = progressBlock;
    data.imagePrefetcher = self;
    self.data = data;

    // Starts prefetching from the very first image on the list with the max allowed concurrency
    NSUInteger listCount = data.prefetchURLs.count;
    for (NSUInteger i = 0; i < self.maxConcurrentDownloads && data.requestedCount < listCount; i++) {
        [self startPrefetchingAtIndex:i data:data];
    }
}

- (void)cancelPrefetching {
    [self.data cancel];
}

@end
