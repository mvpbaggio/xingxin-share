// 行信分享导出 Tweak
// 编译方式: clang -target arm64-apple-ios14.0 -fobjc-arc -dynamiclib -o XingxinShare.dylib hook_dylib.m -lobjc

#import <objc/runtime.h>
#import <objc/message.h>

// 函数指针声明
static id (*$objc_msgSend)(id, SEL, ...) = (id (*)(id, SEL, ...))objc_msgSend;
static Class (*$objc_getClass)(const char *) = objc_getClass;
static SEL (*$sel_registerName)(const char *) = sel_registerName;
static Method (*$class_getInstanceMethod)(Class, SEL) = class_getInstanceMethod;
static IMP (*$method_getImplementation)(Method) = method_getImplementation;
static void (*$method_setImplementation)(Method, IMP) = method_setImplementation;
static BOOL (*$class_addMethod)(Class, SEL, IMP, const char *) = class_addMethod;
static const void *kShareBtnTag = (const void *)0x927;

#define CLS(name) $objc_getClass(name)
#define SEL(name) $sel_registerName(name)
#define MSG(target, sel) $objc_msgSend((id)(target), sel)
#define MSG1(target, sel, a) $objc_msgSend((id)(target), sel, (id)(a))
#define MSG2(target, sel, a, b) $objc_msgSend((id)(target), sel, (id)(a), (id)(b))
#define MSG3(target, sel, a, b, c) $objc_msgSend((id)(target), sel, (id)(a), (id)(b), (id)(c))
#define MSG4(target, sel, a, b, c, d) $objc_msgSend((id)(target), sel, (id)(a), (id)(b), (id)(c), (id)(d))
#define INT(n) ((id)(uintptr_t)(n))

static IMP orig_viewDidAppear = NULL;

// 查找文件路径
static id findFilePath(id vc) {
    const char *propNames[] = {
        "filePath", "fileUrl", "fileURL", "documentURL",
        "localFilePath", "downloadPath", "dataPath",
        "url", "URL", "path", "filePathStr",
        "fileId", "currentUrl", "previewUrl",
        NULL
    };
    
    for (int i = 0; propNames[i]; i++) {
        SEL sel = $sel_registerName(propNames[i]);
        if ($objc_msgSend(vc, $sel_registerName("respondsToSelector:"), (SEL)sel)) {
            id val = ((id (*)(id, SEL))objc_msgSend)(vc, sel);
            if (val) {
                // 检查是否是NSString
                id isStr = ((id (*)(id, SEL))objc_msgSend)(CLS("NSString"), SEL("class"));
                if (((id (*)(id, SEL))objc_msgSend)(val, SEL("isKindOfClass:"), isStr)) {
                    id hasPrefix = ((id (*)(id, SEL, id))objc_msgSend)(val, SEL("hasPrefix:"), (id)@"/");
                    if (hasPrefix == (id)1) return val;
                }
            }
        }
    }
    
    // 尝试取model/fileItem属性
    SEL modelSels[] = {SEL("model"), SEL("fileItem"), SEL("fileInfo"), SEL("dataItem")};
    for (int i = 0; i < 4; i++) {
        if (((id (*)(id, SEL))objc_msgSend)(vc, SEL("respondsToSelector:"), modelSels[i])) {
            id model = ((id (*)(id, SEL))objc_msgSend)(vc, modelSels[i]);
            if (model) {
                id result = findFilePath(model);
                if (result) return result;
            }
        }
    }
    
    return NULL;
}

// 分享按钮被点击
static void shareTapped(id self, SEL _cmd, id sender) {
    // 找顶层VC
    id app = ((id (*)(Class, SEL))objc_msgSend)(CLS("UIApplication"), SEL("sharedApplication"));
    id keyWindow = ((id (*)(id, SEL))objc_msgSend)(app, SEL("keyWindow"));
    id rootVC = ((id (*)(id, SEL))objc_msgSend)(keyWindow, SEL("rootViewController"));
    
    id topVC = rootVC;
    while (1) {
        id presented = ((id (*)(id, SEL))objc_msgSend)(topVC, SEL("presentedViewController"));
        if (!presented) break;
        topVC = presented;
    }
    
    // 如果是UINavigationController
    id navClass = CLS("UINavigationController");
    if (((id (*)(id, SEL, id))objc_msgSend)(topVC, SEL("isKindOfClass:"), navClass)) {
        topVC = ((id (*)(id, SEL))objc_msgSend)(topVC, SEL("topViewController"));
    }
    
    // 找文件路径
    id filePath = findFilePath(topVC);
    
    if (filePath) {
        // NSURL *fileURL = [NSURL fileURLWithPath:filePath];
        id fileURL = ((id (*)(Class, SEL, id))objc_msgSend)(CLS("NSURL"), SEL("fileURLWithPath:"), filePath);
        
        // UIActivityViewController
        id items = ((id (*)(Class, SEL, id))objc_msgSend)(CLS("NSArray"), SEL("arrayWithObjects:"), fileURL, NULL);
        id activityVC = ((id (*)(id, SEL))objc_msgSend)(CLS("UIActivityViewController"), SEL("alloc"));
        activityVC = ((id (*)(id, SEL, id, id))objc_msgSend)(activityVC, SEL("initWithActivityItems:applicationActivities:"), items, NULL);
        
        // iPad popover
        id device = ((id (*)(Class, SEL))objc_msgSend)(CLS("UIDevice"), SEL("currentDevice"));
        id idiom = ((id (*)(id, SEL))objc_msgSend)(device, SEL("userInterfaceIdiom"));
        if (idiom == INT(1)) { // UIUserInterfaceIdiomPad
            id popover = ((id (*)(id, SEL))objc_msgSend)(activityVC, SEL("popoverPresentationController"));
            id view = ((id (*)(id, SEL))objc_msgSend)(topVC, SEL("view"));
            ((void (*)(id, SEL, id))objc_msgSend)(popover, SEL("setSourceView:"), view);
            id bounds = ((id (*)(id, SEL))objc_msgSend)(view, SEL("bounds"));
            double midX = ((double (*)(id, SEL))objc_msgSend)(bounds, SEL("size")) / 2;
            // 简化为居中
            ((void (*)(id, SEL, CGRect))objc_msgSend)(popover, SEL("setSourceRect:"), 
                CGRectMake(200, 200, 0, 0));
        }
        
        ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(topVC, SEL("presentViewController:animated:completion:"), activityVC, 1, NULL);
    } else {
        id alert = ((id (*)(id, SEL))objc_msgSend)(CLS("UIAlertController"), SEL("alloc"));
        alert = ((id (*)(id, SEL, id, id, int))objc_msgSend)(alert, SEL("initWithTitle:message:preferredStyle:"), @"提示", @"未找到文件路径，请先在行信中打开文件", 1);
        id okAction = ((id (*)(id, SEL))objc_msgSend)(CLS("UIAlertAction"), SEL("alloc"));
        okAction = ((id (*)(id, SEL, id, int, id))objc_msgSend)(okAction, SEL("initWithTitle:style:handler:"), @"确定", 0, NULL);
        ((void (*)(id, SEL, id))objc_msgSend)(alert, SEL("addAction:"), okAction);
        ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(topVC, SEL("presentViewController:animated:completion:"), alert, 1, NULL);
    }
}

