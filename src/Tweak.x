#import "../headers/HeadersTweak.h"

Velvet2PrefsManager *prefsManager;

static NSString *const kVelvetUpdateNotification = @"com.noisyflake.velvet2/updateStyle";
static NSString *const kVelvetFocusIdentifier    = @"com.noisyflake.velvetFocus";

#pragma mark - Private-state accessors
//
// Each of these may return nil. Reaching for private state with -valueForKey: or a bare
// @property call raises as soon as Apple moves something, and an exception in SpringBoard
// means safe mode rather than a log line.

/// The blur behind a notification. `backgroundMaterialView` is the iOS 15/16 property; if
/// it is gone, look for the material view in the tree instead.
static UIView *VelvetMaterialViewIn(UIView *view) {
    UIView *material = VLTSafePerform(view, @selector(backgroundMaterialView));
    if (material) return material;
    return VLTDescendantOfClass(view, @"MTMaterialView");
}

static UIView *VelvetContentViewIn(UIView *shortLookView) {
    UIView *content = VLTIvarAny(shortLookView, @[@"notificationContentView", @"contentView"]);
    if (content) return content;
    return VLTDescendantOfClass(shortLookView, @"NCNotificationSeamlessContentView");
}

/// The notification's section identifier — the per-app settings key. nil falls back to
/// the global settings, which is a reasonable degradation.
static NSString *VelvetIdentifierFor(id controller) {
    id request = VLTSafePerform(controller, @selector(notificationRequest));
    id identifier = VLTSafePerform(request, @selector(sectionIdentifier));
    return [identifier isKindOfClass:NSString.class] ? identifier : nil;
}

/// The view holding the app icon. iOS 15/16 exposed it as `badgedIconView.iconView`; on
/// iOS 18 the icon is a plain UIImageView inside NCBadgedIconView.
static UIView *VelvetAppIconViewIn(id contentView) {
    UIView *badgedIconView = VLTIvar(contentView, @"badgedIconView");
    if (!badgedIconView) return nil;

    id iconView = VLTSafePerform(badgedIconView, @selector(iconView));
    if ([iconView isKindOfClass:UIView.class]) return (UIView *)iconView;

    return VLTDescendantOfClass(badgedIconView, @"UIImageView");
}

/// The app icon image, which every "icon" colour type extracts its colour from.
///
/// iOS 15/16 provided this as `prominentIcon` / `subordinateIcon` on the content view.
/// **Both are gone in iOS 18** — NCNotificationSeamlessContentView has no icon property
/// any more. That single removal is why border, title, message and date colouring all did
/// nothing on iOS 18 while corner radius kept working: with no icon there is no colour to
/// extract, and every one of those features defaults to type "icon".
static UIImage *VelvetAppIconIn(id contentView) {
    id icon = VLTSafePerform(contentView, @selector(prominentIcon));
    if (![icon isKindOfClass:UIImage.class]) {
        icon = VLTSafePerform(contentView, @selector(subordinateIcon));
    }
    if ([icon isKindOfClass:UIImage.class]) return (UIImage *)icon;

    UIView *iconView = VelvetAppIconViewIn(contentView);
    if ([iconView isKindOfClass:UIImageView.class]) {
        return ((UIImageView *)iconView).image;
    }
    return nil;
}

/// iOS 15 kept this on the controller's content view; iOS 16 moved it onto the short look
/// view and renamed it. Try both rather than branching on the version, so a third
/// spelling later simply yields nil instead of an exception.
static UIView *VelvetStackDimmingViewFor(id controller, UIView *shortLookView) {
    UIView *dimming = VLTIvar(shortLookView, @"stackDimmingOverlayView");
    if (dimming) return dimming;

    UIView *controllerView = VLTIvar(controller, @"contentSizeManagingView");
    return VLTIvar(controllerView, @"stackDimmingView");
}

/// The two CALayers the accent line is drawn into, created defensively so the colorizer
/// never indexes into an empty sublayer array.
static void VelvetPrepareLayers(UIView *view) {
    if (!view) return;
    while (view.layer.sublayers.count < 2) {
        [view.layer insertSublayer:[CALayer layer] atIndex:0];
    }
}

static CGFloat VelvetCornerRadiusFor(NSString *identifier, CGFloat containerHeight) {
    CGFloat defaultRadius = SYSTEM_VERSION_LESS_THAN(@"16.0") ? 19 : 23.5;
    BOOL custom = [[prefsManager settingForKey:@"cornerRadiusEnabled" withIdentifier:identifier] boolValue];
    CGFloat radius = custom
        ? [[prefsManager settingForKey:@"cornerRadiusCustom" withIdentifier:identifier] floatValue]
        : defaultRadius;
    return MIN(radius, containerHeight / 2);
}

#pragma mark - Banner notifications

%group ShortLook

%hook NCNotificationShortLookViewController
%property (nonatomic, retain) UIView *velvetView;

