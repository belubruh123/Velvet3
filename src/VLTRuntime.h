// VLTRuntime — safe access to Apple's private view internals.
//
// Velvet 2 reached into SpringBoard's notification views with -valueForKey:. That works
// right up until Apple renames an ivar, at which point KVC raises NSUnknownKeyException
// inside SpringBoard, SpringBoard dies, and two deaths in a row put the device in safe
// mode. That is exactly what happens on iOS 17/18.
//
// Everything in here fails soft: if the thing you asked for does not exist on this iOS
// version, you get nil and the caller skips that bit of styling. No styling is always
// better than no SpringBoard.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - Safe private state access

/// Object-typed instance variable lookup by name, walking the superclass chain.
/// Tries both `name` and `_name`. Returns nil if the ivar is absent on this iOS
/// version, or if it holds something that is not an object. Never raises.
id VLTIvar(id obj, NSString *name);

/// First name in `names` that resolves. Use when an ivar was renamed between iOS
/// versions and you want to support both without branching on the version number.
id VLTIvarAny(id obj, NSArray<NSString *> *names);

/// Whether `obj`'s class (or a superclass) declares this ivar. Cheap existence probe.
BOOL VLTHasIvar(id obj, NSString *name);

/// Calls a zero-argument, object-returning selector only if `obj` actually implements
/// it. Private @property declarations in our headers are promises about iOS 15/16 that
/// iOS 18 need not keep — calling one that has been removed is an unrecognized-selector
/// crash, every bit as fatal as a bad KVC key. Route every private property through this.
id VLTSafePerform(id obj, SEL selector);

#pragma mark - Safe view-tree access

/// First *direct* subview that is a kind of `className`. nil if the class does not
/// exist on this iOS version or no subview matches. Replaces `self.subviews[0]`.
UIView *VLTSubviewOfClass(UIView *root, NSString *className);

/// Depth-first search of the whole subtree. Use when Apple has inserted an extra
/// container layer between versions.
UIView *VLTDescendantOfClass(UIView *root, NSString *className);

/// Bounds-checked sublayer access. nil rather than NSRangeException.
CALayer *VLTSublayerAtIndex(CALayer *layer, NSUInteger index);

#pragma mark - Drawing helpers

/// Corner radius + curve, using the public `cornerCurve` (iOS 13+) instead of the
/// private `CALayer.continuousCorners` the original tweak relied on.
void VLTApplyCorners(CALayer *layer, CGFloat radius, BOOL continuous);

#pragma mark - Logging

/// os_log under subsystem "com.tallplay.velvet3". Read with the `oslog` tool on
/// device, or Console.app over USB.
void VLTLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

#pragma mark - Load safety

/// Full pre-flight for %ctor: honours the kill switch, trips the crash watchdog, and
/// checks the OS version. NO if the tweak must stay inert this boot.
BOOL VLTShouldLoad(void);

/// Call once after a successful load. Schedules the watchdog reset that proves
/// SpringBoard survived us.
void VLTArmWatchdogReset(void);

#pragma mark - Recon (read-only introspection)

/// Recon writes a dump of the real class names, ivars and view tree to
/// /var/mobile/Library/Preferences/com.tallplay.velvet3.recon.txt so we can see what
/// iOS 18 actually calls things. Enabled by creating the flag file
/// /var/mobile/Library/Preferences/com.tallplay.velvet3.recon (Filza: New > File).
BOOL VLTReconEnabled(void);

/// Observation only: dump what the runtime has, then install NO hooks at all. This is
/// the zero-risk first install on a new iOS version — it answers "did the dylib even get
/// injected?" and "what are these classes called now?" without a single method being
/// swizzled. Enabled by the flag file
/// /var/mobile/Library/Preferences/com.tallplay.velvet3.reconsafe
BOOL VLTReconSafeMode(void);

/// Class chain, every ivar (name + type + runtime class of the current value) and
/// every declared property of `obj`. Deduplicated: each class is dumped once.
void VLTReconDumpObject(id obj, NSString *label);

/// Indented view tree: class name, frame, and hidden/alpha, to `depth` levels.
void VLTReconDumpTree(UIView *root, NSString *label, NSUInteger depth);

/// Every class currently registered whose name starts with one of `prefixes`. This is
/// how we find out what iOS 18 renamed things to: ask the runtime for every
/// NCNotification* class rather than guessing. Runs once at load, needs no notification
/// to arrive first.
void VLTReconDumpClassesWithPrefixes(NSArray<NSString *> *prefixes);

/// For each name, whether that class exists on this iOS version. Tells us at a glance
/// which of the iOS 15/16 names Velvet 2 depended on have survived.
void VLTReconDumpClassAvailability(NSArray<NSString *> *classNames);

/// Free-form line into the recon file.
void VLTReconNote(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

#ifdef __cplusplus
}
#endif
