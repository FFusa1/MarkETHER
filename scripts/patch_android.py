"""Run in CI after `flutter create`: adds internet permission and the app name."""
import pathlib
import re

manifest = pathlib.Path("android/app/src/main/AndroidManifest.xml")
xml = manifest.read_text(encoding="utf-8")

if "android.permission.INTERNET" not in xml:
    xml = xml.replace(
        "<application",
        '<uses-permission android:name="android.permission.INTERNET"/>\n    <application',
        1,
    )

xml = re.sub(r'android:label="[^"]*"', 'android:label="Market AI"', xml, count=1)
manifest.write_text(xml, encoding="utf-8")
print(xml)
