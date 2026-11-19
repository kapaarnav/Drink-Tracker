#!/usr/bin/env python3
"""Generate the dependency-free Xcode project. Run after changing target membership."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parents[1]
def uid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
objects = {}
def obj(name, text):
    key = uid(name); objects[key] = text; return key
shared = ['Shared/TrackingActivity.swift', 'Shared/AdjustCountIntent.swift', 'Shared/TallyView.swift']
ui_files = ['UITests/DrinkTrackerUITests.swift']
app_files = sorted(str(p.relative_to(root)) for p in (root / 'App').glob('*.swift')) + shared
widget_files = ['Widget/DrinkTrackerWidget.swift'] + shared
refs = {}
for path in sorted(set(app_files + widget_files + ui_files)):
    refs[path] = obj(path, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = SOURCE_ROOT; }}')
app_product = obj('app-product', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = DrinkTracker.app; sourceTree = BUILT_PRODUCTS_DIR; }')
widget_product = obj('widget-product', '{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; path = DrinkTrackerWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; }')
package = obj('package', '{isa = XCLocalSwiftPackageReference; relativePath = .; }')

def configs(name, settings):
    ids = []
    for mode in ['Debug', 'Release']:
        mode_settings = dict(settings)
        mode_settings.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode == 'Debug' else '-O',
                              'ONLY_ACTIVE_ARCH': 'YES' if mode == 'Debug' else 'NO',
                              'DEBUG_INFORMATION_FORMAT': 'dwarf' if mode == 'Debug' else 'dwarf-with-dsym'})
        body = ' '.join(f'{k} = "{v}";' for k,v in mode_settings.items())
        ids.append(obj(name+mode, f'{{isa = XCBuildConfiguration; buildSettings = {{{body}}}; name = {mode}; }}'))
    return obj(name+'configs', '{isa = XCConfigurationList; buildConfigurations = (' + ','.join(ids) + ',); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')
base = {'IPHONEOS_DEPLOYMENT_TARGET': '26.0', 'SDKROOT': 'iphoneos', 'SWIFT_VERSION': '6.0',
        'TARGETED_DEVICE_FAMILY': '1', 'CODE_SIGN_STYLE': 'Automatic', 'CURRENT_PROJECT_VERSION': '1',
        'MARKETING_VERSION': '1.0', 'GENERATE_INFOPLIST_FILE': 'YES',
        'SWIFT_STRICT_CONCURRENCY': 'complete', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES',
        'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST': 'NO',
        'PRODUCT_NAME': '$(TARGET_NAME)', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'}
resources_ref = obj('assets', '{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = App/Assets.xcassets; sourceTree = SOURCE_ROOT; }')
refs['App/Assets.xcassets'] = resources_ref
asset_build = obj('assets-build', '{isa = PBXBuildFile; fileRef = ' + resources_ref + '; }')
resources = obj('resources', '{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (' + asset_build + ',); runOnlyForDeploymentPostprocessing = 0; }')
project_configs = configs('project', {'CLANG_ENABLE_MODULES': 'YES', 'SWIFT_VERSION': '6.0', 'IPHONEOS_DEPLOYMENT_TARGET': '26.0'})
proxy = obj('proxy', '{isa = PBXContainerItemProxy; containerPortal = ' + uid('project') + '; proxyType = 1; remoteGlobalIDString = ' + uid('widget-target') + '; remoteInfo = DrinkTrackerWidget; }')
dep = obj('dependency', '{isa = PBXTargetDependency; target = ' + uid('widget-target') + '; targetProxy = ' + proxy + '; }')
embed_build = obj('embed-build', '{isa = PBXBuildFile; fileRef = ' + widget_product + '; settings = {ATTRIBUTES = (RemoveHeadersOnCopy,); }; }')
embed = obj('embed', '{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = (' + embed_build + ',); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0; }')
for name, files, product, kind in [('app', app_files, app_product, 'com.apple.product-type.application'), ('widget', widget_files, widget_product, 'com.apple.product-type.app-extension')]:
    target_name = 'DrinkTracker' if name == 'app' else 'DrinkTrackerWidget'
    builds = [obj(name+p, '{isa = PBXBuildFile; fileRef = ' + refs[p] + '; }') for p in files]
    sources = obj(name+'sources', '{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(builds) + ',); runOnlyForDeploymentPostprocessing = 0; }')
    product_dep = obj(name+'core-dep', '{isa = XCSwiftPackageProductDependency; package = ' + package + '; productName = DrinkTrackerCore; }')
    core_build = obj(name+'core-build', '{isa = PBXBuildFile; productRef = ' + product_dep + '; }')
    frameworks = obj(name+'frameworks', '{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (' + core_build + ',); runOnlyForDeploymentPostprocessing = 0; }')
    settings = dict(base)
    settings.update({'PRODUCT_BUNDLE_IDENTIFIER': 'com.aarnavkapoor.DrinkTracker' + ('.Widget' if name == 'widget' else ''),
                     'INFOPLIST_FILE': 'Config/Widget-Info.plist' if name == 'widget' else 'Config/App-Info.plist'})
    if name == 'widget': settings.update({'APPLICATION_EXTENSION_API_ONLY': 'YES', 'SKIP_INSTALL': 'YES'})
    else: settings.update({'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited) DRINK_TRACKER_APP',
                           'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES',
                           'INFOPLIST_KEY_UISupportedInterfaceOrientations': 'UIInterfaceOrientationPortrait'})
    config = configs(name, settings)
    phases = sources + ',' + frameworks + (','+embed+','+resources if name == 'app' else '')
    obj(name+'-target', '{isa = PBXNativeTarget; buildConfigurationList = ' + config + '; buildPhases = (' + phases + ',); buildRules = (); dependencies = (' + (dep+',' if name == 'app' else '') + '); name = ' + target_name + '; packageProductDependencies = (' + product_dep + ',); productName = ' + target_name + '; productReference = ' + product + '; productType = "' + kind + '"; }')
ui_product = obj('ui-product', '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = DrinkTrackerUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }')
ui_source_build = obj('ui-build', '{isa = PBXBuildFile; fileRef = ' + refs[ui_files[0]] + '; }')
ui_sources = obj('ui-sources', '{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ui_source_build + ',); runOnlyForDeploymentPostprocessing = 0; }')
ui_settings = dict(base)
ui_settings.update({'PRODUCT_BUNDLE_IDENTIFIER':'com.aarnavkapoor.DrinkTracker.UITests','TEST_TARGET_NAME':'DrinkTracker'})
ui_configs = configs('ui', ui_settings)
ui_dependency = obj('ui-dependency', '{isa = PBXTargetDependency; target = ' + uid('app-target') + '; }')
obj('ui-target', '{isa = PBXNativeTarget; buildConfigurationList = ' + ui_configs + '; buildPhases = (' + ui_sources + ',); buildRules = (); dependencies = (' + ui_dependency + ',); name = DrinkTrackerUITests; productName = DrinkTrackerUITests; productReference = ' + ui_product + '; productType = "com.apple.product-type.bundle.ui-testing"; }')
products = obj('products', '{isa = PBXGroup; children = (' + app_product+','+widget_product+','+ui_product + ',); name = Products; sourceTree = "<group>"; }')
main = obj('main-group', '{isa = PBXGroup; children = (' + ','.join(refs.values()) + ',' + products + ',); sourceTree = "<group>"; }')
obj('project', '{isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; }; buildConfigurationList = ' + project_configs + '; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = ' + main + '; packageReferences = (' + package + ',); productRefGroup = ' + products + '; projectDirPath = ""; projectRoot = ""; targets = (' + uid('app-target') + ',' + uid('widget-target') + ',' + uid('ui-target') + ',); }')
text = '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n'
text += '\n'.join(k + ' = ' + v + ';' for k,v in objects.items())
text += '\n}; rootObject = ' + uid('project') + '; }\n'
(root/'DrinkTracker.xcodeproj/project.pbxproj').write_text(text)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('app-target')}" BuildableName="DrinkTracker.app" BlueprintName="DrinkTracker" ReferencedContainer="container:DrinkTracker.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('ui-target')}" BuildableName="DrinkTrackerUITests.xctest" BlueprintName="DrinkTrackerUITests" ReferencedContainer="container:DrinkTracker.xcodeproj"/></TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('app-target')}" BuildableName="DrinkTracker.app" BlueprintName="DrinkTracker" ReferencedContainer="container:DrinkTracker.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
(root/'DrinkTracker.xcodeproj/xcshareddata/xcschemes/DrinkTracker.xcscheme').write_text(scheme)
print('Generated DrinkTracker.xcodeproj')
