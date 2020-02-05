//
//  MRViewController.m
//  MRMoviePlayer
//
//  Created by qianlongxu on 01/31/2020.
//  Copyright (c) 2020 qianlongxu. All rights reserved.
//

#import "MRViewController.h"
#import <MRMoviePlayer/mr_play.h>
#import "OpenGLView20.h"
#include <AudioUnit/AudioUnit.h>
#include <AVFoundation/AVFoundation.h>

@interface MRViewController ()

//采样率
@property (nonatomic,assign) double targetSampleRate;
//声音大小
@property (nonatomic,assign) float outputVolume;
//音频播放器
@property (nonatomic,assign) AudioUnit audioUnit;
//音频信息结构体
@property (nonatomic,assign) AudioStreamBasicDescription outputFormat;
//音频重采样 packet 格式buffer
@property (nonatomic,assign) uint8_t     *audioBuffer4Packet;
@property (nonatomic,assign) NSUInteger  audioBuffer4PacketSize;
//音频重采样 planar 格式buffer
@property (nonatomic,assign) uint8_t     *audioBuffer4PlanarL;
@property (nonatomic,assign) uint8_t     *audioBuffer4PlanarR;
@property (nonatomic,assign) NSUInteger  audioBuffer4PlanarSize;
@property (nonatomic,assign) MRSampleFormat targetSampleFormat;

@property (weak, nonatomic) OpenGLView20 *glView;
@property (assign, nonatomic) MRPlayer player;

@end

@implementation MRViewController

int displayFunc(void *context,AVFrame *f){
    MRViewController *vc = (__bridge MRViewController *)(context);
    dispatch_async(dispatch_get_main_queue(), ^{
        [vc.glView displayYUV420pData:f];
    });
    return 0;
}

static void msgFunc (void *context,MR_Msg *msg){
    if (!msg) {
        return;
    }
    
    MRViewController *vc = (__bridge MRViewController *)(context);
    
    switch (msg->type) {
        case MR_Msg_Type_InitAudioRender:
        {
            MRSampleFormat targetSampleFormat = msg->arg1;
            dispatch_async(dispatch_get_main_queue(), ^{
                [vc setupAudioRender:targetSampleFormat];
            });
        }
            break;
        case MR_Msg_Type_InitVideoRender:
        {
            int width  = msg->arg1;
            int height = msg->arg2;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [vc setupVideoRender:width height:height];
            });
        }
            break;
    }
}

- (void)setupVideoRender:(int)width height:(int)height
{
    CGSize vSize = self.view.bounds.size;
    CGFloat vh = vSize.width * height / width;
    CGRect frame = CGRectMake(0, (vSize.height-vh)/2, vSize.width , vh);
    
    OpenGLView20 *glView = [[OpenGLView20 alloc]initWithFrame:frame];
    [self.view addSubview:glView];
    self.glView = glView;
}

