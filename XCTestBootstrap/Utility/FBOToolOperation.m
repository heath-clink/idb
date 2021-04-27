/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBOToolOperation.h"

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

@implementation FBOToolOperation

+ (FBFuture<NSArray<NSString*>*>*)listSanitiserDylibsRequiredByBundle:(NSString*)testBundlePath onQueue:(nonnull dispatch_queue_t)queue {
  NSBundle *bundle = [NSBundle bundleWithPath:testBundlePath];
  if (!bundle) {
    NSString *message = [NSString stringWithFormat:@"Bundle '%@' does not identify an accessible bundle directory.", testBundlePath];
    return [FBFuture futureWithError:[[XCTestBootstrapError describe:message] build]];
  }
  if (![bundle executablePath]) {
    NSString *message = [NSString stringWithFormat:@"The bundle at %@ does not contain an executable.", testBundlePath];
    return [FBFuture futureWithError:[[XCTestBootstrapError describe:message] build]];
  }
  
  FBTaskBuilder *builder = [[[[[FBTaskBuilder
                                withLaunchPath:@"/usr/bin/otool"]
                               withArguments:@[@"-L", [bundle executablePath]]]
                              withAcceptableExitCodes:[NSSet setWithObject:@0]]
                             withStdOutInMemoryAsString]
                            withStdErrInMemoryAsString];
  
  return [[builder runUntilCompletion] onQueue:queue map:^NSArray<NSString*>* _Nonnull(FBTask<id,NSString*,NSString*> * _Nonnull task) {
    return [[self class] extractSanitiserDylibsfromOtoolOutput:task.stdOut];
  }];
}

+ (NSArray<NSString *> *)extractSanitiserDylibsfromOtoolOutput:(NSString *)otool_output {
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"@rpath/(libclang_rt\\..*san_.*_dynamic.dylib)"
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:nil];
  NSMutableArray *libs = NSMutableArray.array;
  
  [regex enumerateMatchesInString:otool_output
                          options:0
                            range:NSMakeRange(0, otool_output.length)
                       usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
    NSRange range = [result rangeAtIndex:1];
    NSString *libName = [otool_output substringWithRange:range];
    [libs addObject:libName];
  }];
  return [NSArray arrayWithArray:libs];
}

@end
