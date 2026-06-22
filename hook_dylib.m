// 行信分享导出 Tweak (兼容ARM64 ARC)
// 编译: clang -target arm64-apple-ios14.0 -fobjc-arc -dynamiclib -o XingxinShare.dylib hook_dylib.m

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - 辅助函数

static NSString *xingxin_FindFilePath(id vc) {
    // 常见文件路径属性名
    NSArray *props = @[@"filePath", @"fileUrl", @"fileURL", @"documentURL", 
                       @"localFilePath", @"downloadPath", @"dataPath",
                       @"url", @"URL", @"path", @"filePathStr"];
    
    for (NSString *prop in props) {
        @try {
            id val = [vc valueForKey:prop];
            if ([val isKindOfClass:[NSString class]] && [val length] > 5 && [val hasPrefix:@"/"]) {
                return val;
            }
            if ([val isKindOfClass:[NSURL class]]) {
                NSString *p = [(NSURL *)val path];
                if (p.length > 5) return p;
            }
        } @catch (NSException *e) {}
    }
    
    // 尝试model对象
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
        avc.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX([vc view].bounds),
            CGRectGetMidY([vc view].bounds), 0, 0);
    }
    
    [vc presentViewController:avc animated:YES completion:nil];
}

static void xingxin_AddShareButton(UIViewController *vc) {
    if (!vc.navigationItem) return;
    
    // 检查是否已有
    for (UIBarButtonItem *item in vc.navigationItem.rightBarButtonItems) {
        if (item.tag == 927) return;
    }
    
    UIImage *img = [UIImage systemImageNamed:@"square.and.arrow.up"];
    UIBarButtonItem *btn;
    if (img) {
        btn = [[UIBarButtonItem alloc] initWithImage:img style:UIBarButtonItemStylePlain
                                              target:nil action:@selector(xingxin_shareTapped:)];
    } else {
        btn = [[UIBarButtonItem alloc] initWithTitle:@"分享" style:UIBarButtonItemStylePlain
                                              target:nil action:@selector(xingxin_shareTapped:)];
    }
    btn.tag = 927;
    
    NSMutableArray *items = [NSMutableArray arrayWithArray:vc.navigationItem.rightBarButtonItems];
    [items insertObject:btn atIndex:0];
    vc.navigationItem.rightBarButtonItems = items;
}

// Hook: viewDidAppear
static void (*orig_viewDidAppear)(id, SEL, BOOL);
static void hooked_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    ((void (*)(UIViewController *, SEL, BOOL))orig_viewDidAppear)(self, _cmd, animated);
    
    NSString *cn = NSStringFromClass(self.class);
    NSArray *targets = @[@"EntDisk", @"FilePreview", @"FileAttachment",
                          @"QLPreview", @"DocumentPreview", @"DiskPreview",
                          @"WWKFile", @"WWKEnt", @"WWKDisk",
                          @"TOMainPage", @"TOWebView", @"TOTemplate",
                          @"FMOCRDocument", @"PreviewFile", @"FileBrowser"];
    
    for (NSString *t in targets) {
        if ([cn containsString:t]) {
            xingxin_AddShareButton(self);
            break;
        }
    }
}

// 分享按钮回调
static void xingxin_shareTapped(id self, SEL _cmd, id sender) {
    // 找顶层VC
    UIWindow *keyWindow = UIApplication.sharedApplication.keyWindow;
    UIViewController *topVC = keyWindow.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    if ([topVC isKindOfClass:UINavigationController.class]) {
        topVC = [(UINavigationController *)topVC topViewController];
    }
    
    NSString *filePath = xingxin_FindFilePath(topVC);
    if (filePath) {
        xingxin_ShowShareSheet(topVC, filePath);
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
            message:@"未找到文件路径\n请先在行信中打开文件再试" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [topVC presentViewController:alert animated:YES completion:nil];
    }
}

__attribute__((constructor))
static void load() {
    // Register the shareTapped method on UIViewController
    Class vcClass = UIViewController.class;
    class_addMethod(vcClass, @selector(xingxin_shareTapped:), (IMP)xingxin_shareTapped, "v@:@");
    
    // Hook viewDidAppear:
    Method m = class_getInstanceMethod(vcClass, @selector(viewDidAppear:));
    if (m) {
        orig_viewDidAppear = (void (*)(id, SEL, BOOL))method_getImplementation(m);
        method_setImplementation(m, (IMP)hooked_viewDidAppear);
    }
    
    NSLog(@"[行信分享] Tweak loaded");
}
