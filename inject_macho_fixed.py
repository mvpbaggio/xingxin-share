#!/usr/bin/env python3
"""正确注入LC_LOAD_DYLIB到arm64 Mach-O二进制
支持：padding足够时直接插入，不够时更新所有segment偏移"""
import struct, os, sys

MH_MAGIC_64 = 0xfeedfacf
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x02
LC_DYSYMTAB = 0x0B
LC_LOAD_DYLIB = 0x0C
LC_CODE_SIGNATURE = 0x1D
LC_SEGMENT_SPLIT_INFO = 0x1E
LC_FUNCTION_STARTS = 0x26
LC_DATA_IN_CODE = 0x29
LC_DYLIB_CODE_SIGN_DRS = 0x2B
LC_LINKER_OPTIMIZATION_HINT = 0x2E

def read32(data, off):
    return struct.unpack_from('<I', data[off:off+4])[0]

def write32(data, off, val):
    struct.pack_into('<I', data, off, val)

def read64(data, off):
    return struct.unpack_from('<Q', data[off:off+8])[0]

def write64(data, off, val):
    struct.pack_into('<Q', data, off, val)

def inject(macho_path, dylib_name='@executable_path/XingxinShare.dylib'):
    with open(macho_path, 'rb') as f:
        data = bytearray(f.read())
    
    magic = read32(data, 0)
    if magic != MH_MAGIC_64:
        print(f'Not arm64 Mach-O: magic=0x{magic:x}')
        return False
    
    ncmds = read32(data, 4)
    sizeofcmds = read32(data, 16)
    cmds_end = 32 + sizeofcmds
    
    # 构建dylib命令
    name_bytes = dylib_name.encode() + b'\x00'
    while len(name_bytes) % 4 != 0:
        name_bytes += b'\x00'
    
    cmd = struct.pack('<II', LC_LOAD_DYLIB, 24 + len(name_bytes))
    cmd += struct.pack('<III', 24, 0x01000000, 0x01000000)
    cmd += name_bytes
    cmd = bytes(cmd)
    
    # 遍历load commands找第一个非零数据segment
    pos = 32
    first_seg_off = None
    while pos < cmds_end:
        cmd_type = read32(data, pos)
        cmd_size = read32(data, pos+4)
        if cmd_type == LC_SEGMENT_64 and first_seg_off is None:
            seg_fileoff = read64(data, pos + 0x18)
            if seg_fileoff > 0:
                first_seg_off = seg_fileoff
                seg_name = data[pos+8:pos+24].split(b'\x00')[0].decode() or '?'
                print(f'First data segment: {seg_name}, fileoff=0x{seg_fileoff:x}')
        pos += cmd_size
    
    padding = first_seg_off - cmds_end if first_seg_off else 0
    print(f'cmds_end=0x{cmds_end:x}, data_off=0x{first_seg_off:x}, padding={padding} bytes')
    
    if padding >= len(cmd):
        # 方案A: 直接写padding
        data[cmds_end:cmds_end+len(cmd)] = cmd
        write32(data, 16, sizeofcmds + len(cmd))
        write32(data, 4, ncmds + 1)
        print(f'[A] Injected to padding. ncmds: {ncmds} -> {ncmds+1}')
    else:
        # 方案B: 需要移动segment数据
        shift = len(cmd)
        print(f'[B] Shifting all segments by {shift} bytes...')
        
        # 先插入新命令
        data[cmds_end:cmds_end] = cmd
        
        # 更新header
        write32(data, 16, sizeofcmds + shift)
        write32(data, 4, ncmds + 1)
        
        # 更新所有segment命令的fileoff
        pos = 32
        while pos < cmds_end:
            cmd_type = read32(data, pos)
            cmd_size = read32(data, pos+4)
            if cmd_type == LC_SEGMENT_64:
                seg_fileoff = read64(data, pos + 0x18)
                seg_filesize = read64(data, pos + 0x20)
                nsects = read32(data, pos + 0x3C)
                if seg_fileoff >= cmds_end:
                    write64(data, pos + 0x18, seg_fileoff + shift)
                    # 更新segment内所有section的offset
                    sec_base = pos + 0x48
                    for si in range(nsects):
                        sec_off = read64(data, sec_base + 0x20)
                        if sec_off >= cmds_end:
                            write64(data, sec_base + 0x20, sec_off + shift)
                        sec_base += 0x50
            elif cmd_type == LC_SYMTAB:
                symoff = read32(data, pos + 0x08)
                stroff = read32(data, pos + 0x10)
                if symoff >= cmds_end:
                    write32(data, pos + 0x08, symoff + shift)
                if stroff >= cmds_end:
                    write32(data, pos + 0x10, stroff + shift)
            elif cmd_type == LC_DYSYMTAB:
                for field in [4, 8, 12, 16, 20, 24, 28, 32, 36, 40]:
                    tocoff = read32(data, pos + field)
                    if tocoff >= cmds_end:
                        write32(data, pos + field, tocoff + shift)
            elif cmd_type in (LC_CODE_SIGNATURE, LC_SEGMENT_SPLIT_INFO,
                              LC_FUNCTION_STARTS, LC_DATA_IN_CODE,
                              LC_DYLIB_CODE_SIGN_DRS, LC_LINKER_OPTIMIZATION_HINT):
                dataoff = read32(data, pos + 0x08)
                if dataoff >= cmds_end:
                    write32(data, pos + 0x08, dataoff + shift)
            pos += cmd_size
        
        print(f'[B] Injected with shift. ncmds: {ncmds} -> {ncmds+1}')
    
    # 移除代码签名（对于TrollStore不需要签名）
    pos = 32
    codesig_removed = False
    while pos < read32(data, 16) + 32:
        cmd_type = read32(data, pos)
        cmd_size = read32(data, pos+4)
        if cmd_type == LC_CODE_SIGNATURE:
            # 把datasize和dataoff都归零
            write32(data, pos + 0x0C, 0)  # datasize = 0
            write32(data, pos + 0x08, 0)  # dataoff = 0
            codesig_removed = True
            print(f'[!] Code signature nullified at 0x{pos:x}')
            break
        pos += cmd_size
    
    if not codesig_removed:
        print('[i] No LC_CODE_SIGNATURE found')
    
    data_len_before = os.path.getsize(macho_path)
    with open(macho_path, 'wb') as f:
        f.write(data)
    print(f'Written! {data_len_before} -> {len(data)} bytes')
    return True

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <macho_path> [dylib_name]')
        sys.exit(1)
    inject(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '@executable_path/XingxinShare.dylib')
