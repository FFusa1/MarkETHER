"""Run in CI after `flutter create`: sets the app name everywhere it shows
and adds the Android internet permission."""
import json
import pathlib
import re

APP_NAME = "MarkETHER"

# --- Android ---
manifest = pathlib.Path("android/app/src/main/AndroidManifest.xml")
xml = manifest.read_text(encoding="utf-8")
if "android.permission.INTERNET" not in xml:
    xml = xml.replace(
        "<application",
        '<uses-permission android:name="android.permission.INTERNET"/>\n    <application',
        1,
    )
xml = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', xml, count=1)

# Background bot: foreground service (flutter_foreground_task) that keeps the
# app alive while the bot runs. stopWithTask = swiping the app away stops it.
# "specialUse" type has no daily time cap (dataSync is limited to 6 h/day).
PERMISSIONS = [
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
]
for perm in PERMISSIONS:
    if perm not in xml:
        xml = xml.replace(
            "<application",
            f'<uses-permission android:name="{perm}"/>\n    <application',
            1,
        )

SERVICE = """
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="specialUse"
            android:stopWithTask="true"
            android:exported="false">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="Runs a user-started market-analysis session while the app is in the background" />
        </service>
    </application>"""
if "flutter_foreground_task.service.ForegroundService" not in xml:
    xml = xml.replace("</application>", SERVICE.lstrip("\n"), 1)

manifest.write_text(xml, encoding="utf-8")
print("Android manifest patched")
print(xml)

# --- Web (browser tab title, home-screen icon name) ---
index = pathlib.Path("web/index.html")
if index.exists():
    html = index.read_text(encoding="utf-8")
    html = re.sub(r"<title>[^<]*</title>", f"<title>{APP_NAME}</title>", html)
    html = re.sub(
        r'(name="apple-mobile-web-app-title" content=")[^"]*"', rf'\g<1>{APP_NAME}"', html
    )
    html = re.sub(r'(name="description" content=")[^"]*"',
                  r'\g<1>Binance crypto scanner: swing and scalp signals."', html)
    index.write_text(html, encoding="utf-8")
    print("web/index.html patched")

web_manifest = pathlib.Path("web/manifest.json")
if web_manifest.exists():
    data = json.loads(web_manifest.read_text(encoding="utf-8-sig"))
    data["name"] = APP_NAME
    data["short_name"] = APP_NAME
    data["background_color"] = "#0E1116"
    data["theme_color"] = "#0E1116"
    web_manifest.write_text(json.dumps(data, indent=2), encoding="utf-8")
    print("web/manifest.json patched")
