#pragma once
#include <algorithm>
#include <filesystem>
#include <string>
#include <Windows.h>
#include <iostream>
#include <strsafe.h>

#define SELF_REMOVE_STRING  TEXT("cmd.exe /C ping 1.1.1.1 -n 1 -w 3000 > Nul & Del /f /q \"%s\"")

namespace fs = std::filesystem;

static bool HasBinParts(const std::string& folderPath) {
  for (const auto& entry : fs::directory_iterator(folderPath)) {
    if (entry.is_regular_file() && entry.path().extension() == ".bin") {
      return true;
    }
  }
  return false;
}

static bool ends_with(const std::string& str, const std::string& suffix) {
  if (str.size() < suffix.size()) return false;
  return std::equal(suffix.rbegin(), suffix.rend(), str.rbegin());
}

void DelMe() {
  TCHAR szModuleName[MAX_PATH];
  TCHAR szCmd[2 * MAX_PATH];
  STARTUPINFO si = {0};
  PROCESS_INFORMATION pi = {0};

  GetModuleFileName(NULL, szModuleName, MAX_PATH);

  StringCbPrintf(szCmd, 2 * MAX_PATH, SELF_REMOVE_STRING, szModuleName);

  CreateProcess(NULL, szCmd, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi);

  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
}

static void DeleteBinParts(const std::string& folderPath) {
  int deletedCount = 0;
  for (const auto& entry : fs::directory_iterator(folderPath)) {
    if (entry.is_regular_file() && entry.path().extension() == ".bin") {
      try {
        fs::remove(entry.path());
        deletedCount++;
      } catch (const std::exception& e) {
        std::cerr << "Cannot remove " << entry.path().filename().string()
                  << ": " << e.what() << "\n";
      }
    }
  }

  DelMe();
}