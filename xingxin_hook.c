#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <objc/message.h>

// Runtime类型定义
typedef id (*objc_msgSend_func)(id, SEL, ...);
typedef Class (*objc_getClass_func)(const char *);
typedef SEL (*sel_registerName_func)(const char *);
typedef BOOL (*class_addMethod_func)(Class, SEL, IMP, const char *);
typedef IMP (*class_replaceMethod_func)(Class, SEL, IMP, const char *);
typedef Method (*class_getInstanceMethod_func)(Class, SEL);
typedef void (*method_exchangeImplementations_func)(Method, Method);
typedef id (*objc_getAssociatedObject_func)(id, const void *);
typedef void (*objc_setAssociatedObject_func)(id, const void *, id, unsigned long);

// dlsym 句柄
static void *libobjc = NULL;
static objc_msgSend_func msgSend = NULL;
static objc_getClass_func getClass = NULL;
static sel_registerName_func regSel = NULL;
static class_addMethod_func addMethod = NULL;
static class_replaceMethod_func replaceMethod = NULL;
static class_getInstanceMethod_func getInstMethod = NULL;
static method_exchangeImplementations_func exchMethods = NULL;

// 辅助宏
#define $msgSend(msgSend, self, sel, ...) msgSend((id)(self), sel, ##__VA_ARGS__)
#define $class(name) getClass(name)
#define $sel(name) regSel(name)
#define $imp(name) ((IMP)name)

// ---- 分享按钮回调 ----
static void shareButtonTapped(id self, SEL _cmd, id sender) {
    // 查找当前UIViewController
    id app = $msgSend(msgSend, $class("UIApplication"), $sel("sharedApplication"));
    id keyWindow = $msgSend(msgSend, app, $sel("keyWindow"));
    id rootVC = $msgSend(msgSend, keyWindow, $sel("rootViewController"));
    
    // 找top VC
    id topVC = rootVC;
    while (1) {
        id presented = $msgSend(msgSend, topVC, $sel("presentedViewController"));
        if (presented == nil) break;
        topVC = presented;
    }
    if ($msgSend(msgSend, topVC, $sel("isKindOfClass:"), $class("UINavigationController"))) {
        topVC = $msgSend(msgSend, topVC, $sel("topViewController"));
    }
    
    // 尝试从VC的各种属性获取文件路径
    __block id filePath = nil;
    NSArray *propNames = @[@"filePath", @"fileUrl", @"fileURL", @"documentURL", 
                          @"localFilePath", @"downloadPath", @"dataPath",
                          @"url", @"URL", @"path", @"filePathStr"];
    
    for (NSString *prop in propNames) {
        @try {
            id val = [topVC valueForKey:prop];
            if ([val isKindOfClass:[NSString class]] && [val length] > 10) {
                if ([val hasPrefix:@"/"]) {
                    filePath = val;
                    break;
                }
            } else if ([val isKindOfClass:[NSURL class]]) {
                NSString *p = [val path];
                if (p && [p length] > 10) {
                    filePath = p;
                    break;
                }
            }
        } @catch (NSException *e) { }
    }
    
    if (filePath) {
        NSURL *fileURL = [NSURL fileURLWithPath:filePath];
        id activityVC = [[$class("UIActivityViewController") alloc] 
            initWithActivityItems:@[fileURL] applicationActivities:nil];
        
        // iPad适配
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
            [activityVC popoverPresentationController].sourceView = [topVC view];
            [activityVC popoverPresentationController].sourceRect = CGRectMake(
                CGRectGetMidX([[topVC view] bounds]), 
                CGRectGetMidY([[topVC view] bounds]), 0, 0);
        }
        
        [topVC presentViewController:activityVC animated:YES completion:nil];
    } else {
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"提示" 
            message:@"未找到文件路径，请先在行信中打开文件再试" 
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [topVC presentViewController:alert animated:YES completion:nil];
    }
}

