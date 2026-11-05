import re, json, glob, sys, os
SRC = sys.argv[1]
LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
keys = []
def add(s):
    s = bytes(s, 'utf-8').decode('unicode_escape').encode('latin-1').decode('utf-8') if '\\' in s else s
    if re.search(r'[A-Za-z]', s) and s not in keys: keys.append(s)
def balanced(text, i):
    depth = 0; j = i; instr = False
    while j < len(text):
        c = text[j]
        if instr:
            if c == '\\': j += 2; continue
            if c == '"': instr = False
        else:
            if c == '"': instr = True
            elif c == '(': depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0: return text[i:j+1]
        j += 1
    return text[i:]
PARAMS = r'(?:title|subtitle|body|plan|status|detail|note|placeholder|text|name|actionTitle)'
for f in sorted(glob.glob(os.path.join(SRC, '*.swift'))):
    t = open(f).read()
    base = os.path.basename(f)
    if base in ('Localization.swift', 'TextPipeline.swift'): continue
    for m in re.finditer(r'(?<![A-Za-z_])T\(', t):
        for l in LIT.findall(balanced(t, m.end()-1)): add(l)
    for m in re.finditer(r'(?<![A-Za-z_])' + PARAMS + r': ("(?:[^"\\\n]|\\.)*"(?:\s*:\s*"(?:[^"\\\n]|\\.)*")?)', t):
        for l in LIT.findall(m.group(1)): add(l)
    for m in re.finditer(r'(?:status|title): [^,\n]*\? ("(?:[^"\\\n]|\\.)*") : ("(?:[^"\\\n]|\\.)*")', t):
        add(m.group(1)[1:-1]); add(m.group(2)[1:-1])
    for m in re.finditer(r'SettingsSection\("((?:[^"\\\n]|\\.)*)"\)', t): add(m.group(1))
    for m in re.finditer(r'options: \[([^\]]*)\]', t):
        for l in LIT.findall(m.group(1)): add(l)
    for m in re.finditer(r'(?:message|ollamaStatus) = "((?:[^"\\\n]|\\.)*)"', t): add(m.group(1))
    if base == 'AppState.swift':
        for m in re.finditer(r'case \w+ = "([^"]+)"', t): add(m.group(1))
    if base == 'Transcription.swift':
        for m in re.finditer(r'\("([^"]+)", (?:nil|"[a-z]{2}"), "', t): add(m.group(1))
        for m in re.finditer(r'\("(?!response_format)[^"]+", "([^"]+)"\)', t): add(m.group(1))
    if base == 'SettingsView.swift':
        rel = t[t.index('private let releases'):t.index(']\n', t.index('private let releases'))+2] if 'private let releases' in t else ''
        i = t.find('private let releases'); j = t.find('\n    ]\n', i)
        for l in LIT.findall(t[i:j]): add(l)
for extra in ["Interrupted when Oruri closed. Retry from History.", "Auto-detect"]: add(extra)
json.dump(keys, open(sys.argv[2], 'w'), ensure_ascii=False, indent=0)
print(len(keys))
