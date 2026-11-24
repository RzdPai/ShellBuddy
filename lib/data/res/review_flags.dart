/// Flags that hide functionality for a store submission, without deleting it.
///
/// This is a single, intentional switch: set [hideAi] back to `false` and
/// rebuild once the AI qualification is approved, and every hidden entry
/// below comes back. Nothing is removed from the tree — only the visible
/// entry points are gated, so restoring is a one-line change rather than a
/// revert of a sprawling diff.
abstract final class ReviewFlags {
  /// Hide every user-facing AI / Agent entry point.
  ///
  /// Domestic app-store policy requires an AI qualification before an app may
  /// ship AI features. Until it is granted, the Agent tab, its settings
  /// section, and the terminal's "Ask AI" affordances are hidden. The code,
  /// providers, tools and stored chats are all left intact.
  static const bool hideAi = true;
}
