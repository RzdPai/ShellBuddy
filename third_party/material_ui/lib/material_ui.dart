/// The Material widget set.
///
/// On a stock Flutter, `material_ui` *is* the Material library: it was split
/// out of the framework and published, and `package:flutter/material.dart`
/// re-exports it. The HarmonyOS fork never took that split — its framework
/// still carries `src/material`, with `TargetPlatform.ohos` handled throughout
/// all ~200 places it matters — while the published `material_ui` enumerates
/// `TargetPlatform` exhaustively and so cannot compile against a framework that
/// added a value.
///
/// Pointing the imports at the framework's own copy is therefore both the
/// smaller change and the one where the HarmonyOS behaviour is already written.
library material_ui;

import 'package:flutter/widgets.dart';

export 'package:flutter/material.dart';
// `material_ui` re-exports these, and code that only imports it relies on that.
export 'package:flutter_localizations/flutter_localizations.dart';

/// Does nothing here.
///
/// Upstream this maps a `material_ui` theme onto the legacy `Theme` that
/// dependencies importing `package:flutter/material.dart` still read. With the
/// app on a single Material implementation there are no two themes to bridge,
/// so the widget is kept only because call sites still name it — removing it
/// would be a change in app code for no behaviour.
@Deprecated('The app uses one Material implementation; this is a no-op.')
class MaterialUiCompatibilityBridge extends StatelessWidget {
  /// Creates a no-op bridge.
  const MaterialUiCompatibilityBridge({
    super.key,
    required this.child,
    this.delegates,
  });

  /// The widget below this widget in the tree.
  final Widget child;

  /// Ignored. Accepted so existing call sites keep compiling.
  final List<LocalizationsDelegate<dynamic>>? delegates;

  @override
  Widget build(BuildContext context) => child;
}
