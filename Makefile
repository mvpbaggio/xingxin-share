include $(THEOS)/makefiles/common.mk

TWEAK_NAME = XingxinShare
XingxinShare_FILES = Tweak.xm
XingxinShare_CFLAGS = -fobjc-arc
XingxinShare_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
