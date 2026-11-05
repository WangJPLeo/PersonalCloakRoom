"""Write the native transport policy from the explicitly approved local service."""
import pathlib
import plistlib
import sys
import urllib.parse


def configure_transport(info, config):
    address = urllib.parse.urlsplit(config.get('ServiceURL', ''))
    transport = info.setdefault('NSAppTransportSecurity', {})
    if config.get('AllowHTTPForService') is True and address.scheme == 'http' and address.hostname:
        # On current macOS these finer-grained keys override NSAllowsArbitraryLoads.
        # IP-based HTTP needs that exception; ServicePolicy still enforces the exact origin.
        for key in ['NSAllowsLocalNetworking', 'NSAllowsArbitraryLoadsForMedia', 'NSAllowsArbitraryLoadsInWebContent']:
            transport.pop(key, None)
        transport['NSAllowsArbitraryLoads'] = True
    else:
        transport.pop('NSAllowsArbitraryLoads', None)
        transport['NSAllowsLocalNetworking'] = True
    return info


if __name__ == '__main__':
    app = pathlib.Path(sys.argv[1])
    config = plistlib.loads((app / 'Contents/Resources/Config.local.plist').read_bytes())
    info_path = app / 'Contents/Info.plist'
    info = configure_transport(plistlib.loads(info_path.read_bytes()), config)
    info_path.write_bytes(plistlib.dumps(info))
