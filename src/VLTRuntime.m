#import "VLTRuntime.h"
#import <os/log.h>

#pragma mark - Logging

static os_log_t VLTLogHandle(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.noisyflake.velvet2", "tweak"); });
    return log;
}

void VLTLog(NSString *format, ...) {
    if (!format) return;
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    os_log(VLTLogHandle(), "%{public}s", msg.UTF8String);
}

#pragma mark - Safe private state access

static Ivar VLTFindIvar(id obj, NSString *name) {
    if (!obj || name.length == 0) return NULL;

    // class_getInstanceVariable already walks superclasses, but do it explicitly so
    // behaviour does not depend on that staying true.
    for (Class cls = object_getClass(obj); cls != Nil; cls = class_getSuperclass(cls)) {
        Ivar iv = class_getInstanceVariable(cls, name.UTF8String);
        if (iv) return iv;
    }
    return NULL;
}

BOOL VLTHasIvar(id obj, NSString *name) {
    if (VLTFindIvar(obj, name)) return YES;
    if (![name hasPrefix:@"_"]) {
        return VLTFindIvar(obj, [@"_" stringByAppendingString:name]) != NULL;
    }
    return NO;
}

id VLTIvar(id obj, NSString *name) {
    if (!obj || name.length == 0) return nil;

    Ivar iv = VLTFindIvar(obj, name);
    if (!iv && ![name hasPrefix:@"_"]) {
        // Apple's ivars are underscore-prefixed; callers pass the KVC-style name.
        iv = VLTFindIvar(obj, [@"_" stringByAppendingString:name]);
    }
    if (!iv) return nil;

    // Reading a non-object ivar as `id` hands ARC an integer to release.
    const char *enc = ivar_getTypeEncoding(iv);
    if (!enc || (enc[0] != '@' && enc[0] != '#')) return nil;

    return object_getIvar(obj, iv);
}

id VLTSafePerform(id obj, SEL selector) {
    if (!obj || !selector) return nil;
    if (![obj respondsToSelector:selector]) return nil;

    Method method = class_getInstanceMethod(object_getClass(obj), selector);
    if (!method) return nil;

    // Object returns only — calling through a mismatched signature corrupts registers.
    char returnType[64] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (returnType[0] != '@' && returnType[0] != '#') return nil;

    // Direct IMP call rather than -performSelector:, which ARC cannot reason about.
    id (*invoke)(id, SEL) = (id (*)(id, SEL))method_getImplementation(method);
    return invoke(obj, selector);
}

id VLTIvarAny(id obj, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        id value = VLTIvar(obj, name);
        if (value) return value;
    }
    return nil;
}

#pragma mark - Safe view-tree access

static BOOL VLTIsKindOfClassNamed(id obj, NSString *className) {
    Class cls = NSClassFromString(className);
    if (cls) return [obj isKindOfClass:cls];
    return NO; // class absent on this iOS version — nothing can match
}

UIView *VLTSubviewOfClass(UIView *root, NSString *className) {
    if (!root || className.length == 0) return nil;
    for (UIView *sub in root.subviews) {
        if (VLTIsKindOfClassNamed(sub, className)) return sub;
    }
    return nil;
}

UIView *VLTDescendantOfClass(UIView *root, NSString *className) {
    if (!root || className.length == 0) return nil;
    for (UIView *sub in root.subviews) {
        if (VLTIsKindOfClassNamed(sub, className)) return sub;
        UIView *found = VLTDescendantOfClass(sub, className);
        if (found) return found;
    }
    return nil;
}

CALayer *VLTSublayerAtIndex(CALayer *layer, NSUInteger index) {
    NSArray<CALayer *> *sublayers = layer.sublayers;
    if (index >= sublayers.count) return nil;
    return sublayers[index];
}

#pragma mark - Drawing helpers

void VLTApplyCorners(CALayer *layer, CGFloat radius, BOOL continuous) {
    if (!layer) return;
    layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        layer.cornerCurve = continuous ? kCACornerCurveContinuous : kCACornerCurveCircular;
    }
}
