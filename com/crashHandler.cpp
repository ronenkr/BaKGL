#include "com/crashHandler.hpp"

#include "com/logger.hpp"

#include <csignal>
#include <cstdlib>
#include <exception>
#include <string>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>
#include <DbgHelp.h>
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
void LogStackTrace(CONTEXT* context)
{
    auto& logger = GetCrashLogger();

    const auto process = GetCurrentProcess();
    const auto thread = GetCurrentThread();

    SymSetOptions(SYMOPT_LOAD_LINES | SYMOPT_DEFERRED_LOADS);
    if (!SymInitialize(process, nullptr, TRUE))
    {
        logger.Fatal() << "  (could not initialise symbol handler, no stack trace available)" << std::endl;
        return;
    }

    STACKFRAME64 frame{};
    frame.AddrPC.Offset = context->Rip;
    frame.AddrPC.Mode = AddrModeFlat;
    frame.AddrFrame.Offset = context->Rbp;
    frame.AddrFrame.Mode = AddrModeFlat;
    frame.AddrStack.Offset = context->Rsp;
    frame.AddrStack.Mode = AddrModeFlat;

    constexpr int maxFrames = 64;
    for (int i = 0; i < maxFrames; i++)
    {
        if (!StackWalk64(
                IMAGE_FILE_MACHINE_AMD64,
                process,
                thread,
                &frame,
                context,
                nullptr,
                SymFunctionTableAccess64,
                SymGetModuleBase64,
                nullptr))
        {
            break;
        }

        if (frame.AddrPC.Offset == 0)
        {
            break;
        }

        alignas(SYMBOL_INFO) char symbolBuffer[sizeof(SYMBOL_INFO) + MAX_SYM_NAME];
        auto* symbol = reinterpret_cast<SYMBOL_INFO*>(symbolBuffer);
        symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
        symbol->MaxNameLen = MAX_SYM_NAME;

        DWORD64 symbolDisplacement = 0;
        const bool haveSymbol = SymFromAddr(process, frame.AddrPC.Offset, &symbolDisplacement, symbol);

        DWORD lineDisplacement = 0;
        IMAGEHLP_LINE64 line{};
        line.SizeOfStruct = sizeof(IMAGEHLP_LINE64);
        const bool haveLine = SymGetLineFromAddr64(process, frame.AddrPC.Offset, &lineDisplacement, &line);

        logger.Fatal() << "  #" << i << " 0x" << std::hex << frame.AddrPC.Offset << std::dec
            << " " << (haveSymbol ? symbol->Name : "<unknown>")
            << (haveLine ? (std::string{" at "} + line.FileName + ":" + std::to_string(line.LineNumber)) : "")
            << std::endl;
    }

    SymCleanup(process);
}

LONG WINAPI HandleUnhandledException(EXCEPTION_POINTERS* info)
{
    GetCrashLogger().Fatal() << "Unhandled native exception, code=0x" << std::hex
        << info->ExceptionRecord->ExceptionCode << std::dec
        << " at address=" << info->ExceptionRecord->ExceptionAddress << std::endl;
    LogStackTrace(info->ContextRecord);
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
