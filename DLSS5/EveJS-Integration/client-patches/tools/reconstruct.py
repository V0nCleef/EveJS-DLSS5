"""Combine authored line-slot templates with validated local code-object data.

No original client method source, identifiers or literals are stored here.
Selectors describe the exact supported instruction regions, not source bodies.
This module never executes a client method or imports a client module.
"""
# The authenticated builder supplies derive_method/render_lines in a private
# namespace. Never import adjacent files or cached Python modules here.


ORIGINAL_PYC_HASHES = {
    ('SystemMenu', 'ApplyGraphicsSettings'): '15DFB23A19F1972D4B2802A86116E9FB53B3850672679461456F1AC00FE33625',
    ('DeviceMgr', 'CreateDevice'): '924F5050A7476845B8DBBB4CC96032A14C7773FF18373D707B605A75821A6F61',
}


def require(condition, reason):
    if not condition:
        raise ValueError('local reconstruction rejected: ' + reason)


def select(node, kind, start=None, end=None):
    require(node['kind'] == kind, 'unexpected node kind')
    if start is not None:
        require(node['start'] == start, 'unexpected instruction region start')
    if end is not None:
        require(node['end'] == end, 'unexpected instruction region end')
    return node


def text_lines(nodes, depth):
    return [line['text'] for line in render_lines(nodes, depth)]


def substitute_child(expression, child, authored_name):
    """Substitute one selected local operand, without prewritten client text."""
    require(expression['text'].count(child['text']) == 1, 'ambiguous expression operand')
    return expression['text'].replace(child['text'], authored_name)


def set_block(lines, start, count, name, replacement):
    marker = '@LOCAL:' + name + '@'
    require(lines[start - 1].strip() == marker, 'missing or moved block marker ' + name)
    require(len(replacement) == count, 'source line count changed for ' + name)
    require(all(not line for line in lines[start:start + count - 1]), 'block slot is not empty')
    lines[start - 1:start + count - 1] = replacement


def graphics(nodes, lines):
    require(len(nodes) == 15, 'graphics top-level node count')
    window = select(nodes[0], 'if', 0, 13)
    select(nodes[1], 'assign', 13)
    select(nodes[2], 'assign', end=37)
    select(nodes[3], 'assign', 37)
    select(nodes[10], 'if', end=418)
    change = select(nodes[11], 'if', 418, 625)
    select(nodes[12], 'if', 625, 662)
    select(nodes[13], 'expr', 662, 672)
    select(nodes[14], 'return', 672, 676)
    require(len(change['body']) == 2, 'upscaler body shape')
    setter = select(change['body'][0], 'expr', 463, 521)['expression']
    select(setter, 'call')
    require(len(setter['args']) == 3 and not setter['keywords'] and setter['star'] is None,
            'upscaler call shape')
    nested = select(change['body'][1], 'if', 521)
    require(len(nested['body']) == 2, 'nested upscaler shape')
    wait = select(nested['body'][0], 'while')
    panel = select(nested['body'][1], 'expr')
    ready = select(wait['condition'], 'or')
    require(len(ready['values']) == 2, 'readiness terms')
    compare = select(ready['values'][0], 'compare')
    require(compare['operator'] == '!=', 'readiness comparison')
    select(ready['values'][1], 'not')
    query = select(compare['left'], 'subscript')
    select(query['owner'], 'call')
    query_receiver = select(query['owner']['function'], 'attribute')['owner']
    require(compare['right']['text'] == setter['args'][0]['text'], 'readiness target mismatch')

    set_block(lines, 176, 2, 'graphics_setup', text_lines(nodes[1:3], 3))
    set_block(lines, 221, 19, 'graphics_commit', text_lines(nodes[3:11], 3))
    # Retain the local panel condition and call; the local unbounded wait is
    # replaced by the existing authored bounded helper at its original slot.
    panel_node = dict(nested)
    panel_node['body'] = [panel]
    set_block(lines, 247, 2, 'panel_refresh', text_lines([panel_node], 4))
    set_block(lines, 249, 2, 'graphics_event', text_lines([nodes[12]], 3))
    set_block(lines, 255, 1, 'crash_key', text_lines([nodes[13]], 3))
    set_block(lines, 258, 2, 'window_guard', text_lines([window], 2))
    dev_local = nodes[2]['target']['text']
    require(nodes[2]['value']['text'] == query_receiver['text'], 'device alias mismatch')
    return {
        'ready_condition': (substitute_child(ready, compare['right'], 'targetTechnique'), 1),
        'target_getter': (setter['args'][0]['text'], 3),
        'preset_getter': (setter['args'][1]['text'], 1),
        'framegen_getter': (setter['args'][2]['text'], 1),
        'current_query': (substitute_child(query, query_receiver, dev_local), 1),
        'upscaling_condition': (change['condition']['text'], 1),
        'upscaling_call': (substitute_child(setter, setter['args'][0], 'targetUpscalingTechnique'), 1),
    }


def startup(nodes, lines):
    require(len(nodes) == 14, 'startup top-level node count')
    select(nodes[0], 'expr', 0)
    select(nodes[9], 'while')
    select(nodes[12], 'expr', end=427)
    select(nodes[13], 'return', 427, 431)
    rendered = text_lines(nodes[:13], 2)
    require(len(rendered) == 24, 'startup retained body line count')
    # Preserve accepted line-table layout: one blank between the retry loop
    # and the final three local statements. No original statement text stored.
    rendered.insert(len(rendered) - 3, '')
    set_block(lines, 202, 25, 'startup_body', rendered)
    return {}


def reconstruct(code, template, cls, method):
    require((cls, method) in ORIGINAL_PYC_HASHES, 'unsupported target')
    require(code.co_name == method and code.co_argcount == 1, 'method identity or arguments')
    expected_bytes = 676 if cls == 'SystemMenu' else 431
    require(len(code.co_code) == expected_bytes, 'method byte length')
    require('\r' not in template, 'template must use canonical LF line endings')
    lines = template.split('\n')
    nodes = derive_method(code)
    inline = graphics(nodes, lines) if cls == 'SystemMenu' else startup(nodes, lines)
    result = '\n'.join(lines)
    for name, pair in inline.items():
        value, count = pair
        marker = '@LOCAL:' + name + '@'
        require(result.count(marker) == count, 'inline marker count ' + name)
        require('\n' not in value and '\r' not in value, 'multiline inline expression')
        result = result.replace(marker, value)
    require('@LOCAL:' not in result, 'unexpanded local marker')
    require(len(result.split('\n')) == len(lines), 'template line slots changed')
    return result
