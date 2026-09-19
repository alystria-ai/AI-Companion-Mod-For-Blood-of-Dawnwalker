"""Offline crash evidence: exception registers, unwind ranges and instructions."""
from pathlib import Path
import sys, json
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'vendor/analysis-python'))
import pefile,capstone
from minidump.minidumpfile import MinidumpFile
from minidump.streams.ContextStream import CONTEXT
from game_paths import game_bin

out=[]
def emit(s):out.append(str(s))
dump=MinidumpFile.parse(str(ROOT/'runtime/crash-v0241/UEMinidump.dmp'))
emit(dump.exception)
with (ROOT/'runtime/crash-v0241/UEMinidump.dmp').open('rb') as data:
 data.seek(dump.exception.exception_records[0].ThreadContext.Rva)
 ctx=CONTEXT.parse(data)
 emit({name:hex(getattr(ctx,name)) for name in ['Rax','Rbx','Rcx','Rdx','Rsi','Rdi','R8','R9','Rip','Rsp','Rbp']})
decoder=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_64)
for filename,targets in [(game_bin()/'Dawnwalker.exe',[0x5cddcd2,0x114d452]),(game_bin()/'ue4ss/UE4SS.dll',[0x2b377a,0xb8a395,0xb8fe61])]:
 pe=pefile.PE(str(filename),fast_load=True)
 pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXCEPTION'],pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXPORT']])
 exports=sorted((s.address,s.name.decode(errors='replace'))for s in getattr(pe,'DIRECTORY_ENTRY_EXPORT',type('E',(),{'symbols':[]})()).symbols if s.name)
 emit(filename.name)
 for target in targets:
  f=next((e.struct for e in pe.DIRECTORY_ENTRY_EXCEPTION if e.struct.BeginAddress<=target<e.struct.EndAddress),None)
  emit(f'Frame {target:#x} unwind {f.BeginAddress:#x}..{f.EndAddress:#x}' if f else f'Frame {target:#x} no unwind')
  if exports:emit('Nearest export (not necessarily the function): '+str(max((a,n)for a,n in exports if a<=target)))
  if f:
   size=min(4000,f.EndAddress-f.BeginAddress)
   for i in decoder.disasm(pe.get_data(f.BeginAddress,size),f.BeginAddress):
    if target-100<=i.address<=target+40 or filename.name=='Dawnwalker.exe'and f.EndAddress-f.BeginAddress<500:emit(f'{i.address:#x}: {i.mnemonic} {i.op_str}')
 pe.close()
report='\n'.join(out)
(ROOT/'runtime/crash-v0241/analysis.txt').write_text(report,encoding='utf8')
print(report)
