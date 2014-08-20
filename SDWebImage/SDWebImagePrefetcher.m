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
@property (strong, nonatomic) NSMutableArray *prefetchURLs;
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

- (void)startPrefetching {
    if ([self.prefetchURLs count] == 0) {
        return;
    }
    id url = self.prefetchURLs[0];
    [self.prefetchURLs removeObjectAtIndex:0];
    [self.manager downloadImageWithURL:url options:self.options progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
        if (!finished) {
            return;
        }

        if (self.progressBlock) {
            self.progressBlock(imageURL);
        }

        if (0 < self.prefetchURLs.count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self startPrefetching];
            });
        } else if (self.prefetchURLs.count == 0) {
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
    self.prefetchURLs = [urls mutableCopy];
    self.completionBlock = completionBlock;
    self.progressBlock = progressBlock;

    for (NSUInteger i = 0; i < self.maxConcurrentDownloads; i++) {
        [self startPrefetching];
    }
}

- (void)cancelPrefetching {
    self.prefetchURLs = nil;
    [self.manager cancelAll];
}

@end
