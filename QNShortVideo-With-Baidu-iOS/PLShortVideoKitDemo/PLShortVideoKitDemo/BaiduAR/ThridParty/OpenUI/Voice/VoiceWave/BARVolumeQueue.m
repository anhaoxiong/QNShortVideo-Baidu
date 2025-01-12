//
//  BARVolumeQueue.m
//  MISVoiceSearchLib
//
//  Created by yushichao on 16/8/17.
//  Copyright © 2016年 yushichao. All rights reserved.
//

#import "BARVolumeQueue.h"

#define minVolume 0.05

@interface BARVolumeQueue()

@property (nonatomic, strong) NSMutableArray *volumeArray;

@end

@implementation BARVolumeQueue

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.volumeArray = [NSMutableArray array];
    }
    
    return self;
}
- (void)dealloc
{
    if(!self.volumeArray){
        self.volumeArray = nil;
        //BARLog(@"BAR_SDK_TRIM_SIZE");
    }
}

- (void)pushVolume:(CGFloat)volume
{
    if (volume >= minVolume) {
        [_volumeArray addObject:[NSNumber numberWithFloat:volume]];
    }
}

- (void)pushVolumeWithArray:(NSArray *)array
{
    if (array.count > 0) {
        for (NSInteger i = 0; i < array.count; i++) {
            CGFloat volume = [array[i] floatValue];
            [self pushVolume:volume];
        }
    }
}

- (CGFloat)popVolume
{
    CGFloat volume = -10;
    if (_volumeArray.count > 0) {
        volume = [[_volumeArray firstObject] floatValue];
        [_volumeArray removeObjectAtIndex:0];
    }
    
    return volume;
}

- (void)cleanQueue
{
    if (_volumeArray) {
        [_volumeArray removeAllObjects];
    }
}

@end
