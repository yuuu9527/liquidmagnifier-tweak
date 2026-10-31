// lqm —— 液态放大镜的触发命令
// 用法: lqm [toggle|show|hide]     默认 toggle
// 通过 Darwin 通知唤醒前台进程里的插件，不需要插件自己有 UI。
#include <CoreFoundation/CoreFoundation.h>
#include <string.h>

int main(int argc, char **argv) {
    const char *action = (argc > 1) ? argv[1] : "toggle";
    const char *name = "com.yu.liquidmagnifier.toggle";

    if (strcmp(action, "show") == 0) {
        name = "com.yu.liquidmagnifier.show";
    } else if (strcmp(action, "hide") == 0) {
        name = "com.yu.liquidmagnifier.hide";
    } else if (strcmp(action, "toggle") != 0) {
        fprintf(stderr, "usage: lqm [toggle|show|hide]\n");
        return 2;
    }

    CFStringRef notification = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingUTF8);
    if (!notification) return 1;

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         notification, NULL, NULL, true);
    CFRelease(notification);

    fprintf(stdout, "posted %s\n", name);
    return 0;
}
