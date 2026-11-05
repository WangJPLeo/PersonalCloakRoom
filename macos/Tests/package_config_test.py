import copy
import pathlib
import runpy

configure = runpy.run_path(str(pathlib.Path(__file__).resolve().parents[1] / 'scripts/package_config.py'))['configure_transport']
base = {'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True}}

for service in ['http://example.com:8000/tryon', 'http://127.0.0.1:8000']:
    result = configure(copy.deepcopy(base), {'ServiceURL': service, 'AllowHTTPForService': True})
    ats = result['NSAppTransportSecurity']
    assert ats.get('NSAllowsArbitraryLoads') is True
    assert all(k not in ats for k in ['NSAllowsLocalNetworking', 'NSAllowsArbitraryLoadsForMedia', 'NSAllowsArbitraryLoadsInWebContent'])

for service in ['https://example.com/tryon', 'http://127.0.0.1:8000']:
    result = configure(copy.deepcopy(base), {'ServiceURL': service, 'AllowHTTPForService': False})
    ats = result['NSAppTransportSecurity']
    assert not ats.get('NSAllowsArbitraryLoads')
    assert ats.get('NSAllowsLocalNetworking') is True
print('通过原生应用 ATS 打包配置回归检查。')
