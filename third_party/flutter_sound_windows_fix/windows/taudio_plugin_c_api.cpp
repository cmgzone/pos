#include "include/taudio/taudio_plugin_c_api.h"
#include "include/flutter_sound/flutter_sound_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "taudio_plugin.h"

namespace {

void RegisterTaudioPlugin(
    FlutterDesktopPluginRegistrarRef registrar) {
  taudio::TaudioPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

}  // namespace

void TaudioPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  RegisterTaudioPlugin(registrar);
}

void FlutterSoundPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  RegisterTaudioPlugin(registrar);
}
