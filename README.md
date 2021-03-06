[![](md/imgs/ffmpeg.png)](http://ffmpeg.org/) 


> 从我个人的经验来看使用 **FFmpeg** 封装一个播放器，是有一定门槛的，为了让更多零基础的 iOS/macOS 开发人员少走弯路，我编写了这个教程。

# Foreword

本工程是笔者 2017 年创建的，原本是想把 kxmovie 的源码比葫芦画瓢自己写一遍，以此来熟悉 FFmpeg 的 API，了解播放器内部实现细节，谁料想在学习的过程中萌生了自己封装播放器的想法...

3 年期间虽然摸索出了多种音视频渲染方法，但终究没有完成原定目标！于 2020 年年初从零重写该项目，工程采用 Pod 开发库（Development Pod）的形式来组织，所有教程均提供 iOS 和 macOS 的调用实例，封装代码都放在 FFmpegTutorial 里，该开发库依赖了 [MRFFmpegPod](https://github.com/debugly/MRFFToolChainPod) 等库。

开发语言为 Objective-C，工程目录结构如下：

```
├── Example
│   ├── iOS //iOS 配套demo
│   │   ├── FFmpegTutorial-iOS
│   │   ├── FFmpegTutorial-iOS.xcodeproj
│   │   ├── FFmpegTutorial-iOS.xcworkspace
│   │   ├── Podfile
│   │   ├── Podfile.lock
│   │   ├── Pods
│   │   └── Tests
│   └── macOS //macOS 配套demo
│       ├── FFmpegTutorial-macOS
│       ├── FFmpegTutorial-macOS.xcodeproj
│       ├── FFmpegTutorial-macOS.xcworkspace
│       ├── Podfile
│       ├── Podfile.lock
│       └── Pods
├── FFmpegTutorial // demo工程依赖了这个 Development Pod
│   └── Classes
│       ├── 0x01  //具体教程源码
│       ├── 0x02
│       ├── 0x03
│       ├── 0x04
│       ├── 0x05
│       ├── 0x06
│       ├── 0x10
│       ├── 0x11
│       ├── 0x12
│       ├── 0x13
│       ├── 0x14
│       ├── 0x15
│       ├── 0x20
│       ├── 0x21
│       ├── 0x22
│       ├── 0x30
│       ├── 0x31
│       ├── 0x32
│       ├── 0x40
│       └── common //通用类
├── FFmpegTutorial.podspec
├── LICENSE
├── README.md
└── md  //教程配套文档
    ├── 0x00.md
    ├── 0x01.md
    ├── 0x02.md
    ├── 0x03.md
    ├── 0x04.md
    ├── 0x05.md
    ├── 0x06.md
    ├── 0x10.md
    ├── 0x11.md
    ├── illiteracy
    │   ├── 0x01.md
    │   ├── 0x02.md
    │   ├── 0x03.md
    │   ├── 0x04-todo.md
    │   ├── 0x04.md
    │   └── imgs
    ├── imgs
    │   ├── 004-1.jpg
    │   ├── 03-path.jpeg
    │   ├── 0x01
    │   ├── 0x02
    │   ├── 0x07
    │   ├── MR-16-9.png
    │   ├── ffmpeg.png
    │   ├── gray-bar.png
    │   └── snow.jpg
    └── todo
        ├── 0x04.md
        ├── 0x05.md
        ├── 0x07.md
        ├── 0x08.md
        ├── 0x12-1.md
        ├── 0x12.md
        ├── 0x13.md
        └── 0xF0.md
```

# Anti-Illiteracy

- 0x01：[常见封装格式介绍](md/illiteracy/0x01.md)
- 0x02：[播放器总体架构设计](md/illiteracy/0x02.md)
- 0x03：[封装 NSThread，支持 join](md/illiteracy/0x03.md)
- 0x04：[AVFrame 内存管理分析](md/illiteracy/0x04.md)

# Tutorials

音视频基础，解码队列，解码器

- 0x00：[FFmpeg简介及编译方法](md/0x00.md) 
- 0x01：[查看编译时配置信息、支持的协议、版本号](md/0x01.md)
- 0x02：[查看音视频码流基础信息](md/0x02.md)
- 0x03：[读包线程与 AVPacket 缓存队列](md/0x03.md)
- 0x04：[多线程解码](md/0x04.md)
- 0x05：[渲染线程与 AVFrame 缓存队列](md/0x05.md)
- 0x06：[整理代码，封装解码器](md/0x06.md)

渲染视频帧

- 0x10：[使用 Core Graphics 渲染视频帧](md/0x10.md)
- 0x11：[使用 Core Animation 渲染视频帧](md/0x11.md)
- 0x12：[使用 Core Image 渲染视频帧]
- 0x13：[使用 Core Video 渲染视频帧]
- 0x14：[使用 OpenGL ES 渲染视频帧]

渲染音频采样

- 0x20：[使用 AudioUnit 渲染音频桢，支持 S16,S16P,FLT,FLTP 四种采样深度格式]

- 0x21：[使用 AudioQueue 渲染音频桢，支持 S16,FLT 两种采样深度格式]

- 0x22：[封装音频渲染器，屏蔽内部实现细节]

封装播放器

- 0x30：[音视频同步]
- 0x31：[支持播放和暂停]
- 0x32：[显示播放进度和时长]

## Tools

通过上面教程的学习，对 FFmpeg 有了一定的了解，写了下面几个小工具：

- 视频抽帧器：抽取视频关键帧图片，非常高效，开源地址：[MRVideoToPicture](https://github.com/debugly/MRVideoToPicture)。

# TODO

- 0x15：[使用 Metal 渲染视频帧]
- 0x33：[支持 seek]
- 0x34：[支持从指定位置开始播放]
- 0x35：[封装 MRMoviePlayer 播放器]

Just For Fun

- 0x41：[黑白电视机雪花屏、灰色色阶图] 

### Cross-platform

本教程的终极目标是写一款 **跨平台播放器**，理想很丰满，现实很骨感，这是一项庞大的工程，我会分四个阶段来完成，计划如下：

第一阶段：先完成 iOS 平台的播放，由于没写过播放器，因此代码可能不是很成熟，前期改动可能会多些，以弥补思考不严密与规划不正确带来的问题。从长远来讲为了实现跨平台，不应当使用 Cocoa 特有的技术，比如 NSThread，GCD等，这完全是给自己挖坑😂！但是为了照顾广大 iOS 开发者零基础入门，我还是放弃了 C++ Thread 或 pthread 等实现方式，从而降低学习的门槛，让大家不用去学那么多乱七八糟的东西。

第二阶段：移植到 macOS 平台，这一阶段需要处理平台特有接口，主要是视频渲染方面的，另外需要考虑后续的移植问题，设计出优良的方便移植的接口。移植完毕后考虑学习下使用 MetalKit 渲染，和 VideoToolbox 硬解等。

第三阶段：移植到 Android 平台，这个阶段的主要问题是将前两个阶段使用的 Cocoa API 替换成跨平台 API，主要包括线程和锁，还要学习 JNI 调用，音视频如何渲染，重新创建配套的 Demo 工程，学习如何管理依赖（有没有 Cocoapods 一样的工具呢？）...

第四阶段：移植到 Windows 平台，好多年没有使用 Windows 系统了，有余力了搞下。

# Usage

克隆该仓库之后，项目并不能运行起来，因为项目依赖的 [MRFFmpegPod](https://github.com/debugly/MRFFToolChainPod) 等库还没有下载下来，

1、运行 iOS demo 需要执行:

**pod install --project-directory=Example/iOS**

成功安装后就可以打开 **Example/iOS/FFmpegTutorial-iOS.xcworkspace** 运行了，支持模拟器和真机！

运行 macOS demo 需要执行:

**pod install --project-directory=Example/macOS**

成功安装后就可以打开 **Example/iOS/FFmpegTutorial-macOS.xcworkspace** 运行了。

## Ends

- Please give me an issue or a star or pull request！
- New members are always welcome!

Good Luck,Thank you！
