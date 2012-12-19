#import "UIAppUtils.h"

void showAlert(NSString *title, NSString *msg) {
    [[[[UIAlertView alloc] initWithTitle:title message:msg delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];
}