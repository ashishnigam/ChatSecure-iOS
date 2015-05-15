//
//  OTRBaseLoginViewController.m
//  ChatSecure
//
//  Created by David Chiles on 5/12/15.
//  Copyright (c) 2015 Chris Ballinger. All rights reserved.
//

#import "OTRBaseLoginViewController.h"
#import "Strings.h"
#import "OTRColors.h"
#import "OTRCertificatePinning.h"
#import "OTRConstants.h"
#import "OTRXMPPError.h"
#import "SIAlertView.h"
#import "UIAlertView+Blocks.h"

@interface OTRBaseLoginViewController ()

@property (nonatomic,strong) SIAlertView * certAlertView;

@end

@implementation OTRBaseLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.loginCreateButtonItem = [[UIBarButtonItem alloc] initWithTitle:LOGIN_STRING style:UIBarButtonItemStylePlain target:self action:@selector(loginButtonPressed:)];
    
    self.navigationItem.rightBarButtonItem = self.loginCreateButtonItem;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)loginButtonPressed:(id)sender
{
    if ([self validForm]) {
        [self.createLoginHandler performActionWithValidForm:self.form account:self.account completion:^(NSError *error, OTRAccount *account) {
            
            if (account) {
                self.account = account;
            }
            
            if (error) {
                [self handleError:error];
            }
        }];
    }
}

- (BOOL)validForm
{
    BOOL validForm = YES;
    NSArray *formValidationErrors = [self formValidationErrors];
    if ([formValidationErrors count]) {
        validForm = NO;
    }
    
    [formValidationErrors enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        
        XLFormValidationStatus * validationStatus = [[obj userInfo] objectForKey:XLValidationStatusErrorKey];
        UITableViewCell * cell = [self.tableView cellForRowAtIndexPath:[self.form indexPathOfFormRow:validationStatus.rowDescriptor]];
        cell.backgroundColor = [UIColor orangeColor];
        [UIView animateWithDuration:0.3 animations:^{
            cell.backgroundColor = [UIColor whiteColor];
        }];
        
    }];
    return validForm;
}

- (void)handleError:(NSError *)error
{
    //show xmpp erors, cert errors, tor errors, oauth errors.
    if (error.code == OTRXMPPSSLError) {
        NSData * certData = error.userInfo[OTRXMPPSSLCertificateDataKey];
        NSString * hostname = error.userInfo[OTRXMPPSSLHostnameKey];
        uint32_t trustResultType = [error.userInfo[OTRXMPPSSLTrustResultKey] unsignedIntValue];
        
        [self showCertWarningForCertificateData:certData withHostname:hostname trustResultType:trustResultType];
    }
    else if(!self.certAlertView.isVisible){
        [self handleXMPPError:error];
    }
}

- (void)handleXMPPError:(NSError *)error
{
    [self showAlertViewWithTitle:ERROR_STRING message:XMPP_FAIL_STRING error:error];
}

- (void)showAlertViewWithTitle:(NSString *)title message:(NSString *)message error:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        RIButtonItem * okButtonItem = [RIButtonItem itemWithLabel:OK_STRING];
        UIAlertView * alertView = nil;
        if (error) {
            RIButtonItem * infoButton = [RIButtonItem itemWithLabel:INFO_STRING action:^{
                NSString * errorDescriptionString = [NSString stringWithFormat:@"%@ : %@",[error domain],[error localizedDescription]];
                
                if ([[error domain] isEqualToString:@"kCFStreamErrorDomainSSL"]) {
                    NSString * sslString = [OTRXMPPError errorStringWithSSLStatus:(OSStatus)error.code];
                    if ([sslString length]) {
                        errorDescriptionString = [errorDescriptionString stringByAppendingFormat:@"\n%@",sslString];
                    }
                }
                
                
                RIButtonItem * copyButtonItem = [RIButtonItem itemWithLabel:COPY_STRING action:^{
                    NSString * copyString = [NSString stringWithFormat:@"Domain: %@\nCode: %ld\nUserInfo: %@",[error domain],(long)[error code],[error userInfo]];
                    
                    UIPasteboard *pasteBoard = [UIPasteboard generalPasteboard];
                    [pasteBoard setString:copyString];
                }];
                
                UIAlertView * alert = [[UIAlertView alloc] initWithTitle:INFO_STRING
                                                                 message:errorDescriptionString
                                                        cancelButtonItem:nil
                                                        otherButtonItems:okButtonItem,copyButtonItem, nil];
                
                [alert show];
            }];
            alertView = [[UIAlertView alloc] initWithTitle:title
                                                   message:message
                                          cancelButtonItem:nil
                                          otherButtonItems:okButtonItem,infoButton, nil];
        }
        else {
            alertView = [[UIAlertView alloc] initWithTitle:title
                                                   message:message
                                          cancelButtonItem:nil
                                          otherButtonItems:okButtonItem, nil];
        }
        
        
        
        if (alertView) {
            [alertView show];
        }
    });
}


