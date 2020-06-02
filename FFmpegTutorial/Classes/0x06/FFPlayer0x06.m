//
//  FFPlayer0x06.m
//  FFmpegTutorial
//
//  Created by qianlongxu on 2020/5/21.
//

#import "FFPlayer0x06.h"
#import "MRThread.h"
#import "FFPlayerInternalHeader.h"
#import "FFPlayerPacketHeader.h"
#import "FFPlayerFrameHeader.h"

#include <libavutil/pixdesc.h>

@class FFDecoder0x06;
@protocol FFDecoderDelegate0x06 <NSObject>

- (int)decoder:(FFDecoder0x06 *)decoder fetchPacket:(AVPacket * )packet;

@end

@interface FFDecoder0x06 : NSObject

@property (atomic, assign) int streamIdx;
@property (nonatomic, assign) AVStream * stream;
@property (nonatomic, assign) AVCodecContext * avctx;
///解码线程
@property (nonatomic, strong) MRThread * workThread;
@property (nonatomic, copy) NSString * name;
@property (atomic, assign) int abort_request;

@property (nonatomic, weak) id <FFDecoderDelegate0x06> delegate;

//开始解码
- (void)start;
//取消解码
- (void)cancel;
//解码前的准备
- (void)prepare;

@end

@implementation FFDecoder0x06

- (void)dealloc
{
    //释放解码器上下文
    if (_avctx) {
        avcodec_free_context(&_avctx);
        _avctx = NULL;
    }
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _streamIdx = -1;
    }
    return self;
}

- (void)start
{
    if (self.workThread) {
        self.workThread.name = self.name;
        [self.workThread start];
    }
}

- (void)cancel
{
    if (self.workThread) {
        [self.workThread cancel];
        [self.workThread join];
        self.workThread = nil;
    }
}

- (void)prepare
{
    self.workThread = [[MRThread alloc] initWithTarget:self selector:@selector(workFunc) object:nil];
}

#pragma mark - 音视频通用解码方法

- (int)decodeAFrame:(AVCodecContext *)avctx result:(AVFrame*)frame
{
    for (;;) {
        int ret;
        do {
            //停止时，直接返回
            if (self.abort_request){
                return -1;
            }
            
            //先尝试接收帧
            ret = avcodec_receive_frame(avctx, frame);
            
            //成功接收到一个解码帧
            if (ret >= 0){
                return 1;
            }
            
            //结束标志，此次并没有获取到frame！
            if (ret == AVERROR_EOF) {
                avcodec_flush_buffers(avctx);
                return AVERROR_EOF;
            }
            
        } while (ret != AVERROR(EAGAIN)/*需要更多packet数据*/);
        
        AVPacket pkt;
        
        //[阻塞等待]直到获取一个packet
        int r = -1;
        if ([self.delegate respondsToSelector:@selector(decoder:fetchPacket:)]) {
            r = [self.delegate decoder:self fetchPacket:&pkt];
        }
        
        if (r < 0)
        {
            return -1;
        }
        
        //发送给解码器去解码
        if (avcodec_send_packet(avctx, &pkt) == AVERROR(EAGAIN)) {
            av_log(avctx, AV_LOG_ERROR, "Receive_frame and send_packet both returned EAGAIN, which is an API violation.\n");
        }
        //释放内存
        av_packet_unref(&pkt);
    }
}

#pragma mark - 解码线程

- (void)workFunc
{
    //创建一个frame就行了，可以复用
    AVFrame *frame = av_frame_alloc();
    if (!frame) {
        av_log(NULL, AV_LOG_ERROR, "can't alloc a frame.");
        return;
    }
    do {
        //使用通用方法解码音频队列
        int got_frame = [self decodeAFrame:self.avctx result:frame];
        //解码出错
        if (got_frame < 0) {
            if (got_frame == AVERROR_EOF) {
                av_log(NULL, AV_LOG_ERROR, "decode frame eof.");
            } else if (self.abort_request){
                av_log(NULL, AV_LOG_ERROR, "cancel decoder.");
            } else {
                av_log(NULL, AV_LOG_ERROR, "can't decode frame.");
            }
            break;
        } else {
            //正常解码
            av_log(NULL, AV_LOG_VERBOSE, "decode a audio frame:%lld\n",frame->pts);
            sleep(1);
        }
    } while (1);
    
    //释放内存
    if (frame) {
        av_frame_free(&frame);
    }
}

