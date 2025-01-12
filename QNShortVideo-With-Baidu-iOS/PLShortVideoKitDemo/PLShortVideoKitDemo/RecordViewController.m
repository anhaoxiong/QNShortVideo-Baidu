//
//  BARBusinessViewController.m
//  ARAPP-FaceDemo
//
//  Created by Zhao,Xiangkai on 2018/7/5.
//  Copyright © 2018年 Zhao,Xiangkai. All rights reserved.
//

#import "RecordViewController.h"
#import <PLShortVideoKit/PLShortVideoKit.h>

#if defined (__arm64__)
#import <ARSDKProOpenSDK/ARSDKProOpenSDK.h>
#import "DARRenderViewController.h"
#import "BARBaseView.h"
#import "BARBaseView+ARLogic.h"
#import "DARFiltersController.h"
#import "BARShareViewControllers.h"
#import "DarFaceAlgoModleParse.h"
#import "DARFaceDecalsController.h"
#import "EditViewController.h"
#import "BARGestureView.h"

#define IPAD     (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
#define ASPECT_RATIO (IPAD ? (4.0/3.0) : (16.0/9.0))

#define SHOULD_MIRROR 1  //是否要根据设备方向做镜像

#define FILTER_RATIO  0.8  //滤镜透明度所乘的比例系数

#define SAMPLE_BUffER_LAYER 1

typedef NS_ENUM(NSUInteger, BARDeviceType) {
    BARDeviceTypeLow,
    BARDeviceTypeMedium,
    BARDeviceTypeHigh,
    BARDeviceTypeUnknow
};

@interface RecordViewController ()<UINavigationControllerDelegate, UIAlertViewDelegate, BARARKitModuleDelegate, BARGestureImageViewDelegate, PLShortVideoRecorderDelegate>
{
    BOOL _recording;
}

/**
 UI
 */
@property (nonatomic, strong) BARBaseView *baseUIView;
@property (nonatomic, strong) UIView *replacedView;
//@property (nonatomic, strong) AVSampleBufferDisplayLayer *bufferLayer;

/**
 AR
 */
@property (nonatomic,strong) BARMainController *arController;//AR控制器
//@property (nonatomic, strong) BARVideoRecorder *videoRecorder;//AR视频录制
@property (nonatomic, strong) BARARKitModule *arkitModule;//ARKit相机

/**
 人脸
 */
@property (nonatomic, assign) BOOL isFirstShowDecal;
@property (nonatomic, assign) BOOL loadFirstAssetsFinished;
@property (nonatomic, assign) BOOL isFaceAssetsLoaded;
@property (nonatomic, assign) BOOL isFaceTrackLoadingSucceed;
@property (nonatomic, assign) BOOL isFaceTrackingSucceed;
//@property(nonatomic, assign) NSUInteger frameReadyCount;
@property (nonatomic, strong) NSMutableDictionary *faceBeautyLastValueDic;
@property (nonatomic, assign) CGFloat filterLastValue;
@property (nonatomic, copy) NSString *currentTrigger;
@property (nonatomic, copy) NSString *currentBeauty;
@property (nonatomic, strong) DARFaceDecalsController *faceDecalsController;
@property (nonatomic, strong) DARFiltersController *filtersController;
@property (nonatomic, assign) BOOL isManualFocus;
@property (nonatomic, strong) NSString *currentFilterID;

/**
 组件
 */
@property (nonatomic, strong) id voiceConfigure;//语音识别能力组件

/**
 其他属性
 */
@property (nonatomic, copy) NSString *arKey;
@property (nonatomic, copy) NSString *arType;
@property (assign, nonatomic) BOOL viewAppearDoneAtLeastOnce;
@property (nonatomic, assign) BOOL hasPendingGotoShare;
@property (nonatomic, assign) BOOL willGoToShare;
//@property (nonatomic, assign) BOOL needDelayChangeToARView;


@property (nonatomic, strong) DarFaceAlgoModleParse *darFaceAlgoModleParse;
@property (nonatomic, assign) CFAbsoluteTime m_lastRenderTime;

@property (nonatomic, strong) NSDictionary *demo_trigger_config_list;


@property (assign, nonatomic) CMSampleBufferRef lastARSample;

@property (strong, nonatomic) BARGestureView *gestureView;

// ==== 七牛 =====
@property (strong, nonatomic) PLSVideoConfiguration *videoConfiguration;
@property (strong, nonatomic) PLSAudioConfiguration *audioConfiguration;
@property (strong, nonatomic) PLShortVideoRecorder *shortVideoRecorder;

@end

@implementation RecordViewController

#pragma mark - Lifecycle

/**
 ReadMe：
 case的几个操作流程如下：
 加载AR --> 下载AR资源包并且加载AR
 启动AR --> 加载AR成功后，调用startAR
 */

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setupShortVideoRecorder];
    
    if([BARSDKPro isSupportAR]){
        [self setUpNotifications];//设置通知
        [self loadFaceData];//设置人脸资源
        [self setupARView];//设置ARView
        [self setupUIView];//设置UI
        
        AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        if (status == AVAuthorizationStatusDenied) {
            [self showalert:@"请在设置中打开相机权限"];
        } else if(status == AVAuthorizationStatusAuthorized) {
            [self cameraAuthorizedFinished];
        } else if(status == AVAuthorizationStatusNotDetermined) {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (granted) {
                        [self cameraAuthorizedFinished];
                    } else {
                        [self showalert:@"请在设置中打开相机权限"];
                    }
                });
            }];
        } else {
            [self showalert:@"请在设置中打开相机权限"];
        }
    }
}

// 短视频录制核心类设置
- (void)setupShortVideoRecorder {
    
    // SDK 的版本信息
    NSLog(@"PLShortVideoRecorder versionInfo: %@", [PLShortVideoRecorder versionInfo]);
    
    // SDK 授权信息查询
    [PLShortVideoRecorder checkAuthentication:^(PLSAuthenticationResult result) {
        NSString *authResult[] = {@"NotDetermined", @"Denied", @"Authorized"};
        NSLog(@"PLShortVideoRecorder auth status: %@", authResult[result]);
    }];
    
    self.videoConfiguration = [PLSVideoConfiguration defaultConfiguration];
    self.videoConfiguration.position = AVCaptureDevicePositionFront;
    self.videoConfiguration.videoFrameRate = 30;
    self.videoConfiguration.videoSize = CGSizeMake(720, 1280);
    self.videoConfiguration.averageVideoBitRate = 4 * 1000 * 1000;
    self.videoConfiguration.videoOrientation = AVCaptureVideoOrientationPortrait;
    self.videoConfiguration.sessionPreset = AVCaptureSessionPreset1280x720;
    
    self.audioConfiguration = [PLSAudioConfiguration defaultConfiguration];
    
    self.shortVideoRecorder = [[PLShortVideoRecorder alloc] initWithVideoConfiguration:self.videoConfiguration audioConfiguration:self.audioConfiguration];
    self.shortVideoRecorder.delegate = self;
    self.shortVideoRecorder.maxDuration = 10.0f; // 设置最长录制时长
    [self.shortVideoRecorder setBeautifyModeOn:YES]; // 默认打开美颜
    self.shortVideoRecorder.outputFileType = PLSFileTypeMPEG4;
    self.shortVideoRecorder.innerFocusViewShowEnable = YES; // 显示 SDK 内部自带的对焦动画
    self.shortVideoRecorder.previewView.frame = self.view.bounds;
    self.shortVideoRecorder.touchToFocusEnable = NO;
    [self.view addSubview:self.shortVideoRecorder.previewView];
    self.shortVideoRecorder.backgroundMonitorEnable = NO;
}


- (void)cameraAuthorizedFinished{
    
    if (self.cameraToAR) {
        self.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    [self setupARController];//设置AR控制器
//    #error 设置申请的APPID、APIKey https://dumix.baidu.com/dumixar
    [BARSDKPro setAppID:@"25" APIKey:@"e0f9dd03f6ba90db7ef3582d2df1d496" andSecretKey:@""];//SecretKey可选
    NSString *version = [BARSDKPro arSdkVersion];
    NSLog(@"sdk version is %@",version);
    [self setupComponents];
}

- (void)setupComponents{
    /*
     [self setupARVoice];//设置语音组件（可选）
     [self setupTTS];//设置TTS组件（可选）
     */
    [self setupARKit];//设置ARKit（可选）
}

- (void)setupARKit {
    self.arkitModule = [[BARARKitModule alloc] init];
    self.arkitModule.arkitDelegate = self;
    [self.arkitModule setupARController:self.arController];
    [self.arkitModule setupARKitControllerWithRatio:ASPECT_RATIO];
}

-(void)viewDidDisappear:(BOOL)animated{
    [self.shortVideoRecorder stopCaptureSession];
    [super viewDidDisappear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:NO];
    if (self.navigationController) {
        self.navigationController.delegate = self;
    }
    
    if(self.viewAppearDoneAtLeastOnce) {
        
//        if(self.hasPendingGotoShare){
//            self.hasPendingGotoShare = NO;
//            [self goEditViewController];
//        }else{
            //首次进入不调用resumeAR，从预览页或其他页面回来才调用
            [self resumeAR];
//        }
    }else{
        self.viewAppearDoneAtLeastOnce = YES;
    }
    self.baseUIView.screenshotBtn.enabled = YES;
    
    [self.shortVideoRecorder startCaptureSession];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:NO];
    
    if (self.disappearBlock) {
        self.disappearBlock();
    }
    
    [self resetlightStatus];
    [self pauseAR];
    [[BARAlert sharedInstance]  dismiss];
    //    [[BARRouter sharedInstance] voice_stopVoiceWithConfigure:self.voiceConfigure];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (void)dealloc {
    if (self.arkitModule) {
        [self.arkitModule cleanARKitModule];
        self.arkitModule = nil;
    }
    //    [[BARRouter sharedInstance] voice_cleanUpWithConfigure:self.voiceConfigure];
    [self removeNotificationsObserver];
}

