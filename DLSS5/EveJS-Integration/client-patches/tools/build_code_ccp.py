import sys
import marshal
import zlib
import binascii
import _sha256
import _struct
import _codecs
# Authored helper sources are authenticated and evaluated in private scopes.
# Never import from the package directory, sys.path, or a cached .pyc file.
sys.dont_write_bytecode = True


def fail(message):
    raise RuntimeError(message)


def sha256(data):
    return _sha256.sha256(data).hexdigest().upper()


def u16(data, offset):
    return _struct.unpack('<H', str(data[offset:offset + 2]))[0]


def u32(data, offset):
    return _struct.unpack('<L', str(data[offset:offset + 4]))[0]


def put_u32(data, offset, value):
    data[offset:offset + 4] = _struct.pack('<L', value)


def utf8_path(value):
    path = _codecs.utf_8_decode(value, 'strict', True)[0]
    # Python 2's CRT otherwise applies MAX_PATH even though the surrounding
    # PowerShell/.NET manager accepts the user's legitimate deep EveJS path.
    if path.startswith(u'\\\\?\\'):
        return path
    if path.startswith(u'\\\\'):
        return u'\\\\?\\UNC\\' + path[2:]
    if len(path) >= 3 and path[1] == u':' and path[2] in (u'\\', u'/'):
        return u'\\\\?\\' + path.replace(u'/', u'\\')
    fail('filesystem arguments must be absolute Windows paths')


def load_local_reconstruction(template_path, class_name, method_name):
    patches_path = utf8_path(sys.argv[0]).rsplit(u'\\', 2)[0]
    records = (
        ('local-source', u'tools\\local_source.py', 21812, 'BD070ED7047613C14FD8C961A7B2447921AB9F2ED0C769B98D555ECDBD579A99'),
        ('reconstruct', u'tools\\reconstruct.py', 6440, '585E32DD92A636F90C76CCD772767D0ECEAB34F2DBB6812D7B8D68A127223EFE'),
        ('graphics-template', u'templates\\systemmenu_apply_graphics.py.in', 17954, '240B379994A42374C41F7875A8783D4FA6237194833C37F54C3C9C1F02B70F38'),
        ('startup-template', u'templates\\device_create.py.in', 11703, '4A00A98FC65997E7996F665BA5DBEC85923DDA16CBD84C458F26F0663FC709D7'),
    )
    verified = {}
    paths = {}
    # Authenticate EVERY input before executing either helper; retain the
    # verified bytes in memory so a later file replacement cannot be loaded.
    for name, relative, size, expected_hash in records:
        path = patches_path + u'\\' + relative
        source = open(path, 'rb').read()
        if len(source) != size or sha256(source) != expected_hash:
            fail('local source input identity mismatch: %s' % name)
        verified[name] = source
        paths[name] = path
    template_name = 'graphics-template' if class_name == 'SystemMenu' else 'startup-template'
    if template_path.lower() != paths[template_name].lower():
        fail('template is not the exact local source package target')
    emitter_scope = {'__builtins__': __builtins__, '__name__': '_evejs_verified_emitter'}
    eval(compile(verified['local-source'], '<evejs-verified-local-source>', 'exec'), emitter_scope)
    reconstruction_scope = {
        '__builtins__': __builtins__, '__name__': '_evejs_verified_reconstruct',
        'derive_method': emitter_scope['derive_method'],
        'render_lines': emitter_scope['render_lines'],
    }
    eval(compile(verified['reconstruct'], '<evejs-verified-reconstruct>', 'exec'), reconstruction_scope)
    return reconstruction_scope['reconstruct'], reconstruction_scope['ORIGINAL_PYC_HASHES'], verified[template_name]


def is_code(value):
    return hasattr(value, 'co_code') and hasattr(value, 'co_consts') and hasattr(value, 'co_name')


def direct_child(code, name):
    matches = [value for value in code.co_consts if is_code(value) and value.co_name == name]
    if len(matches) != 1:
        fail('expected exactly one direct child named %s, found %d' % (name, len(matches)))
    return matches[0]