@end

@interface  FFPlayer0x06 ()<FFDecoderDelegate0x06>
{
    //解码前的音频包缓存队列
    PacketQueue audioq;
    //解码前的视频包缓存队列
    PacketQueue videoq;
    
    //解码后的音频帧缓存队列
    FrameQueue sampq;
    //解码后的视频帧缓存队列
    FrameQueue pictq;
    
    //读包完毕？
    int eof;
}

///读包线程
@property (nonatomic, strong) MRThread *readThread;
///渲染线程
@property (nonatomic, strong) MRThread *rendererThread;

//音频解码器
@property (nonatomic, strong) FFDecoder0x06 *audioDecoder;
//视频解码器
@property (nonatomic, strong) FFDecoder0x06 *videoDecoder;


@property (atomic, assign) int abort_request;
@property (nonatomic, copy) dispatch_block_t onErrorBlock;
@property (nonatomic, copy) dispatch_block_t onPacketBufferFullBlock;
@property (nonatomic, copy) dispatch_block_t onPacketBufferEmptyBlock;
@property (atomic, assign) BOOL packetBufferIsFull;
@property (atomic, assign) BOOL packetBufferIsEmpty;

@end

@implementation  FFPlayer0x06

static int decode_interrupt_cb(void *ctx)
{
    FFPlayer0x06 *player = (__bridge FFPlayer0x06 *)ctx;
    return player.abort_request;
}

- (void)_stop
{
    ///避免重复stop做无用功
    if (self.readThread) {
        
        self.abort_request = 1;
        audioq.abort_request = 1;
        videoq.abort_request = 1;
        sampq.abort_request = 1;
        pictq.abort_request = 1;
        
        [self.readThread cancel];
        [self.readThread join];
        self.readThread = nil;
        
        [self.rendererThread cancel];
        [self.rendererThread join];
        self.rendererThread = nil;
        
        [self.audioDecoder cancel];
        [self.videoDecoder cancel];
        
        packet_queue_destroy(&audioq);
        packet_queue_destroy(&videoq);
        
        frame_queue_destory(&pictq);
        frame_queue_destory(&sampq);
    }
}

- (void)dealloc
{
    [self _stop];
}

///准备
- (void)prepareToPlay
{
    if (self.readThread) {
        NSAssert(NO, @"不允许重复创建");
    }
    
    ///初始化视频包队列
    packet_queue_init(&videoq);
    ///初始化音频包队列
    packet_queue_init(&audioq);
    ///初始化ffmpeg相关函数
    init_ffmpeg_once();
    
    ///初始化视频帧队列
    frame_queue_init(&pictq, VIDEO_PICTURE_QUEUE_SIZE, "pictq");
    ///初始化音频帧队列
    frame_queue_init(&sampq, SAMPLE_QUEUE_SIZE, "sampq");
    
    self.readThread = [[MRThread alloc] initWithTarget:self selector:@selector(readPacketsFunc) object:nil];
    self.readThread.name = @"readPackets";
}

#pragma mark - 打开解码器创建解码线程

- (int)openStreamComponent:(AVFormatContext *)ic streamIdx:(int)idx
{
    if (ic == NULL) {
        return -1;
    }
    
    if (idx < 0 || idx >= ic->nb_streams){
        return -1;
    }
    
    AVStream *stream = ic->streams[idx];
    
    //创建解码器上下文
    AVCodecContext *avctx = avcodec_alloc_context3(NULL);
    if (!avctx) {
        return AVERROR(ENOMEM);
    }
    
    //填充下相关参数
    if (avcodec_parameters_to_context(avctx, stream->codecpar)) {
        avcodec_free_context(&avctx);
        return -1;
    }
    
    av_codec_set_pkt_timebase(avctx, stream->time_base);
    
    //查找解码器
    AVCodec *codec = avcodec_find_decoder(avctx->codec_id);
    if (!codec){
        avcodec_free_context(&avctx);
        return -1;
    }
    
    avctx->codec_id = codec->id;
    
    //打开解码器
    if (avcodec_open2(avctx, codec, NULL)) {
        avcodec_free_context(&avctx);
        return -1;
    }
    
    stream->discard = AVDISCARD_DEFAULT;
    
    //根据流类型，准备相关线程
    switch (avctx->codec_type) {
        case AVMEDIA_TYPE_AUDIO:
        {
            //创建音频解码器
            [self prepareAudioDecoder:stream->index stream:stream avctx:avctx];
        }
            break;
        case AVMEDIA_TYPE_VIDEO:
        {
            //创建视频解码器
           [self prepareVideoDecoder:stream->index stream:stream avctx:avctx];
        }
            break;
        default:
            break;
    }
    return 0;
}

