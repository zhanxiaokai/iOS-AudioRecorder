//
//  AudioRecorder.m
//  AudioRecorder
//
//  Created by apple on 2017/2/21.
//  Copyright © 2017年 xiaokai.zhan. All rights reserved.
//

/**
 *      Setup AudioSession
 * 1: Category
 * 2: Set Listener
 *      Interrupt Listener
 *      AudioRoute Change Listener
 *      Hardwate output Volume Listener
 * 3: Set IO BufferDuration
 * 4: Active AudioSession
 *
 *      Setup AudioUnit
 * 1:Build AudioComponentDescription To Build AudioUnit Instance
 * 2:Build AudioStreamBasicDescription To Set AudioUnit Property
 * 3:Connect Node Or Set RenderCallback For AudioUnit
 * 4:Initialize AudioUnit
 * 5:Initialize AudioUnit
 * 6:AudioOutputUnitStart
 *
 **/
#import "AudioRecorder.h"
#import "ELAudioSession.h"


static const AudioUnitElement inputElement = 1;

@interface AudioRecorder()
@property(nonatomic, assign) AUGraph            auGraph;
@property(nonatomic, assign) AUNode             ioNode;
@property(nonatomic, assign) AudioUnit          ioUnit;
@property(nonatomic, assign) AUNode             mixerNode;
@property(nonatomic, assign) AudioUnit          mixerUnit;
@property(nonatomic, assign) AUNode             convertNode;
@property(nonatomic, assign) AudioUnit          convertUnit;
@property(nonatomic, assign) Float64            sampleRate;

@end

@implementation AudioRecorder
{
    NSString* _destinationFilePath;
    ExtAudioFileRef finalAudioFile;
}

- (id) initWithPath:(NSString*) path {
    self = [super init];
    if(self) {
        _sampleRate = 44100.0;
        _destinationFilePath = path;
        [[ELAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord];
        [[ELAudioSession sharedInstance] setPreferredSampleRate:_sampleRate];
        [[ELAudioSession sharedInstance] setActive:YES];
        [[ELAudioSession sharedInstance] addRouteChangeListener];
        [self addAudioSessionInterruptedObserver];
        [self createAudioUnitGraph];
    }
    return self;
}


- (void)createAudioUnitGraph
{
    OSStatus status = NewAUGraph(&_auGraph);
    CheckStatus(status, @"Could not create a new AUGraph", YES);
    [self addAudioUnitNodes];
    status = AUGraphOpen(_auGraph);
    CheckStatus(status, @"Could not open AUGraph", YES);
    [self getUnitsFromNodes];
    [self setAudioUnitProperties];
    [self makeNodeConnections];
    CAShow(_auGraph);
    status = AUGraphInitialize(_auGraph);
    CheckStatus(status, @"Could not initialize AUGraph", YES);
}

- (void)addAudioUnitNodes
{
    OSStatus status = noErr;
    AudioComponentDescription ioDescription;
    bzero(&ioDescription, sizeof(ioDescription));
    ioDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioDescription.componentType = kAudioUnitType_Output;
    ioDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    status = AUGraphAddNode(_auGraph, &ioDescription, &_ioNode);
    CheckStatus(status, @"Could not add I/O node to AUGraph", YES);
    
    AudioComponentDescription converterDescription;
    bzero(&converterDescription, sizeof(converterDescription));
    converterDescription.componentType = kAudioUnitType_FormatConverter;
    converterDescription.componentSubType = kAudioUnitSubType_AUConverter;
    converterDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    status = AUGraphAddNode(_auGraph, &converterDescription, &_convertNode);
    CheckStatus(status, @"Could not add Converter node to AUGraph", YES);
    
    AudioComponentDescription mixerDescription;
    bzero(&mixerDescription, sizeof(mixerDescription));
    mixerDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    mixerDescription.componentType = kAudioUnitType_Mixer;
    mixerDescription.componentSubType = kAudioUnitSubType_MultiChannelMixer;
    status = AUGraphAddNode(_auGraph, &mixerDescription, &_mixerNode);
    CheckStatus(status, @"Could not add mixer node to AUGraph", YES);
}

- (void)getUnitsFromNodes
{
    OSStatus status = noErr;
    status = AUGraphNodeInfo(_auGraph, _ioNode, NULL, &_ioUnit);
    CheckStatus(status, @"Could not retrieve node info for I/O node", YES);
    status = AUGraphNodeInfo(_auGraph, _convertNode, NULL, &_convertUnit);
    CheckStatus(status, @"Could not retrieve node info for convert node", YES);
    status = AUGraphNodeInfo(_auGraph, _mixerNode, NULL, &_mixerUnit);
    CheckStatus(status, @"Could not retrieve node info for mixer node", YES);
}

- (void)setAudioUnitProperties
{
    OSStatus status = noErr;
    AudioStreamBasicDescription stereoStreamFormat = [self noninterleavedPCMFormatWithChannels:2];
    status = AudioUnitSetProperty(_ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inputElement,
                                  &stereoStreamFormat, sizeof(stereoStreamFormat));
    CheckStatus(status, @"Could not set stream format on I/O unit output scope", YES);
    UInt32 enableIO = 1;
    status = AudioUnitSetProperty(_ioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, inputElement,
                                  &enableIO, sizeof(enableIO));
    CheckStatus(status, @"Could not enable I/O on I/O unit input scope", YES);
    UInt32 mixerElementCount = 1;
    status = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0,
                                  &mixerElementCount, sizeof(mixerElementCount));
    CheckStatus(status, @"Could not set element count on mixer unit input scope", YES);
    status = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_SampleRate, kAudioUnitScope_Output, 0,
                                  &_sampleRate, sizeof(_sampleRate));
    CheckStatus(status, @"Could not set sample rate on mixer unit output scope", YES);
    
    UInt32 maximumFramesPerSlice = 4096;
    AudioUnitSetProperty (
                  _ioUnit,
                  kAudioUnitProperty_MaximumFramesPerSlice,
                  kAudioUnitScope_Global,
                  0,
                  &maximumFramesPerSlice,
                  sizeof (maximumFramesPerSlice)
                          );
    
    
    
    UInt32 bytesPerSample = sizeof (AudioUnitSampleType);
    AudioStreamBasicDescription _clientFormat32float;
    _clientFormat32float.mFormatID          = kAudioFormatLinearPCM;
    _clientFormat32float.mFormatFlags       = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    _clientFormat32float.mBytesPerPacket    = bytesPerSample;
    _clientFormat32float.mFramesPerPacket   = 1;
    _clientFormat32float.mBytesPerFrame     = bytesPerSample;
    _clientFormat32float.mChannelsPerFrame  = 2;
    _clientFormat32float.mBitsPerChannel    = 8 * bytesPerSample;
    _clientFormat32float.mSampleRate        = _sampleRate;
    AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &_clientFormat32float, sizeof(_clientFormat32float));
    AudioUnitSetProperty(_ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &_clientFormat32float, sizeof(_clientFormat32float));
    AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &stereoStreamFormat, sizeof(stereoStreamFormat));
    AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &_clientFormat32float, sizeof(_clientFormat32float));
}

