/**
 * HarmonyOS system share plugin.
 *
 * Bridges Flutter sharing to the **real system share panel** (Share Kit /
 * `@hms.collaboration.systemShare`), not merely "open with an app".
 * `package:share_plus` has no endorsed OHOS implementation, so we build a
 * `systemShare.SharedData` from the sandbox file URIs and present the system
 * share sheet. The panel lets the user pick any target app and automatically
 * grants that target temporary read permission over the URIs — which is
 * exactly what `startAbility(sendData)` does NOT do (it just launches the
 * first matching app, i.e. "open", not "share").
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
import { systemShare } from '@kit.ShareKit';
import fileUri from '@ohos.file.fileuri';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

const TAG: string = 'ShareOhosPlugin';
const CHANNEL: string = 'serverbox.ohos/share';

export default class ShareOhosPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
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
      case 'shareFiles':
        // Dart passes `{ 'paths': [...] }`; pull the list back out.
        this.shareFiles(result, call.argument('paths') as Array<string>);
        break;
      default:
        result.notImplemented();
    }
  }

  // Map a file extension to a UDMF uniform type descriptor. Share Kit requires
  // the `utd` field on every record; `general.file` is the catch-all that every
  // file-aware target accepts, while the media classes let the panel surface
  // specialised targets (e.g. "save to gallery" for images).
  private inferUtd(path: string): string {
    const lower: string = path.toLowerCase();
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') || lower.endsWith('.bmp') || lower.endsWith('.webp')) {
      return 'general.image';
    }
    if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.aac') ||
      lower.endsWith('.flac') || lower.endsWith('.ogg')) {
      return 'general.audio';
    }
    if (lower.endsWith('.mp4') || lower.endsWith('.avi') || lower.endsWith('.mkv') ||
      lower.endsWith('.mov')) {
      return 'general.video';
    }
    return 'general.file';
  }

  private shareFiles(result: MethodResult, paths: Array<string>): void {
    if (this.uiContext == null) {
      result.error('no_context', 'UIAbility not attached', null);
      return;
    }
    try {
      // Build the system share panel payload from the sandbox file URIs. The
      // first file seeds the SharedData; the rest are appended as extra
      // records (multi-file share). Share Kit shows the real share sheet and
      // grants the chosen target temporary read permission over the URIs.
      const shareData = new systemShare.SharedData({
        utd: this.inferUtd(paths[0]),
        uri: fileUri.getUriFromPath(paths[0]),
      });
      for (let i = 1; i < paths.length; i++) {
        shareData.addRecord({
          utd: this.inferUtd(paths[i]),
          uri: fileUri.getUriFromPath(paths[i]),
        });
      }

      const controller = new systemShare.ShareController(shareData);
      controller
        .show(this.uiContext, {
          selectionMode: systemShare.SelectionMode.SINGLE,
          previewMode: systemShare.SharePreviewMode.DEFAULT,
        })
        .then(() => {
          result.success(true);
        })
        .catch((err: BusinessError) => {
          const e: BusinessError = err as BusinessError;
          console.error(TAG, `share panel failed: ${e.code} ${e.message}`);
          result.error('share_failed', e.message ?? 'unknown', null);
        });
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      console.error(TAG, `share failed: ${e.code} ${e.message}`);
      result.error('share_failed', e.message ?? 'unknown', null);
    }
  }
}
