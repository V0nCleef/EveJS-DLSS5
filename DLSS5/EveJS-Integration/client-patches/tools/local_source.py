"""Narrow, data-only Python 2.7 instruction-to-source reconstruction.

This is not a general decompiler. Callers must verify the archive and target
identity before calling it. Names, literals, expressions and statements are
derived from the supplied code object, never from a client-source template.
The accepted subset has forward conditionals, while loops, and one typed
exception handler. Unsupported bytecode or control flow fails closed.

There are deliberately no imports: the pinned embedded Python runtime can use
this module without xdis or an installed standard library. Portable xdis code
objects are supported only as a convenience for offline development.
"""


class UnsupportedCode(ValueError):
    pass


# Public CPython 2.7 opcode numbers, not application-specific instruction data.
OPCODES = {
    1: 'POP_TOP', 4: 'DUP_TOP', 12: 'UNARY_NOT', 25: 'BINARY_SUBSCR',
    83: 'RETURN_VALUE', 87: 'POP_BLOCK', 88: 'END_FINALLY',
    95: 'STORE_ATTR', 100: 'LOAD_CONST', 103: 'BUILD_LIST', 106: 'LOAD_ATTR',
    107: 'COMPARE_OP', 110: 'JUMP_FORWARD', 113: 'JUMP_ABSOLUTE',
    114: 'POP_JUMP_IF_FALSE', 115: 'POP_JUMP_IF_TRUE', 116: 'LOAD_GLOBAL',
    120: 'SETUP_LOOP', 121: 'SETUP_EXCEPT', 124: 'LOAD_FAST',
    125: 'STORE_FAST', 131: 'CALL_FUNCTION', 140: 'CALL_FUNCTION_VAR',
}
COMPARE = ('<', '<=', '==', '!=', '>', '>=', 'in', 'not in', 'is', 'is not')


def _error(message, offset=None):
    if offset is not None:
        message += ' at byte offset %s' % offset
    raise UnsupportedCode(message)


def _byte(value):
    return value if isinstance(value, int) else ord(value)


def _identifier(value):
    # Restrict the narrow prototype to ASCII identifiers. Never interpolate an
    # unchecked name into generated source.
    if not isinstance(value, type('')):
        _error('non-byte-string identifier')
    if not value or value[0] not in '_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ':
        _error('invalid identifier')
    if any(c not in '_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' for c in value):
        _error('invalid identifier')
    if value in ('and', 'as', 'assert', 'break', 'class', 'continue', 'def',
                 'del', 'elif', 'else', 'except', 'exec', 'finally', 'for',
                 'from', 'global', 'if', 'import', 'in', 'is', 'lambda',
                 'not', 'or', 'pass', 'print', 'raise', 'return', 'try',
                 'while', 'with', 'yield'):
        _error('keyword used as an identifier')
    return value


def _literal(value):
    if value is None or isinstance(value, (bool, int, float)):
        result = repr(value)
        if result in ('nan', 'inf', '-inf'):
            _error('non-finite constant')
        return result
    if isinstance(value, type('')):
        if any(ord(c) > 127 for c in value):
            _error('non-ASCII constant is outside the supported subset')
        return repr(value)
    _error('unsupported constant type')


def decode(code):
    """Decode only the supported public Python 2.7 instruction subset."""
    raw = code.co_code
    instructions = []
    cursor = 0
    while cursor < len(raw):
        start = cursor
        number = _byte(raw[cursor])
        cursor += 1
        if number not in OPCODES:
            _error('unsupported opcode %s' % number, start)
        arg = None
        if number >= 90:
            if cursor + 2 > len(raw):
                _error('truncated instruction', start)
            arg = _byte(raw[cursor]) | (_byte(raw[cursor + 1]) << 8)
            cursor += 2
        op = OPCODES[number]
        ins = {'op': op, 'arg': arg, 'offset': start, 'end': cursor}
        if op in ('JUMP_FORWARD', 'SETUP_LOOP', 'SETUP_EXCEPT'):
            ins['target'] = cursor + arg
        elif op in ('JUMP_ABSOLUTE', 'POP_JUMP_IF_TRUE', 'POP_JUMP_IF_FALSE'):
            ins['target'] = arg
        instructions.append(ins)
    boundaries = set(ins['offset'] for ins in instructions)
    boundaries.add(len(raw))
    for ins in instructions:
        if 'target' in ins and ins['target'] not in boundaries:
            _error('jump target is not an instruction boundary', ins['offset'])
    return instructions


