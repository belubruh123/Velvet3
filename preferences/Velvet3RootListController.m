#import "../headers/HeadersPreferences.h"

@implementation Velvet3RootListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}

	return _specifiers;
}

-(void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	[self setupHeader];
	[self setupFooterVersion];
}

-(void)setupHeader {
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 140)];

    UIImage *image = [UIImage imageNamed:@"velvet-header-icon.png" inBundle:[NSBundle bundleForClass:NSClassFromString(@"Velvet3RootListController")] compatibleWithTraitCollection:nil];
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 30 - 4, self.view.bounds.size.width, 80)];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    [imageView setImage:image];

    [header addSubview:imageView];
	self.table.tableHeaderView = header;
}

-(void)setupFooterVersion {
	NSString *firstLine = [NSString stringWithFormat:@"Velvet %@", PACKAGE_VERSION];

	NSMutableAttributedString *fullFooter = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\nby tallplay \u00b7 after Velvet 2 by NoisyFlake", firstLine]];

	[fullFooter beginEditing];
	[fullFooter addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:18] range:NSMakeRange(0, [firstLine length])];
	[fullFooter endEditing];

	UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 100)];
	footerLabel.font = [UIFont systemFontOfSize:13];
	footerLabel.textColor = UIColor.systemGrayColor;
	footerLabel.numberOfLines = 2;
	footerLabel.attributedText = fullFooter;
	footerLabel.textAlignment = NSTextAlignmentCenter;
	self.table.tableFooterView = footerLabel;
}

-(void)resetSettings {
	[[NSUserDefaults standardUserDefaults] removePersistentDomainForName:@"com.tallplay.velvet3"];
	[self reload];

	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)@"com.tallplay.velvet3/preferenceUpdate", NULL, NULL, YES);
}

-(void)github {
	[self openLink:@"https://github.com/belubruh123/Velvet3"];
}

-(void)reportIssue {
	[self openLink:@"https://github.com/belubruh123/Velvet3/issues"];
}

// Velvet 3 is a derivative work; the donation link stays pointed at the original author.
-(void)paypal {
	[self openLink:@"https://www.paypal.me/NoisyFlake"];
}

-(void)openLink:(NSString *)urlString {
	NSURL *url = [NSURL URLWithString:urlString];
	if (!url) return;

	[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

-(void)setTweakEnabled:(id)value specifier:(PSSpecifier *)specifier {
	[self setPreferenceValue:value specifier:specifier];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Respring" style:UIBarButtonItemStylePlain target:self action:@selector(respring)];
}

-(void)respring {
	pid_t pid;
	const char* args[] = {"sbreload", NULL};
	posix_spawn(&pid, ROOT_PATH("/usr/bin/sbreload"), NULL, NULL, (char* const*)args, NULL);
}
@end