#pragma mark - Notifications

- (void)setUpNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationEnterForeground:)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)removeNotificationsObserver {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    [self pauseAR];
    
    //切到后台或者锁屏，闪光灯强制关闭
//    if ([self.renderVC lightSwitchOn]) {
//        [self.baseUIView setLightSwitchBtnOn:NO];
//        [self.renderVC openLightSwitch:NO];
//    }
//
    if (self.shortVideoRecorder.isTorchOn) {
        [self.shortVideoRecorder setTorchOn:NO];
    }
    
    if(self.baseUIView.shootingVideo){
        [self.baseUIView stopShootVideo];
    }
    
    [self.baseUIView willEnterBackground];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    [self pauseAR];
    //切到后台或者锁屏，闪光灯强制关闭
//    if ([self.renderVC lightSwitchOn]) {
//        [self.baseUIView setLightSwitchBtnOn:NO];
//        [self.renderVC openLightSwitch:NO];
//    }
    
    if ([self.shortVideoRecorder isTorchOn]) {
        [self.shortVideoRecorder setTorchOn:NO];
    }
    if(self.baseUIView.shootingVideo){
        [self.baseUIView stopShootVideo];
    }
    
    [self.baseUIView willEnterBackground];
}

- (void)applicationEnterForeground:(NSNotification *)notification
{
    if ([self isVisiable] ) {
        if(!self.willGoToShare){
            [self resumeAR];
            
            //锁屏或切到后台后，再次进入如果上次录制时间过短则显示“录制时间过短”提示
            if(self.videoRecorder.videoDuration > 0.0 && self.videoRecorder.videoDuration < 1.0){
                [self showRecordVideoTooShort];
                self.videoRecorder.videoDuration = 0;
            }
        } else {
            //锁屏或切到后台后，再次进入如果上次录制时间超过1s则跳转到预览页
//            if(self.hasPendingGotoShare){
//                self.hasPendingGotoShare = NO;
//                [self goShareViewController];
//            }
        }
    }
}

-(BOOL)prefersStatusBarHidden {
    return YES;
}

#pragma mark - Setup
- (void)loadFaceData {
    self.isFirstShowDecal = YES;
    //self.frameReadyCount = 0;
    self.darFaceAlgoModleParse = [[DarFaceAlgoModleParse alloc] init];
    self.faceBeautyLastValueDic = [NSMutableDictionary dictionary];
    __weak typeof(self) weakSelf = self;
    
    //贴纸列表
    self.faceDecalsController = [[DARFaceDecalsController alloc] init];
    self.faceDecalsController.plistPath = self.plistPath;
    [self.faceDecalsController queryDecalsListWithFinishedBlock:nil];
    [self.faceDecalsController setDecalsSwitchBlock:^(DARFaceDecalsModel *model) {
        
    }];
    [self.faceDecalsController setUpdateDecalsArray:^{
        [weakSelf.baseUIView updateDecals:weakSelf.faceDecalsController.decalsArray];
    }];
    
    //滤镜列表
    self.filtersController = [[DARFiltersController alloc] init];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"filter" ofType:@"bundle"];
    NSString *filterPath = [path stringByAppendingPathComponent:@"Filter/ar"];
    [self.filtersController queryFiltersResultWithFilterPath:filterPath queryFinishedBlock:nil];
    [self.filtersController setFilterSwitchBlock:^(NSDictionary *dic) {
        
        NSLog(@"dic %@",dic);
        NSString *filterID = @"500038";
        if (dic != nil) {
            NSDictionary *filterDic = [dic objectForKey:@"filter"];
            filterID = [[filterDic objectForKey:@"filter_group_id"] stringValue];
            [weakSelf.arController switchFilter:filterID];
            weakSelf.currentFilterID = filterID;
            //当切回滤镜时读取之前的参数，设置滤镜效果并修改滑块值
            CGFloat filterDefaultValue = weakSelf.filterLastValue;
            
            if ([filterID isEqualToString:@"500001"]) {
                // 原图滤镜的默认值
                filterDefaultValue = 0.4;
            }
            [weakSelf.arController adjustFilterType:BARFaceBeautyTypeNormalFilter value:filterDefaultValue * FILTER_RATIO];
        } else {
            [weakSelf.arController adjustFilterType:BARFaceBeautyTypeNormalFilter value:0];
            [weakSelf.baseUIView updateBeautySliderValue:0 type:0];
        }
        
    }];
    
}

