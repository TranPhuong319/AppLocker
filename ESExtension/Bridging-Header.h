//
//  Bridging-Header.h
//  ESExtension
//
//  Created by Doe Phương on 20/12/25.
//

#ifndef Bridging_Header_h
#define Bridging_Header_h

#import <Foundation/Foundation.h>
#include <libproc.h>
#include <sys/proc_info.h>
#include <bsm/libbsm.h>
#include <notify.h>

@interface NSXPCConnection (AuditToken)
@property (readonly) audit_token_t auditToken;
@end

#endif /* Bridging_Header_h */
