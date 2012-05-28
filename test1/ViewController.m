//
//  ViewController.m
//  test1
//
//  Created by Yuan Mingyi on 12-5-27.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "ViewController.h"
#import <AudioToolbox/AudioServices.h>
#include "opencv/cv.h"
#include "opencv/highgui.h"

// only for 3-channel bgr or 4-channel rgba iplimage!!
UIImage *makeUIImageFromIplImage(IplImage *iplimage) {
    assert(iplimage != NULL 
           && iplimage->depth == IPL_DEPTH_8U 
           && (iplimage->nChannels == 3 
               || iplimage->nChannels == 4)
           );

    IplImage *iplimage4 = cvCreateImage(cvGetSize(iplimage), 
                                        iplimage->depth,
                                        4);
    assert(iplimage4 != NULL);
    if (iplimage->nChannels == 3) {
        cvCvtColor(iplimage, iplimage4, CV_BGR2RGBA);
    } else {
        cvCopyImage(iplimage, iplimage4);
    }

    UIImage *uiimage = nil;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = 
        CGBitmapContextCreate(iplimage4->imageData, 
                              iplimage4->width, 
                              iplimage4->height, 
                              iplimage4->depth, 
                              iplimage4->widthStep,
                              colorSpace, 
                              kCGImageAlphaPremultipliedLast);
    if (context != NULL)
    {
        CGImageRef cgimage = CGBitmapContextCreateImage(context);
        if (cgimage != NULL)
        {
            uiimage = [UIImage imageWithCGImage:cgimage];
            CGImageRelease(cgimage);
        }
        CGContextRelease(context);
    }
    CGColorSpaceRelease(colorSpace);
    cvReleaseImage(&iplimage4);

    return uiimage;
}


@interface ViewController () {
    BOOL closeCameraSignal_;
    CvCapture * capture_;
    BOOL lockCamera_;
    UIViewAnimationTransition defaultTransition_;
    SystemSoundID tickSound_;
}
@property (strong, nonatomic) NSMutableArray * allImages;
@property (atomic, setter = unlockCamera:) BOOL lockCamera;
@property (nonatomic) int showImageIndex;

- (NSString *)getDataPath;
- (NSString *)getRandomFilePath;
- (void)alertWithMessage:(NSString *)message;
- (void)grabFrame:(NSTimer *)timer;
- (void)stopCapture;
- (void)startCapture;
- (void)addImage:(UIImage*)image;
- (void)animateWithParantView:(UIView *)parentView 
                    enterView:(UIView *)inView
                     exitView:(UIView *)outView 
                   transition:(UIViewAnimationTransition)transitionType;
- (void)removeImageAtIndex:(NSInteger)index;
- (void)saveImageAtIndex:(NSInteger)index;
@end

@implementation ViewController

@synthesize backgroundView, flipView, mainView;
@synthesize cameraView, messageLabel; 
@synthesize tapGesture;
@synthesize controlBar, pageLabel, saveButton, deleteButton, pageControl;
@synthesize allImages = allImages_;
@synthesize showImageIndex = showImageIndex_;
@dynamic lockCamera;

- (BOOL)lockCamera {
    BOOL isLock = lockCamera_;
    lockCamera_ = YES;
    return !isLock;
}

- (void)setShowImageIndex:(int)_showImageIndex {
    showImageIndex_ = _showImageIndex;
    int numImages = [self.allImages count];
    if (numImages > 0) {
        showImageIndex_ %= numImages;
        self.mainView.image = [self.allImages objectAtIndex:showImageIndex_];
        self.pageControl.value = showImageIndex_;
    } else {
        self.mainView.image = nil;
        self.pageControl.value = 0;
    }
    self.pageLabel.text = [NSString stringWithFormat:
                           @"%d/%d", 
                           showImageIndex_+1, 
                           numImages];
    [self.pageLabel sizeToFit];
}

