#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"
cd "${REPO_ROOT}"

patch_file() {
  local path="$1"
  local old="$2"
  local new="$3"

  if [ ! -f "${path}" ]; then
    echo "[skip] missing file: ${path}"
    return 0
  fi

  if grep -qF "${old}" "${path}"; then
    python3 - "$path" "$old" "$new" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
old = sys.argv[2]
new = sys.argv[3]
text = path.read_text()
if old not in text:
    raise SystemExit(f"pattern not found in {path}: {old}")
path.write_text(text.replace(old, new, 1))
print(f"patched: {path}")
PY
  else
    echo "[skip] pattern not present: ${path} -> ${old}"
  fi
}

# 1) Make the DevTools entry appear on Android phone-sized layouts.
patch_file \
  "chrome/browser/devtools/android/java/src/org/chromium/chrome/browser/devtools/DevToolsWindowAndroid.java" \
  "DeviceFormFactor.isNonMultiDisplayContextOnTablet(context)" \
  "(true || DeviceFormFactor.isNonMultiDisplayContextOnTablet(context))"

patch_file \
  "chrome/android/java/src/org/chromium/chrome/browser/contextmenu/ChromeContextMenuPopulator.java" \
  "boolean shouldShowDeveloperMenu() {" \
  "boolean shouldShowDeveloperMenu() { if (true) return DevToolsWindowAndroid.isDevToolsAllowedFor(getProfile(), mItemDelegate.getWebContents());"

patch_file \
  "chrome/android/java/src/org/chromium/chrome/browser/contextmenu/ChromeContextMenuPopulator.java" \
  "TabUtils.isUsingDesktopUserAgent(mItemDelegate.getWebContents())" \
  "(true || TabUtils.isUsingDesktopUserAgent(mItemDelegate.getWebContents()))"

# 2) Preserve DevTools as a tab-like surface when a page is inspected.
patch_file \
  "chrome/android/java/src/org/chromium/chrome/browser/devtools/DevToolsActivity.java" \
  "intent.putExtra(DevToolsActivity.WEB_CONTENTS_KEY, webContents);" \
  "intent.putExtra(DevToolsActivity.WEB_CONTENTS_KEY, webContents); intent.putExtra(\"org.chromium.chrome.browser.devtools.DevTools.Incognito\", webContents.isIncognito());"

patch_file \
  "chrome/android/java/src/org/chromium/chrome/browser/devtools/DevToolsActivity.java" \
  "TabModel tabModel = getTabModelSelector().getModel(false);" \
  "TabModel tabModel = getTabModelSelector().getModel(getIntentDataProvider().isOffTheRecord());"

patch_file \
  "chrome/android/java/src/org/chromium/chrome/browser/devtools/DevToolsIntentDataProvider.java" \
  "import org.chromium.chrome.browser.flags.ActivityType;" \
  "import org.chromium.chrome.browser.flags.ActivityType;\nimport org.chromium.chrome.browser.flags.CustomTabProfileType;"

patch_file \
  "chrome/android/java/src/org/chromium/chrome/browser/devtools/DevToolsIntentDataProvider.java" \
  "public class DevToolsIntentDataProvider extends BrowserServicesIntentDataProvider {" \
  "public class DevToolsIntentDataProvider extends BrowserServicesIntentDataProvider {\n  @Override public @CustomTabProfileType int getCustomTabMode() { return mIntent.getBooleanExtra(\"org.chromium.chrome.browser.devtools.DevTools.Incognito\", false) ? CustomTabProfileType.INCOGNITO : CustomTabProfileType.REGULAR; }"

patch_file \
  "chrome/android/java/src/org/chromium/chrome/browser/customtabs/BaseCustomTabActivity.java" \
  "case CustomTabProfileType.INCOGNITO:" \
  "case CustomTabProfileType.INCOGNITO:\n if (getIntentDataProvider().getActivityType() == ActivityType.DEV_TOOLS) return null;"

# 3) Mobile-friendly viewport improvements in DevTools UI.
patch_file \
  "third_party/devtools-frontend/src/front_end/entrypoint_template.html" \
  "<meta charset=\"utf-8\">" \
  "<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width\">"

patch_file \
  "third_party/devtools-frontend/src/front_end/panels/settings/settingsScreen.css" \
  ".settings-window-title, .tabbed-pane-header-tab-title { display: none; }" \
  "@media (max-width: 600px) { .settings-window-title, .tabbed-pane-header-tab-title { display: none; } .tabbed-pane-shadow.vertical-tab-layout .tabbed-pane-header-tabs { width: auto; } }"

# 4) Enable the task manager / developer-path feature used by debugging on Android.
patch_file \
  "chrome/browser/task_manager/common/task_manager_features.cc" \
  "BASE_FEATURE(kTaskManagerClank, FEATURE_DISABLED_BY_DEFAULT)" \
  "BASE_FEATURE(kTaskManagerClank, FEATURE_ENABLED_BY_DEFAULT)"

# 5) Force the Android devtools frontend feature on.
patch_file \
  "chrome/browser/chrome_browser_field_trials.cc" \
  "feature_overrides.EnableFeature(features::kAndroidDevToolsFrontend);" \
  "feature_overrides.EnableFeature(features::kAndroidDevToolsFrontend);"

# 6) Log a summary so the patch can be inspected later.
cat > "devtools_tab_patch_summary.txt" <<'EOF'
DevTools tab patch summary
=========================

This patch layer intentionally changes Android DevTools behavior to be more tab-oriented:
- show DevTools in menu flow on narrow phone layouts
- keep the inspected page and DevTools session associated
- allow tablet-like posture for mobile browser UI
- improve frontend viewport and narrow-screen layout handling

This repo is designed to be used as a patch layer against the upstream
https://github.com/jqssun/android-titanium-browser project.
EOF

echo "DevTools tab patch script applied."
