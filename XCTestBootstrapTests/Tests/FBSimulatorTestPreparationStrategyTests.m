/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

@interface FBSimulatorTestPreparationStrategyTests : XCTestCase
@end

@implementation FBSimulatorTestPreparationStrategyTests

+ (BOOL)isGoodConfigurationPath:(NSString *)path
{
  return [path rangeOfString:@"\\/heaven\\/testBundle\\/testBundle-(.*)\\.xctestconfiguration" options:NSRegularExpressionSearch].location != NSNotFound;
}

- (void)testSimulatorPreparation
{
  id xctConfigArg = [OCMArg checkWithBlock:^ BOOL (NSString *path){
    return [self.class isGoodConfigurationPath:path];
  }];
  NSDictionary *plist = @{
    @"CFBundleIdentifier" : @"bundleID",
    @"CFBundleExecutable" : @"exec",
  };

  OCMockObject<FBFileManager> *fileManagerMock = [OCMockObject mockForProtocol:@protocol(FBFileManager)];
  [[[fileManagerMock stub] andReturn:plist] dictionaryWithPath:[OCMArg any]];
  [[[fileManagerMock expect] andReturnValue:@YES] copyItemAtPath:@"/testBundle" toPath:@"/heaven/testBundle" error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] writeData:[OCMArg any] toFile:xctConfigArg options:0 error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock stub] andReturnValue:@YES] ignoringNonObjectArgs] createDirectoryAtPath:@"/heaven" withIntermediateDirectories:YES attributes:[OCMArg any] error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock stub] andReturnValue:@YES] ignoringNonObjectArgs] fileExistsAtPath:@"/app/exec"];
  [[[[fileManagerMock stub] andReturnValue:@NO] ignoringNonObjectArgs] fileExistsAtPath:[OCMArg any]];

  NSError *error;
  FBProductBundle *productBundle = [[[FBProductBundleBuilder
    builderWithFileManager:fileManagerMock]
    withBundlePath:@"/app"]
    buildWithError:&error];
  XCTAssertNil(error);

  OCMockObject<FBiOSTarget> *iosTargetMock = [OCMockObject mockForProtocol:@protocol(FBiOSTarget)];
  [[[iosTargetMock stub] andReturn:dispatch_get_main_queue()] workQueue];
  OCMockObject<FBDeviceOperator> *deviceOperatorMock = [OCMockObject mockForProtocol:@protocol(FBDeviceOperator)];
  [[[iosTargetMock stub] andReturn:deviceOperatorMock] deviceOperator];
  [[[deviceOperatorMock expect] andReturn:productBundle] applicationBundleWithBundleID:@"bundleId" error:[OCMArg anyObjectRef]];

  OCMockObject<FBCodesignProvider> *codesignMock = [OCMockObject mockForProtocol:@protocol(FBCodesignProvider)];
  [[[codesignMock stub] andReturn:[FBFuture futureWithResult:@"aaa1111"]] cdHashForBundleAtPath:OCMArg.any];

  FBSimulatorTestPreparationStrategy *strategy = [FBSimulatorTestPreparationStrategy
    strategyWithTestLaunchConfiguration:self.defaultTestLaunch
    workingDirectory:@"/heaven"
    fileManager:fileManagerMock
    codesign:codesignMock];
  FBTestRunnerConfiguration *configuration = [[strategy prepareTestWithIOSTarget:iosTargetMock] await:nil];

  NSDictionary *env = configuration.launchEnvironment;
  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.testRunner);
  XCTAssertNotNil(configuration.launchArguments);
  XCTAssertNotNil(env);
  XCTAssertEqualObjects(env[@"AppTargetLocation"], @"/app/exec");
  XCTAssertEqualObjects(env[@"TestBundleLocation"], @"/heaven/testBundle");
  XCTAssertEqualObjects(env[@"XCInjectBundle"], @"/heaven/testBundle");
  XCTAssertEqualObjects(env[@"XCInjectBundleInto"], @"/app/exec");
  XCTAssertNotNil(env[@"DYLD_INSERT_LIBRARIES"]);
  XCTAssertTrue([self.class isGoodConfigurationPath:configuration.launchEnvironment[@"XCTestConfigurationFilePath"]],
                @"XCTestConfigurationFilePath should be like /heaven/testBundle/testBundle-[UDID].xctestconfiguration but is %@",
                env[@"XCTestConfigurationFilePath"]
                );
  [fileManagerMock verify];
  [iosTargetMock verify];
  [deviceOperatorMock verify];
}

- (FBTestLaunchConfiguration *)defaultTestLaunch
{
  return [[FBTestLaunchConfiguration configurationWithTestBundlePath:@"/testBundle"] withApplicationLaunchConfiguration:self.defaultAppLaunch];
}

- (FBApplicationLaunchConfiguration *)defaultAppLaunch
{
  return [FBApplicationLaunchConfiguration
    configurationWithBundleID:@"bundleId"
    bundleName:@""
    arguments:@[]
    environment:@{}
    waitForDebugger:NO
    output:FBProcessOutputConfiguration.outputToDevNull];
}

@end
