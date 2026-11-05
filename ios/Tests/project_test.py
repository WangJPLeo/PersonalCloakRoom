"""Check target wiring and privacy-critical shared configuration without an iOS SDK."""
import json
import plistlib
from pathlib import Path
import struct
import subprocess
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class ProjectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        project = subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(ROOT / 'CloakRoom.xcodeproj/project.pbxproj')])
        cls.project = json.loads(project)
        cls.objects = cls.project['objects']
        cls.targets = {value['name']: value for value in cls.objects.values() if value['isa'] == 'PBXNativeTarget'}

    def files(self, target, phase):
        result = []
        for key in target['buildPhases']:
            value = self.objects[key]
            if value['isa'] == phase:
                result += [self.objects[self.objects[item]['fileRef']]['path'] for item in value['files']]
        return result

    def test_shared_sources_and_embed(self):
        self.assertEqual(set(self.targets), {'CloakRoom', 'CloakRoomShare'})
        for name, target in self.targets.items():
            files = self.files(target, 'PBXSourcesBuildPhase')
            expected = list((ROOT / 'Shared').glob('*.swift'))
            expected += list((ROOT / ('App' if name == 'CloakRoom' else 'ShareExtension')).glob('*.swift'))
            for path in expected:
                self.assertIn(str(path.relative_to(ROOT)), files)
            for file in files:
                self.assertTrue((ROOT / file).is_file())
            self.assertIn('../macos/Sources/CloakCapture/Service.swift', files)
            self.assertIn('../macos/Sources/CloakCapture/HistoryStore.swift', files)
            resources = self.files(target, 'PBXResourcesBuildPhase')
            self.assertIn('.generated/Config.local.plist', resources)
            if name == 'CloakRoomShare':
                self.assertNotIn('.generated/Gallery', resources)
            else:
                self.assertIn('.generated/Gallery', resources)
        app = self.targets['CloakRoom']
        self.assertEqual(self.files(app, 'PBXCopyFilesBuildPhase'), ['CloakRoomShare.appex'])
        self.assertEqual(len(app['dependencies']), 1)
        dependency = self.objects[app['dependencies'][0]]
        self.assertEqual(self.objects[dependency['target']]['name'], 'CloakRoomShare')

    def test_share_activation_and_data_group(self):
        entitlement = plistlib.loads((ROOT / 'Shared/App.entitlements').read_bytes())
        self.assertEqual(entitlement['com.apple.security.application-groups'], ['$(APP_GROUP_ID)'])
        for folder in ['App', 'ShareExtension']:
            info = plistlib.loads((ROOT / folder / 'Info.plist').read_bytes())
            self.assertEqual(info['AppGroupIdentifier'], '$(APP_GROUP_ID)')
            self.assertIn('NSPhotoLibraryAddUsageDescription', info)
        share = plistlib.loads((ROOT / 'ShareExtension/Info.plist').read_bytes())['NSExtension']
        self.assertEqual(share['NSExtensionPointIdentifier'], 'com.apple.share-services')
        self.assertEqual(share['NSExtensionAttributes']['NSExtensionActivationRule'], {'NSExtensionActivationSupportsImageWithMaxCount': 1})
        for target in self.targets.values():
            configurations = self.objects[target['buildConfigurationList']]['buildConfigurations']
            for configuration in configurations:
                settings = self.objects[configuration]['buildSettings']
                self.assertEqual(settings['CODE_SIGN_ENTITLEMENTS'], 'Shared/App.entitlements')
                self.assertTrue((ROOT / settings['INFOPLIST_FILE']).is_file())

    def test_transport_and_resource_separation(self):
        config = plistlib.loads((ROOT / '.generated/Config.local.plist').read_bytes())
        self.assertEqual(set(config), {'ServiceURL', 'AllowHTTPForService'})
        app = plistlib.loads((ROOT / '.generated/AppInfo.plist').read_bytes())
        share = plistlib.loads((ROOT / '.generated/ShareInfo.plist').read_bytes())
        self.assertEqual(app['NSAppTransportSecurity'], share['NSAppTransportSecurity'])
        ats = app['NSAppTransportSecurity']
        if config['ServiceURL'].startswith('http://') and config['AllowHTTPForService']:
            self.assertTrue(ats.get('NSAllowsArbitraryLoads'))
            self.assertNotIn('NSAllowsLocalNetworking', ats)
        entries = json.loads((ROOT / '.generated/Gallery/catalog.json').read_text())
        self.assertGreater(len(entries), 0)
        for entry in entries:
            for key in ['image', 'thumbnail']:
                self.assertTrue((ROOT / '.generated/Gallery' / entry[key]).is_file())

    def test_icon_and_scheme(self):
        icon = (ROOT / '.generated/Assets.xcassets/AppIcon.appiconset/icon1024.png').read_bytes()
        self.assertEqual(icon[:8], b'\x89PNG\r\n\x1a\n')
        self.assertEqual(struct.unpack('>II', icon[16:24]), (1024, 1024))
        self.assertEqual(icon[25], 2, 'iOS app icon must be RGB without an alpha channel')
        scheme = ET.parse(ROOT / 'CloakRoom.xcodeproj/xcshareddata/xcschemes/CloakRoom.xcscheme')
        build = scheme.find('.//BuildActionEntry/BuildableReference')
        self.assertIsNotNone(build)
        self.assertEqual(self.objects[build.attrib['BlueprintIdentifier']]['name'], 'CloakRoom')


if __name__ == '__main__':
    unittest.main()