//配置FaceAR
- (void)setupARController{
    
    __weak typeof(self) weakSelf = self;

    self.arController = [[BARMainController alloc] initARWithCameraSize:self.videoConfiguration.videoSize previewSize:self.videoConfiguration.videoSize];
    
    [self.arController setAlgorithmModelsPath:[[NSBundle mainBundle] pathForResource:@"dlModels" ofType:@"bundle"]];
    
    int position = self.videoConfiguration.position == AVCaptureDevicePositionBack ? 0 : 1;
    BOOL mirror = YES;
    if (0 == position) {
        mirror = !self.videoConfiguration.previewMirrorRearFacing;
    } else {
        mirror = !self.videoConfiguration.previewMirrorFrontFacing;
    }
    [self.arController setDevicePosition:position needArMirrorBuffer:mirror];
    
    [self.arController setVideoOrientation:self.videoOrientation];
    
    if (SAMPLE_BUffER_LAYER) {
        
        [self.arController setPipeline:BARPipelineFramebuffer];
        
        
        weakSelf.m_lastRenderTime = CFAbsoluteTimeGetCurrent();
        NSLog(@"..");
        [self.arController setRenderSampleBufferCompleteBlock:^(CMSampleBufferRef sampleBuffer, id extraData) {
            
            if (weakSelf.lastARSample) {
                CFRelease(weakSelf.lastARSample);
                weakSelf.lastARSample = NULL;
            }
            weakSelf.lastARSample = CFRetain(sampleBuffer);
//            [weakSelf.renderVC updateRenderSampleBuffer:sampleBuffer];
            
            NSDictionary* attachmentWithTime = (NSDictionary*)extraData;
            double beginTime = [attachmentWithTime[@"startTime"] doubleValue];
            double intervalTime = CFAbsoluteTimeGetCurrent() - weakSelf.m_lastRenderTime;
            
            double processIntervalTime = CFAbsoluteTimeGetCurrent() - beginTime;
            
            NSString *frameTimeInfo = [NSString stringWithFormat:@"每帧处理时长 %.1f",processIntervalTime*1000];
            
            //-------------send 1 per 5 times-------------//
            static NSUInteger count = 0;
            static double result = 0;
            count++;
            
            result += (intervalTime*1000);
            if(count%5 ==0){
                double showNumber = 1000.0/(result/5);
                NSString *framePerSecond = [NSString stringWithFormat:@"帧率 %.1f", showNumber ];
                //[[NSNotificationCenter defaultCenter] postNotificationName:@"DEMO_TIME_EVERY_FRAME" object:framePerSecond];
                count = 0;
                result = 0;
            }
            weakSelf.m_lastRenderTime = CFAbsoluteTimeGetCurrent();
            
            
            //            [weakSelf monitorPerformanceParam:(NSDictionary*)extraData];
        }];
    };
    
    [self.arController setUiStateChangeBlock:^(BARSDKUIState state, NSDictionary *stateInfo) {
        dispatch_async(dispatch_get_main_queue(), ^{
            switch (state) {
                    
                case BARSDKUIState_DistanceNormal:
                {
                    
                }
                    break;
                    
                case BARSDKUIState_DistanceTooFar:
                case BARSDKUIState_DistanceTooNear:
                {
                    NSLog(@"过远，过近");
                }
                    break;
                case BARSDKUIState_TrackLost_HideModel:
                {
                    [weakSelf.arController setBAROutputType:BAROutputVideo];
                }
                    break;
                case BARSDKUIState_TrackLost_ShowModel:
                {
                    NSLog(@"跟踪丢失,显示模型");
                }
                    break;
                    
                case BARSDKUIState_TrackOn:
                {
                    [weakSelf.arController setBAROutputType:BAROutputBlend];
                    break;
                }
                    
                case BARSDKUIState_TrackTimeOut:
                {
                    //跟踪超时
                }
                    break;
                    
                default:
                    break;
            }
        });
    }];
    
    self.arController.luaMsgBlock = ^(BARMessageType msgType, NSDictionary *dic) {
        switch (msgType) {
            case BARMessageTypeOpenURL:
            {
                //打开浏览器
                NSString *urlStr = dic[@"url"];
                if (urlStr) {
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlStr]];
                }
                
            }
                break;
            case BARMessageTypeEnableFrontCamera:
            {
                //允许前置摄像头使用
                
            }
                break;
            case BARMessageTypeChangeFrontBackCamera:
            {
                //前后摄像头切换
                [weakSelf cameraSwitchBtnClick];
            }
                break;
            case BARMessageTypeIntitialClick:
            {
                //引导图点击
            }
                break;
            case BARMessageTypeNativeUIVisible:
            {
                //隐藏或者显示界面元素
            }
                break;
            case BARMessageTypeCloseAR:
            {
                [weakSelf closeARView];
            }
                break;
            case BARMessageTypeShowAlert:
            {
                //展示弹框
            }
                break;
            case BARMessageTypeShowToast:
            {
                //展示提示框
            }
                break;
            case BARMessageTypeSwitchCase:
            {
                //切换Case
            }
                break;
            case BARMessageTypeBatchDownloadRetryShowDialog:
            {
                //分布加载
                [weakSelf handleBatchDownload];
            }
                break;
            case BARMessageTypeCustom:
            {
                NSLog(@"dic %@",dic);
                NSString *msgId = [[dic objectForKey:@"id"] description];
                NSInteger msgType = [msgId intValue];
                switch (msgType) {
                    case 10100:
                    {
                        NSLog(@"消息A：Do what you want to do.");
                    }
                        break;
                    case 10101:
                    {
                        NSLog(@"消息B：Do what you want to do.");
                        
                    }
                        break;
                    default:
                        break;
                }
                
            }
                break;
            default:
                break;
        }
    };
    
    [self.arController setShowAlertEventBlock:^(BARSDKShowAlertType type, dispatch_block_t cancelBlock, dispatch_block_t ensureBlock, NSMutableDictionary *info) {
        NSString *alertMsg = nil;
        switch (type) {
            case BARSDKShowAlertType_CaseVersion_Error:
            {
                [weakSelf showalert:@"case版本号与SDK版本号不符"];
            }
                break;
            case BARSDKShowAlertType_NetWrong:
                //网络错误
                alertMsg = @"网络异常";
                break;
                
            case BARSDKShowAlertType_SDKVersionTooLow:
                //版本太低
                alertMsg = @"版本太低";
                break;
                
            case BARSDKShowAlertType_Unsupport:
            {
                //机型、系统、SDK版本等不支持
                NSString *url = [info objectForKey:@"help_url"];//退化URL
                alertMsg = @"机型、系统、SDK版本等不支持";
                
            }
                break;
            case BARSDKShowAlertType_ARError:
            case BARSDKShowAlertType_LuaInvokeSDKToast:
            {
                alertMsg = [info objectForKey:@"msg"] ? : @"出错啦";
                break;
            }
                
            case BARSDKShowAlertType_BatchZipDownloadFail:
                //分布下载，网络异常
                alertMsg = @"分布下载出错";
                break;
                
            case BARSDKShowAlertType_LuaInvokeSDKAlert:{
                //lua中调起AlertView
                NSString *title = [info objectForKey:@"title"];
                NSString *msg = [info objectForKey:@"msg"];
                NSString *confirm_text = [info objectForKey:@"confirm_text"];
                NSString *cancel_text = [info objectForKey:@"cancel_text"];
                alertMsg = title;
            }
                break;
            case BARSDKShowAlertType_AuthenticationError:
            {
                //鉴权识别
                alertMsg = @"鉴权失败";
                [weakSelf.baseUIView resetDecalsViewData];
            }
                break;
            default:
                break;
        }
        
        if (alertMsg) {
            UIAlertController *alertVC = [UIAlertController alertControllerWithTitle:alertMsg message:nil preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *action = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:NULL];
            [alertVC addAction:action];
            [weakSelf presentViewController:alertVC animated:YES completion:NULL];
        }
        
    }];
    [self.arController initFaceData];
    [self.arController setImbin:[self getImbinPath]];
    [self.arController setFaceDetectModelPath:[self getDetectPath]];
    [self.arController setFaceTrackModelPaths:[self getTrackPaths]];
    
    [self.arController lowDeviceStopAlgoWhenRender:NO];
    
    NSString *deviceInfo = [BARUIDevice barPlatformString];
    BARDeviceType deviceType = [self getDeviceType:deviceInfo];
    
    NSString *trackingSmoothAlpha = [self.darFaceAlgoModleParse trackingSmoothAlpha:deviceType];
    NSString *trackingSmoothThreshold = [self.darFaceAlgoModleParse trackingSmoothThreshold:deviceType];
    
    [self.arController setFaceAlgoInfo:@{@"faceSyncProcess":@(YES),
                                         @"deviceInfo":deviceInfo,
                                         @"deviceType":@(deviceType),
                                         @"printLog":@(NO),
                                         @"trackingSmoothAlpha":trackingSmoothAlpha,
                                         @"trackingSmoothThreshold":trackingSmoothThreshold,
                                         }];
    
    //加载滤镜配置文件
    NSString *filterConfigPath = [[NSBundle mainBundle] pathForResource:@"filter" ofType:@"bundle"];
    [self.arController loadFaceFilterDefaultConfigWith:filterConfigPath];
    self.faceBeautyLastValueDic = [[self.arController getFaceConfigDic] mutableCopy];
    [self.faceBeautyLastValueDic setValue:[[self.arController getFilterConfigsDic] mutableCopy] forKey:@"filter"];
    self.currentFilterID = @"500001";
    [self setBeautyDefaultValue:weakSelf.faceBeautyLastValueDic];
    
    //贴纸加载成功
    [self.arController setFaceAssetLoadingFinishedBlock:^(NSArray *triggerList) {
        [weakSelf parseTriggerList:triggerList];
    }];
    
    //box人脸rect，facePoints 特征点， isTracking
    [self.arController setFaceDrawFaceBoxRectangleBlock:^(CGRect box, NSArray *facePoints, BOOL isTracking) {
        if(isTracking){
            weakSelf.isManualFocus = NO;
        }else {
            // 屏幕中心对焦
            if (!weakSelf.isManualFocus) {
//                [weakSelf.renderVC manualAdjustFocusAtPoint:CGPointMake(0.5, 0.5)];
                weakSelf.shortVideoRecorder.focusPointOfInterest = CGPointMake(.5, .5);
                weakSelf.isManualFocus = YES;
            }
        }
        // 人脸对焦
        [weakSelf autoFocusAtFace:facePoints];
//        weakSelf.renderVC.isTrackingSucceed = isTracking;
    }];
    
    //每次算法识别到人脸的表情
    [self.arController setFaceTriggerListLogBlock:^(NSArray *triggerList) {
        
        [triggerList enumerateObjectsUsingBlock:^(NSString *triggerStr, NSUInteger idx, BOOL * _Nonnull stop) {
            //            [weakSelf.demoInfoView updateTriggerInfo:triggerStr];
            
            NSArray *array = [triggerStr componentsSeparatedByString:@":"];
            if(array.count==2){
                if ([weakSelf.currentTrigger containsString:array[0]]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        weakSelf.baseUIView.triggerLabel.hidden = YES;
                        weakSelf.currentTrigger = nil;
                    });
                }
            }
        }];
    }];
    
    
    [self.arController setFaceFrameAvailableBlock:^(NSDictionary *frameDict ,CMSampleBufferRef originBuffer) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isFaceTrackingSucceed = [[frameDict objectForKey:@"trackingSucceeded"] boolValue];
            NSArray *facePoints = frameDict[@"facePointList"];
            
            [weakSelf refreshFaceTrackDemoUI];
            
        });
    }];
    
    [self start:nil];
    [self.arController switchFilter:self.currentFilterID];
    
    
    
    {
        NSString *resPath = [[NSBundle mainBundle] pathForResource:@"face_trigger" ofType:@"json"];
        NSData *resData = [[NSData alloc] initWithContentsOfFile:resPath];
        NSDictionary *resDic = [NSJSONSerialization JSONObjectWithData:resData options:NSJSONReadingMutableLeaves error:nil];
        self.demo_trigger_config_list = resDic;
    }
}

