#ifndef FLUTTER_WINDOW_H_
#define FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <memory>
#include "win32_window.h"

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  ~FlutterWindow() override;

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message,
                         WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  const flutter::DartProject& project_;
};
#endif
