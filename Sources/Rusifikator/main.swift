import Darwin

// A second copy must give up before anything user-visible or long-lived exists:
// no status item, no popover, no observers, no network clients.
if SingleInstanceGate.shared.claimSession() == .secondary {
    exit(EXIT_SUCCESS)
}

RusifikatorApp.main()
