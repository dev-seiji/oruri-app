#!/usr/bin/env python3
"""Gera es.json, pt.json e ja.json a partir de translations.txt e confere:
- todo texto do código (extraído por extract.py) tem tradução nos três idiomas;
- os %@ / %ld / %% de cada tradução batem com os do inglês."""
import json, os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'Sources', 'Oruri')
LANGS = ['es', 'pt', 'ja']
keys_path = os.path.join(HERE, '.keys.json')
subprocess.run([sys.executable, os.path.join(HERE, 'extract.py'), SRC, keys_path], check=True, stdout=subprocess.DEVNULL)
code_keys = json.load(open(keys_path)); os.remove(keys_path)

table = {l: {} for l in LANGS}; current = None; errors = []
for n, line in enumerate(open(os.path.join(HERE, 'translations.txt')), 1):
    line = line.rstrip('\n')
    if line.startswith('#') or not line.strip(): continue
    if line.startswith('@ '): current = line[2:]; continue
    m = re.match(r'(es|pt|ja): (.*)$', line)
    if not m or current is None: errors.append(f'linha {n}: formato inesperado: {line[:60]}'); continue
    table[m.group(1)][current] = m.group(2)

spec = re.compile(r'%(?:\d+\$)?[0-9]*l?[d@%]')
for k in code_keys:
    for l in LANGS:
        if k not in table[l]: errors.append(f'[{l}] falta: {k[:90]}')
        elif sorted(spec.findall(table[l][k])) != sorted(spec.findall(k)):
            errors.append(f'[{l}] valores diferentes: {k[:70]}')
extra = [k for k in table['es'] if k not in code_keys]
for l in LANGS:
    json.dump(table[l], open(os.path.join(HERE, f'{l}.json'), 'w'), ensure_ascii=False, indent=1, sort_keys=True)
print(f'{len(code_keys)} textos no código; {len(extra)} traduções sem uso')
for k in extra: print('  sem uso:', k[:90])
for e in errors: print(e)
sys.exit(1 if errors else 0)
