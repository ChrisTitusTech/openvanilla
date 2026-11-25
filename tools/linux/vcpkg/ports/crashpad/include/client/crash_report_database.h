// Linux cross-build crashpad stub (tools/linux/vcpkg/ports/crashpad).
#pragma once
#include "base/files/file_path.h"
#include "client/settings.h"
#include "util/misc/uuid.h"
#include <cstdint>
#include <ctime>
#include <memory>
#include <string>
#include <vector>

namespace crashpad {
class CrashReportDatabase
{
public:
	struct Report
	{
		UUID uuid;
		base::FilePath file_path;
		std::string id;
		time_t creation_time = 0;
		bool uploaded = false;
		time_t last_upload_attempt_time = 0;
		int upload_attempts = 0;
		bool upload_explicitly_requested = false;
		uint64_t total_size = 0;
	};

	enum OperationStatus
	{
		kNoError = 0,
		kReportNotFound,
		kFileSystemError,
		kDatabaseError,
		kBusyError,
		kCannotRequestUpload,
	};

	// Always unavailable: callers treat a null database as "crash reporting disabled".
	static std::unique_ptr<CrashReportDatabase> Initialize(const base::FilePath&) { return nullptr; }

	Settings* GetSettings() { return nullptr; }
	OperationStatus GetPendingReports(std::vector<Report>* reports) { reports->clear(); return kDatabaseError; }
	OperationStatus GetCompletedReports(std::vector<Report>* reports) { reports->clear(); return kDatabaseError; }
	OperationStatus RequestUpload(const UUID&) { return kCannotRequestUpload; }
	OperationStatus DeleteReport(const UUID&) { return kReportNotFound; }
};
} // namespace crashpad
