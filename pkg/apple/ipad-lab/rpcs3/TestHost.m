#import <UIKit/UIKit.h>
@interface PS3TestScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation PS3TestScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options
{
   self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
   self.window.rootViewController = [[UIViewController alloc] init];
   [self.window makeKeyAndVisible];
}
@end
@interface PS3TestDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation PS3TestDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options
{
   UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
   configuration.delegateClass = PS3TestScene.class; return configuration;
}
@end
int main(int argc, char **argv)
{ @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(PS3TestDelegate.class)); } }