#pragma -mark 读包线程

//读包循环
- (void)readPacketLoop:(AVFormatContext *)formatCtx {
    AVPacket pkt1, *pkt = &pkt1;
    ///循环读包
    for (;;) {
        
        ///调用了stop方法，则不再读包
        if (self.abort_request) {
            break;
        }
        
        /* 队列不满继续读，满了则休眠10 ms */
        if (audioq.size + videoq.size > MAX_QUEUE_SIZE
            || (stream_has_enough_packets(self.audioDecoder.stream, self.audioDecoder.streamIdx, &audioq) &&
                stream_has_enough_packets(self.videoDecoder.stream, self.videoDecoder.streamIdx, &videoq))) {
            
            if (!self.packetBufferIsFull) {
                self.packetBufferIsFull = YES;
                if (self.onPacketBufferFullBlock) {
                    self.onPacketBufferFullBlock();
                }
            }
            /* wait 10 ms */
            usleep(10000);
            continue;
        }
        
        self.packetBufferIsFull = NO;
        ///读包
        int ret = av_read_frame(formatCtx, pkt);
        ///读包出错
        if (ret < 0) {
            //读到最后结束了
            if ((ret == AVERROR_EOF || avio_feof(formatCtx->pb)) && !eof) {
                ///最后放一个空包进去
                if (self.audioDecoder.streamIdx >= 0) {
                    packet_queue_put_nullpacket(&videoq, self.audioDecoder.streamIdx);
                }
                    
                if (self.videoDecoder.streamIdx >= 0) {
                    packet_queue_put_nullpacket(&audioq, self.videoDecoder.streamIdx);
                }
                //标志为读包结束
                eof = 1;
            }
            
            if (formatCtx->pb && formatCtx->pb->error) {
                break;
            }
            /* wait 10 ms */
            usleep(10000);
            continue;
        } else {
            //音频包入音频队列
            if (pkt->stream_index == self.audioDecoder.streamIdx) {
                packet_queue_put(&audioq, pkt);
            }
            //视频包入视频队列
            else if (pkt->stream_index == self.videoDecoder.streamIdx) {
                packet_queue_put(&videoq, pkt);
            }
            //其他包释放内存忽略掉
            else {
                av_packet_unref(pkt);
            }
        }
    }
}

#pragma mark - 查找最优的音视频流
- (void)findBestStreams:(AVFormatContext *)formatCtx result:(int (*) [AVMEDIA_TYPE_NB])st_index {

    int first_video_stream = -1;
    int first_h264_stream = -1;
    //查找H264格式的视频流
    for (int i = 0; i < formatCtx->nb_streams; i++) {
        AVStream *st = formatCtx->streams[i];
        enum AVMediaType type = st->codecpar->codec_type;
        st->discard = AVDISCARD_ALL;

        if (type == AVMEDIA_TYPE_VIDEO) {
            enum AVCodecID codec_id = st->codecpar->codec_id;
            if (codec_id == AV_CODEC_ID_H264) {
                if (first_h264_stream < 0) {
                    first_h264_stream = i;
                    break;
                }
                if (first_video_stream < 0) {
                    first_video_stream = i;
                }
            }
        }
    }
    //h264优先
    (*st_index)[AVMEDIA_TYPE_VIDEO] = first_h264_stream != -1 ? first_h264_stream : first_video_stream;
    //根据上一步确定的视频流查找最优的视频流
    (*st_index)[AVMEDIA_TYPE_VIDEO] = av_find_best_stream(formatCtx, AVMEDIA_TYPE_VIDEO, (*st_index)[AVMEDIA_TYPE_VIDEO], -1, NULL, 0);
    //参照视频流查找最优的音频流
    (*st_index)[AVMEDIA_TYPE_AUDIO] = av_find_best_stream(formatCtx, AVMEDIA_TYPE_AUDIO, (*st_index)[AVMEDIA_TYPE_AUDIO], (*st_index)[AVMEDIA_TYPE_VIDEO], NULL, 0);
}

