#import "../headers/HeadersTweak.h"

@implementation Velvet3PrefsManager

static void sendUpdateNotification() {
    // Send the notification to our hooks
    [[NSNotificationCenter defaultCenter] postNotificationName:@"com.belubruh123.velvet3/updateStyle" object:nil];
}

// Velvet 3.2.0 renamed the preferences domain from com.tallplay.velvet3. Carry the old
// settings across once, so upgrading does not silently reset everyone's configuration.
// Both the tweak (inside SpringBoard) and the prefs bundle reach this; whichever runs
// first does the work and the marker stops the other from repeating it.
static NSString *const kVLTPrefsDomain = @"com.belubruh123.velvet3";
static NSString *const kVLTLegacyPrefsDomain = @"com.tallplay.velvet3";
static NSString *const kVLTMigrationMarker = @"_migratedFromLegacyDomain";

static void migrateLegacyPreferences(NSUserDefaults *prefs) {
    if ([prefs boolForKey:kVLTMigrationMarker]) return;

    NSDictionary *current = [prefs persistentDomainForName:kVLTPrefsDomain];
    NSDictionary *old = [prefs persistentDomainForName:kVLTLegacyPrefsDomain];

    // Only fill keys with no persisted value under the new domain. Reading the persistent
    // domain rather than -objectForKey: keeps this correct wherever it sits relative to
    // -registerDefaults:, whose values would otherwise read back as real settings and
    // make every key look already-set.
    for (NSString *key in old) {
        if (current[key] == nil) [prefs setObject:old[key] forKey:key];
    }

    [prefs setBool:YES forKey:kVLTMigrationMarker];
}

+ (instancetype)sharedInstance {
    static Velvet3PrefsManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[Velvet3PrefsManager alloc] initWithSuiteName:kVLTPrefsDomain];
    });
    return sharedInstance;
}

- (instancetype)initWithSuiteName:(NSString *)suitename {
    Velvet3PrefsManager *prefs = [super initWithSuiteName:suitename];

    migrateLegacyPreferences(prefs);

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

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)sendUpdateNotification, CFSTR("com.belubruh123.velvet3/preferenceUpdate"), NULL, CFNotificationSuspensionBehaviorCoalesce);

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