#!/usr/bin/env python3
"""Generates TruckoRig.xcodeproj/project.pbxproj from the source tree.

The project file is generated rather than hand-maintained so that adding a Swift file never means
editing pbxproj by hand (or merging a conflict in it). Run this after adding, moving or deleting
files:

    python3 Tools/generate_xcodeproj.py

Object identifiers are derived from a hash of the object's role and path, so regenerating produces
a stable file and the diff shows only what actually changed.
"""

from __future__ import annotations

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "TruckoRig"
APP_DIR = "TruckoRig"
WIDGET_DIR = "TruckoRigWidget"

APP_BUNDLE_ID = "com.truckorig"
WIDGET_BUNDLE_ID = "com.truckorig.widget"
MARKETING_VERSION = "1.5.7"
DEPLOYMENT_TARGET = "17.0"

# App sources the widget extension also compiles. Kept deliberately small: the widget only needs
# the goal snapshot, the theme and the formatters.
WIDGET_SHARED_SOURCES = [
    "TruckoRig/Core/Persistence/WidgetBridge.swift",
    "TruckoRig/Core/Theme/Colors.swift",
    "TruckoRig/Core/Theme/Fonts.swift",
    "TruckoRig/Core/Theme/PaceStatusPresentation.swift",
    "TruckoRig/Core/Utils/StringUtils.swift",
    "TruckoRig/Domain/Models/RPMBand.swift",
    "TruckoRig/Domain/Models/WeeklyGoalProgress.swift",
]

# Files that live in the source tree but must not be copied into the bundle.
NON_BUNDLE_FILES = {"Info.plist", "TruckoRig.entitlements", "TruckoRigWidget.entitlements"}

FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".plist": "text.plist.xml",
    ".entitlements": "text.plist.entitlements",
    ".xcstrings": "text.json.xcstrings",
    ".md": "net.daringfireball.markdown",
    ".png": "image.png",
    ".json": "text.json",
    ".ttf": "file",
    ".otf": "file",
}


def object_id(role: str, path: str) -> str:
    digest = hashlib.sha256(f"{role}:{path}".encode()).hexdigest().upper()
    return digest[:24]


def file_type(name: str) -> str:
    if name.endswith(".xcassets"):
        return "folder.assetcatalog"
    _, extension = os.path.splitext(name)
    return FILE_TYPES.get(extension, "text")


class Tree:
    """Mirror of the on-disk folder structure, as PBXGroup objects."""

    def __init__(self) -> None:
        self.files: list[str] = []
        self.groups: dict[str, list[str]] = {}

    def collect(self, directory: str) -> None:
        for current, dirnames, filenames in os.walk(os.path.join(ROOT, directory)):
            relative = os.path.relpath(current, ROOT)
            # Asset catalogs are referenced whole, never walked into.
            if ".xcassets" in relative:
                dirnames[:] = []
                continue
            dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
            entries: list[str] = []
            for name in dirnames:
                entries.append(os.path.join(relative, name))
            for name in sorted(filenames):
                if name.startswith("."):
                    continue
                path = os.path.join(relative, name)
                entries.append(path)
                self.files.append(path)
            self.groups[relative] = entries

        # Asset catalogs: one reference each, added to their parent group.
        for current, dirnames, _ in os.walk(os.path.join(ROOT, directory)):
            for name in list(dirnames):
                if not name.endswith(".xcassets"):
                    continue
                relative = os.path.relpath(os.path.join(current, name), ROOT)
                self.files.append(relative)


