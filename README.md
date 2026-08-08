# Snap-Productivity

Snap-Productivity is a lightweight native macOS utility that lets you switch between Finder and the numbered applications in your Dock with Command + number shortcuts.

## Shortcuts

- **⌘0** — Show or hide Finder.
- **⌘1–⌘9** — Show or hide the corresponding numbered Dock application.
- If the selected Dock application is not running, Snap-Productivity can launch it.

## How it works

- Native Swift macOS application.
- Runs as an accessory application rather than a normal Dock application.
- Uses a global keyboard event tap for the Command + number shortcuts.
- Does not use a browser engine, network service, or continuous polling loop.
- Registers itself as a macOS Login Item so it can start automatically when you log in.
- Creates a menu-bar status item. If the icon is not visible because of menu-bar layout/visibility, the application can still run normally in the background.

## Requirements

- macOS 13 or newer.
- Xcode Command Line Tools (`swiftc`, `codesign`, and `lipo`).
- Accessibility permission.
- Input Monitoring permission.

## Install locally

### 1. Extract the project

Put the project somewhere convenient, such as:

`~/Downloads/Snap-Productivity-1.0.0`

Open Terminal and enter the project directory:

```bash
cd ~/Downloads/Snap-Productivity-1.0.0
```

If the folder has a different name, use that actual folder name.

### 2. Remove the downloaded-file quarantine

If macOS downloaded the project from the internet, run:

```bash
xattr -dr com.apple.quarantine .
```

### 3. Make the scripts executable

```bash
chmod +x install.sh uninstall.sh diagnose.sh
```

### 4. Build and install

```bash
./install.sh
```

The installer:

- builds native arm64 and x86_64 executables
- combines them into one universal binary
- creates `~/Applications/Snap-Productivity.app`
- applies a local ad-hoc code signature
- clears the application's quarantine attribute
- verifies the application bundle
- launches the application

No `sudo` is required.

## First-run permissions

After installation, open:

**System Settings → Privacy & Security → Accessibility**

Find **Snap-Productivity**, add it if necessary, and turn it **ON**.

Then open:

**System Settings → Privacy & Security → Input Monitoring**

Find **Snap-Productivity**, add it if necessary, and turn it **ON**.

After changing either permission, restart the app:

```bash
killall SnapProductivity 2>/dev/null || true
open ~/Applications/Snap-Productivity.app
```

## Start automatically at login

Snap-Productivity registers itself with macOS as a Login Item when it launches.

Verify it in:

**System Settings → General → Login Items & Extensions**

Look for **Snap-Productivity** in the applications allowed to run at login.

If registration succeeded, macOS will launch Snap-Productivity automatically after you log in. It runs as an accessory/background application; you do not need to manually open it each time.

If you disable or remove the Login Item, it will no longer start automatically.

## Verify that it is working

From the project directory:

```bash
./diagnose.sh
```

You can also inspect the log:

```bash
tail -50 ~/Library/Logs/Snap-Productivity.log
```

A healthy launch should show:

- Accessibility is trusted.
- The keyboard event tap is created/enabled.
- Dock applications are detected.
- Login Item registration succeeds.

To verify the running process directly:

```bash
pgrep -fl SnapProductivity
```

## Menu-bar icon

Snap-Productivity creates a menu-bar status item. The icon is intentionally minimal.

If the icon is not visible, this does not by itself mean the application is stopped. Verify the process and log with:

```bash
pgrep -fl SnapProductivity
tail -50 ~/Library/Logs/Snap-Productivity.log
```

## Uninstall

From the project directory:

```bash
./uninstall.sh
```

This removes the installed application and its local log.

## Important note about local builds

This project is intended to be built locally on the Mac where it will run.

The installer uses an ad-hoc local code signature because there is no Apple Developer signing identity required for this local build. A newly rebuilt application can have a different code-signing identity, so macOS may require Accessibility and Input Monitoring permissions to be granted again after replacing the installed application.

For normal use, keep the installed build in:

`~/Applications/Snap-Productivity.app`

and leave its Login Item enabled.