- (void)setAllImages:(NSMutableArray *)_allImages {
    allImages_ = _allImages;
    self.pageControl.stepValue = 1.0;
    self.pageControl.minimumValue = 0.0;
    int numImages = 0;
    if (allImages_) {
        numImages = [allImages_ count];   
    }
    self.pageControl.maximumValue = (numImages > 0) ? (numImages - 1) : 0;
}

enum {CAM_UNLOCK = 0};
- (void)unlockCamera:(BOOL)lockCamera {
    lockCamera_ = CAM_UNLOCK;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    capture_ = NULL;
    closeCameraSignal_ = NO;
    defaultTransition_ = UIViewAnimationTransitionFlipFromLeft;
    
    // load image from jpg file
    UIImage *uiimage = nil;
    NSArray *filePaths = [NSBundle pathsForResourcesOfType:nil 
                                        inDirectory:[self getDataPath]];
    filePaths = [filePaths arrayByAddingObjectsFromArray:
                 [[NSBundle mainBundle] pathsForResourcesOfType:@"jpg" 
                                                    inDirectory:nil]];
    NSMutableArray *imageArray = [[NSMutableArray alloc] init];
    for (NSString *fPath in filePaths) {
        IplImage *iplimage = cvLoadImage([fPath UTF8String], 
                                         CV_LOAD_IMAGE_COLOR);
        if (iplimage) {
            // transform the IplImage* to UIImage* for display
            uiimage = makeUIImageFromIplImage(iplimage);
            // clean up
            cvReleaseImage(&iplimage);
            [imageArray addObject:uiimage];
        }
    }
    self.allImages = imageArray;
    self.showImageIndex = [imageArray count] - 1;
    
    if ([imageArray count] == 0) {
        self.saveButton.enabled = NO;
        self.deleteButton.enabled = NO;
        self.saveButton.alpha = 0.5;
        self.deleteButton.alpha = 0.5;
    }
    
    AudioServicesCreateSystemSoundID(
        (__bridge CFURLRef)[NSURL fileURLWithPath:
                            [[NSBundle mainBundle] pathForResource:@"tick"
                                                            ofType:@"aiff"]],
        &tickSound_);
}