-(void)viewDidLoad {
    %orig;

    UIView *view = VLTSafePerform(self, @selector(viewForPreview));
    if (!view) return;

    UIView *material = VelvetMaterialViewIn(view);
    UIView *host = material.superview ?: view;

    UIView *velvetView = [UIView new];
    VelvetPrepareLayers(velvetView);
    velvetView.clipsToBounds = YES;

    // Previously hardcoded index 1, assuming the blur sits at index 0. Place ourselves
    // directly in front of whatever the blur actually is, falling back to the very back
    // when there is no blur to anchor to.
    NSUInteger materialIndex = material ? [host.subviews indexOfObject:material] : NSNotFound;
    NSUInteger insertIndex = (materialIndex == NSNotFound) ? 0 : materialIndex + 1;
    [host insertSubview:velvetView atIndex:MIN(insertIndex, host.subviews.count)];

    self.velvetView = velvetView;

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(velvetUpdateStyle)
                                               name:kVelvetUpdateNotification
                                             object:nil];
}

-(void)viewDidLayoutSubviews {
    %orig;

    UIView *view = VLTSafePerform(self, @selector(viewForPreview));
    if (view.frame.size.width == 0) return;

    [self velvetUpdateStyle];
}

-(void)viewDidAppear:(BOOL)arg1 {
    %orig;

    UIView *view = VLTSafePerform(self, @selector(viewForPreview));
    UIView *contentView = VelvetContentViewIn(view);
    if (!contentView) return;

    Velvet2Colorizer *colorizer = [[Velvet2Colorizer alloc] initWithIdentifier:VelvetIdentifierFor(self)];
    colorizer.appIcon = VelvetAppIconIn(contentView);

    // dateLabel and the icon view are not fully built until after layout, hence doing
    // these two here rather than in velvetUpdateStyle.
    [colorizer colorDate:VLTIvar(contentView, @"dateLabel")];
    [colorizer setAppIconCornerRadius:VelvetAppIconViewIn(contentView)];
}

%new
-(void)velvetUpdateStyle {
    UIView *view = VLTSafePerform(self, @selector(viewForPreview));
    if (!view) return;

    NSString *identifier = VelvetIdentifierFor(self);
    UIView *material     = VelvetMaterialViewIn(view);
    UIView *contentView  = VelvetContentViewIn(view);
    UIView *stackDimming = VelvetStackDimmingViewFor(self, view);

    // Without a blur there is no frame to match and nothing to sit behind, so there is no
    // meaningful styling to do.
    if (!material) return;

    VelvetPrepareLayers(self.velvetView);
    self.velvetView.frame = material.frame;

    Velvet2Colorizer *colorizer = [[Velvet2Colorizer alloc] initWithIdentifier:identifier];
    colorizer.appIcon = VelvetAppIconIn(contentView);

    CGFloat radius = VelvetCornerRadiusFor(identifier, material.frame.size.height);
    BOOL continuous = radius < material.frame.size.height / 2;

    VLTApplyCorners(material.layer, radius, continuous);
    VLTApplyCorners(self.velvetView.layer, radius, radius < self.velvetView.frame.size.height / 2);
    VLTApplyCorners(view.layer, radius, continuous);
    VLTApplyCorners(material.superview.layer, radius, continuous);
    VLTApplyCorners(stackDimming.layer, radius, continuous);

    stackDimming.hidden = [[prefsManager settingForKey:@"stackDimmingViewHidden" withIdentifier:identifier] boolValue];

    [colorizer setAppIconCornerRadius:VelvetAppIconViewIn(contentView)];
    [colorizer colorBackground:self.velvetView];
    [colorizer setBackgroundBlur:material];
    [colorizer colorBorder:self.velvetView];
    [colorizer colorShadow:material];
    [colorizer colorLine:self.velvetView inFrame:material.frame];
    [colorizer colorTitle:VLTIvar(contentView, @"primaryTextLabel")];
    [colorizer colorMessage:VLTIvar(contentView, @"secondaryTextElement")];
    [colorizer colorDate:VLTIvar(contentView, @"dateLabel")];
    [colorizer setAppearance:self.view];
}

%end

%end // group ShortLook

#pragma mark - Focus summary platter

%group SummaryPlatter

%hook NCNotificationSummaryPlatterView
%property (nonatomic, retain) UIView *velvetView;
%property (nonatomic, assign) BOOL velvetObserving;

