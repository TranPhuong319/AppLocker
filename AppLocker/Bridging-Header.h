//
//  Bridging-Header.h
//  AppLocker
//
//  Created by Doe Phương on 5/9/26.
//

#ifndef AppLocker_Bridging_Header_h
#define AppLocker_Bridging_Header_h

#import <Foundation/Foundation.h>
#include <notify.h>
#include <bsm/libbsm.h>

@interface NSXPCConnection (AuditToken)
@property (readonly) audit_token_t auditToken;
@end

#endif /* AppLocker_Bridging_Header_h */
