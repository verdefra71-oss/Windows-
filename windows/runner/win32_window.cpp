#include "win32_window.h"
#include <windowsx.h>

Win32Window::Win32Window() {}
Win32Window::~Win32Window() {}

bool Win32Window::CreateAndShow(const std::wstring& title, const Point& origin, const Size& size) {
  WNDCLASS window_class = {};
  window_class.lpfnWndProc = Win32Window::WndProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = L"FLUTTER_RUNNER_WIN32_WINDOW";
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClass(&window_class);

  window_handle_ = CreateWindowEx(
      0, window_class.lpszClassName, title.c_str(),
      WS_OVERLAPPEDWINDOW | WS_VISIBLE,
      origin.x, origin.y, size.width, size.height,
      nullptr, nullptr, window_class.hInstance, this);
  if (!window_handle_) return false;
  return OnCreate();
}

void Win32Window::SetQuitOnClose(bool quit_on_close) { quit_on_close_ = quit_on_close; }
void Win32Window::SetChildContent(HWND content) { child_content_ = content; SetParent(content, window_handle_); ShowWindow(content, SW_SHOW); }
void Win32Window::Show() { ShowWindow(window_handle_, SW_SHOW); UpdateWindow(window_handle_); }
RECT Win32Window::GetClientArea() { RECT rect; GetClientRect(window_handle_, &rect); return rect; }
HWND Win32Window::GetHandle() { return window_handle_; }

bool Win32Window::OnCreate() { return true; }
void Win32Window::OnDestroy() { if (child_content_) DestroyWindow(child_content_); child_content_=nullptr; }
LRESULT Win32Window::MessageHandler(HWND window, UINT const message, WPARAM const wparam, LPARAM const lparam) noexcept {
  switch(message) {
    case WM_SIZE:
      if(child_content_) SetWindowPos(child_content_, nullptr, 0, 0, GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam), SWP_NOZORDER|SWP_NOACTIVATE);
      return 0;
    case WM_DESTROY:
      OnDestroy();
      if(quit_on_close_) PostQuitMessage(0);
      return 0;
  }
  return DefWindowProc(window,message,wparam,lparam);
}
LRESULT CALLBACK Win32Window::WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  Win32Window* that = reinterpret_cast<Win32Window*>(GetWindowLongPtr(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    that = static_cast<Win32Window*>(cs->lpCreateParams);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(that));
    that->window_handle_ = window;
  }
  if (that) return that->MessageHandler(window,message,wparam,lparam);
  return DefWindowProc(window,message,wparam,lparam);
}
