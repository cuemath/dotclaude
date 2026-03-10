---
name: binary_release
description: Prepare a CUEMATHAPP binary release by bumping version, app codes, config, and changelog
allowed-tools: Bash(git log*), Bash(git diff*), Read, Edit, Grep, Glob, WebFetch
argument-hint: "[new_version] [changelog summary]"
---

# Binary Release for CUEMATHAPP

Prepare all files required for a new binary (non-CodePush) release of the Cuemath app.

## Context

A binary release requires updating **5 files**. The user must run this skill from inside the `CUEMATHAPP` repo.

## Steps

1. **Determine the new version**
   - If the user provided a version argument (e.g., `/binary_release 5.5.6`), use it.
   - Otherwise, read `package.json` to get the current version, and bump the **patch** number by 1 (e.g., `5.5.4` → `5.5.5`). If the user wants a minor or major bump, they should specify explicitly.

2. **Read current values from the codebase** — read these files in parallel:
   - `package.json` — current `version`
   - `ios/cuemathapp/Info.plist` — current `CFBundleShortVersionString` and `CFBundleVersion`
   - `src/constants/api/index.tsx` — current `APP_CODE` values (iOS and Android) and `CODEPUSH_PATCH_VERSION`
   - `src/store/config.tsx` — current `VERSIONS` map and `persistConfig.version`
   - `CHANGELOG.MD` — top of file to know where to insert

3. **Look up the next app codes**
   - Fetch the Cuemath admin app-code page to find the latest app codes:
     ```
     URL: https://admin.cuemath.com/auth/admin/cueapp/?sort=1&desc=1
     ```
   - Extract the highest iOS app code (starts with `4xxxxx`) and Android app code (starts with `5xxxxx`).
   - The new iOS code = highest iOS code + 1, new Android code = highest Android code + 1.
   - **If the fetch fails** (auth required), fall back: read the current codes from `src/constants/api/index.tsx` and increment each by 1.

4. **Compute derived values**
   - `new_version` — from step 1
   - `new_ios_app_code` and `new_android_app_code` — from step 3
   - `new_config_version_number` — read the last numeric value in the `VERSIONS` map in `src/store/config.tsx` and add 1
   - `new_bundle_version` — read current `CFBundleVersion` from Info.plist and add 1
   - Today's date in `YYYY-MM-DD` format

5. **Update `package.json`**
   - Change `"version"` to the new version.

6. **Update `ios/cuemathapp/Info.plist`**
   - Set `CFBundleShortVersionString` to the new version.
   - Set `CFBundleVersion` to the new bundle version.

7. **Update `src/constants/api/index.tsx`**
   - Set `CODEPUSH_PATCH_VERSION` to `''` (empty string — this is a binary release, not a CodePush patch).
   - Set `APP_CODE` iOS value to the new iOS app code, Android value to the new Android app code.

8. **Update `src/store/config.tsx`**
   - Add `'<new_version>': <new_config_version_number>,` to the end of the `VERSIONS` object (before the closing `} as const`).
   - Add `[VERSIONS['<new_version>']]: clearAccessToken,` to the `migrations` object (before the closing `};`).
   - Update `version: VERSIONS['<old_version>']` to `version: VERSIONS['<new_version>']` in `persistConfig`.

9. **Update `CHANGELOG.MD`**
   - Insert a new section at the top (after the header paragraph), using this format:
     ```
     ## [<new_version>] - <YYYY-MM-DD>

     ### Fixed/Added/Changed

     - <summary from the user or from recent git commits>
     ```
   - If the user provided a changelog summary, use it. Otherwise, ask what the changelog entry should say.

10. **Print a summary** showing all changes made:
    - Version: old → new
    - iOS App Code: old → new
    - Android App Code: old → new
    - Bundle Version: old → new
    - Config Version: old → new
    - Files modified (list all 5)
    - Remind the user: "Run `/pr` when ready to create the pull request."

## Do NOT

- Commit or push changes — the user will use `/pr` for that
- Ask for confirmation between steps — execute fluidly
- Modify any files beyond the 5 listed above
- Over-explain each step
- Offer follow-up suggestions beyond the `/pr` reminder
