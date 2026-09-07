import json,pathlib,re
p=pathlib.Path(__file__).parent
d=json.loads((p/'address-evaluation.json').read_text())
outputs={}
for label,r in d['results'].items():
    assert r['exit_code']==0
    assert r['messages'][-1]['stopReason']=='stop'
    outputs[label]=json.loads(''.join(b['text'] for b in r['messages'][-1]['content']))
assert set(outputs)=={'base','target'}
for label,reply in outputs.items():
    assert set(reply)=={'normal','failure','routine'}
    address='Captain' if label=='base' else 'Nikita'
    for case,text in reply.items():
        assert text.startswith(address+', '),(label,case,text)
        if label=='target': assert not re.search(r'\bcaptain\b',text,re.I)
    assert reply['routine']==address+', shipshape.'
    assert not any(w in reply['failure'].lower() for w in ['shipshape','ahoy','aye','on deck','under way'])
assert all(not text.startswith('Nikita, ') for text in outputs['base'].values())
lines=['# Firstmate direct-address development evaluation','',
'Actual Pi-generated messages using the full AGENTS.md from each commit. Runtime: openai-codex / gpt-5.6-sol, medium thinking. Tools, extensions, context discovery, and session persistence disabled. The contract was explicitly supplied as an appended system prompt. This is a bounded model-interpretation evaluation, not a native discovery/restart test or a universal compliance guarantee.','',
'The same scenario request was used for base and target; it specified no name or expected wording.','', '## Scenario request','',d['prompt']]
for label,reply in outputs.items():
    lines += ['## '+label.title()+' ('+d['results'][label]['commit']+')','']
    for case,text in reply.items(): lines += ['### '+case,'',text,'']
lines += ['## Assessment','',
'All three target replies address Nikita; all three baseline replies address Captain. The routine reply preserves shipshape. Both failure replies omit nautical seasoning. Manual diff review confirms only AGENTS.md changed and the two nautical-guidance lines remain unchanged.','',
'Local Ollama availability check failed (connection refused); the installed authenticated Pi runtime completed the evaluation instead. No browser/UI surface changed, so the generated CLI conversation is the product evidence.']
(p/'address-transcript.md').write_text('\n'.join(lines)+'\n')
print('PASS: generated replies demonstrate Captain → Nikita for ordinary, failure, and routine scenarios; shipshape and serious tone preserved.')
