
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import QrScanOhosPlugin from '../plugins/QrScanOhosPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // Registered here, not in GeneratedPluginRegistrant: this OHOS toolchain
    // regenerates that file from a stale .flutter-plugins-dependencies, which
    // drops plugins added after the project was scaffolded.
    flutterEngine.getPlugins()?.add(new QrScanOhosPlugin())
  }
}
