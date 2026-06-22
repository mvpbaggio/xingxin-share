// 纯C + arm64 asm 实现的iOS dylib
// 完全不需要任何Apple SDK头文件

#include <stdint.h>
#include <string.h>

// arm64 objc_msgSend 的 trampoline
// 这个函数签名是: id objc_msgSend(id self, SEL op, ...)
// 用汇编实现满足 arm64 调用约定 (x0=self, x1=sel, ...)
__attribute__((naked)) static id msgSend(id self, const char *selName, ...) {
    __asm__ volatile(
        "mov    x1, x0\n"        // 保存self到x1
        "adr    x0, Lsel\n"      // x0 = selName指针
        "b      _objc_msgSend\n"
        "Lsel:\n"
        ".asciz  \"test\"\n"
        ::: "memory"
    );
    return 0;
}

// 另一种方式: 用dlsym找objc_msgSend
#include <dlfcn.h>

typedef id (*msgSendFunc)(id, void*, ...);

__attribute__((constructor))
static void init() {
    // 啥也不做，只验证dylib能被加载
    const char *msg = "XingxinShare dylib loaded\n";
    // 用write直接输出到syslog
    __asm__ volatile(
        "mov    x0, #1\n"         // stdout
        "adr    x1, Lmsg\n"      
        "mov    x2, #28\n"       // 长度
        "mov    x16, #4\n"       // SYS_write
        "svc    #0x80\n"
        "b      Lend\n"
        "Lmsg: .asciz \"XingxinShare dylib loaded\\n\"\n"
        "Lend:\n"
    );
}