- (void)showCertWarningForCertificateData:(NSData *)certData withHostname:(NSString *)hostname trustResultType:(SecTrustResultType)resultType {
    
    SecCertificateRef certificate = [OTRCertificatePinning certForData:certData];
    NSString * fingerprint = [OTRCertificatePinning sha1FingerprintForCertificate:certificate];
    NSString * message = [NSString stringWithFormat:@"%@\nSHA1: %@",hostname,fingerprint];
    NSUInteger length = [message length];
    
    UIColor * sslMessageColor;
    NSMutableAttributedString * attributedString = nil;
    
    self.certAlertView = [[SIAlertView alloc] initWithTitle:NEW_CERTIFICATE_STRING andMessage:nil];
    
    self.certAlertView.buttonColor = [UIColor whiteColor];
    
    if (![OTRCertificatePinning publicKeyWithCertData:certData]) {
        //no public key not able to save because won't be able evaluate later
        
        self.certAlertView.messageAttributedString = nil;
        message = [message stringByAppendingString:[NSString stringWithFormat:@"\nX %@",PUBLIC_KEY_ERROR_STRING]];
        attributedString = [[NSMutableAttributedString alloc] initWithString:message];
        sslMessageColor = [OTRColors redErrorColor];
        
        [self.certAlertView addButtonWithTitle:OK_STRING type:SIAlertViewButtonTypeCancel handler:^(SIAlertView *alertView) {
            [alertView dismissAnimated:YES];
        }];
        
    }
    else {
        if (resultType == kSecTrustResultProceed || resultType == kSecTrustResultUnspecified) {
            //#52A352
            sslMessageColor = [OTRColors greenNoErrorColor];
            message = [message stringByAppendingString:[NSString stringWithFormat:@"\n✓ %@",VALID_CERTIFICATE_STRING]];
        }
        else {
            NSString * sslErrorMessage = [OTRXMPPError errorStringWithTrustResultType:resultType];
            sslMessageColor = [OTRColors redErrorColor];
            message = [message stringByAppendingString:[NSString stringWithFormat:@"\nX %@",sslErrorMessage]];
        }
        
        attributedString = [[NSMutableAttributedString alloc] initWithString:message];
        
        [self.certAlertView addButtonWithTitle:REJECT_STRING type:SIAlertViewButtonTypeDestructive handler:^(SIAlertView *alertView) {
            [alertView dismissAnimated:YES];
        }];
        __weak typeof(self)weakSelf = self;
        [self.certAlertView addButtonWithTitle:SAVE_STRING type:SIAlertViewButtonTypeDefault handler:^(SIAlertView *alertView) {
            __strong typeof(weakSelf)strongSelf = weakSelf;

            [OTRCertificatePinning addCertificate:[OTRCertificatePinning certForData:certData] withHostName:hostname];
            [strongSelf loginButtonPressed:strongSelf];
        }];
    }
    
    NSRange errorMessageRange = NSMakeRange(length, message.length-length);
    [attributedString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:16] range:NSMakeRange(0, message.length)];
    [attributedString addAttribute:NSForegroundColorAttributeName value:sslMessageColor range:errorMessageRange];
    
    self.certAlertView.messageAttributedString = attributedString;
    
    [self.certAlertView show];
    
    // For some reason we must show the alert view first,
    // THEN change the button style, otherwise the button doesn't appear.
    UIImage * normalImage = [UIImage imageNamed:@"button-green"];
    CGFloat hInset = floorf(normalImage.size.width / 2);
    CGFloat vInset = floorf(normalImage.size.height / 2);
    UIEdgeInsets insets = UIEdgeInsetsMake(vInset, hInset, vInset, hInset);
    UIImage * buttonImage = [normalImage resizableImageWithCapInsets:insets];
    
    [self.certAlertView setDefaultButtonImage:buttonImage forState:UIControlStateNormal];
    [self.certAlertView setDefaultButtonImage:buttonImage forState:UIControlStateHighlighted];
}

@end