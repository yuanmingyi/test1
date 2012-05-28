//
//  ViewController.h
//  test1
//
//  Created by Yuan Mingyi on 12-5-27.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController <UIGestureRecognizerDelegate>

@property (weak, nonatomic) IBOutlet UIView * backgroundView;
@property (weak, nonatomic) IBOutlet UIImageView * flipView;
@property (weak, nonatomic) IBOutlet UIImageView * mainView;
@property (weak, nonatomic) IBOutlet UIImageView * cameraView;
@property (weak, nonatomic) IBOutlet UITapGestureRecognizer * tapGesture;
@property (weak, nonatomic) IBOutlet UILabel * messageLabel;
@property (weak, nonatomic) IBOutlet UIView * controlBar;
@property (weak, nonatomic) IBOutlet UIButton * saveButton;
@property (weak, nonatomic) IBOutlet UIButton * deleteButton;
@property (weak, nonatomic) IBOutlet UILabel * pageLabel;
@property (weak, nonatomic) IBOutlet UIStepper * pageControl;

- (IBAction)tapResponder:(UITapGestureRecognizer *)recognizer;
- (IBAction)swipeResponder:(UISwipeGestureRecognizer *)recognizer;
- (IBAction)flipPage:(id)sender;
- (IBAction)deleteImage:(id)sender;
- (IBAction)saveImage:(id)sender;

@end
