from pathlib import Path
import shutil


def read(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    Path(path).write_text(text, encoding="utf-8")


stage = Path(".ci/neura-adaptive-intent-phase4")
replacements = {
    stage / "runtime.dart": Path(
        "lib/adaptive_intent/neura_adaptive_intent_runtime.dart"
    ),
    stage / "status_card.dart": Path(
        "lib/adaptive_intent/neura_adaptive_intent_status_card.dart"
    ),
    stage / "session_screen.dart": Path(
        "lib/adaptive_intent/neura_adaptive_session_screen.dart"
    ),
    stage / "adaptive_intent.dart": Path(
        "lib/adaptive_intent/adaptive_intent.dart"
    ),
    stage / "README.md": Path("NEURA_ADAPTIVE_INTENT_OS_V1_4.md"),
}
for source, destination in replacements.items():
    if not source.is_file():
        raise SystemExit(f"Missing Phase 4 staged source: {source}")
    destination.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")


# Carry live-signal evidence metadata into the existing controller.
controller_path = "lib/adaptive_intent/neura_adaptive_intent_controller.dart"
controller = read(controller_path)
old_signature = """    double? completionRate,
    double? notificationPressure,
  }) {"""
new_signature = """    double? completionRate,
    double? notificationPressure,
    int? evidenceCount,
    bool? includesSelfReport,
  }) {"""
if "int? evidenceCount" not in controller:
    if old_signature not in controller:
        raise SystemExit("Adaptive Intent updateSignals signature anchor missing.")
    controller = controller.replace(old_signature, new_signature, 1)

old_copy = """      completionRate: completionRate,
      notificationPressure: notificationPressure,
    );"""
new_copy = """      completionRate: completionRate,
      notificationPressure: notificationPressure,
      evidenceCount: evidenceCount,
      includesSelfReport: includesSelfReport,
    );"""
if "evidenceCount: evidenceCount" not in controller:
    if old_copy not in controller:
        raise SystemExit("Adaptive Intent signal copy anchor missing.")
    controller = controller.replace(old_copy, new_copy, 1)
write(controller_path, controller)


# Route the dashboard tile through the enrollment gate and collect bounded
# in-app surface-switch counts.
navigation_path = "lib/modules/navigation/enhanced_navigation.dart"
navigation = read(navigation_path)
old_screen_import = (
    "import '../../adaptive_intent/neura_adaptive_intent_screen.dart';\n"
)
entry_import = (
    "import '../../adaptive_intent/"
    "neura_adaptive_intent_entry_screen.dart';\n"
)
live_import = (
    "import '../../adaptive_intent/neura_live_signal_adapter.dart';\n"
)
if old_screen_import in navigation:
    navigation = navigation.replace(old_screen_import, entry_import, 1)
elif entry_import not in navigation:
    anchor = "import '../../core/memory/memory_consolidation_service.dart';\n"
    if anchor not in navigation:
        raise SystemExit("EnhancedNavigation import anchor missing.")
    navigation = navigation.replace(anchor, entry_import + anchor, 1)
if live_import not in navigation:
    navigation = navigation.replace(entry_import, entry_import + live_import, 1)

navigation = navigation.replace(
    "const NeuraAdaptiveIntentScreen()",
    "const NeuraAdaptiveIntentEntryScreen()",
)
tab_anchor = """  void _onTab(int i) {
    setState(() => _index = i);"""
tab_replacement = """  void _onTab(int i) {
    NeuraAdaptiveActivityTracker.instance.recordSurfaceVisit(
      'primary_tab_$i',
    );
    setState(() => _index = i);"""
if "primary_tab_$i" not in navigation:
    if tab_anchor not in navigation:
        raise SystemExit("EnhancedNavigation tab anchor missing.")
    navigation = navigation.replace(tab_anchor, tab_replacement, 1)
write(navigation_path, navigation)


# Drain and clear encrypted Adaptive Intent outcomes before deleting the shared
# OS-backed encryption key.
wipe_path = "lib/src/core/data_wipe_service.dart"
wipe = read(wipe_path)
runtime_import = (
    "import '../../adaptive_intent/"
    "neura_adaptive_intent_runtime.dart';\n"
)
if runtime_import not in wipe:
    import_anchor = "import '../../core/memory/memory_crypto.dart';\n"
    if import_anchor not in wipe:
        raise SystemExit("Data-wipe import anchor missing.")
    wipe = wipe.replace(import_anchor, runtime_import + import_anchor, 1)

reset_block = """    await _attempt(
      failures,
      'adaptive intent shutdown',
      NeuraAdaptiveIntentRuntime.instance.resetAfterDataWipe,
    );
"""
if "'adaptive intent shutdown'" not in wipe:
    reset_anchor = """    // Drain persistent writers and release cached file paths before removing
    // their parent directories.
"""
    if reset_anchor not in wipe:
        raise SystemExit("Data-wipe reset anchor missing.")
    wipe = wipe.replace(reset_anchor, reset_anchor + reset_block, 1)

resume_line = (
    "    NeuraAdaptiveIntentRuntime.instance.resumeAfterDataWipe();\n"
)
if resume_line not in wipe:
    resume_anchor = (
        "    ProactiveBannerService.instance.resumeAfterDataWipe();\n"
    )
    if resume_anchor not in wipe:
        raise SystemExit("Data-wipe resume anchor missing.")
    wipe = wipe.replace(resume_anchor, resume_line + resume_anchor, 1)
write(wipe_path, wipe)


# Keep the permanent hosted gate aware of the integration surfaces.
workflow_path = ".github/workflows/neura-adaptive-intent-validation.yml"
workflow = read(workflow_path)
nav_path_line = '      - "lib/modules/navigation/enhanced_navigation.dart"\n'
wipe_path_line = '      - "lib/src/core/data_wipe_service.dart"\n'
path_anchor = (
    '      - "lib/dashboard/widgets/proactive_banner_card.dart"\n'
)
if nav_path_line not in workflow:
    if path_anchor not in workflow:
        raise SystemExit("Validation workflow path anchor missing.")
    workflow = workflow.replace(
        path_anchor,
        path_anchor + nav_path_line + wipe_path_line,
        1,
    )

format_anchor = (
    "            lib/dashboard/widgets/proactive_banner_card.dart \\\n"
)
format_lines = (
    "            lib/modules/navigation/enhanced_navigation.dart \\\n"
    "            lib/src/core/data_wipe_service.dart \\\n"
)
if "lib/src/core/data_wipe_service.dart \\" not in workflow:
    if format_anchor not in workflow:
        raise SystemExit("Validation workflow format anchor missing.")
    workflow = workflow.replace(
        format_anchor,
        format_anchor + format_lines,
        1,
    )
write(workflow_path, workflow)


# Advance the package milestone.
pubspec_path = "pubspec.yaml"
pubspec = read(pubspec_path)
if "version: 1.4.0+7" not in pubspec:
    if "version: 1.4.0+6" not in pubspec:
        raise SystemExit("Expected Neura 1.4 package version missing.")
    pubspec = pubspec.replace(
        "version: 1.4.0+6",
        "version: 1.4.0+7",
        1,
    )
write(pubspec_path, pubspec)

shutil.rmtree(stage)
Path(__file__).unlink()
