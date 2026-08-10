@interface PLPlatterView : UIView
@end

@interface NCNotificationSummaryPlatterView : PLPlatterView
@property (nonatomic,retain) UIView *velvetView;
@property (nonatomic,assign) BOOL velvetObserving;
-(void)velvetUpdateStyle;
@end