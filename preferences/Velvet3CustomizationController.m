#import "../headers/HeadersPreferences.h"

@implementation Velvet3CustomizationController

- (NSArray *)specifiers {
	if (!_specifiers) {
        _specifiers = [self visibleSpecifiersFromPlist:[NSString stringWithFormat:@"Custom%@", self.currentKey]];
	}

	return _specifiers;
}

@end