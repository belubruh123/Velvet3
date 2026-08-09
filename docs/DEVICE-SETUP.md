# Device setup, install, recon and recovery

For an A12 device on iOS 18.0–18.4 with Dopamine 3 (rootless, semi-untethered).

Read [Recovery](#5-recovery--when-something-goes-wrong) *before* you install anything.

---

## 1. Connecting to the phone over SSH

You have OpenSSH installed but have not connected yet. Do this **from your own computer,
on the same Wi-Fi as the phone.** The Linux build box (`207.244.236.183`) is out on the
public internet and cannot reach a phone behind your home router.

1. **Find the phone's IP.** On the phone: **Settings → Wi-Fi → ⓘ** next to the network
   you are on → **IP Address**. Something like `192.168.1.42`.

2. **Connect.** In Terminal (macOS/Linux) or PowerShell (Windows 10+):

   ```bash
   ssh root@192.168.1.42
   ```

   The default password is **`alpine`**. You will get a host-key prompt the first time —
   type `yes`.

3. **Change the password immediately:**

   ```bash
   passwd
   ```

   A jailbroken phone reachable on your LAN with the default password is a real risk, not
   a theoretical one.

4. **If you get `Connection refused`**, sshd is not running. Open NewTerm on the phone and:

   ```bash
   launchctl load /var/jb/Library/LaunchDaemons/com.openssh.sshd.plist
   ```

   (Rootless: everything jailbreak-related lives under `/var/jb`.)

5. **While you are in, note these** — needed to pick the right SDK/IPSW later:

   ```bash
   sysctl -n hw.machine        # e.g. iPhone11,8
   uname -a
   ```

   Plus **Settings → General → About → Software Version** for the exact 18.x build.

### Optional: let the build box drive the phone directly

If you want the whole install/test loop scriptable from the Linux box, open a reverse
tunnel **from the phone** (NewTerm, or over SSH from your computer):

```bash
ssh -f -N -R 2222:127.0.0.1:22 jeremy@207.244.236.183
```

Then from the build box, `ssh -p 2222 root@127.0.0.1` reaches the phone.

---

## 2. Getting the build onto the phone

On the build box, from the repo root:

```bash
python3 -m http.server 8000 --directory packages
```

On the phone: Safari → `http://207.244.236.183:8000/` → tap the `.deb` → **Open in
Filza** → **Install**. (Make sure port 8000 is open in the firewall.)

Or, if you have SSH working, from your own computer:

```bash
scp com.tallplay.velvet3_3.0.0_iphoneos-arm64.deb root@192.168.1.42:/var/mobile/
ssh root@192.168.1.42 'dpkg -i /var/mobile/com.tallplay.velvet3_3.0.0_iphoneos-arm64.deb && sbreload'
```

Installing Velvet 3 automatically removes Velvet 2 (`Conflicts`/`Replaces`); they hook the
same classes and must never both be loaded.

> **Which build?** The Linux box produces **arm64-only** packages. On an A12 device
> SpringBoard is arm64e, so an arm64-only build may not inject at all — see
> [§6](#6-about-the-arm64e-build). The macOS CI build is the one to install for real use.

---

## 3. Recon mode — finding out what iOS 18 renamed

Recon makes the tweak dump the real iOS 18 class names, ivars and view hierarchy to a
file. It is **read-only**: it observes and writes a text file, it changes nothing.

**Turn it on** — create an empty file (Filza: **+ → File**, or over SSH):

```bash
touch /var/mobile/Library/Preferences/com.tallplay.velvet3.recon
```

Respring. Then trigger a few notifications from different apps (Messages, Mail, anything
with an icon), let a couple stack up, and open the Focus summary if you use one.

**Read the results:**

```
/var/mobile/Library/Preferences/com.tallplay.velvet3.recon.txt
```

Open it in Filza, or pull it off:

```bash
scp root@192.168.1.42:/var/mobile/Library/Preferences/com.tallplay.velvet3.recon.txt .
```

You get four things:

1. **Class availability** — which of the iOS 15/16 classes Velvet 2 relied on still
   exist, and which are marked `** MISSING **`.
2. **Every registered `NCNotification*` / `MTMaterial*` / `PLPlatter*` class** — this is
   where renamed classes show up.
3. **Full ivar and property lists** for the live notification objects, with the runtime
   class of each value.
4. **The view tree** with frames, so you can see what actually nests inside what.

Points 1 and 2 are written at load, so you get them even if no hook ever fires.

**Turn it off** by deleting the flag file. Delete the `.txt` too if it has grown.

---

## 4. Reading crash logs

If SpringBoard does die:

```
/var/mobile/Library/Logs/CrashReporter/SpringBoard-<date>.ips
```

Look for `Exception Type` and the exception name. `NSUnknownKeyException` will name the
key it could not find — that names the ivar Apple renamed, which is exactly what needs a
new candidate in `VLTIvarAny(...)`.

Tweak logging goes to `os_log` under subsystem `com.tallplay.velvet3`:

```bash
oslog | grep velvet3        # the `oslog` package, from a jailbreak repo
```

---

## 5. Recovery — when something goes wrong

**In order of preference:**

1. **It should disable itself.** The crash watchdog counts loads and only resets the
   counter after SpringBoard has stayed up 20 seconds. Three loads without a survival and
   the tweak writes its own `.disabled` file and stops hooking. A crash loop should cost
   you one respring.

2. **Kill switch.** From safe mode, in Filza, create:

   ```
   /var/mobile/Library/Preferences/com.tallplay.velvet3.disabled
   ```

   Respring. The tweak loads but installs no hooks. Delete the file to re-enable.

3. **Uninstall.** Safe mode → Sileo → Velvet 3 → Remove → Respring. Or over SSH:

   ```bash
   dpkg -r com.tallplay.velvet3 && sbreload
   ```

**Test the kill switch deliberately, before you need it.** Create the file, respring,
confirm notifications go back to stock, delete it, respring again.

---

## 6. About the arm64e build

Short version: **install the macOS CI build, not the Linux one, for real use.**

A12+ devices run SpringBoard as arm64e. There are two arm64e ABIs, and only Apple's Xcode
clang emits the iOS 14+ one; Theos on Linux emits the pre-iOS-14 one, which iOS 15+
refuses to load — and because dyld *prefers* the arm64e slice, including a bad one breaks
loading entirely rather than falling back to arm64. So Linux builds here are deliberately
arm64-only.

Whether an arm64-only dylib injects into arm64e SpringBoard is worth one cheap
experiment, and the recon build is the perfect harmless way to run it: install the
arm64-only build with recon enabled and respring.

- **`com.tallplay.velvet3.recon.txt` appears** → arm64 injection works; the Linux box can
  drive the whole loop.
- **No file appears** → arm64-only does not inject; use the macOS CI build from then on.

Either way it cannot crash anything — with recon on and nothing hooked yet, the worst
case is that nothing happens.

Check any `.deb` before installing:

```bash
python3 tools/check-slices.py packages/*.deb
```
