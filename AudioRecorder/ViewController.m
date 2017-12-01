//
//  ViewController.m
//  AudioRecorder
//
//  Created by apple on 2017/2/16.
//  Copyright © 2017年 xiaokai.zhan. All rights reserved.
//

#import "ViewController.h"
#import "AudioRecorder.h"
#import "CommonUtil.h"

@interface ViewController ()

@end

@implementation ViewController
{
    AudioRecorder*          _recorder;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (IBAction)record:(id)sender {
    NSLog(@"Forward To Recorder Page...");
    NSString* filePath = [CommonUtil documentsPath:@"recorder.caf"];
    _recorder = [[AudioRecorder alloc] initWithPath:filePath];
    [_recorder start];
}

- (IBAction)stop:(id)sender {
    if(_recorder) {
        [_recorder stop];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
