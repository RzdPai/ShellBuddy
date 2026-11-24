/**
 * Minimal HarmonyOS file picker plugin.
 *
 * Bridges Flutter's file picking to the system DocumentViewPicker
 * (@ohos.file.picker). Picker results are URIs that dart:io cannot open, so
 * single-file picks are copied into the app cache and the plain path is
 * returned instead.
 */
import {
  FlutterPlugin,
  FlutterPluginBinding,
  AbilityAware,
  AbilityPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';

const TAG: string = 'FilePickerOhosPlugin';
const CHANNEL: string = 'serverbox.ohos/file_picker';

export default class FilePickerOhosPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private uiContext: common.UIAbilityContext | null = null;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.uiContext = binding.getAbility().context as common.UIAbilityContext;
  }

  onDetachedFromAbility(): void {
    this.uiContext = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'pickFile':
        this.pickFile(result, false);
        break;
      case 'pickDirectory':
        this.pickFile(result, true);
        break;
      default:
        result.notImplemented();
    }
  }

  private async pickFile(result: MethodResult, isDirectory: boolean): Promise<void> {
    if (this.uiContext == null) {
      result.error('no_context', 'UIAbility not attached', null);
      return;
    }
    try {
      const docPicker = new picker.DocumentViewPicker(this.uiContext);
      const options = new picker.DocumentSelectOptions();
      if (isDirectory) {
        options.selectMode = picker.DocumentSelectMode.FOLDER;
      } else {
        options.maxSelectNumber = 1;
      }
      const uris = await docPicker.select(options);
      if (!uris || uris.length === 0) {
        // User cancelled: return null, not an error.
        result.success(null);
        return;
      }
      if (isDirectory) {
        result.success(uris[0]);
        return;
      }
      const uri: string = uris[0];
      console.info(TAG, `picked uri: ${uri}`);

      // Picker URIs are URL-encoded and may not end with the real file name,
      // so decode the tail and fall back to a timestamp if it looks unusable.
      // A wrong but non-empty name never blocks the upload.
      let rawName: string = uri.substring(uri.lastIndexOf('/') + 1);
      try {
        rawName = decodeURIComponent(rawName);
      } catch (e) {
        // Leave the encoded form if it cannot be decoded.
      }
      // A decoded tail could carry a path separator; flatten it so it cannot
      // break the cache path.
      rawName = rawName.replaceAll('/', '_');
      if (rawName.length === 0 || rawName.indexOf('.') < 0) {
        rawName = `picked_${Date.now()}.dat`;
      }

      const destDir: string = this.uiContext.cacheDir + '/picked';
      if (!fs.accessSync(destDir)) {
        fs.mkdirSync(destDir, true);
      }
      const destPath: string = destDir + '/' + rawName;

      // Open via fd rather than passing the picker URI string straight to
      // copyFileSync: some HarmonyOS releases reject a datashare/file URI as
      // the copy source, but an fd opened from it is always accepted.
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        fs.copyFileSync(file.fd, destPath);
      } finally {
        fs.closeSync(file.fd);
      }

      const stat = fs.statSync(destPath);
      console.info(TAG, `copied to ${destPath}, size=${stat.size}`);
      result.success({ path: destPath, name: rawName, size: stat.size });
    } catch (err) {
      const e = err as BusinessError;
      console.error(TAG, `pickFile failed: ${e.code} ${e.message}`);
      result.error('pick_failed', e.message ?? 'unknown error', null);
    }
  }
}
