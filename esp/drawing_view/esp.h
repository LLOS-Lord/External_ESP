#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Core/GameLogic.h"

struct ESPBox {
    Vector3 pos;
    CGFloat width;
    CGFloat height;
};

@interface ESP_View : UIView

- (instancetype)init;
- (void)update_data;
@end
