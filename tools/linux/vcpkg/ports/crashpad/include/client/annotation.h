// Linux cross-build crashpad stub (tools/linux/vcpkg/ports/crashpad).
#pragma once
#include "base/strings/string_piece.h"
#include <cstddef>

namespace crashpad {
template <size_t MaxSize>
class StringAnnotation
{
public:
	constexpr explicit StringAnnotation(const char* name) : m_name(name) {}
	void Set(base::StringPiece) {}
	void Clear() {}
	const char* name() const { return m_name; }
private:
	const char* m_name;
};
} // namespace crashpad
