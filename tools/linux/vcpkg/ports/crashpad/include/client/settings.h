// Linux cross-build crashpad stub (tools/linux/vcpkg/ports/crashpad).
#pragma once
#include "util/misc/uuid.h"

namespace crashpad {
class Settings
{
public:
	bool GetClientID(UUID* client_id) { *client_id = UUID(); return false; }
	bool GetUploadsEnabled(bool* enabled) { *enabled = false; return false; }
	bool SetUploadsEnabled(bool) { return false; }
};
} // namespace crashpad
