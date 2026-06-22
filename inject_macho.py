#!/usr/bin/env python3
"""Mach-O dylib注入工具 (纯Python, 无依赖)"""

import struct
import os
import sys

# Mach-O 常量
FAT_MAGIC = 0xcafebabe
FAT_CIGAM = 0xbebafeca
MH_MAGIC_64 = 0xfeedfacf
MH_CIGAM_64 = 0xcffaedfe

LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0xc
LC_ID_DYLIB = 0xd
LC_CODE_SIGNATURE = 0x1d
LC_ENCRYPTION_INFO_64 = 0x2c

CPU_TYPE_ARM64 = 0x100000c  # CPU_TYPE_ARM | CPU_ARCH_ABI64

def read_pascal_string(data, offset):
    """读取Pascal字符串 (长度+内容)"""
    length = struct.unpack_from('>I', data, offset)[0]
    s = data[offset+4:offset+4+length]
    # 补齐到4字节对齐
    padding = (4 - ((length + 4) % 4)) % 4
    return s.decode('utf-8', errors='replace'), 4 + length + padding

def write_pascal_string(s):
    """写入Pascal字符串"""
    encoded = s.encode('utf-8')
    length = len(encoded)
    padding = (4 - ((length + 4) % 4)) % 4
    return struct.pack('>I', length) + encoded + b'\x00' * padding

def create_minimal_dylib():
    """创建一个最小化的arm64 dylib (只含构造函数并调Runtime)"""
    # 汇编代码: __attribute__((constructor))
    # 使用纯ARM64指令
    asm_code = b''
    # 我们写一个简单的dylib模板（完整功能在第二个函数中实现注入）
    # 这是一个带符号的空白dylib模板
    # 使用magic bytes: 正常的arm64 dylib结构
    
    # 为了简化，这里我们直接生成一个调用dlsym的dylib
    # 但更好的方案是: 只生成一个空的load命令，实际代码由外部注入
    
    # 对于注入来说，我们只需要一个有效的dylib
    # 这里使用Python构造最小dylib
    return b''

def patch_macho(input_path, output_path, dylib_path):
    """注入LC_LOAD_DYLIB到Mach-O"""
    with open(input_path, 'rb') as f:
        data = bytearray(f.read())
    
    # 检查是否是胖二进制
    magic = struct.unpack_from('>I', bytes(data[0:4]))[0]
    
    if magic in (FAT_MAGIC, FAT_CIGAM):
        print("[*] 胖二进制，提取arm64 slice...")
        # 简单处理: 找到arm64 slice
        narch = struct.unpack_from('>I', bytes(data[4:8]))[0]
        offset = 8
        for i in range(narch):
            cputype, cpusubtype, arch_offset, arch_size, align = \
                struct.unpack_from('>IIIIII' if magic == FAT_MAGIC else '<IIIIII',
                                 bytes(data[offset:offset+24]))
            print(f"  slice {i}: cputype=0x{cputype:x}, offset={arch_offset}, size={arch_size}")
            if cputype == CPU_TYPE_ARM64:
                data = bytearray(data[arch_offset:arch_offset+arch_size])
                break
            offset += 20
    elif magic in (MH_MAGIC_64, MH_CIGAM_64):
        print("[*] 已经是arm64 Mach-O")
    else:
        print(f"[!] 未知格式: magic=0x{magic:x}")
        return False
    
    # 解析Mach-O头部
    is_swap = struct.unpack_from('>I', bytes(data[0:4]))[0] != MH_MAGIC_64
    endian = '<' if is_swap else '>'
    
    # 读取头部
    (magic, cputype, cpusubtype, filetype, ncmds, 
     sizeofcmds, flags, reserved) = struct.unpack_from(f'{endian}IIIIIIII', bytes(data[0:32]))
    
    print(f"[*] 架构: arm64, ncmds={ncmds}, sizeofcmds={sizeofcmds}")
    
    # 构建LC_LOAD_DYLIB命令
    dylib_name = b'@executable_path/XingxinShare.dylib\x00'
    dylib_name_aligned = dylib_name + b'\x00' * ((4 - len(dylib_name) % 4) % 4)
    
    # dylib command结构
    cmd_size = 24 + len(dylib_name_aligned)  # dylib_command大小
    
    dylib_cmd = struct.pack(f'{endian}II', LC_LOAD_DYLIB, cmd_size)
    dylib_cmd += struct.pack(f'{endian}III', 
        24,          # dylib name offset
        0x01000000,  # 最低版本  
        0x01000000,  # 兼容版本
    )
    dylib_cmd += dylib_name_aligned
    
    # 在__LINKEDIT区段前插入，或者在末尾追加
    # 最简单: 直接追加到所有load commands后面
    
    # 找到load commands结束位置
    cmds_end = 32 + sizeofcmds
    
    # 构造新数据: header + loadcommands + 新command + segments
    new_data = data[:cmds_end] + dylib_cmd + data[cmds_end:]
    
    # 更新header
    new_ncmds = ncmds + 1
    new_sizeofcmds = sizeofcmds + cmd_size
    new_header = struct.pack(f'{endian}IIIIIIII',
        magic, cputype, cpusubtype, filetype,
        new_ncmds, new_sizeofcmds, flags, reserved)
    new_data[0:32] = new_header
    
    # 更新fat header中的大小（如果适用）
    # (简单处理：先不管)
    
    with open(output_path, 'wb') as f:
        f.write(new_data)
    
    print(f"[✓] 注入成功! 已添加LC_LOAD_DYLIB (@executable_path/XingxinShare.dylib)")
    print(f"    ncmds: {ncmds} -> {new_ncmds}")
    return True

def create_dylib_stub(output_path):
    """创建一个最小化的arm64 dylib（可以加载但不做任何事）"""
    # 使用Python构造一个完整的、有效的arm64 dylib
    
    # arm64 dylib的最小结构:
    # - mach_header_64 (32 bytes)
    # - LC_SEGMENT_64: __PAGEZERO (空)
    # - LC_SEGMENT_64: __TEXT
    # - LC_SEGMENT_64: __DATA
    # - LC_ID_DYLIB
    # - __TEXT,__text section (构造函数)
    # - __LINKEDIT
    
    # 为了简单，使用一个有效的dylib模板
    # 从已有的系统dylib复制一个作为基础（跨平台不行）
    # 手动构建
    
    # 可以用更简单的方法：从`/usr/lib/libobjc.A.dylib`复制? 但Linux没有
    # 
    # 实际上，dylib的load command结构:
    # Mach-O header + segments + sections + linkedit
    
    # 最简单的方案: 使用insert_dylib仅修改二进制，真正的dylib留到macOS编译
    # 或者: 创建一个空的.cpp embed
    
    print("[*] 创建最小dylib模板 (占位用)")
    print("[!] 注意: 这需要真正的arm64 dylib才能工作")
    
    # 创建一个标记文件让用户放入真正的dylib
    with open(output_path, 'w') as f:
        f.write("PLACEHOLDER - 请替换为真正的arm64 dylib\n")
    
    return False

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("用法: python3 inject_macho.py <输入二进制> <输出路径> [dylib名称]")
        sys.exit(1)
    
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    dylib_name = sys.argv[3] if len(sys.argv) > 3 else '@executable_path/XingxinShare.dylib'
    
    if not os.path.exists(input_path):
        print(f"[!] 文件不存在: {input_path}")
        sys.exit(1)
    
    patch_macho(input_path, output_path, dylib_name)