- (void)readPacketsFunc
{
    if (![self.contentPath hasPrefix:@"/"]) {
            _init_net_work_once();
        }
        
        AVFormatContext *formatCtx = avformat_alloc_context();
        
        if (!formatCtx) {
            self.error = _make_nserror_desc(FFPlayerErrorCode_AllocFmtCtxFailed, @"Could not allocate context.");
            [self performErrorResultOnMainThread];
            return;
        }
        
        formatCtx->interrupt_callback.callback = decode_interrupt_cb;
        formatCtx->interrupt_callback.opaque = (__bridge void *)self;
        
        /*
         打开输入流，读取文件头信息，不会打开解码器；
         */
        ///低版本是 av_open_input_file 方法
        const char *moviePath = [self.contentPath cStringUsingEncoding:NSUTF8StringEncoding];
        
        //打开文件流，读取头信息；
        if (0 != avformat_open_input(&formatCtx, moviePath , NULL, NULL)) {
            ///释放内存
            avformat_free_context(formatCtx);
            //当取消掉时，不给上层回调
            if (self.abort_request) {
                return;
            }
            self.error = _make_nserror_desc(FFPlayerErrorCode_OpenFileFailed, @"文件打开失败！");
            [self performErrorResultOnMainThread];
            return;
        }
        
        /* 刚才只是打开了文件，检测了下文件头而已，并不知道流信息；因此开始读包以获取流信息
         设置读包探测大小和最大时长，避免读太多的包！
        */
        formatCtx->probesize = 500 * 1024;
        formatCtx->max_analyze_duration = 5 * AV_TIME_BASE;
    #if DEBUG
        NSTimeInterval begin = [[NSDate date] timeIntervalSinceReferenceDate];
    #endif
        if (0 != avformat_find_stream_info(formatCtx, NULL)) {
            avformat_close_input(&formatCtx);
            self.error = _make_nserror_desc(FFPlayerErrorCode_StreamNotFound, @"不能找到流！");
            [self performErrorResultOnMainThread];
            //出错了，销毁下相关结构体
            avformat_close_input(&formatCtx);
            return;
        }
        
    #if DEBUG
        NSTimeInterval end = [[NSDate date] timeIntervalSinceReferenceDate];
        ///用于查看详细信息，调试的时候打出来看下很有必要
        av_dump_format(formatCtx, 0, moviePath, false);
        
        NSLog(@"avformat_find_stream_info coast time:%g",end-begin);
    #endif
        
        //确定最优的音视频流
        int st_index[AVMEDIA_TYPE_NB];
        memset(st_index, -1, sizeof(st_index));
        [self findBestStreams:formatCtx result:&st_index];
        
        //打开解码器，创建解码线程
        if (st_index[AVMEDIA_TYPE_AUDIO] >= 0){
            if([self openStreamComponent:formatCtx streamIdx:st_index[AVMEDIA_TYPE_AUDIO]]){
                av_log(NULL, AV_LOG_ERROR, "can't open audio stream.");
                self.error = _make_nserror_desc(FFPlayerErrorCode_StreamOpenFailed, @"音频流打开失败！");
                [self performErrorResultOnMainThread];
                //出错了，销毁下相关结构体
                avformat_close_input(&formatCtx);
                return;
            }
        }
        
        if (st_index[AVMEDIA_TYPE_VIDEO] >= 0){
            if([self openStreamComponent:formatCtx streamIdx:st_index[AVMEDIA_TYPE_VIDEO]]){
                av_log(NULL, AV_LOG_ERROR, "can't open video stream.");
                self.error = _make_nserror_desc(FFPlayerErrorCode_StreamOpenFailed, @"视频流打开失败！");
                [self performErrorResultOnMainThread];
                //出错了，销毁下相关结构体
                avformat_close_input(&formatCtx);
                return;
            }
        }
        
        //音视频解码线程开始工作
        [self.audioDecoder start];
        [self.videoDecoder start];
        //准备渲染线程
        [self prepareRendererThread];
        //渲染线程开始工作
        [self.rendererThread start];
        //循环读包
        [self readPacketLoop:formatCtx];
        ///读包线程结束了，销毁下相关结构体
        avformat_close_input(&formatCtx);
}