- (void)viewDidUnload
{
    [self stopCapture];
    self.allImages = nil;
    self.backgroundView = nil;
    self.flipView = nil;
    self.mainView = nil;
    self.cameraView = nil;
    self.tapGesture = nil;
    self.messageLabel = nil;
    self.controlBar = nil;
    self.pageLabel = nil;
    self.saveButton = nil;
    self.deleteButton = nil;
    self.pageControl = nil;
    AudioServicesDisposeSystemSoundID(tickSound_);
    
    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:
    (UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer 
       shouldReceiveTouch:(UITouch *)touch {
    if (capture_ == NULL 
        && (touch.view == self.saveButton
            || touch.view == self.deleteButton
            || touch.view == self.pageControl)        
        && gestureRecognizer == self.tapGesture) {
        return NO;
    }
    return YES;
}

- (NSString *)getDataPath {
    NSString *path = [[[NSBundle mainBundle] bundlePath] 
                      stringByAppendingPathComponent:@"photos"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL checkDir;
    if (![fileManager fileExistsAtPath:path isDirectory:&checkDir] 
        || !checkDir) {
        [fileManager removeItemAtPath:path error:nil];
        [fileManager createDirectoryAtPath:path 
               withIntermediateDirectories:NO
                                attributes:nil
                                     error:nil];
    }
    return path;
}

- (NSString *)getRandomFilePath {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init]; 
    [dateFormatter setDateFormat:@"yyyyMMddHHmmss"];
    NSString *fileName = [dateFormatter stringFromDate:[NSDate date]];
    NSString *filePath = [[self getDataPath] 
                stringByAppendingFormat:@"/%@.jpg", fileName];
    return filePath;
}

- (void)grabFrame:(NSTimer *)timer {
    // grab a frame from the camera
    IplImage *frame = cvQueryFrame(capture_);
    if (frame != NULL) {
        // display on |cameraView|
        CvMat mapMat = cvMat(2, 3, CV_32FC1, 0);
        CvSize fixSize = cvSize(frame->width, frame->height);
        float map[] = {
            1, 0, 0,
            0, 1, 0,
            -1, 0, frame->width-1, 
            0, -1, frame->height-1,
            1, 0, 0
        };
        switch (self.interfaceOrientation) {
            case UIInterfaceOrientationPortrait:
                cvSetData(&mapMat, map, CV_AUTOSTEP);
                break;
            case UIInterfaceOrientationLandscapeRight:
                cvSetData(&mapMat, map+3, CV_AUTOSTEP);
                fixSize = cvSize(frame->height, frame->width);
                break;
            case UIInterfaceOrientationPortraitUpsideDown:
                cvSetData(&mapMat, map+6, CV_AUTOSTEP);
                break;
            case UIInterfaceOrientationLandscapeLeft:
                cvSetData(&mapMat, map+9, CV_AUTOSTEP);
                fixSize = cvSize(frame->height, frame->width);
                break;
        }
        IplImage *fixFrame = cvCreateImage(fixSize, 
                                           frame->depth, 
                                           frame->nChannels);
        cvWarpAffine(frame, 
                     fixFrame, 
                     &mapMat, 
                     CV_INTER_NN+CV_WARP_FILL_OUTLIERS, 
                     cvScalarAll(0));
        
        UIImage *uiimage = makeUIImageFromIplImage(fixFrame);
        self.cameraView.image = uiimage;
        //cvReleaseImage(&frame);
        cvReleaseImage(&fixFrame);
    }
    if (closeCameraSignal_) {
        self.cameraView.image = nil;
        cvReleaseCapture(&capture_);
        [self alertWithMessage:@" Camera Closed "];
        [timer invalidate];
    }
}

- (void)addImage:(UIImage *)inImage {
    [self.allImages addObject:inImage];
    self.pageControl.maximumValue = [self.allImages count] - 1;
    if (![self.deleteButton isEnabled]) {
        self.deleteButton.enabled = YES;  
        self.deleteButton.alpha = 1.0;
    }
    if (![self.saveButton isEnabled]) {
        self.saveButton.enabled = YES;
        self.saveButton.alpha = 1.0;
    }
}

- (void)alertWithMessage:(NSString *)message {
    UILabel *label = self.messageLabel;
    label.text = message;
    label.alpha = 1.0;
    label.backgroundColor = [UIColor whiteColor];
    [label sizeToFit];
    CGSize viewSize = self.view.bounds.size;
    label.center = CGPointMake(viewSize.width/2, viewSize.height/2);
    [UIView animateWithDuration:2 animations:^{
        label.alpha = 0.0;
    }];
}

- (void)stopCapture {
    closeCameraSignal_ = YES;
    [self animateWithParantView:self.view
                      enterView:self.backgroundView
                       exitView:self.cameraView
                     transition:defaultTransition_];
    //self.controlBar.hidden = NO;
}

- (void)startCapture {
    // !!!assure capture == NULL
    if ([self lockCamera]) {
        // lock the camera and, when success, process it.
        capture_ = cvCreateCameraCapture(-1);
        [self unlockCamera:CAM_UNLOCK];
        if (capture_ == NULL) {
            [self alertWithMessage:@" Open Camera Failed! "];
        } else {
            closeCameraSignal_ = NO;
            [self alertWithMessage:@" Camera Opened "];
            NSTimer *timer = 
                [NSTimer scheduledTimerWithTimeInterval:0.03 
                                                 target:self 
                                               selector:@selector(grabFrame:) 
                                               userInfo:nil 
                                                repeats:YES];
            [timer fire];
            //self.controlBar.hidden = YES;
            [self animateWithParantView:self.view
                              enterView:self.cameraView
                               exitView:self.backgroundView
                             transition:defaultTransition_];
        }
    }
}

- (void)animateWithParantView:(UIView *)parentView 
                    enterView:(UIView *)inView
                     exitView:(UIView *)outView 
                   transition:(UIViewAnimationTransition)transitionType {
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:1];
    [UIView setAnimationTransition:transitionType 
                           forView:parentView
                             cache:YES];
    if (!outView.hidden) {
        outView.hidden = YES;
    }
    if (inView.hidden) {
        inView.hidden = NO;
    }
    [UIView commitAnimations];
}

- (IBAction)tapResponder:(UITapGestureRecognizer *)recognizer {
    // tap the screen to take a photo
    if (capture_ == NULL) {
        [self startCapture]; 
    } else if (self.cameraView.image) {
        UIImage *uiimage = self.cameraView.image;
        [self addImage:uiimage];
        self.showImageIndex = [self.allImages count] - 1;
        AudioServicesPlaySystemSound(tickSound_);
        [self stopCapture];
    }
}

- (IBAction)swipeResponder:(UISwipeGestureRecognizer *)recognizer {
    // swipe the screen to change the background picture
    int totalPages = [self.allImages count];
    int nextPage = showImageIndex_;
    
    // make an animation for changing the background image
    defaultTransition_ = UIViewAnimationTransitionNone;
    switch (recognizer.direction) {
        case UISwipeGestureRecognizerDirectionUp:
            nextPage = nextPage + 1;
            defaultTransition_ = UIViewAnimationTransitionCurlUp;
            break;
        case UISwipeGestureRecognizerDirectionDown:
            nextPage = nextPage + totalPages - 1;
            defaultTransition_ = UIViewAnimationTransitionCurlDown;
            break;
        case UISwipeGestureRecognizerDirectionLeft:
            nextPage = nextPage + 1;
            defaultTransition_ = UIViewAnimationTransitionFlipFromRight;
            break;
        case UISwipeGestureRecognizerDirectionRight:
            nextPage = nextPage + totalPages - 1;
            defaultTransition_ = UIViewAnimationTransitionFlipFromLeft;
            break;
    }
    if (capture_) {
        [self stopCapture];
    } /*else if (recognizer.direction == UISwipeGestureRecognizerDirectionLeft || 
               recognizer.direction == UISwipeGestureRecognizerDirectionRight) {
        [self startCapture];
    }*/ else if (totalPages > 1) {
        self.flipView.image = self.mainView.image;
        self.showImageIndex = nextPage;
        [self animateWithParantView:self.backgroundView 
                          enterView:self.mainView
                           exitView:self.flipView 
                         transition:defaultTransition_];
    }
}

- (void)removeImageAtIndex:(NSInteger)index {
    [self.allImages removeObjectAtIndex:index];
    int numImages = [self.allImages count];
    self.pageControl.maximumValue = (numImages > 0) ? (numImages - 1) : 0;
    if (self.showImageIndex >= numImages) {
        self.showImageIndex = numImages - 1;
    } else {
        // update |self.pageLabel|, |self.mainView.image| and |self.pageControl|
        self.showImageIndex = self.showImageIndex;  
    }
    if (numImages <= 0) {
        self.deleteButton.enabled = NO;
        self.saveButton.enabled = NO;
        self.deleteButton.alpha = 0.5;
        self.saveButton.alpha = 0.5;
    }
}

- (void)saveImageAtIndex:(NSInteger)index {
    UIImage *uiimage = [self.allImages objectAtIndex:index];
    NSString *filePath = [self getRandomFilePath];
    if ([UIImageJPEGRepresentation(uiimage, 1.0) writeToFile:filePath
                                                  atomically:YES]) {
        [self alertWithMessage:
         [NSString stringWithFormat:@"%@ saved", [filePath lastPathComponent]]];
    } else {
        [self alertWithMessage:
         [NSString stringWithFormat:@"%failed in saving"]];
    }
}

- (IBAction)flipPage:(id)sender {
    if (sender == self.pageControl) {
        self.showImageIndex = [(UIStepper *)sender value];
    }
}

- (IBAction)deleteImage:(id)sender {
    if (sender == self.deleteButton) {
        [self removeImageAtIndex:self.showImageIndex];
    }
}

- (IBAction)saveImage:(id)sender {
    if (sender == self.saveButton) {
        [self saveImageAtIndex:self.showImageIndex];
    }
}

@end