- (void)monitorPerformanceParam:(NSDictionary *)extraDic{
    
    double beginTime = [extraDic[@"startTime"] doubleValue];
    double updateRenderStartTime = [extraDic[@"updateRenderStartTime"] doubleValue];
    double endTime = CFAbsoluteTimeGetCurrent();
    double rveryFrameTime = endTime - beginTime;
    double renderTime = endTime - updateRenderStartTime;
    NSString *frameTimeInfo = [NSString stringWithFormat:@"每帧处理时长 %.1f",rveryFrameTime*1000];
    
    if ([extraDic objectForKey:@"engineStartTime"]) {
        
        double videoStartTime = [[extraDic objectForKey:@"videoStartTime"] doubleValue];
        double videoEndTime = [[extraDic objectForKey:@"videoEndTime"] doubleValue];
        double engineBeginTime = [[extraDic objectForKey:@"engineStartTime"] doubleValue];
        double engineFinishTime = [[extraDic objectForKey:@"engineFinishTime"] doubleValue];
        double blendBeginTime = [[extraDic objectForKey:@"blendStartTime"] doubleValue];
        double blendFinishTime = [[extraDic objectForKey:@"blendFinishTime"] doubleValue];
        double readyCompleteTime = [[extraDic objectForKey:@"readyCompleteTime"] doubleValue];
        double beforeRenderStartTime = [[extraDic objectForKey:@"beforeRenderStartTime"] doubleValue];
        
        NSLog(@"beforeRenderStartTime: %.2f",(beforeRenderStartTime - beginTime)*1000);
        NSLog(@"updateRenderStartTime: %.2f",(updateRenderStartTime - beginTime)* 1000);
        NSLog(@"videoBeginTime: %.2f - videoFinishTime: %.2f",(videoStartTime - beginTime)*1000,(videoEndTime - beginTime)*1000);
        NSLog(@"engineBeginTime: %.2f - engineFinishTime: %.2f",(engineBeginTime - beginTime)*1000,(engineFinishTime - beginTime)*1000);
        NSLog(@"blendBeginTime: %.2f - blendFinishTime: %.2f",(blendBeginTime - beginTime)*1000,(blendFinishTime - beginTime)*1000);
        NSLog(@"readyCompleteTime: %.2f",(readyCompleteTime - beginTime)*1000);
    }
    
    
    NSLog(@"perFrameTime: %.2f",rveryFrameTime * 1000);
    
    double trackPercent = 0.0;
    double animatePercent = 0.0;
    double detectPercent = 0.0;
    double createFramePercent = 0.0;
    double renderPercent;
    double otherPercent;
    
    trackPercent = [extraDic[@"trackTime"] doubleValue] / rveryFrameTime;
    animatePercent = [extraDic[@"animateTime"] doubleValue] / rveryFrameTime;
    detectPercent = [extraDic[@"detectTime"] doubleValue] / rveryFrameTime;
    createFramePercent = [extraDic[@"createFrameTime"] doubleValue] / rveryFrameTime;
    
    renderPercent = renderTime / rveryFrameTime;
    otherPercent = 1 - trackPercent - animatePercent- detectPercent - renderPercent - createFramePercent;
    if (otherPercent < 0) {
        otherPercent = 0.0;
    }
    
    static NSUInteger count = 0;
    static double trackSum = 0;
    static double animateSum = 0;
    static double detectSum = 0;
    static double renderSum = 0;
    static double otherSum = 0;
    static double rveryFrameSum = 0;
    static double createFrameSum = 0;
    count++;
    trackSum += trackPercent;
    animateSum += animatePercent;
    detectSum += detectPercent;
    renderSum += renderPercent;
    otherSum += otherPercent;
    rveryFrameSum += rveryFrameTime;
    createFrameSum += createFramePercent;
    
    if(count == 5){
        trackPercent = trackSum * 0.2;
        animatePercent = animateSum * 0.2;
        detectPercent = detectSum * 0.2;
        renderPercent = renderSum * 0.2;
        otherPercent = otherSum * 0.2;
        rveryFrameTime = rveryFrameSum * 0.2;
        createFramePercent = createFrameSum * 0.2;
        count = 0;
        trackSum = 0;
        animateSum = 0;
        detectSum = 0;
        renderSum = 0;
        otherSum = 0;
        rveryFrameSum = 0;
        createFrameSum = 0;
        NSString *percentString = [NSString stringWithFormat:@"引擎渲染时长占比:%0.1f%% \n人脸算法跟踪时长占比:%0.1f%% \n人脸动画时长占比:%0.1f%% \n人脸算法检测时长占比:%0.1f%% \n创建handle时长占比:%0.1f%% \n其他时长占比:%0.1f%%",renderPercent * 100,trackPercent * 100,animatePercent * 100,detectPercent * 100,createFramePercent * 100,otherPercent * 100];
        
        NSDictionary *percentDic = @{@"rveryFrameTime":frameTimeInfo,@"percentString":percentString};
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DEMO_TIME_EVERY_FRAME" object:percentDic];
    }
}

- (UIImage *)imageConvert:(CMSampleBufferRef)sampleBuffer
{
    
    if (!CMSampleBufferIsValid(sampleBuffer)) {
        return nil;
    }
    CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    
    UIImage *image = [UIImage imageWithCIImage:ciImage];
    return image;
}

- (void)changeToARCamera{
    /*
     if([[self renderVC] videoPreviewView]){
     [[self renderVC] videoPreviewView].enabled = YES;
     [self.arController setTargetView:[[self renderVC] videoPreviewView]];
     dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
     [[self renderVC] changeToARCamera];
     });
     }*/
}

- (void)setupARView{
    NSString *deviceInfo = [BARUIDevice barPlatformString];
    BARDeviceType deviceType = [self getDeviceType:deviceInfo];
    
//    self.renderVC = [[DARRenderViewController alloc] init];
//    self.renderVC.deviceType = deviceType;
//    self.renderVC.isInitCamera = self.cameraToAR;
//    self.renderVC.aspect = [UIScreen mainScreen].bounds.size.height/[UIScreen mainScreen].bounds.size.width;
//    self.renderVC.dataSource = self;
//    [self addChildViewController:self.renderVC];
//    [self.replacedView addSubview:self.renderVC.view];
//    self.renderVC.view.backgroundColor = [UIColor clearColor];
//    [self.renderVC didMoveToParentViewController:self];
//    [self.renderVC manualAdjustFocusAtPoint:CGPointMake(0.5, 0.5)];
    [self.shortVideoRecorder.previewView removeFromSuperview];
    [self.replacedView addSubview:self.shortVideoRecorder.previewView];
    
    
    
}

- (void)setupUIView {
    __weak typeof(self) weakSelf = self;
    self.baseUIView = [[BARBaseView alloc] initWithFrame:self.replacedView.bounds];
    self.baseUIView.clickEventHandler = ^(BARClickActionType action, NSDictionary *data) {
        [weakSelf handleButtonAction:action data:data];
    };
    [self.replacedView addSubview:self.baseUIView];
    
    _gestureView = [[BARGestureView alloc]initWithFrame:self.view.bounds];
    [self.gestureView setBackgroundColor:[UIColor clearColor]];
    [self.replacedView insertSubview:_gestureView belowSubview:self.baseUIView];
    _gestureView.gesturedelegate = (id<BARGestureDelegate>)self;


    [self.baseUIView addFaceUI];
    [self.baseUIView showAllViews];
    self.baseUIView.lightSwitchBtn.hidden = YES;
    self.baseUIView.cameraSwitchBtn.hidden = NO;
    self.baseUIView.cameraSwitchBtn.userInteractionEnabled = YES;
    [self.baseUIView setRecordButtonAndSwitchViewEnable:YES];
}

- (void)loadLocalAR:(NSDictionary *)dic {
    
    NSString *artype = dic[@"type"];
    NSString *path = dic[@"name"];
    NSString *arkey = dic[@"arkey"];
    if (path && [path length] > 0) {
        
        [self hideFaceDemoUI];
        
        if (![self.arType isEqualToString:artype]) {
            self.arType = artype;
        }
        __weak typeof(self) weakSelf = self;
        [self.arController loadARFromFilePath:path arKey:arkey arType:artype success:^(NSString *arKey, kBARType arType) {
            [weakSelf handleARKey:arKey arType:arType];
            [weakSelf.baseUIView handleSwitchDone];
            
        } failure:^{
            NSString *tipStr = BARNSLocalizedString(@"bar_tip_load_resources_fail");
            [[BARAlert sharedInstance] showToastViewPortraitWithTime:1.0f title:nil message:tipStr dismissComplete:nil];
            [weakSelf.baseUIView resetDecalsViewData];
        }];
    }
}

//卸载当前case，以及当前case使用的组件能力
- (void)unLoadCase {
    [self.arController cancelDownLoadArCase];
    //    [[BARRouter sharedInstance] cancelTTS];
    //    [[BARRouter sharedInstance] voice_stopVoiceWithConfigure:self.voiceConfigure];
}