#pragma mark - FFDecoderDelegate0x06

- (int)decoder:(FFDecoder0x06 *)decoder fetchPacket:(AVPacket *)pkt
{
    if (decoder == self.audioDecoder) {
        return packet_queue_get(&audioq, pkt, 1);
    } else if (decoder == self.videoDecoder) {
        return packet_queue_get(&videoq, pkt, 1);
    } else {
        return -1;
    }
}

#pragma mark - 音视频解码器

- (void)prepareAudioDecoder:(int)idx stream:(AVStream *)stream avctx:(AVCodecContext *)avctx
{
    FFDecoder0x06 *decoder = [FFDecoder0x06 new];
    decoder.avctx = avctx;
    decoder.stream = stream;
    decoder.streamIdx = idx;
    decoder.delegate = self;
    decoder.name = @"audioDecoder";
    [decoder prepare];
    self.audioDecoder = decoder;
}

- (void)prepareVideoDecoder:(int)idx stream:(AVStream *)stream avctx:(AVCodecContext *)avctx
{
    FFDecoder0x06 *decoder = [FFDecoder0x06 new];
    decoder.avctx = avctx;
    decoder.stream = stream;
    decoder.streamIdx = idx;
    decoder.delegate = self;
    decoder.name = @"videoDecoder";
    [decoder prepare];
    self.videoDecoder = decoder;
}

#pragma mark - RendererThread

- (void)prepareRendererThread
{
    self.rendererThread = [[MRThread alloc] initWithTarget:self selector:@selector(rendererThreadFunc) object:nil];
    self.rendererThread.name = @"renderer";
}

- (void)rendererThreadFunc
{
    ///调用了stop方法，，则不再渲染
    while (!self.abort_request) {
        
        //队列里缓存帧大于0，则取出
        if (frame_queue_nb_remaining(&sampq) > 0) {
            Frame *ap = frame_queue_peek(&sampq);
            av_log(NULL, AV_LOG_VERBOSE, "render audio frame %lld\n", ap->frame->pts);
            //释放该节点存储的frame的内存
            frame_queue_pop(&sampq);
        }
        
        if (frame_queue_nb_remaining(&pictq) > 0) {
            Frame *vp = frame_queue_peek(&pictq);
            av_log(NULL, AV_LOG_VERBOSE, "render video frame %lld\n", vp->frame->pts);
            frame_queue_pop(&pictq);
        }
        
        usleep(1000 * 40);
    }
}

- (void)performErrorResultOnMainThread
{
    if (![NSThread isMainThread]) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (self.onErrorBlock) {
                self.onErrorBlock();
            }
        }];
    } else {
        if (self.onErrorBlock) {
            self.onErrorBlock();
        }
    }
}

- (void)readPacket
{
    [self.readThread start];
}

- (void)stop
{
    [self _stop];
}

- (void)onError:(dispatch_block_t)block
{
    self.onErrorBlock = block;
}

- (void)onPacketBufferFull:(dispatch_block_t)block
{
    self.onPacketBufferFullBlock = block;
}

- (void)onPacketBufferEmpty:(dispatch_block_t)block
{
    self.onPacketBufferEmptyBlock = block;
}

- (NSString *)peekPacketBufferStatus
{
    return [NSString stringWithFormat:@"Packet Buffer is%@Full，audio(%d)，video(%d)",self.packetBufferIsFull ? @" " : @" not ",audioq.nb_packets,videoq.nb_packets];
}

@end