#import <Preferences/PSListController.h>
#import "Velvet3PreviewView.h"

@interface Velvet3PreviewController : PSListController

@property (nonatomic,copy) NSString * identifier;
@property (nonatomic,copy) NSString * identifierName;
@property (nonatomic,retain) Velvet3PreviewView *preview;

- (NSMutableArray*)visibleSpecifiersFromPlist:(NSString*)plist;
- (BOOL)appSettingForKeyExists:(NSString *)key;

@end