- (void)changeToBackCamera{
//    if(1 == [self.renderVC devicePosition]){//front
//        [self.renderVC rotateCamera];
//        BOOL position = [self.renderVC devicePosition];
//        [self.arController setDevicePosition:position needArMirrorBuffer:[self.renderVC demoNeedARMirrorBuffer]];
//    }
//
    
    __weak typeof(self) weakself = self;
    if (AVCaptureDevicePositionFront == self.shortVideoRecorder.captureDevicePosition ) {
        [self.shortVideoRecorder toggleCamera:^(BOOL isFinish) {
            if (!isFinish) return;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakself.arController setDevicePosition:0 needArMirrorBuffer:!weakself.shortVideoRecorder.previewMirrorRearFacing];
            });
        }];
    }
}

- (void)changeToFrontCamera {
//    if (0 == [self.renderVC devicePosition]) {//back
//        [self.renderVC rotateCamera];
//        BOOL position = [self.renderVC devicePosition];
//        [self.arController setDevicePosition:position needArMirrorBuffer:[self.renderVC demoNeedARMirrorBuffer]];
//    }
    
    __weak typeof(self) weakself = self;
    if (AVCaptureDevicePositionBack == self.shortVideoRecorder.captureDevicePosition ) {
        [self.shortVideoRecorder toggleCamera:^(BOOL isFinish) {
            if (!isFinish) return;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakself.arController setDevicePosition:1 needArMirrorBuffer:!weakself.shortVideoRecorder.previewMirrorFrontFacing];
            });
        }];
    }
}

- (void)handleARKey:(NSString *)arKey arType:(kBARType)arType {
    if (arKey && ![arKey isEqualToString:@""]) {
        self.arKey = arKey;
    }
    self.arType = [NSString stringWithFormat:@"%i",arType];
    
    //[self hideFaceDemoUI];
    
    if (kBARTypeLocalSameSearch == arType) {
        
    }else if (kBARTypeCloudSameSearch == arType) {
        
    }else if (kBARTypeARKit == arType) {
        [self startARKit];
    }else {
        [self start:nil];
    }
}

//启动AR
- (void)start:(id)sender{
    
    [self.arController startAR];
    
    if(kBARTypeFace == self.arType.integerValue){
        return;
    }
    
//    if (!SAMPLE_BUffER_LAYER) {
//        if([[self currentRenderVC] videoPreviewView]){
//            [[self currentRenderVC] videoPreviewView].enabled = YES;
//            [self.arController setTargetView:[[self currentRenderVC] videoPreviewView]];
//            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//                if ([[self currentRenderVC] isKindOfClass:[BARARKitCameraRenderViewController class]]) {
//                    [[self currentRenderVC] changeToARCamera];
//                }else {
//                    [[self currentRenderVC] changeToARCamera];
//                }
//            });
//        }
//    }
}

#pragma mark - ARKit < --- > AR

- (void)startARKit {
    
    [self.arController startAR];
    if(self.arkitModule.arRenderWithCameraVC.videoPreviewView){
        self.arkitModule.arRenderWithCameraVC.videoPreviewView.enabled = YES;
        [self.arController setTargetView:self.arkitModule.arRenderWithCameraVC.videoPreviewView];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[self currentRenderVC] changeToARCamera];
        });
    }
}

- (void)removeARKitCurrentCamera{
    
    if (self.arkitModule.arRenderWithCameraVC){
        self.arkitModule.arRenderWithCameraVC.videoPreviewView.enabled = NO;
        [self.arkitModule.arRenderWithCameraVC stopCapture];
        [self.arkitModule.arRenderWithCameraVC.view removeFromSuperview];
        [self.arkitModule.arRenderWithCameraVC removeFromParentViewController];
        
        [self.arController setTargetView:nil];
        self.arkitModule.arRenderWithCameraVC = nil;
        
        [self changeToBARRender];
        [[self currentRenderVC] changeToSystemCamera];
    }
}

- (void)changeToARKitRender {
//    if(self.renderVC){
//        //        self.renderVC.videoPreviewView.enabled = NO;
//        [self.renderVC stopCapture];
//        [self.renderVC.view removeFromSuperview];
//        [self.renderVC removeFromParentViewController];
//        [self.arController setTargetView:nil];
//        self.renderVC = nil;
//    }
    
    [self.replacedView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    BARRenderBaseViewController *arKitVC = [self.arkitModule setupARKitControllerWithRatio:ASPECT_RATIO];
    [self addChildViewController:arKitVC];
    [self.replacedView addSubview:arKitVC.view];
    [arKitVC didMoveToParentViewController:self];
    
    [arKitVC startCapture];
    if(self.videoRecorder){
//        self.videoRecorder = nil;
    }
    id camera = [arKitVC currentCameraForRecord];
//    self.videoRecorder = [[BARVideoRecorder alloc] initWithCamera:camera];
}

- (void)changeToBARRender {
    
//    if(self.renderVC){
//        [self.renderVC stopCapture];
//        [self.renderVC.view removeFromSuperview];
//        [self.renderVC removeFromParentViewController];
//        self.renderVC = nil;
//    }
    
    [self.replacedView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    [self setupARView];
    
    [[self currentRenderVC] startCapture];
    
    if(self.videoRecorder){
//        self.videoRecorder = nil;
    }
//    self.videoRecorder = [[BARVideoRecorder alloc] initVideoRecorder];
}

#pragma mark - Private
- (BARVideoRecorder *)videoRecorder {
//    if (!_videoRecorder) {
//        _videoRecorder = [[BARVideoRecorder alloc] initVideoRecorder];
//    }
//    return _videoRecorder;
    return nil;
}

- (NSString *)getImbinPath {
    return  [self.darFaceAlgoModleParse imbinPath];
}

- (NSString *)getDetectPath {
    if (self.faceAlgoModelDic) {
        return self.faceAlgoModelDic[@"detectPath"];
    }
    return  [self.darFaceAlgoModleParse detectPath];
}

- (NSArray *)getTrackPaths {
    if (self.faceAlgoModelDic) {
        return self.faceAlgoModelDic[@"trackArray"];
    }
    NSString *deviceInfo = [BARUIDevice barPlatformString];
    BARDeviceType deviceType = [self getDeviceType:deviceInfo];
    return [self.darFaceAlgoModleParse trackPaths:deviceType];
}

- (BARDeviceType)getDeviceType:(NSString *)deviceInfo {
    BARDeviceType deviceType = BARDeviceTypeUnknow;
    NSString *deviceConfigPath = [[NSBundle mainBundle] pathForResource:@"device_config" ofType:@"json"];
    NSData *deviceData = [[NSData alloc] initWithContentsOfFile:deviceConfigPath];
    NSDictionary *deviceDic = [NSJSONSerialization JSONObjectWithData:deviceData options:NSJSONReadingMutableLeaves error:nil];
    
    id highDevice = [deviceDic objectForKey:@"high"];
    if (highDevice && [highDevice isKindOfClass:[NSArray class]]) {
        for (NSString *temp in highDevice) {
            if ([temp isEqualToString:deviceInfo]) {
                deviceType = BARDeviceTypeHigh;
                return deviceType;
            }
        }
    }
    
    id mediumDevice = [deviceDic objectForKey:@"medium"];
    if (mediumDevice && [mediumDevice isKindOfClass:[NSArray class]]) {
        for (NSString *temp in mediumDevice) {
            if ([temp isEqualToString:deviceInfo]) {
                deviceType = BARDeviceTypeMedium;
                return deviceType;
            }
        }
    }
    
    id lowDevice = [deviceDic objectForKey:@"low"];
    if (lowDevice && [lowDevice isKindOfClass:[NSArray class]]) {
        for (NSString *temp in lowDevice) {
            if ([temp isEqualToString:deviceInfo]) {
                deviceType = BARDeviceTypeLow;
                return deviceType;
            }
        }
    }
    
    return deviceType;
}

- (BOOL)isVisiable {
    return (self.isViewLoaded && self.view.window);
}

/**
 拍摄视频后跳转到保存页
 
 */
- (void)goEditViewController {
//    NSString *videoPath = [BARSDKProConfig sharedInstance].videoPath;
//    BARShareViewControllers* vc = [[BARShareViewControllers alloc] initWithVideoPath:videoPath];
//    __weak typeof(self) weakSelf = self;
//    weakSelf.willGoToShare = YES;
//    __weak typeof(weakSelf) weakweakSelf = weakSelf;
//    [weakSelf presentViewController:vc animated:NO completion:^{
//        [weakweakSelf.baseUIView setRecordButtonAndSwitchViewEnable:YES];
//    }];
    
    // 获取当前会话的所有的视频段文件
    AVAsset *asset = [self.shortVideoRecorder assetRepresentingAllFiles];
    NSArray *filesURLArray = [self.shortVideoRecorder getAllFilesURL];
    NSLog(@"filesURLArray:%@", filesURLArray);
    
    __block AVAsset *movieAsset = asset;
    // 设置音视频、水印等编辑信息
    NSMutableDictionary *outputSettings = [[NSMutableDictionary alloc] init];
    // 待编辑的原始视频素材
    NSMutableDictionary *plsMovieSettings = [[NSMutableDictionary alloc] init];
    plsMovieSettings[PLSAssetKey] = movieAsset;
    plsMovieSettings[PLSStartTimeKey] = [NSNumber numberWithFloat:0.f];
    plsMovieSettings[PLSDurationKey] = [NSNumber numberWithFloat:[self.shortVideoRecorder getTotalDuration]];
    plsMovieSettings[PLSVolumeKey] = [NSNumber numberWithFloat:1.0f];
    outputSettings[PLSMovieSettingsKey] = plsMovieSettings;
    
    EditViewController *videoEditViewController = [[EditViewController alloc] init];
    videoEditViewController.settings = outputSettings;
    videoEditViewController.filesURLArray = filesURLArray;
    [self presentViewController:videoEditViewController animated:YES completion:nil];
}

- (void)parseTriggerList:(NSArray *)triggerList {
    if (triggerList && [triggerList count] != 0) {
        NSString *key = triggerList[0];
        NSArray *comArr = [key componentsSeparatedByString:@":"];
        if(comArr.count==2){
            
            NSString *triggerChineseName = [self getTriggerChineseName:comArr[0]];
            
            if(triggerChineseName.length>0){
                self.currentTrigger = comArr[0];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.baseUIView.triggerLabel.text = [NSString stringWithFormat:@"请 %@", triggerChineseName];
                    [self refreshTriggerDemoUIHidden:NO];
                });
                return;
            }else{
                self.currentTrigger = nil;
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.baseUIView.triggerLabel.text = @"";
                });
                
            }
        }
    }
    [self refreshTriggerDemoUIHidden:YES];
}

