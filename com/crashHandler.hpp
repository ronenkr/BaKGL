#pragma once

namespace Com {

// Installs process-wide handlers for the ways this process can go down
// silently (an unhandled C++ exception reaching std::terminate, a failed
// assert()/abort(), or a native crash such as an access violation) so that
// each one leaves a message in the log before the process actually exits.
void InstallCrashHandlers();

}
