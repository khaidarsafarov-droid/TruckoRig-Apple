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
TESTS_DIR = "TruckoRigTests"
UITESTS_DIR = "TruckoRigUITests"

APP_BUNDLE_ID = "com.truckorig"
WIDGET_BUNDLE_ID = "com.truckorig.widget"
TESTS_BUNDLE_ID = "com.truckorig.tests"
UITESTS_BUNDLE_ID = "com.truckorig.uitests"

# SQLCipher build of GRDB. The app target is the only one that links it: the widget never opens
# the database, and the test bundle uses the app's copy through TEST_HOST.
GRDB_REPOSITORY = "https://github.com/sqlcipher/GRDB.swift"
GRDB_VERSION = "7.11.1"
GRDB_PRODUCT = "GRDB"
# Maps SDK for iOS. The key is not in the repo: Config/Maps.xcconfig reads GOOGLE_MAPS_API_KEY.
MAPS_REPOSITORY = "https://github.com/googlemaps/ios-maps-sdk"
MAPS_VERSION = "11.2.0"
MAPS_PRODUCT = "GoogleMaps"
CONFIG_DIR = "Config"
CONFIG_FILES = [
    "Config/Maps.xcconfig",
    "Config/Secrets.example.xcconfig",
]
MARKETING_VERSION = "1.5.7"
DEPLOYMENT_TARGET = "17.0"

# App sources the widget extension also compiles. Kept deliberately small: the widget only needs
# the goal snapshot, the theme and the formatters.
WIDGET_SHARED_SOURCES = [
    "TruckoRig/Core/Persistence/WidgetBridge.swift",
    "TruckoRig/Core/Theme/Colors.swift",
    "TruckoRig/Core/Theme/Fonts.swift",
    "TruckoRig/Core/Theme/ThemePalette.swift",
    "TruckoRig/Core/Theme/PaceStatusPresentation.swift",
    "TruckoRig/Core/Utils/StringUtils.swift",
    "TruckoRig/Domain/DeepLink/WidgetDeepLink.swift",
    "TruckoRig/Domain/Models/RPMBand.swift",
    "TruckoRig/Domain/Models/WeeklyGoalProgress.swift",
    "TruckoRig/Domain/Models/WidgetGoalSnapshot.swift",
    "TruckoRig/Domain/Units/MeasurementUnits.swift",
    "TruckoRig/Features/Widget/WeeklyGoalWidgetView.swift",
]

