#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

HHOOK hKeyboardHook = NULL;

// Procedimiento de hook para interceptar atajos de teclado no autorizados en modo retail
LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
  if (nCode == HC_ACTION) {
    KBDLLHOOKSTRUCT* pkbhs = (KBDLLHOOKSTRUCT*)lParam;
    DWORD key = pkbhs->vkCode;
    bool alt = GetKeyState(VK_MENU) & 0x8000;
    bool ctrl = GetKeyState(VK_CONTROL) & 0x8000;
    bool win = (pkbhs->flags & LLKHF_ALTDOWN) || key == VK_LWIN || key == VK_RWIN;
    bool shift = GetKeyState(VK_SHIFT) & 0x8000;

    // 1. Bypass para Admin: Ctrl+C, Ctrl+V, Ctrl+X, Ctrl+Shift+Esc
    if (ctrl && !win && !alt && (key == 'C' || key == 'V' || key == 'X' || (shift && key == VK_ESCAPE))) {
      return CallNextHookEx(NULL, nCode, wParam, lParam);
    }

    // 2. Bloqueos de atajos del sistema
    bool should_block = false;
    
    if (win && key != VK_LWIN && key != VK_RWIN) {
      // Bloquear atajos de Windows (Win + ...)
      should_block = (key == VK_TAB || key == 'D' || key == 'R' || key == 'E' || key == 'L' || key == 'X' || 
                      key == 'I' || key == 'S' || key == 'A' || key == 'K' || key == 'P' || key == 'U' || 
                      key == 'V' || key == 'W' || key == 'Z' || key == 'C' || key == VK_HOME || key == 'M' || 
                      key == 'T' || key == 'B' || key == 'H' || key == 'Q' || key == VK_LEFT || key == VK_RIGHT || 
                      key == VK_UP || key == VK_DOWN || key == 0xBE || key == 0xBA);
    } else if (alt) {
      // Bloquear Alt+Tab, Alt+Esc, Alt+F4, Alt+Espacio
      should_block = (key == VK_TAB || key == VK_ESCAPE || key == VK_F4 || key == VK_SPACE);
    } else if (ctrl) {
      // Bloquear Ctrl+Esc (pero permitir Ctrl+Shift+Esc)
      should_block = (key == VK_ESCAPE && !shift);
    } else {
      // Bloquear tecla Menú (Apps), Shift+F10 (menú contextual) y Shift+Esc
      should_block = (key == VK_APPS || (shift && (key == VK_F10 || key == VK_ESCAPE)));
    }

    if (should_block) {
      return 1; // Interceptar y no propagar
    }
  }
  return CallNextHookEx(NULL, nCode, wParam, lParam);
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Instalar el hook de teclado global de bajo nivel
  hKeyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, LowLevelKeyboardProc, instance, 0);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"zenit_flutter", origin, size)) {
    if (hKeyboardHook) UnhookWindowsHookEx(hKeyboardHook);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // Desinstalar el hook de teclado al cerrar
  if (hKeyboardHook) {
    UnhookWindowsHookEx(hKeyboardHook);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