def clone_with_consts(code, consts):
    return type(code)(code.co_argcount,
                      code.co_nlocals,
                      code.co_stacksize,
                      code.co_flags,
                      code.co_code,
                      tuple(consts),
                      code.co_names,
                      code.co_varnames,
                      code.co_filename,
                      code.co_name,
                      code.co_firstlineno,
                      code.co_lnotab,
                      code.co_freevars,
                      code.co_cellvars)


def replace_direct_child(code, name, replacement):
    replacements = 0
    consts = []
    for value in code.co_consts:
        if is_code(value) and value.co_name == name:
            consts.append(replacement)
            replacements += 1
        else:
            consts.append(value)
    if replacements != 1:
        fail('expected to replace exactly one direct child named %s, replaced %d' % (name, replacements))
    return clone_with_consts(code, consts)


if len(sys.argv) not in (8, 10):
    fail('usage: SCRIPT ARCHIVE STUB ENTRY EMBEDDED_FILENAME OUTPUT EXPECTED_INPUT_SHA256 EXPECTED_OUTPUT_SHA256 [CLASS METHOD]')

archive_path = utf8_path(sys.argv[1])
stub_path = utf8_path(sys.argv[2])
entry_name = sys.argv[3]
embedded_filename = sys.argv[4]
output_path = utf8_path(sys.argv[5])
expected_input_hash = sys.argv[6].upper()
expected_output_hash = sys.argv[7].upper()
class_name, method_name = ('SystemMenu', 'ApplyGraphicsSettings') if len(sys.argv) == 8 else (sys.argv[8], sys.argv[9])
allowed_targets = {
    ('SystemMenu', 'ApplyGraphicsSettings'): 'eve/client/script/ui/shared/systemMenu/systemmenu.pyj',
    ('DeviceMgr', 'CreateDevice'): 'carbonui/services/device.pyj',
}
if allowed_targets.get((class_name, method_name)) != entry_name:
    fail('unsupported class/method/archive entry combination')

archive = open(archive_path, 'rb').read()
if sha256(archive) != expected_input_hash:
    fail('unsupported input archive SHA-256: %s' % sha256(archive))

eocd_offset = len(archive) - 22
if eocd_offset < 0 or archive[eocd_offset:eocd_offset + 4] != 'PK\x05\x06':
    fail('expected an un-commented classic ZIP end record')

disk_number = u16(archive, eocd_offset + 4)
central_disk = u16(archive, eocd_offset + 6)
disk_entries = u16(archive, eocd_offset + 8)
total_entries = u16(archive, eocd_offset + 10)
central_size = u32(archive, eocd_offset + 12)
central_offset = u32(archive, eocd_offset + 16)
comment_length = u16(archive, eocd_offset + 20)
if disk_number != 0 or central_disk != 0 or disk_entries != total_entries or comment_length != 0:
    fail('unsupported split, multi-disk, or commented ZIP archive')
if central_offset + central_size != eocd_offset:
    fail('central directory boundaries do not match the end record')

target_central_offset = None
target_local_offset = None
target_compressed_size = None
central_cursor = central_offset
for index in range(total_entries):
    if archive[central_cursor:central_cursor + 4] != 'PK\x01\x02':
        fail('invalid central directory record %d' % index)
    flags = u16(archive, central_cursor + 8)
    method = u16(archive, central_cursor + 10)
    compressed_size = u32(archive, central_cursor + 20)
    filename_length = u16(archive, central_cursor + 28)
    extra_length = u16(archive, central_cursor + 30)
    entry_comment_length = u16(archive, central_cursor + 32)
    disk_start = u16(archive, central_cursor + 34)
    local_offset = u32(archive, central_cursor + 42)
    filename = archive[central_cursor + 46:central_cursor + 46 + filename_length]
    if filename == entry_name:
        if target_central_offset is not None:
            fail('target ZIP entry appears more than once')
        if flags != 0 or method != 0 or extra_length != 0 or entry_comment_length != 0 or disk_start != 0:
            fail('target ZIP entry is not the expected simple stored entry')
        target_central_offset = central_cursor
        target_local_offset = local_offset
        target_compressed_size = compressed_size
    central_cursor += 46 + filename_length + extra_length + entry_comment_length
if central_cursor != eocd_offset:
    fail('central directory record count or length mismatch')
if target_central_offset is None:
    fail('target ZIP entry was not found')