// Hook后的viewDidAppear
static void hooked_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))orig_viewDidAppear)(self, _cmd, animated);
    
    // 检查类名
    id className = ((id (*)(id, SEL))objc_msgSend)(self, SEL("description"));
    if (className) {
        const char *cn = ((const char *(*)(id, SEL))objc_msgSend)(className, SEL("UTF8String"));
        if (cn) {
            const char *targets[] = {
                "EntDisk", "FilePreview", "FileAttachment",
                "QLPreview", "DocumentPreview", "DiskPreview",
                "WWKFile", "WWKEnt", "WWKDisk",
                "TOMainPage", "TOWebView", "TOTemplate",
                "FMOCRDocument", "PreviewFile", "FileBrowser",
                NULL
            };
            
            for (int i = 0; targets[i]; i++) {
                if (strstr(cn, targets[i])) {
                    // 添加分享按钮
                    id navItem = ((id (*)(id, SEL))objc_msgSend)(self, SEL("navigationItem"));
                    if (navItem) {
                        id rightBtns = ((id (*)(id, SEL))objc_msgSend)(navItem, SEL("rightBarButtonItems"));
                        if (rightBtns) {
                            id enumerator = ((id (*)(id, SEL))objc_msgSend)(rightBtns, SEL("objectEnumerator"));
                            id item;
                            while ((item = ((id (*)(id, SEL))objc_msgSend)(enumerator, SEL("nextObject")))) {
                                id tag = ((id (*)(id, SEL))objc_msgSend)(item, SEL("tag"));
                                if (tag == INT(0x927)) return; // 已添加
                            }
                        }
                        
                        // 创建分享按钮
                        id shareImg = ((id (*)(Class, SEL, id))objc_msgSend)(CLS("UIImage"), SEL("systemImageNamed:"), @"square.and.arrow.up");
                        id btn;
                        if (shareImg) {
                            btn = ((id (*)(id, SEL))objc_msgSend)(CLS("UIBarButtonItem"), SEL("alloc"));
                            btn = ((id (*)(id, SEL, id, int, id, SEL))objc_msgSend)(btn, 
                                SEL("initWithImage:style:target:action:"),
                                shareImg, 0, self, SEL("_xingxin_shareTapped:"));
                        } else {
                            btn = ((id (*)(id, SEL))objc_msgSend)(CLS("UIBarButtonItem"), SEL("alloc"));
                            btn = ((id (*)(id, SEL, id, int, id, SEL))objc_msgSend)(btn,
                                SEL("initWithTitle:style:target:action:"),
                                @"分享", 0, self, SEL("_xingxin_shareTapped:"));
                        }
                        
                        ((void (*)(id, SEL, id))objc_msgSend)(btn, SEL("setTag:"), INT(0x927));
                        id items = ((id (*)(id, SEL, id))objc_msgSend)(rightBtns, SEL("arrayByAddingObject:"), btn);
                        ((void (*)(id, SEL, id))objc_msgSend)(navItem, SEL("setRightBarButtonItems:"), items);
                    }
                    break;
                }
            }
        }
    }
}

__attribute__((constructor))
static void load() {
    // 添加_ xingxin_shareTapped: 方法
    Class vcClass = CLS("UIViewController");
    if (vcClass) {
        $class_addMethod(vcClass, SEL("_xingxin_shareTapped:"), (IMP)shareTapped, "v@:@");
        
        // Hook viewDidAppear:
        Method m = $class_getInstanceMethod(vcClass, SEL("viewDidAppear:"));
        if (m) {
            orig_viewDidAppear = $method_getImplementation(m);
            $method_setImplementation(m, (IMP)hooked_viewDidAppear);
        }
    }
}
