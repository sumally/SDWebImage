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
@property (strong, nonatomic) NSMutableArray *proceedingURLs;
@property (copy, nonatomic) SDWebImageNoParamsBlock completionBlock;
@property (copy, nonatomic) SDWebImagePrefetcherProgressBlock progressBlock;
@property (strong, nonatomic) NSMutableDictionary *handlers;

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
        _prefetchURLs = [NSMutableArray array];
        _proceedingURLs = [NSMutableArray array];
        _handlers = [NSMutableDictionary dictionary];
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
    [self.proceedingURLs addObject:url];
    [self.manager downloadImageWithURL:url options:self.options progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
        if (!finished) {
            return;
        }
        [self.proceedingURLs removeObject:url];
        SDWebImageCompletionBlock handler = self.handlers[imageURL];
        if (handler) {
            handler(image, error, cacheType, imageURL);
            [self.handlers removeObjectForKey:imageURL];
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
    [self.prefetchURLs addObjectsFromArray:urls];
    self.completionBlock = completionBlock;
    self.progressBlock = progressBlock;
    for (NSUInteger i = [self.proceedingURLs count]; i < self.maxConcurrentDownloads; i++) {
        [self startPrefetching];
    }
}

- (void)removeURLFromStack:(NSURL *)url cancel:(BOOL)cancel {
    if (!url) {
        return;
    }
    BOOL isCurrent = [self isCurrentProceeding:url];
    if (isCurrent && cancel) {
        [self cancelPrefetchingForURL:url];
    } else {
        [self.prefetchURLs removeObject:url];
    }
    [self.handlers removeObjectForKey:url];
}

- (void)cancelPrefetchingForURL:(NSURL *)url {
    [self.prefetchURLs removeObject:url];
    // in case the array is const of NSString
    [self.prefetchURLs removeObject:url.absoluteString];
    [self.manager cancelForURL:url];

    [self.proceedingURLs removeObject:url];
    // in case the array is const of NSString
    [self.proceedingURLs removeObject:url.absoluteString];

    [self.handlers removeObjectForKey:url];

    for (NSUInteger i = [self.proceedingURLs count]; i < self.maxConcurrentDownloads; i++) {
        [self startPrefetching];
    }
}

- (void)cancelPrefetching {
    [self.prefetchURLs removeAllObjects];
    [self.manager cancelAll];
    [self.proceedingURLs removeAllObjects];
    [self.handlers removeAllObjects];
}

- (BOOL)isCurrentProceeding:(NSURL *)url {
    BOOL isExist = [self.proceedingURLs containsObject:url];
    if (!isExist) {
        isExist = [self.proceedingURLs containsObject:url.absoluteString];
    }
    return isExist;
}

- (BOOL)containsOnStack:(NSURL *)url {
    BOOL contains = [self.prefetchURLs containsObject:url];
    if (!contains) {
        contains = [self.prefetchURLs containsObject:url.absoluteString];
    }
    return contains;
}

- (BOOL)waitComplete:(NSURL *)url handler:(SDWebImageCompletionBlock)handler {
    if ([self containsOnStack:url]) {
        return NO;
    }
    self.handlers[url] = [handler copy];
    return YES;
}

- (void)cancelWaitingComplete:(NSURL *)url {
    if (!url) {
        return;
    }
    [self.handlers removeObjectForKey:url];
}

@end