- (void)prepareFinalWriteFile{
    AudioStreamBasicDescription destinationFormat;
    memset(&destinationFormat, 0, sizeof(destinationFormat));
    
    destinationFormat.mFormatID = kAudioFormatLinearPCM;
    destinationFormat.mSampleRate = _sampleRate;
    // if we want pcm, default to signed 16-bit little-endian
    destinationFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    destinationFormat.mBitsPerChannel = 16;
    destinationFormat.mChannelsPerFrame = 2;
    destinationFormat.mBytesPerPacket = destinationFormat.mBytesPerFrame = (destinationFormat.mBitsPerChannel / 8) * destinationFormat.mChannelsPerFrame;
    destinationFormat.mFramesPerPacket = 1;
    
    UInt32 size = sizeof(destinationFormat);
    OSStatus result = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &destinationFormat);
    
    if(result) printf("AudioFormatGetProperty %d \n", (int)result);
    CFURLRef destinationURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                            (CFStringRef)_destinationFilePath,
                                                            kCFURLPOSIXPathStyle,
                                                            false);
    
    // specify codec Saving the output in .m4a format
    result = ExtAudioFileCreateWithURL(destinationURL,
                                       kAudioFileCAFType,
                                       &destinationFormat,
                                       NULL,
                                       kAudioFileFlags_EraseFile,
                                       &finalAudioFile);
    if(result) printf("ExtAudioFileCreateWithURL %d \n", (int)result);
    CFRelease(destinationURL);
    
//    // This is a very important part and easiest way to set the ASBD for the File with correct format.
    AudioStreamBasicDescription clientFormat;
    UInt32 fSize = sizeof (clientFormat);
    memset(&clientFormat, 0, sizeof(clientFormat));
    // get the audio data format from the Output Unit
    CheckStatus(AudioUnitGetProperty(_mixerUnit,
                                     kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Output,
                                     0,
                                     &clientFormat,
                                     &fSize),@"AudioUnitGetProperty on failed", YES);
    
    // set the audio data format of mixer Unit
    CheckStatus(ExtAudioFileSetProperty(finalAudioFile,
                                        kExtAudioFileProperty_ClientDataFormat,
                                        sizeof(clientFormat),
                                        &clientFormat),
                @"ExtAudioFileSetProperty kExtAudioFileProperty_ClientDataFormat failed", YES);
    
    
    // specify codec
    UInt32 codec = kAppleHardwareAudioCodecManufacturer;
    CheckStatus(ExtAudioFileSetProperty(finalAudioFile,
                                        kExtAudioFileProperty_CodecManufacturer,
                                        sizeof(codec),
                                        &codec),@"ExtAudioFileSetProperty on extAudioFile Faild", YES);
    
    CheckStatus(ExtAudioFileWriteAsync(finalAudioFile, 0, NULL),@"ExtAudioFileWriteAsync Failed", YES);
}

