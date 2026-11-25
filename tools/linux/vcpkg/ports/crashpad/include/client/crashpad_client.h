// Linux cross-build crashpad stub (tools/linux/vcpkg/ports/crashpad).
#pragma once
#include "base/files/file_path.h"
#include <windows.h>
#include <map>
#include <string>
#include <vector>

namespace crashpad {
using NativeCPUContext = CONTEXT;

inline void CaptureContext(NativeCPUContext* context) { RtlCaptureContext(context); }

class CrashpadClient
{
public:
	bool StartHandler(const base::FilePath&, const base::FilePath&, const base::FilePath&,
		const std::string&, const std::map<std::string, std::string>&,
		const std::vector<std::string>&, bool, bool,
		const std::vector<base::FilePath>& = {}) { return false; }
	bool WaitForHandlerStart(unsigned int) { return false; }
	bool SetHandlerIPCPipe(const std::wstring&) { return false; }
	std::wstring GetHandlerIPCPipe() const { return {}; }
	static void DumpWithoutCrash(const CONTEXT&) {}
};
} // namespace crashpad
