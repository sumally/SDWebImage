/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImagePrefetcher.h"

@interface SDWebImagePrefetcher ()

@property (strong, nonatomic) SDWebImageManager *manager;
@property (strong, nonatomic) NSArray *prefetchURLs;
@property (assign, nonatomic) NSUInteger requestedCount;
@property (assign, nonatomic) NSUInteger skippedCount;
@property (assign, nonatomic) NSUInteger finishedCount;
@property (assign, nonatomic) NSTimeInterval startedTime;
@property (copy, nonatomic) SDWebImageNoParamsBlock completionBlock;
@property (copy, nonatomic) SDWebImagePrefetcherProgressBlock progressBlock;

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

- (void)startPrefetchingAtIndex:(NSUInteger)index {
    if (index >= self.prefetchURLs.count) return;
    self.requestedCount++;
    [self.manager downloadImageWithURL:self.prefetchURLs[index] options:self.options progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
        if (!finished) return;
        self.finishedCount++;

        if (image) {
            if (self.progressBlock) {
                self.progressBlock(imageURL);
            }

        }
        else {
            if (self.progressBlock) {
                self.progressBlock(imageURL);
            }
            // Add last failed
            self.skippedCount++;
        }

        if (self.prefetchURLs.count > self.requestedCount) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self startPrefetchingAtIndex:self.requestedCount];
            });
        }
        else if (self.finishedCount == self.requestedCount) {
            if (self.completionBlock) {
                self.completionBlock();
                self.completionBlock = nil;
            }
        }
    }];
}

- (void)prefetchURLs:(NSArray *)urls {
    [self prefetchURLs:urls progress:nil completed:nil];
}

- (void)prefetchURLs:(NSArray *)urls progress:(SDWebImagePrefetcherProgressBlock)progressBlock completed:(SDWebImageNoParamsBlock)completionBlock {
    [self cancelPrefetching]; // Prevent duplicate prefetch request
    self.startedTime = CFAbsoluteTimeGetCurrent();
    self.prefetchURLs = urls;
    self.completionBlock = completionBlock;
    self.progressBlock = progressBlock;

    // Starts prefetching from the very first image on the list with the max allowed concurrency
    NSUInteger listCount = self.prefetchURLs.count;
    for (NSUInteger i = 0; i < self.maxConcurrentDownloads && self.requestedCount < listCount; i++) {
        [self startPrefetchingAtIndex:i];
    }
}

- (void)cancelPrefetching {
    self.prefetchURLs = nil;
    self.skippedCount = 0;
    self.requestedCount = 0;
    self.finishedCount = 0;
    [self.manager cancelAll];
}

@end
