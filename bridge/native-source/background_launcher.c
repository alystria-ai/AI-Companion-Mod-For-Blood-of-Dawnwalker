/* Launch the fixed background script without creating a console window in the
 * game process. package.loadlib calls this export with a lua_State pointer;
 * the pointer is deliberately unused so no Lua ABI is linked or crossed. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

static HMODULE self;

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) self = instance;
    return TRUE;
}

static int append(wchar_t *path, size_t capacity, const wchar_t *suffix) {
    size_t used = wcslen(path), extra = wcslen(suffix);
    if (used + extra >= capacity) return 0;
    memcpy(path + used, suffix, (extra + 1) * sizeof(wchar_t));
    return 1;
}

static void report_error(const wchar_t *payload, DWORD code) {
    wchar_t path[32768];
    char message[96];
    HANDLE file;
    int length;
    DWORD written;
    if (wcslen(payload) >= sizeof(path) / sizeof(path[0])) return;
    wcscpy(path, payload);
    if (!append(path, sizeof(path) / sizeof(path[0]), L"\\runtime\\background-launch-error.txt")) return;
    length = snprintf(message, sizeof(message), "Background launch failed (Windows error %lu)\n", (unsigned long)code);
    file = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return;
    if (length > 0) WriteFile(file, message, (DWORD)length, &written, NULL);
    CloseHandle(file);
}

__declspec(dllexport) int start_background_hidden(void *unused) {
    wchar_t payload[32768], script[32768], executable[32768], command[32768];
    wchar_t *part;
    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION process = {0};
    DWORD size, error = ERROR_BUFFER_OVERFLOW;
    (void)unused;

    size = GetModuleFileNameW(self, payload, (DWORD)(sizeof(payload) / sizeof(payload[0])));
    if (!size || size >= sizeof(payload) / sizeof(payload[0])) return 0;
    part = wcsrchr(payload, L'\\');
    if (!part || _wcsicmp(part + 1, L"background_launcher_v1.dll") != 0) return 0;
    *part = 0;
    part = wcsrchr(payload, L'\\');
    if (!part || _wcsicmp(part + 1, L"native") != 0) return 0;
    *part = 0;
    part = wcsrchr(payload, L'\\');
    if (!part || _wcsicmp(part + 1, L"bridge") != 0) return 0;
    *part = 0;

    wcscpy(script, payload);
    if (!append(script, sizeof(script) / sizeof(script[0]), L"\\scripts\\Start-Background.ps1")) goto failed;
    if (GetFileAttributesW(script) == INVALID_FILE_ATTRIBUTES) {
        error = GetLastError();
        goto failed;
    }

    size = GetSystemDirectoryW(executable, (DWORD)(sizeof(executable) / sizeof(executable[0])));
    if (!size || size >= sizeof(executable) / sizeof(executable[0])) goto failed;
    if (!append(executable, sizeof(executable) / sizeof(executable[0]), L"\\WindowsPowerShell\\v1.0\\powershell.exe")) goto failed;
    if (swprintf(command, sizeof(command) / sizeof(command[0]),
                 L"\"%ls\" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%ls\"",
                 executable, script) < 0) goto failed;

    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    if (!CreateProcessW(executable, command, NULL, NULL, FALSE, CREATE_NO_WINDOW,
                        NULL, payload, &startup, &process)) {
        error = GetLastError();
        goto failed;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    wcscpy(script, payload);
    if (append(script, sizeof(script) / sizeof(script[0]), L"\\runtime\\background-launch-error.txt")) DeleteFileW(script);
    return 0;

failed:
    report_error(payload, error);
    return 0;
}
