// VLTRuntime — safe access to SpringBoard's private view internals.
//
// Velvet reaches into private notification views three ways, and all three raise when
// Apple moves something between iOS releases:
//
//     [view valueForKey:@"notificationContentView"]   NSUnknownKeyException
//     view.backgroundMaterialView                     unrecognized selector
//     self.subviews[0]                                NSRangeException
//
// Inside SpringBoard an uncaught exception is not a caught error — it takes the UI down,
// and twice in a row means safe mode. That is what happens on iOS 17/18, where several of
// the things Velvet reaches for have moved or gone.
//
// Everything here fails soft: if what you asked for does not exist on this iOS version
// you get nil, and the caller skips that piece of styling. No styling beats no
// SpringBoard.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Object-typed instance variable lookup by name, walking the superclass chain. Tries
/// both `name` and `_name`. nil if the ivar is absent on this iOS version, or if it holds
/// something that is not an object. Never raises.
id VLTIvar(id obj, NSString *name);

/// First name in `names` that resolves. For ivars renamed between iOS versions, so you
/// can support both spellings without branching on the version number.
id VLTIvarAny(id obj, NSArray<NSString *> *names);

/// Whether `obj`'s class or a superclass declares this ivar.
BOOL VLTHasIvar(id obj, NSString *name);

/// Calls a zero-argument, object-returning selector only if `obj` implements it. The
/// private @property declarations in headers/ are promises about iOS 15/16 that later
/// versions need not keep, and calling one that has been removed is an
/// unrecognized-selector crash. Route private properties through this.
id VLTSafePerform(id obj, SEL selector);

/// First direct subview that is a kind of `className`; nil if the class does not exist on
/// this iOS version or nothing matches. Replaces positional access like `subviews[0]`.
UIView *VLTSubviewOfClass(UIView *root, NSString *className);

/// Depth-first search of the whole subtree, for when Apple has inserted an extra
/// container between versions.
UIView *VLTDescendantOfClass(UIView *root, NSString *className);

/// Bounds-checked sublayer access; nil rather than NSRangeException.
CALayer *VLTSublayerAtIndex(CALayer *layer, NSUInteger index);

/// Corner radius and curve via the public `cornerCurve` (iOS 13+) rather than the private
/// `CALayer.continuousCorners`.
void VLTApplyCorners(CALayer *layer, CGFloat radius, BOOL continuous);

/// os_log under subsystem "com.noisyflake.velvet2".
void VLTLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

#ifdef __cplusplus
}
#endif
