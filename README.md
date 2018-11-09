# project-builder

Example of script for building ios project

Look for provisioning:

```bash
ls -al /Users/alex/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision
```

Look for identity:

```bash
security find-identity -v -p codesigning
```

Look for device:

```bash
ios-deploy -c
```

Deploy to device:

```bash
ios-deploy -i bab4a251167f94fd9db7c6a001be13d207a62f07 -b ExampleApp.app
```

Run application:

```bash
open -a "Simulator.app"
xcrun simctl install booted ExampleApp.app
xcrun simctl launch booted com.rubikon.ExampleApp
```

Example of .env file:

```yaml
type: iphoneos
project_name: ExampleApp-iOS
namespace: com.rubikon
team_identifier: ***
identity: ***
provisioning_profile_name: ***.mobileprovision
```

Links

- https://vojtastavik.com/2018/10/15/building-ios-app-without-xcode/
- https://github.com/ios-control/ios-deploy