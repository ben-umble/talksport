# Installing talkSPORT Companion

Release builds contain:

- `talksport-companion-windows-x64-vX.Y.Z.zip` for Windows.
- `talksport-companion-android-vX.Y.Z.apk` for Android sideloading.
- `SHA256SUMS.txt` for checking downloaded files.

## Windows

1. Download the Windows ZIP from the release.
2. Extract the ZIP.
3. Open the extracted folder and run `talksport_companion.exe`.

Keep the DLLs and `data` folder beside the EXE. The app will not launch reliably if only the EXE is moved on its own.

Windows may show a SmartScreen warning because this is not code-signed. Choose "More info" and then "Run anyway" if you trust the build.

## Android

1. Download the Android APK from the release.
2. On your Android device, allow installs from the browser or file manager you are using.
3. Open the APK and install it.

The current APK is signed for personal sideload use, not Play Store distribution. If Android reports a signature conflict after a future build, uninstall the previous sideloaded build first.

## Building A Release Locally

From the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\package_release.ps1
```

The files are written to `dist\release\vX.Y.Z`.

## Publishing To GitHub Releases

Create an empty GitHub repository first, then run these commands from the project root:

```powershell
git init
git add .
git commit -m "Initial talkSPORT Companion release"
git branch -M main
git remote add origin https://github.com/<your-user>/<your-repo>.git
git push -u origin main
```

Then create and push a version tag that matches `pubspec.yaml`:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

The GitHub Actions release workflow will build the Windows ZIP, Android APK, and checksum file, then attach them to the GitHub Release for that tag.
