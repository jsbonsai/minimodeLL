// minimodell-runtime-guard: tiny sandbox-inheriting supervisor for the bundled llama-server.
//
// Usage (by RuntimeManager only): minimodell-runtime-guard <llama-server path> [server arguments...]
//
// Why: if the app is killed (SIGKILL, crash, force quit) it cannot stop its child, and an orphaned
// llama-server would keep gigabytes of model memory resident. This guard spawns the server, forwards
// SIGTERM/SIGINT/SIGHUP to it, and stops it when the app's process disappears (re-parenting to launchd).
// It exits with the server's status so the app still sees crashes. It never logs, and it passes the
// environment (including the per-launch API key) only to the server.
import Darwin

let arguments = CommandLine.arguments
guard arguments.count >= 2, arguments[1].hasPrefix("/") else { exit(64) }
let appPID = getppid()

var serverPID: pid_t = 0
var argv: [UnsafeMutablePointer<CChar>?] = arguments.dropFirst().map { strdup($0) } + [nil]
guard posix_spawn(&serverPID, arguments[1], nil, nil, &argv, environ) == 0 else { exit(70) }

// Forward termination requests. Handlers only call async-signal-safe kill() and set a flag.
nonisolated(unsafe) var forwardTarget: pid_t = serverPID
nonisolated(unsafe) var stopRequested: sig_atomic_t = 0
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig) { received in stopRequested = 1; if forwardTarget > 0 { kill(forwardTarget, received) } }
}

var status: Int32 = 0
var stoppingSince: Int = -1
var ticks = 0
while true {
    let result = waitpid(serverPID, &status, WNOHANG)
    if result == serverPID { break }
    if result < 0 && errno != EINTR { exit(71) }
    // App gone (we were re-parented) or stop requested: SIGTERM the server, SIGKILL it after 3 seconds.
    // The app's own grace period is longer, so the guard normally exits before the app escalates to it.
    if getppid() != appPID || stopRequested != 0 {
        if stoppingSince < 0 { stoppingSince = ticks; kill(serverPID, SIGTERM) }
        else if ticks - stoppingSince >= 30 { kill(serverPID, SIGKILL) }
    }
    usleep(100_000)
    ticks += 1
}
// Mirror the server's outcome: normal exit status, or 128 + signal number.
let signalled = status & 0x7f
exit(signalled == 0 ? (status >> 8) & 0xff : 128 + signalled)
