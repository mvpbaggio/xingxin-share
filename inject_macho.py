#!/usr/bin/env python3
"""注入LC_LOAD_DYLIB到Mach-O二进制"""
import struct, os, sys

def inject(macho_path, dylib_name='@executable_path/XingxinShare.dylib'):
    with open(macho_path, 'rb') as f:
        data = bytearray(f.read())
    
    magic = struct.unpack_from('<I', data[0:4])[0]
    if magic not in (0xfeedfacf,):
        print(f'Not arm64 Mach-O: magic=0x{magic:x}')
        return False
    
    (_, _, _, _, ncmds, sizeofcmds, _, _) = struct.unpack_from('<IIIIIIII', data[0:32])
    
    name_bytes = dylib_name.encode() + b'\x00'
    while len(name_bytes) % 4 != 0:
        name_bytes += b'\x00'
    
    cmd = struct.pack('<II', 0xc, 24 + len(name_bytes))
    cmd += struct.pack('<III', 24, 0x01000000, 0x01000000)
    cmd += name_bytes
    
    cmds_end = 32 + sizeofcmds
    new_data = data[:cmds_end] + cmd + data[cmds_end:]
    
    vals = list(struct.unpack_from('<IIIIIIII', data[0:32]))
    vals[4] += 1
    vals[5] += len(cmd)
    new_data[0:32] = struct.pack('<IIIIIIII', *vals)
    
    with open(macho_path, 'wb') as f:
        f.write(new_data)
    
    print(f'Injected: ncmds {ncmds} -> {ncmds+1}, added {len(cmd)} bytes')
    return True

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <macho_path> [dylib_name]')
        sys.exit(1)
    inject(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '@executable_path/XingxinShare.dylib')
