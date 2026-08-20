#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

void MoveWindowToRightSide(Win32Window& window) {
  HWND handle = window.GetHandle();
  if (handle == nullptr) {
    return;
  }

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  HMONITOR monitor = ::MonitorFromWindow(handle, MONITOR_DEFAULTTOPRIMARY);
  RECT window_rect{};
  if (!::GetMonitorInfoW(monitor, &monitor_info) ||
      !::GetWindowRect(handle, &window_rect)) {
    return;
  }

  const int width = window_rect.right - window_rect.left;
  const int height = window_rect.bottom - window_rect.top;
  const int margin = ::MulDiv(16, ::GetDpiForWindow(handle), 96);
  const RECT& work_area = monitor_info.rcWork;
  int x = work_area.right - width - margin;
  int y = work_area.top + ((work_area.bottom - work_area.top - height) / 2);
  if (x < work_area.left) {
    x = work_area.left;
  }
  if (y < work_area.top) {
    y = work_area.top;
  }

  ::SetWindowPos(handle, nullptr, x, y, 0, 0,
                 SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOSIZE);
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  ::SetLastError(ERROR_SUCCESS);
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"Local\\Mclash.Desktop.SingleInstance");
  if (instance_mutex == nullptr) {
    return EXIT_FAILURE;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (HWND existing_window = ::FindWindowW(nullptr, L"Mclash")) {
      ::ShowWindow(existing_window, SW_RESTORE);
      ::SetForegroundWindow(existing_window);
    }
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(360, 720);
  if (!window.Create(L"Mclash", origin, size)) {
    ::ReleaseMutex(instance_mutex);
    ::CloseHandle(instance_mutex);
    return EXIT_FAILURE;
  }
  MoveWindowToRightSide(window);
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::ReleaseMutex(instance_mutex);
  ::CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}
