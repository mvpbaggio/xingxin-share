// 行信分享导出 Tweak (最小化测试版)
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 标记 - 用来验证dylib是否加载成功
static BOOL xingxin_loaded = NO;

__attribute__((constructor))
static void load() {
    xingxin_loaded = YES;
    NSLog(@"[行信] Tweak loaded successfully");
}
