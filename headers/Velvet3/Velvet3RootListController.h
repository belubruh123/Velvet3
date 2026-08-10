#import <Preferences/PSListController.h>
#import <spawn.h>

@interface Velvet3RootListController : PSListController
-(void)setupHeader;
-(void)setupFooterVersion;
-(void)resetSettings;
-(void)github;
-(void)reportIssue;
-(void)paypal;
-(void)openLink:(NSString *)urlString;
-(void)setTweakEnabled:(id)value specifier:(PSSpecifier *)specifier;
-(void)respring;
@end
