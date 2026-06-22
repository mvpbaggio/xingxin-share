// 行信分享导出 + 复制限制解除 Tweak
// 编译: clang -target arm64-apple-ios14.0 -fobjc-arc -dynamiclib -o XingxinShare.dylib hook_dylib.m

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - 文件分享辅助函数

static NSString *xingxin_FindFilePath(id vc) {
    NSArray *props = @[@"filePath", @"fileUrl", @"fileURL", @"documentURL", 
                       @"localFilePath", @"downloadPath", @"dataPath",
                       @"url", @"URL", @"path", @"filePathStr"];
    for (NSString *prop in props) {
        @try {
            id val = [vc valueForKey:prop];
            if ([val isKindOfClass:[NSString class]] && [val length] > 5 && [val hasPrefix:@"/"])
                return val;
            if ([val isKindOfClass:[NSURL class]]) {
                NSString *p = [(NSURL *)val path];
                if (p.length > 5) return p;
            }
        } @catch (NSException *e) {}
    }
    NSArray *modelSels = @[@"model", @"fileItem", @"fileInfo", @"dataItem"];
    for (NSString *sel in modelSels) {
        if ([vc respondsToSelector:NSSelectorFromString(sel)]) {
            id model = [vc valueForKey:sel];
            if (model) {
                NSString *found = xingxin_FindFilePath(model);
                if (found) return found;
            }
        }
    }
    return nil;
}

static void xingxin_ShowShareSheet(id vc, NSString *filePath) {
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    UIActivityViewController *avc = [[UIActivityViewController alloc]
        initWithActivityItems:@[fileURL] applicationActivities:nil];
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        avc.popoverPresentationController.sourceView = [vc view];
        CGRect b = [vc view].bounds;
        avc.popoverPresentationController.sourceRect = CGRectMake(
            b.origin.x + b.size.width / 2, b.origin.y + b.size.height / 2, 0, 0);
    }
    [vc presentViewController:avc animated:YES completion:nil];
}

static void xingxin_AddShareButton(UIViewController *vc) {
    if (!vc.navigationItem) return;
    for (UIBarButtonItem *item in vc.navigationItem.rightBarButtonItems)
        if (item.tag == 927) return;
    
    UIImage *img = [UIImage systemImageNamed:@"square.and.arrow.up"];
    UIBarButtonItem *btn = img ?
        [[UIBarButtonItem alloc] initWithImage:img style:UIBarButtonItemStylePlain
                                        target:nil action:@selector(xingxin_shareTapped:)] :
        [[UIBarButtonItem alloc] initWithTitle:@"分享" style:UIBarButtonItemStylePlain
                                        target:nil action:@selector(xingxin_shareTapped:)];
    btn.tag = 927;
    NSMutableArray *items = [NSMutableArray arrayWithArray:vc.navigationItem.rightBarButtonItems];
    [items insertObject:btn atIndex:0];
    vc.navigationItem.rightBarButtonItems = items;
}

#pragma mark - 分享 Hook

static void (*orig_viewDidAppear)(id, SEL, BOOL);
static void hooked_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    ((void (*)(UIViewController *, SEL, BOOL))orig_viewDidAppear)(self, _cmd, animated);
    NSString *cn = NSStringFromClass(self.class);
    NSArray *targets = @[@"EntDisk", @"FilePreview", @"FileAttachment",
                          @"QLPreview", @"DocumentPreview", @"DiskPreview",
                          @"WWKFile", @"WWKEnt", @"WWKDisk",
                          @"TOMainPage", @"TOWebView", @"TOTemplate",
                          @"FMOCRDocument", @"PreviewFile", @"FileBrowser"];
    for (NSString *t in targets)
        if ([cn containsString:t]) { xingxin_AddShareButton(self); break; }
}

static void xingxin_shareTapped(id self, SEL _cmd, id sender) {
    UIWindow *kw = UIApplication.sharedApplication.keyWindow;
    UIViewController *top = kw.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:UINavigationController.class])
        top = [(UINavigationController *)top topViewController];
    
    NSString *fp = xingxin_FindFilePath(top);
    if (fp) {
        xingxin_ShowShareSheet(top, fp);
    } else {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"提示"
            message:@"未找到文件路径\n请先打开文件" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:a animated:YES completion:nil];
    }
}

#pragma mark - 复制限制解除

// 保存每个类的原始 canPerformAction IMP
static NSMutableDictionary *origCanPerformMap = nil;
static NSMutableDictionary *origCopyMap = nil;

static BOOL xingxin_canPerformAction_hook(id self, SEL _cmd, SEL action, id sender) {
    // 强制允许复制/剪切
    if (action == @selector(copy:) || action == @selector(cut:))
        return YES;
    
    // 调原始实现
    Class cls = object_getClass(self);
    NSValue *key = [NSValue valueWithPointer:(void *)cls];
    BOOL (*orig)(id, SEL, SEL, id) = NULL;
    if (origCanPerformMap) {
        orig = (__bridge void *)[origCanPerformMap objectForKey:key];
    }
    if (orig)
        return orig(self, _cmd, action, sender);
    return [self respondsToSelector:action];
}