- (void)setupAudioRender:(MRSampleFormat)targetSampleFormat
{
    _outputVolume = [[AVAudioSession sharedInstance]outputVolume];
    
    {
        [[AVAudioSession sharedInstance]setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:nil];
        //        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(audioRouteChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
        //        [[AVAudioSession sharedInstance]addObserver:self forKeyPath:@"outputVolume" options:NSKeyValueObservingOptionNew context:nil];
        
        [[AVAudioSession sharedInstance]setActive:YES error:nil];
    }
    
    {
        // ----- Audio Unit Setup -----
        
#define kOutputBus 0 //Bus 0 is used for the output side
#define kInputBus  1 //Bus 0 is used for the output side
        
        // Describe the output unit.
        
        AudioComponentDescription desc = {0};
        desc.componentType = kAudioUnitType_Output;
        desc.componentSubType = kAudioUnitSubType_RemoteIO;
        desc.componentManufacturer = kAudioUnitManufacturer_Apple;
        
        // Get component
        AudioComponent component = AudioComponentFindNext(NULL, &desc);
        OSStatus status = AudioComponentInstanceNew(component, &_audioUnit);
        NSAssert(noErr == status, @"AudioComponentInstanceNew");
        
        UInt32 size = sizeof(self.outputFormat);
        /// 获取默认的输入信息
        AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, kOutputBus, &_outputFormat, &size);
        //设置采样率
        _outputFormat.mSampleRate = _targetSampleRate;
        /**不使用视频的原声道数_audioCodecCtx->channels;
         mChannelsPerFrame 这个值决定了后续AudioUnit索要数据时 ioData->mNumberBuffers 的值！
         如果写成1会影响Planar类型，就不会开两个buffer了！！因此这里写死为2！
         */
        _outputFormat.mChannelsPerFrame = 2;
        _outputFormat.mFormatID = kAudioFormatLinearPCM;
        _outputFormat.mReserved = 0;
        
        bool isFloat = targetSampleFormat == MR_SAMPLE_FMT_FLT || targetSampleFormat == MR_SAMPLE_FMT_FLTP;
        bool isS16 = targetSampleFormat == MR_SAMPLE_FMT_S16 || targetSampleFormat == MR_SAMPLE_FMT_S16P;
        
        bool isPlanar = mr_sample_fmt_is_planar(targetSampleFormat);
        
        if (isS16){
            _outputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger;
            _outputFormat.mFramesPerPacket = 1;
            _outputFormat.mBitsPerChannel = sizeof(SInt16) * 8;
        } else if (isFloat){
            _outputFormat.mFormatFlags = kAudioFormatFlagIsFloat;
            _outputFormat.mFramesPerPacket = 1;
            _outputFormat.mBitsPerChannel = sizeof(float) * 8;
        } else {
            NSAssert(NO, @"不支持的音频采样格式%d",targetSampleFormat);
        }
        
        if (isPlanar) {
            _outputFormat.mFormatFlags |= kAudioFormatFlagIsNonInterleaved;
            _outputFormat.mBytesPerFrame = _outputFormat.mBitsPerChannel / 8;
            _outputFormat.mBytesPerPacket = _outputFormat.mBytesPerFrame * _outputFormat.mFramesPerPacket;
        } else {
            _outputFormat.mFormatFlags |= kAudioFormatFlagIsPacked;
            _outputFormat.mBytesPerFrame = (_outputFormat.mBitsPerChannel / 8) * _outputFormat.mChannelsPerFrame;
            _outputFormat.mBytesPerPacket = _outputFormat.mBytesPerFrame * _outputFormat.mFramesPerPacket;
        }
        
        status = AudioUnitSetProperty(_audioUnit,
                             kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input,
                             kOutputBus,
                             &_outputFormat, size);
        NSAssert(noErr == status, @"AudioUnitSetProperty");
        ///get之后刷新这个值；
        _targetSampleRate  = _outputFormat.mSampleRate;
        
        UInt32 flag = 0;
        AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, kInputBus, &flag, sizeof(flag));
        AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, kInputBus, &flag, sizeof(flag));
        // Slap a render callback on the unit
        AURenderCallbackStruct callbackStruct;
        callbackStruct.inputProc = MRRenderCallback;
        callbackStruct.inputProcRefCon = (__bridge void *)(self);
        
        status = AudioUnitSetProperty(_audioUnit,
                             kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Input,
                             kOutputBus,
                             &callbackStruct,
                             sizeof(callbackStruct));
        NSAssert(noErr == status, @"AudioUnitSetProperty");
        status = AudioUnitInitialize(_audioUnit);
        NSAssert(noErr == status, @"AudioUnitInitialize");
#undef kOutputBus
#undef kInputBus
        
        self.targetSampleFormat = targetSampleFormat;
        
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        OSStatus status = AudioOutputUnitStart(_audioUnit);
        if(noErr == status){

        }
        NSAssert(noErr == status, @"AudioOutputUnitStart");
    });
    
}

#pragma mark - 音频

///音频渲染回调；
static inline OSStatus MRRenderCallback(void *inRefCon,
                                        AudioUnitRenderActionFlags    * ioActionFlags,
                                        const AudioTimeStamp          * inTimeStamp,
                                        UInt32                        inOutputBusNumber,
                                        UInt32                        inNumberFrames,
                                        AudioBufferList                * ioData)
{
    MRViewController *am = (__bridge MRViewController *)inRefCon;
    return [am renderFrames:inNumberFrames ioData:ioData];
}