// ---- Hook viewDidAppear ----
static void (*orig_viewDidAppear)(id, SEL, BOOL);
static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    
    // 检查类名
    id className = $msgSend(msgSend, self, $sel("description"));
    if (className) {
        const char *cn = $msgSend(msgSend, className, $sel("UTF8String"));
        if (cn) {
            // 目标类名关键词
            const char *keywords[] = {
                "EntDiskPreview", "FilePreview", "FileAttachment",
                "QLPreviewController", "DocumentPreview", "DiskPreview",
                "WWKFile", "WWKEnt", "WWKDisk",
                "TOMainPage", "TOWebView", "TOTemplate",
                "FMOCRDocument", "PreviewFile", "FileBrowser"
            };
            BOOL shouldHook = NO;
            for (int i = 0; i < sizeof(keywords)/sizeof(keywords[0]); i++) {
                if (strstr(cn, keywords[i]) != NULL) {
                    shouldHook = YES;
                    break;
                }
            }
            
            if (shouldHook) {
                // 添加分享按钮
                id navItem = $msgSend(msgSend, self, $sel("navigationItem"));
                if (navItem) {
                    id rightItems = $msgSend(msgSend, navItem, $sel("rightBarButtonItems"));
                    if (rightItems) {
                        // 检查是否已添加
                        for (id item in rightItems) {
                            id tag = $msgSend(msgSend, item, $sel("tag"));
                            if (tag == (id)927) return;
                        }
                    }
                    
                    id shareImg = $msgSend(msgSend, $class("UIImage"), $sel("systemImageNamed:"), @"square.and.arrow.up");
                    id shareBtn;
                    if (shareImg) {
                        shareBtn = $msgSend(msgSend, 
                            $class("UIBarButtonItem"), 
                            $sel("alloc"));
                        shareBtn = $msgSend(msgSend, shareBtn, 
                            $sel("initWithImage:style:target:action:"), 
                            shareImg, (id)0, self, $sel("_xingxin_shareTapped:"));
                    } else {
                        shareBtn = $msgSend(msgSend, 
                            $class("UIBarButtonItem"), 
                            $sel("alloc"));
                        shareBtn = $msgSend(msgSend, shareBtn, 
                            $sel("initWithTitle:style:target:action:"),
                            @"分享", (id)0, self, $sel("_xingxin_shareTapped:"));
                    }
                    
                    if (shareBtn) {
                        $msgSend(msgSend, shareBtn, $sel("setTag:"), (id)927);
                        id items = $msgSend(msgSend, rightItems, $sel("arrayByAddingObject:"), shareBtn);
                        $msgSend(msgSend, navItem, $sel("setRightBarButtonItems:"), items);
                    }
                }
            }
        }
    }
}

// ---- 初始化 ----
__attribute__((constructor))
static void init() {
    // 加载ObjC运行时
    libobjc = dlopen("/usr/lib/libobjc.A.dylib", RTLD_LAZY);
    if (!libobjc) {
        fprintf(stderr, "[行信分享] 无法加载libobjc\n");
        return;
    }
    
    msgSend = (objc_msgSend_func)dlsym(libobjc, "objc_msgSend");
    getClass = (objc_getClass_func)dlsym(libobjc, "objc_getClass");
    regSel = (sel_registerName_func)dlsym(libobjc, "sel_registerName");
    getInstMethod = (class_getInstanceMethod_func)dlsym(libobjc, "class_getInstanceMethod");
    exchMethods = (method_exchangeImplementations_func)dlsym(libobjc, "method_exchangeImplementations");
    
    if (!msgSend || !getClass || !regSel || !getInstMethod || !exchMethods) {
        fprintf(stderr, "[行信分享] 符号加载失败\n");
        return;
    }
    
    // Hook UIViewController
    Class vcClass = getClass("UIViewController");
    if (vcClass) {
        SEL origSel = regSel("viewDidAppear:");
        Method origMethod = getInstMethod(vcClass, origSel);
        if (origMethod) {
            orig_viewDidAppear = (void (*)(id, SEL, BOOL))method_getImplementation(origMethod);
            
            // 添加我们的方法
            class_addMethod(vcClass, regSel("_xingxin_shareTapped:"), 
                          (IMP)shareButtonTapped, "v@:@");
            
            // Hook viewDidAppear
            method_setImplementation(origMethod, (IMP)hook_viewDidAppear);
            
            NSLog(@"[行信分享] Tweak加载成功 - Hook了UIViewController");
        }
    }
}
