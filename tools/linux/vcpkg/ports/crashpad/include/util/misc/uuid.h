// Linux cross-build crashpad stub (tools/linux/vcpkg/ports/crashpad).
#pragma once
#include <cstdint>
#include <cstdio>
#include <random>
#include <string>

namespace crashpad {
struct UUID
{
	uint32_t data_1 = 0;
	uint16_t data_2 = 0;
	uint16_t data_3 = 0;
	uint8_t data_4[2] = {};
	uint8_t data_5[6] = {};

	bool InitializeWithNew()
	{
		std::random_device rd;
		data_1 = rd();
		data_2 = static_cast<uint16_t>(rd());
		data_3 = static_cast<uint16_t>((rd() & 0x0fff) | 0x4000);
		uint32_t r = rd();
		data_4[0] = static_cast<uint8_t>((r & 0x3f) | 0x80);
		data_4[1] = static_cast<uint8_t>(r >> 8);
		for (auto& b : data_5)
			b = static_cast<uint8_t>(rd());
		return true;
	}

	std::string ToString() const
	{
		char buf[37];
		std::snprintf(buf, sizeof(buf), "%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
			data_1, data_2, data_3, data_4[0], data_4[1],
			data_5[0], data_5[1], data_5[2], data_5[3], data_5[4], data_5[5]);
		return buf;
	}

	bool operator==(const UUID& other) const = default;
};
} // namespace crashpad
