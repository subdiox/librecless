include $(THEOS)/makefiles/common.mk

TWEAK_NAME = librecless
librecless_FILES = Tweak.xm
librecless_FRAMEWORKS = CoreTelephony AudioToolbox

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 mediaserverd"
