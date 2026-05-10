# InkBridge — root Makefile
# Targets for iOS client. Add android/macos targets below as needed.

.PHONY: ios-test ios-build

# Run the iOS unit test suite in the simulator.
ios-test:
	cd ios/InkBridgeIOS && xcodebuild test -scheme InkBridgeIOS -destination 'platform=iOS Simulator,name=iPhone 16' -quiet

# Build the iOS app without running tests.
ios-build:
	cd ios/InkBridgeIOS && xcodebuild build -scheme InkBridgeIOS -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
