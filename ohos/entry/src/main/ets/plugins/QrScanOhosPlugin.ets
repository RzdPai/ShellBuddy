/**
 * HarmonyOS system QR scan plugin.
 *
 * `qr_code_dart_scan` drives a camera preview through a plugin that has no
 * OHOS implementation, so its page never opens on this platform. Scan Kit
 * supplies a system scan UI instead, and `detectBarcode` decodes a code from
 * an album image. The system owns the camera / picker, so the app needs no
 * CAMERA permission.
 *
 * Device split: a real camera path works on phone/tablet (and any 2in1 that
 * actually has a camera). Many 2in1/PC devices have NO camera — on those,
 * `startScanForResult` resolves with `null`, and dereferencing
 * `res.originalValue` threw "Cannot read property originalValue of null".
 * So we probe for a camera first: with one, use the system scan UI; without
 * one (or if the scan yields nothing), fall back to the photo picker +
 * on-device decode. Every callback is null-safe.
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
import { scanBarcode, scanCore, detectBarcode } from '@kit.ScanKit';
import { camera } from '@kit.CameraKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

const TAG: string = 'QrScanOhosPlugin';
const CHANNEL: string = 'serverbox.ohos/qr_scan';
const SCAN_CANCELED: number = 1000500002;

export default class QrScanOhosPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
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
      case 'scan':
        this.startScan(result);
        break;
      default:
        result.notImplemented();
    }
  }

  /** True only when the device exposes at least one physical camera. */
  private hasCamera(): boolean {
    if (this.uiContext == null) return false;
    try {
      const manager = camera.getCameraManager(this.uiContext);
      return manager.getSupportedCameras().length > 0;
    } catch (e) {
      const err = e as BusinessError;
      console.warn(TAG, `camera probe failed, assuming no camera: ${err?.code} ${err?.message}`);
      return false;
    }
  }

  private startScan(result: MethodResult): void {
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: true,
    };

    // Null-safe result delivery. An empty string maps to "cancelled" on the
    // Dart side (scanQrCode() returns null), never a crash or a false error.
    const deliver = (res: scanBarcode.ScanResult | null | undefined): void => {
      const value: string = res?.originalValue ?? '';
      result.success(value);
    };

    // Photo-picker path — the only way to scan on a camera-less 2in1/PC.
    const fromAlbum = (): void => {
      this.scanFromAlbum(options, deliver, result);
    };

    // If a device reports a camera but the system scanner still fails or
    // resolves null, give the album path a chance before giving up.
    const onSystemFailure = (err?: BusinessError): void => {
      if (err != null) {
        if (err.code === SCAN_CANCELED) {
          result.success('');
          return;
        }
        console.error(TAG, `system scan failed: ${err.code} ${err.message}; trying album`);
      }
      fromAlbum();
    };

    if (this.hasCamera()) {
      scanBarcode.startScanForResult(this.uiContext, options)
        .then((res: scanBarcode.ScanResult) => {
          if (res != null && res.originalValue != null && res.originalValue.length > 0) {
            deliver(res);
          } else {
            // Resolved but empty (seen on some 2in1) — not a user cancellation.
            onSystemFailure();
          }
        })
        .catch((e: BusinessError) => onSystemFailure(e));
    } else {
      fromAlbum();
    }
  }

  /**
   * Ask the system photo picker for one image and decode any QR code in it.
   * The picker grants a temporary read grant on the returned URI, so no
   * ohos.permission is required. Picker cancellation is treated as "cancel".
   */
  private scanFromAlbum(
    options: scanBarcode.ScanOptions,
    deliver: (res: scanBarcode.ScanResult | null | undefined) => void,
    result: MethodResult,
  ): void {
    const picker = new photoAccessHelper.PhotoViewPicker();
    picker.select({
      MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
      maxSelectNumber: 1,
    }).then((sel: photoAccessHelper.PhotoSelectResult) => {
      const uri: string | undefined = sel?.photoUris?.[0];
      if (uri == null || uri.length === 0) {
        // Nothing chosen — equivalent to cancelling.
        result.success('');
        return;
      }
      detectBarcode.decode({ uri: uri }, options)
        .then((codes: scanBarcode.ScanResult[]) => {
          deliver(codes?.[0]);
        })
        .catch((e: BusinessError) => {
          console.error(TAG, `album decode failed: ${e?.code} ${e?.message}`);
          result.error('scan_failed', e?.message ?? 'Cannot decode QR image', null);
        });
    }).catch((e: BusinessError) => {
      // The user dismissed the picker. Do not surface it as an error.
      console.info(TAG, `album picker dismissed: ${e?.code} ${e?.message}`);
      result.success('');
    });
  }
}
