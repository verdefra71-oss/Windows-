#include "utils.h"
#include <windows.h>
#include <shellapi.h>
#include <iostream>

std::vector<std::string> GetCommandLineArguments() {
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (!argv) return {};
  std::vector<std::string> result;
  for (int i = 1; i < argc; ++i) {
    std::wstring ws(argv[i]);
    result.push_back(std::string(ws.begin(), ws.end()));
  }
  ::LocalFree(argv);
  return result;
}

void CreateAndAttachConsole() {
  if (!::AllocConsole()) return;
  FILE* unused;
  freopen_s(&unused, "CONOUT$", "w", stdout);
  freopen_s(&unused, "CONOUT$", "w", stderr);
  freopen_s(&unused, "CONIN$", "r", stdin);
  std::ios::sync_with_stdio();
}
