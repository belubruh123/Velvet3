#import "VLTRuntime.h"
#import <os/log.h>

#pragma mark - Paths

// One directory, so everything the user might need to touch is in one place in Filza.
static NSString *const kVLTPrefsDir  = @"/var/mobile/Library/Preferences";
static NSString *const kVLTDisabled  = @"/var/mobile/Library/Preferences/com.belubruh123.velvet3.disabled";
static NSString *const kVLTCounter   = @"/var/mobile/Library/Preferences/com.belubruh123.velvet3.launchcount";
static NSString *const kVLTReconFlag = @"/var/mobile/Library/Preferences/com.belubruh123.velvet3.recon";
static NSString *const kVLTReconSafeFlag = @"/var/mobile/Library/Preferences/com.belubruh123.velvet3.reconsafe";
static NSString *const kVLTReconOut  = @"/var/mobile/Library/Preferences/com.belubruh123.velvet3.recon.txt";

// Three consecutive loads that never reached the "SpringBoard survived" mark.
static const int kVLTMaxConsecutiveLaunches = 3;
// How long SpringBoard has to stay alive before we call the load a success.
static const NSTimeInterval kVLTWatchdogGrace = 20.0;
// Stop appending once the recon file gets big; it is a diagnostic, not a log.
static const unsigned long long kVLTReconMaxBytes = 4 * 1024 * 1024;

#pragma mark - Logging

static os_log_t VLTLogHandle(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.belubruh123.velvet3", "tweak"); });
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

    // class_getInstanceVariable already walks superclasses, but we do it explicitly so
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
        // Apple's ivars are underscore-prefixed; callers usually pass the KVC-style name.
        iv = VLTFindIvar(obj, [@"_" stringByAppendingString:name]);
    }
    if (!iv) return nil;

    // Reading a non-object ivar as `id` would hand ARC an integer to release. Only
    // object and Class ivars are safe here.
    const char *enc = ivar_getTypeEncoding(iv);
    if (!enc || (enc[0] != '@' && enc[0] != '#')) return nil;

    return object_getIvar(obj, iv);
}

id VLTSafePerform(id obj, SEL selector) {
    if (!obj || !selector) return nil;
    if (![obj respondsToSelector:selector]) return nil;

    Method method = class_getInstanceMethod(object_getClass(obj), selector);
    if (!method) return nil;

    // Only object returns. Calling through a mismatched signature (say, a selector that
    // now returns a struct or a primitive) corrupts registers and crashes.
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
    // Class does not exist on this iOS version — nothing can match it.
    return NO;
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

#pragma mark - Load safety

static int VLTReadLaunchCount(void) {
    NSString *s = [NSString stringWithContentsOfFile:kVLTCounter encoding:NSUTF8StringEncoding error:NULL];
    return s ? s.intValue : 0;
}

static void VLTWriteLaunchCount(int count) {
    [[NSString stringWithFormat:@"%d", count] writeToFile:kVLTCounter
                                               atomically:YES
                                                 encoding:NSUTF8StringEncoding
                                                    error:NULL];
}

BOOL VLTShouldLoad(void) {
    NSFileManager *fm = NSFileManager.defaultManager;

    // 1. Manual kill switch. Create this file in Filza to make the tweak inert without
    //    uninstalling it — the way out of a crash loop from safe mode.
    if ([fm fileExistsAtPath:kVLTDisabled]) {
        VLTLog(@"disabled by kill switch at %@ — not loading", kVLTDisabled);
        return NO;
    }

    // 2. Version gate. Everything below hooks classes that did not exist before iOS 15.
    if (@available(iOS 15.0, *)) {
        // ok
    } else {
        VLTLog(@"iOS < 15 — not loading");
        return NO;
    }

    // 3. Crash watchdog. Each load bumps a counter; surviving the grace period resets it. A
    //    genuine crash loop never gets to the reset, so the counter climbs and we bow
    //    out before the user has to fight their way through safe mode.
    int count = VLTReadLaunchCount() + 1;
    VLTWriteLaunchCount(count);

    if (count >= kVLTMaxConsecutiveLaunches) {
        VLTLog(@"%d consecutive loads without a successful launch — self-disabling", count);
        [@"self-disabled by crash watchdog" writeToFile:kVLTDisabled
                                             atomically:YES
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
        VLTWriteLaunchCount(0);
        return NO;
    }

    return YES;
}

void VLTArmWatchdogReset(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVLTWatchdogGrace * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        VLTWriteLaunchCount(0);
        VLTLog(@"SpringBoard survived %.0fs — watchdog reset", kVLTWatchdogGrace);
    });
}

#pragma mark - Recon

BOOL VLTReconSafeMode(void) {
    static BOOL safeMode;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        safeMode = [NSFileManager.defaultManager fileExistsAtPath:kVLTReconSafeFlag];
    });
    return safeMode;
}

BOOL VLTReconEnabled(void) {
    static BOOL enabled;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        enabled = [NSFileManager.defaultManager fileExistsAtPath:kVLTReconFlag];
    });
    // Observation-only mode still needs the dumps written — that is the whole point.
    return enabled || VLTReconSafeMode();
}

static void VLTReconAppend(NSString *text) {
    if (!text.length) return;

    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.belubruh123.velvet3.recon", DISPATCH_QUEUE_SERIAL); });

    dispatch_async(queue, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        if (![fm fileExistsAtPath:kVLTReconOut]) {
            [fm createFileAtPath:kVLTReconOut contents:nil attributes:nil];
        }

        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kVLTReconOut];
        if (!fh) return;
        @try {
            unsigned long long end = [fh seekToEndOfFile];
            if (end < kVLTReconMaxBytes) {
                [fh writeData:[text dataUsingEncoding:NSUTF8StringEncoding]];
            }
        } @catch (__unused NSException *e) {
            // A diagnostic dump is never worth taking SpringBoard down for.
        }
        [fh closeFile];
    });
}