- (bool) renderFrames: (UInt32) wantFrames
               ioData: (AudioBufferList *) ioData
{
    // 1. 将buffer数组全部置为0；
    for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
        AudioBuffer audioBuffer = ioData->mBuffers[iBuffer];
        bzero(audioBuffer.mData, audioBuffer.mDataByteSize);
    }
    
    ///目标是Packet类型
    if(self.targetSampleFormat == MR_SAMPLE_FMT_S16
       || self.targetSampleFormat == MR_SAMPLE_FMT_FLT){
    
        //    numFrames = 1115
        //    SInt16 = 2;
        //    mNumberChannels = 2;
        //    ioData->mBuffers[iBuffer].mDataByteSize = 4460
        // 4460 = numFrames x SInt16 * mNumberChannels = 1115 x 2 x 2;
        
        // 2. 获取 AudioUnit 的 Buffer
        int numberBuffers = ioData->mNumberBuffers;
        
        // AudioUnit 对于 packet 形式的PCM，只会提供一个 AudioBuffer
        if (numberBuffers >= 1) {
            
            AudioBuffer audioBuffer = ioData->mBuffers[0];
            //这个是 AudioUnit 给我们提供的用于存放采样点的buffer
            uint8_t *buffer = audioBuffer.mData;
            // 长度可以这么计算，也可以使用 audioBuffer.mDataByteSize 获取
            //                ///每个采样点占用的字节数:
            //                UInt32 bytesPrePack = self.outputFormat.mBitsPerChannel / 8;
            //                ///Audio的Frame是包括所有声道的，所以要乘以声道数；
            //                const NSUInteger frameSizeOf = 2 * bytesPrePack;
            //                ///向缓存的音频帧索要wantBytes个音频采样点: wantFrames x frameSizeOf
            //                NSUInteger bufferSize = wantFrames * frameSizeOf;
            const UInt32 bufferSize = audioBuffer.mDataByteSize;
            /* 对于 AV_SAMPLE_FMT_S16 而言，采样点是这么分布的:
             S16_L,S16_R,S16_L,S16_R,……
             AudioBuffer 也需要这样的排列格式，因此直接copy即可；
             同理，对于 FLOAT 也是如此左右交替！
             */
            
            ///3. 获取 bufferSize 个字节，并塞到 buffer 里；
            [self fetchPacketSample:buffer wantBytes:bufferSize];
        } else {
            NSLog(@"what's wrong?");
        }
    }
    
    ///目标是Planar类型，Mac平台支持整形和浮点型，交错和二维平面
    else if (self.targetSampleFormat == MR_SAMPLE_FMT_FLTP || self.targetSampleFormat == MR_SAMPLE_FMT_S16P){
        
        //    numFrames = 558
        //    float = 4;
        //    ioData->mBuffers[iBuffer].mDataByteSize = 2232
        // 2232 = numFrames x float = 558 x 4;
        // FLTP = FLOAT + Planar;
        // FLOAT: 具体含义是使用 float 类型存储量化的采样点，比 SInt16 精度要高出很多！当然空间也大些！
        // Planar: 二维的，所以会把左右声道使用两个数组分开存储，每个数组里的元素是同一个声道的！
        
        //when _outputFormat.mChannelsPerFrame == 2
        if (ioData->mNumberBuffers == 2) {
            // 2. 向缓存的音频帧索要 ioData->mBuffers[0].mDataByteSize 个字节的数据
            /*
             Float_L,Float_L,Float_L,Float_L,……  -> mBuffers[0].mData
             Float_R,Float_R,Float_R,Float_R,……  -> mBuffers[1].mData
             左对左，右对右
             
             同理，对于 S16P 也是如此！一一对应！
             */
            //3. 获取左右声道数据
            [self fetchPlanarSample:ioData->mBuffers[0].mData leftSize:ioData->mBuffers[0].mDataByteSize right:ioData->mBuffers[1].mData rightSize:ioData->mBuffers[1].mDataByteSize];
        }
        //when _outputFormat.mChannelsPerFrame == 1;不会左右分开
        else {
            [self fetchPlanarSample:ioData->mBuffers[0].mData leftSize:ioData->mBuffers[0].mDataByteSize right:NULL rightSize:0];
        }
    }
    return noErr;
}

- (bool) fetchPacketSample:(uint8_t*)buffer
                 wantBytes:(UInt32)bufferSize
{
    mr_fetch_packet_sample(self.player, buffer, bufferSize);
    return noErr;
}

- (bool) fetchPlanarSample:(uint8_t*)left
                  leftSize:(UInt32)leftSize
                     right:(uint8_t*)right
                 rightSize:(UInt32)rightSize
{
    mr_fetch_planar_sample(self.player, left, leftSize, right, rightSize);
    return noErr;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
//    stream_open("");
    
    [[AVAudioSession sharedInstance] setPreferredSampleRate:48000 error:nil];
    
    _targetSampleRate = [[AVAudioSession sharedInstance]sampleRate];
    
    mr_init_params *params = malloc(sizeof(mr_init_params));
    bzero(params, sizeof(mr_init_params));
    params->url = "http://localhost/movies/%e5%82%b2%e6%85%a2%e4%b8%8e%e5%81%8f%e8%a7%81.BD1280%e8%b6%85%e6%b8%85%e5%9b%bd%e8%8b%b1%e5%8f%8c%e8%af%ad%e4%b8%ad%e8%8b%b1%e5%8f%8c%e5%ad%97.mp4";
    params->url = "http://localhost/ffmpeg-test/sintel.mp4";
    params->url = "http://localhost/ffmpeg-test/xp5.mp4";
    
    params->msg_func = &msgFunc;
    params->msg_func_ctx = (__bridge void *)self;
    params->supported_sample_rate = _targetSampleRate;
    params->supported_sample_fmts = MR_SAMPLE_FMT_S16P | MR_SAMPLE_FMT_S16 | MR_SAMPLE_FMT_FLTP | MR_SAMPLE_FMT_FLT;
    
    MRPlayer player = mr_player_instance_create(params);
    mr_set_display_func(player,(__bridge void *)self, displayFunc);
    mr_prepare_play(player);
    self.player = player;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
