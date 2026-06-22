#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - 文件分享工具

@interface XSFilesHelper : NSObject
+ (NSString *)findFilePathFromVC:(UIViewController *)vc;
+ (void)showShareSheetFromVC:(UIViewController *)vc filePath:(NSString *)filePath;
+ (void)addShareButtonToVC:(UIViewController *)vc;
@end

@implementation XSFilesHelper

+ (NSString *)findFilePathFromVC:(UIViewController *)vc {
    id target = vc;
    // 尝试模型对象
    SEL modelSel = @selector(model);
    SEL fileItemSel = @selector(fileItem);
    SEL fileInfoSel = @selector(fileInfo);
    SEL dataItemSel = @selector(dataItem);
    
    // 属性名列表 - 对应企业微信/行信类的属性
    NSArray *properties = @[
        @"filePath", @"fileUrl", @"fileURL", @"documentURL",
        @"localFilePath", @"downloadPath", @"dataPath",
        @"filePathStr", @"attachPath", @"attachmentPath",
        @"absoluteString", @"relativePath",
        @"url", @"URL", @"path",
        @"currentUrl", @"webUrl", @"fileId",
        @"previewUrl", @"sourceUrl"
    ];
    
    // 尝试直接从VC取
    for (NSString *prop in properties) {
        id val = [target valueForKey:prop];
        if ([val isKindOfClass:[NSString class]] && [val length] > 5) {
            if ([val hasPrefix:@"/"] || [val hasPrefix:@"/var/"]) return val;
        }
        if ([val isKindOfClass:[NSURL class]]) {
            NSString *p = [(NSURL *)val path];
            if (p && [p length] > 5) return p;
        }
    }
    
    // 尝试model对象
    for (SEL sel in @[@selector(model), @selector(fileItem), @selector(fileInfo), @selector(dataItem)]) {
        if ([target respondsToSelector:sel]) {
            id model = ((id (*)(id, SEL))objc_msgSend)(target, sel);
            if ([model isKindOfClass:[NSObject class]]) {
                for (NSString *prop in properties) {
                    id val = [model valueForKey:prop];
                    if ([val isKindOfClass:[NSString class]] && [val length] > 5 && [val hasPrefix:@"/"]) return val;
                    if ([val isKindOfClass:[NSURL class]]) {
                        NSString *p = [(NSURL *)val path];
                        if (p && [p length] > 5) return p;
                    }
                }
            }
        }
    }
    
    return nil;
}

+ (void)showShareSheetFromVC:(UIViewController *)vc filePath:(NSString *)filePath {
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc]
        initWithActivityItems:@[fileURL] applicationActivities:nil];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = vc.view;
        activityVC.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds),
            CGRectGetMidY(vc.view.bounds), 0, 0);
    }
    
    [vc presentViewController:activityVC animated:YES completion:nil];
}

+ (void)addShareButtonToVC:(UIViewController *)vc {
    if (!vc.navigationController || !vc.navigationItem) return;
    
    // 避免重复添加
    for (UIBarButtonItem *item in vc.navigationItem.rightBarButtonItems) {
        if (item.tag == 927) return; // 我们的标记
    }
    
    UIImage *shareImg = [UIImage systemImageNamed:@"square.and.arrow.up"];
    if (!shareImg) {
        // fallback: 用"分享"文字
        UIBarButtonItem *btn = [[UIBarButtonItem alloc] initWithTitle:@"分享"
            style:UIBarButtonItemStylePlain target:[self class] action:@selector(_xs_shareBtnTapped:)];
        btn.tag = 927;
        NSMutableArray *items = [NSMutableArray arrayWithArray:vc.navigationItem.rightBarButtonItems];
        [items insertObject:btn atIndex:0];
        vc.navigationItem.rightBarButtonItems = items;
        return;
    }
    
    UIBarButtonItem *shareItem = [[UIBarButtonItem alloc] initWithImage:shareImg
        style:UIBarButtonItemStylePlain target:[self class] action:@selector(_xs_shareBtnTapped:)];
    shareItem.tag = 927;
    
    NSMutableArray *items = [NSMutableArray arrayWithArray:vc.navigationItem.rightBarButtonItems];
    [items insertObject:shareItem atIndex:0];
    vc.navigationItem.rightBarButtonItems = items;
}

+ (void)_xs_shareBtnTapped:(UIBarButtonItem *)sender {
    // 找到所属的VC
    UIViewController *vc = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.rootViewController) {
            vc = [self _xs_topVC:w.rootViewController];
            break;
        }
    }
    // 从navigationController找
    if (!vc) {
        id resp = sender;
        while (resp) {
            if ([resp isKindOfClass:[UIViewController class]]) {
                vc = resp;
                break;
            }
            resp = [resp nextResponder];
        }
    }
    if (!vc) return;
    
    NSString *filePath = [self findFilePathFromVC:vc];
    if (filePath) {
        [self showShareSheetFromVC:vc filePath:filePath];
    } else {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"提示"
            message:@"未找到文件路径，请先用行信打开文件\n\n找不到试试：\n1. 在聊天中长按文件\n2. 选择「用其他应用打开」\n3. 然后回到本页面再点分享"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:alert animated:YES completion:nil];
    }
}

+ (UIViewController *)_xs_topVC:(UIViewController *)root {
    if ([root presentedViewController]) return [self _xs_topVC:[root presentedViewController]];
    if ([root isKindOfClass:[UITabBarController class]]) return [self _xs_topVC:[(id)root selectedViewController]];
    if ([root isKindOfClass:[UINavigationController class]]) return [self _xs_topVC:[(id)root topViewController]];
    return root;
}

@end

#pragma mark - Hook: 文件预览VC自动加分享按钮

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    
    NSString *cn = NSStringFromClass([self class]);
    
    // 目标类名 - 企业微信/行信文件预览相关的类
    NSArray *targets = @[
        @"WWKEntDiskPreviewImagVC",
        @"WWKFileAttachmentViewController",
        @"WWKFilePreviewController",
        @"WWKDocumentPreviewVC",
        @"QLPreviewController",
        @"WWKWebFilePreviewVC",
        @"WWKEnterpriseFilePreviewVC",
        @"WWKPreviewFileViewController",
        @"WWKFileBrowserViewController",
        @"WWKFileDetailViewController",
        @"WWKDiskFilePreviewController",
        @"FMOCRDocumentDisplayViewController",
        @"WWKTOMainPageViewController"
    ];
    
    for (NSString *t in targets) {
        if ([cn containsString:t]) {
            [XSFilesHelper addShareButtonToVC:self];
            break;
        }
    }
}

%end

#pragma mark - 通用截图方案: 捕获所有视图控制器的文件路径

%hook NSObject

- (id)valueForUndefinedKey:(NSString *)key {
    return nil;
}

%end

__attribute__((constructor))
static void init() {
    NSLog(@"[行信分享] Tweak 已加载!");
}
