#!/usr/bin/env python3
"""替换已有LC_LOAD_DYLIB，不增加字节数"""
import struct, os, sys

def r(data, off, fmt='I'):
    return struct.unpack_from('<' + fmt, data, off)[0]

def patch(macho_path, dylib_path='@executable_path/XingxinShare.dylib'):
    with open(macho_path, 'rb') as f:
        data = bytearray(f.read())
    
    ncmds = r(data, 16)
    sizeofcmds = r(data, 20)
    cmds_end = 32 + sizeofcmds
    
    # 找所有LC_LOAD_DYLIB，找最适合替换的（足够大、不重要的framework）
    pos = 32
    candidates = []
    while pos < cmds_end:
        cmd = r(data, pos)
        cmdsize = r(data, pos+4)
        if cmd == 0x0C:  # LC_LOAD_DYLIB
            off = r(data, pos+8)
            name = data[pos+off:pos+cmdsize].split(b'\x00')[0].decode(errors='replace')
            candidates.append((pos, cmdsize, name))
        pos += cmdsize
    
    # 排序：优先选包含不关键关键词的，大小>=68的
    NON_ESSENTIAL = ['OpenGLES', 'GLKit', 'AdSupport', 'OpenAL', 
                     'AssetsLibrary', 'GLKit', 'OpenGL', 'GameKit']
    
    candidates.sort(key=lambda c: (
        -sum(k in c[2] for k in NON_ESSENTIAL),  # 不关键优先
        -c[1],  # 大的优先
    ))
    
    target = None
    for pos, sz, name in candidates:
        if sz >= 68:
            target = (pos, sz, name)
            break
    
    if not target:
        print("No suitable LC_LOAD_DYLIB found!")
        return False
    
    t_pos, t_sz, t_name = target
    print(f"Replacing: {t_name} (sz={t_sz}) at 0x{t_pos:x}")
    
    # 构建新dylib命令
    path_bytes = dylib_path.encode() + b'\x00'
    # 路径字符串区域的可用大小 = cmdsize - 24
    path_space = t_sz - 24
    if len(path_bytes) > path_space:
        print(f"Path too long: {len(path_bytes)} > {path_space}")
        return False
    
    # Zero-fill剩余路径空间
    path_bytes += b'\x00' * (path_space - len(path_bytes))
    
    # 构建完整命令
    new_cmd = struct.pack('<II', 0x0C, t_sz)  # cmd, cmdsize
    new_cmd += struct.pack('<IIII', 24, 0, 0x01000000, 0x01000000)  # offset, timestamp, cur_ver, compat_ver
    new_cmd += path_bytes
    
    assert len(new_cmd) == t_sz, f"Size mismatch: {len(new_cmd)} != {t_sz}"
    
    # 替换
    data[t_pos:t_pos + t_sz] = new_cmd
    
    # 把LC_CODE_SIGNATURE的dataoff/datasize归零
    pos = 32
    while pos < 32 + sizeofcmds:
        cmd = r(data, pos)
        cmdsize = r(data, pos+4)
        if cmd == 0x1D:  # LC_CODE_SIGNATURE
            struct.pack_into('<I', data, pos+8, 0)  # dataoff=0
            struct.pack_into('<I', data, pos+12, 0) # datasize=0
            print(f"Code signature nullified at 0x{pos:x}")
            break
        pos += cmdsize
    
    with open(macho_path, 'wb') as f:
        f.write(data)
    print(f"Patched! {macho_path}")
    return True

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <macho_path> [dylib_path]")
        sys.exit(1)
    patch(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '@executable_path/XingxinShare.dylib')
