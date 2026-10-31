import AppKit

let options = LaunchOptions(arguments: CommandLine.arguments)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(options: options)
app.delegate = delegate
app.run()
