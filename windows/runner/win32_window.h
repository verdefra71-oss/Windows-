#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>
#include <string>

class Win32Window {
 public:
  struct Point { unsigned int x; unsigned int y; Point(unsigned int x, unsigned int y):x(x),y(y){} };
  struct Size { unsigned int width; unsigned int height; Size(unsigned int w, unsigned int h):width(w),height(h){} };

  Win32Window();
  virtual ~Win32Window();
  bool CreateAndShow(const std::wstring& title, const Point& origin, const Size& size);
  void SetQuitOnClose(bool quit_on_close);
  void SetChildContent(HWND content);
  void Show();
  RECT GetClientArea();
  virtual LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam, LPARAM const lparam) noexcept;
 protected:
  virtual bool OnCreate();
  virtual void OnDestroy();
  HWND GetHandle();
 private:
  HWND window_handle_ = nullptr;
  HWND child_content_ = nullptr;
  bool quit_on_close_ = false;
  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam);
};
#endif
