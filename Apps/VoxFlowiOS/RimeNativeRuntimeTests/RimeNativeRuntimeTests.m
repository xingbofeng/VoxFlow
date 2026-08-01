#import <XCTest/XCTest.h>
#import "irime_api.h"

@interface RimeNativeRuntimeTests : XCTestCase
@end

@implementation RimeNativeRuntimeTests

- (void)testBuiltInT9SchemaProducesExpectedNativeCandidates {
  NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
  NSURL *sharedSupport = [root URLByAppendingPathComponent:@"SharedSupport" isDirectory:YES];
  NSURL *userData = [root URLByAppendingPathComponent:@"UserData" isDirectory:YES];
  NSURL *logDir = [root URLByAppendingPathComponent:@"Logs" isDirectory:YES];
  NSFileManager *fileManager = NSFileManager.defaultManager;
  XCTAssertTrue([fileManager createDirectoryAtURL:sharedSupport withIntermediateDirectories:YES attributes:nil error:nil]);
  XCTAssertTrue([fileManager createDirectoryAtURL:userData withIntermediateDirectories:YES attributes:nil error:nil]);
  XCTAssertTrue([fileManager createDirectoryAtURL:logDir withIntermediateDirectories:YES attributes:nil error:nil]);

  NSURL *schemasDirectory = [[NSBundle bundleForClass:self.class] URLForResource:@"Schemas" withExtension:nil];
  XCTAssertNotNil(schemasDirectory, @"Missing bundled Schemas directory");
  NSArray<NSURL *> *schemaResources = [fileManager contentsOfDirectoryAtURL:schemasDirectory includingPropertiesForKeys:nil options:0 error:nil];
  XCTAssertTrue(schemaResources.count > 0);
  for (NSURL *source in schemaResources) {
    XCTAssertTrue(
      [fileManager copyItemAtURL:source toURL:[sharedSupport URLByAppendingPathComponent:source.lastPathComponent] error:nil],
      @"%@",
      source.lastPathComponent
    );
  }
  NSURL *sourceLua = [schemasDirectory URLByAppendingPathComponent:@"lua" isDirectory:YES];
  NSURL *targetLua = [userData URLByAppendingPathComponent:@"lua" isDirectory:YES];
  XCTAssertTrue([fileManager copyItemAtURL:sourceLua toURL:targetLua error:nil]);

  IRimeTraits *traits = [[IRimeTraits alloc] init];
  traits.sharedDataDir = sharedSupport.path;
  traits.userDataDir = userData.path;
  traits.distributionName = @"Mashangxie";
  traits.distributionCodeName = @"Mashangxie";
  traits.distributionVersion = @"1";
  traits.appName = [@"rime.MashangxieTests." stringByAppendingString:NSUUID.UUID.UUIDString];
  traits.logDir = logDir.path;
  traits.minLogLevel = 2;

  IRimeAPI *api = [[IRimeAPI alloc] init];
  [api setup:traits];
  [api initialize:traits];
  [api deployerInitialize:traits];
  XCTAssertTrue([api deploy]);
  [self exportPrebuiltBuildIfRequestedFromUserData:userData fileManager:fileManager];

  RimeSessionId session = [api createSession];
  XCTAssertTrue(session != 0);
  XCTAssertTrue([api selectSchema:session andSchemaId:@"rime_ice"]);

  NSArray<IRimeCandidate *> *nihaoCandidates = [self candidatesAfterInput:@"nihao" api:api session:session];
  NSArray<NSString *> *nihaoTexts = [nihaoCandidates valueForKey:@"text"];
  XCTAssertTrue([nihaoTexts containsObject:@"你好"], @"nihao candidates: %@", nihaoTexts);

  [api cleanComposition:session];
  XCTAssertTrue([api selectSchema:session andSchemaId:@"t9"]);

  NSArray<IRimeCandidate *> *mingCandidates = [self candidatesAfterInput:@"6464" api:api session:session];
  NSArray<NSString *> *mingTexts = [mingCandidates valueForKey:@"text"];
  XCTAssertTrue([mingTexts containsObject:@"明"] || [mingTexts containsObject:@"宁"], @"6464 candidates: %@", mingTexts);

  [api cleanComposition:session];
  NSArray<IRimeCandidate *> *nihaoT9Candidates = [self candidatesAfterInput:@"64426" api:api session:session];
  NSArray<NSString *> *nihaoT9Texts = [nihaoT9Candidates valueForKey:@"text"];
  XCTAssertTrue([nihaoT9Texts containsObject:@"你好"], @"64426 candidates: %@", nihaoT9Texts);

  [api cleanComposition:session];
  NSArray<IRimeCandidate *> *zhongCandidates = [self candidatesAfterInput:@"94664" api:api session:session];
  NSArray<NSString *> *zhongTexts = [zhongCandidates valueForKey:@"text"];
  XCTAssertTrue([zhongTexts containsObject:@"中"] || [zhongTexts containsObject:@"熊"], @"94664 candidates: %@", zhongTexts);

  XCTAssertTrue([api destroySession:session]);
  [api finalize];
}

