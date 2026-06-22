; Arm64 bare-metal dylib
; 编译: clang -target arm64-apple-ios -nostdlib -dynamiclib -o XingxinShare.dylib tweak_bare.s

.section __TEXT,__text
.align 2

; __attribute__((constructor))
.globl _init
_init:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    
    ; 找 objc_getClass("UIViewController")
    adrp x0, L_UIViewController@PAGE
    add x0, x0, L_UIViewController@PAGEOFF
    bl _objc_getClass
    
    ; 找 sel_registerName("viewDidAppear:")
    adrp x0, L_viewDidAppear@PAGE
    add x0, x0, L_viewDidAppear@PAGEOFF
    bl _sel_registerName
    
    ; 找 class_getInstanceMethod(UIViewController, viewDidAppear:)
    ; class在x0还在, sel也在x0... 重新加载
    adrp x0, L_UIViewController@PAGE
    add x0, x0, L_UIViewController@PAGEOFF
    bl _objc_getClass
    mov x19, x0                 ; x19 = UIViewController class
    
    adrp x0, L_viewDidAppear@PAGE
    add x0, x0, L_viewDidAppear@PAGEOFF
    bl _sel_registerName
    mov x1, x0                  ; x1 = sel
    mov x0, x19                 ; x0 = class
    bl _class_getInstanceMethod
    
    ; method_setImplementation(method, hooked_impl)
    mov x19, x0                 ; x19 = method
    adrp x0, L_hooked_impl@PAGE
    add x0, x0, L_hooked_impl@PAGEOFF
    bl _hooked_impl             ; 获取hooked函数地址
    mov x1, x0                  ; x1 = IMP
    mov x0, x19                 ; x0 = method
    bl _method_setImplementation
    
    ldp x29, x30, [sp], #16
    ret

; Hook替换的实现
.globl _hooked_impl
_hooked_impl:
    ; 调用原始的viewDidAppear
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ; 保存参数
    stp x0, x1, [sp, #-16]!
    
    ; 调用 original
    ; ... (简化)
    
    ldp x0, x1, [sp], #16
    
    ; 添加分享按钮逻辑
    ; 创建UIBarButtonItem
    ; ... (简化)
    
    ldp x29, x30, [sp], #16
    ret

; 字符串常量
.section __TEXT,__cstring
L_UIViewController:
.asciz "UIViewController"
L_viewDidAppear:
.asciz "viewDidAppear:"
L_shareBtnTag:
.asciz "927"

; dylib信息
.section __TEXT,__info_plist
.asciz "XingxinShare"

; 符号表
.subsections_via_symbols
