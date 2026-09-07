import json, os, pathlib, shutil, subprocess, tempfile
root = pathlib.Path.cwd()
evidence = pathlib.Path('/home/nikita/.no-mistakes/evidence/01M1YDAAFDAABFD7GPFX4A5J7K')
prompt = '''Development-only conversation evaluation. Follow the supplied Firstmate contract. For each independent scenario below, generate the exact message you would send the user. Do not perform any operations. Return only a JSON object mapping each scenario ID to its user-facing message.
normal: The user asks what a scout does. Answer in one sentence.
failure: Verified result: the build failed because a required dependency is missing. Tell the user the result and consequence in one sentence.
routine: A routine operational update requires no action, but a response must be sent. There are no other decisions or issues to report.
'''
results = {}
with tempfile.TemporaryDirectory(prefix='.address-eval-', dir=root) as td:
    lab=pathlib.Path(td); config=lab/'config'; config.mkdir(mode=0o700)
    original=pathlib.Path('/home/nikita/.pi/agent')
    for name in ('auth.json','models.json'):
        if (original/name).exists():
            shutil.copyfile(original/name,config/name); (config/name).chmod(0o600)
    settings=json.loads((original/'settings.json').read_text())
    (config/'settings.json').write_text(json.dumps({k:settings[k] for k in ('defaultProvider','defaultModel','defaultThinkingLevel') if k in settings}))
    env=dict(os.environ, PI_CODING_AGENT_DIR=str(config), PI_TELEMETRY='0', PI_OFFLINE='1')
    args=['pi','--print','--mode','json','--no-session','--no-tools','--no-extensions','--no-skills','--no-prompt-templates','--no-themes','--no-context-files','--offline','--append-system-prompt',str(lab/'contract.md'),prompt]
    for label,rev in [('base','d4eb22801f7509c1c7942ea047db78bcb5389ea0'),('target','b65a2aaeff3025ccdd3a5583fbf5618bfdb4708a')]:
        contract=subprocess.check_output(['git','show',rev+':AGENTS.md'],text=True)
        (lab/'contract.md').write_text(contract)
        run=subprocess.run(args,cwd=lab,env=env,text=True,capture_output=True,timeout=150)
        (evidence/(label+'-pi.stderr.txt')).write_text(run.stderr)
        messages=[]
        for line in run.stdout.splitlines():
            try: event=json.loads(line)
            except ValueError: continue
            if event.get('type')=='message_end' and event.get('message',{}).get('role')=='assistant':
                m=event['message']
                messages.append({k:m[k] for k in ('role','provider','model','stopReason') if k in m} | {'content':[{'type':'text','text':b['text']} for b in m['content'] if b['type']=='text']})
        (evidence/(label+'-pi.jsonl')).write_text('\n'.join(json.dumps({'type':'message_end','message':m}) for m in messages)+'\n')
        result={'commit':rev,'exit_code':run.returncode,'messages':messages}
        results[label]=result
        print(label, json.dumps(result),flush=True)
        if run.returncode != 0: break
(evidence/'address-evaluation.json').write_text(json.dumps({'runtime':{k:settings.get(k) for k in ('defaultProvider','defaultModel','defaultThinkingLevel')},'prompt':prompt,'results':results},indent=2))