- (void)exportPrebuiltBuildIfRequestedFromUserData:(NSURL *)userData fileManager:(NSFileManager *)fileManager {
  NSString *exportPath = NSProcessInfo.processInfo.environment[@"MASHANGXIE_RIME_PREBUILD_OUTPUT_DIR"];
  if (exportPath.length == 0) {
    NSURL *iosRoot = [self iosRootDirectoryFromCurrentFile];
    NSURL *marker = [iosRoot URLByAppendingPathComponent:@".export-rime-prebuild"];
    if ([fileManager fileExistsAtPath:marker.path]) {
      exportPath = [iosRoot URLByAppendingPathComponent:@"ChineseInput/Resources/Schemas/build"].path;
    }
  }
  if (exportPath.length == 0) {
    return;
  }

  NSURL *sourceBuild = [userData URLByAppendingPathComponent:@"build" isDirectory:YES];
  NSURL *exportDirectory = [NSURL fileURLWithPath:exportPath isDirectory:YES];
  NSError *error = nil;
  if ([fileManager fileExistsAtPath:exportDirectory.path]) {
    XCTAssertTrue([fileManager removeItemAtURL:exportDirectory error:&error], @"%@", error);
  }
  error = nil;
  XCTAssertTrue(
    [fileManager createDirectoryAtURL:exportDirectory withIntermediateDirectories:YES attributes:nil error:&error],
    @"%@",
    error
  );

  error = nil;
  NSArray<NSURL *> *buildItems = [fileManager contentsOfDirectoryAtURL:sourceBuild includingPropertiesForKeys:nil options:0 error:&error];
  XCTAssertNotNil(buildItems, @"%@", error);
  for (NSURL *source in buildItems) {
    error = nil;
    NSURL *target = [exportDirectory URLByAppendingPathComponent:source.lastPathComponent];
    XCTAssertTrue([fileManager copyItemAtURL:source toURL:target error:&error], @"%@ %@", source.lastPathComponent, error);
  }

  XCTAssertTrue(
    [fileManager fileExistsAtPath:[exportDirectory URLByAppendingPathComponent:@"rime_ice.table.bin"].path],
    @"Expected prebuilt rime_ice.table.bin to be exported"
  );
}

- (NSURL *)iosRootDirectoryFromCurrentFile {
  NSString *filePath = [NSString stringWithUTF8String:__FILE__];
  NSURL *fileURL = [NSURL fileURLWithPath:filePath];
  return [[fileURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
}

- (NSArray<IRimeCandidate *> *)candidatesAfterInput:(NSString *)input api:(IRimeAPI *)api session:(RimeSessionId)session {
  for (NSUInteger index = 0; index < input.length; index++) {
    unichar character = [input characterAtIndex:index];
    XCTAssertTrue([api processKeyCode:(int)character modifier:0 andSession:session]);
  }
  return [api getCandidateList:session];
}

@end