def _expr(kind, text, start, end, **fields):
    result = {'kind': kind, 'text': text, 'start': start, 'end': end}
    result.update(fields)
    return result


def _parenthesize(expr, kinds):
    return '(' + expr['text'] + ')' if expr['kind'] in kinds else expr['text']


def _negate(expr):
    if expr['kind'] == 'not':
        return expr['operand']
    return _expr('not', 'not ' + _parenthesize(expr, ('or', 'compare')),
                 expr['start'], expr['end'], operand=expr)


def _combine_or(terms):
    if len(terms) == 1:
        return terms[0]
    return _expr('or', ' or '.join(term['text'] for term in terms),
                 terms[0]['start'], terms[-1]['end'], values=terms)


class _Parser(object):
    def __init__(self, code):
        self.code = code
        self.ins = decode(code)
        self.index = dict((ins['offset'], i) for i, ins in enumerate(self.ins))
        self.index[len(code.co_code)] = len(self.ins)
        self.covered = set()

    def mark(self, first, end):
        for i in range(first, end):
            if i in self.covered:
                _error('instruction consumed more than once', self.ins[i]['offset'])
            self.covered.add(i)

    def item(self, table, arg, ins):
        if arg is None or arg < 0 or arg >= len(table):
            _error('operand table index out of bounds', ins['offset'])
        return table[arg]

    def pop(self, stack, ins):
        if not stack:
            _error('expression stack underflow', ins['offset'])
        return stack.pop()

    def expression_step(self, i, stack):
        ins = self.ins[i]
        op, arg, start, end = ins['op'], ins['arg'], ins['offset'], ins['end']
        if op == 'LOAD_CONST':
            value = self.item(self.code.co_consts, arg, ins)
            stack.append(_expr('constant', _literal(value), start, end, value=value))
        elif op in ('LOAD_FAST', 'LOAD_GLOBAL'):
            table = self.code.co_varnames if op == 'LOAD_FAST' else self.code.co_names
            name = _identifier(self.item(table, arg, ins))
            stack.append(_expr('name', name, start, end, name=name, scope=op))
        elif op == 'LOAD_ATTR':
            owner = self.pop(stack, ins)
            name = _identifier(self.item(self.code.co_names, arg, ins))
            stack.append(_expr('attribute', _parenthesize(owner, ('or', 'compare', 'not')) + '.' + name,
                               owner['start'], end, owner=owner, attribute=name))
        elif op == 'UNARY_NOT':
            value = self.pop(stack, ins)
            result = _negate(value)
            result = dict(result)
            result['end'] = end
            stack.append(result)
        elif op == 'COMPARE_OP':
            if arg >= len(COMPARE):
                _error('comparison outside expression subset', start)
            right, left = self.pop(stack, ins), self.pop(stack, ins)
            text = '%s %s %s' % (_parenthesize(left, ('or', 'compare', 'not')),
                                  COMPARE[arg], _parenthesize(right, ('or', 'compare', 'not')))
            stack.append(_expr('compare', text, left['start'], end,
                               left=left, right=right, operator=COMPARE[arg]))
        elif op == 'BINARY_SUBSCR':
            key, owner = self.pop(stack, ins), self.pop(stack, ins)
            stack.append(_expr('subscript', _parenthesize(owner, ('or', 'compare', 'not')) + '[' + key['text'] + ']',
                               owner['start'], end, owner=owner, key=key))
        elif op == 'BUILD_LIST':
            if len(stack) < arg:
                _error('list stack underflow', start)
            values = stack[-arg:] if arg else []
            if arg:
                del stack[-arg:]
            stack.append(_expr('list', '[' + ', '.join(value['text'] for value in values) + ']',
                               values[0]['start'] if values else start, end, values=values))
        elif op in ('CALL_FUNCTION', 'CALL_FUNCTION_VAR'):
            star = self.pop(stack, ins) if op == 'CALL_FUNCTION_VAR' else None
            positional_count, keyword_count = arg & 255, arg >> 8
            keywords = []
            for unused in range(keyword_count):
                value, name = self.pop(stack, ins), self.pop(stack, ins)
                if name['kind'] != 'constant':
                    _error('keyword name is not a constant', start)
                keywords.append((_identifier(name['value']), value))
            keywords.reverse()
            if len(set(name for name, value in keywords)) != len(keywords):
                _error('duplicate keyword', start)
            args = [self.pop(stack, ins) for unused in range(positional_count)]
            args.reverse()
            function = self.pop(stack, ins)
            pieces = [value['text'] for value in args]
            pieces.extend(name + '=' + value['text'] for name, value in keywords)
            if star is not None:
                pieces.append('*' + star['text'])
            text = _parenthesize(function, ('or', 'compare', 'not')) + '(' + ', '.join(pieces) + ')'
            stack.append(_expr('call', text, function['start'], end,
                               function=function, args=args, keywords=keywords, star=star))
        else:
            return False
        return True

    def condition(self, start, end):
        """Consume one condition, including a narrowly checked OR chain."""
        stack = []
        i = start
        while i < end and self.expression_step(i, stack):
            i += 1
        if i >= end or self.ins[i]['op'] not in ('POP_JUMP_IF_TRUE', 'POP_JUMP_IF_FALSE') or len(stack) != 1:
            _error('condition does not end in a single conditional jump', self.ins[start]['offset'])
        return self.condition_tail(start, i, stack[0], end)

    def condition_tail(self, start, jump_index, condition, end):
        jump = self.ins[jump_index]
        destination = self.index[jump['target']]
        if destination <= jump_index or destination > end:
            _error('conditional target is not a forward in-block boundary', jump['offset'])
        # OR: true branches all target the body start; the final false branch
        # skips the body. Everything between terms must be an expression.
        if jump['op'] == 'POP_JUMP_IF_TRUE':
            cursor = jump_index + 1
            terms = [condition]
            chain_end = None
            while cursor < destination:
                stack = []
                while cursor < destination and self.expression_step(cursor, stack):
                    cursor += 1
                if cursor >= destination or len(stack) != 1:
                    break
                probe = self.ins[cursor]
                if probe['op'] == 'POP_JUMP_IF_TRUE' and probe['target'] == jump['target']:
                    terms.append(stack[0])
                    cursor += 1
                    continue
                if probe['op'] == 'POP_JUMP_IF_FALSE' and cursor + 1 == destination:
                    chain_end = self.index[probe['target']]
                    if chain_end <= destination or chain_end > end:
                        _error('OR-chain exit outside enclosing block', probe['offset'])
                    terms.append(stack[0])
                break
            if chain_end is not None:
                self.mark(start, destination)
                return _combine_or(terms), destination, chain_end
            condition = _negate(condition)
        self.mark(start, jump_index + 1)
        return condition, jump_index + 1, destination

    def try_node(self, i, end, loop_head):
        setup = self.ins[i]
        handler = self.index[setup['target']]
        if handler < i + 3 or handler >= end:
            _error('unsupported exception region', setup['offset'])
        normal_pop, normal_jump = handler - 2, handler - 1
        if self.ins[normal_pop]['op'] != 'POP_BLOCK' or self.ins[normal_jump]['op'] not in ('JUMP_ABSOLUTE', 'JUMP_FORWARD'):
            _error('unsupported normal exception exit', setup['offset'])
        join = self.ins[normal_jump]['target']
        self.mark(i, i + 1)
        body = self.sequence(i + 1, normal_pop, loop_head)
        self.mark(normal_pop, handler)
        if self.ins[handler]['op'] != 'DUP_TOP':
            _error('only one typed exception handler is supported', setup['offset'])
        cursor = handler + 1
        stack = []
        while cursor < end and self.ins[cursor]['op'] != 'COMPARE_OP' and self.expression_step(cursor, stack):
            cursor += 1
        if cursor + 4 >= end or len(stack) != 1 or self.ins[cursor]['op'] != 'COMPARE_OP' or self.ins[cursor]['arg'] != 10:
            _error('malformed typed exception match', setup['offset'])
        exception_type = stack[0]
        cursor += 1
        if self.ins[cursor]['op'] != 'POP_JUMP_IF_FALSE':
            _error('malformed exception dispatch', setup['offset'])
        finally_index = self.index[self.ins[cursor]['target']]
        if self.ins[finally_index]['op'] != 'END_FINALLY':
            _error('multiple or unknown exception handlers', setup['offset'])
        cursor += 1
        if [self.ins[k]['op'] for k in range(cursor, cursor + 3)] != ['POP_TOP', 'STORE_FAST', 'POP_TOP']:
            _error('unsupported exception binding', setup['offset'])
        binding = self.ins[cursor + 1]
        target = _identifier(self.item(self.code.co_varnames, binding['arg'], binding))
        cursor += 3
        self.mark(handler, cursor)
        catch_jump = self.ins[finally_index - 1]
        if catch_jump['op'] not in ('JUMP_ABSOLUTE', 'JUMP_FORWARD') or catch_jump['target'] != join:
            _error('exception paths have different joins', setup['offset'])
        if join < setup['offset'] and join != loop_head:
            _error('exception back edge does not target owning loop', setup['offset'])
        if join not in (self.ins[finally_index]['end'], loop_head):
            _error('exception join skips an unknown region', setup['offset'])
        catch_body = self.sequence(cursor, finally_index - 1, loop_head)
        self.mark(finally_index - 1, finally_index + 1)
        node = {'kind': 'try', 'start': setup['offset'], 'end': self.ins[finally_index]['end'],
                'body': body, 'handlers': [{'type': exception_type, 'target': target,
                                           'body': catch_body, 'start': self.ins[handler]['offset'],
                                           'end': self.ins[finally_index]['offset']}]}
        return node, finally_index + 1

    def sequence(self, start, end, loop_head=None):
        nodes, stack = [], []
        i, expression_start = start, start
        while i < end:
            ins = self.ins[i]
            op = ins['op']
            if self.expression_step(i, stack):
                i += 1
                continue
            if op in ('POP_TOP', 'STORE_FAST', 'STORE_ATTR', 'RETURN_VALUE'):
                if op == 'STORE_ATTR':
                    owner, value = self.pop(stack, ins), self.pop(stack, ins)
                    name = _identifier(self.item(self.code.co_names, ins['arg'], ins))
                    target = _expr('attribute', owner['text'] + '.' + name, owner['start'], ins['end'], owner=owner, attribute=name)
                else:
                    value = self.pop(stack, ins)
                    target = None
                if stack:
                    _error('statement leaves expression stack values', ins['offset'])
                node = {'start': self.ins[expression_start]['offset'], 'end': ins['end']}
                if op == 'POP_TOP':
                    node.update(kind='expr', expression=value)
                elif op == 'RETURN_VALUE':
                    node.update(kind='return', value=value, implicit=(i == len(self.ins) - 1 and value['kind'] == 'constant' and value['value'] is None))
                else:
                    if op == 'STORE_FAST':
                        name = _identifier(self.item(self.code.co_varnames, ins['arg'], ins))
                        target = _expr('name', name, ins['offset'], ins['end'], name=name, scope=op)
                    node.update(kind='assign', target=target, value=value)
                nodes.append(node)
                self.mark(expression_start, i + 1)
                i += 1
            elif op in ('POP_JUMP_IF_TRUE', 'POP_JUMP_IF_FALSE'):
                if len(stack) != 1:
                    _error('conditional requires exactly one stack expression', ins['offset'])
                value = stack.pop()
                condition, body_start, body_end = self.condition_tail(expression_start, i, value, end)
                nodes.append({'kind': 'if', 'condition': condition,
                              'body': self.sequence(body_start, body_end, loop_head),
                              'start': self.ins[expression_start]['offset'],
                              'end': self.ins[body_end]['offset'] if body_end < len(self.ins) else len(self.code.co_code)})
                i = body_end
            elif op == 'SETUP_LOOP':
                if stack:
                    _error('loop starts with expression values', ins['offset'])
                loop_end = self.index[ins['target']]
                if loop_end > end or loop_end < i + 4 or self.ins[loop_end - 1]['op'] != 'POP_BLOCK':
                    _error('unsupported loop layout', ins['offset'])
                self.mark(i, i + 1)
                head = i + 1
                condition, body_start, body_end = self.condition(head, loop_end - 1)
                if body_end != loop_end - 1:
                    _error('while condition has unexpected exit', ins['offset'])
                back = self.ins[body_end - 1]
                if back['op'] != 'JUMP_ABSOLUTE' or back['target'] != self.ins[head]['offset']:
                    _error('loop has no validated back edge', ins['offset'])
                body = self.sequence(body_start, body_end - 1, self.ins[head]['offset'])
                self.mark(body_end - 1, loop_end)
                nodes.append({'kind': 'while', 'condition': condition, 'body': body,
                              'start': ins['offset'], 'end': ins['target']})
                i = loop_end
            elif op == 'SETUP_EXCEPT':
                if stack:
                    _error('try starts with expression values', ins['offset'])
                node, i = self.try_node(i, end, loop_head)
                nodes.append(node)
            elif op in ('JUMP_FORWARD', 'JUMP_ABSOLUTE'):
                boundary = self.ins[end]['offset'] if end < len(self.ins) else len(self.code.co_code)
                if stack or ins['target'] not in (ins['end'], boundary):
                    _error('unsupported nonlocal jump', ins['offset'])
                self.mark(i, i + 1)
                i += 1
            else:
                _error('unsupported statement/control opcode ' + op, ins['offset'])
            expression_start = i
        if stack:
            _error('block ends with an incomplete expression', self.ins[start]['offset'])
        return nodes


