# Vydávání nové verze StatusBar

In-app kontrola aktualizací (Nastavení → Aktualizace) porovnává verzi běžící app
s nejnovějším GitHub Release. Aby se „Nová verze dostupná" zobrazila:

1. Bump verze v `Resources/Info.plist` (`CFBundleShortVersionString` + `CFBundleVersion`).
2. Commit, tag `vX.Y.Z`, push tagu:
   ```
   git tag v0.10.0 && git push origin v0.10.0
   ```
3. Vytvořit GitHub Release z tagu (volitelně přiložit zazipovanou `.app`):
   ```
   gh release create v0.10.0 --title "v0.10.0" --notes "…"
   ```
4. **Repo musí být veřejné.** Anonymní `api.github.com/repos/Rivalio-s-r-o/StatusBar/releases/latest`
   u privátního repa vrací 404 → in-app check tiše hlásí „Nelze ověřit / aktuální".
   Dokud je repo privátní, je updater připravený, ale „neviditelný".

Updater je **notify-only**: otevře release stránku v prohlížeči. Neinstaluje automaticky
(app je ad-hoc podepsaná). Uživatel stáhne/přebuilduje ručně.