# Files that live in the source tree but must not be copied into the bundle.
NON_BUNDLE_FILES = {
    "Info.plist",
    "InfoSideload.plist",
    "TruckoRig.entitlements",
    "TruckoRigSideload.entitlements",
    "TruckoRigWidget.entitlements",
    # Licenses stay in the repository and out of the app bundle.
    "DMSans-OFL.txt",
    "Roboto-LICENSE.txt",
    # StoreKit configuration is selected by the scheme. It is not an app resource.
    "Premium.storekit",
}

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
    ".storekit": "text.json",
    ".xcconfig": "text.xcconfig",
    ".xcprivacy": "text.plist.xml",
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
    tree.collect(TESTS_DIR)
    tree.collect(UITESTS_DIR)
    # xcconfig lives outside the app sources. Secrets.xcconfig is gitignored and not referenced.
    tree.groups[CONFIG_DIR] = list(CONFIG_FILES)
    tree.files.extend(CONFIG_FILES)

    app_sources = [p for p in tree.files if p.endswith(".swift") and p.startswith(APP_DIR + os.sep)]
    widget_sources = [p for p in tree.files if p.endswith(".swift") and p.startswith(WIDGET_DIR + os.sep)]
    widget_sources += WIDGET_SHARED_SOURCES
    test_sources = [p for p in tree.files if p.endswith(".swift") and p.startswith(TESTS_DIR + os.sep)]
    ui_test_sources = [p for p in tree.files if p.endswith(".swift") and p.startswith(UITESTS_DIR + os.sep)]

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
    font_directory = os.path.join(ROOT, APP_DIR, "Resources", "Fonts")
    if os.path.isdir(font_directory):
        widget_resources.extend(
            os.path.join(APP_DIR, "Resources", "Fonts", name)
            for name in sorted(os.listdir(font_directory))
            if name.endswith(".ttf")
        )

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
    for target, paths in (
        ("app", app_sources + app_resources),
        ("widget", widget_sources + widget_resources),
        ("tests", test_sources),
        ("uitests", ui_test_sources),
    ):
        for path in paths:
            add(
                f"\t\t{object_id(f'buildfile-{target}', path)} /* {os.path.basename(path)} */ = "
                f"{{isa = PBXBuildFile; fileRef = {object_id('fileref', path)} /* {os.path.basename(path)} */; }};"
            )
    add(
        f"\t\t{object_id('buildfile-app', GRDB_PRODUCT)} /* {GRDB_PRODUCT} in Frameworks */ = "
        f"{{isa = PBXBuildFile; productRef = {object_id('package-product', GRDB_PRODUCT)} /* {GRDB_PRODUCT} */; }};"
    )
    add(
        f"\t\t{object_id('buildfile-app', MAPS_PRODUCT)} /* {MAPS_PRODUCT} in Frameworks */ = "
        f"{{isa = PBXBuildFile; productRef = {object_id('package-product', MAPS_PRODUCT)} /* {MAPS_PRODUCT} */; }};"
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
    add(f"\t\t{object_id('proxy', 'tests')} /* PBXContainerItemProxy */ = {{")
    add("\t\t\tisa = PBXContainerItemProxy;")
    add(f"\t\t\tcontainerPortal = {object_id('project', PROJECT_NAME)} /* Project object */;")
    add("\t\t\tproxyType = 1;")
    add(f"\t\t\tremoteGlobalIDString = {object_id('target', 'app')};")
    add(f"\t\t\tremoteInfo = {PROJECT_NAME};")
    add("\t\t};")
    add(f"\t\t{object_id('proxy', 'uitests')} /* PBXContainerItemProxy */ = {{")
    add("\t\t\tisa = PBXContainerItemProxy;")
    add(f"\t\t\tcontainerPortal = {object_id('project', PROJECT_NAME)} /* Project object */;")
    add("\t\t\tproxyType = 1;")
    add(f"\t\t\tremoteGlobalIDString = {object_id('target', 'app')};")
    add(f"\t\t\tremoteInfo = {PROJECT_NAME};")
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
    test_product = f"{PROJECT_NAME}Tests.xctest"
    add(
        f"\t\t{object_id('product', test_product)} /* {test_product} */ = {{isa = PBXFileReference; "
        "explicitFileType = wrapper.cfbundle; includeInIndex = 0; "
        f"path = \"{test_product}\"; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    ui_test_product = f"{PROJECT_NAME}UITests.xctest"
    add(
        f"\t\t{object_id('product', ui_test_product)} /* {ui_test_product} */ = {{isa = PBXFileReference; "
        "explicitFileType = wrapper.cfbundle; includeInIndex = 0; "
        f"path = \"{ui_test_product}\"; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    add("/* End PBXFileReference section */")

    # PBXFrameworksBuildPhase (empty: Swift auto-links the system frameworks it imports)
    add("")
    add("/* Begin PBXFrameworksBuildPhase section */")
    for target in ("app", "widget", "tests", "uitests"):
        add(f"\t\t{object_id('phase-frameworks', target)} /* Frameworks */ = {{")
        add("\t\t\tisa = PBXFrameworksBuildPhase;")
        add("\t\t\tbuildActionMask = 2147483647;")
        add("\t\t\tfiles = (")
        if target == "app":
            add(f"\t\t\t\t{object_id('buildfile-app', GRDB_PRODUCT)} /* {GRDB_PRODUCT} in Frameworks */,")
            add(f"\t\t\t\t{object_id('buildfile-app', MAPS_PRODUCT)} /* {MAPS_PRODUCT} in Frameworks */,")
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
    add(f"\t\t\t\t{object_id('group', TESTS_DIR)} /* {TESTS_DIR} */,")
    add(f"\t\t\t\t{object_id('group', UITESTS_DIR)} /* {UITESTS_DIR} */,")
    add(f"\t\t\t\t{object_id('group', CONFIG_DIR)} /* {CONFIG_DIR} */,")
    add(f"\t\t\t\t{object_id('group', 'Products')} /* Products */,")
    add("\t\t\t);")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    add(f"\t\t{object_id('group', 'Products')} /* Products */ = {{")
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add(f"\t\t\t\t{object_id('product', app_product)} /* {app_product} */,")
    add(f"\t\t\t\t{object_id('product', appex)} /* {appex} */,")
    add(f"\t\t\t\t{object_id('product', test_product)} /* {test_product} */,")
    add(f"\t\t\t\t{object_id('product', ui_test_product)} /* {ui_test_product} */,")
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
        ("app", PROJECT_NAME, app_product, "com.apple.product-type.application"),
        ("widget", f"{PROJECT_NAME}Widget", appex, "com.apple.product-type.app-extension"),
        ("tests", f"{PROJECT_NAME}Tests", test_product, "com.apple.product-type.bundle.unit-test"),
        ("uitests", f"{PROJECT_NAME}UITests", ui_test_product, "com.apple.product-type.bundle.ui-testing"),
    ]
    for key, name, product, product_type in targets:
        add(f"\t\t{object_id('target', key)} /* {name} */ = {{")
        add("\t\t\tisa = PBXNativeTarget;")
        add(f"\t\t\tbuildConfigurationList = {object_id('configlist', key)} /* Build configuration list */;")
        add("\t\t\tbuildPhases = (")
        add(f"\t\t\t\t{object_id('phase-sources', key)} /* Sources */,")
        add(f"\t\t\t\t{object_id('phase-frameworks', key)} /* Frameworks */,")
        add(f"\t\t\t\t{object_id('phase-resources', key)} /* Resources */,")
        if key == "app":
            add(f"\t\t\t\t{object_id('phase-embed', 'app')} /* Embed Foundation Extensions */,")
            add(f"\t\t\t\t{object_id('phase-strip', 'app')} /* Strip widget for sideload */,")
        add("\t\t\t);")
        add("\t\t\tbuildRules = (")
        add("\t\t\t);")
        add("\t\t\tdependencies = (")
        if key == "app":
            add(f"\t\t\t\t{object_id('dependency', 'widget')} /* PBXTargetDependency */,")
        if key == "tests":
            add(f"\t\t\t\t{object_id('dependency', 'tests')} /* PBXTargetDependency */,")
        if key == "uitests":
            add(f"\t\t\t\t{object_id('dependency', 'uitests')} /* PBXTargetDependency */,")
        add("\t\t\t);")
        add(f"\t\t\tname = {name};")
        if key == "app":
            add("\t\t\tpackageProductDependencies = (")
            add(f"\t\t\t\t{object_id('package-product', GRDB_PRODUCT)} /* {GRDB_PRODUCT} */,")
            add(f"\t\t\t\t{object_id('package-product', MAPS_PRODUCT)} /* {MAPS_PRODUCT} */,")
            add("\t\t\t);")
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
    for key, _, _, _ in targets:
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
    add("\t\t\t\tes,")
    add("\t\t\t\tfr,")
    add("\t\t\t\tru,")
    add("\t\t\t\tBase,")
    add("\t\t\t);")
    add(f"\t\t\tmainGroup = {object_id('group', 'root')};")
    add("\t\t\tpackageReferences = (")
    add(f"\t\t\t\t{object_id('package', GRDB_REPOSITORY)} /* XCRemoteSwiftPackageReference \"GRDB.swift\" */,")
    add(f"\t\t\t\t{object_id('package', MAPS_REPOSITORY)} /* XCRemoteSwiftPackageReference \"ios-maps-sdk\" */,")
    add("\t\t\t);")
    add(f"\t\t\tproductRefGroup = {object_id('group', 'Products')} /* Products */;")
    add("\t\t\tprojectDirPath = \"\";")
    add("\t\t\tprojectRoot = \"\";")
    add("\t\t\ttargets = (")
    for key, name, _, _ in targets:
        add(f"\t\t\t\t{object_id('target', key)} /* {name} */,")
    add("\t\t\t);")
    add("\t\t};")
    add("/* End PBXProject section */")

    # PBXResourcesBuildPhase
    add("")
    add("/* Begin PBXResourcesBuildPhase section */")
    for key, paths in (("app", app_resources), ("widget", widget_resources), ("tests", []), ("uitests", [])):
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
    for key, paths in (("app", app_sources), ("widget", widget_sources), ("tests", test_sources), ("uitests", ui_test_sources)):
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

    # Removes the widget appex only from the Sideload configuration. Debug and Release keep it.
    add("")
    add("/* Begin PBXShellScriptBuildPhase section */")
    add(f"\t\t{object_id('phase-strip', 'app')} /* Strip widget for sideload */ = {{")
    add("\t\t\tisa = PBXShellScriptBuildPhase;")
    add("\t\t\talwaysOutOfDate = 1;")
    add("\t\t\tenableUserScriptSandboxing = 0;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    add("\t\t\t);")
    add("\t\t\tinputFileListPaths = (")
    add("\t\t\t);")
    add("\t\t\tinputPaths = (")
    add("\t\t\t);")
    add('\t\t\tname = "Strip widget for sideload";')
    add("\t\t\toutputFileListPaths = (")
    add("\t\t\t);")
    add("\t\t\toutputPaths = (")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t\tshellPath = /bin/sh;")
    add(
        '\t\t\tshellScript = "if [ \\"$CONFIGURATION\\" = \\"Sideload\\" ]; then\\n'
        '  rm -rf \\"${TARGET_BUILD_DIR}/${WRAPPER_NAME}/PlugIns\\" || true\\n'
        'fi\\n";'
    )
    add("\t\t};")
    add("/* End PBXShellScriptBuildPhase section */")

    # PBXTargetDependency
    add("")
    add("/* Begin PBXTargetDependency section */")
    add(f"\t\t{object_id('dependency', 'widget')} /* PBXTargetDependency */ = {{")
    add("\t\t\tisa = PBXTargetDependency;")
    add(f"\t\t\ttarget = {object_id('target', 'widget')} /* {PROJECT_NAME}Widget */;")
    add(f"\t\t\ttargetProxy = {object_id('proxy', 'widget')} /* PBXContainerItemProxy */;")
    add("\t\t};")
    add(f"\t\t{object_id('dependency', 'tests')} /* PBXTargetDependency */ = {{")
    add("\t\t\tisa = PBXTargetDependency;")
    add(f"\t\t\ttarget = {object_id('target', 'app')} /* {PROJECT_NAME} */;")
    add(f"\t\t\ttargetProxy = {object_id('proxy', 'tests')} /* PBXContainerItemProxy */;")
    add("\t\t};")
    add(f"\t\t{object_id('dependency', 'uitests')} /* PBXTargetDependency */ = {{")
    add("\t\t\tisa = PBXTargetDependency;")
    add(f"\t\t\ttarget = {object_id('target', 'app')} /* {PROJECT_NAME} */;")
    add(f"\t\t\ttargetProxy = {object_id('proxy', 'uitests')} /* PBXContainerItemProxy */;")
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
    for key in ("app", "widget", "tests", "uitests"):
        for name, settings in target_configurations(key).items():
            add(f"\t\t{object_id(f'config-{key}', name)} /* {name} */ = {{")
            add("\t\t\tisa = XCBuildConfiguration;")
            if key == "app":
                maps_config = "Config/Maps.xcconfig"
                add(
                    f"\t\t\tbaseConfigurationReference = {object_id('fileref', maps_config)} "
                    "/* Maps.xcconfig */;"
                )
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
    for key, role in (
        ("project", "config-project"),
        ("app", "config-app"),
        ("widget", "config-widget"),
        ("tests", "config-tests"),
        ("uitests", "config-uitests"),
    ):
        add(f"\t\t{object_id('configlist', key)} /* Build configuration list */ = {{")
        add("\t\t\tisa = XCConfigurationList;")
        add("\t\t\tbuildConfigurations = (")
        for name in ("Debug", "Release", "Sideload"):
            add(f"\t\t\t\t{object_id(role, name)} /* {name} */,")
        add("\t\t\t);")
        add("\t\t\tdefaultConfigurationIsVisible = 0;")
        add("\t\t\tdefaultConfigurationName = Release;")
        add("\t\t};")
    add("/* End XCConfigurationList section */")

    add("")
    add("/* Begin XCRemoteSwiftPackageReference section */")
    add(f"\t\t{object_id('package', GRDB_REPOSITORY)} /* XCRemoteSwiftPackageReference \"GRDB.swift\" */ = {{")
    add("\t\t\tisa = XCRemoteSwiftPackageReference;")
    add(f"\t\t\trepositoryURL = \"{GRDB_REPOSITORY}\";")
    add("\t\t\trequirement = {")
    add("\t\t\t\tkind = exactVersion;")
    add(f"\t\t\t\tversion = {GRDB_VERSION};")
    add("\t\t\t};")
    add("\t\t};")
    add(f"\t\t{object_id('package', MAPS_REPOSITORY)} /* XCRemoteSwiftPackageReference \"ios-maps-sdk\" */ = {{")
    add("\t\t\tisa = XCRemoteSwiftPackageReference;")
    add(f"\t\t\trepositoryURL = \"{MAPS_REPOSITORY}\";")
    add("\t\t\trequirement = {")
    add("\t\t\t\tkind = exactVersion;")
    add(f"\t\t\t\tversion = {MAPS_VERSION};")
    add("\t\t\t};")
    add("\t\t};")
    add("/* End XCRemoteSwiftPackageReference section */")

    add("")
    add("/* Begin XCSwiftPackageProductDependency section */")
    add(f"\t\t{object_id('package-product', GRDB_PRODUCT)} /* {GRDB_PRODUCT} */ = {{")
    add("\t\t\tisa = XCSwiftPackageProductDependency;")
    add(f"\t\t\tpackage = {object_id('package', GRDB_REPOSITORY)} /* XCRemoteSwiftPackageReference \"GRDB.swift\" */;")
    add(f"\t\t\tproductName = {GRDB_PRODUCT};")
    add("\t\t};")
    add(f"\t\t{object_id('package-product', MAPS_PRODUCT)} /* {MAPS_PRODUCT} */ = {{")
    add("\t\t\tisa = XCSwiftPackageProductDependency;")
    add(f"\t\t\tpackage = {object_id('package', MAPS_REPOSITORY)} /* XCRemoteSwiftPackageReference \"ios-maps-sdk\" */;")
    add(f"\t\t\tproductName = {MAPS_PRODUCT};")
    add("\t\t};")
    add("/* End XCSwiftPackageProductDependency section */")

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
    # Same optimizer settings as Release. The app target turns signing and paid capabilities off.
    sideload = dict(release)
    sideload["VALIDATE_PRODUCT"] = "NO"
    return {"Debug": debug, "Release": release, "Sideload": sideload}


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
            # Maps SDK categories. The key itself stays in Config/Maps.xcconfig, not here,
            # so this dictionary cannot override GOOGLE_MAPS_API_KEY with an empty value.
            "OTHER_LDFLAGS": '"$(inherited) -ObjC"',
            "MARKETING_VERSION": MARKETING_VERSION,
            "PRODUCT_BUNDLE_IDENTIFIER": APP_BUNDLE_ID,
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "TARGETED_DEVICE_FAMILY": '"1,2"',
        }
    elif key == "uitests":
        settings = {
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "YES",
            "MARKETING_VERSION": MARKETING_VERSION,
            "PRODUCT_BUNDLE_IDENTIFIER": UITESTS_BUNDLE_ID,
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "TARGETED_DEVICE_FAMILY": '"1,2"',
            "TEST_TARGET_NAME": PROJECT_NAME,
        }
    elif key == "widget":
        settings = {
            "CODE_SIGN_ENTITLEMENTS": f"{WIDGET_DIR}/TruckoRigWidget.entitlements",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_FILE": f"{WIDGET_DIR}/Info.plist",
            "INFOPLIST_KEY_CFBundleDisplayName": '"TruckoRig"',
            "INFOPLIST_KEY_NSHumanReadableCopyright": '""',
            "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"',
            "MARKETING_VERSION": MARKETING_VERSION,
            "PRODUCT_BUNDLE_IDENTIFIER": WIDGET_BUNDLE_ID,
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "SKIP_INSTALL": "YES",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "TARGETED_DEVICE_FAMILY": '"1,2"',
        }
    else:
        settings = {
            "BUNDLE_LOADER": '"$(TEST_HOST)"',
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "YES",
            "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @loader_path/Frameworks"',
            "MARKETING_VERSION": MARKETING_VERSION,
            "PRODUCT_BUNDLE_IDENTIFIER": TESTS_BUNDLE_ID,
            "PRODUCT_NAME": '"$(TARGET_NAME)"',
            "TARGETED_DEVICE_FAMILY": '"1,2"',
            "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/TruckoRig.app/TruckoRig"',
        }
    debug = dict(settings)
    release = dict(settings)
    sideload = dict(settings)
    if key == "app":
        sideload.update({
            "CODE_SIGN_ENTITLEMENTS": f"{APP_DIR}/Resources/TruckoRigSideload.entitlements",
            "CODE_SIGN_IDENTITY": '"-"',
            "CODE_SIGNING_ALLOWED": "NO",
            "CODE_SIGNING_REQUIRED": "NO",
            "INFOPLIST_FILE": f"{APP_DIR}/Resources/InfoSideload.plist",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"SIDELOAD"',
            "VALIDATE_PRODUCT": "NO",
        })
    elif key == "widget":
        # Still built, because the app target depends on it, then deleted from the Sideload app.
        sideload.update({
            "CODE_SIGN_IDENTITY": '"-"',
            "CODE_SIGNING_ALLOWED": "NO",
            "CODE_SIGNING_REQUIRED": "NO",
        })
    return {"Debug": debug, "Release": release, "Sideload": sideload}


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
{testables}
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
      <StoreKitConfigurationFileReference
         identifier = "../../TruckoRig/Resources/Premium.storekit">
      </StoreKitConfigurationFileReference>
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
    def testable(key: str, product: str, name: str) -> str:
        block = BUILDABLE_REFERENCE.format(
            target_id=object_id("target", key),
            product=product,
            name=name,
            project=PROJECT_NAME,
        )
        return (
            "         <TestableReference\n"
            "            skipped = \"NO\">\n"
            f"            {block}\n"
            "         </TestableReference>"
        )

    testables = "\n".join([
        testable("tests", f"{PROJECT_NAME}Tests.xctest", f"{PROJECT_NAME}Tests"),
        testable("uitests", f"{PROJECT_NAME}UITests.xctest", f"{PROJECT_NAME}UITests"),
    ])
    path = os.path.join(schemes, f"{PROJECT_NAME}.xcscheme")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(SCHEME_TEMPLATE.format(reference=reference, testables=testables))
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