- (NSString *)getTriggerChineseName:(NSString *)triggerName {
    __block NSString *imgName = @"";
    __block NSString *imgName1 = [triggerName copy];
    [self.demo_trigger_config_list enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj, BOOL * _Nonnull stop) {
        if([key isEqualToString:imgName1]){
            imgName = obj;
            *stop = YES;
        }
    }];
    return [imgName copy];
}

- (void)hideFaceDemoUI{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.baseUIView.undetectedFaceImgView.hidden = YES;
        self.currentTrigger = nil;
        //        self.baseUIView.faceAlertImgView.image = nil;
        //        self.baseUIView.faceAlertImgView.hidden = YES;
        self.baseUIView.triggerLabel.hidden = YES;
    });
}

- (void)refreshTriggerDemoUIHidden:(BOOL)hidden{
    if([self.arType integerValue] == kBARTypeFace){
        dispatch_async(dispatch_get_main_queue(), ^{
            self.baseUIView.triggerLabel.hidden = hidden;
        });
    }
}

- (void)refreshFaceTrackDemoUI{
    if([self.arType integerValue] == kBARTypeFace){
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if (self.isFaceTrackingSucceed){
                self.baseUIView.undetectedFaceImgView.hidden = YES;
                if(self.currentTrigger){
                    self.baseUIView.triggerLabel.hidden = NO;
                }
            }else{
                self.baseUIView.undetectedFaceImgView.hidden = NO;
                self.baseUIView.triggerLabel.hidden = YES;
            }
            
        });
    }
}

- (BOOL) isIPhoneX {
    if (([UIScreen instancesRespondToSelector:@selector(currentMode)] ? CGSizeEqualToSize(CGSizeMake(828, 1792), [[UIScreen mainScreen] currentMode].size) : NO)) return YES;
    if (([UIScreen instancesRespondToSelector:@selector(currentMode)] ? CGSizeEqualToSize(CGSizeMake(818, 1792), [[UIScreen mainScreen] currentMode].size) : NO)) return YES;
    if (([UIScreen instancesRespondToSelector:@selector(currentMode)] ? CGSizeEqualToSize(CGSizeMake(1125, 2436), [[UIScreen mainScreen] currentMode].size) : NO)) return YES;
    if (([UIScreen instancesRespondToSelector:@selector(currentMode)] ? CGSizeEqualToSize(CGSizeMake(1242, 2688), [[UIScreen mainScreen] currentMode].size) : NO)) return YES;
    if (([UIScreen instancesRespondToSelector:@selector(currentMode)] ? CGSizeEqualToSize(CGSizeMake(1242, 2607), [[UIScreen mainScreen] currentMode].size) : NO)) return YES;
    return NO;
}

- (void)showRecordVideoTooShort{
    [[BARAlert sharedInstance] showToastViewPortraitWithTime:1 title:nil message:BARNSLocalizedString(@"bar_tip_video_too_short_alert") dismissComplete:^{
        
    }];
}

- (id)currentRenderVC {
//    if (kBARTypeARKit == [self.arType integerValue]) {
//        return self.arkitModule.arRenderWithCameraVC;
//    }else {
//        return self.renderVC;
//    }
    return nil;
}

- (void)resetlightStatus {
    [self.baseUIView setLightSwitchBtnOn:NO];
//    [self.renderVC openLightSwitch:NO];
}

#pragma mark - Actions
- (void)handleButtonAction:(BARClickActionType)action data:(NSDictionary *)data {
    switch(action) {
        case BARClickActionClose:
            [self closeARView];
            break;
        case BARClickActionLightSwitch:
            [self lightSwitchButtonClicked];
            break;
        case BARClickActionCameraSwitch:
            [self cameraSwitchBtnClick];
            break;
        case BARClickActionScreenshot:
            [self screenshotBtnClick];
            break;
        case BARClickActionShootVideoStart:{
            [self shootVideoBtnStart];
            break;
        }
        case BARClickActionShootVideoStop:{
            [self shootVideoBtnStop];
            break;
        }
        case BARClickActionDecals:
        {
            [self.baseUIView decalsViewShow:self.faceDecalsController.decalsArray];
            break;
        }
        case BARClickActionTypeDecalsSwitch:
        {
            NSInteger decalsIndex = [[data objectForKey:@"index"] integerValue];
//            self.renderVC.isFaceAssetsLoaded = YES;
            DARFaceDecalsModel *model = self.faceDecalsController.decalsArray[decalsIndex];
            [self loadLocalAR:[model dic]];
            
            break;
        }
        case BARClickActionTypeCloseFace:
        {
            [self.baseUIView closeFaceView];
            break;
        }
        case BARClickActionTypeCancelDecals:
        {
            [self.faceDecalsController switchDecalWithIndex:-1];
            //self.isFaceAssetsLoaded = NO;
            self.baseUIView.undetectedFaceImgView.hidden = YES;
            [self.baseUIView hideFaceAlertImgView];
            self.currentTrigger = nil;
            [self.arController stopAR];
            [self.arController startFaceAR];
            
            NSDictionary *dic = @{@"BARNeedAnimate": @(NO)};
            [[NSNotificationCenter defaultCenter] postNotificationName:@"BARNeedAnimate" object:dic userInfo:nil];
            
            [self.arController setConfigurationType:BAROutConfigurationTypeDefault];
            
            break;
        }
        case BARClickActionBeauty:
        {
            [self.baseUIView beautyViewShow:self.filtersController.filtersArray];
        }
            break;
        case BARClickActionTypeFilterAdjust: {
            [self adjustFilterWithParam:data];
            break;
        }
        case BARClickActionTypeFilterSwitch:
        {
            NSInteger filterIndex = [[data objectForKey:@"index"] integerValue];
            NSString *defaultValue = [[self.faceBeautyLastValueDic objectForKey:@"filter"] objectForKey:@"defaultValue"];
            self.filterLastValue = [defaultValue floatValue];
            [self.filtersController switchFilterWith:filterIndex];
            [self.baseUIView.beautyView setSliderValue:self.filterLastValue type:0];
            break;
        }
        case BARClickActionTypeBeautySwitch:
        {
            NSString *beauty = [data objectForKey:@"beauty"];
            NSString *defaultValue = [[self.faceBeautyLastValueDic objectForKey:beauty] objectForKey:@"defaultValue"];
            [self.baseUIView.beautyView setSliderValue:[defaultValue floatValue] type:0];
            self.currentBeauty = beauty;
            break;
        }
        case BARClickActionTypeCancelFilter:
        {
            [self.filtersController switchFilterWith:-1];
            break;
        }
        case BARClickActionTypeResetBeauty:
        {
            //先保存滤镜参数，因为重置只是重置美颜相关参数
            NSDictionary *filterDic = [self.faceBeautyLastValueDic objectForKey:@"filter"];
            self.faceBeautyLastValueDic = [[self.arController getFaceConfigDic] mutableCopy];
            [self.faceBeautyLastValueDic setValue:filterDic forKey:@"filter"];
            if (self.currentBeauty) {
                NSString *defaultValue = [[self.faceBeautyLastValueDic objectForKey:self.currentBeauty] objectForKey:@"defaultValue"];
                [self.baseUIView.beautyView setSliderValue:[defaultValue floatValue] type:0];
            }
            [self setBeautyDefaultValue:self.faceBeautyLastValueDic];
            break;
        }
        case BARClickActionTypeCancelBeauty:
        {
            self.currentBeauty = nil;
            break;
        }
        case BARClickActionTypeSwitchResolution:
        {
            //            if ([data isKindOfClass:[NSDictionary class]]) {
            //                NSNumber *value = [data objectForKey:@"isOn"];
            //                if (value) {
            //                    [self.renderVC changeCameFormatPreset:[value intValue]];
            //                }
            //            }
            break;
        }
        default:
            break;
    }
}