static void xingxin_copy_hook(id self, SEL _cmd, id sender) {
    // 优先调原始copy，看会不会写剪贴板
    Class cls = object_getClass(self);
    NSValue *key = [NSValue valueWithPointer:(void *)cls];
    void (*orig)(id, SEL, id) = NULL;
    if (origCopyMap) {
        orig = (__bridge void *)[origCopyMap objectForKey:key];
    }
    
    NSString *origText = nil;
    if (orig) {
        orig(self, _cmd, sender);
        // 检查剪贴板有没有被写进去
        origText = [UIPasteboard generalPasteboard].string;
    }
    
    // 如果没写进去（被拦截了），手动拿文字写
    if (origText.length == 0) {
        NSString *text = nil;
        if ([self respondsToSelector:@selector(text)])
            text = [self performSelector:@selector(text)];
        if (!text && [self respondsToSelector:@selector(attributedText)])
            text = [[self valueForKey:@"attributedText"] string];
        
        // 尝试获取选中文字
        UITextRange *range = nil;
        if ([self respondsToSelector:@selector(selectedTextRange)])
            range = [self valueForKey:@"selectedTextRange"];
        if (range && [self respondsToSelector:@selector(textInRange:)]) {
            NSString *selText = ((NSString *(*)(id, SEL, UITextRange *))[self methodForSelector:@selector(textInRange:)])(self, @selector(textInRange:), range);
            if (selText.length > 0) text = selText;
        }
        
        if (text.length > 0) {
            [UIPasteboard generalPasteboard].string = text;
            NSLog(@"[行信] copy bypass: 已复制 %lu 字符", (unsigned long)text.length);
        }
    }
}

static IMP xingxin_ReplaceMethod(Class cls, SEL sel, IMP newImpl) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NULL;
    return method_setImplementation(m, newImpl);
}

static void xingxin_HookTextClass(Class cls) {
    if (!cls) return;
    
    // 初始化map
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        origCanPerformMap = [NSMutableDictionary dictionary];
        origCopyMap = [NSMutableDictionary dictionary];
    });
    
    // Hook canPerformAction:
    SEL sel1 = @selector(canPerformAction:withSender:);
    Method m1 = class_getInstanceMethod(cls, sel1);
    if (m1) {
        NSValue *key = [NSValue valueWithPointer:(void *)cls];
        origCanPerformMap[key] = (__bridge id)(void *)method_getImplementation(m1);
        method_setImplementation(m1, (IMP)xingxin_canPerformAction_hook);
        NSLog(@"[行信] hook canPerformAction: on %s", class_getName(cls));
    }
    
    // Hook copy:
    SEL sel2 = @selector(copy:);
    Method m2 = class_getInstanceMethod(cls, sel2);
    if (m2) {
        NSValue *key = [NSValue valueWithPointer:(void *)cls];
        origCopyMap[key] = (__bridge id)(void *)method_getImplementation(m2);
        method_setImplementation(m2, (IMP)xingxin_copy_hook);
        NSLog(@"[行信] hook copy: on %s", class_getName(cls));
    }
}

#pragma mark - 入口

__attribute__((constructor))
static void load() {
    // 1. 分享按钮回调
    class_addMethod(UIViewController.class, @selector(xingxin_shareTapped:),
                    (IMP)xingxin_shareTapped, "v@:@");
    
    // 2. Hook viewDidAppear:
    Method m0 = class_getInstanceMethod(UIViewController.class, @selector(viewDidAppear:));
    if (m0) {
        orig_viewDidAppear = (void (*)(id, SEL, BOOL))method_getImplementation(m0);
        method_setImplementation(m0, (IMP)hooked_viewDidAppear);
    }
    
    // 3. 复制限制解除 - Hook所有已知文本类
    // 企业微信/行信常用文本类
    NSArray *textClasses = @[
        @"WKTextView", @"WKWebView", @"WKTextField",
        @"WWKTextView", @"WWKWebView", @"WWKTextField",
        @"MMTextView", @"MMWebView",
        @"WKContentView", @"WKTextInteraction",
    ];
    for (NSString *cn in textClasses) {
        Class cls = objc_getClass(cn.UTF8String);
        if (cls) xingxin_HookTextClass(cls);
    }
    
    // 4. 兜底：hook UITextView 和 UIResponder
    xingxin_HookTextClass(UITextView.class);
    xingxin_HookTextClass(UITextField.class);
    xingxin_HookTextClass(UIResponder.class);
    xingxin_HookTextClass(UIWebView.class);
    
    NSLog(@"[行信] Tweak loaded (分享+复制解除)");
}