def build() -> str:
    tree = Tree()
    tree.collect(APP_DIR)
    tree.collect(WIDGET_DIR)

    app_sources = [p for p in tree.files if p.endswith(".swift") and p.startswith(APP_DIR + os.sep)]
    widget_sources = [p for p in tree.files if p.endswith(".swift") and p.startswith(WIDGET_DIR + os.sep)]
    widget_sources += WIDGET_SHARED_SOURCES

    app_resources = [
        p for p in tree.files
        if p.startswith(APP_DIR + os.sep)
        and not p.endswith(".swift")
        and os.path.basename(p) not in NON_BUNDLE_FILES
        and not p.endswith(".md")
    ]
    widget_resources = [
        p for p in tree.files
        if p.startswith(WIDGET_DIR + os.sep)
        and not p.endswith(".swift")
        and os.path.basename(p) not in NON_BUNDLE_FILES
    ]
    widget_resources.append(f"{APP_DIR}/Resources/Localizable.xcstrings")

    lines: list[str] = []
    add = lines.append

    add("// !$*UTF8*$!")
    add("{")
    add("\tarchiveVersion = 1;")
    add("\tclasses = {")
    add("\t};")
    add("\tobjectVersion = 56;")
    add(f"\trootObject = {object_id('project', PROJECT_NAME)} /* Project object */;")
    add("\tobjects = {")

    # PBXBuildFile
    add("")
    add("/* Begin PBXBuildFile section */")
    for target, paths in (("app", app_sources + app_resources), ("widget", widget_sources + widget_resources)):
        for path in paths:
            add(
                f"\t\t{object_id(f'buildfile-{target}', path)} /* {os.path.basename(path)} */ = "
                f"{{isa = PBXBuildFile; fileRef = {object_id('fileref', path)} /* {os.path.basename(path)} */; }};"
            )
    appex = f"{PROJECT_NAME}Widget.appex"
    add(
        f"\t\t{object_id('buildfile-embed', appex)} /* {appex} in Embed Foundation Extensions */ = "
        f"{{isa = PBXBuildFile; fileRef = {object_id('product', appex)} /* {appex} */; "
        "settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };"
    )
    add("/* End PBXBuildFile section */")

    # PBXContainerItemProxy
    add("")
    add("/* Begin PBXContainerItemProxy section */")
    add(f"\t\t{object_id('proxy', 'widget')} /* PBXContainerItemProxy */ = {{")
    add("\t\t\tisa = PBXContainerItemProxy;")
    add(f"\t\t\tcontainerPortal = {object_id('project', PROJECT_NAME)} /* Project object */;")
    add("\t\t\tproxyType = 1;")
    add(f"\t\t\tremoteGlobalIDString = {object_id('target', 'widget')};")
    add(f"\t\t\tremoteInfo = {PROJECT_NAME}Widget;")
    add("\t\t};")
    add("/* End PBXContainerItemProxy section */")

    # PBXCopyFilesBuildPhase
    add("")
    add("/* Begin PBXCopyFilesBuildPhase section */")
    add(f"\t\t{object_id('phase-embed', 'app')} /* Embed Foundation Extensions */ = {{")
    add("\t\t\tisa = PBXCopyFilesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tdstPath = \"\";")
    add("\t\t\tdstSubfolderSpec = 13;")
    add("\t\t\tfiles = (")
    add(f"\t\t\t\t{object_id('buildfile-embed', appex)} /* {appex} in Embed Foundation Extensions */,")
    add("\t\t\t);")
    add("\t\t\tname = \"Embed Foundation Extensions\";")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXCopyFilesBuildPhase section */")

    # PBXFileReference
    add("")
    add("/* Begin PBXFileReference section */")
    for path in sorted(set(tree.files)):
        name = os.path.basename(path)
        add(
            f"\t\t{object_id('fileref', path)} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type(name)}; path = \"{name}\"; sourceTree = \"<group>\"; }};"
        )
    app_product = f"{PROJECT_NAME}.app"
    add(
        f"\t\t{object_id('product', app_product)} /* {app_product} */ = {{isa = PBXFileReference; "
        "explicitFileType = wrapper.application; includeInIndex = 0; "
        f"path = \"{app_product}\"; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    add(
        f"\t\t{object_id('product', appex)} /* {appex} */ = {{isa = PBXFileReference; "
        "explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; "
        f"path = \"{appex}\"; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    add("/* End PBXFileReference section */")

    # PBXFrameworksBuildPhase (empty: Swift auto-links the system frameworks it imports)
    add("")
    add("/* Begin PBXFrameworksBuildPhase section */")
    for target in ("app", "widget"):
        add(f"\t\t{object_id('phase-frameworks', target)} /* Frameworks */ = {{")
        add("\t\t\tisa = PBXFrameworksBuildPhase;")
        add("\t\t\tbuildActionMask = 2147483647;")
        add("\t\t\tfiles = (")
        add("\t\t\t);")
        add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        add("\t\t};")
    add("/* End PBXFrameworksBuildPhase section */")

    # PBXGroup
    add("")
    add("/* Begin PBXGroup section */")
    add(f"\t\t{object_id('group', 'root')} = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{object_id('group', APP_DIR)} /* {APP_DIR} */,")
    add(f"\t\t\t\t{object_id('group', WIDGET_DIR)} /* {WIDGET_DIR} */,")
    add(f"\t\t\t\t{object_id('group', 'Products')} /* Products */,")
    add("\t\t\t);")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    add(f"\t\t{object_id('group', 'Products')} /* Products */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{object_id('product', app_product)} /* {app_product} */,")
    add(f"\t\t\t\t{object_id('product', appex)} /* {appex} */,")
    add("\t\t\t);")
    add("\t\t\tname = Products;")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    for group_path in sorted(tree.groups):
        children = tree.groups[group_path]
        add(f"\t\t{object_id('group', group_path)} /* {os.path.basename(group_path)} */ = {{")
        add("\t\t\tisa = PBXGroup;")
        add("\t\t\tchildren = (")
        for child in children:
            role = "group" if child in tree.groups else "fileref"
            add(f"\t\t\t\t{object_id(role, child)} /* {os.path.basename(child)} */,")
        add("\t\t\t);")
        add(f"\t\t\tpath = \"{os.path.basename(group_path)}\";")
        add("\t\t\tsourceTree = \"<group>\";")
        add("\t\t};")
    add("/* End PBXGroup section */")

    # PBXNativeTarget
    add("")
    add("/* Begin PBXNativeTarget section */")
    targets = [
        ("app", PROJECT_NAME, app_product, "com.apple.product-type.application", True),
        ("widget", f"{PROJECT_NAME}Widget", appex, "com.apple.product-type.app-extension", False),
    ]
    for key, name, product, product_type, is_app in targets:
        add(f"\t\t{object_id('target', key)} /* {name} */ = {{")
        add("\t\t\tisa = PBXNativeTarget;")
        add(f"\t\t\tbuildConfigurationList = {object_id('configlist', key)} /* Build configuration list */;")
        add("\t\t\tbuildPhases = (")
        add(f"\t\t\t\t{object_id('phase-sources', key)} /* Sources */,")
        add(f"\t\t\t\t{object_id('phase-frameworks', key)} /* Frameworks */,")
        add(f"\t\t\t\t{object_id('phase-resources', key)} /* Resources */,")
        if is_app:
            add(f"\t\t\t\t{object_id('phase-embed', 'app')} /* Embed Foundation Extensions */,")
        add("\t\t\t);")
        add("\t\t\tbuildRules = (")
        add("\t\t\t);")
        add("\t\t\tdependencies = (")
        if is_app:
            add(f"\t\t\t\t{object_id('dependency', 'widget')} /* PBXTargetDependency */,")
        add("\t\t\t);")
        add(f"\t\t\tname = {name};")
        add(f"\t\t\tproductName = {name};")
        add(f"\t\t\tproductReference = {object_id('product', product)} /* {product} */;")
        add(f"\t\t\tproductType = \"{product_type}\";")
        add("\t\t};")
    add("/* End PBXNativeTarget section */")

    # PBXProject
    add("")
    add("/* Begin PBXProject section */")
    add(f"\t\t{object_id('project', PROJECT_NAME)} /* Project object */ = {{")
    add("\t\t\tisa = PBXProject;")
    add("\t\t\tattributes = {")
    add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    add("\t\t\t\tLastSwiftUpdateCheck = 1600;")
    add("\t\t\t\tLastUpgradeCheck = 1600;")
    add("\t\t\t\tTargetAttributes = {")
    for key, _, _, _, _ in targets:
        add(f"\t\t\t\t\t{object_id('target', key)} = {{")
        add("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
        add("\t\t\t\t\t};")
    add("\t\t\t\t};")
    add("\t\t\t};")
    add(f"\t\t\tbuildConfigurationList = {object_id('configlist', 'project')} /* Build configuration list */;")
    add("\t\t\tcompatibilityVersion = \"Xcode 15.0\";")
    add("\t\t\tdevelopmentRegion = en;")
    add("\t\t\thasScannedForEncodings = 0;")
    add("\t\t\tknownRegions = (")
    add("\t\t\t\ten,")
    add("\t\t\t\tru,")
    add("\t\t\t\tBase,")
    add("\t\t\t);")
    add(f"\t\t\tmainGroup = {object_id('group', 'root')};")
    add(f"\t\t\tproductRefGroup = {object_id('group', 'Products')} /* Products */;")
    add("\t\t\tprojectDirPath = \"\";")
    add("\t\t\tprojectRoot = \"\";")
    add("\t\t\ttargets = (")
    for key, name, _, _, _ in targets:
        add(f"\t\t\t\t{object_id('target', key)} /* {name} */,")
    add("\t\t\t);")
    add("\t\t};")
    add("/* End PBXProject section */")

    # PBXResourcesBuildPhase
    add("")
    add("/* Begin PBXResourcesBuildPhase section */")
    for key, paths in (("app", app_resources), ("widget", widget_resources)):
        add(f"\t\t{object_id('phase-resources', key)} /* Resources */ = {{")
        add("\t\t\tisa = PBXResourcesBuildPhase;")
        add("\t\t\tbuildActionMask = 2147483647;")
        add("\t\t\tfiles = (")
        for path in paths:
            add(f"\t\t\t\t{object_id(f'buildfile-{key}', path)} /* {os.path.basename(path)} */,")
        add("\t\t\t);")
        add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        add("\t\t};")
    add("/* End PBXResourcesBuildPhase section */")

    # PBXSourcesBuildPhase
    add("")
    add("/* Begin PBXSourcesBuildPhase section */")
    for key, paths in (("app", app_sources), ("widget", widget_sources)):
        add(f"\t\t{object_id('phase-sources', key)} /* Sources */ = {{")
        add("\t\t\tisa = PBXSourcesBuildPhase;")
        add("\t\t\tbuildActionMask = 2147483647;")
        add("\t\t\tfiles = (")
        for path in paths:
            add(f"\t\t\t\t{object_id(f'buildfile-{key}', path)} /* {os.path.basename(path)} */,")
        add("\t\t\t);")
        add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        add("\t\t};")
    add("/* End PBXSourcesBuildPhase section */")

    # PBXTargetDependency
    add("")
    add("/* Begin PBXTargetDependency section */")
    add(f"\t\t{object_id('dependency', 'widget')} /* PBXTargetDependency */ = {{")
    add("\t\t\tisa = PBXTargetDependency;")
    add(f"\t\t\ttarget = {object_id('target', 'widget')} /* {PROJECT_NAME}Widget */;")
    add(f"\t\t\ttargetProxy = {object_id('proxy', 'widget')} /* PBXContainerItemProxy */;")
    add("\t\t};")
    add("/* End PBXTargetDependency section */")

    # XCBuildConfiguration
    add("")
    add("/* Begin XCBuildConfiguration section */")
    for name, settings in project_configurations().items():
        add(f"\t\t{object_id('config-project', name)} /* {name} */ = {{")
        add("\t\t\tisa = XCBuildConfiguration;")
        add("\t\t\tbuildSettings = {")
        for setting, value in settings.items():
            add(f"\t\t\t\t{setting} = {value};")
        add("\t\t\t};")
        add(f"\t\t\tname = {name};")
        add("\t\t};")
    for key in ("app", "widget"):
        for name, settings in target_configurations(key).items():
            add(f"\t\t{object_id(f'config-{key}', name)} /* {name} */ = {{")
            add("\t\t\tisa = XCBuildConfiguration;")
            add("\t\t\tbuildSettings = {")
            for setting, value in settings.items():
                add(f"\t\t\t\t{setting} = {value};")
            add("\t\t\t};")
            add(f"\t\t\tname = {name};")
            add("\t\t};")
    add("/* End XCBuildConfiguration section */")

    # XCConfigurationList
    add("")
    add("/* Begin XCConfigurationList section */")
    for key, role in (("project", "config-project"), ("app", "config-app"), ("widget", "config-widget")):
        add(f"\t\t{object_id('configlist', key)} /* Build configuration list */ = {{")
        add("\t\t\tisa = XCConfigurationList;")
        add("\t\t\tbuildConfigurations = (")
        for name in ("Debug", "Release"):
            add(f"\t\t\t\t{object_id(role, name)} /* {name} */,")
        add("\t\t\t);")
        add("\t\t\tdefaultConfigurationIsVisible = 0;")
        add("\t\t\tdefaultConfigurationName = Release;")
        add("\t\t};")
    add("/* End XCConfigurationList section */")

    add("\t};")
    add("}")
    return "\n".join(lines) + "\n"


def project_configurations() -> dict[str, dict[str, str]]:
    shared = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "SDKROOT": "iphoneos",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
    }
    debug = dict(shared)
    debug.update({
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": '"DEBUG=1 $(inherited)"',
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
    })
    release = dict(shared)
    release.update({
        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
        "ENABLE_NS_ASSERTIONS": "NO",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "VALIDATE_PRODUCT": "YES",
    })
    return {"Debug": debug, "Release": release}


def target_configurations(key: str) -> dict[str, dict[str, str]]:
    if key == "app":
        settings = {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_ENTITLEMENTS": f"{APP_DIR}/Resources/TruckoRig.entitlements",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_FILE": f"{APP_DIR}/Resources/Info.plist",
            # The launch screen is declared in Info.plist (a brand-coloured field); letting Xcode
            # also generate one would write a duplicate UILaunchScreen key.
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad":
                '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown '
                'UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone":
                '"UIInterfaceOrientationPortrait"',
            "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
            "MARKETING_VERSION": MARKETING_VERSION,
            "PRODUCT_BUNDLE_IDENTIFIER": APP_BUNDLE_ID,
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "TARGETED_DEVICE_FAMILY": '"1,2"',
        }
    else:
        settings = {
            "CODE_SIGN_ENTITLEMENTS": f"{WIDGET_DIR}/TruckoRigWidget.entitlements",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_FILE": f"{WIDGET_DIR}/Info.plist",
            "INFOPLIST_KEY_CFBundleDisplayName": '"TruckoRig Goal"',
            "INFOPLIST_KEY_NSHumanReadableCopyright": '""',
            "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"',
            "MARKETING_VERSION": MARKETING_VERSION,
            "PRODUCT_BUNDLE_IDENTIFIER": WIDGET_BUNDLE_ID,
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "SKIP_INSTALL": "YES",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "TARGETED_DEVICE_FAMILY": '"1,2"',
        }
    return {"Debug": dict(settings), "Release": dict(settings)}


SCHEME_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {reference}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {reference}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {reference}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

BUILDABLE_REFERENCE = """<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "{product}"
               BlueprintName = "{name}"
               ReferencedContainer = "container:{project}.xcodeproj">
            </BuildableReference>"""


def write_scheme(directory: str) -> str:
    """Writes the shared scheme, so `xcodebuild -scheme TruckoRig` works on a fresh clone."""
    schemes = os.path.join(directory, "xcshareddata", "xcschemes")
    os.makedirs(schemes, exist_ok=True)
    reference = BUILDABLE_REFERENCE.format(
        target_id=object_id("target", "app"),
        product=f"{PROJECT_NAME}.app",
        name=PROJECT_NAME,
        project=PROJECT_NAME,
    )
    path = os.path.join(schemes, f"{PROJECT_NAME}.xcscheme")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(SCHEME_TEMPLATE.format(reference=reference))
    return path


def main() -> int:
    directory = os.path.join(ROOT, f"{PROJECT_NAME}.xcodeproj")
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, "project.pbxproj")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(build())
    print(f"wrote {path}")
    print(f"wrote {write_scheme(directory)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
