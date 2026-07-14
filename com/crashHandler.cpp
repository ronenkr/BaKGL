#include "com/crashHandler.hpp"

#include "com/logger.hpp"

#include <csignal>
#include <cstdlib>
#include <exception>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>
#endif

namespace Com {
namespace {

const Logging::Logger& GetCrashLogger()
{
    static const auto& logger = Logging::LogState::GetLogger("Crash");
    return logger;
}

void HandleTerminate()
{
    auto& logger = GetCrashLogger();
    if (auto currentException = std::current_exception())
    {
        try
        {
            std::rethrow_exception(currentException);
        }
        catch (const std::exception& e)
        {
            logger.Fatal() << "std::terminate called due to an unhandled exception: "
                << e.what() << std::endl;
        }
        catch (...)
        {
            logger.Fatal() << "std::terminate called due to an unhandled non-standard exception" << std::endl;
        }
    }
    else
    {
        logger.Fatal() << "std::terminate called with no active exception "
            "(likely a noexcept function let an exception escape)" << std::endl;
    }
    std::_Exit(3);
}

void HandleAbortSignal(int)
{
    GetCrashLogger().Fatal() << "Process received SIGABRT "
        "(likely a failed assert() or an explicit abort())" << std::endl;
    std::_Exit(4);
}

#if defined(_WIN32)
LONG WINAPI HandleUnhandledException(EXCEPTION_POINTERS* info)
{
    GetCrashLogger().Fatal() << "Unhandled native exception, code=0x" << std::hex
        << info->ExceptionRecord->ExceptionCode << std::dec
        << " at address=" << info->ExceptionRecord->ExceptionAddress << std::endl;
    return EXCEPTION_CONTINUE_SEARCH;
}
#endif

}

void InstallCrashHandlers()
{
    std::set_terminate(&HandleTerminate);
    std::signal(SIGABRT, &HandleAbortSignal);
#if defined(_WIN32)
    SetUnhandledExceptionFilter(&HandleUnhandledException);
#endif
}

}
