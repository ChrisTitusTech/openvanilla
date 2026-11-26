#!/usr/bin/env bash
# Build the pinned external EverQuest Live x64 plugins (tools/linux/README.md).
set -euo pipefail

linux="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugins=(
    MQ2AASpend MQ2AdvPath MQ2AutoAccept MQ2Camera MQ2Cast MQ2DanNet
    MQ2EQBC MQ2EasyFind MQ2Exchange MQ2GroupInfo MQ2Melee MQ2MoveUtils
    MQ2Nav MQ2PortalSetter MQ2Relocate MQ2Rez MQ2Status MQItemColor
)

export TARGETS="${TARGETS:-${plugins[*]}}"
exec "$linux/build.sh" -DMQ_BUILD_CUSTOM_PLUGINS=ON -DMQ_FORCE_VCXPROJ_CONVERSION=ON "$@"
