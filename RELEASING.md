# Releasing AgentBar

The in-app update check (Settings → Updates) compares the running app version
with the latest GitHub Release. To make "New version available" appear:

1. Bump the version in `Resources/Info.plist` (`CFBundleShortVersionString` +
   `CFBundleVersion`).
2. Commit, tag, and push the tag:
   ```
   git tag vX.Y.Z && git push origin vX.Y.Z
   ```
3. Create a GitHub Release from the tag:
   ```
   gh release create vX.Y.Z --title "AgentBar vX.Y.Z" --notes "…"
   ```
4. **The repository must be public.** For a private repo the anonymous
   `api.github.com/repos/Rivalio-s-r-o/AgentBar/releases/latest` returns 404,
   so the in-app check silently reports "up to date / couldn't check".

The updater is **notify-only**: it opens the release page in the browser. It
does not auto-install (the app is self-signed). Users download / rebuild
manually.