static OSStatus renderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData)
{
    OSStatus result = noErr;
    __unsafe_unretained AudioRecorder *THIS = (__bridge AudioRecorder *)inRefCon;
    AudioUnitRender(THIS->_mixerUnit, ioActionFlags, inTimeStamp, 0, inNumberFrames, ioData);
    result = ExtAudioFileWriteAsync(THIS->finalAudioFile, inNumberFrames, ioData);
    return result;
}

- (void)makeNodeConnections
{
    OSStatus status = noErr;
    status = AUGraphConnectNodeInput(_auGraph, _ioNode, 1, _convertNode, 0);
    CheckStatus(status, @"Could not connect I/O node input to convert node input", YES);
    status = AUGraphConnectNodeInput(_auGraph, _convertNode, 0, _mixerNode, 0);
    CheckStatus(status, @"Could not connect I/O node input to mixer node input", YES);
    AURenderCallbackStruct finalRenderProc;
    finalRenderProc.inputProc = &renderCallback;
    finalRenderProc.inputProcRefCon = (__bridge void *)self;
    status = AUGraphSetNodeInputCallback(_auGraph, _ioNode, 0, &finalRenderProc);
    CheckStatus(status, @"Could not set InputCallback For IONode", YES);
    
//    status = AUGraphConnectNodeInput(_auGraph, _mixerNode, 0, _ioNode, 0);
//    CheckStatus(status, @"Could not connect mixer node output to I/O node input", YES);
}

- (void)dealloc
{
    [self destroyAudioUnitGraph];
}

- (AudioStreamBasicDescription)noninterleavedPCMFormatWithChannels:(UInt32)channels
{
    UInt32 bytesPerSample = sizeof(AudioUnitSampleType);
    
    AudioStreamBasicDescription asbd;
    bzero(&asbd, sizeof(asbd));
    asbd.mSampleRate = _sampleRate;
    asbd.mFormatID = kAudioFormatLinearPCM;
//    asbd.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    asbd.mFormatFlags = kAudioFormatFlagsAudioUnitCanonical | kAudioFormatFlagIsNonInterleaved;
    asbd.mBitsPerChannel = 8 * bytesPerSample;
    asbd.mBytesPerFrame = bytesPerSample;
    asbd.mBytesPerPacket = bytesPerSample;
    asbd.mFramesPerPacket = 1;
    asbd.mChannelsPerFrame = channels;
    
    return asbd;
}

- (void)destroyAudioUnitGraph
{
    AUGraphStop(_auGraph);
    AUGraphUninitialize(_auGraph);
    AUGraphClose(_auGraph);
    AUGraphRemoveNode(_auGraph, _mixerNode);
    AUGraphRemoveNode(_auGraph, _ioNode);
    DisposeAUGraph(_auGraph);
    _ioUnit = NULL;
    _mixerUnit = NULL;
    _mixerNode = 0;
    _ioNode = 0;
    _auGraph = NULL;
}

- (void)start
{
    [self prepareFinalWriteFile];
    OSStatus status = AUGraphStart(_auGraph);
    CheckStatus(status, @"Could not start AUGraph", YES);
}

- (void)stop
{
    OSStatus status = AUGraphStop(_auGraph);
    CheckStatus(status, @"Could not stop AUGraph", YES);
    ExtAudioFileDispose(finalAudioFile);
}

// AudioSession 被打断的通知
- (void)addAudioSessionInterruptedObserver
{
    [self removeAudioSessionInterruptedObserver];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onNotificationAudioInterrupted:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:[AVAudioSession sharedInstance]];
}

- (void)removeAudioSessionInterruptedObserver
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVAudioSessionInterruptionNotification
                                                  object:nil];
}

- (void)onNotificationAudioInterrupted:(NSNotification *)sender {
    AVAudioSessionInterruptionType interruptionType = [[[sender userInfo] objectForKey:AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    switch (interruptionType) {
        case AVAudioSessionInterruptionTypeBegan:
            [self stop];
            break;
        case AVAudioSessionInterruptionTypeEnded:
            [self start];
            break;
        default:
            break;
    }
}

static void CheckStatus(OSStatus status, NSString *message, BOOL fatal)
{
    if(status != noErr)
    {
        char fourCC[16];
        *(UInt32 *)fourCC = CFSwapInt32HostToBig(status);
        fourCC[4] = '\0';
        
        if(isprint(fourCC[0]) && isprint(fourCC[1]) && isprint(fourCC[2]) && isprint(fourCC[3]))
            NSLog(@"%@: %s", message, fourCC);
        else
            NSLog(@"%@: %d", message, (int)status);
        
        if(fatal)
            exit(-1);
    }
}
@end