//停止AR
- (void)stopAR{
    [self.arController leaveAR];
    [self unLoadCase];
}

//暂停AR
- (void)pauseAR{
    [self.arController pauseAR];
    [self.shortVideoRecorder stopCaptureSession];
//    [self.renderVC pauseCapture];
}

//恢复AR
- (void)resumeAR {
    self.willGoToShare = NO;
//    [self.renderVC resumeCapture];
    [self.shortVideoRecorder startCaptureSession];
    [self.arController resumeAR];
}

- (void)closeARView {
    [self stopAR];
    [self dismissViewControllerAnimated:YES completion:^{
//        [self.renderVC stopCapture];
//        [self.renderVC removeContaintView];
        [self.shortVideoRecorder stopCaptureSession];
    }];
}


//视频录制
- (void)shootVideoBtnStart {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if(status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self shootVideoBtnStartAction:granted];
            });
            
        }];
    }
    else if(status == AVAuthorizationStatusDenied) {
        [self shootVideoBtnStartAction:NO];
    }
    else{
        [self shootVideoBtnStartAction:YES];
    }
    
}

- (void)shootVideoBtnStartAction:(BOOL)enableAudioTrack {
    if (![self.baseUIView canStartRecord]) {
        return;
    }
    
    if (self.baseUIView.shootingVideo) {
        return ;
    }
    
//    if (self.videoRecorder.isRecording) {
//        return ;
//    }
    if (self.shortVideoRecorder.isRecording) {
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    [self.baseUIView startShootVideoWithComplitionHandler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if(strongSelf){
            [strongSelf shootVideoCompletion];
        }
    }];
//    [self.videoRecorder startRecordingWithAudioTrack:enableAudioTrack];
//    [self.arController setRenderMovieWriter:self.videoRecorder.movieWriter];
    [self.shortVideoRecorder deleteAllFiles];
    [self.shortVideoRecorder startRecording];
}

//停止视频录制
- (void)shootVideoCompletion {
    
    [self.shortVideoRecorder stopRecording];
    
//    [self.videoRecorder stopRecording:^{
//        [self.arController setRenderMovieWriter:nil];
//        dispatch_async(dispatch_get_main_queue(), ^{
//            if(self.videoRecorder.videoDuration > 1.0 || self.videoRecorder.videoDuration == 1.0){
//                self.willGoToShare = YES;
//                [self goShareViewController];
//            }else{
//                if(self.hasPendingGotoShare) {
//                    self.hasPendingGotoShare = NO;
//                }
//                if([self isVisiable]){
//                    [self  showRecordVideoTooShort];
//                }
//            }
//        });
//    }];
}

- (void)shootVideoBtnStop {
    [self.baseUIView stopShootVideo];
}

//拍照
- (void)screenshotBtnClick {
    [self.baseUIView setRecordButtonAndSwitchViewEnable:NO];
    __weak typeof(self) weakSelf = self;
    [self.arController takePicture:^(UIImage *image) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!image) {
                [weakSelf.baseUIView setRecordButtonAndSwitchViewEnable:YES];
                return;
            }
            BARShareViewControllers* vc = [[BARShareViewControllers alloc] initWithImage:image];
            __weak typeof(self) weakSelf = self;
            weakSelf.willGoToShare = YES;
            __weak typeof(weakSelf) weakweakSelf = weakSelf;
            [weakSelf presentViewController:vc animated:NO completion:^{
                [weakweakSelf.baseUIView setRecordButtonAndSwitchViewEnable:YES];
            }];
        });
    }];
}

//闪光灯开启关闭切换
- (void)lightSwitchButtonClicked {
//    if ([self.renderVC lightSwitchOn]) {
//        [self.baseUIView setLightSwitchBtnOn:NO];
//        [self.renderVC openLightSwitch:NO];
//    } else {
//        [self.baseUIView setLightSwitchBtnOn:YES];
//        [self.renderVC openLightSwitch:YES];
//    }
    
    [self.shortVideoRecorder setTorchOn:!self.shortVideoRecorder.isTorchOn];
    [self.baseUIView setLightSwitchBtnOn:self.shortVideoRecorder.isTorchOn];
}


//相机前后摄像头切换
- (void)cameraSwitchBtnClick {
    
    [self pauseAR];
    [self.shortVideoRecorder toggleCamera:^(BOOL isFinish) {
        [self resumeAR];
    }];
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//        [self.renderVC pauseCapture];
//        [self.renderVC rotateCamera];
//        BOOL position = [self.renderVC devicePosition];
//
//        [self.arController setDevicePosition:position needArMirrorBuffer:[self.renderVC demoNeedARMirrorBuffer]];
//
//        __weak typeof(self)weakSelf = self;
//        dispatch_async(dispatch_get_main_queue(), ^{
//            if (1 == position) {//前置
//                [weakSelf.baseUIView setLightSwitchBtnOn:NO];
//                weakSelf.baseUIView.lightSwitchBtn.hidden = YES;
//            }else {
//                weakSelf.baseUIView.lightSwitchBtn.hidden = NO;
//            }
//
//        });
//
//        [self.arController sendMsgToLuaWithMapData:@{@"id":[NSNumber numberWithInteger:10200],
//                                                     @"front_camera": [NSNumber numberWithInteger:[self.renderVC devicePosition]]}];
//
//        [self.renderVC resumeCapture];
//        [self resumeAR];
//    });
}

#pragma mark - TTS Component

//设置TTS
- (void)setupTTS {
    [[BARRouter sharedInstance] setUpTTS];
}

#pragma mark - Voice Component

- (void)setupARVoice{
    self.voiceConfigure = [[BARRouter sharedInstance] voice_createVoiceConfigure];
    [[BARRouter sharedInstance] voice_setStopBlock:^{
        NSLog(@"voiceStop");
    } withConfigure:self.voiceConfigure];
    
    
    [[BARRouter sharedInstance] voice_setStartBlock:^(BOOL success){
        NSLog(@"voiceStart");
    } withConfigure:self.voiceConfigure];
    
    [[BARRouter sharedInstance] voice_setStatusBlock:^(int status, id aObj) {
        switch (status) {
            case BARVoiceUIState_ShowLoading:
            {
                break;
            }
            case BARVoiceUIState_StopLoading:
            {
                break;
            }
            case BARVoiceUIState_ShowWave:
            {
                break;
            }
            case BARVoiceUIState_StopWave:
            {
                break;
            }
            case BARVoiceUIState_WaveChangeVolume:
            {
                NSLog(@"volume %li",(long)[aObj integerValue]);
                break;
            }
            case BARVoiceUIState_ShowTips:
            {
                NSLog(@"tips %@",aObj);
                break;
            }
            case BARVoiceUIState_HideVoice:
            {
                break;
            }
            default:
                break;
        }
    } withConfigure:self.voiceConfigure];
    
    [[BARRouter sharedInstance] voice_setUpWithConfigure:self.voiceConfigure];
}

////开启语音识别
- (void)startVoice:(id)sender {
    [[BARRouter sharedInstance] voice_setUpWithConfigure:self.voiceConfigure];
    [[BARRouter sharedInstance] voice_startVoiceWithConfigure:self.voiceConfigure];
}
//
////结束语音识别
- (void)stopVoice:(id)sender {
    [[BARRouter sharedInstance] voice_setUpWithConfigure:self.voiceConfigure];
    [[BARRouter sharedInstance] voice_stopVoiceWithConfigure:self.voiceConfigure];
}


#pragma mark - DARRenderViewControllerDataSource

/**
 Render DataSource
 @param srcBuffer 相机buffer源
 */
- (void)updateSampleBuffer:(CMSampleBufferRef)srcBuffer {
    if (SAMPLE_BUffER_LAYER) {
        NSDictionary *exraDic = @{@"startTime":[NSNumber numberWithDouble:CFAbsoluteTimeGetCurrent()]};
        [self.arController updateSampleBuffer:srcBuffer extraInfo:exraDic];
    } else {
        [self.arController updateSampleBuffer:srcBuffer];
    }
    
    
}

- (void)updateAudioSampleBuffer:(CMSampleBufferRef)audioBuffer {
    if(self.videoRecorder.isRecording){
        [self.videoRecorder.movieWriter processAudioBuffer:audioBuffer];
    }
}

- (void)updateSampleBuffer:(CMSampleBufferRef)sampleBuffer extraInfo:(id)info{
    [self.arController updateSampleBuffer:sampleBuffer extraInfo:info];
}

- (void)showalert:(NSString *)alertinfo{
    UIAlertController *vc = [UIAlertController alertControllerWithTitle:@"提示" message:alertinfo
                                                         preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [vc dismissViewControllerAnimated:YES completion:^{
            
        }];
    }];
    [vc addAction:cancelAction];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self presentViewController:vc animated:YES completion:NULL];
    });
    
    
}

