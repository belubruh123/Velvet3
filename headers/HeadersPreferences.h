#import <Foundation/Foundation.h>
#import <Preferences/PSSpecifier.h>
#import <AudioToolbox/AudioServices.h>
#import <rootless.h>

#import "CoreServices.h"
#import "Log.h"
#import "MaterialKit.h"
#import "NSTask.h"
#import "Preferences.h"
#import "QuartzCore.h"
#import "UIColor+Private.h"
#import "UIImage+Private.h"
#import "UIView+Private.h"
#import "UIViewController+Private.h"
#import "Velvet3/ColorDetection.h"
#import "Velvet3/UIColor+Velvet.h"
#import "Velvet3/Velvet3AppearanceCell.h"
#import "Velvet3/Velvet3AppSelectController.h"
#import "Velvet3/Velvet3Button.h"
#import "Velvet3/Velvet3Colorizer.h"
#import "Velvet3/Velvet3ColorPicker.h"
#import "Velvet3/Velvet3CustomizationController.h"
#import "Velvet3/Velvet3LinkCell.h"
#import "Velvet3/Velvet3PrefsManager.h"
#import "Velvet3/Velvet3PreviewController.h"
#import "Velvet3/Velvet3PreviewView.h"
#import "Velvet3/Velvet3RootListController.h"
#import "Velvet3/Velvet3SettingsController.h"
#import "Velvet3/Velvet3Slider.h"
#import "Velvet3/Velvet3Switch.h"

#define kVelvetColor [UIColor colorWithRed: 0.38 green: 0.76 blue: 1.00 alpha: 1.00]