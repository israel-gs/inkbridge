# InputTests

Raw `UIView` touch overrides (`touchesBegan/Moved/Ended/Cancelled`) cannot be unit-tested in this project — they require either a physical device or XCUITests. The TouchRouter consumed by the canvas IS unit-tested. Behavior of CanvasUIView is verified via XCUITest in `InkBridgeIOSUITests/`.