local_cursor = target_local_offset
if archive[local_cursor:local_cursor + 4] != 'PK\x03\x04':
    fail('target local ZIP header is invalid')
local_flags = u16(archive, local_cursor + 6)
local_method = u16(archive, local_cursor + 8)
local_compressed_size = u32(archive, local_cursor + 18)
local_filename_length = u16(archive, local_cursor + 26)
local_extra_length = u16(archive, local_cursor + 28)
local_filename = archive[local_cursor + 30:local_cursor + 30 + local_filename_length]
if local_flags != 0 or local_method != 0 or local_extra_length != 0 or local_filename != entry_name:
    fail('target local ZIP header is not the expected simple stored entry')
if local_compressed_size != target_compressed_size:
    fail('target local and central compressed sizes differ')

payload_offset = local_cursor + 30 + local_filename_length + local_extra_length
original_pyj = archive[payload_offset:payload_offset + target_compressed_size]
original_pyc = zlib.decompress(original_pyj)
if len(original_pyc) < 9:
    fail('target PYC is truncated')

original_module = marshal.loads(original_pyc[8:])
original_class = direct_child(original_module, class_name)
original_method = direct_child(original_class, method_name)
# Only the authenticated authored helpers execute. Original and reconstructed
# client modules/methods are parsed/compiled as data, never imported or called.
reconstruct, ORIGINAL_PYC_HASHES, template_source = load_local_reconstruction(stub_path, class_name, method_name)
if sha256(original_pyc) != ORIGINAL_PYC_HASHES[(class_name, method_name)]:
    fail('original target PYC identity mismatch')
stub_source = reconstruct(original_method, template_source, class_name, method_name)
stub_module = compile(stub_source, embedded_filename, 'exec')
stub_class = direct_child(stub_module, class_name)
replacement_method = direct_child(stub_class, method_name)
if original_method.co_argcount != replacement_method.co_argcount:
    fail('replacement method argument count changed')

patched_class = replace_direct_child(original_class, method_name, replacement_method)
patched_module = replace_direct_child(original_module, class_name, patched_class)
patched_pyc = original_pyc[:8] + marshal.dumps(patched_module, 2)
patched_pyj = zlib.compress(patched_pyc, 9)
patched_crc = binascii.crc32(patched_pyj) & 0xffffffff
delta = len(patched_pyj) - len(original_pyj)

output = bytearray(archive[:payload_offset] + patched_pyj + archive[payload_offset + len(original_pyj):])
put_u32(output, local_cursor + 14, patched_crc)
put_u32(output, local_cursor + 18, len(patched_pyj))
put_u32(output, local_cursor + 22, len(patched_pyj))

new_central_offset = central_offset + delta
central_cursor = new_central_offset
target_count = 0
for index in range(total_entries):
    if str(output[central_cursor:central_cursor + 4]) != 'PK\x01\x02':
        fail('invalid output central directory record %d' % index)
    filename_length = u16(output, central_cursor + 28)
    extra_length = u16(output, central_cursor + 30)
    entry_comment_length = u16(output, central_cursor + 32)
    filename = str(output[central_cursor + 46:central_cursor + 46 + filename_length])
    local_offset = u32(output, central_cursor + 42)
    if filename == entry_name:
        target_count += 1
        put_u32(output, central_cursor + 16, patched_crc)
        put_u32(output, central_cursor + 20, len(patched_pyj))
        put_u32(output, central_cursor + 24, len(patched_pyj))
    if local_offset > target_local_offset:
        put_u32(output, central_cursor + 42, local_offset + delta)
    central_cursor += 46 + filename_length + extra_length + entry_comment_length
if target_count != 1:
    fail('output target ZIP entry count changed')

new_eocd_offset = eocd_offset + delta
put_u32(output, new_eocd_offset + 16, new_central_offset)
output_bytes = str(output)
if sha256(output_bytes) != expected_output_hash:
    fail('generated output SHA-256 mismatch: %s' % sha256(output_bytes))
open(output_path, 'wb').write(output_bytes)
print('generated %d-byte V12 development code.ccp (%s.%s) with SHA-256 %s' % (len(output_bytes), class_name, method_name, sha256(output_bytes)))
