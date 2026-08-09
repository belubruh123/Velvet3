#import "../headers/HeadersTweak.h"

Velvet3PrefsManager *prefsManager;

static NSString *const kVelvetUpdateNotification = @"com.tallplay.velvet3/updateStyle";
static NSString *const kVelvetFocusIdentifier    = @"com.tallplay.velvetFocus";

#pragma mark - Private-state accessors
//
// Every one of these is allowed to return nil. Upstream reached for these through
// -valueForKey: and bare @property calls, which raise on iOS 17/18 when Apple has moved
// something — and an exception in SpringBoard means safe mode, not a log line.

/// The blur behind a notification. `backgroundMaterialView` is the iOS 15/16 property;
/// if it is gone we go looking for the material view in the tree instead.
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

/// The notification's section identifier — the per-app settings key. nil means "use the
/// global settings", which is a fine degradation.
static NSString *VelvetIdentifierFor(id controller) {
    id request = VLTSafePerform(controller, @selector(notificationRequest));
    id identifier = VLTSafePerform(request, @selector(sectionIdentifier));
    return [identifier isKindOfClass:NSString.class] ? identifier : nil;
}

static UIImage *VelvetAppIconIn(id contentView) {
    id icon = VLTSafePerform(contentView, @selector(prominentIcon));
    if (![icon isKindOfClass:UIImage.class]) {
        icon = VLTSafePerform(contentView, @selector(subordinateIcon));
    }
    return [icon isKindOfClass:UIImage.class] ? (UIImage *)icon : nil;
}

static UIView *VelvetAppIconViewIn(id contentView) {
    id badgedIconView = VLTIvar(contentView, @"badgedIconView");
    id iconView = VLTSafePerform(badgedIconView, @selector(iconView));
    return [iconView isKindOfClass:UIView.class] ? (UIView *)iconView : nil;
}

/// iOS 15 kept this on the controller's content view; iOS 16 moved it onto the short
/// look view and renamed it. Try both rather than branching on the version number, so a
/// third spelling on iOS 18 simply yields nil instead of an exception.
static UIView *VelvetStackDimmingViewFor(id controller, UIView *shortLookView) {
    UIView *dimming = VLTIvar(shortLookView, @"stackDimmingOverlayView");
    if (dimming) return dimming;

    UIView *controllerView = VLTIvar(controller, @"contentSizeManagingView");
    return VLTIvar(controllerView, @"stackDimmingView");
}

/// The two CALayers Velvet draws its accent line into. Created defensively so a hook
/// that ran before we could set them up does not leave the colorizer indexing into an
/// empty sublayer array.
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

    // Upstream hardcoded index 1, assuming the blur sits at index 0. Place ourselves
    // directly in front of whatever the blur actually is, and fall back to the very
    // back if there is no blur to anchor to.
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

    // Recon: this is the one place we are guaranteed to hold a fully built notification,
    // so it is where we photograph iOS 18's real structure.
    VLTReconDumpTree(view, @"NCNotificationShortLookViewController.viewForPreview", 12);
    VLTReconDumpObject(self, @"short look controller");
    VLTReconDumpObject(view, @"short look view");
    VLTReconDumpObject(contentView, @"content view");

    if (!contentView) return;

    Velvet3Colorizer *colorizer = [[Velvet3Colorizer alloc] initWithIdentifier:VelvetIdentifierFor(self)];
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

    // Without a blur view we have no frame to match and nothing to sit behind, so there
    // is no meaningful styling to do. Bail rather than guess.
    if (!material) return;

    VelvetPrepareLayers(self.velvetView);
    self.velvetView.frame = material.frame;

    Velvet3Colorizer *colorizer = [[Velvet3Colorizer alloc] initWithIdentifier:identifier];
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
    %orig; // upstream omitted this, silently dropping PLPlatterView's own behaviour

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

    // didMoveToWindow fires every time the platter is re-parented; registering each time
    // stacked up duplicate observers upstream.
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
    // Upstream took self.subviews[0] here, which is an NSRangeException the moment the
    // platter is laid out before its blur exists.
    UIView *material = VLTDescendantOfClass(self, @"MTMaterialView");
    if (!material) return;

    VLTReconDumpTree(self, @"NCNotificationSummaryPlatterView", 10);

    UIView *contentView = VLTIvar(self, @"summaryContentView");

    Velvet3Colorizer *colorizer = [[Velvet3Colorizer alloc] initWithIdentifier:kVelvetFocusIdentifier];

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
    Velvet3Colorizer *colorizer = [[Velvet3Colorizer alloc] initWithIdentifier:VelvetIdentifierFor(controller)];

    [colorizer toggleAppIconVisibility:VLTIvar(self, @"badgedIconView")
                             withTitle:VLTIvar(self, @"primaryTextLabel")
                               message:VLTIvar(self, @"secondaryTextElement")
                                footer:VLTIvar(self, @"footerTextLabel")
                          alwaysUpdate:YES];
}

%end

%end // group ContentView

#pragma mark - Stacked-notification recycling (iOS 15/16 only)

// Upstream blanked out UIKit's view recycling to stop stacked notifications inheriting a
// recycled neighbour's colour. Stubbing Apple's methods with no %orig is a blunt tool: it
// leaks views, and on a notification list that Apple has since rewritten it is a prime
// crash candidate. We keep it only where it was known to work, and rely on
// velvetUpdateStyle running on every layout pass elsewhere.
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
        // Kill switch, crash watchdog and OS version gate, before we touch anything.
        if (!VLTShouldLoad()) return;

        prefsManager = [NSClassFromString(@"Velvet3PrefsManager") sharedInstance];
        if (![[prefsManager objectForKey:@"enabled"] boolValue]) {
            VLTLog(@"disabled in settings — not hooking");
            return;
        }

        if (VLTReconEnabled()) {
            VLTReconNote(@"\n\n########## Velvet 3 recon — %@ — iOS %@ ##########",
                         NSDate.date, UIDevice.currentDevice.systemVersion);
            VLTReconDumpClassAvailability(@[
                @"NCNotificationShortLookViewController",
                @"NCNotificationShortLookView",
                @"NCNotificationSeamlessContentView",
                @"NCNotificationSummaryPlatterView",
                @"NCNotificationSummaryContentView",
                @"NCNotificationListView",
                @"NCNotificationViewControllerView",
                @"NCBadgedIconView",
                @"MTMaterialView",
                @"PLPlatterView",
            ]);
            VLTReconDumpClassesWithPrefixes(@[@"NCNotification", @"NCBadged", @"MTMaterial", @"PLPlatter"]);
        }

        // Observation-only: we have written everything the runtime can tell us without
        // touching a single method. Stop here. If the dump file exists after a respring,
        // the dylib was injected — which on an arm64e device is exactly the question an
        // arm64-only build needs answered.
        if (VLTReconSafeMode()) {
            VLTLog(@"recon-safe mode — dumped runtime state, installing no hooks");
            VLTArmWatchdogReset();
            return;
        }

        // Hook only what this iOS version actually has. A %hook on a class that does not
        // exist is not something to hand to the hooking engine.
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

        // Nothing exploded on the way in. Let the watchdog clear itself once SpringBoard
        // has been up long enough to call this load a success.
        VLTArmWatchdogReset();
        VLTLog(@"loaded on iOS %@", UIDevice.currentDevice.systemVersion);
    }
}
