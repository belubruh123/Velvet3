#import <UIKit/UIKit.h>

#import "../src/VLTRuntime.h"
#import "Log.h"
#import "MaterialKit.h"
#import "PlatterKit.h"
#import "QuartzCore.h"
#import "UIView+Private.h"
#import "UserNotificationsKit.h"
#import "UserNotificationsUIKit.h"
#import "Velvet3/ColorDetection.h"
#import "Velvet3/UIColor+Velvet.h"
#import "Velvet3/Velvet3Colorizer.h"
#import "Velvet3/Velvet3PrefsManager.h"

#define SYSTEM_VERSION_LESS_THAN(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)