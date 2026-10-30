import Foundation
// usage: debugctl "<command>" [more commands...]  — sends commands to a running debug build (IELTSMOCK_DEBUG=1)
for (i, cmd) in CommandLine.arguments.dropFirst().enumerated() {
    if i > 0 { Thread.sleep(forTimeInterval: 0.6) }
    DistributedNotificationCenter.default().postNotificationName(.init("local.ieltsmock.debug"), object: cmd, userInfo: nil, deliverImmediately: true)
}
Thread.sleep(forTimeInterval: 0.2)
