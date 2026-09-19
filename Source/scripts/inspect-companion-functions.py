"""Read selected function bodies from the local executable; never run them."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'vendor/analysis-python'))
import pefile,capstone
from game_paths import game_bin
pe=pefile.PE(str(game_bin()/'Dawnwalker.exe'),fast_load=True)
pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXCEPTION']])
cs=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_64)
out=[]
for value in sys.argv[1:]:
 address=int(value,16)
 f=next((e.struct for e in pe.DIRECTORY_ENTRY_EXCEPTION if e.struct.BeginAddress<=address<e.struct.EndAddress),None)
 if not f:
  out.append(f'LEAF / NO UNWIND {address:#x} (bounded decode)')
  for i in cs.disasm(pe.get_data(address,96),address):
   out.append(f'{i.address:#x}: {i.mnemonic} {i.op_str}')
   if i.mnemonic in ('ret','int3'):break
  continue
 out.append(f'FUNCTION {f.BeginAddress:#x}..{f.EndAddress:#x}')
 for i in cs.disasm(pe.get_data(f.BeginAddress,min(5000,f.EndAddress-f.BeginAddress)),f.BeginAddress):out.append(f'{i.address:#x}: {i.mnemonic} {i.op_str}')
print('\n'.join(out))
