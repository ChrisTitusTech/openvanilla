// Linux cross-build crashpad stub (tools/linux/vcpkg/ports/crashpad).
#pragma once
#include <string>

namespace base {
class FilePath
{
public:
	using StringType = std::wstring;
	FilePath() = default;
	explicit FilePath(const StringType& path) : m_path(path) {}
	const StringType& value() const { return m_path; }
	bool empty() const { return m_path.empty(); }
private:
	StringType m_path;
};
} // namespace base
