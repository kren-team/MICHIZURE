# MICHIZURE Demo Target

`com.kren.michizure.demotarget` は、managed Android Emulatorで
package suspension / releaseを再現するための独立したデモfixtureである。
MICHIZURE本体のartifactやrelease bundleには含まれない。

- permissionなし
- networkなし
- user dataなし
- debug shortcut / backend mutationなし

Build:

```bash
./android/gradlew -p tools/demo-target assembleDebug
```

Install:

```bash
adb -s emulator-5554 install -r \
  tools/demo-target/app/build/outputs/apk/debug/app-debug.apk
```
