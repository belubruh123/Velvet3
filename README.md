# Velvet 3

A fork of [NoisyFlake/Velvet2](https://github.com/NoisyFlake/Velvet2) — the notification
banner customisation tweak — brought forward to **iOS 17/18** and **Dopamine 3**
(rootless, A12+).

Upstream stopped at commit `3f2ccfe` (June 2023) and targets iOS 15–16. On iOS 18 it
installs, loads, and then takes SpringBoard down into safe mode.

## Why it was crashing

Velvet 2 reads SpringBoard's private notification views by name, and asserts the iOS
15/16 view hierarchy on every single notification. Three flavours of that, all fatal when
Apple moves something:

- `-valueForKey:` on ~12 private ivars → `NSUnknownKeyException`
- private `@property` calls such as `view.backgroundMaterialView` → unrecognized selector
- positional access: `self.subviews[0]`, `layer.sublayers[0]` → `NSRangeException`

An uncaught exception inside SpringBoard is not a caught error — it is a dead UI, and
twice in a row is safe mode.

## What this fork changes

**Phase 1 — cannot crash SpringBoard (done)**

- `src/VLTRuntime.{h,m}`: a safe-access layer. Ivar lookup, private-property calls,
  subview and sublayer access all return `nil` when the thing is not there on this iOS
  version, instead of raising. Every private access in the tweak goes through it.
- Hooks are grouped and installed conditionally — a class that iOS 18 no longer has
  simply never gets hooked.
- **Kill switch + crash watchdog** in `%ctor`, so a bad build costs one respring rather
  than an evening in safe mode.
- **Recon mode**: a read-only dump of the real iOS 18 class names, ivars and view tree,
  so the port is driven by what the device actually has rather than by guesswork.
- Restored a missing `%orig`; removed the blanket stubbing of UIKit's view recycling on
  iOS 17+; swapped private `CALayer.continuousCorners` for public `cornerCurve`.
- Fixed upstream's `/var/jb/var/jb/...` double-prefix in the preference bundle path.

**Phase 2 — restore the styling features against the real iOS 18 hierarchy (next)**

In order: corner radius → background → border → shadow → accent line → title/message/date
colours → app icon → Focus summary platter → stack dimming.

## Building

Full detail in [docs/TWEAK-DEV-PRIMER.md](docs/TWEAK-DEV-PRIMER.md); device workflow in
[docs/DEVICE-SETUP.md](docs/DEVICE-SETUP.md).

```bash
export THEOS=~/theos
make package FINALPACKAGE=1
python3 tools/check-slices.py packages/*.deb
```

> **Release builds must be produced on macOS.** A12+ devices run SpringBoard as arm64e,
> and the iOS 14+ arm64e ABI is only emitted by Apple's Xcode clang. Theos on Linux emits
> the pre-iOS-14 ABI, which iOS 15+ refuses to load — and dyld *prefers* that slice, so
> shipping it breaks loading outright instead of falling back to arm64. Linux builds here
> are therefore arm64-only, and `.github/workflows/build.yml` builds the real package on
> macOS. `tools/check-slices.py` is the guard.

## Credits and licence

Original tweak by **NoisyFlake**. Colour extraction is ColorCube by Ole Krause-Sparmann.
MIT licensed — see [LICENSE](LICENSE); this fork keeps that licence and attribution.
