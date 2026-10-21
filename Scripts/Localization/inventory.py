import re,json
from pathlib import Path

def string_end(s,i):
    assert s[i]=='"'
    j=i+1; key=''; depth=0
    while j<len(s):
        if s[j]=='"':return j+1,key
        if s[j:j+2]=='\\(':
            k=j+2;dep=1
            while k<len(s) and dep:
                if s[k]=='"':k=string_end(s,k)[0];continue
                if s[k]=='(':dep+=1
                if s[k]==')':dep-=1
                k+=1
            key+='{'+str(depth)+'}';depth+=1;j=k;continue
        if s[j]=='\\' and j+1<len(s):
            key+={'n':'\n','t':'\t','r':'\r','"':'"','\\':'\\'}.get(s[j+1],s[j:j+2]);j+=2;continue
        key+=s[j];j+=1
    raise ValueError(s[i:i+120])

if __name__=='__main__':
    entries={}
    for p in Path('Sources').glob('*.swift'):
        s=p.read_text()
        for m in re.finditer(r'\b(Text|Button|Label|Picker|Section|Toggle|LabeledContent|GroupBox|TextField|ColorPicker|ClementineError|tr|help|accessibilityLabel|alert|confirmationDialog)\s*\(\s*(")',s):
            try: end,key=string_end(s,m.start(2))
            except:continue
            if key and (any(c.isalpha() for c in key)):
                entries.setdefault(key,[]).append(p.name)
    Path('.build/localization-inventory.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2))
    for key in entries:print(json.dumps(key,ensure_ascii=False))
