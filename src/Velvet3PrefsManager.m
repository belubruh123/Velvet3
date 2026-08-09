#import "../headers/HeadersTweak.h"

@implementation Velvet3PrefsManager

static void sendUpdateNotification() {
    // Send the notification to our hooks
    [[NSNotificationCenter defaultCenter] postNotificationName:@"com.tallplay.velvet3/updateStyle" object:nil];
}

+ (instancetype)sharedInstance {
    static Velvet3PrefsManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[Velvet3PrefsManager alloc] initWithSuiteName:@"com.tallplay.velvet3"];
    });
    return sharedInstance;
}

- (instancetype)initWithSuiteName:(NSString *)suitename {
    Velvet3PrefsManager *prefs = [super initWithSuiteName:suitename];

    [prefs registerDefaults:@{
        @"enabled": @YES,
        @"appearance": @"default",
        @"backgroundEnabled": @NO,
        @"backgroundBlurHidden" : @NO,
        @"backgroundType": @"icon",
        @"backgroundIconAlpha": @50,
        @"backgroundGradientDirection": @"right",
        @"borderEnabled": @NO,
        @"borderWidth": @2,
        @"borderType": @"icon",
        @"borderIconAlpha": @100,
        @"borderGradientDirection": @"right",
        @"shadowEnabled": @NO,
        @"shadowWidth": @5,
        @"shadowType": @"icon",
        @"shadowIconAlpha": @100,
        @"lineEnabled": @NO,
        @"linePosition": @"left",
        @"lineWidth": @3,
        @"lineType": @"icon",
        @"lineIconAlpha": @100,
        @"lineGradientDirection": @"right",
        @"titleEnabled": @NO,
        @"titleType": @"icon",
        @"titleIconAlpha": @100,
        @"titleGradientDirection": @"right",
        @"messageEnabled": @NO,
        @"messageType": @"icon",
        @"messageIconAlpha": @100,
        @"messageGradientDirection": @"right",
        @"dateEnabled": @NO,
        @"dateType": @"icon",
        @"dateIconAlpha": @100,
        @"dateGradientDirection": @"right",
        @"cornerRadiusEnabled": @NO,
        @"cornerRadiusCustom": @19,
        @"appIconHidden": @NO,
        @"appIconCornerRadiusCircle": @NO,
        @"stackDimmingViewHidden": @NO
    }];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)sendUpdateNotification, CFSTR("com.tallplay.velvet3/preferenceUpdate"), NULL, CFNotificationSuspensionBehaviorCoalesce);

    return prefs;
}

- (id)settingForKey:(NSString *)key withIdentifier:(NSString *)identifier {
    if (identifier) {
        id result = [self objectForKey:[NSString stringWithFormat:@"%@_%@", key, identifier]];
        if (result) return result;
    }

    return [self objectForKey:key];
}

- (UIColor *)colorForKey:(NSString *)key withIdentifier:(NSString *)identifier {
    NSString *colorString = [self settingForKey:key withIdentifier:identifier];
    return [UIColor colorFromP3String:colorString];
}

- (CGFloat)alphaValueForKey:(NSString *)key withIdentifier:(NSString *)identifier {
    NSString *string = [self settingForKey:key withIdentifier:identifier];
    return [string floatValue] / 100;
}
@end