-(void)didMoveToWindow {
    %orig; // was omitted, silently dropping PLPlatterView's own behaviour

    if (!self.velvetView) {
        UIView *velvetView = [UIView new];
        VelvetPrepareLayers(velvetView);
        velvetView.clipsToBounds = YES;

        UIView *material = VLTDescendantOfClass(self, @"MTMaterialView");
        NSUInteger materialIndex = material ? [self.subviews indexOfObject:material] : NSNotFound;
        NSUInteger insertIndex = (materialIndex == NSNotFound) ? 0 : materialIndex + 1;
        [self insertSubview:velvetView atIndex:MIN(insertIndex, self.subviews.count)];

        self.velvetView = velvetView;
    }

    // didMoveToWindow fires on every re-parent; registering each time stacked up
    // duplicate observers.
    if (!self.velvetObserving) {
        self.velvetObserving = YES;
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(velvetUpdateStyle)
                                                   name:kVelvetUpdateNotification
                                                 object:nil];
    }
}

-(void)layoutSubviews {
    %orig;
    [self velvetUpdateStyle];
}

%new
-(void)velvetUpdateStyle {
    // Was self.subviews[0], an NSRangeException the moment the platter is laid out
    // before its blur exists.
    UIView *material = VLTDescendantOfClass(self, @"MTMaterialView");
    if (!material) return;

    UIView *contentView = VLTIvar(self, @"summaryContentView");

    Velvet2Colorizer *colorizer = [[Velvet2Colorizer alloc] initWithIdentifier:kVelvetFocusIdentifier];

    CGFloat radius = VelvetCornerRadiusFor(kVelvetFocusIdentifier, self.frame.size.height);

    VelvetPrepareLayers(self.velvetView);
    self.velvetView.frame = material.frame;

    VLTApplyCorners(material.layer, radius, radius < self.frame.size.height / 2);
    VLTApplyCorners(self.velvetView.layer, radius, radius < self.velvetView.frame.size.height / 2);

    [colorizer colorBackground:self.velvetView];
    [colorizer colorBorder:self.velvetView];
    [colorizer colorShadow:material];
    [colorizer colorLine:self.velvetView inFrame:material.frame];
    [colorizer colorTitle:VLTIvar(contentView, @"summaryTitleLabel")];
    [colorizer colorMessage:VLTIvar(contentView, @"summaryLabel")];
    [colorizer setAppearance:self];
}

%end

%end // group SummaryPlatter

#pragma mark - Content view (app icon visibility)

%group ContentView

%hook NCNotificationSeamlessContentView
%property (nonatomic, assign) BOOL velvetObserving;

-(void)didMoveToWindow {
    %orig;

    if (!self.velvetObserving) {
        self.velvetObserving = YES;
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(velvetUpdateStyle)
                                                   name:kVelvetUpdateNotification
                                                 object:nil];
    }
}

-(void)layoutSubviews {
    %orig;
    [self velvetUpdateStyle];
}

%new
-(void)velvetUpdateStyle {
    id controller = VLTSafePerform(self, @selector(_viewControllerForAncestor));
    Velvet2Colorizer *colorizer = [[Velvet2Colorizer alloc] initWithIdentifier:VelvetIdentifierFor(controller)];

    [colorizer toggleAppIconVisibility:VLTIvar(self, @"badgedIconView")
                             withTitle:VLTIvar(self, @"primaryTextLabel")
                               message:VLTIvar(self, @"secondaryTextElement")
                                footer:VLTIvar(self, @"footerTextLabel")
                          alwaysUpdate:YES];
}

%end

%end // group ContentView

#pragma mark - Stacked-notification recycling (iOS 15/16 only)

// Blanking out UIKit's view recycling stops stacked notifications inheriting a recycled
// neighbour's colour, but stubbing Apple's methods with no %orig is a blunt tool: it
// leaks views, and on the notification list as rewritten in iOS 17 it is a crash
// candidate. Keep it only where it is known to work — elsewhere velvetUpdateStyle runs on
// every layout pass anyway.
%group ListRecycleFix

%hook NCNotificationListView
-(void)recycleVisibleViews {}
-(void)_recycleViewIfNecessary:(id)arg1 {}
-(void)_recycleViewIfNecessary:(id)arg1 withDataSource:(id)arg2 {}
%end

%end // group ListRecycleFix

#pragma mark - Load

%ctor {
    @autoreleasepool {
        prefsManager = [NSClassFromString(@"Velvet2PrefsManager") sharedInstance];

        if (![[prefsManager objectForKey:@"enabled"] boolValue]) return;

        // Hook only what this iOS version actually has, rather than handing a class that
        // may be nil to the hooking engine.
        if (NSClassFromString(@"NCNotificationShortLookViewController")) {
            %init(ShortLook);
        } else {
            VLTLog(@"NCNotificationShortLookViewController missing — banner styling unavailable");
        }

        if (NSClassFromString(@"NCNotificationSummaryPlatterView")) %init(SummaryPlatter);
        if (NSClassFromString(@"NCNotificationSeamlessContentView")) %init(ContentView);

        if (SYSTEM_VERSION_LESS_THAN(@"17.0") && NSClassFromString(@"NCNotificationListView")) {
            %init(ListRecycleFix);
        }
    }
}
