//
//  AppLockerXPC.swift
//  AppLocker
//
//  Created by Doe Phương on 26/07/2025.
//


// AppLockerXPC.h
#import <Foundation/Foundation.h>

@protocol AppLockerXPC
- (void)handleLaunchRequestFromPID:(pid_t)pid
                           appPath:(NSString *)path
                          withReply:(void (^)(BOOL success))reply;
@end
