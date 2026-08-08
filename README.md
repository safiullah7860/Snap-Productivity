# Snap-Productivity

Snap-Productivity is a lightweight macOS menu-bar utility that lets you switch between Finder and the numbered applications in your Dock using Command + number shortcuts.

## What it does

- **⌘0** — Show or hide Finder.
- **⌘1–⌘9** — Show or hide the corresponding numbered Dock application.
- If a Dock application is not running, Snap-Productivity can launch it.
- Runs as a small menu-bar utility without opening a normal Dock window.
- Includes a menu-bar status item so you can see whether Accessibility, keyboard monitoring, and Dock access are working.

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools (`swiftc`, `codesign`, and `lipo`)
- Accessibility permission
- Input Monitoring permission

## Run locally

The project is intended to be built locally on the Mac where it will run.

### 1. Extract the project

Put the project folder somewhere convenient, such as:

`~/Downloads/Snap-Productivity`

Open Terminal and enter the project directory:

```bash
cd ~/Downloads/Snap-Productivity
```

If the downloaded folder has a version suffix, use that actual folder name instead.

### 2. Remove macOS quarantine

If macOS downloaded the project from the internet, remove the quarantine attribute before running the installer:

```bash
xattr -dr com.apple.quarantine .
```

### 3. Make the scripts executable

```bash
chmod +x install.sh uninstall.sh diagnose.sh
```

### 4. Install and build

```bash
./install.sh
```

The installer:

- compiles the native Swift executable for Apple silicon and Intel Macs
- creates the application bundle
- signs the local application
- clears the application's quarantine attribute
- installs it to `~/Applications/`
- launches the application

No `sudo` is required.

## macOS permissions

After installation, open:

**System Settings → Privacy & Security → Accessibility**

Add the installed application and turn it **ON**.

Then open:

**System Settings → Privacy & Security → Input Monitoring**

Add the installed application and turn it **ON**.

If the application is already listed, make sure the toggle is enabled.

After changing either permission, quit and reopen the application:

```bash
killall SnapReplacement 2>/dev/null || true
open ~/Applications/SnapReplacement.app
```

## Verify that it is running

Run:

```bash
./diagnose.sh
```

You can also inspect the log:

```bash
tail -50 ~/Library/Logs/SnapReplacement.log
```

A healthy installation should show that:

- Accessibility is trusted.
- Input Monitoring is available.
- The keyboard event tap was created and enabled.
- The Dock reader can see the numbered Dock applications.

## Testing the shortcuts

With the application running:

1. Put any application in the Dock.
2. Position it in the desired numbered slot.
3. Press **⌘1–⌘9** to show or hide that application.
4. Press **⌘0** to show or hide Finder.

Only Command + number shortcuts are intercepted. Other keyboard input is left alone.

## Uninstall

From the project directory:

```bash
./uninstall.sh
```

This removes the installed application and its local log.

## Notes

This is a local macOS utility built directly from Swift. The installer uses an ad-hoc local signature, so macOS may require you to approve the application and grant its privacy permissions again after rebuilding or changing the application's identity.

Do not use:

```bash
sudo tccutil reset All
```

That would reset privacy permissions system-wide and is unnecessary for this project.
