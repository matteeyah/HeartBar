#!/usr/bin/env python3
"""Regenerate the checked-in Xcode project using only the Python standard library."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
objects = {}


def identifier(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def add(object_name, isa, **values):
    key = identifier(object_name)
    objects[key] = dict(isa=isa, **values)
    return key


def ref(name, path, kind, tree="<group>"):
    return add(name, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree=tree)


def build(name, file_ref, **values):
    return add(name, "PBXBuildFile", fileRef=file_ref, **values)


def group(name, children, path=None):
    return add("group:" + name, "PBXGroup", children=children, name=name,
               sourceTree="<group>", **({"path": path} if path else {}))


def phase(object_name, kind, files, **values):
    return add(object_name, kind, buildActionMask=2147483647, files=files,
               runOnlyForDeploymentPostprocessing=0, **values)


def configurations(name, common, debug=None, release=None):
    configs = []
    for variant, extra in [("Debug", debug or {}), ("Release", release or {})]:
        configs.append(add(name + variant, "XCBuildConfiguration", name=variant,
                           buildSettings={**common, **extra}))
    return add("config:" + name, "XCConfigurationList", buildConfigurations=configs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


source_groups = []
source_phases = {}
for target, directory in [("HeartBarCore", "Sources/HeartBarCore"),
                          ("HeartBar", "Sources/HeartBarApp"),
                          ("HeartBarCoreTests", "Tests/HeartBarCoreTests")]:
    refs, builds = [], []
    for path in sorted((ROOT / directory).glob("*.swift")):
        file_ref = ref(str(path.relative_to(ROOT)), path.name, "sourcecode.swift")
        refs.append(file_ref)
        builds.append(build("build:" + str(path.relative_to(ROOT)), file_ref))
    source_groups.append(group(target, refs, directory))
    source_phases[target] = phase("sources:" + target, "PBXSourcesBuildPhase", builds)

products = {}
for name, suffix, kind in [("HeartBar", ".app", "wrapper.application"),
                           ("HeartBarCore", ".framework", "wrapper.framework"),
                           ("HeartBarCoreTests", ".xctest", "wrapper.cfbundle")]:
    products[name] = add("product:" + name, "PBXFileReference", explicitFileType=kind,
                         includeInIndex=0, path=name + suffix, sourceTree="BUILT_PRODUCTS_DIR")

icon = ref("icon", "AppIcon.icns", "image.icns")
resource_group = group("Resources", [ref("info", "Info.plist", "text.plist.xml"),
                                    ref("entitlements", "HeartBar.entitlements", "text.plist.entitlements"), icon], "Resources")
products_group = group("Products", list(products.values()))
root_group = group("HeartBarProject", source_groups + [resource_group,
                  ref("readme", "README.md", "net.daringfireball.markdown"),
                  ref("package", "Package.swift", "sourcecode.swift"), products_group])

project_config = configurations("Project", {
    "MACOSX_DEPLOYMENT_TARGET": "14.0", "SDKROOT": "macosx", "SWIFT_VERSION": "6.0",
    "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
    "SWIFT_STRICT_CONCURRENCY": "complete", "ARCHS": "$(ARCHS_STANDARD)",
    "CODE_SIGN_IDENTITY": "-", "CODE_SIGN_STYLE": "Manual",
}, {"ONLY_ACTIVE_ARCH": "YES", "DEBUG_INFORMATION_FORMAT": "dwarf",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone", "ENABLE_TESTABILITY": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)"},
   {"ONLY_ACTIVE_ARCH": "NO", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "SWIFT_OPTIMIZATION_LEVEL": "-O", "SWIFT_COMPILATION_MODE": "wholemodule"})

core_config = configurations("Core", {
    "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "com.heartbar.core",
    "DEFINES_MODULE": "YES", "GENERATE_INFOPLIST_FILE": "YES", "SKIP_INSTALL": "YES",
    "DYLIB_INSTALL_NAME_BASE": "@rpath", "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks",
    "VERSIONING_SYSTEM": "apple-generic", "CURRENT_PROJECT_VERSION": "1",
})
core_target = add("target:HeartBarCore", "PBXNativeTarget", name="HeartBarCore",
                  productName="HeartBarCore", productReference=products["HeartBarCore"],
                  productType="com.apple.product-type.framework", buildConfigurationList=core_config,
                  buildPhases=[source_phases["HeartBarCore"], phase("core:frameworks", "PBXFrameworksBuildPhase", [])],
                  buildRules=[], dependencies=[])


def dependency(name):
    proxy = add("proxy:" + name, "PBXContainerItemProxy", containerPortal=identifier("project"),
                proxyType=1, remoteGlobalIDString=core_target, remoteInfo="HeartBarCore")
    return add("dependency:" + name, "PBXTargetDependency", target=core_target, targetProxy=proxy)


app_config = configurations("App", {
    "PRODUCT_NAME": "HeartBar", "PRODUCT_BUNDLE_IDENTIFIER": "com.heartbar.app",
    "INFOPLIST_FILE": "Resources/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
    "CODE_SIGN_ENTITLEMENTS": "Resources/HeartBar.entitlements", "ENABLE_HARDENED_RUNTIME": "YES",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
})
app_target = add("target:HeartBar", "PBXNativeTarget", name="HeartBar", productName="HeartBar",
                 productReference=products["HeartBar"], productType="com.apple.product-type.application",
                 buildConfigurationList=app_config, buildRules=[], dependencies=[dependency("app")],
                 buildPhases=[source_phases["HeartBar"],
                              phase("app:frameworks", "PBXFrameworksBuildPhase", [build("app:core", products["HeartBarCore"])]),
                              phase("app:resources", "PBXResourcesBuildPhase", [build("app:icon", icon)]),
                              phase("app:embed", "PBXCopyFilesBuildPhase", [build("app:embedcore", products["HeartBarCore"],
                                    settings={"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]})],
                                    dstPath="", dstSubfolderSpec=10, name="Embed Frameworks")])
test_config = configurations("Tests", {
    "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "com.heartbar.tests",
    "GENERATE_INFOPLIST_FILE": "YES", "SKIP_INSTALL": "YES",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@loader_path/../Frameworks", "@loader_path/../../..", "$(BUILT_PRODUCTS_DIR)"],
})
test_target = add("target:HeartBarCoreTests", "PBXNativeTarget", name="HeartBarCoreTests",
                  productName="HeartBarCoreTests", productReference=products["HeartBarCoreTests"],
                  productType="com.apple.product-type.bundle.unit-test", buildConfigurationList=test_config,
                  buildRules=[], dependencies=[dependency("tests")],
                  buildPhases=[source_phases["HeartBarCoreTests"], phase("tests:frameworks", "PBXFrameworksBuildPhase",
                               [build("tests:core", products["HeartBarCore"])])])
project = add("project", "PBXProject", attributes={"LastUpgradeCheck": "1600", "BuildIndependentTargetsInParallel": "YES"},
              buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0", developmentRegion="en",
              hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=root_group,
              productRefGroup=products_group, projectDirPath="", projectRoot="", targets=[app_target, core_target, test_target])


def serialize(value, level=0):
    indent = "\t" * level
    if isinstance(value, dict):
        return "{\n" + "".join(f'{indent}\t{json.dumps(key)} = {serialize(item, level + 1)};\n' for key, item in value.items()) + indent + "}"
    if isinstance(value, list):
        return "(\n" + "".join(f"{indent}\t{serialize(item, level + 1)},\n" for item in value) + indent + ")"
    return json.dumps(value)


project_dir = ROOT / "HeartBar.xcodeproj"
project_dir.mkdir(exist_ok=True)
(project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)) + "\n")
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="HeartBar.app" BlueprintName="HeartBar" ReferencedContainer="container:HeartBar.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables>
      <TestableReference skipped="NO">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="HeartBarCoreTests.xctest" BlueprintName="HeartBarCoreTests" ReferencedContainer="container:HeartBar.xcodeproj"/>
      </TestableReference>
    </Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="HeartBar.app" BlueprintName="HeartBar" ReferencedContainer="container:HeartBar.xcodeproj"/>
    </BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="HeartBar.app" BlueprintName="HeartBar" ReferencedContainer="container:HeartBar.xcodeproj"/>
    </BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_dir = project_dir / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / "HeartBar.xcscheme").write_text(scheme)
print("Generated HeartBar.xcodeproj and shared HeartBar scheme.")
