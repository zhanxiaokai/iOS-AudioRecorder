//
//  AudioRecorder.h
//  AudioRecorder
//
//  Created by apple on 2017/2/21.
//  Copyright © 2017年 xiaokai.zhan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AudioRecorder : NSObject

- (id) initWithPath:(NSString*) path;

- (void)start;

- (void)stop;

@end