#pragma mark - Gesture

- (void)onViewGesture:(UIGestureRecognizer *)gesture{
    [self.arController onViewGesture:gesture];
}
- (void)ar_touchesBegan:(NSSet<UITouch *> *)touches scale:(CGFloat)scale {
    [self.arController ar_touchesBegan:touches scale:scale];
    
    if ([self.arType integerValue] == kBARTypeFace) {
//        CGPoint point = [[touches anyObject] locationInView:self.renderVC.view];
        CGPoint point = [[touches anyObject] locationInView:self.shortVideoRecorder.previewView];
        [self handleCameraFocus:point];
    }
    
    [self.baseUIView closeFaceView];
}
- (void)ar_touchesMoved:(NSSet<UITouch *> *)touches scale:(CGFloat)scale {
    [self.arController ar_touchesMoved:touches scale:scale];
}
- (void)ar_touchesEnded:(NSSet<UITouch *> *)touches scale:(CGFloat)scale {
    [self.arController ar_touchesEnded:touches scale:scale];
}
- (void)ar_touchesCancelled:(NSSet<UITouch *> *)touches scale:(CGFloat)scale {
    [self.arController ar_touchesCancelled:touches scale:scale];
}

#pragma mark - handle camera focus

- (void)handleCameraFocus:(CGPoint)point {
//    CGSize screenSize = [UIScreen mainScreen].bounds.size;
//    if ([self.renderVC devicePosition] == 1) {
//        [self.renderVC manualAdjustFocusAtPoint:CGPointMake(point.y / screenSize.height, point.x / screenSize.width)];
//    }else {
//        [self.renderVC manualAdjustFocusAtPoint:CGPointMake(point.y / screenSize.height, (screenSize.width - point.x) / screenSize.width)];
//    }
//
//    NSValue *leftPoint = [NSValue valueWithCGPoint:CGPointMake(point.x - 50, point.y - 50)];
//    NSValue *rightPoint = [NSValue valueWithCGPoint:CGPointMake(point.x + 50, point.y + 50)];
//    NSArray *points = @[leftPoint, rightPoint];
//    [self.renderVC tapAdjustFocusToDrawRectangle:points];
}

#pragma mark - Face

- (void)adjustFilterWithParam:(NSDictionary *)param {
    NSString *title = [param objectForKey:@"title"];
    CGFloat value = [[param objectForKey:@"value"] floatValue];
    if([title isEqualToString:@"whiten"]){  //美白
        [self.arController adjustFilterType:BARFaceBeautyTypeWhiten value:value];
    }else if([title isEqualToString:@"skin"]){ //磨皮
        [self.arController adjustFilterType:BARFaceBeautyTypeSkin value:value];
    }else if([title isEqualToString:@"eye"]){ //大眼
        [self.arController adjustFilterType:BARFaceBeautyTypeEye value:value];
    }else if([title isEqualToString:@"thinFace"]){ //瘦脸
        [self.arController adjustFilterType:BARFaceBeautyTypeThinFace value:value];
    }else if([title isEqualToString:@"filter"]) { //透明度
        if ([self.currentFilterID isEqualToString:@"500001"]) {
            // 默认滤镜默认值为0.4
            [self.arController adjustFilterType:BARFaceBeautyTypeNormalFilter value:0.4 * FILTER_RATIO];
        }else {
            [self.arController adjustFilterType:BARFaceBeautyTypeNormalFilter value:value * FILTER_RATIO];
            self.filterLastValue = value;
        }
    }
    if (title != nil) {
        //保存当前值
        NSMutableDictionary *faceBeautyValueDict = [[self.faceBeautyLastValueDic objectForKey:title] mutableCopy];
        [faceBeautyValueDict setObject:[NSNumber numberWithFloat:value] forKey:@"defaultValue"];
        if (faceBeautyValueDict != nil) {
            [self.faceBeautyLastValueDic setObject:faceBeautyValueDict forKey:title];
        }
    }
}

- (void)setBeautyDefaultValue:(NSDictionary *)param {
    if (param && [param isKindOfClass:[NSDictionary class]]) {
        [param enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            NSDictionary *dic = @{@"title" : key, @"value": [[param objectForKey:key] objectForKey:@"defaultValue"]};
            [self adjustFilterWithParam:dic];
        }];
    }
}

- (void)autoFocusAtFace:(NSArray *)points {
    NSArray *tempPoints = [points copy];
    double minX = 2000;
    double maxX = 0;
    double minY = 2000;
    double maxY = 0;
    // 循环所有点，求最大框
    for (NSValue *value in tempPoints) {
        CGPoint point = [value CGPointValue];
        if (point.x < minX) {
            minX = point.x;
        }
        if (point.x > maxX) {
            maxX = point.x;
        }
        if (point.y < minY) {
            minY = point.y;
        }
        if (point.y > maxY) {
            maxY = point.y;
        }
    }
    
    NSValue *minXY = [NSValue valueWithCGPoint:CGPointMake(minX, minY)];
    NSValue *maxXY = [NSValue valueWithCGPoint:CGPointMake(maxX, maxY)];
    NSArray *result = [NSArray arrayWithObjects:minXY, maxXY, nil];
    
//    [self.renderVC drawFaceBoxRectangle:result];
}

#pragma mark - setter getter
- (UIView *) replacedView{
    if(!_replacedView){
        _replacedView = [[UIView alloc] initWithFrame:self.view.bounds];
        _replacedView.backgroundColor = [UIColor blackColor];
        [self.view addSubview:_replacedView];
    }
    return _replacedView;
}

#pragma mark - 分布加载
- (void)handleBatchDownload {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"网络不给力" message:@"是否重试？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    __weak typeof(self) weakSelf = self;
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf.arController cancelDownloadBatchZip];
    }];
    [alert addAction:cancelAction];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf.arController retryDownloadBatchZip];
    }];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:NULL];
    
}



#pragma mark -- PLShortVideoRecorderDelegate 摄像头／麦克风鉴权的回调
- (void)shortVideoRecorder:(PLShortVideoRecorder *__nonnull)recorder didGetCameraAuthorizationStatus:(PLSAuthorizationStatus)status {
    if (status == PLSAuthorizationStatusAuthorized) {
        [recorder startCaptureSession];
    }
    else if (status == PLSAuthorizationStatusDenied) {
        NSLog(@"Error: user denies access to camera");
    }
}

- (void)shortVideoRecorder:(PLShortVideoRecorder *__nonnull)recorder didGetMicrophoneAuthorizationStatus:(PLSAuthorizationStatus)status {
    if (status == PLSAuthorizationStatusAuthorized) {
        [recorder startCaptureSession];
    }
    else if (status == PLSAuthorizationStatusDenied) {
        NSLog(@"Error: user denies access to microphone");
    }
}

#pragma mark - PLShortVideoRecorderDelegate 摄像头对焦位置的回调
- (void)shortVideoRecorder:(PLShortVideoRecorder *)recorder didFocusAtPoint:(CGPoint)point {
    NSLog(@"shortVideoRecorder: didFocusAtPoint: %@", NSStringFromCGPoint(point));
}

#pragma mark - PLShortVideoRecorderDelegate 摄像头采集的视频数据的回调
/// @abstract 获取到摄像头原数据时的回调, 便于开发者做滤镜等处理，需要注意的是这个回调在 camera 数据的输出线程，请不要做过于耗时的操作，否则可能会导致帧率下降
- (CVPixelBufferRef)shortVideoRecorder:(PLShortVideoRecorder *)recorder cameraSourceDidGetPixelBuffer:(CVPixelBufferRef)pixelBuffer {
   
    CMSampleBufferRef newSampleBuffer = NULL;
    CMSampleTimingInfo timimgInfo = kCMTimingInfoInvalid;
    CMVideoFormatDescriptionRef videoInfo = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &videoInfo);
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                       pixelBuffer,
                                       true,
                                       NULL,
                                       NULL,
                                       videoInfo,
                                       &timimgInfo,
                                       &newSampleBuffer);
    CFRelease(videoInfo);
    
    [self.arController updateSampleBuffer:newSampleBuffer];
    CFRelease(newSampleBuffer);
    
    if (self.lastARSample) {
        return CMSampleBufferGetImageBuffer(self.lastARSample);
    } else {
        return nil;
    }
//    return pixelBuffer;
}


- (void)shortVideoRecorder:(PLShortVideoRecorder *)recorder didFinishRecordingToOutputFileAtURL:(NSURL *)fileURL fileDuration:(CGFloat)fileDuration totalDuration:(CGFloat)totalDuration {
    if(totalDuration > 1.0 || totalDuration == 1.0){
        self.willGoToShare = YES;
        [self.baseUIView stopShootVideo];
        [self goEditViewController];
    }else{
//        if(self.hasPendingGotoShare) {
//            self.hasPendingGotoShare = NO;
//        }
        if([self isVisiable]){
            [self  showRecordVideoTooShort];
        }
    }

}

@end
#else
@implementation RecordViewController

@end
#endif

