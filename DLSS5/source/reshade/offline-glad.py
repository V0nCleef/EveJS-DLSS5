# Build-only driver: pinned Khronos file URLs use the solution's local XML;
# all remote support resources resolve to pinned GLAD package data, no network.
import os
import runpy
import sys
from urllib.parse import urlparse
glad_root = os.path.realpath(sys.argv[1])
sys.path.insert(0, glad_root)
sys.argv = ['glad'] + sys.argv[2:]
import glad.files
original = glad.files.StaticFileOpener
class PinnedFileOpener(original):
    def urlopen(self, url, data=None, *args, **kwargs):
        parsed = urlparse(url)
        if parsed.scheme == 'file':
            target = os.path.realpath(os.path.join(glad_root, parsed.path))
            if target not in [os.path.join(glad_root, name) for name in ('gl.xml', 'wgl.xml', 'vk.xml')]:
                raise RuntimeError('Unexpected local XML request: ' + url)
            if data is not None:
                raise RuntimeError('Unexpected local XML request payload')
            return open(target, 'rb')
        return super(PinnedFileOpener, self).urlopen(url, data, *args, **kwargs)
glad.files.StaticFileOpener = PinnedFileOpener
runpy.run_module('glad', run_name='__main__')
