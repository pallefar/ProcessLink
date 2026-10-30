# Updater

ProcessLink checks the public GitHub release feed:

```text
https://api.github.com/repos/pallefar/ProcessLink/releases/latest
```

- Native: **Settings → Updates** and **ProcessLink → Check for Updates…**
- Web: **OS suite → ProcessLink updates**
- It compares the release tag with `CFBundleShortVersionString` and offers the
  signed DMG / release page.
- It never installs silently and never runs a downloaded binary.
- Auto-check at launch is on by default and can be turned off in Settings.
- Web feedback and product feedback stay in the browser; native product
  feedback stays in SwiftData.
