"""Run in CI after `flutter create`: sets the app name everywhere it shows
and adds the Android internet permission."""
import base64
import json
import os
import pathlib
import re
import sys

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

# --- Release signing: the same key for every build ---
# Without this, each cloud build signs with a brand-new random debug key, so
# Android sees every APK as a different app (no update-in-place, and Play
# Protect treats it as new each time). The key comes from two GitHub secrets.
ks_b64 = os.environ.get("MARKETHER_KEYSTORE", "").strip()
ks_pass = os.environ.get("MARKETHER_KEYSTORE_PASSWORD", "").strip()
if ks_b64 and ks_pass:
    if not re.fullmatch(r"[A-Za-z0-9]+", ks_pass):
        sys.exit("MARKETHER_KEYSTORE_PASSWORD must be letters and digits only")
    pathlib.Path("android/app/markether.p12").write_bytes(base64.b64decode(ks_b64))
    kts = pathlib.Path("android/app/build.gradle.kts")
    groovy = pathlib.Path("android/app/build.gradle")
    if kts.exists():
        g = kts.read_text(encoding="utf-8")
        block = f"""    signingConfigs {{
        create("markether") {{
            storeFile = file("markether.p12")
            storePassword = "{ks_pass}"
            keyAlias = "markether"
            keyPassword = "{ks_pass}"
            storeType = "pkcs12"
        }}
    }}

    buildTypes {{"""
        old_ref, new_ref, target = 'signingConfigs.getByName("debug")', 'signingConfigs.getByName("markether")', kts
    elif groovy.exists():
        g = groovy.read_text(encoding="utf-8")
        block = f"""    signingConfigs {{
        markether {{
            storeFile file("markether.p12")
            storePassword "{ks_pass}"
            keyAlias "markether"
            keyPassword "{ks_pass}"
            storeType "pkcs12"
        }}
    }}

    buildTypes {{"""
        old_ref, new_ref, target = "signingConfigs.debug", "signingConfigs.markether", groovy
    else:
        sys.exit("android/app/build.gradle(.kts) not found")
    if "    buildTypes {" not in g or old_ref not in g:
        sys.exit("Could not find where to add release signing in " + str(target))
    g = g.replace("    buildTypes {", block, 1).replace(old_ref, new_ref)
    target.write_text(g, encoding="utf-8")
    print("Release signing: MarkETHER key")
else:
    print("WARNING: signing secrets not set, APK uses a random debug key")

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