void VLTReconNote(NSString *format, ...) {
    if (!VLTReconEnabled() || !format) return;
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    VLTReconAppend([msg stringByAppendingString:@"\n"]);
}

NSString *VLTDescribe(id obj) {
    if (!obj) return @"** nil **";
    return NSStringFromClass(object_getClass(obj));
}

void VLTReconDumpClassesWithPrefixes(NSArray<NSString *> *prefixes) {
    if (!VLTReconEnabled() || prefixes.count == 0) return;

    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (!classes) return;

    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        const char *raw = class_getName(classes[i]);
        if (!raw) continue;
        NSString *name = @(raw);
        for (NSString *prefix in prefixes) {
            if ([name hasPrefix:prefix]) {
                [matches addObject:name];
                break;
            }
        }
    }
    free(classes);

    [matches sortUsingSelector:@selector(caseInsensitiveCompare:)];

    NSMutableString *out = [NSMutableString stringWithFormat:
        @"\n========== REGISTERED CLASSES matching %@ (%lu) ==========\n",
        [prefixes componentsJoinedByString:@", "], (unsigned long)matches.count];
    for (NSString *name in matches) {
        [out appendFormat:@"   %@\n", name];
    }
    VLTReconAppend(out);
}

void VLTReconDumpClassAvailability(NSArray<NSString *> *classNames) {
    if (!VLTReconEnabled()) return;

    NSMutableString *out = [NSMutableString stringWithString:
        @"\n========== iOS 15/16 CLASSES VELVET 2 RELIED ON ==========\n"];
    for (NSString *name in classNames) {
        Class cls = NSClassFromString(name);
        [out appendFormat:@"   %-45@ %@\n", name, cls ? @"present" : @"** MISSING **"];
    }
    VLTReconAppend(out);
}

void VLTReconDumpObject(id obj, NSString *label) {
    if (!VLTReconEnabled() || !obj) return;

    // Each class only needs dumping once; notifications arrive constantly.
    static NSMutableSet<NSString *> *seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet new]; });

    NSString *clsName = NSStringFromClass(object_getClass(obj));
    NSString *key = [NSString stringWithFormat:@"%@|%@", label, clsName];
    @synchronized (seen) {
        if ([seen containsObject:key]) return;
        [seen addObject:key];
    }

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"\n========== %@ : %@ ==========\n", label, clsName];

    [out appendString:@"-- class chain --\n"];
    for (Class c = object_getClass(obj); c != Nil; c = class_getSuperclass(c)) {
        [out appendFormat:@"   %s\n", class_getName(c)];
    }

    for (Class c = object_getClass(obj); c != Nil; c = class_getSuperclass(c)) {
        if (c == [NSObject class]) break;

        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(c, &ivarCount);
        if (ivarCount) {
            [out appendFormat:@"-- ivars of %s --\n", class_getName(c)];
            for (unsigned int i = 0; i < ivarCount; i++) {
                const char *name = ivar_getName(ivars[i]);
                const char *type = ivar_getTypeEncoding(ivars[i]);
                NSString *valueClass = @"";
                if (type && (type[0] == '@' || type[0] == '#')) {
                    id v = object_getIvar(obj, ivars[i]);
                    if (v) valueClass = [NSString stringWithFormat:@"  -> %@", NSStringFromClass(object_getClass(v))];
                }
                [out appendFormat:@"   %-40s %s%@\n", name ?: "?", type ?: "?", valueClass];
            }
        }
        if (ivars) free(ivars);

        unsigned int propCount = 0;
        objc_property_t *props = class_copyPropertyList(c, &propCount);
        if (propCount) {
            [out appendFormat:@"-- properties of %s --\n", class_getName(c)];
            for (unsigned int i = 0; i < propCount; i++) {
                [out appendFormat:@"   %s\n", property_getName(props[i])];
            }
        }
        if (props) free(props);
    }

    VLTReconAppend(out);
}

static void VLTReconDumpTreeInternal(UIView *view, NSMutableString *out, NSUInteger indent, NSUInteger maxDepth) {
    if (!view || indent > maxDepth) return;

    NSMutableString *pad = [NSMutableString string];
    for (NSUInteger i = 0; i < indent; i++) [pad appendString:@"  "];

    [out appendFormat:@"%@%@  frame=(%.1f,%.1f,%.1f,%.1f) alpha=%.2f%@\n",
                      pad,
                      NSStringFromClass(object_getClass(view)),
                      view.frame.origin.x, view.frame.origin.y,
                      view.frame.size.width, view.frame.size.height,
                      view.alpha,
                      view.hidden ? @" HIDDEN" : @""];

    for (UIView *sub in view.subviews) {
        VLTReconDumpTreeInternal(sub, out, indent + 1, maxDepth);
    }
}

void VLTReconDumpTree(UIView *root, NSString *label, NSUInteger depth) {
    if (!VLTReconEnabled() || !root) return;

    // Once per root class is plenty — the tree shape does not change per notification.
    static NSMutableSet<NSString *> *seenTrees;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seenTrees = [NSMutableSet new]; });

    NSString *key = [NSString stringWithFormat:@"%@|%@", label, NSStringFromClass(object_getClass(root))];
    @synchronized (seenTrees) {
        if ([seenTrees containsObject:key]) return;
        [seenTrees addObject:key];
    }

    NSMutableString *out = [NSMutableString stringWithFormat:@"\n========== VIEW TREE: %@ ==========\n", label];
    VLTReconDumpTreeInternal(root, out, 0, depth);
    VLTReconAppend(out);
}
