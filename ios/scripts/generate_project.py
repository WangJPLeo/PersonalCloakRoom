"""Generate a dependency-free Xcode project for the app and image Share extension."""
import hashlib
import json
from pathlib import Path


def generate(root):
    objects = {}

    def identifier(label):
        return hashlib.sha256(label.encode()).hexdigest()[:24].upper()

    def add(label, isa, **values):
        key = identifier(label)
        objects[key] = {'isa': isa, **values}
        return key

    def file(path, kind):
        return add('file:' + path, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='<group>')

    shared = [str(path.relative_to(root)) for path in sorted((root / 'Shared').glob('*.swift'))]
    shared += ['../macos/Sources/CloakCapture/' + name for name in ['Service.swift', 'HistoryStore.swift', 'GarmentCatalog.swift']]
    app = [str(path.relative_to(root)) for path in sorted((root / 'App').glob('*.swift'))]
    extension = [str(path.relative_to(root)) for path in sorted((root / 'ShareExtension').glob('*.swift'))]
    refs = {path: file(path, 'sourcecode.swift') for path in shared + app + extension}
    config = file('Config.xcconfig', 'text.xcconfig')
    service = file('.generated/Config.local.plist', 'text.plist.xml')
    gallery = file('.generated/Gallery', 'folder')
    assets = file('.generated/Assets.xcassets', 'folder.assetcatalog')
    app_product = add('product:app', 'PBXFileReference', explicitFileType='wrapper.application', path='CloakRoom.app', sourceTree='BUILT_PRODUCTS_DIR', includeInIndex=0)
    share_product = add('product:share', 'PBXFileReference', explicitFileType='wrapper.app-extension', path='CloakRoomShare.appex', sourceTree='BUILT_PRODUCTS_DIR', includeInIndex=0)
    products = add('group:products', 'PBXGroup', children=[app_product, share_product], name='Products', sourceTree='<group>')
    main = add('group:main', 'PBXGroup', children=[*refs.values(), config, service, gallery, assets, products], sourceTree='<group>')

    def configurations(label, extra):
        configurations = []
        for name in ['Debug', 'Release']:
            settings = dict(extra)
            settings.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if name == 'Debug' else '-O',
                             'DEBUG_INFORMATION_FORMAT': 'dwarf' if name == 'Debug' else 'dwarf-with-dsym'})
            if name == 'Debug':
                settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
                settings['ENABLE_TESTABILITY'] = 'YES'
            configurations.append(add(label + ':' + name, 'XCBuildConfiguration', name=name, baseConfigurationReference=config, buildSettings=settings))
        return add(label + ':list', 'XCConfigurationList', buildConfigurations=configurations, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')

    project_config = configurations('project-config', {
        'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SWIFT_VERSION': '5.0',
        'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES', 'TARGETED_DEVICE_FAMILY': '1',
        'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST': 'NO',
    })
    project_key = identifier('project')
    app_key, share_key = identifier('target:app'), identifier('target:share')
    proxy = add('proxy:share', 'PBXContainerItemProxy', containerPortal=project_key, proxyType=1, remoteGlobalIDString=share_key, remoteInfo='CloakRoomShare')
    dependency = add('dependency:share', 'PBXTargetDependency', target=share_key, targetProxy=proxy)

    def build_file(target, key, settings=None):
        values = {'fileRef': key}
        if settings:
            values['settings'] = settings
        return add('build:' + target + ':' + key, 'PBXBuildFile', **values)

    for target, name, sources, resource_refs, product, bundle, info, is_extension in [
        ('app', 'CloakRoom', shared + app, [service, gallery, assets], app_product, '$(APP_BUNDLE_ID)', '.generated/AppInfo.plist', False),
        ('share', 'CloakRoomShare', shared + extension, [service], share_product, '$(APP_BUNDLE_ID).share', '.generated/ShareInfo.plist', True),
    ]:
        phases = [
            add('sources:' + target, 'PBXSourcesBuildPhase', buildActionMask=2147483647,
                files=[build_file(target, refs[path]) for path in sources], runOnlyForDeploymentPostprocessing=0),
            add('frameworks:' + target, 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0),
            add('resources:' + target, 'PBXResourcesBuildPhase', buildActionMask=2147483647,
                files=[build_file(target, ref) for ref in resource_refs], runOnlyForDeploymentPostprocessing=0),
        ]
        if not is_extension:
            phases.append(add('embed-share', 'PBXCopyFilesBuildPhase', buildActionMask=2147483647,
                              files=[build_file('embed', share_product, {'ATTRIBUTES': ['RemoveHeadersOnCopy']})],
                              dstPath='', dstSubfolderSpec=13, name='Embed App Extensions', runOnlyForDeploymentPostprocessing=0))
        settings = {
            'PRODUCT_NAME': '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER': bundle,
            'GENERATE_INFOPLIST_FILE': 'NO', 'INFOPLIST_FILE': info, 'CODE_SIGN_ENTITLEMENTS': 'Shared/App.entitlements',
            'APPLICATION_EXTENSION_API_ONLY': 'YES' if is_extension else 'NO',
            'SKIP_INSTALL': 'YES' if is_extension else 'NO',
            'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
        }
        if not is_extension:
            settings.update({'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES': 'YES'})
        add('target:' + target, 'PBXNativeTarget', name=name, productName=name, productReference=product,
            productType='com.apple.product-type.app-extension' if is_extension else 'com.apple.product-type.application',
            buildConfigurationList=configurations('config:' + target, settings), buildPhases=phases,
            buildRules=[], dependencies=[] if is_extension else [dependency])
    add('project', 'PBXProject', attributes={
        'LastUpgradeCheck': '1600', 'LastSwiftUpdateCheck': '1600',
        'TargetAttributes': {key: {'CreatedOnToolsVersion': '16.0', 'SystemCapabilities': {'com.apple.ApplicationGroups.iOS': {'enabled': 1}}} for key in [app_key, share_key]},
    }, buildConfigurationList=project_config, compatibilityVersion='Xcode 14.0', developmentRegion='zh-Hans',
        knownRegions=['zh-Hans', 'en', 'Base'], mainGroup=main, productRefGroup=products,
        projectDirPath='', projectRoot='', targets=[app_key, share_key])

    def serialize(value, indent=0):
        tab = '\t' * indent
        if isinstance(value, dict):
            return '{\n' + ''.join(tab + '\t' + json.dumps(str(k), ensure_ascii=False) + ' = ' + serialize(v, indent + 1) + ';\n' for k, v in value.items()) + tab + '}'
        if isinstance(value, list):
            return '(\n' + ''.join(tab + '\t' + serialize(v, indent + 1) + ',\n' for v in value) + tab + ')'
        return str(value) if isinstance(value, int) else json.dumps(value, ensure_ascii=False)

    project = root / 'CloakRoom.xcodeproj'
    project.mkdir(exist_ok=True)
    content = {'archiveVersion': 1, 'classes': {}, 'objectVersion': 56, 'objects': objects, 'rootObject': project_key}
    (project / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + serialize(content) + '\n', encoding='utf-8')
    schemes = project / 'xcshareddata/xcschemes'
    schemes.mkdir(parents=True, exist_ok=True)
    (schemes / 'CloakRoom.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_key}" BuildableName="CloakRoom.app" BlueprintName="CloakRoom" ReferencedContainer="container:CloakRoom.xcodeproj"/>
    </BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_key}" BuildableName="CloakRoom.app" BlueprintName="CloakRoom" ReferencedContainer="container:CloakRoom.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''', encoding='utf-8')
    return objects


if __name__ == '__main__':
    generate(Path(__file__).resolve().parents[1])
