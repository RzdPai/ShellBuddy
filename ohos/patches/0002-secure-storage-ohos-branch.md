Patch applied to: /root/.pub-cache/git/flutter_secure_storage-1142e9e65732a66b9e0a9bef46e5fd74e9d19de7/flutter_secure_storage/lib/flutter_secure_storage.dart

Why: `_selectOptions` switches on `defaultTargetPlatform`; the HarmonyOS
framework fork adds `TargetPlatform.ohos`, which matched no branch and fell
into `throw UnsupportedError('unsupported_platform')` — the app died at
launch on every secret read (webdavPwd / hivePwd / githubToken).

Fix: add the ohos branch and carry the options on the android ones. The
native side (flutter_secure_storage_ohos, integrated separately as a plugin)
listens on the same channel name `plugins.it_nomads.com/flutter_secure_storage`.

Keep as record; if pub re-fetches the git checkout, re-apply by hand.

--- a/flutter_secure_storage/lib/flutter_secure_storage.dart
+++ b/flutter_secure_storage/lib/flutter_secure_storage.dart
@@ -364,6 +364,14 @@
     } else if (defaultTargetPlatform == TargetPlatform.macOS) {
       return mOptions?.params ?? this.mOptions.params;
+    } else if (defaultTargetPlatform == TargetPlatform.ohos) {
+      // HarmonyOS NEXT: the framework fork adds TargetPlatform.ohos, which
+      // no branch above matches, and the else used to throw here — crashing
+      // every launch that reads a secret. The params map is platform-neutral
+      // and the native side registers on the same method-channel name, so the
+      // android options work as the carrier.
+      return aOptions?.params ?? this.aOptions.params;
     } else {
       throw UnsupportedError(_unsupportedPlatform);
     }
