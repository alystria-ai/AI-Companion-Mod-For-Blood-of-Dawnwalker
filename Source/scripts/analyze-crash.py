"""Offline PE export/unwind analysis; never attaches to or modifies the game.

Dependencies: pefile and capstone in vendor/analysis-python.
Run from the project root: python scripts/analyze-crash.py
"""
from pathlib import Path
import hashlib
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'vendor/analysis-python'))
import pefile
import capstone

dll = ROOT / 'vendor/ue4ss/ue4ss/UE4SS.dll'
pe = pefile.PE(str(dll))
exports = sorted((s.address, s.name.decode(errors='replace'))
                 for s in pe.DIRECTORY_ENTRY_EXPORT.symbols if s.name)
decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
lines = [f'UE4SS SHA256: {hashlib.sha256(dll.read_bytes()).hexdigest()}',
         'Frame RVAs copied from preserved CrashContext.runtime-xml.',
         'Nearest exports alone are NOT proof of function identity.',
         'Unwind ranges and call destinations below distinguish unnamed functions.']
for target in [0x227e52, 0x464d99, 0x2a9d51, 0x2bad71, 0x2bc184]:
    function = next(e.struct for e in pe.DIRECTORY_ENTRY_EXCEPTION
                    if e.struct.BeginAddress <= target < e.struct.EndAddress)
    address, name = max((a, n) for a, n in exports if a <= target)
    lines += [f'\nFrame {target:#x}; nearest export {address:#x}: {name}',
              f'Unwind range {function.BeginAddress:#x}..{function.EndAddress:#x}']
    for ins in decoder.disasm(pe.get_data(function.BeginAddress,
                             function.EndAddress-function.BeginAddress), function.BeginAddress):
        if target-22 <= ins.address <= target+4:
            lines.append(f'  {ins.address:#x}: {ins.mnemonic} {ins.op_str}')
lines += ['', 'Confirmed: push_softobjectproperty calls an unnamed copy routine,',
          'which calls FSoftObjectPath copy assignment, then FString copy assignment.',
          'The 0x2bc184 frame is in a separate unnamed function, NOT the nearest',
          'export push_multicastsparsedelegateproperty. No delegate crash is established.',
          'The precise runtime property and reason its path data was invalid remain unknown.']
result = '\n'.join(lines) + '\n'
(ROOT / 'runtime/native-crash-analysis.txt').write_text(result, encoding='utf8')
print(result)
