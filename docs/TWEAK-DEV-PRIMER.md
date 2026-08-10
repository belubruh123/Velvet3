# How iOS tweaks actually work

Written alongside the Velvet 2 → Velvet 3 port, using this repo as the worked example.
If you read one section, read [The two rules](#the-two-rules) — they are the difference
between a tweak that works and a tweak that puts your phone in safe mode.

---

## 1. What a tweak is

A tweak is **a dynamic library that gets loaded into somebody else's running process.**
That is the whole idea. There is no plugin API, no sandboxed extension point. Your code
is injected into Apple's process and runs with that process's identity and privileges.

Concretely, for Velvet 3:

```
/var/jb/Library/MobileSubstrate/DynamicLibraries/Velvet3.dylib    <- your code
/var/jb/Library/MobileSubstrate/DynamicLibraries/Velvet3.plist    <- who to load it into
```

The `.plist` is a filter. Ours (`Velvet3.plist`) says:

```
{ Filter = { Bundles = ( "com.apple.springboard" ); }; }
```

"Load me into any process whose bundle identifier is `com.apple.springboard`." That is
SpringBoard: the home screen, the lock screen, notifications, Control Center. Every
notification banner you see is a view SpringBoard built.

The thing that reads those plists and does the injecting is the **hooking library**. On
Dopamine 3 that is **ElleKit** (older jailbreaks used Cydia Substrate or libhooker; the
package name `mobilesubstrate` survives as a compatibility alias, which is why our
`control` says `Depends: ellekit | mobilesubstrate`).

The consequence worth internalising: **if your tweak crashes, SpringBoard crashes.** And
if SpringBoard crashes twice in quick succession, iOS boots it into *safe mode* with all
tweaks disabled. That is not a bug in the jailbreak — it is the seatbelt.

---

## 2. Hooking, and the Logos syntax

You change Apple's behaviour by **swizzling**: replacing the implementation of an
Objective-C method with your own, keeping a pointer to the original so you can still call
it. Theos gives you a preprocessor called **Logos** so you can write that declaratively.
Files ending `.x` (or `.xm` for Objective-C++) get run through it.

```objc
%hook NCNotificationShortLookViewController   // the class you are modifying

-(void)viewDidLoad {
    %orig;                                    // call Apple's implementation
    // ... your code ...
}

%end
```

The directives you will actually use:

| Directive | What it does |
|---|---|
| `%hook Class` / `%end` | Open/close a block of replacements for `Class` |
| `%orig` | Call the original implementation. Returns its value; takes its args |
| `%new` | Add a method that did not exist on the class before |
| `%property` | Add a property (backed by an associated object) to someone else's class |
| `%group Name` / `%end` | A named set of hooks you can install conditionally |
| `%init` / `%init(Name)` | Actually install the hooks. Nothing happens until you call it |
| `%ctor` | Runs when your dylib is loaded. This is your `main()` |

**`%orig` is almost never optional.** Omitting it means Apple's method never runs. Velvet
2 omitted it in `NCNotificationSummaryPlatterView -didMoveToWindow` — probably by
accident — and silently disabled `PLPlatterView`'s own setup. We put it back.

`%group` + conditional `%init` is how Velvet 3 stays safe across iOS versions:

```objc
%ctor {
    if (NSClassFromString(@"NCNotificationSummaryPlatterView")) %init(SummaryPlatter);
}
```

If Apple deleted that class in iOS 18, we simply never install those hooks, instead of
handing a `nil` class to the hooking engine and hoping.

---

## 3. The two rules

### Rule 1 — never let an exception escape a hook

In an app, an uncaught `NSException` kills the app. In SpringBoard it takes down the
whole UI, and twice in a row means safe mode. There is no "recoverable error" tier here.

### Rule 2 — never assume private state exists

Everything interesting in SpringBoard is private: undocumented classes, undocumented
ivars, undocumented properties. Apple renames them freely between releases, because from
their point of view nobody is looking. There are three ways people reach into that state,
and **all three crash** when the thing has moved:

```objc
[view valueForKey:@"notificationContentView"]   // NSUnknownKeyException
view.backgroundMaterialView                     // unrecognized selector
self.subviews[0]                                // NSRangeException
```

Velvet 2 used all three. That is precisely why it crash-loops on iOS 18: it was written
against the iOS 15/16 view hierarchy and asserts that hierarchy on every notification.

The fix is `src/VLTRuntime.m`, which does the same lookups through the Objective-C
runtime and **returns nil instead of raising**:

```objc
id VLTIvar(id obj, NSString *name);              // ivar lookup, nil if absent
id VLTSafePerform(id obj, SEL selector);         // only calls it if it exists
UIView *VLTDescendantOfClass(UIView *, NSString *); // find by class, not by index
CALayer *VLTSublayerAtIndex(CALayer *, NSUInteger); // bounds-checked
```

So the port is largely mechanical:

```objc
// before — one rename away from safe mode
UILabel *title = [contentView valueForKey:@"primaryTextLabel"];

// after — nil on iOS 18 if Apple moved it, and we simply skip colouring the title
UILabel *title = VLTIvar(contentView, @"primaryTextLabel");
```

`VLTIvar` also refuses to hand back an ivar that is not an object — reading an `int` ivar
as an `id` would give ARC an integer to release, which is its own kind of crash.

---

## 4. Finding out what iOS 18 actually calls things

You cannot guess this, and no SDK ships it — private classes are in the dyld shared
cache, not in any header Apple publishes. Two ways to find the truth:

**Ask the runtime, on the device.** Every loaded class is enumerable. Velvet 3 does this
in `VLTReconDumpClassesWithPrefixes`:

```objc
unsigned int count = 0;
Class *classes = objc_copyClassList(&count);
// keep the ones starting "NCNotification", write them to a file
```

and `class_copyIvarList` gives you every ivar of a class, with type encodings. Point that
at a live notification and you have the exact iOS 18 structure — no downloads, no
guessing. That is what recon mode is (see `docs/DEVICE-SETUP.md`).

**Dump the shared cache offline.** `ipsw` (blacktop/ipsw) runs on Linux, extracts the
dyld shared cache from an IPSW, and class-dumps it:

```bash
ipsw class-dump --headers -o ./hdrs dyld_shared_cache_arm64e UserNotificationsUIKit
```

Slower and needs a multi-GB download, but works without touching the device.

---

## 5. Rootless, and `/var/jb`

Older jailbreaks remounted the system partition and installed to `/Library`, `/usr`, etc.
Modern ones (Dopamine included) are **rootless**: the system partition stays sealed and
everything jailbreak-related lives under `/var/jb`.

For you that means:

- `THEOS_PACKAGE_SCHEME=rootless` — Theos prefixes install paths and sets
  `Architecture: iphoneos-arm64`.
- Never hardcode `/usr/bin/...`. Use `ROOT_PATH("/usr/bin/sbreload")`, which expands to
  `/var/jb/usr/bin/sbreload`. Velvet already did this correctly for its respring button.
- Do **not** manually prepend `$(THEOS_PACKAGE_INSTALL_PREFIX)` to an `INSTALL_PATH` —
  Theos already applies it. Doing both gets you `/var/jb/var/jb/...` and a settings pane
  that never shows up. (Upstream's `preferences/Makefile` had exactly this bug; it is
  fixed here.)

---

## 6. Architectures, and the arm64e trap

This one cost real time on this port, so it is worth stating plainly.

A12 and newer devices run system processes as **arm64e** — ARM pointer authentication.
There are two incompatible arm64e ABIs, distinguished by the Mach-O `cpusubtype`:

| cpusubtype | ABI | Loads on |
|---|---|---|
| `0x00000002` | pre-iOS-14 | iOS 12–13 only |
| `0x80000002` | iOS 14+ (`CPU_SUBTYPE_PTRAUTH_ABI`) | iOS 14 and later |

The trap: **dyld prefers the arm64e slice over the arm64 slice.** So a fat dylib carrying
an *old-ABI* arm64e slice does not quietly fall back to arm64 — it fails to load at all.

And: the iOS 14+ ABI is only produced by Apple's Xcode clang. Theos on Linux emits the
old one (Theos even hardcodes `IS_NEW_ABI = 0` on non-macOS). So:

- **Linux builds here are arm64-only**, on purpose. Good for editing and compile-checking.
- **Release builds run on macOS** via `.github/workflows/build.yml`.
- `tools/check-slices.py` inspects a built `.deb` and fails if it finds an old-ABI arm64e
  slice, or (with `--require-arm64e`) if a release is missing a good one.

```bash
python3 tools/check-slices.py packages/*.deb
```

---

## 7. Packaging

A tweak ships as a Debian package. `control` is the metadata:

```
Package: com.belubruh123.velvet3          # unique id; the thing dpkg tracks
Architecture: iphoneos-arm64           # rootless
Depends: firmware (>= 15.0), ellekit | mobilesubstrate, preferenceloader
Conflicts: com.noisyflake.velvet2      # cannot coexist — both hook the same classes
Replaces: com.noisyflake.velvet2       # installing this removes that
```

Anything in `layout/` is copied verbatim into the package, which is how the
PreferenceLoader entry gets to `/var/jb/Library/PreferenceLoader/Preferences/`.

Settings panes are a separate bundle (`preferences/`), loaded into the **Settings app**,
not SpringBoard. They talk to the tweak by writing `NSUserDefaults` and posting a Darwin
notification (`com.belubruh123.velvet3/preferenceUpdate`) that the tweak listens for — a
cross-process signal, since Settings and SpringBoard are different processes.

Build:

```bash
make package FINALPACKAGE=1      # FINALPACKAGE strips debug and drops the +debug suffix
```

---

## 8. Debugging

**Crash logs.** `/var/mobile/Library/Logs/CrashReporter/SpringBoard-*.ips`. Read the
exception type and the top of the thread that raised. `NSUnknownKeyException` names the
key it could not find — which is exactly the ivar Apple renamed.

**Logging.** `VLTLog()` writes to `os_log` under subsystem `com.belubruh123.velvet3`. Read it
with the `oslog` package on device, or Console.app over USB.

**Safe mode is information.** It means your tweak raised, twice. Get the crash log before
you change anything.

**Better: do not rely on recovery.** Velvet 3 has two mechanisms in `VLTShouldLoad()`:

- a **kill switch** — if `/var/mobile/Library/Preferences/com.belubruh123.velvet3.disabled`
  exists, the tweak does not install any hooks. Create it in Filza to go inert without
  uninstalling.
- a **crash watchdog** — a counter is bumped on every load and reset only after
  SpringBoard has survived 20 seconds. Three loads without a survival, and the tweak
  disables itself. A crash loop costs you one respring, not an evening.

This pattern is worth copying into anything you write that loads into SpringBoard.

---

## 9. Where to look next

- `theos.dev/docs` — Logos reference, rootless, arm64e deployment
- `iphonedev.wiki` — private framework notes
- `src/VLTRuntime.h` — the safe-access layer, commented as a worked example
- `src/Tweak.x` — the hooks; compare against `git log` for the upstream version