def derive_method(code):
    """Return structured statements derived solely from code-object data.

    Every statement/expression has start/end byte offsets (end exclusive).
    Nodes: expr(expression), assign(target,value), if/while(condition,body),
    try(body,handlers), return(value,implicit). Expression nodes expose text
    plus structural fields: call(function,args,keywords,star), attribute(owner,
    attribute), compare(left,operator,right), subscript(owner,key), name(name),
    constant(value), list/or(values), not(operand).
    """
    for field in ('co_code', 'co_consts', 'co_names', 'co_varnames', 'co_argcount',
                  'co_flags', 'co_freevars', 'co_cellvars'):
        if not hasattr(code, field):
            _error('missing code-object field ' + field)
    if code.co_freevars or code.co_cellvars or code.co_flags & (4 | 8 | 32):
        _error('closures, variadic arguments and generators are unsupported')
    parser = _Parser(code)
    if not parser.ins:
        _error('empty method')
    nodes = parser.sequence(0, len(parser.ins))
    if parser.covered != set(range(len(parser.ins))):
        _error('not every input instruction was consumed exactly once')
    return nodes


def render_lines(nodes, indent=0):
    """Render one source line per node/header, carrying provenance offsets."""
    result = []

    def add(text, node, depth):
        result.append({'text': '    ' * depth + text, 'start': node['start'], 'end': node['end']})

    for node in nodes:
        kind = node['kind']
        if kind == 'expr':
            add(node['expression']['text'], node, indent)
        elif kind == 'assign':
            add(node['target']['text'] + ' = ' + node['value']['text'], node, indent)
        elif kind == 'return':
            value = node['value']
            add('return' if value['kind'] == 'constant' and value['value'] is None else 'return ' + value['text'], node, indent)
        elif kind in ('if', 'while'):
            add(kind + ' ' + node['condition']['text'] + ':', node, indent)
            result.extend(render_lines(node['body'], indent + 1))
        elif kind == 'try':
            add('try:', node, indent)
            result.extend(render_lines(node['body'], indent + 1))
            for handler in node['handlers']:
                add('except ' + handler['type']['text'] + ' as ' + handler['target'] + ':', handler, indent)
                result.extend(render_lines(handler['body'], indent + 1))
        else:
            _error('unsupported rendering node ' + kind)
    return result
