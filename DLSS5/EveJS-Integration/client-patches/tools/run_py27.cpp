#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

namespace
{
template <typename T>
T load_export(HMODULE module, const char *name)
{
    const auto address = GetProcAddress(module, name);
    if (address == nullptr)
    {
        std::fprintf(stderr, "python27.dll is missing export %s\n", name);
        ExitProcess(2);
    }
    return reinterpret_cast<T>(address);
}

bool read_file(const wchar_t *path, std::vector<char> &data)
{
    const HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return false;

    LARGE_INTEGER size = {};
    if (!GetFileSizeEx(file, &size) || size.QuadPart < 0 || size.QuadPart > INT32_MAX)
    {
        CloseHandle(file);
        return false;
    }

    data.resize(static_cast<size_t>(size.QuadPart));
    DWORD bytes_read = 0;
    const bool ok = data.empty() || (ReadFile(file, data.data(), static_cast<DWORD>(data.size()), &bytes_read, nullptr) && bytes_read == data.size());
    CloseHandle(file);
    return ok;
}

std::string utf8(const wchar_t *value)
{
    const int size = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
    std::string result(static_cast<size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value, -1, &result[0], size, nullptr, nullptr);
    result.resize(result.size() - 1);
    return result;
}
}

int wmain(int argc, wchar_t **argv)
{
    if (argc < 3)
    {
        std::fprintf(stderr, "usage: run_py27 PYTHON27.DLL SCRIPT.PY [ARG ...]\n");
        return 2;
    }

    std::vector<char> script;
    if (!read_file(argv[2], script))
    {
        std::fprintf(stderr, "failed to read script\n");
        return 2;
    }
    script.push_back('\0');

    const HMODULE python = LoadLibraryExW(argv[1], nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (python == nullptr)
    {
        std::fprintf(stderr, "failed to load python27.dll (Win32 error %lu)\n", GetLastError());
        return 2;
    }

    const auto Py_InitializeEx = load_export<void (__cdecl *)(int)>(python, "Py_InitializeEx");
    const auto Py_Finalize = load_export<void (__cdecl *)()>(python, "Py_Finalize");
    const auto PySys_SetArgvEx = load_export<void (__cdecl *)(int, char **, int)>(python, "PySys_SetArgvEx");
    const auto PyRun_SimpleString = load_export<int (__cdecl *)(const char *)>(python, "PyRun_SimpleString");
    const auto PyErr_Print = load_export<void (__cdecl *)()>(python, "PyErr_Print");
    *load_export<int *>(python, "Py_NoSiteFlag") = 1;
    *load_export<int *>(python, "Py_IgnoreEnvironmentFlag") = 1;

    Py_InitializeEx(0);

    std::vector<std::string> narrow_arguments;
    std::vector<char *> python_argv;
    for (int index = 2; index < argc; ++index)
        narrow_arguments.push_back(utf8(argv[index]));
    for (std::string &argument : narrow_arguments)
        python_argv.push_back(&argument[0]);
    PySys_SetArgvEx(static_cast<int>(python_argv.size()), python_argv.data(), 0);

    const int result = PyRun_SimpleString(script.data());
    if (result != 0)
        PyErr_Print();

    Py_Finalize();
    FreeLibrary(python);
    return result == 0 ? 0 : 1;
}
