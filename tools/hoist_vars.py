#!/usr/bin/env python3
"""Hoist inline `var x: T;` statements and `for var x :=` loops into the
enclosing procedure's var section (FPC objfpc doesn't allow inline vars).
Only touches src/*.pas. Idempotent-ish: lines already in a var section
(i.e. not starting with the 'var ' keyword) are left alone."""
import re, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = ["src/reg.pas", "src/sim.pas", "src/selftest.pas", "src/render.pas", "src/maps.pas"]

INLINE_VAR = re.compile(r'^(\s*)var\s+(.+?);\s*$')
FORVAR = re.compile(r'for\s+var\s+(\w+)\s*:=')
FORVAR_IN = re.compile(r'for\s+var\s+(\w+)\s+in\s+(.+)\s+do')

def split_decls(s):
    # 'a, b: T' possibly multiple 'var a: T; var b: U;' already split by caller
    return s.strip()

def hoist(path):
    with open(path) as f:
        lines = f.read().split('\n')
    out = []
    # stack of (proc_start_idx_in_out, hoisted_decls)
    proc_stack = []  # list of dicts: {'start': idx, 'decls': [(name,type)], 'vars_done': False}
    cur = None
    i = 0
    changed = False
    for line in lines:
        m = re.match(r'^(procedure|function)\s', line)
        if m:
            cur = {'start': len(out), 'decls': [], 'header_lines': 0}
            proc_stack.append(cur)
            out.append(line)
            continue
        # end of procedure: a line starting with 'end.' or 'end;' at col0? procedures end with 'end;' possibly indented
        if re.match(r'^end\s*[.;]', line) and cur is not None:
            # insert hoisted decls into var section if any
            if cur['decls']:
                # find var section: scan out from cur['start'] for a line == 'var' (col 0)
                inserted = False
                for k in range(cur['start'], len(out)):
                    if out[k].strip() == 'var':
                        for name, typ in cur['decls']:
                            out.insert(k + 1, f'  {name}: {typ};')
                            k += 1
                        inserted = True
                        break
                    if out[k].strip().startswith('begin') or (out[k].strip() and not re.match(r'^(var|\s|\{|\$)', out[k]) and not out[k].startswith('  ') and cur['header_lines'] > 0 and out[k].strip() == ''):
                        pass
                if not inserted:
                    # no var section: insert before first 'begin' at col 0 after header
                    for k in range(cur['start'], len(out)):
                        if re.match(r'^begin', out[k]):
                            out.insert(k, 'var')
                            for name, typ in cur['decls']:
                                out.insert(k + 1, f'  {name}: {typ};')
                                k += 1
                            inserted = True
                            break
                if not inserted:
                    # append var right after header (before first non-header line)
                    k = cur['start'] + 1
                    while k < len(out) and (out[k].strip() == '' or out[k].startswith('{$') or out[k].startswith('{')):
                        k += 1
                    out.insert(k, 'var')
                    for name, typ in cur['decls']:
                        out.insert(k + 1, f'  {name}: {typ};')
                        k += 1
                changed = True
            proc_stack.pop()
            cur = proc_stack[-1] if proc_stack else None
            out.append(line)
            continue
        if cur is not None:
            # for var x in COLLECTION do  -> infer type
            m = FORVAR_IN.search(line)
            if m:
                name, coll = m.group(1), m.group(2)
                typ = 'TSkillEffect' if 'effects' in coll else 'Integer'
                if not any(d[0] == name for d in cur['decls']):
                    cur['decls'].append((name, typ))
                line = FORVAR_IN.sub(f'for {name} in {coll} do', line)
                changed = True
            else:
                m = FORVAR.search(line)
                if m:
                    name = m.group(1)
                    if not any(d[0] == name for d in cur['decls']):
                        cur['decls'].append((name, 'Integer'))
                    line = FORVAR.sub(f'for {name} :=', line)
                    changed = True
            # inline var statement: starts with whitespace + 'var ' and no 'begin' later on the line
            m = INLINE_VAR.match(line)
            if m and 'begin' not in line:
                indent, decl = m.group(1), m.group(2)
                # decl may contain multiple: 'a: T; var b: U' won't match due to ; — handle by splitting manually
                # split on '; var ' first
                parts = re.split(r';\s*var\s+', decl)
                for p in parts:
                    p = p.strip().rstrip(';')
                    if not p:
                        continue
                    mm = re.match(r'^(.+?):\s*(.+)$', p)
                    if mm:
                        names, typ = mm.group(1), mm.group(2)
                        for nm in [x.strip() for x in names.split(',')]:
                            if nm and not any(d[0] == nm for d in cur['decls']):
                                cur['decls'].append((nm, typ))
                changed = True
                continue  # drop the inline var line
        out.append(line)
    if changed:
        with open(path, 'w') as f:
            f.write('\n'.join(out))
    print(path, 'changed' if changed else 'ok')

for f in FILES:
    hoist(os.path.join(ROOT, f))
