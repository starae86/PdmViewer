#include "flutter_window.h"

#include <optional>
#include <set>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {
int CALLBACK CollectFontFamily(const LOGFONTW* font, const TEXTMETRICW*,
                               DWORD, LPARAM data) {
  auto* families = reinterpret_cast<std::set<std::string>*>(data);
  if (font->lfFaceName[0] != L'@') {
    families->insert(Utf8FromUtf16(font->lfFaceName));
  }
  return 1;
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  flutter::MethodChannel<flutter::EncodableValue> font_channel(
      flutter_controller_->engine()->messenger(), "pdm_viewer/system_fonts",
      &flutter::StandardMethodCodec::GetInstance());
  font_channel.SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "listFamilies") {
          result->NotImplemented();
          return;
        }
        std::set<std::string> families;
        LOGFONTW font = {};
        font.lfCharSet = DEFAULT_CHARSET;
        HDC dc = GetDC(nullptr);
        if (!dc) {
          result->Error("font_enumeration_failed", "Cannot access system fonts");
          return;
        }
        EnumFontFamiliesExW(dc, &font, CollectFontFamily,
                           reinterpret_cast<LPARAM>(&families), 0);
        ReleaseDC(nullptr, dc);
        flutter::EncodableList values;
        for (const auto& family : families) {
          values.emplace_back(family);
        }
        result->Success(flutter::EncodableValue(values));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
